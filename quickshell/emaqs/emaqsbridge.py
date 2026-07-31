#!/usr/bin/env python3
# emaqsbridge.py — Doom-workspace / buffer backend for emaqs, via the Emacs daemon.
#
#   workspaces        print JSON {"names":[…], "current":"…"}
#   buffers [WS]      print JSON [{"group":…, "items":[…]}, …] for workspace WS
#   switch NAME       switch to workspace NAME, raise + focus Emacs
#   openbuf NAME WS   show buffer NAME (switching to WS first), raise + focus
#   magit WS          magit-status at WS's project root, raise + focus
#   close WS          kill workspace WS (+workspace/kill, buffers included)
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
  (defun emaqs--ws-names ()
    (if (fboundp '+workspace-list-names) (+workspace-list-names) '()))
  (defun emaqs--ws-current ()
    (if (fboundp '+workspace-current-name) (+workspace-current-name) ""))
  (defun emaqs-workspaces ()
    (json-encode (list (cons "names" (vconcat (emaqs--ws-names)))
                       (cons "current" (emaqs--ws-current)))))
  ;; buffers of workspace NAME ("" = current) WITHOUT switching to it.
  (defun emaqs--ws-buffers (name)
    (let ((persp (and name (not (string= name "")) (fboundp '+workspace-get)
                      (ignore-errors (+workspace-get name t)))))
      (cond
       ((and persp (fboundp '+workspace-buffer-list)) (+workspace-buffer-list persp))
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
  ;; raise + focus an Emacs frame, mirrored from the pill's pill-open.
  (defun emaqs--raise ()
    (let ((f (or (seq-find #'frame-visible-p (frame-list)) (car (frame-list)))))
      (when (frame-live-p f)
        (make-frame-visible f)
        (raise-frame f)
        (select-frame-set-input-focus f))
      f))
  (defun emaqs--goto-ws (name)
    (when (and name (not (string= name "")) (fboundp '+workspace-switch)
               (not (string= name (emaqs--ws-current))))
      (ignore-errors (+workspace-switch name))))
  (defun emaqs-switch (name)
    (emaqs--goto-ws name)
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
    (let ((bufs (emaqs--ws-buffers name)))
      (seq-some (lambda (b)
                  (with-current-buffer b
                    (when (buffer-file-name)
                      (or (and (fboundp 'projectile-project-root)
                               (ignore-errors (projectile-project-root)))
                          (and (fboundp 'vc-root-dir)
                               (ignore-errors (vc-root-dir)))
                          (file-name-directory (buffer-file-name))))))
                bufs)))
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
      (cond ((fboundp '+workspace/kill) (ignore-errors (+workspace/kill name)))
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
