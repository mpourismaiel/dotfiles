;;; teamwork.el --- Timesheet editing from an org buffer -*- lexical-binding: t; -*-
;;
;;; Commentary:
;;
;; Pull your Teamwork projects/tasklists/tasks + time logs into an editable org
;; buffer, edit freely, then submit a reviewed diff. All API work is done by the
;; timesheet.py sidecar next to this file; credentials live in the system keyring
;; (see teamwork-setup.sh).
;;
;; Commands:
;;   M-x teamwork-timesheet        pull the previous month (C-u = prompt dates)
;;   M-x teamwork-management       edit the project structure (no time filter) + labels
;;   M-x teamwork-comments         open comments of the task under point (edit/add/delete)
;;   M-x teamwork-filter           pick which projects appear (stored per account)
;;   M-x teamwork-submit           review the diff, then apply on confirm
;;   M-x teamwork-refresh          re-fetch the current buffer's data
;;   M-x teamwork-account-add      add a Teamwork account (name, site, API key)
;;   M-x teamwork-account-view     list the configured accounts
;;   M-x teamwork-account-delete   remove an account from the keyring
;;
;; Several accounts can be configured; when more than one exists the pull
;; commands ask which to use and record it in a #+TEAMWORK_ACCOUNT header.  Each
;; account keeps its own project filter (teamwork-filter), so switching accounts
;; never resets it.
;;
;; Every buffer loads cached data instantly (a banner marks it STALE) then
;; refreshes in the background; the buffer is replaced when fresh data arrives,
;; and submit is refused while stale/errored (the diff would be against old data).
;;
;; Every editable buffer submits with C-c C-c (preview split + echo-line
;; confirmation + live per-action progress) and previews pending changes in a
;; side window with C-c C-l.
;; In the timesheet buffer:
;;   C-c C-c   submit     C-c C-k   close       C-c C-r   refresh
;;   C-c C-d   set range  C-c C-l   live log + changes preview   C-c C-o   task comments
;;   C-c C-p   set a task property (tags/due/priority/assignee) with completion
;; In the management buffer:
;;   C-c C-c submit  C-c C-l changes preview  C-c C-o comments  C-c C-f filter
;;   C-c C-p set property (tags/due/priority/assignee w/ value completion)  C-c C-r refresh
;; In a comments buffer:
;;   C-c C-c submit  C-c C-l changes preview  C-c C-k close  C-c C-r refresh
;;
;; NOTE (vanilla port): this package defines no global/leader keybindings — the
;; Doom config never bound any SPC-leader keys for it either; entry points are
;; the M-x commands above.  Add any leader binds in mp-keys.el, not here.  The
;; mode-local C-c keys above live on the package's own minor-mode maps and are
;; kept as-is.
;;
;;; Code:

(require 'org)
(require 'json)

(defvar teamwork-dir
  (file-name-directory (or load-file-name buffer-file-name default-directory))
  "Directory holding timesheet.py (this file's directory).")

(defvar teamwork-script (expand-file-name "timesheet.py" teamwork-dir)
  "Path to the timesheet.py sidecar.")

(defvar teamwork-python "python3"
  "Python interpreter used to run the sidecar.")

(defvar teamwork-buffer "teamwork-timesheet"
  "Name of the timesheet buffer.  No earmuffs so buffer switchers don't hide it.")

(defvar teamwork-preview-buffer "*teamwork-submit*"
  "Name of the submit-preview / progress buffer.")

(defvar teamwork-logs-buffer "*teamwork-logs*"
  "Name of the live chronological log-list side buffer.")

(defvar teamwork-changes-buffer "*teamwork-changes*"
  "Name of the live pending-changes preview side buffer (management/comments).")

;; Icons for the submit preview (unicode by default; set to nerd-font glyphs if
;; you like).  One per node kind.
(defvar teamwork-icon-tasklist "≣" "Icon for task-list actions.")
(defvar teamwork-icon-task "◆" "Icon for task actions.")
(defvar teamwork-icon-log "◷" "Icon for time-log actions.")

(defface teamwork-new-face '((t :inherit success))
  "Face for create/new actions (green).")
(defface teamwork-edit-face '((t :foreground "#4fa6ff"))
  "Face for update/edit actions (blue).")
(defface teamwork-delete-face '((t :inherit error))
  "Face for delete actions (red).")

;; --------------------------------------------------------------------------- ;;
;; Accounts — several Teamwork logins, told apart by name (one keyring item each)
;; --------------------------------------------------------------------------- ;;
(defun teamwork--list-accounts ()
  "Return the configured accounts (list of alists) via the sidecar, or nil.
Never signals: a locked keyring / missing sidecar just yields no accounts."
  (condition-case _err
      (teamwork--run-json "accounts")
    (error nil)))

(defun teamwork--account-names ()
  "Return the list of configured account names (strings)."
  (delq nil (mapcar (lambda (a) (alist-get 'account a)) (teamwork--list-accounts))))

(defun teamwork--choose-account (&optional prompt)
  "Return the account name to use for a pull.
Nil when none are configured (the sidecar then guides you to set one up); the
sole name when only one exists; otherwise prompt with completion using PROMPT."
  (let ((names (teamwork--account-names)))
    (cond ((null names) nil)
          ((null (cdr names)) (car names))
          (t (completing-read (or prompt "Teamwork account: ") names nil t)))))

(defun teamwork--buffer-account (&optional buffer)
  "Return BUFFER's #+TEAMWORK_ACCOUNT header value, or nil (default: the
timesheet buffer).  So submit targets the same account the buffer was pulled
from."
  (let ((buf (or buffer (get-buffer teamwork-buffer))))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (save-excursion
          (goto-char (point-min))
          (when (re-search-forward "^#\\+TEAMWORK_ACCOUNT:[ \t]*\\(.+?\\)[ \t]*$" nil t)
            (match-string-no-properties 1)))))))

;; --------------------------------------------------------------------------- ;;
;; Minor mode / keymap for the timesheet buffer
;; --------------------------------------------------------------------------- ;;
(defvar teamwork-timesheet-mode-map
  (let ((m (make-sparse-keymap)))
    (define-key m (kbd "C-c C-c") #'teamwork-submit)
    (define-key m (kbd "C-c C-k") #'teamwork-quit)
    (define-key m (kbd "C-c C-d") #'teamwork-set-range)
    (define-key m (kbd "C-c C-l") #'teamwork-log-preview)
    (define-key m (kbd "C-c C-r") #'teamwork-refresh)
    (define-key m (kbd "C-c C-o") #'teamwork-comments)
    (define-key m (kbd "C-c C-p") #'teamwork-set-property)
    m)
  "Keymap active in the timesheet buffer.")

(define-minor-mode teamwork-timesheet-mode
  "Minor mode for the Teamwork timesheet buffer."
  :lighter " TW"
  :keymap teamwork-timesheet-mode-map)

(defvar teamwork-management-buffer "teamwork-management"
  "Name of the management buffer (project structure, no time filter).")

(defvar teamwork-management-mode-map
  (let ((m (make-sparse-keymap)))
    (define-key m (kbd "C-c C-c") #'teamwork-submit)
    (define-key m (kbd "C-c C-k") #'teamwork-quit)
    (define-key m (kbd "C-c C-r") #'teamwork-refresh)
    (define-key m (kbd "C-c C-l") #'teamwork-changes-preview)
    (define-key m (kbd "C-c C-o") #'teamwork-comments)
    (define-key m (kbd "C-c C-f") #'teamwork-filter)
    (define-key m (kbd "C-c C-p") #'teamwork-set-property)
    m)
  "Keymap active in the management buffer.")

(define-minor-mode teamwork-management-mode
  "Minor mode for the Teamwork management buffer."
  :lighter " TWm"
  :keymap teamwork-management-mode-map)

(defvar teamwork-comments-mode-map
  (let ((m (make-sparse-keymap)))
    (define-key m (kbd "C-c C-c") #'teamwork-submit)
    (define-key m (kbd "C-c C-k") #'teamwork-quit)
    (define-key m (kbd "C-c C-r") #'teamwork-refresh)
    (define-key m (kbd "C-c C-l") #'teamwork-changes-preview)
    m)
  "Keymap active in a comments buffer.")

(define-minor-mode teamwork-comments-mode
  "Minor mode for a Teamwork task-comments buffer."
  :lighter " TWc"
  :keymap teamwork-comments-mode-map)

(defun teamwork--enable-timesheet-mode () (teamwork-timesheet-mode 1))
(defun teamwork--enable-management-mode () (teamwork-management-mode 1))
(defun teamwork--enable-comments-mode () (teamwork-comments-mode 1))

;; --------------------------------------------------------------------------- ;;
;; Cached-first, background-refresh loading with a data-freshness banner
;;
;; Every teamwork buffer (timesheet / management / comments) is filled from a
;; local cache instantly (marked STALE), then a fresh copy is fetched in the
;; background and swapped in (FRESH).  A banner in the header-line tells you the
;; state; while stale/errored, submit refuses (its diff would be against data
;; that is about to be — or already has been — replaced).
;;
;; The per-buffer state below is `permanent-local' so it survives the `org-mode'
;; call inside `teamwork--fill-buffer' (which otherwise wipes local variables).
;; --------------------------------------------------------------------------- ;;
(defvar-local teamwork--kind nil "This buffer's kind: \"timesheet\"|\"manage\"|\"comments\".")
(defvar-local teamwork--key nil "Cache key: range \"FROM_TO\" / \"manage\" / task id.")
(defvar-local teamwork--account nil "Account this buffer was pulled from.")
(defvar-local teamwork--fresh-args nil "Sidecar argv (sans --account/--out/--prev) for a live fetch.")
(defvar-local teamwork--submit-cmd nil "Sidecar subcommand submit uses (\"submit\"|\"comments-submit\").")
(defvar-local teamwork--mode-fn nil "Function enabling this buffer's teamwork minor mode.")
(defvar-local teamwork--use-prev nil "Whether to pass the old buffer as --prev on refresh.")
(defvar-local teamwork--data-state nil "One of nil, `stale', `fresh', `error'.")
(defvar-local teamwork--return-to nil "Buffer to switch back to when this one is closed.")
(dolist (v '(teamwork--kind teamwork--key teamwork--account teamwork--fresh-args
             teamwork--submit-cmd teamwork--mode-fn teamwork--use-prev teamwork--data-state
             teamwork--return-to))
  (put v 'permanent-local t))

(defun teamwork-quit ()
  "Close this teamwork buffer (and any preview / log / changes windows).
If the buffer was opened over another teamwork buffer (e.g. comments opened from
the management buffer), switch back to that buffer instead of leaving whatever
Emacs happens to surface."
  (interactive)
  (teamwork--stop-log-timer)
  (let ((back (and (buffer-live-p teamwork--return-to) teamwork--return-to)))
    (dolist (name (list teamwork-preview-buffer teamwork-logs-buffer teamwork-changes-buffer))
      (when-let ((w (get-buffer-window name))) (delete-window w))
      (when (get-buffer name) (kill-buffer name)))
    (kill-buffer (current-buffer))
    (when back (switch-to-buffer back))))

(defun teamwork--banner (state &optional msg)
  "Header-line string for data STATE, or nil for none."
  (pcase state
    ('stale
     (propertize
      " ⟳ Showing existing data — refreshing in the background.  This buffer will be REPLACED when fresh data arrives; edits made now are discarded. "
      'face '(:background "#3a2f00" :foreground "#ffd479" :weight bold)))
    ('error
     (propertize
      (concat " ⚠ Refresh FAILED — this data is not current, so submit is disabled (edits would not be sent)."
              (if (and msg (not (string-empty-p msg)))
                  (format "  [%s] " (car (split-string msg "\n"))) " "))
      'face '(:background "#3a0000" :foreground "#ff9a9a" :weight bold)))
    (_ nil)))

(defun teamwork--set-state (state &optional msg)
  "Set the current buffer's data STATE and update its banner."
  (setq teamwork--data-state state)
  (setq header-line-format (teamwork--banner state msg))
  (force-mode-line-update))

(defun teamwork--cached (kind key account)
  "Return cached org text for KIND/KEY/ACCOUNT from the sidecar, or nil."
  (with-temp-buffer
    (let ((code (apply #'call-process teamwork-python nil t nil
                       teamwork-script "cached" "--kind" kind "--key" key
                       (when account (list "--account" account)))))
      (when (zerop code) (buffer-string)))))

(defun teamwork--snapshot-prev (buffer)
  "Write BUFFER to a temp file if it looks like a teamwork buffer; return the
path or nil.  Passed to pull/manage as --prev so a deleted project heading
updates the hidden-project prefs."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (save-excursion (goto-char (point-min))
                            (re-search-forward "^#\\+TEAMWORK\\(_MANAGE\\)?:" nil t))
        (let ((f (make-temp-file "teamwork-prev" nil ".org")))
          (write-region (point-min) (point-max) f nil 'silent)
          f)))))

(defun teamwork--fill-from-string (buffer text mode-fn)
  "Fill BUFFER with TEXT via a scratch buffer, enabling MODE-FN."
  (let ((ob (generate-new-buffer " *teamwork-fill*")))
    (with-current-buffer ob (insert text))
    (teamwork--fill-buffer buffer ob mode-fn)
    (kill-buffer ob)))

(defun teamwork--run-fresh (buffer &optional prev)
  "Fetch BUFFER's data fresh (async) using its buffer-local fetch spec, then swap
it in on success (state FRESH) or leave it and warn (state ERROR).  PREV, if
given, is a pre-captured --prev snapshot path (used when the caller snapshotted
the buffer BEFORE overwriting it with cache); otherwise the buffer's current
content is snapshotted here (the refresh path, where edits are still in place)."
  (with-current-buffer buffer
    (let* ((args teamwork--fresh-args)
           (account teamwork--account)
           (mode-fn teamwork--mode-fn)
           (prev (or prev (and teamwork--use-prev (teamwork--snapshot-prev buffer))))
           (tmp-out (make-temp-file "teamwork-fresh" nil ".org"))
           (errbuf (get-buffer-create " *teamwork-fetch-stderr*")))
      (with-current-buffer errbuf (erase-buffer))
      (make-process
       :name "teamwork-fetch" :buffer (get-buffer-create " *teamwork-fetch-out*")
       :stderr errbuf :noquery t
       :command (append (list teamwork-python teamwork-script) args
                        (when account (list "--account" account))
                        (when prev (list "--prev" prev))
                        (list "--out" tmp-out))
       :sentinel
       (lambda (proc _event)
         (when (memq (process-status proc) '(exit signal))
           (if (and (eq (process-status proc) 'exit)
                    (zerop (process-exit-status proc))
                    (file-readable-p tmp-out))
               (when (buffer-live-p buffer)
                 (teamwork--fill-from-string
                  buffer (with-temp-buffer (insert-file-contents tmp-out) (buffer-string))
                  mode-fn)
                 (with-current-buffer buffer (teamwork--set-state 'fresh))
                 (message "Teamwork: refreshed — buffer is now current."))
             (when (buffer-live-p buffer)
               (with-current-buffer buffer
                 (teamwork--set-state
                  'error (with-current-buffer errbuf (string-trim (buffer-string))))))
             (message "Teamwork: refresh failed — showing existing data (submit disabled)."))
           (ignore-errors (delete-file tmp-out))
           (when prev (ignore-errors (delete-file prev)))))))))

(defun teamwork--fetch (buffer kind key account fresh-args submit-cmd mode-fn use-prev
                               &optional return-to)
  "Populate BUFFER for KIND/KEY: show cache instantly (STALE), refresh in the
background.  FRESH-ARGS is the sidecar argv for the live fetch; SUBMIT-CMD the
subcommand submit uses; MODE-FN enables the buffer's minor mode; USE-PREV passes
the old buffer as --prev.  RETURN-TO, if given, is the buffer to switch back to
when this one is closed (so opening comments over a management buffer returns to
it on quit)."
  ;; Snapshot any EXISTING buffer content (e.g. hidden-header edits from a prior
  ;; open) for --prev BEFORE the cache fill overwrites it — otherwise re-running
  ;; the command silently discards those edits and they never reach the sidecar.
  (let ((prev (and use-prev (teamwork--snapshot-prev buffer))))
    (with-current-buffer buffer
      (setq teamwork--kind kind teamwork--key key teamwork--account account
            teamwork--fresh-args fresh-args teamwork--submit-cmd submit-cmd
            teamwork--mode-fn mode-fn teamwork--use-prev use-prev
            teamwork--return-to (and (buffer-live-p return-to) return-to))
      (let ((cached (teamwork--cached kind key account)))
        (teamwork--fill-from-string
         buffer (or cached (format "loading %s ...\n" key)) mode-fn)
        ;; the fill re-created local bindings via org-mode; re-assert the spec
        (setq teamwork--kind kind teamwork--key key teamwork--account account
              teamwork--fresh-args fresh-args teamwork--submit-cmd submit-cmd
              teamwork--mode-fn mode-fn teamwork--use-prev use-prev
              teamwork--return-to (and (buffer-live-p return-to) return-to))
        (teamwork--set-state 'stale)))
    (switch-to-buffer buffer)
    (teamwork--run-fresh buffer prev)))

;;;###autoload
(defun teamwork-refresh ()
  "Re-fetch the current teamwork buffer's data in the background."
  (interactive)
  (unless teamwork--kind (user-error "Not a teamwork buffer"))
  (teamwork--set-state 'stale)
  (teamwork--run-fresh (current-buffer))
  (message "Teamwork: refreshing…"))

;; --------------------------------------------------------------------------- ;;
;; Live log preview — a chronological list of the buffer's time logs
;; --------------------------------------------------------------------------- ;;
(defvar teamwork--log-timer nil "Idle timer refreshing the log preview.")
(defvar teamwork--log-tick nil "Last seen modification tick of the timesheet buffer.")

(defconst teamwork--log-line-re
  (concat "^[ \t]*-[ \t]+\\(?:[0-9]+[ \t]+\\)?"           ; optional id
          "\\(?1:[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)[ \t]+"  ; 1 date
          "\\(?:=\\(?2:[0-9]\\{1,2\\}:[0-9]\\{2\\}\\)"    ; 2 =duration
          ;; 3 start  4 end — each either H:MM or HHMM
          "\\|\\(?3:[0-9]\\{1,2\\}:[0-9]\\{2\\}\\|[0-9]\\{3,4\\}\\)[ \t]+"
          "\\(?4:[0-9]\\{1,2\\}:[0-9]\\{2\\}\\|[0-9]\\{3,4\\}\\)\\)"
          "[ \t]*\\(?:\\(?6:\\[[dD]\\]\\)[ \t]*\\)?"      ; 6 optional [d] done marker
          "\\(?5:.*\\)$")                                 ; 5 first desc line
  "Match a log line, capturing date, dur, start, end, first description, done.")

(defun teamwork--hhmm (s)
  "Minutes for a time token S in \"H:MM\" or \"HHMM\" form, or nil."
  (when s
    (cond
     ((string-match "\\`\\([0-9]+\\):\\([0-9]\\{2\\}\\)\\'" s)
      (+ (* 60 (string-to-number (match-string 1 s))) (string-to-number (match-string 2 s))))
     ((string-match "\\`\\([0-9]\\{3,4\\}\\)\\'" s)
      (let ((p (string-to-number (match-string 1 s))))
        (+ (* 60 (/ p 100)) (% p 100)))))))

(defun teamwork--norm-hm (s)
  "Normalise a time token S (\"HHMM\" or \"H:MM\") to \"HH:MM\", or S if unparseable."
  (let ((m (teamwork--hhmm s)))
    (if m (format "%02d:%02d" (/ m 60) (% m 60)) s)))

(defun teamwork--parse-buffer-logs ()
  "Parse the timesheet buffer into a chronological list of log plists."
  (let (logs (task ""))
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (let ((line (buffer-substring-no-properties (line-beginning-position) (line-end-position))))
          (cond
           ((string-match "^\\*\\{3,\\} \\(.*\\)$" line)   ; task (***) or subtask (**** …)
            (setq task (string-trim (match-string 1 line))))
           ((string-match teamwork--log-line-re line)
            (let ((date (match-string 1 line))
                  (dur (match-string 2 line))
                  (start (match-string 3 line))
                  (end (match-string 4 line))
                  (done (match-string 6 line))
                  (desc (list (string-trim (or (match-string 5 line) "")))))
              (save-excursion
                (forward-line 1)
                (while (and (not (eobp))
                            (let ((l (buffer-substring-no-properties
                                      (line-beginning-position) (line-end-position))))
                              (and (string-match-p "^[ \t]+[^ \t]" l)
                                   (not (string-match-p "^[ \t]*-[ \t]" l))
                                   (not (string-match-p "^\\*" l)))))
                  (push (string-trim (buffer-substring-no-properties
                                      (line-beginning-position) (line-end-position)))
                        desc)
                  (forward-line 1)))
              (push (list :date date :start start :end end :dur dur :task task
                          :done (and done t)
                          :desc (string-join (nreverse desc) "\n") :overlap nil)
                    logs))))
          (forward-line 1))))
    (sort (nreverse logs)
          (lambda (a b)
            (if (string= (plist-get a :date) (plist-get b :date))
                (string< (or (plist-get a :start) (plist-get a :dur) "")
                         (or (plist-get b :start) (plist-get b :dur) ""))
              (string< (plist-get a :date) (plist-get b :date)))))))

(defun teamwork--log-minutes (lg)
  (let ((dur (plist-get lg :dur)) (start (plist-get lg :start)) (end (plist-get lg :end)))
    (cond (dur (or (teamwork--hhmm dur) 0))
          ((and start end) (max 0 (- (teamwork--hhmm end) (teamwork--hhmm start))))
          (t 0))))

(defun teamwork--fmt-hours (minutes)
  "Format MINUTES as a compact decimal-hours string, e.g. 270 -> \"4.5h\"."
  (let ((h (/ minutes 60.0)))
    (if (= h (ftruncate h))
        (format "%dh" (truncate h))
      (format "%sh" (string-trim-right (format "%.2f" h) "0+")))))

(defun teamwork--weekday (iso-date)
  "Return the English weekday name for ISO-DATE (\"YYYY-MM-DD\"), or nil.
Locale is forced to C so the name is always English (e.g. \"Monday\")."
  (when (and iso-date
             (string-match "\\`\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\)\\'"
                           iso-date))
    (let ((y (string-to-number (match-string 1 iso-date)))
          (m (string-to-number (match-string 2 iso-date)))
          (d (string-to-number (match-string 3 iso-date)))
          (system-time-locale "C"))
      (format-time-string "%A" (encode-time (list 0 0 0 d m y nil -1 nil))))))

(defun teamwork--log-interval (lg)
  "Return (START . END) in minutes if LG has both times, else nil."
  (let ((s (plist-get lg :start)) (e (plist-get lg :end)))
    (when (and s e) (cons (teamwork--hhmm s) (teamwork--hhmm e)))))

(defun teamwork--mark-overlaps (logs)
  "Set :overlap on any logs whose times intersect another on the same date."
  (dolist (a logs)
    (let ((ia (teamwork--log-interval a)))
      (when ia
        (dolist (b logs)
          (unless (eq a b)
            (let ((ib (teamwork--log-interval b)))
              (when (and ib (string= (plist-get a :date) (plist-get b :date))
                         (< (car ia) (cdr ib)) (< (car ib) (cdr ia)))
                (plist-put a :overlap t))))))))
  logs)

(defun teamwork--buffer-log-problems ()
  "Return human-readable problems with dated log lines in the timesheet buffer."
  (let (problems (ln 0))
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (setq ln (1+ ln))
        (let ((line (buffer-substring-no-properties
                     (line-beginning-position) (line-end-position))))
          (when (and (string-match-p "^[ \t]*-[ \t]" line)             ; a bullet
                     (string-match-p "[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}" line)) ; that is dated
            (if (string-match teamwork--log-line-re line)
                (let ((s (match-string 3 line)) (e (match-string 4 line)))
                  (when (and s e (<= (teamwork--hhmm e) (teamwork--hhmm s)))
                    (push (format "L%d end ≤ start: %s" ln (string-trim line)) problems)))
              (push (format "L%d bad format: %s" ln (string-trim line)) problems))))
        (forward-line 1)))
    (nreverse problems)))

;; -- action preview (async, debounced) -------------------------------------- ;;
(defvar teamwork--plan-cache nil "Propertised text of the pending-changes preview.")
(defvar teamwork--plan-timer nil "Debounce timer for the action preview.")
(defvar teamwork--plan-proc nil "In-flight action-preview process, if any.")

(defun teamwork--format-plan (actions problems)
  "Return propertised text summarising pending ACTIONS and PROBLEMS."
  (let ((new 0) (edit 0) (del 0) lines)
    (dolist (a actions)
      (let* ((type (alist-get 'type a))
             (mark (cond ((string-prefix-p "create" type) (setq new (1+ new)) "+")
                         ((string-prefix-p "update" type) (setq edit (1+ edit)) "~")
                         ((string-prefix-p "delete" type) (setq del (1+ del)) "−")
                         (t "·"))))
        (push (propertize (format "  %s %s %s" mark (teamwork--action-icon type)
                                  (or (alist-get 'summary a) type))
                          'face (teamwork--action-face type))
              lines)))
    (setq lines (nreverse lines))
    (concat
     (when problems
       (concat (mapconcat (lambda (p) (propertize (format "  ⚠ %s" p) 'face 'error)) problems "\n")
               "\n"))
     (format "  %s · %s · %s\n"
             (propertize (format "%d new" new) 'face 'teamwork-new-face)
             (propertize (format "%d edit" edit) 'face 'teamwork-edit-face)
             (propertize (format "%d delete" del) 'face 'teamwork-delete-face))
     (when lines
       (concat (string-join (seq-take lines 15) "\n")
               (when (> (length lines) 15) (format "\n  … +%d more" (- (length lines) 15)))
               "\n")))))

(defun teamwork--schedule-plan ()
  "After the user pauses, compute the action preview asynchronously (debounced)."
  (when (timerp teamwork--plan-timer) (cancel-timer teamwork--plan-timer))
  (setq teamwork--plan-timer (run-with-timer 1.0 nil #'teamwork--compute-plan)))

(defun teamwork--compute-plan ()
  "Run `submit --json' on the current buffer async; cache the formatted result."
  (let ((src (get-buffer teamwork-buffer)))
    (when (and src (get-buffer-window teamwork-logs-buffer))
      (when (process-live-p teamwork--plan-proc) (ignore-errors (kill-process teamwork--plan-proc)))
      (let ((tmp (make-temp-file "teamwork-plan" nil ".org"))
            (obuf (generate-new-buffer " *teamwork-plan-out*"))
            (account (teamwork--buffer-account)))
        (with-current-buffer src (write-region (point-min) (point-max) tmp nil 'silent))
        (setq teamwork--plan-proc
              (make-process
               :name "teamwork-plan" :buffer obuf :noquery t
               :command (append (list teamwork-python teamwork-script "submit" "--file" tmp "--json")
                                (when account (list "--account" account)))
               :sentinel
               (lambda (proc _e)
                 (when (memq (process-status proc) '(exit signal))
                   (let ((ok (and (eq (process-status proc) 'exit) (zerop (process-exit-status proc))))
                         (out (with-current-buffer obuf (buffer-string))))
                     (setq teamwork--plan-cache
                           (or (and ok (condition-case nil
                                           (let ((plan (json-parse-string
                                                        out :object-type 'alist :array-type 'list
                                                        :null-object nil)))
                                             (teamwork--format-plan (alist-get 'actions plan)
                                                                    (alist-get 'problems plan)))
                                         (error nil)))
                               (propertize "  (unavailable — pull a range first)\n" 'face 'shadow)))
                     (ignore-errors (delete-file tmp))
                     (when (buffer-live-p obuf) (kill-buffer obuf))
                     (when (get-buffer-window teamwork-logs-buffer)
                       (teamwork--render-log-preview)))))))))))

(defun teamwork--render-log-preview ()
  "Re-render the log list into the logs buffer, preserving scroll position.
Overlapping times are red; formatting problems show at the top; a
non-committable action preview sits between separators above the totals."
  (let* ((src (get-buffer teamwork-buffer))
         (logs (and src (with-current-buffer src (teamwork--parse-buffer-logs))))
         (problems (and src (with-current-buffer src (teamwork--buffer-log-problems))))
         (buf (get-buffer-create teamwork-logs-buffer))
         (win (get-buffer-window buf))
         (wstart (and win (window-start win)))
         (wpt (and win (window-point win)))
         (rule (propertize (make-string 30 ?─) 'face 'shadow))
         (day-totals (make-hash-table :test 'equal))
         (total 0) (cur nil))
    (teamwork--mark-overlaps logs)
    (dolist (lg logs)
      (let ((d (plist-get lg :date)))
        (puthash d (+ (gethash d day-totals 0) (teamwork--log-minutes lg)) day-totals)))
    (with-current-buffer buf
      (let ((inhibit-read-only t) (buffer-read-only nil))
        (erase-buffer)
        (when problems
          (insert (propertize "⚠ formatting problems\n" 'face 'error))
          (dolist (p problems) (insert (propertize (format "  %s\n" p) 'face 'error)))
          (insert "\n"))
        (dolist (lg logs)
          (let ((date (plist-get lg :date)))
            (unless (equal date cur)
              (setq cur date)
              (insert (propertize (format "%s %s (%s)\n" date
                                          (or (teamwork--weekday date) "")
                                          (teamwork--fmt-hours (gethash date day-totals 0)))
                                  'face 'font-lock-comment-face)))
            (let* ((over (plist-get lg :overlap))
                   (span (if (plist-get lg :dur)
                             (format "=%s" (plist-get lg :dur))
                           (format "%s-%s" (teamwork--norm-hm (plist-get lg :start))
                                   (teamwork--norm-hm (plist-get lg :end))))))
              (setq total (+ total (teamwork--log-minutes lg)))
              (insert "  "
                      (propertize (format "%-11s " span)
                                  'face (if over 'error 'font-lock-keyword-face))
                      (propertize (plist-get lg :task) 'face 'font-lock-function-name-face)
                      (if (plist-get lg :done) (propertize "  ✔ done" 'face 'success) "")
                      (if over (propertize "  ⟂ overlap" 'face 'error) "")
                      "\n")
              (dolist (dl (split-string (or (plist-get lg :desc) "") "\n" t))
                (insert "    " (propertize dl 'face 'font-lock-doc-face) "\n")))))
        ;; separator · pending-changes preview · separator · totals
        (insert "\n" rule "\n"
                (propertize "pending changes (preview only)\n" 'face 'font-lock-comment-face)
                (or teamwork--plan-cache (propertize "  computing…\n" 'face 'shadow))
                rule "\n"
                (propertize (format "%d logs · %d:%02d total\n"
                                    (length logs) (/ total 60) (% total 60)) 'face 'bold)))
      (unless (derived-mode-p 'special-mode) (special-mode))
      (if (and win wstart)
          (progn (set-window-start win (min wstart (point-max)) t)
                 (set-window-point win (min (or wpt (point-min)) (point-max))))
        (goto-char (point-min))))))

(defun teamwork--stop-log-timer ()
  (when teamwork--log-timer (cancel-timer teamwork--log-timer))
  (when (timerp teamwork--plan-timer) (cancel-timer teamwork--plan-timer))
  (setq teamwork--log-timer nil teamwork--log-tick nil teamwork--plan-timer nil))

(defun teamwork--log-tick-refresh ()
  "Idle callback: refresh the log preview when the timesheet buffer changed."
  (let ((src (get-buffer teamwork-buffer)))
    (if (or (not src) (not (get-buffer-window teamwork-logs-buffer)))
        (teamwork--stop-log-timer)          ; preview closed → stop polling
      (let ((tick (buffer-chars-modified-tick src)))
        (unless (equal tick teamwork--log-tick)
          (setq teamwork--log-tick tick)
          (teamwork--render-log-preview)     ; cheap: logs + overlaps + warnings
          (teamwork--schedule-plan))))))     ; heavy: action preview, debounced/async

;;;###autoload
(defun teamwork-log-preview ()
  "Toggle a live side window listing the buffer's time logs in chronological order."
  (interactive)
  (if (get-buffer-window teamwork-logs-buffer)
      (progn (teamwork--stop-log-timer)
             (when-let ((w (get-buffer-window teamwork-logs-buffer))) (delete-window w))
             (when (get-buffer teamwork-logs-buffer) (kill-buffer teamwork-logs-buffer)))
    (setq teamwork--plan-cache nil teamwork--log-tick nil)
    (teamwork--render-log-preview)
    (display-buffer-in-side-window (get-buffer teamwork-logs-buffer)
                                   '((side . right) (window-width . 0.4)))
    (teamwork--stop-log-timer)
    (teamwork--schedule-plan)
    (setq teamwork--log-timer (run-with-idle-timer 0.4 t #'teamwork--log-tick-refresh))))

;; --------------------------------------------------------------------------- ;;
;; Live pending-changes preview (management / comments) — a side window that
;; shows what C-c C-c would submit, recomputed as you edit.  The timesheet's
;; richer log preview (C-c C-l) already folds this in; this is the equivalent
;; for buffers that have no time logs, on the same key.
;; --------------------------------------------------------------------------- ;;
(defvar teamwork--changes-src nil "Source buffer the changes preview reflects.")
(defvar teamwork--changes-timer nil "Idle timer refreshing the changes preview.")
(defvar teamwork--changes-tick nil "Last seen modification tick of the source buffer.")
(defvar teamwork--changes-proc nil "In-flight changes-preview process, if any.")

(defun teamwork--changes-render (text)
  "Render TEXT (a pending-changes summary) into the changes side buffer."
  (let ((buf (get-buffer-create teamwork-changes-buffer)))
    (with-current-buffer buf
      (let ((inhibit-read-only t) (buffer-read-only nil))
        (erase-buffer)
        (insert (propertize "pending changes (preview only — C-c C-c to submit)\n\n"
                            'face 'font-lock-comment-face))
        (insert (or text (propertize "  computing…\n" 'face 'shadow))))
      (unless (derived-mode-p 'special-mode) (special-mode)))))

(defun teamwork--changes-compute ()
  "Run SUBMIT-CMD --json on the source buffer async; render the formatted plan."
  (let ((src teamwork--changes-src))
    (when (and (buffer-live-p src) (get-buffer-window teamwork-changes-buffer))
      (when (process-live-p teamwork--changes-proc)
        (ignore-errors (kill-process teamwork--changes-proc)))
      (let ((tmp (make-temp-file "teamwork-chg" nil ".org"))
            (obuf (generate-new-buffer " *teamwork-chg-out*"))
            (submit-cmd (with-current-buffer src (or teamwork--submit-cmd "submit")))
            (account (with-current-buffer src
                       (or teamwork--account (teamwork--buffer-account src)))))
        (with-current-buffer src (write-region (point-min) (point-max) tmp nil 'silent))
        (setq teamwork--changes-proc
              (make-process
               :name "teamwork-changes" :buffer obuf :noquery t
               :command (append (list teamwork-python teamwork-script submit-cmd
                                      "--file" tmp "--json")
                                (when account (list "--account" account)))
               :sentinel
               (lambda (proc _e)
                 (when (memq (process-status proc) '(exit signal))
                   (let* ((ok (and (eq (process-status proc) 'exit)
                                   (zerop (process-exit-status proc))))
                          (out (with-current-buffer obuf (buffer-string)))
                          (txt (or (and ok (condition-case nil
                                               (let ((plan (json-parse-string
                                                            out :object-type 'alist
                                                            :array-type 'list :null-object nil)))
                                                 (teamwork--format-plan
                                                  (alist-get 'actions plan)
                                                  (alist-get 'problems plan)))
                                             (error nil)))
                                   (propertize "  (unavailable — refresh first)\n"
                                               'face 'shadow))))
                     (ignore-errors (delete-file tmp))
                     (when (buffer-live-p obuf) (kill-buffer obuf))
                     (when (get-buffer-window teamwork-changes-buffer)
                       (teamwork--changes-render txt)))))))))))

(defun teamwork--changes-stop ()
  (when (timerp teamwork--changes-timer) (cancel-timer teamwork--changes-timer))
  (when (process-live-p teamwork--changes-proc)
    (ignore-errors (kill-process teamwork--changes-proc)))
  (setq teamwork--changes-timer nil teamwork--changes-tick nil))

(defun teamwork--changes-tick-fn ()
  "Idle callback: recompute the changes preview when the source buffer changed."
  (let ((src teamwork--changes-src))
    (if (or (not (buffer-live-p src)) (not (get-buffer-window teamwork-changes-buffer)))
        (teamwork--changes-stop)
      (let ((tick (buffer-chars-modified-tick src)))
        (unless (equal tick teamwork--changes-tick)
          (setq teamwork--changes-tick tick)
          (teamwork--changes-compute))))))

;;;###autoload
(defun teamwork-changes-preview ()
  "Toggle a live side window previewing this buffer's pending changes.
The same diff C-c C-c would apply, recomputed (debounced) as you edit."
  (interactive)
  (unless teamwork--kind (user-error "Not a teamwork buffer"))
  (if (get-buffer-window teamwork-changes-buffer)
      (progn (teamwork--changes-stop)
             (when-let ((w (get-buffer-window teamwork-changes-buffer))) (delete-window w))
             (when (get-buffer teamwork-changes-buffer) (kill-buffer teamwork-changes-buffer)))
    (setq teamwork--changes-src (current-buffer) teamwork--changes-tick nil)
    (teamwork--changes-render nil)
    (display-buffer-in-side-window (get-buffer-create teamwork-changes-buffer)
                                   '((side . right) (window-width . 0.4)))
    (teamwork--changes-compute)
    (teamwork--changes-stop)
    (setq teamwork--changes-timer (run-with-idle-timer 0.6 t #'teamwork--changes-tick-fn))))

;; --------------------------------------------------------------------------- ;;
;; Folding: hide property drawers on open, keep the #+TEAMWORK header visible
;; --------------------------------------------------------------------------- ;;
(defun teamwork--fold-drawers ()
  "Fold every :PROPERTIES: drawer in the current buffer."
  (org-with-wide-buffer
   (goto-char (point-min))
   (while (re-search-forward "^[ \t]*:PROPERTIES:[ \t]*$" nil t)
     (save-excursion
       (forward-line 0)
       (cond ((fboundp 'org-fold-hide-drawer-toggle) (org-fold-hide-drawer-toggle t))
             ((fboundp 'org-hide-drawer-toggle) (org-hide-drawer-toggle t))
             ((fboundp 'org-flag-drawer) (org-flag-drawer t)))))))

;; --------------------------------------------------------------------------- ;;
;; Pull
;; --------------------------------------------------------------------------- ;;
(defun teamwork--default-range ()
  "Return (FROM . TO) ISO strings for the previous 30 days (today-30 .. today)."
  (let ((now (current-time)))
    (cons (format-time-string "%Y-%m-%d" (time-subtract now (days-to-time 30)))
          (format-time-string "%Y-%m-%d" now))))

(defun teamwork--prompt-range ()
  "Prompt for FROM/TO via the org calendar; return (FROM . TO)."
  (cons (org-read-date nil nil nil "From date: ")
        (org-read-date nil nil nil "To date: ")))

(defun teamwork--buffer-range ()
  "Return (FROM . TO) parsed from the timesheet buffer's #+TEAMWORK header, or nil.
This is what lets you edit the dates in the header and re-run to change range."
  (let ((buf (get-buffer teamwork-buffer)))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (save-excursion
          (goto-char (point-min))
          (when (re-search-forward "^#\\+TEAMWORK: from=\\([0-9-]+\\) to=\\([0-9-]+\\)" nil t)
            (cons (match-string 1) (match-string 2))))))))

(defun teamwork--fill-buffer (buf out &optional mode-fn)
  "Replace BUF's contents with process buffer OUT, set up mode and folding.
MODE-FN enables the buffer's teamwork minor mode (default: the timesheet mode).
Buffer-local teamwork state survives the `org-mode' call here because it is
marked permanent-local; the caller re-applies the banner via
`teamwork--set-state'."
  (with-current-buffer buf
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert-buffer-substring out)
      (goto-char (point-min))
      (org-mode)
      (funcall (or mode-fn #'teamwork--enable-timesheet-mode))
      (teamwork--fold-drawers))))

(defvar teamwork--range-file
  (expand-file-name "teamwork-timesheet/last-range"
                    (or (getenv "XDG_CONFIG_HOME") (expand-file-name "~/.config")))
  "File remembering the last-used FROM/TO range (one line: \"FROM TO\").")

(defvar teamwork--last-range nil "In-memory last-used (FROM . TO).")

(defun teamwork--save-range (from to)
  "Remember FROM/TO in memory and on disk (called at request time, so a failed
pull needn't be retyped)."
  (setq teamwork--last-range (cons from to))
  (ignore-errors
    (make-directory (file-name-directory teamwork--range-file) t)
    (with-temp-file teamwork--range-file (insert from " " to "\n"))))

(defun teamwork--load-range ()
  "Return the last-used (FROM . TO) from memory or disk, or nil."
  (or teamwork--last-range
      (and (file-readable-p teamwork--range-file)
           (with-temp-buffer
             (insert-file-contents teamwork--range-file)
             (when (looking-at "\\([0-9-]+\\)[ \t]+\\([0-9-]+\\)")
               (cons (match-string 1) (match-string 2)))))))

(defun teamwork--pull (from to &optional account)
  "Pull the timesheet for FROM..TO into the timesheet buffer (current window).
ACCOUNT, when given, selects which stored Teamwork account to pull from; the
sidecar records it in the buffer's #+TEAMWORK_ACCOUNT header so submit reuses
it.

Cached data (if any) is shown instantly while a fresh copy is fetched in the
background; the buffer being replaced is passed to the sidecar as --prev, so a
deleted project heading or edited #+TEAMWORK_HIDDEN updates the hidden-project
prefs."
  (teamwork--save-range from to)   ; remember before requesting, so failures survive
  (teamwork--fetch (get-buffer-create teamwork-buffer) "timesheet"
                   (format "%s_%s" from to) account
                   (list "pull" "--from" from "--to" to)
                   "submit" #'teamwork--enable-timesheet-mode t))

;;;###autoload
(defun teamwork-timesheet (&optional ask)
  "Pull the timesheet for the past 30 days into an org buffer (current window).

Range is chosen as: with prefix ASK, prompt via the calendar; else if the
timesheet buffer already has a #+TEAMWORK header, reuse its dates (so you can
edit the dates in the header and re-run to change the range); else default to
the past 30 days.  To pick dates without a prefix (C-u scrolls in evil), use
`teamwork-set-range' (C-c C-d); reuse the last range with
`teamwork-timesheet-prev-time'.

With more than one account configured you are asked which to use; when reusing
the current buffer's dates (no prefix), its account is reused without asking."
  (interactive "P")
  (let* ((buf-range (teamwork--buffer-range))
         (range (cond (ask (teamwork--prompt-range))
                      (buf-range)
                      (t (teamwork--default-range))))
         ;; Reuse the buffer's account when reusing its dates; else pick one.
         (account (if (and buf-range (not ask))
                      (or (teamwork--buffer-account) (teamwork--choose-account))
                    (teamwork--choose-account))))
    (teamwork--pull (car range) (cdr range) account)))

;;;###autoload
(defun teamwork-set-range ()
  "Prompt for a date range via the calendar, then pull the timesheet.
Reliable under evil where C-u scrolls instead of giving a prefix arg.
Asks which account to use when several are configured."
  (interactive)
  (let ((range (teamwork--prompt-range))
        (account (teamwork--choose-account)))
    (teamwork--pull (car range) (cdr range) account)))

;;;###autoload
(defun teamwork-timesheet-prev-time ()
  "Pull using the last-used date range (remembered across pulls and restarts).
Asks which account to use when several are configured."
  (interactive)
  (let ((range (teamwork--load-range)))
    (if range
        (teamwork--pull (car range) (cdr range) (teamwork--choose-account))
      (user-error "No previous range yet — use `teamwork-set-range' (C-c C-d)"))))

;; --------------------------------------------------------------------------- ;;
;; Management — the whole project structure (no time filter), edit + label
;; --------------------------------------------------------------------------- ;;
;;;###autoload
(defun teamwork-management ()
  "Open a management buffer: the project/tasklist/task/subtask structure with no
time filter.  Create tasks/lists/subtasks by adding headings, rename by editing
heading text, and label tasks with a :LABELS: property.  Which projects appear
is the per-account filter (see `teamwork-filter').  C-c C-c submits."
  (interactive)
  (let ((account (or (teamwork--buffer-account (get-buffer teamwork-management-buffer))
                     (teamwork--choose-account "Teamwork account (manage): "))))
    (teamwork--fetch (get-buffer-create teamwork-management-buffer) "manage" "manage" account
                     (list "manage") "submit" #'teamwork--enable-management-mode t)))

;; --------------------------------------------------------------------------- ;;
;; Comments — fetch/edit the comments of the task under point (any TW buffer)
;; --------------------------------------------------------------------------- ;;
;;;###autoload
(defun teamwork-comments ()
  "Open the comments of the task under point in a new buffer (edit/add/delete).
Run from a timesheet or management buffer with point inside a task; the task's
:TASK_ID: (inherited from ancestors) selects which task.  C-c C-c submits the
comment changes."
  (interactive)
  (let ((tid (org-entry-get nil "TASK_ID" t))
        (account (or teamwork--account (teamwork--buffer-account (current-buffer))))
        (origin (current-buffer)))
    (unless tid
      (user-error "No task under point (no TASK_ID here or above)"))
    (teamwork--fetch (get-buffer-create (format "teamwork-comments-%s" tid))
                     "comments" tid account
                     (list "comments-pull" "--task" tid)
                     "comments-submit" #'teamwork--enable-comments-mode nil
                     origin)))

;; --------------------------------------------------------------------------- ;;
;; Project filter — a per-account allowlist of projects (persisted in prefs)
;; --------------------------------------------------------------------------- ;;
;;;###autoload
(defun teamwork-filter ()
  "Choose which projects appear in management/timesheet for an account.
The choice is stored per account, so switching accounts no longer resets it.
An empty selection means all active projects."
  (interactive)
  (let* ((account (teamwork--choose-account "Teamwork account (filter): "))
         (projs (apply #'teamwork--run-json "projects"
                       (when account (list "--account" account))))
         (label (lambda (p) (format "%s  %s" (alist-get 'id p) (alist-get 'name p))))
         (labels (mapcar label projs))
         (current (delq nil (mapcar (lambda (p)
                                      (when (eq t (alist-get 'in_filter p)) (funcall label p)))
                                    projs)))
         (chosen (completing-read-multiple
                  "Projects to include (empty = all active): " labels nil t
                  (when current (mapconcat #'identity current ","))))
         (ids (mapcar (lambda (s) (car (split-string s))) chosen)))
    (apply #'teamwork--run-json "filter-set"
           "--projects" (mapconcat #'identity ids ",")
           (when account (list "--account" account)))
    (message "Teamwork: filter set to %d project(s)%s — re-run manage/pull to apply."
             (length ids) (if account (format " [%s]" account) ""))))

;; --------------------------------------------------------------------------- ;;
;; Property picker — set task properties (tags/due/priority/assignee) w/ values
;; --------------------------------------------------------------------------- ;;
(defvar teamwork-priorities '("" "low" "medium" "high")
  "Allowed :URGENCY: values (empty = none).")

(defun teamwork--account-args ()
  "(\"--account\" NAME) for this buffer's account, or nil."
  (let ((a (or teamwork--account (teamwork--buffer-account (current-buffer)))))
    (when a (list "--account" a))))

(defun teamwork--json-or-nil (subcmd)
  "Run the sidecar SUBCMD for this buffer's account; parsed JSON, or nil on error."
  (condition-case err
      (apply #'teamwork--run-json subcmd (teamwork--account-args))
    (error (message "Teamwork: %s" (error-message-string err)) nil)))

(defun teamwork--current-prop-list (key)
  "Current comma-separated values of drawer property KEY at point, as a list."
  (let ((v (org-entry-get nil key)))
    (and v (not (string-empty-p (string-trim v)))
         (split-string v "[,]+" t "[ \t]+"))))

(defun teamwork--put-property (key value)
  "Set drawer property KEY to VALUE on the task at point (empty VALUE clears it
in Teamwork — the line is kept with no value)."
  (org-entry-put (point) key (or value "")))

;;;###autoload
(defun teamwork-set-property ()
  "Set a property on the task at point, completing over the available values.
Done is true/false, priority is a fixed list, due date uses the org calendar, and
tags / assignees complete against the account's configured tags / project people
(you can still type a new one).  In a timesheet buffer only Tags applies."
  (interactive)
  (unless (org-entry-get nil "TASK_ID" t)
    (user-error "Point is not on a task (no TASK_ID here or above)"))
  (let* ((manage (equal teamwork--kind "manage"))
         (choices (if manage '("Done" "Tags" "Due date" "Priority" "Assignee") '("Tags")))
         (prop (if (cdr choices) (completing-read "Set property: " choices nil t) "Tags")))
    (pcase prop
      ("Done"
       (teamwork--put-property
        "DONE" (completing-read "Done: " '("true" "false") nil t
                                nil nil
                                ;; default to the opposite of the current value
                                (if (equal (org-entry-get nil "DONE") "true") "false" "true"))))
      ("Due date"
       (teamwork--put-property "DUE" (org-read-date nil nil nil "Due date: ")))
      ("Priority"
       (teamwork--put-property "URGENCY"
                               (completing-read "Priority: " teamwork-priorities nil t)))
      ("Tags"
       (let* ((all (teamwork--json-or-nil "tags"))
              (cur (teamwork--current-prop-list "LABELS"))
              (chosen (completing-read-multiple
                       "Tags (comma-separated, empty clears): " all nil nil
                       (and cur (mapconcat #'identity cur ",")))))
         (teamwork--put-property "LABELS" (mapconcat #'identity chosen ", "))))
      ("Assignee"
       (let* ((people (teamwork--json-or-nil "people"))
              (names (delq nil (mapcar (lambda (p) (alist-get 'name p)) people)))
              (cur (teamwork--current-prop-list "ASSIGNEE"))
              (chosen (completing-read-multiple
                       "Assignees (comma-separated, empty clears): " names nil nil
                       (and cur (mapconcat #'identity cur ",")))))
         (teamwork--put-property "ASSIGNEE" (mapconcat #'identity chosen ", ")))))
    (message "Teamwork: %s set — C-c C-l previews, C-c C-c submits." prop)))

;; --------------------------------------------------------------------------- ;;
;; Submit: preview -> confirm -> streamed apply
;; --------------------------------------------------------------------------- ;;
(defun teamwork--run-json (&rest args)
  "Run the sidecar with ARGS and parse its single-line JSON stdout."
  (with-temp-buffer
    (let ((code (apply #'call-process teamwork-python nil t nil teamwork-script args)))
      (goto-char (point-min))
      (if (zerop code)
          (json-parse-buffer :object-type 'alist :array-type 'list :null-object nil)
        (user-error "teamwork sidecar failed: %s" (buffer-string))))))

(defvar-local teamwork--markers nil
  "Vector of overlay markers, one per action, in the preview buffer.")

(defun teamwork--action-face (type)
  "Colour face for action TYPE: green/new, blue/edit, red/delete."
  (cond ((string-prefix-p "create" type) 'teamwork-new-face)
        ((string-prefix-p "update" type) 'teamwork-edit-face)
        ((string-prefix-p "delete" type) 'teamwork-delete-face)
        (t 'default)))

(defun teamwork--action-icon (type)
  "Node icon for action TYPE (task list / task / log)."
  (cond ((string-match-p "tasklist" type) teamwork-icon-tasklist)
        ((string-match-p "task" type) teamwork-icon-task)
        (t teamwork-icon-log)))

(defun teamwork--render-preview (actions)
  "Render ACTIONS into the preview buffer; return it. Records status markers."
  (let ((buf (get-buffer-create teamwork-preview-buffer)))
    (with-current-buffer buf
      (setq buffer-read-only nil)
      (erase-buffer)
      (insert (format "Teamwork submit — %d action(s)\n" (length actions)))
      (insert "  "
              (propertize "new" 'face 'teamwork-new-face) "   "
              (propertize "edit" 'face 'teamwork-edit-face) "   "
              (propertize "delete" 'face 'teamwork-delete-face) "     "
              (format "%s list  %s task  %s log\n\n"
                      teamwork-icon-tasklist teamwork-icon-task teamwork-icon-log))
      (let ((vec (make-vector (length actions) nil))
            (i 0))
        (dolist (a actions)
          (let* ((type (alist-get 'type a))
                 (face (teamwork--action-face type)))
            (insert " ")
            (let ((m (point-marker)))
              (aset vec i m)
              (insert "…"))             ; single-char status cell (stable width)
            (insert "  "
                    (propertize (teamwork--action-icon type) 'face face) "  "
                    (propertize (or (alist-get 'summary a) type) 'face face) "\n")
            (setq i (1+ i))))
        (setq-local teamwork--markers vec))
      (goto-char (point-min))
      (setq buffer-read-only t))
    buf))

(defun teamwork--set-status (idx glyph &optional face)
  "Replace the status glyph for action IDX with GLYPH, optionally in FACE."
  (when (and teamwork--markers (< idx (length teamwork--markers)))
    (let ((m (aref teamwork--markers idx))
          (inhibit-read-only t))
      (when m
        (save-excursion
          (goto-char m)
          (delete-char 1)
          (insert (if face (propertize glyph 'face face) glyph)))))))

(defun teamwork--apply (tmp out target submit-cmd &optional account)
  "Run streamed apply on TMP via SUBMIT-CMD, updating the preview live; reload the
TARGET buffer from OUT (keeping its teamwork mode).  ACCOUNT selects the stored
account (else the sidecar reads the buffer header)."
  (let ((acc "")
        (mode-fn (and (buffer-live-p target)
                      (with-current-buffer target
                        (or teamwork--mode-fn #'teamwork--enable-timesheet-mode))))
        (errbuf (get-buffer-create " *teamwork-apply-stderr*")))
    (with-current-buffer errbuf (erase-buffer))
    (make-process
     :name "teamwork-apply" :buffer (get-buffer-create " *teamwork-apply-out*")
     :stderr errbuf :noquery t
     :command (append (list teamwork-python teamwork-script submit-cmd "--file" tmp
                            "--apply" "--out" out)
                      (when account (list "--account" account)))
     :filter
     (lambda (_proc chunk)
       (setq acc (concat acc chunk))
       (while (string-match "\n" acc)
         (let ((line (substring acc 0 (match-beginning 0))))
           (setq acc (substring acc (match-end 0)))
           (unless (string-empty-p (string-trim line))
             (teamwork--handle-event
              (json-parse-string line :object-type 'alist :array-type 'list :null-object nil))))))
     :sentinel
     (lambda (proc _event)
       (when (memq (process-status proc) '(exit signal))
         (with-current-buffer (get-buffer-create teamwork-preview-buffer)
           (let ((inhibit-read-only t))
             (goto-char (point-max))
             (unless (zerop (process-exit-status proc))
               (insert (format "\nsidecar exited %d; see %s\n"
                               (process-exit-status proc) (buffer-name errbuf))))))
         ;; reload the buffer from the (partially) applied file; it is now current
         (when (and (buffer-live-p target) (file-readable-p out))
           (let ((ob (generate-new-buffer " *teamwork-reload*")))
             (with-current-buffer ob (insert-file-contents out))
             (teamwork--fill-buffer target ob mode-fn)
             (kill-buffer ob))
           (with-current-buffer target (teamwork--set-state 'fresh)))
         (ignore-errors (delete-file tmp))
         (ignore-errors (delete-file out)))))))

(defun teamwork--handle-event (ev)
  "Update the preview buffer from a single stream event EV (an alist)."
  (with-current-buffer (get-buffer-create teamwork-preview-buffer)
    (let ((event (alist-get 'event ev))
          (idx (alist-get 'idx ev)))
      (pcase event
        ("start"  (teamwork--set-status idx "⋯" 'shadow))
        ("retry"  (teamwork--set-status idx "↻" 'warning))
        ("ok"     (teamwork--set-status idx "✓" 'success))
        ("fail"   (teamwork--set-status idx "✗" 'error)
                  (let ((inhibit-read-only t))
                    (goto-char (point-max))
                    (insert (format "\n ✗  action %s failed after %s tries:\n    %s\n"
                                    idx (alist-get 'attempts ev) (alist-get 'error ev)))))
        ("error"  (let ((inhibit-read-only t))
                    (goto-char (point-max))
                    (insert "\nPROBLEMS (nothing applied):\n")
                    (dolist (p (alist-get 'problems ev))
                      (insert "  ! " p "\n"))))
        ("done"   (let ((inhibit-read-only t))
                    (goto-char (point-max))
                    (insert (format "\n%s  applied %s/%s%s\n"
                                    (if (eq t (alist-get 'aborted ev)) "✗" "✓")
                                    (alist-get 'applied ev) (alist-get 'total ev)
                                    (if (eq t (alist-get 'aborted ev))
                                        " — ABORTED; unapplied changes kept in the buffer" "")))))))))

;;;###autoload
(defun teamwork-submit ()
  "Compute the diff for the current teamwork buffer (timesheet, management or
comments), review it, then apply.  Preview appears in a split below; on confirm
it applies with live progress.

Refuses when the buffer is not current (`stale'/`error'): its diff would be
against data that is about to be — or already has been — replaced.  Wait for the
background refresh, or force one with `teamwork-refresh' (C-c C-r)."
  (interactive)
  (unless (save-excursion (goto-char (point-min))
                          (re-search-forward "^#\\+TEAMWORK\\(_MANAGE\\|_COMMENTS\\)?:" nil t))
    (user-error "Not a teamwork buffer"))
  (when (memq teamwork--data-state '(stale error))
    (user-error "Buffer is %s — data is not current, so nothing is submitted; refresh first (C-c C-r)"
                teamwork--data-state))
  (let ((submit-cmd (or teamwork--submit-cmd "submit"))
        (target (current-buffer))
        (tmp (make-temp-file "teamwork" nil ".org"))
        (out (make-temp-file "teamwork-applied" nil ".org"))
        (account (or teamwork--account (teamwork--buffer-account (current-buffer)))))
    (write-region (point-min) (point-max) tmp nil 'silent)
    (let* ((plan (apply #'teamwork--run-json
                        (append (list submit-cmd "--file" tmp "--json")
                                (when account (list "--account" account)))))
           (problems (alist-get 'problems plan))
           (actions (alist-get 'actions plan)))
      (cond
       (problems
        (with-current-buffer (teamwork--render-preview '())
          (let ((inhibit-read-only t))
            (goto-char (point-max))
            (insert "PROBLEMS — fix these, nothing submitted:\n")
            (dolist (p problems) (insert "  ! " p "\n"))))
        (display-buffer-below-selected (get-buffer teamwork-preview-buffer) nil)
        (delete-file tmp) (delete-file out)
        (message "Teamwork: fix the problems shown above."))
       ((null actions)
        (delete-file tmp) (delete-file out)
        (message "Teamwork: no changes to submit."))
       (t
        (let ((pbuf (teamwork--render-preview actions)))
          (display-buffer-below-selected pbuf nil)
          (if (yes-or-no-p (format "Apply %d change(s) to Teamwork%s? " (length actions)
                                   (if account (format " [%s]" account) "")))
              (teamwork--apply tmp out target submit-cmd account)
            ;; declined: close preview window, keep the buffer
            (when-let ((w (get-buffer-window pbuf))) (delete-window w))
            (kill-buffer pbuf)
            (delete-file tmp) (delete-file out)
            (message "Teamwork: submit cancelled."))))))))

;; --------------------------------------------------------------------------- ;;
;; Account management — add / view / delete stored Teamwork logins
;; --------------------------------------------------------------------------- ;;
;;;###autoload
(defun teamwork-account-add ()
  "Add (or update) a Teamwork account interactively in a terminal buffer.
Runs teamwork-setup.sh, which prompts for an account name, site URL and API key,
validates against the live API, and stores the credentials in the system
keyring.  Re-using an existing account name updates it in place."
  (interactive)
  (let ((script (expand-file-name "teamwork-setup.sh" teamwork-dir)))
    (unless (file-exists-p script)
      (user-error "teamwork-setup.sh not found in %s" teamwork-dir))
    (require 'term)
    (when (get-buffer "*teamwork-account-add*")
      (kill-buffer "*teamwork-account-add*"))
    (ansi-term script "teamwork-account-add")
    (message "Teamwork: enter the account details in the terminal buffer.")))

;;;###autoload
(defun teamwork-account-view ()
  "List the configured Teamwork accounts (name, site, user; API keys masked)."
  (interactive)
  (let ((accounts (teamwork--list-accounts))
        (buf (get-buffer-create "*teamwork-accounts*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (if (null accounts)
            (insert "No Teamwork accounts configured.\n\n"
                    "Run M-x teamwork-account-add to add one.\n")
          (insert (propertize (format "Teamwork accounts (%d)\n\n" (length accounts))
                              'face 'bold))
          (dolist (a accounts)
            (insert (propertize (format "• %s\n" (alist-get 'account a))
                                'face 'font-lock-function-name-face)
                    (format "    site : %s\n"
                            (or (alist-get 'base_url a) (alist-get 'site a)))
                    (format "    user : %s (id %s)\n"
                            (alist-get 'user_name a) (alist-get 'user_id a))
                    (format "    key  : %s\n\n" (alist-get 'api_key_masked a))))))
      (goto-char (point-min))
      (special-mode))
    (display-buffer buf)))

;;;###autoload
(defun teamwork-account-delete ()
  "Delete a Teamwork account from the keyring, after confirmation."
  (interactive)
  (let ((names (teamwork--account-names)))
    (unless names (user-error "No Teamwork accounts configured"))
    (let ((name (completing-read "Delete Teamwork account: " names nil t)))
      (if (yes-or-no-p
           (format "Really delete Teamwork account %S from the keyring? " name))
          (progn
            (teamwork--run-json "account-delete" "--account" name)
            (message "Teamwork: deleted account %s" name))
        (message "Teamwork: deletion cancelled")))))

(provide 'teamwork)
;;; teamwork.el ends here
