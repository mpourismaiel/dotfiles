;;; macros.el --- Keyboard-macro capture, library, and runner  -*- lexical-binding: t; -*-
;;; Commentary:
;; Heavy keyboard-macro integration on top of evil / vanilla kmacro:
;;
;;   * `q' (evil normal state) toggles recording via `mp/macro-toggle-record':
;;     first press starts, second press stops and stores the recording.  No
;;     register prompt (that is the one deviation from evil's default `q').
;;
;;   * Session macros: every stopped recording is pushed onto
;;     `mp/macro-session-list' (most recent first), unnamed and in-memory only.
;;
;;   * Saved macros: named recordings persisted to `mp/macro-save-file'
;;     (var/macros.el) and reloaded at startup.
;;
;;   * `mp/macro-run' / `mp/macro-save' / `mp/macro-delete' back the
;;     `SPC m k k' / `SPC m k a' / `SPC m k d' leader keys (bound in mp-keys).
;;
;;   * `mp/macro-header-label' + `mp/macro-run-most-recent-once' feed the
;;     svg-header chip (guarded there by `fboundp', like the hledger rows).
;;
;; No leader-key bindings live here; the recording `q' bind lives in mp-evil and
;; the `SPC m k' prefix in mp-keys, matching the rest of the config.
;;; Code:

(require 'cl-lib)
(require 'seq)

;;; Stores

(defvar mp/macro-session-list nil
  "Recorded session macros, most recent first.
Each element is a plist (:keys KEYS :desc DESC).  In-memory only.")

(defvar mp/macro-saved-list nil
  "Named, persisted macros.
Each element is a plist (:name NAME :keys KEYS :desc DESC).")

(defvar mp/macro-save-file
  (expand-file-name "macros.el" (or (bound-and-true-p mp/var-dir)
                                    user-emacs-directory))
  "File where named macros are persisted between sessions.")

(defvar mp/macro-session-limit 50
  "Maximum number of session macros retained.")

;;; Helpers

(defun mp/macro--describe (keys)
  "Return a readable one-line description of macro KEYS."
  (condition-case nil
      (let ((s (key-description keys)))
        (if (string-empty-p s) "(empty)" s))
    (error (format "%S" keys))))

;;; Persistence

(defun mp/macro-load ()
  "Load saved macros from `mp/macro-save-file' into `mp/macro-saved-list'."
  (when (file-exists-p mp/macro-save-file)
    (with-temp-buffer
      (insert-file-contents mp/macro-save-file)
      (condition-case err
          (let ((data (read (current-buffer))))
            (when (listp data)
              (setq mp/macro-saved-list data)))
        (error (message "mp/macro: failed reading %s: %S"
                        mp/macro-save-file err))))))

(defun mp/macro--persist ()
  "Write `mp/macro-saved-list' to `mp/macro-save-file'."
  (with-temp-file mp/macro-save-file
    (let ((print-length nil) (print-level nil))
      (insert ";;; mp saved keyboard macros -*- lexical-binding: t; -*-\n"
              ";;; Auto-generated; edit via SPC m k a / SPC m k d.\n")
      (prin1 mp/macro-saved-list (current-buffer))
      (insert "\n"))))

;;; Recording

(defun mp/macro-session-push (keys)
  "Push KEYS as a new session macro (most recent first)."
  (when (and keys (> (length keys) 0))
    (push (list :keys (copy-sequence keys)
                :desc (mp/macro--describe keys))
          mp/macro-session-list)
    (when (> (length mp/macro-session-list) mp/macro-session-limit)
      (setq mp/macro-session-list
            (seq-take mp/macro-session-list mp/macro-session-limit)))))

(defun mp/macro-toggle-record ()
  "Start recording a keyboard macro, or stop and store the current one.
Bound to `q' in evil normal state (no register prompt)."
  (interactive)
  (if defining-kbd-macro
      (progn
        (end-kbd-macro)
        (if (and last-kbd-macro (> (length last-kbd-macro) 0))
            (progn
              (mp/macro-session-push last-kbd-macro)
              (force-mode-line-update t)
              (message "Macro stored: %s" (mp/macro--describe last-kbd-macro)))
          (message "Empty macro — nothing stored")))
    (kmacro-start-macro nil)
    (message "Recording macro… press q to stop")))

;;; Selection UI

(defun mp/macro--candidates ()
  "Return (CANDS . TABLE) describing all macros for `completing-read'.
CANDS is an ordered list of display strings (session macros first, then
saved macros by name).  TABLE maps each string to a plist
\(:macro PLIST :group GROUP)."
  (let (session saved table)
    (let ((i 1))
      (dolist (m mp/macro-session-list)
        (let ((s (format "%d. %s" i (plist-get m :desc))))
          (setq session (nconc session (list s)))
          (push (cons s (list :macro m :group "")) table)
          (setq i (1+ i)))))
    (dolist (m (sort (copy-sequence mp/macro-saved-list)
                     (lambda (a b) (string< (or (plist-get a :name) "")
                                            (or (plist-get b :name) "")))))
      (let ((s (plist-get m :name)))
        (setq saved (nconc saved (list s)))
        (push (cons s (list :macro m :group "Saved")) table)))
    (cons (append session saved) table)))

(defun mp/macro--completion-table (cands table)
  "Return a completion table over CANDS grouped and ordered via TABLE."
  (lambda (string pred action)
    (if (eq action 'metadata)
        `(metadata
          (display-sort-function . identity)
          (group-function
           . ,(lambda (cand transform)
                (if transform
                    cand
                  (or (plist-get (cdr (assoc cand table)) :group) "")))))
      (complete-with-action action cands string pred))))

(defun mp/macro--read (prompt)
  "Read a macro via `completing-read' with PROMPT.
Return (MACRO GROUP CHOICE) or nil when nothing is chosen."
  (let* ((data (mp/macro--candidates))
         (cands (car data))
         (table (cdr data)))
    (unless cands (user-error "No macros available"))
    (let* ((choice (completing-read prompt
                                    (mp/macro--completion-table cands table)
                                    nil t))
           (entry (cdr (assoc choice table))))
      (when entry
        (list (plist-get entry :macro) (plist-get entry :group) choice)))))

;;; Commands (bound to SPC m k …)

(defun mp/macro-run ()
  "Select a macro and run it a given number of times (SPC m k k)."
  (interactive)
  (when-let* ((sel (mp/macro--read "Run macro: "))
              (m (nth 0 sel)))
    (let ((count (read-number "Times: " 1)))
      (execute-kbd-macro (plist-get m :keys) (max 1 count)))))

(defun mp/macro-save ()
  "Save the most recent session macro under a name (SPC m k a)."
  (interactive)
  (unless mp/macro-session-list
    (user-error "No session macro to save — record one with q first"))
  (let* ((m (car mp/macro-session-list))
         (name (string-trim (read-string "Macro name: "))))
    (when (string-empty-p name)
      (user-error "Empty macro name"))
    (setq mp/macro-saved-list
          (cl-remove name mp/macro-saved-list
                     :key (lambda (x) (plist-get x :name)) :test #'equal))
    (push (list :name name
                :keys (copy-sequence (plist-get m :keys))
                :desc (plist-get m :desc))
          mp/macro-saved-list)
    (mp/macro--persist)
    (message "Saved macro %S" name)))

(defun mp/macro-delete ()
  "Delete a macro after confirmation (SPC m k d)."
  (interactive)
  (when-let* ((sel (mp/macro--read "Delete macro: "))
              (m (nth 0 sel)))
    (let ((group (nth 1 sel))
          (choice (nth 2 sel)))
      (when (yes-or-no-p (format "Delete macro %s? " choice))
        (if (equal group "Saved")
            (progn
              (setq mp/macro-saved-list (delq m mp/macro-saved-list))
              (mp/macro--persist))
          (setq mp/macro-session-list (delq m mp/macro-session-list)))
        (force-mode-line-update t)
        (message "Deleted macro")))))

;;; svg-header integration

(defun mp/macro-most-recent ()
  "Return the most recent session macro plist, or nil."
  (car mp/macro-session-list))

(defun mp/macro-header-label ()
  "Short label for the most recent session macro, or nil.
Consumed by svg-header to show the resting-header macro chip."
  (when-let* ((m (mp/macro-most-recent)))
    (truncate-string-to-width (plist-get m :desc) 14 nil nil "…")))

(defun mp/macro-run-most-recent-once ()
  "Run the most recent session macro once (svg-header chip / any binding)."
  (interactive)
  (if-let* ((m (mp/macro-most-recent)))
      (execute-kbd-macro (plist-get m :keys) 1)
    (message "No session macro recorded yet")))

(mp/macro-load)

(provide 'macros)
;;; macros.el ends here
