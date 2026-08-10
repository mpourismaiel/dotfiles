#!/usr/bin/env python3
# emaqsbridge.py — workspace / buffer backend for emaqs, via the Emacs daemon.
#
# Workspaces are perspective.el perspectives (the vanilla successor to Doom's
# +workspace-* API), wrapped by the user's mp/workspace-* helpers.
#
#   workspaces        print JSON {"names":[…], "current":"…"}
#   buffers [WS]      print JSON [{"group":…, "items":[…]}, …] for workspace WS
#   switch NAME       switch to workspace NAME, raise + focus Emacs
#   openbuf NAME WS   show buffer NAME (switching to WS first), raise + focus
#   magit WS          magit-status at WS's project root, raise + focus
#   close WS          kill workspace WS (persp-kill, buffers included)
#   agent-action ID KEY   dispatch an emaqs agent-shell button/click into the daemon
#
# All calls talk to the running Emacs daemon with emacsclient. Buffer grouping reuses
# the user's own super-menu predicates (mp/normal-buffer-p, mp/agent-shell-buffer-p,
# mp/ghostel-buffer-p) and buffer-name-history ordering when present. Data commands
# write JSON to a temp file (path returned by emacsclient) so Unicode survives; if the
# daemon is unreachable they print empty JSON.
import sys, os, subprocess

# Lisp helpers, prepended to every eval so the script needs no separate .el file.
HELPERS = r"""
(progn
  (require 'json)
  (require 'cl-lib)
  ;; Vanilla port: Doom's +workspace-* API is gone; workspaces are now
  ;; perspective.el perspectives wrapped by the user's mp/workspace-* helpers
  ;; (see emacs/lisp/mp-workspaces.el). Prefer those, then raw persp-*, then the
  ;; old +workspace-* names as a last resort so this bridge keeps working either way.
  (defun emaqs--ws-names ()
    (cond ((fboundp 'mp/workspace-names) (or (ignore-errors (mp/workspace-names)) '()))
          ((fboundp 'persp-names) (or (ignore-errors (reverse (persp-names))) '()))
          ((fboundp '+workspace-list-names) (+workspace-list-names))
          (t '())))
  (defun emaqs--ws-current ()
    (or (cond ((fboundp 'mp/workspace-current-name) (ignore-errors (mp/workspace-current-name)))
              ((fboundp 'persp-current-name) (ignore-errors (persp-current-name)))
              ((fboundp '+workspace-current-name) (+workspace-current-name)))
        ""))
  ;; The bar SWITCHES by raw perspective name but DISPLAYS the same human label
  ;; the dashboard/super-menu show ("INDEX project" / "empty workspace - NAME"),
  ;; via mp/workspace--label. Perspective names ("main", "empty workspace - 2")
  ;; are internal and mean nothing to the user, so send both.
  (defun emaqs--ws-label (name)
    (or (and (fboundp 'mp/workspace--label) (ignore-errors (mp/workspace--label name)))
        name))
  (defun emaqs--ws-labels ()
    (mapcar #'emaqs--ws-label (emaqs--ws-names)))
  (defun emaqs-workspaces ()
    (json-encode (list (cons "names" (vconcat (emaqs--ws-names)))
                       (cons "labels" (vconcat (emaqs--ws-labels)))
                       (cons "current" (emaqs--ws-current)))))
  ;; buffers of workspace NAME ("" = current) WITHOUT switching to it.
  (defun emaqs--ws-buffers (name)
    (let ((persp (and name (not (string= name "")) (fboundp 'perspectives-hash)
                      (ignore-errors (gethash name (perspectives-hash))))))
      (cond
       ((and persp (fboundp 'persp-buffers)) (persp-buffers persp))
       ((fboundp 'persp-current-buffers) (persp-current-buffers))
       ((fboundp '+workspace-buffer-list) (+workspace-buffer-list))
       (t (buffer-list)))))
  ;; group predicates — prefer the user's own super-menu helpers, else fall back.
  (defun emaqs--normal-p (b)
    (if (fboundp 'mp/normal-buffer-p)
        (mp/normal-buffer-p b)
      (and (buffer-live-p b) (not (string-prefix-p "*" (buffer-name b))))))
  (defun emaqs--agent-p (b)
    (and (fboundp 'mp/agent-shell-buffer-p) (mp/agent-shell-buffer-p b)))
  (defun emaqs--ghostel-p (b)
    (and (fboundp 'mp/ghostel-buffer-p) (mp/ghostel-buffer-p b)))
  ;; sort buffer NAMES by their position in buffer-name-history (super-menu order).
  (defun emaqs--sort-hist (names)
    (let ((hist (and (boundp 'buffer-name-history) buffer-name-history)))
      (sort (copy-sequence names)
            (lambda (a b)
              (< (or (cl-position a hist :test #'equal) most-positive-fixnum)
                 (or (cl-position b hist :test #'equal) most-positive-fixnum))))))
  (defun emaqs--names (bufs pred)
    (emaqs--sort-hist
     (delq nil (mapcar (lambda (b) (and (funcall pred b) (buffer-name b))) bufs))))
  (defun emaqs-buffers (name)
    (let* ((bufs (emaqs--ws-buffers name))
           (buffers (emaqs--names bufs #'emaqs--normal-p))
           (agents  (emaqs--names bufs #'emaqs--agent-p))
           (ghostel (emaqs--names bufs #'emaqs--ghostel-p))
           (groups '()))
      ;; pushed reverse so the JSON order is Buffers, Agent Shell, Ghostel.
      (when ghostel
        (push (list (cons "group" "Ghostel") (cons "items" (vconcat ghostel))) groups))
      (when agents
        (push (list (cons "group" "Agent Shell") (cons "items" (vconcat agents))) groups))
      (when buffers
        (push (list (cons "group" "Buffers") (cons "items" (vconcat buffers))) groups))
      (json-encode (vconcat groups))))
  ;; raise + focus an Emacs frame, mirrored from the pill's pill-open. Prefer the
  ;; frame this eval is already selected in — with perspective.el the perspective
  ;; set is FRAME-LOCAL, and emacsclient -e runs in the user's real GUI frame; a
  ;; blind "first visible frame" could grab a stray frame (e.g. an "F1" that only
  ;; has the default "main"), which is a different workspace universe entirely.
  (defun emaqs--raise ()
    (let ((f (if (frame-visible-p (selected-frame))
                 (selected-frame)
               (or (seq-find #'frame-visible-p (frame-list)) (car (frame-list))))))
      (when (frame-live-p f)
        (make-frame-visible f)
        (raise-frame f)
        (select-frame-set-input-focus f))
      f))
  (defun emaqs--goto-ws (name)
    (when (and name (not (string= name "")) (not (string= name (emaqs--ws-current))))
      (cond ((fboundp 'persp-switch) (ignore-errors (persp-switch name)))
            ((fboundp '+workspace-switch) (ignore-errors (+workspace-switch name))))))
  ;; The *dashboard* is a SINGLE shared buffer that only re-renders on demand; a
  ;; bare persp-switch restores a window layout that may still show the dashboard
  ;; as rendered for the PREVIOUS workspace. Re-render it in place after a switch
  ;; (the user's own n/p keys go through mp/dashboard-refresh; emaqs must too).
  (defun emaqs--refresh-dashboard ()
    (when (and (fboundp 'mp/dashboard-refresh)
               (boundp 'mp/dashboard-buffer-name)
               (get-buffer-window mp/dashboard-buffer-name t))
      (ignore-errors (mp/dashboard-refresh))))
  (defun emaqs-switch (name)
    (emaqs--goto-ws name)
    (emaqs--refresh-dashboard)
    (emaqs--raise)
    nil)
  (defun emaqs-open-buffer (name wsname)
    (emaqs--goto-ws wsname)
    (let ((buf (get-buffer name)))
      (emaqs--raise)
      (when (buffer-live-p buf)
        (with-selected-frame (selected-frame) (switch-to-buffer buf))))
    nil)
  (defun emaqs--project-root (name)
    ;; Prefer the workspace's assigned/inferred root (mp/workspace--project-root);
    ;; "" means the current workspace. Fall back to scanning its file buffers.
    (let ((wsname (if (or (null name) (string= name "")) (emaqs--ws-current) name)))
      (or (and (fboundp 'mp/workspace--project-root)
               (ignore-errors (mp/workspace--project-root wsname)))
          (seq-some (lambda (b)
                      (and (buffer-live-p b)
                           (with-current-buffer b
                             (when (buffer-file-name)
                               (or (and (fboundp 'projectile-project-root)
                                        (ignore-errors (projectile-project-root)))
                                   (and (fboundp 'vc-root-dir)
                                        (ignore-errors (vc-root-dir)))
                                   (file-name-directory (buffer-file-name)))))))
                    (emaqs--ws-buffers name)))))
  (defun emaqs-magit (name)
    (let ((root (emaqs--project-root name)))
      (emaqs--goto-ws name)
      (emaqs--raise)
      (cond
       ((and root (fboundp 'magit-status))
        (with-selected-frame (selected-frame) (magit-status root)))
       ((fboundp 'magit-status)
        (with-selected-frame (selected-frame) (call-interactively #'magit-status)))))
    nil)
  (defun emaqs-close (name)
    (when (and name (not (string= name "")))
      (cond ((fboundp 'mp/workspace-delete) (ignore-errors (mp/workspace-delete name)))
            ((fboundp 'persp-kill) (ignore-errors (persp-kill name)))
            ((fboundp '+workspace/kill) (ignore-errors (+workspace/kill name)))
            ((fboundp '+workspace-delete) (ignore-errors (+workspace-delete name)))))
    nil))
"""


def _esc(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _emacs(form, wait=True):
    try:
        r = subprocess.run(
            ["emacsclient", "-e", form],
            capture_output=True,
            timeout=(12 if wait else 6),
        )
    except Exception:
        return None
    if r.returncode != 0:
        return None
    return r.stdout.decode("utf-8", "replace").strip()


def _eval_to_file(call, empty="[]"):
    # Emacs writes the JSON to a temp file and returns its (quoted) path; we read and
    # delete it. Keeps Unicode intact vs. parsing Lisp string syntax.
    form = (
        "(progn %s (let ((f (make-temp-file \"emaqs-\"))) "
        "(with-temp-file f (insert %s)) f))" % (HELPERS, call)
    )
    out = _emacs(form)
    if not out:
        return empty
    path = out.strip().strip('"')
    if not path or not os.path.exists(path):
        return empty
    try:
        with open(path, encoding="utf-8") as fh:
            data = fh.read()
    except OSError:
        return empty
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass
    return data or empty


def main():
    argv = sys.argv
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "workspaces":
        sys.stdout.write(_eval_to_file("(emaqs-workspaces)", empty="{}"))
    elif cmd == "buffers":
        ws = argv[2] if len(argv) > 2 else ""
        sys.stdout.write(_eval_to_file("(emaqs-buffers %s)" % _esc(ws)))
    elif cmd == "switch" and len(argv) > 2:
        _emacs("(progn %s (emaqs-switch %s))" % (HELPERS, _esc(argv[2])), wait=False)
    elif cmd == "openbuf" and len(argv) > 3:
        _emacs("(progn %s (emaqs-open-buffer %s %s))"
               % (HELPERS, _esc(argv[2]), _esc(argv[3])), wait=False)
    elif cmd == "magit":
        ws = argv[2] if len(argv) > 2 else ""
        _emacs("(progn %s (emaqs-magit %s))" % (HELPERS, _esc(ws)), wait=False)
    elif cmd == "close":
        ws = argv[2] if len(argv) > 2 else ""
        _emacs("(progn %s (emaqs-close %s))" % (HELPERS, _esc(ws)), wait=False)
    elif cmd == "agent-action" and len(argv) > 3:
        # dispatch an emaqs notification button/click back into the daemon; the
        # responder closure lives in the user's config, so no HELPERS prelude.
        _emacs("(mp/agent-shell-emaqs-action %s %s)" % (_esc(argv[2]), _esc(argv[3])),
               wait=False)
    else:
        sys.stdout.write("{}")


if __name__ == "__main__":
    main()
