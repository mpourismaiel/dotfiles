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
;;   C-c C-d   set range  C-c C-l   live log + changes preview
;;   C-c C-p   set a task property (tags/due/priority/assignee) with completion
;;   C-c C-b   set labels (tags)   (complete a task by marking a log [d])
;; In the management buffer:
;;   C-c C-c submit  C-c C-l changes preview  C-c C-f filter
;;   C-c C-p set property (tags/due/priority/assignee w/ value completion)  C-c C-r refresh
;;   C-c C-b labels · C-c C-u urgency · C-c C-d due date · C-c C-a assignee  (dedicated pickers)
;;   Tasks carry their comments inline under a `# Comments' line: edit your own
;;   comment's text to change it, or add a `-'-prefixed block to post a new one.
;;   Done state rides the heading's TODO/DONE keyword (edit it directly; C-c C-t
;;   is disabled).
;;
;; Every editable buffer also shows an interactive header line (rendered as a
;; tall SVG when the config's `svg-header' package is loaded, else a clickable
;; text row): a data-freshness pill, help, a Refetch button, and clickable
;; hidden-project chips (click one to restore it).  The management header adds
;; Lists/Tasks buttons that toggle showing completed task lists / tasks (a
;; per-account, persisted view; completed items render dimmed with a checkmark).
;; The view flags and hidden-project list are read from the account prefs via the
;; sidecar's `manage-state' command after each fetch (buffer-local
;; `teamwork--header-state'), so the management buffer no longer repeats them as a
;; header comment block — it keeps only the routing markers.
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
(require 'seq)
(require 'subr-x)
(require 'cl-lib)

;; Optional GUI header dependencies (only used when the config's `svg-header'
;; package is loaded; every call site is guarded by `featurep'/`fboundp').
(declare-function svg-create "svg")
(declare-function svg-rectangle "svg")
(declare-function svg-text "svg")
(declare-function svg-image "svg")
(declare-function mp/header-line-background "svg-header")
(declare-function mp/header-line-buffer-foreground "svg-header")
(declare-function mp/header-line-position-foreground "svg-header")
(defvar mp/header-svg-font-size)

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

(defface teamwork-completed-face '((t :inherit shadow))
  "Face dimming completed tasks / task lists in the management buffer.")

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
    (define-key m (kbd "C-c C-p") #'teamwork-set-property)
    (define-key m (kbd "C-c C-b") #'teamwork-set-labels)
    (define-key m (kbd "C-c C-t") #'teamwork--todo-key-disabled)  ; shadow org-todo
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
    (define-key m (kbd "C-c C-f") #'teamwork-filter)
    (define-key m (kbd "C-c C-p") #'teamwork-set-property)
    (define-key m (kbd "C-c C-b") #'teamwork-set-labels)
    (define-key m (kbd "C-c C-u") #'teamwork-set-urgency)
    (define-key m (kbd "C-c C-d") #'teamwork-set-due)
    (define-key m (kbd "C-c C-a") #'teamwork-set-assignee)
    (define-key m (kbd "C-c C-t") #'teamwork--todo-key-disabled)  ; shadow org-todo
    m)
  "Keymap active in the management buffer.")

(define-minor-mode teamwork-management-mode
  "Minor mode for the Teamwork management buffer."
  :lighter " TWm"
  :keymap teamwork-management-mode-map)

(defun teamwork--enable-timesheet-mode () (teamwork-timesheet-mode 1))
(defun teamwork--enable-management-mode () (teamwork-management-mode 1))

(defun teamwork--todo-key-disabled ()
  "Shadow org's C-c C-t in Teamwork buffers: done-toggling via that key is off.
Edit the TODO/DONE keyword on the task heading directly to change its state."
  (interactive)
  (message "Teamwork: C-c C-t is disabled; edit the task's TODO/DONE keyword directly."))

;; --------------------------------------------------------------------------- ;;
;; Cached-first, background-refresh loading with a data-freshness banner
;;
;; Every teamwork buffer (timesheet / management) is filled from a
;; local cache instantly (marked STALE), then a fresh copy is fetched in the
;; background and swapped in (FRESH).  A banner in the header-line tells you the
;; state; while stale/errored, submit refuses (its diff would be against data
;; that is about to be — or already has been — replaced).
;;
;; The per-buffer state below is `permanent-local' so it survives the `org-mode'
;; call inside `teamwork--fill-buffer' (which otherwise wipes local variables).
;; --------------------------------------------------------------------------- ;;
(defvar-local teamwork--kind nil "This buffer's kind: \"timesheet\"|\"manage\".")
(defvar-local teamwork--key nil "Cache key: range \"FROM_TO\" / \"manage\" / task id.")
(defvar-local teamwork--account nil "Account this buffer was pulled from.")
(defvar-local teamwork--fresh-args nil "Sidecar argv (sans --account/--out/--prev) for a live fetch.")
(defvar-local teamwork--submit-cmd nil "Sidecar subcommand submit uses (always \"submit\").")
(defvar-local teamwork--mode-fn nil "Function enabling this buffer's teamwork minor mode.")
(defvar-local teamwork--use-prev nil "Whether to pass the old buffer as --prev on refresh.")
(defvar-local teamwork--data-state nil "One of nil, `stale', `fresh', `error'.")
(defvar-local teamwork--state-msg nil "Last error message, shown in the header.")
(defvar-local teamwork--return-to nil "Buffer to switch back to when this one is closed.")
(defvar-local teamwork--view-override nil
  "Optimistic (:all-tasklists BOOL :all-tasks BOOL) shown until the refetch.
Set the instant a view toggle is clicked so the button flips at once.  It is not
`permanent-local', so `teamwork--fill-buffer' wipes it once fresh data (and a
fresh `teamwork--header-state') lands.")
(defvar-local teamwork--header-state nil
  "Management header state (view + hidden projects), sourced from account prefs.
A plist (:view (:all-tasklists BOOL :all-tasks BOOL) :hidden ((ID . NAME) …)),
fetched by `teamwork--load-header-state' after each manage fill — the buffer no
longer carries it.  `permanent-local' so it survives the `org-mode' call in
`teamwork--fill-buffer' and keeps the header painted until fresh state lands.")
(dolist (v '(teamwork--kind teamwork--key teamwork--account teamwork--fresh-args
             teamwork--submit-cmd teamwork--mode-fn teamwork--use-prev teamwork--data-state
             teamwork--state-msg teamwork--return-to teamwork--header-state))
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

(defvar-local teamwork--header-cache nil
  "Cons (SIG . RENDERED) memoizing the header for the current inputs.")

(defun teamwork--set-state (state &optional msg)
  "Set the current buffer's data STATE (and error MSG) and refresh its header."
  (setq teamwork--data-state state
        teamwork--state-msg msg
        teamwork--header-cache nil)
  (setq header-line-format '(:eval (teamwork--header-render)))
  (force-mode-line-update))

;; --------------------------------------------------------------------------- ;;
;; Interactive header line — a clickable control strip (help + refetch + view
;; toggles + hidden-project chips) that keeps the data-freshness state visible.
;; Rendered as a tall multi-row SVG when the config's `svg-header' package is
;; loaded (GUI), else as a single clickable text row (works in a TTY too).  A
;; `condition-case' guard means a rendering bug degrades to a message, never a
;; broken redisplay.
;; --------------------------------------------------------------------------- ;;
(defun teamwork--state-label ()
  "Return (TEXT FACE-PLIST HELP) for the data-state pill."
  (pcase teamwork--data-state
    ('stale (list "STALE"
                  '(:background "#3a2f00" :foreground "#ffd479" :weight bold)
                  "Showing cached data; refreshing in the background — this buffer will be REPLACED, so edits made now are discarded."))
    ('error (list "ERROR"
                  '(:background "#3a0000" :foreground "#ff9a9a" :weight bold)
                  (concat "Refresh FAILED — data is not current, submit is disabled."
                          (when (and teamwork--state-msg
                                     (not (string-empty-p teamwork--state-msg)))
                            (concat "  " (car (split-string teamwork--state-msg "\n")))))))
    (_ (list "READY"
             '(:background "#12331a" :foreground "#9affa0" :weight bold)
             "Data is current — C-c C-c submits."))))

;; -- reading a timesheet buffer's header block ------------------------------ ;;
;; The timesheet buffer still carries its hidden-project list in the header text
;; (only the MANAGEMENT header was decluttered), so its chips are parsed from the
;; buffer; management gets the same state from prefs (see below).
(defun teamwork--header-prefix ()
  "Return the buffer's top block (everything before the first Org heading)."
  (save-excursion
    (goto-char (point-min))
    (buffer-substring-no-properties
     (point-min)
     (if (re-search-forward "^\\*+ " nil t) (match-beginning 0) (point-max)))))

(defun teamwork--parse-hidden (prefix)
  "Return ((ID . NAME) …) for hidden projects parsed from PREFIX text."
  (let (names ids)
    (dolist (line (split-string prefix "\n"))
      (cond
       ((string-match "^#[ \t]+hidden[ \t]+\\([0-9]+\\)[ \t]*\\(.*\\)$" line)
        (push (cons (match-string 1 line) (string-trim (match-string 2 line))) names))
       ((string-match "^#\\+TEAMWORK_HIDDEN:[ \t]*\\(.*\\)$" line)
        (setq ids (split-string (match-string 1 line))))))
    (mapcar (lambda (id) (cons id (or (cdr (assoc id names)) ""))) ids)))

;; -- management header state (view + hidden), sourced from account prefs ---- ;;
;; The management buffer no longer carries the view flags / hidden-project list
;; as comments; `manage-state' reports them from the account prefs and we cache
;; the result in `teamwork--header-state', refreshed after each manage fill.
(defun teamwork--state-from-json (json)
  "Convert a `manage-state' JSON alist to a header-state plist."
  (let ((view (alist-get 'view json))
        (hidden (alist-get 'hidden json)))
    (list :view (list :all-tasklists (eq (alist-get 'all_tasklists view) t)
                      :all-tasks (eq (alist-get 'all_tasks view) t))
          ;; `hidden' is an alist of (ID-SYMBOL . NAME); normalise to strings.
          :hidden (mapcar (lambda (kv) (cons (format "%s" (car kv))
                                             (format "%s" (cdr kv))))
                          hidden))))

(defun teamwork--load-header-state (buffer)
  "Async-fetch BUFFER's management header state (view + hidden) from prefs and
repaint its header.  A no-op for non-management buffers."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (equal teamwork--kind "manage")
        (let ((account teamwork--account)
              (obuf (generate-new-buffer " *teamwork-state*")))
          (make-process
           :name "teamwork-state" :buffer obuf :noquery t
           :command (append (list teamwork-python teamwork-script "manage-state")
                            (when account (list "--account" account)))
           :sentinel
           (lambda (proc _event)
             (when (memq (process-status proc) '(exit signal))
               (when (and (eq (process-status proc) 'exit)
                          (zerop (process-exit-status proc))
                          (buffer-live-p buffer))
                 (when-let ((json (ignore-errors
                                    (with-current-buffer obuf
                                      (goto-char (point-min))
                                      (json-parse-buffer :object-type 'alist
                                                         :array-type 'list
                                                         :null-object nil)))))
                   (with-current-buffer buffer
                     (setq teamwork--header-state (teamwork--state-from-json json)
                           teamwork--header-cache nil)
                     (force-mode-line-update))))
               (kill-buffer obuf)))))))))

(defun teamwork--header-model (prefix)
  "Return a plist describing this buffer's header.
Management reads view + hidden from `teamwork--header-state' (account prefs);
the timesheet still parses its hidden list from PREFIX (its buffer text).  The
optimistic `teamwork--view-override' wins for the view either way."
  (if (equal teamwork--kind "manage")
      (list :kind teamwork--kind
            :hidden (plist-get teamwork--header-state :hidden)
            :view (or teamwork--view-override
                      (plist-get teamwork--header-state :view)))
    (list :kind teamwork--kind
          :hidden (teamwork--parse-hidden prefix)
          :view teamwork--view-override)))

;; -- header actions --------------------------------------------------------- ;;
(defun teamwork--unhide-project (id)
  "Restore hidden project ID and refetch.
In a management buffer this drops ID from the account's hidden prefs (the buffer
no longer carries a `#+TEAMWORK_HIDDEN' line to edit); in a timesheet buffer it
removes ID from that line, whose --prev snapshot the sidecar reconciles."
  (if (equal teamwork--kind "manage")
      (let ((account (or teamwork--account (teamwork--buffer-account (current-buffer)))))
        (condition-case err
            (apply #'teamwork--run-json "unhide" "--id" id
                   (when account (list "--account" account)))
          (error (message "Teamwork: %s" (error-message-string err)))))
    (save-excursion
      (goto-char (point-min))
      (when (re-search-forward "^#\\+TEAMWORK_HIDDEN:[ \t]*\\(.*\\)$" nil t)
        ;; `split-string' clobbers the match data, so capture the id list under
        ;; `save-match-data' — otherwise `replace-match' would edit the wrong span.
        (let* ((inhibit-read-only t)
               (kept (delete id (save-match-data
                                  (split-string (match-string-no-properties 1))))))
          (replace-match (concat "#+TEAMWORK_HIDDEN: " (string-join kept " ")) t t)))))
  (message "Teamwork: restoring project %s…" id)
  (teamwork-refresh))

(defun teamwork--toggle-view (flag)
  "Flip management view FLAG (`:all-tasklists' or `:all-tasks'), persist, refetch."
  (unless (equal teamwork--kind "manage")
    (user-error "View toggles apply to the management buffer only"))
  (let* ((view (or teamwork--view-override
                   (plist-get teamwork--header-state :view)))
         (cur (plist-get view flag))
         (opt (pcase flag (:all-tasklists "--show-all-tasklists")
                          (:all-tasks "--show-all-tasks")))
         (account (or teamwork--account (teamwork--buffer-account (current-buffer)))))
    ;; Flip the button NOW (optimistic), before the async refetch, so the click
    ;; feels immediate; the fresh buffer's header carries the real value and
    ;; wipes this override.  Repaint the header at once.
    (setq teamwork--view-override
          (plist-put (copy-sequence view) flag (not cur))
          teamwork--header-cache nil)
    (force-mode-line-update)
    (apply #'teamwork--run-json "config-set" opt (if cur "false" "true")
           (when account (list "--account" account)))
    (message "Teamwork: completed %s now %s — refreshing…"
             (if (eq flag :all-tasklists) "task lists" "tasks")
             (if cur "hidden" "shown"))
    (teamwork-refresh)))

(defun teamwork--header-buttons (view kind)
  "Return ((LABEL HELP COMMAND STYLE) …) button specs for VIEW/KIND.
STYLE is a plist read by the renderers: `:role' is `refetch' or `toggle', and a
toggle carries `:on' (whether completed items are currently shown)."
  (let (btns)
    (push (list "⟳ Refetch" "Re-fetch now, applying hidden-list changes"
                #'teamwork-refresh '(:role refetch))
          btns)
    (when (equal kind "manage")
      (let ((on (and (plist-get view :all-tasklists) t)))
        (push (list (format "Lists: %s" (if on "all" "active"))
                    "Toggle showing completed task lists"
                    (lambda () (interactive) (teamwork--toggle-view :all-tasklists))
                    (list :role 'toggle :on on))
              btns))
      (let ((on (and (plist-get view :all-tasks) t)))
        (push (list (format "Tasks: %s" (if on "all" "open"))
                    "Toggle showing completed tasks"
                    (lambda () (interactive) (teamwork--toggle-view :all-tasks))
                    (list :role 'toggle :on on))
              btns)))
    (nreverse btns)))

(defun teamwork--header-hint (kind state-help)
  "Header help line for KIND, prefixed by STATE-HELP."
  (concat state-help "   "
          (pcase kind
            ("manage" "C-c C-c submit · C-c C-b/u/d/a labels/urgency/due/assignee · C-c C-p props · edit comments inline under # Comments · click a hidden project to restore it")
            ("timesheet" "C-c C-c submit · C-c C-d range · C-c C-b labels · C-c C-l logs · click a hidden project to restore it")
            (_ "C-c C-c submit"))))

;; -- text (TTY / no-svg) renderer ------------------------------------------- ;;
(defun teamwork--header-chunk (label help command &optional face)
  "A clickable propertized header chunk running COMMAND on mouse-1."
  (let ((map (make-sparse-keymap)))
    (define-key map [header-line mouse-1] command)
    (define-key map [header-line mouse-2] command)
    (propertize label 'face (or face 'teamwork-edit-face)
                'mouse-face 'highlight 'help-echo help
                'keymap map 'pointer 'hand)))

(defun teamwork--header-text (model)
  "Render MODEL as a single clickable text header-line string."
  (let* ((sl (teamwork--state-label))
         (view (plist-get model :view))
         (kind (plist-get model :kind))
         (hidden (plist-get model :hidden))
         (parts (list (propertize (format " %s " (nth 0 sl))
                                  'face (nth 1 sl) 'help-echo (nth 2 sl)))))
    (dolist (b (teamwork--header-buttons view kind))
      (let* ((style (nth 3 b))
             (face (pcase (plist-get style :role)
                     ('refetch 'teamwork-new-face)
                     ('toggle (if (plist-get style :on) 'teamwork-edit-face 'shadow))
                     (_ 'teamwork-edit-face))))
        (push (teamwork--header-chunk (format "[%s]" (nth 0 b)) (nth 1 b) (nth 2 b) face)
              parts)))
    (when hidden
      (push (propertize "hidden:" 'face 'shadow) parts)
      (dolist (h hidden)
        (let ((id (car h)))
          (push (teamwork--header-chunk
                 (format "%s✕" (if (string-empty-p (cdr h)) id (cdr h)))
                 (format "Click to restore hidden project %s" id)
                 (lambda () (interactive) (teamwork--unhide-project id))
                 'teamwork-delete-face)
                parts))))
    (concat " " (mapconcat #'identity (nreverse parts) "  "))))

;; -- SVG renderer (GUI, when svg-header is loaded) --------------------------- ;;
(defvar-local teamwork--header-svg-boxes nil
  "Click boxes for the SVG header: list of (X0 Y0 X1 Y1 COMMAND) in pixels.")

(defun teamwork--header-svg-click (event)
  "Dispatch a click on the teamwork SVG header to its button, by pixel geometry."
  (interactive "e")
  (let* ((posn (event-start event))
         (win (posn-window posn))
         (xy (posn-object-x-y posn)))
    (when (and (windowp win) xy)
      (with-selected-window win
        (let ((dx (car xy)) (dy (cdr xy)))
          (when-let ((hit (seq-find (lambda (b)
                                      (and (>= dx (nth 0 b)) (< dx (nth 2 b))
                                           (>= dy (nth 1 b)) (< dy (nth 3 b))))
                                    teamwork--header-svg-boxes)))
            (call-interactively (nth 4 hit))))))))

(defvar teamwork--header-svg-keymap
  (let ((m (make-sparse-keymap)))
    (define-key m [header-line mouse-1] #'teamwork--header-svg-click)
    m)
  "Keymap on the teamwork SVG header line.")

(defun teamwork--header-svg (model)
  "Render MODEL as a tall multi-row SVG header image; record click boxes."
  (require 'svg)
  (let* ((width (max 1 (window-pixel-width)))
         (cw (frame-char-width)) (fh (frame-char-height))
         (font-size (or (and (boundp 'mp/header-svg-font-size) mp/header-svg-font-size)
                        (ignore-errors (default-font-height)) (round (* cw 1.7))))
         (family (or (face-attribute 'default :family nil 'default) "monospace"))
         (bg (or (mp/header-line-background) "#1a1b26"))
         (fg (or (mp/header-line-buffer-foreground) "#c0caf5"))
         (dim (or (mp/header-line-position-foreground) "#7f8496"))
         (btn-bg (or (face-attribute 'mode-line :background nil t) "#2a2e38"))
         (accent (or (face-attribute 'teamwork-edit-face :foreground nil t) "#4fa6ff"))
         (danger (or (face-attribute 'teamwork-delete-face :foreground nil t) "#ff9a9a"))
         (bd dim)                       ; subtle border for resting buttons
         (pad-x 8) (pad-y 5)
         (line-h (+ fh 4))
         (base-off (round (+ (/ (- line-h font-size) 2.0) (* font-size 0.8))))
         (hp (max 4 (round (* cw 0.6))))
         (gap (max 6 (round (* cw 0.7))))
         (rx (round (* fh 0.28)))
         (nbsp (char-to-string #xA0))
         (sl (teamwork--state-label))
         (view (plist-get model :view))
         (kind (plist-get model :kind))
         (hidden (plist-get model :hidden))
         (ops nil) (boxes nil)
         (x pad-x) (y pad-y))
    (cl-labels
        ((tw (s) (* (length s) cw))
         (emit-text (s cx cy col)
           (push (list 'text s cx (+ cy base-off) col) ops))
         (new-row () (setq x pad-x y (+ y line-h)))
         (emit-btn (s col bcol cmd &optional border)
           (let ((w (+ (tw s) (* 2 hp))))
             (when (and (> x pad-x) (> (+ x w) (- width pad-x)))
               (new-row))
             (when bcol (push (list 'rect x (+ y 2) w (- line-h 4) bcol border) ops))
             (emit-text s (+ x hp) y col)
             (when cmd (push (list x y (+ x w) (+ y line-h) cmd) boxes))
             (setq x (+ x w gap)))))
      ;; row 0: state pill + action buttons
      (emit-btn (nth 0 sl)
                (or (plist-get (nth 1 sl) :foreground) bg)
                (or (plist-get (nth 1 sl) :background) btn-bg) nil)
      (dolist (b (teamwork--header-buttons view kind))
        (let* ((style (nth 3 b))
               (role (plist-get style :role)))
          ;; Refetch reads as an accent button; a view toggle glows accent while
          ;; ON (completed items shown) and is a plain resting button while OFF.
          (pcase role
            ('refetch (emit-btn (nth 0 b) accent btn-bg (nth 2 b) accent))
            ('toggle  (if (plist-get style :on)
                          (emit-btn (nth 0 b) accent btn-bg (nth 2 b) accent)
                        (emit-btn (nth 0 b) fg btn-bg (nth 2 b) bd)))
            (_        (emit-btn (nth 0 b) fg btn-bg (nth 2 b) bd)))))
      ;; row 1: help / hint line
      (new-row)
      (emit-text (teamwork--header-hint kind (nth 2 sl)) x y dim)
      ;; rows 2+: hidden-project chips (wrap as needed)
      (when hidden
        (new-row)
        (emit-text "hidden:" x y dim)
        (setq x (+ x (tw "hidden:") gap))
        (dolist (h hidden)
          (let ((id (car h)))
            (emit-btn (format "%s ✕" (if (string-empty-p (cdr h)) id (cdr h)))
                      danger btn-bg
                      (lambda () (interactive) (teamwork--unhide-project id))
                      danger)))))          ; red outline → clearly a restore button
    (let* ((height (+ y line-h pad-y))
           (svg (svg-create width height)))
      (svg-rectangle svg 0 0 width height :fill bg)
      (dolist (op (nreverse ops))
        (pcase (car op)
          ('rect (pcase-let ((`(,_ ,rx0 ,ry0 ,rw ,rh ,col ,bd0) op))
                   (apply #'svg-rectangle svg rx0 ry0 rw rh :fill col :rx rx
                          (when bd0 (list :stroke bd0 :stroke-width 1)))))
          ('text (pcase-let ((`(,_ ,s ,tx ,ty ,col) op))
                   (svg-text svg (replace-regexp-in-string " " nbsp s)
                             :x tx :y ty :fill col :font-family family
                             :font-size font-size :font-weight "normal")))))
      (setq teamwork--header-svg-boxes (nreverse boxes))
      (propertize " " 'display (svg-image svg :ascent 'center :scale 1)
                  'keymap teamwork--header-svg-keymap 'pointer 'hand))))

(defun teamwork--header-render ()
  "Return the header-line value for a teamwork buffer (SVG when available).
Memoized on (state, error, header block, width); guarded so a rendering error
degrades to a short message rather than breaking redisplay."
  (condition-case err
      (let* ((prefix (teamwork--header-prefix))
             (graphic (and (display-graphic-p) (featurep 'svg-header)
                           (fboundp 'mp/header-line-background)))
             (w (if graphic (window-pixel-width) (window-width)))
             (sig (list teamwork--data-state teamwork--state-msg teamwork--kind
                        teamwork--header-state prefix w graphic teamwork--view-override)))
        (if (and teamwork--header-cache (equal (car teamwork--header-cache) sig))
            (cdr teamwork--header-cache)
          (let* ((model (teamwork--header-model prefix))
                 (out (if graphic (teamwork--header-svg model)
                        (teamwork--header-text model))))
            (setq teamwork--header-cache (cons sig out))
            out)))
    (error (format " teamwork header: %s " (error-message-string err)))))

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
                 (teamwork--load-header-state buffer)
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
        (teamwork--set-state 'stale)
        (teamwork--load-header-state buffer)))
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
                (propertize "pending changes (preview only · q to close)\n" 'face 'font-lock-comment-face)
                (or teamwork--plan-cache (propertize "  computing…\n" 'face 'shadow))
                rule "\n"
                (propertize (format "%d logs · %d:%02d total\n"
                                    (length logs) (/ total 60) (% total 60)) 'face 'bold)))
      (unless (derived-mode-p 'teamwork-logs-mode) (teamwork-logs-mode))
      (if (and win wstart)
          (progn (set-window-start win (min wstart (point-max)) t)
                 (set-window-point win (min (or wpt (point-min)) (point-max))))
        (goto-char (point-min))))))

(defun teamwork--stop-log-timer ()
  (when teamwork--log-timer (cancel-timer teamwork--log-timer))
  (when (timerp teamwork--plan-timer) (cancel-timer teamwork--plan-timer))
  (setq teamwork--log-timer nil teamwork--log-tick nil teamwork--plan-timer nil))

(defun teamwork--log-preview-close ()
  "Stop the log-preview timer, close its side window and kill the buffer."
  (interactive)
  (teamwork--stop-log-timer)
  (when-let ((w (get-buffer-window teamwork-logs-buffer))) (delete-window w))
  (when (get-buffer teamwork-logs-buffer) (kill-buffer teamwork-logs-buffer)))

(define-derived-mode teamwork-logs-mode special-mode "TW-Logs"
  "Read-only side window listing a timesheet buffer's time logs.  `q' closes it.")
(define-key teamwork-logs-mode-map (kbd "q") #'teamwork--log-preview-close)

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
      (teamwork--log-preview-close)
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

(define-derived-mode teamwork-changes-mode special-mode "TW-Changes"
  "Read-only side window previewing a teamwork buffer's pending changes.
`q' closes it.")
(define-key teamwork-changes-mode-map (kbd "q") #'teamwork--changes-preview-close)

(defun teamwork--changes-render (text)
  "Render TEXT (a pending-changes summary) into the changes side buffer."
  (let ((buf (get-buffer-create teamwork-changes-buffer)))
    (with-current-buffer buf
      (let ((inhibit-read-only t) (buffer-read-only nil))
        (erase-buffer)
        (insert (propertize "pending changes (preview only — C-c C-c to submit · q to close)\n\n"
                            'face 'font-lock-comment-face))
        (insert (or text (propertize "  computing…\n" 'face 'shadow))))
      (unless (derived-mode-p 'teamwork-changes-mode) (teamwork-changes-mode)))))

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

(defun teamwork--changes-preview-close ()
  "Stop the changes-preview timer, close its side window and kill the buffer."
  (interactive)
  (teamwork--changes-stop)
  (when-let ((w (get-buffer-window teamwork-changes-buffer))) (delete-window w))
  (when (get-buffer teamwork-changes-buffer) (kill-buffer teamwork-changes-buffer)))

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
      (teamwork--changes-preview-close)
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
(defun teamwork--restyle-completed ()
  "Dim + checkmark headings of completed task lists (:COMPLETED: set).
Purely cosmetic overlays over the fetched completion state (shown only when the
management \"Lists: all\" view is on); re-run on fill.  Completed *tasks* carry an
org DONE keyword instead, which org fontifies/strikes on its own."
  (remove-overlays (point-min) (point-max) 'teamwork-completed t)
  (org-with-wide-buffer
   (goto-char (point-min))
   (while (re-search-forward org-heading-regexp nil t)
     (when (org-entry-get (point) "COMPLETED")
       (let ((ov (make-overlay (line-beginning-position) (line-end-position))))
         (overlay-put ov 'teamwork-completed t)
         (overlay-put ov 'face 'teamwork-completed-face)
         (overlay-put ov 'after-string
                      (propertize " ✓" 'face 'teamwork-completed-face)))))))

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
      (teamwork--fold-drawers)
      (teamwork--restyle-completed))))

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
deleted project heading updates the hidden-project prefs (restoring one goes
through the `unhide' command instead)."
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
heading text, and label tasks with a `<a,b>' prefix on the task heading (C-c C-b).
Which projects appear is the per-account filter (see `teamwork-filter').  C-c C-c
submits."
  (interactive)
  (let ((account (or (teamwork--buffer-account (get-buffer teamwork-management-buffer))
                     (teamwork--choose-account "Teamwork account (manage): "))))
    (teamwork--fetch (get-buffer-create teamwork-management-buffer) "manage" "manage" account
                     (list "manage") "submit" #'teamwork--enable-management-mode t)))

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

(defun teamwork--buffer-prop-values (key)
  "Distinct, non-empty values of drawer property KEY across every heading in the
current buffer.  Comma-separated cells are split, so a task labelled \"a, b\"
contributes both \"a\" and \"b\".  Used to seed a picker with the values other
already-loaded tasks use, so common labels / assignees / urgencies are one
keystroke away without a round-trip."
  (let (vals)
    (save-excursion
      (org-map-entries
       (lambda ()
         (let ((v (org-entry-get nil key)))
           (when (and v (not (string-empty-p (string-trim v))))
             (dolist (item (split-string v "[,]+" t "[ \t]+"))
               (push item vals)))))))
    (delete-dups (nreverse vals))))

(defmacro teamwork--with-task-heading (&rest body)
  "Move point to the enclosing task heading, then eval BODY there.
Signals a `user-error' when point is not inside a task subtree.  Wrapped in
`save-excursion', so point is restored afterwards."
  (declare (indent 0) (debug t))
  `(save-excursion
     (unless (ignore-errors (org-back-to-heading t) t)
       (user-error "Point is not on a task"))
     (unless (org-entry-get nil "TASK_ID")   ; non-inherited: THIS heading is a task
       (user-error "Point is not on a task heading (no :TASK_ID: here)"))
     ,@body))

;; Each picker prompts for and sets one property on the task at point.  They are
;; shared by the dispatcher (`teamwork-set-property') and the dedicated commands.
;; Labels live in the heading in a management buffer — a `<a,b>` prefix before the
;; task title (rendered/parsed by the sidecar) — but stay in the :LABELS: drawer in
;; a timesheet.  These helpers read/write whichever form this buffer uses so the
;; picker and completion source don't have to care.
(defun teamwork--heading-label-prefix ()
  "The task heading text at point with its leading `<...>' label prefix stripped,
and the labels it carried.  Returns (REST . LABELS)."
  (save-excursion
    (org-back-to-heading t)
    (let ((h (org-get-heading t t t t)))
      (if (string-match "\\`<\\([^>]*\\)>[ \t]*" h)
          (cons (substring h (match-end 0))
                (split-string (match-string 1 h) "[,]+" t "[ \t]+"))
        (cons h nil)))))

(defun teamwork--manage-buffer-p ()
  (equal teamwork--kind "manage"))

(defun teamwork--current-labels ()
  "Labels on the task at point: from the `<...>' title prefix in a management
buffer, else the :LABELS: drawer."
  (if (teamwork--manage-buffer-p)
      (cdr (teamwork--heading-label-prefix))
    (teamwork--current-prop-list "LABELS")))

(defun teamwork--set-labels (labels)
  "Set the task at point's LABELS: the `<...>' title prefix in a management buffer
\(empty LABELS drops the prefix), else the :LABELS: drawer."
  (if (teamwork--manage-buffer-p)
      (save-excursion
        (org-back-to-heading t)
        (let ((rest (car (teamwork--heading-label-prefix)))
              (prefix (if labels (concat "<" (mapconcat #'identity labels ",") ">") "")))
          (org-edit-headline (concat prefix rest))))
    (teamwork--put-property "LABELS" (mapconcat #'identity labels ", "))))

(defun teamwork--buffer-label-values ()
  "Distinct labels used across the buffer, from title prefixes in a management
buffer, else the :LABELS: drawers."
  (if (teamwork--manage-buffer-p)
      (let (vals)
        (save-excursion
          (org-map-entries
           (lambda ()
             (let ((h (org-get-heading t t t t)))
               (when (string-match "\\`<\\([^>]*\\)>" h)
                 (dolist (x (split-string (match-string 1 h) "[,]+" t "[ \t]+"))
                   (push x vals)))))))
        (delete-dups (nreverse vals)))
    (teamwork--buffer-prop-values "LABELS")))

(defun teamwork--pick-labels ()
  "Prompt for and set the task's labels (tags), completing over the labels
already used in this buffer plus the account's configured tags; custom values
allowed, empty clears.  In a management buffer the labels are a `<a,b>' prefix
on the task heading; in a timesheet they are the :LABELS: drawer property."
  (let* ((all (delete-dups (append (teamwork--buffer-label-values)
                                   (teamwork--json-or-nil "tags"))))
         (cur (teamwork--current-labels))
         (chosen (completing-read-multiple
                  "Tags (comma-separated, empty clears): " all nil nil
                  (and cur (mapconcat #'identity cur ",")))))
    (teamwork--set-labels chosen)))

(defun teamwork--pick-urgency ()
  "Prompt for and set the task's :URGENCY: (priority) from the fixed set, seeded
with any values already used in the buffer (Teamwork only accepts these, so the
match is required)."
  (let ((all (delete-dups (append teamwork-priorities
                                  (teamwork--buffer-prop-values "URGENCY")))))
    (teamwork--put-property "URGENCY" (completing-read "Priority: " all nil t))))

(defun teamwork--pick-due ()
  "Prompt for and set the task's :DUE: date via the org date picker (an empty
answer clears it)."
  (teamwork--put-property "DUE" (org-read-date nil nil nil "Due date: ")))

(defun teamwork--pick-assignee ()
  "Prompt for and set the task's :ASSIGNEE:, completing over the project's people
\(the `people' endpoint) plus assignees already used in this buffer; a name that
matches neither is still accepted but rejected at submit.  Empty clears."
  (let* ((people (teamwork--json-or-nil "people"))
         (names (delete-dups
                 (append (delq nil (mapcar (lambda (p) (alist-get 'name p)) people))
                         (teamwork--buffer-prop-values "ASSIGNEE"))))
         (cur (teamwork--current-prop-list "ASSIGNEE"))
         (chosen (completing-read-multiple
                  "Assignees (comma-separated, empty clears): " names nil nil
                  (and cur (mapconcat #'identity cur ",")))))
    (teamwork--put-property "ASSIGNEE" (mapconcat #'identity chosen ", "))))

;;;###autoload
(defun teamwork-set-property ()
  "Set a property on the task at point, completing over the available values.
A one-stop dispatcher over the same pickers as the dedicated commands
\(`teamwork-set-labels', `teamwork-set-due', `teamwork-set-urgency',
`teamwork-set-assignee').  Priority is a fixed list, the due date uses the org
calendar, and tags / assignees complete against values already in the buffer
plus the account's tags / project people (you can still type a new one).  In a
timesheet buffer only Tags applies.  The done state is not here — use org's own
C-c C-t (`org-todo') on the task heading to complete/reopen it."
  (interactive)
  (unless (org-entry-get nil "TASK_ID" t)
    (user-error "Point is not on a task (no TASK_ID here or above)"))
  (let* ((manage (equal teamwork--kind "manage"))
         (choices (if manage '("Tags" "Due date" "Priority" "Assignee") '("Tags")))
         (prop (if (cdr choices) (completing-read "Set property: " choices nil t) "Tags")))
    (pcase prop
      ("Due date" (teamwork--pick-due))
      ("Priority" (teamwork--pick-urgency))
      ("Tags"     (teamwork--pick-labels))
      ("Assignee" (teamwork--pick-assignee)))
    (message "Teamwork: %s set — C-c C-l previews, C-c C-c submits." prop)))

;; --- Dedicated per-property commands ---------------------------------------- ;;
;; C-c C-b/C-d/C-u/C-a jump straight to one property, skipping the dispatcher
;; menu.  Labels apply everywhere; due/urgency/assignee are management-only (a
;; timesheet submit ignores them).
(defun teamwork--set-one-property (picker label &optional manage-only)
  "Run PICKER on the enclosing task heading, then echo LABEL.
When MANAGE-ONLY, refuse outside a management buffer, where the property would
be dropped by the submit."
  (when (and manage-only (not (equal teamwork--kind "manage")))
    (user-error "%s can only be set in a management buffer" label))
  (teamwork--with-task-heading (funcall picker))
  (message "Teamwork: %s set — C-c C-l previews, C-c C-c submits." label))

;;;###autoload
(defun teamwork-set-labels ()
  "Set the task's labels (tags), completing over buffer + account values.
In a management buffer the labels are a `<a,b>' prefix on the task heading; in
a timesheet they are the :LABELS: drawer property.  Point may sit anywhere in
the task's subtree.  Custom values are allowed, and an empty answer clears them."
  (interactive)
  (teamwork--set-one-property #'teamwork--pick-labels "Labels"))

;;;###autoload
(defun teamwork-set-urgency ()
  "Set the task's :URGENCY: (priority) from the fixed set (management only)."
  (interactive)
  (teamwork--set-one-property #'teamwork--pick-urgency "Priority" t))

;;;###autoload
(defun teamwork-set-due ()
  "Set the task's :DUE: date via the org date picker (management only)."
  (interactive)
  (teamwork--set-one-property #'teamwork--pick-due "Due date" t))

;;;###autoload
(defun teamwork-set-assignee ()
  "Set the task's :ASSIGNEE:, completing over project people + buffer values
\(management only)."
  (interactive)
  (teamwork--set-one-property #'teamwork--pick-assignee "Assignee" t))

;; Task done state is an org TODO/DONE keyword on the heading, so `org-todo'
;; (C-c C-t, org's own binding) cycles it — no custom toggle command, and org
;; fontifies/strikes the completed headings itself.  The heading's keyword
;; round-trips through the sidecar, so C-c C-c submits the completion.

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
        ((string-prefix-p "move" type) 'teamwork-edit-face)
        ((string-prefix-p "delete" type) 'teamwork-delete-face)
        (t 'default)))

(defun teamwork--action-icon (type)
  "Node icon for action TYPE (task list / task / log)."
  (cond ((string-match-p "tasklist" type) teamwork-icon-tasklist)
        ((string-match-p "task" type) teamwork-icon-task)
        (t teamwork-icon-log)))

(defun teamwork--preview-close ()
  "Close the submit-preview window and kill its buffer."
  (interactive)
  (when-let ((buf (get-buffer teamwork-preview-buffer)))
    (when-let ((w (get-buffer-window buf))) (ignore-errors (delete-window w)))
    (kill-buffer buf)))

(defun teamwork--preview-defocused-p ()
  "Non-nil when the submit preview is shown but is not the selected window.
Selection resting in the minibuffer (the yes/no confirm prompt, echoed messages)
does not count as defocused, so the prompt never dismisses the preview."
  (let ((win (get-buffer-window teamwork-preview-buffer)))
    (and win
         (not (eq win (selected-window)))
         (not (window-minibuffer-p (selected-window))))))

(defun teamwork--preview-selection-changed (&optional _frame)
  "Close the submit preview once it stops being the selected window.
The close is deferred (deleting a window from inside a selection-change hook is
unsafe) and re-checks focus when it fires, so a preview re-focused in the
meantime survives."
  (when (teamwork--preview-defocused-p)
    (run-at-time 0 nil (lambda ()
                         (when (teamwork--preview-defocused-p)
                           (teamwork--preview-close))))))

(define-derived-mode teamwork-submit-mode special-mode "TW-Submit"
  "Read-only teamwork submit preview / live progress buffer.
It takes focus when shown, `q' closes it, and it closes when it loses focus."
  (setq-local window-selection-change-functions
              (list #'teamwork--preview-selection-changed)))
(define-key teamwork-submit-mode-map (kbd "q") #'teamwork--preview-close)

(defun teamwork--preview-show (buf)
  "Display submit-preview BUF below the selected window and give it focus."
  (let ((w (display-buffer-below-selected buf nil)))
    (when (window-live-p w) (select-window w))
    w))

(defun teamwork--render-preview (actions)
  "Render ACTIONS into the preview buffer; return it. Records status markers."
  (let ((buf (get-buffer-create teamwork-preview-buffer)))
    (with-current-buffer buf
      (unless (derived-mode-p 'teamwork-submit-mode) (teamwork-submit-mode))
      (let ((inhibit-read-only t))
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
                (insert "…"))           ; single-char status cell (stable width)
              (insert "  "
                      (propertize (teamwork--action-icon type) 'face face) "  "
                      (propertize (or (alist-get 'summary a) type) 'face face) "\n")
              (setq i (1+ i))))
          (setq-local teamwork--markers vec))
        (goto-char (point-min))))
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
         (when-let ((pbuf (get-buffer teamwork-preview-buffer)))
           (with-current-buffer pbuf
             (let ((inhibit-read-only t))
               (goto-char (point-max))
               (unless (zerop (process-exit-status proc))
                 (insert (format "\nsidecar exited %d; see %s\n"
                                 (process-exit-status proc) (buffer-name errbuf)))))))
         ;; reload the buffer from the (partially) applied file; it is now current
         (when (and (buffer-live-p target) (file-readable-p out))
           (let ((ob (generate-new-buffer " *teamwork-reload*")))
             (with-current-buffer ob (insert-file-contents out))
             (teamwork--fill-buffer target ob mode-fn)
             (kill-buffer ob))
           (with-current-buffer target (teamwork--set-state 'fresh))
           (teamwork--load-header-state target))
         (ignore-errors (delete-file tmp))
         (ignore-errors (delete-file out)))))))

(defun teamwork--handle-event (ev)
  "Update the preview buffer from a single stream event EV (an alist).
No-op if the preview was closed (its window lost focus) — apply still runs."
  (when-let ((pbuf (get-buffer teamwork-preview-buffer)))
   (with-current-buffer pbuf
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
                                        " — ABORTED; unapplied changes kept in the buffer" ""))))))))))

;;;###autoload
(defun teamwork-submit ()
  "Compute the diff for the current teamwork buffer (timesheet or management),
review it, then apply.  Preview appears in a split below; on confirm it applies
with live progress.

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
        (teamwork--preview-show (get-buffer teamwork-preview-buffer))
        (delete-file tmp) (delete-file out)
        (message "Teamwork: fix the problems shown above (q to close)."))
       ((null actions)
        (delete-file tmp) (delete-file out)
        (message "Teamwork: no changes to submit."))
       (t
        (let ((pbuf (teamwork--render-preview actions)))
          (teamwork--preview-show pbuf)
          (if (yes-or-no-p (format "Apply %d change(s) to Teamwork%s? " (length actions)
                                   (if account (format " [%s]" account) "")))
              ;; keep focus on the preview so its live progress stays in view
              (progn (teamwork--apply tmp out target submit-cmd account)
                     (when (window-live-p (get-buffer-window pbuf))
                       (select-window (get-buffer-window pbuf))))
            ;; declined: close preview window, keep the source buffer
            (teamwork--preview-close)
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
