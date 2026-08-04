#!/usr/bin/env python3
# orgbridge.py — Org-agenda backend for the pill's calendar, via the Emacs daemon.
#
#   day YYYY-MM-DD    print JSON [{text, todo, type, priority, done, dated, file, pos}, …]
#   range A B         print JSON ["YYYY-MM-DD", …] of dates in [A,B] with dated entries
#   deadlines [N]     print JSON [{…, delta, date}, …] undone DEADLINE todos due
#                     within N days ahead (default 30); overdue always included,
#                     sorted most-overdue-first (delta = deadline-day - today)
#   open YYYY-MM-DD   open the Org agenda in Emacs (reuse an existing frame)
#   goto FILE POS     open FILE at headline POS in a visible frame, reveal subtree
#   toggle FILE POS   flip the TODO/DONE state of the headline at FILE:POS, save
#
# All calls talk to the running Emacs daemon with emacsclient, so the user's real
# org-agenda-files / TODO keywords are used. day/range write their JSON to a temp
# file (path returned by emacsclient) so Unicode survives; best-effort — if the
# daemon is unreachable the data commands print "[]".
import sys, os, subprocess

# Lisp helpers, prepended to every eval so the script needs no separate .el file.
HELPERS = r"""
(progn
  (require 'org)
  (require 'org-agenda)
  (require 'json)
  (defun pill--parse (s)                       ; "YYYY-MM-DD" -> (month day year)
    (let ((p (mapcar #'string-to-number (split-string s "-"))))
      (list (nth 1 p) (nth 2 p) (nth 0 p))))
  (defun pill--day-entries (greg)              ; greg = (month day year)
    ;; Bind org-deadline-warning-days to 0 so a DEADLINE lands ONLY on its due
    ;; date in the calendar grid. With the normal warning window (default 14)
    ;; org-agenda-get-day-entries returns a future deadline on every day inside
    ;; the window too — as an "In N d.:" reminder — which, once the pill strips
    ;; the agenda prefix, looks like the same todo duplicated on today AND its
    ;; due date. Past-days defaults are left untouched, so genuinely overdue
    ;; deadlines/scheduled items still carry forward onto today.
    ;; skip-*-if-done bound nil so DONE dated items are still returned — the
    ;; pill wants them (struck through) on their own date, not hidden.
    (let ((org-deadline-warning-days 0)
          (org-agenda-skip-deadline-if-done nil)
          (org-agenda-skip-scheduled-if-done nil)
          (org-agenda-skip-timestamp-if-done nil)
          items)
      (dolist (f (org-agenda-files))
        (dolist (e (ignore-errors
                     (org-agenda-get-day-entries
                      f greg :scheduled :deadline :timestamp)))
          (push e items)))
      (nreverse items)))
  ;; --- one entry, read from the source headline (point must be on it) -------
  ;; Pulls a clean heading (no todo keyword / no [#A] cookie / no tags), the
  ;; priority letter, the done flag, and a file+pos handle so the pill can mark
  ;; it done later. Emacs's agenda formatting is skipped entirely — the pill
  ;; renders these fields in its own style.
  (defun pill--item ()
    (let* ((comps (org-heading-components))
           (todo (or (nth 2 comps) ""))
           (prisym (nth 3 comps))
           (pri (if prisym (char-to-string prisym) ""))
           (heading (org-trim (or (nth 4 comps) "")))
           (done (and (org-get-todo-state)
                      (member (org-get-todo-state) org-done-keywords) t)))
      (list (cons "text" (substring-no-properties heading))
            (cons "todo" (substring-no-properties todo))
            (cons "priority" pri)
            (cons "done" (if done t :json-false))
            (cons "file" (or (buffer-file-name (buffer-base-buffer)) ""))
            (cons "pos" (point)))))
  (defun pill--dated-item (e)                  ; agenda entry -> item (dated t)
    (let ((m (or (get-text-property 0 'org-hd-marker e)
                 (get-text-property 0 'org-marker e))))
      (if m
          (org-with-point-at m
            (append (pill--item)
                    (list (cons "type" (format "%s" (or (get-text-property 0 'type e) "")))
                          (cons "dated" t))))
        (list (cons "text" (org-trim (substring-no-properties e)))
              (cons "todo" (or (get-text-property 0 'todo-state e) ""))
              (cons "priority" "") (cons "done" :json-false)
              (cons "file" "") (cons "pos" 0)
              (cons "type" (format "%s" (or (get-text-property 0 'type e) "")))
              (cons "dated" t)))))
  ;; DONE-ness of one agenda-day entry `e' (marker -> todo state).
  (defun pill--entry-done-p (e)
    (let ((m (or (get-text-property 0 'org-hd-marker e)
                 (get-text-property 0 'org-marker e))))
      (and m (org-with-point-at m
               (let ((s (org-get-todo-state)))
                 (and s (member s org-done-keywords) t))))))
  ;; One scan of all agenda headings for the UNDATED items the dated agenda
  ;; query doesn't cover (dated items — active or done — come from
  ;; pill--day-entries and show on their own date, so they are excluded here to
  ;; avoid duplicates):
  ;;   • active undated TODOs (no SCHEDULED/DEADLINE) — the persistent to-do
  ;;     list, shown on every day;
  ;;   • undated DONE headings — shown on their CLOSED day (log-mode style), so
  ;;     a finished note-to-self still surfaces once, on the day it was closed.
  (defun pill--extra-items (datestr)
    (delq nil
          (ignore-errors
            (org-map-entries
             (lambda ()
               (let* ((todo (org-get-todo-state))
                      (done (and todo (member todo org-done-keywords)))
                      (dated (or (org-entry-get nil "SCHEDULED")
                                 (org-entry-get nil "DEADLINE")))
                      (closed (org-entry-get nil "CLOSED")))
                 (cond
                  ((and todo (not done) (not dated))
                   (append (pill--item)
                           (list (cons "type" "") (cons "dated" :json-false))))
                  ((and done (not dated) closed
                        (string-match-p (regexp-quote datestr) closed))
                   (append (pill--item)
                           (list (cons "type" "") (cons "dated" :json-false)))))))
             t 'agenda))))
  (defun pill-day (datestr)
    (json-encode
     (vconcat
      (append
       ;; dated items on this day — active AND done. Done ones stay on their own
       ;; deadline/scheduled date (struck through), not moved elsewhere.
       (mapcar #'pill--dated-item
               (pill--day-entries (pill--parse datestr)))
       (pill--extra-items datestr)))))
  ;; Each date with dated entries lights a dot; `done' is t when EVERY dated
  ;; entry on that date is finished (all todos for the day complete) — the pill
  ;; paints those dots in the success colour.
  (defun pill-range (startstr endstr)
    (let* ((sa (calendar-absolute-from-gregorian (pill--parse startstr)))
           (ea (calendar-absolute-from-gregorian (pill--parse endstr)))
           (a sa) (out '()))
      (while (<= a ea)
        (let* ((g (calendar-gregorian-from-absolute a))
               (entries (pill--day-entries g)))   ; dots track dated entries only
          (when entries
            (push (list (cons "date" (format "%04d-%02d-%02d"
                                             (nth 2 g) (nth 0 g) (nth 1 g)))
                        (cons "done" (if (seq-every-p #'pill--entry-done-p entries)
                                         t :json-false)))
                  out)))
        (setq a (1+ a)))
      (json-encode (vconcat (nreverse out)))))
  ;; Toggle the TODO/DONE state of the headline at FILE:POS and save. POS is a
  ;; fresh buffer position from the same session, so it lands on the heading;
  ;; org-todo re-anchors to the headline before flipping the keyword.
  (defun pill-toggle (file pos)
    (when (and file (not (string= file "")) (file-exists-p file))
      (with-current-buffer (find-file-noselect file)
        (org-with-wide-buffer
         (goto-char (min (max pos (point-min)) (point-max)))
         (when (ignore-errors (org-back-to-heading t) t)
           ;; force timestamp logging (never an interactive note prompt, which
           ;; would hang the emacsclient call in the daemon)
           (let ((org-log-done 'time))
             (if (member (org-get-todo-state) org-done-keywords)
                 (org-todo "TODO")
               (org-todo 'done)))
           (save-buffer)))))
    nil)
  (defun pill--iso-from-abs (abs)                ; day number -> "YYYY-MM-DD"
    (let ((g (calendar-gregorian-from-absolute abs)))
      (format "%04d-%02d-%02d" (nth 2 g) (nth 0 g) (nth 1 g))))
  ;; All undone TODOs that carry a DEADLINE, as flat items sorted by how many
  ;; days away the deadline is (most overdue first). `delta' is (deadline-day -
  ;; today): negative = overdue ("late"), 0 = due today, positive = ahead. Only
  ;; items due at most AHEAD days out are returned; every overdue item is kept.
  ;; `date' is the deadline's own ISO date so the pill can label it (weekday +
  ;; day). Reuses pill--item for the clean heading + file/pos handle (so the
  ;; pill can tick it done or jump to it), exactly like the day list.
  (defun pill-deadlines (ahead)
    (let* ((today (calendar-absolute-from-gregorian (calendar-current-date)))
           (out '()))
      (ignore-errors
        (org-map-entries
         (lambda ()
           (let* ((todo (org-get-todo-state))
                  (done (and todo (member todo org-done-keywords)))
                  (dl (org-entry-get nil "DEADLINE")))
             (when (and todo (not done) dl)
               (let* ((abs (ignore-errors (org-time-string-to-absolute dl)))
                      (delta (and abs (- abs today))))
                 (when (and delta (<= delta ahead))
                   (push (append (pill--item)
                                 (list (cons "delta" delta)
                                       (cons "date" (pill--iso-from-abs abs))))
                         out))))))
         t 'agenda))
      (setq out (sort out (lambda (a b) (< (cdr (assoc "delta" a))
                                           (cdr (assoc "delta" b))))))
      (json-encode (vconcat out))))
  ;; Open FILE at buffer position POS (a headline) in a visible Emacs frame and
  ;; reveal the subtree — the pill's "open this deadline" action.
  (defun pill-goto (file pos)
    (when (and file (not (string= file "")) (file-exists-p file))
      (let ((f (or (seq-find #'frame-visible-p (frame-list))
                   (car (frame-list))
                   (make-frame '((name . "pill-agenda"))))))
        (when (frame-live-p f)
          (make-frame-visible f)
          (raise-frame f)
          (select-frame-set-input-focus f)
          (with-selected-frame f
            (find-file file)
            (goto-char (min (max pos (point-min)) (point-max)))
            (ignore-errors (org-back-to-heading t))
            (ignore-errors (org-fold-show-entry))
            (ignore-errors (org-fold-show-children))))))
    nil)
  (defun pill-open ()
    (let ((f (or (seq-find #'frame-visible-p (frame-list))
                 (car (frame-list))
                 (make-frame '((name . "pill-agenda"))))))
      (when (frame-live-p f)
        (make-frame-visible f)
        (raise-frame f)
        (select-frame-set-input-focus f)
        (with-selected-frame f
          (org-agenda nil "a")))
      nil)))
"""


# Optional `--dir DIR` (leading): when set, org-agenda-files is rebound to every
# .org file under DIR for the query, so the pill isn't tied to Emacs's own
# org-agenda-files. Set in main() before any command runs.
AGENDA_DIR = ""


def _esc(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _wrap(call):
    """Wrap a HELPERS call so org-agenda-files points at AGENDA_DIR's .org files.
    A bad/empty dir yields nil (→ empty results), never an error."""
    if not AGENDA_DIR:
        return call
    return (
        "(let ((org-agenda-files "
        "(ignore-errors (directory-files-recursively %s \"\\\\.org\\\\'\")))) %s)"
        % (_esc(AGENDA_DIR), call)
    )


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


def _eval_to_file(call):
    # Emacs writes the JSON to a temp file and returns its (quoted) path; we read
    # and delete it. Keeps Unicode headings intact vs. parsing Lisp string syntax.
    form = (
        '(progn %s (let ((f (make-temp-file "pill-agenda-"))) '
        "(with-temp-file f (insert %s)) f))" % (HELPERS, call)
    )
    out = _emacs(form)
    if not out:
        return "[]"
    path = out.strip().strip('"')
    if not path or not os.path.exists(path):
        return "[]"
    try:
        with open(path, encoding="utf-8") as fh:
            data = fh.read()
    except OSError:
        return "[]"
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass
    return data or "[]"


def main():
    global AGENDA_DIR
    argv = sys.argv[1:]
    # optional leading `--dir DIR` overrides Emacs's org-agenda-files
    if len(argv) >= 2 and argv[0] == "--dir":
        AGENDA_DIR = os.path.expanduser(argv[1]) if argv[1] else ""
        argv = argv[2:]
    cmd = argv[0] if argv else ""
    if cmd == "day" and len(argv) > 1:
        sys.stdout.write(_eval_to_file(_wrap("(pill-day %s)" % _esc(argv[1]))))
    elif cmd == "range" and len(argv) > 2:
        sys.stdout.write(
            _eval_to_file(_wrap("(pill-range %s %s)" % (_esc(argv[1]), _esc(argv[2]))))
        )
    elif cmd == "toggle" and len(argv) > 2:
        # flip a headline's TODO/DONE state; POS is a plain integer buffer pos
        _emacs("(progn %s (pill-toggle %s %s))" % (HELPERS, _esc(argv[1]), argv[2]))
        sys.stdout.write("[]")
    elif cmd == "deadlines":
        # all undone DEADLINE todos within AHEAD days (default 30); overdue always
        try:
            ahead = int(argv[1]) if len(argv) > 1 else 30
        except ValueError:
            ahead = 30
        sys.stdout.write(_eval_to_file(_wrap("(pill-deadlines %d)" % ahead)))
    elif cmd == "goto" and len(argv) > 2:
        # open FILE at headline POS in a visible frame (fire-and-forget)
        _emacs(
            "(progn %s (pill-goto %s %s))" % (HELPERS, _esc(argv[1]), argv[2]),
            wait=False,
        )
        sys.stdout.write("[]")
    elif cmd == "open":
        _emacs("(progn %s %s)" % (HELPERS, _wrap("(pill-open)")), wait=False)
    else:
        sys.stdout.write("[]")


if __name__ == "__main__":
    main()
