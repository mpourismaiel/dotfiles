;;; mp-workspaces.el --- Perspective workspaces, projectile, persistence, dashboard -*- lexical-binding: t; -*-

;;; Projectile

(use-package projectile
  :demand t
  :config
  (setq projectile-known-projects-file (expand-file-name "projectile-bookmarks.eld" mp/var-dir)
        projectile-cache-file (expand-file-name "projectile.cache" mp/var-dir)
        projectile-auto-discover nil
        projectile-enable-caching t)
  ;; `server/Pipfile' must count as a project root before `.git' does
  ;; (monorepos like root-backend).
  (add-to-list 'projectile-project-root-files "Pipfile")
  ;; A Godot project is rooted at its `project.godot', even before it has a VCS.
  (add-to-list 'projectile-project-root-files "project.godot")
  (projectile-mode 1))

;; project.el: prefer language-specific roots inside monorepos over the
;; repository root (port of the Project Root Behavior section).
(with-eval-after-load 'project
  (defun mp/project-root-from-markers (dir markers)
    "Return the first project root above DIR matching one of MARKERS."
    (when-let ((root (seq-some (lambda (marker)
                                 (locate-dominating-file dir marker))
                               markers)))
      (cons 'transient root)))

  (add-hook 'project-find-functions
            (lambda (dir)
              (or (mp/project-root-from-markers dir '("go.mod"))
                  (mp/project-root-from-markers dir '("Cargo.toml"))
                  (mp/project-root-from-markers dir '("package.json"))
                  (mp/project-root-from-markers
                   dir
                   '("Pipfile" "pyproject.toml" "setup.py" "requirements.txt"))
                  (mp/project-root-from-markers dir '(".git"))))))

;;; Perspective

(use-package perspective
  :demand t
  :init
  (setq persp-suppress-no-prefix-key-warning t
        persp-initial-frame-name "main"
        persp-sort 'created
        persp-state-default-file (expand-file-name "persp-state" mp/var-dir)
        persp-modestring-short t)
  :config
  (persp-mode 1))

;; Everything below calls persp-* at command time, but the dashboard/session code
;; at the bottom of this file needs perspective loaded.
(elpaca-wait)

;;; Workspace command layer (successor of Doom's +workspace API)

(defun mp/workspace-current-name ()
  "Name of the current workspace."
  (persp-current-name))

(defun mp/workspace-names ()
  "Workspace names in CREATION order (oldest first).
`persp-names' with `persp-sort' 'created returns newest-first; positional
indices (labels, SPC TAB 1..9) must be stable, so reverse it: new
workspaces take the next index instead of renumbering everything."
  (reverse (persp-names)))

(defun mp/workspace--show-fresh ()
  "Make a newly-created workspace visibly fresh: one window, dashboard shown."
  (delete-other-windows)
  (switch-to-buffer (mp/dashboard-buffer)))

(defun mp/workspace-new ()
  "Create and switch to a fresh, project-less workspace.
Named `empty workspace - N', where N counts up from the number of
workspaces that already exist — so a new workspace never inherits a name
(or project) that a previous one used.  Opens on the dashboard overview so
the switch is obvious."
  (interactive)
  (let* ((names (persp-names))
         (n (1+ (length names))))
    (while (member (format "empty workspace - %d" n) names) (cl-incf n))
    (let ((wname (format "empty workspace - %d" n)))
      ;; Belt and braces: make sure no stale project association survives.
      (remhash wname mp/workspace-project-roots)
      (persp-switch wname)
      (mp/workspace--show-fresh))))

(defun mp/workspace-new-named (name)
  "Create and switch to workspace NAME, showing the dashboard overview."
  (interactive (list (read-string "Workspace name: ")))
  (let ((existed (member name (persp-names))))
    (persp-switch name)
    (unless existed (mp/workspace--show-fresh))))

(defun mp/workspace-rename ()
  (interactive)
  (call-interactively #'persp-rename))

(defun mp/workspace-kill ()
  "Kill the current workspace.
Killing the last remaining workspace replaces it with a fresh one showing
the dashboard overview instead of leaving a dead frame."
  (interactive)
  (let ((name (persp-current-name)))
    (remhash name mp/workspace-project-roots)
    (if (> (length (persp-names)) 1)
        (persp-kill name)
      ;; Last one: create a replacement first, then kill the old.
      (let ((fresh (if (equal name "main") "#1" "main")))
        (persp-switch fresh)
        (persp-kill name)
        (mp/workspace--show-fresh)))
    (message "Killed workspace %s" name)))

(defun mp/workspace-delete (name)
  "Kill workspace NAME (prompts)."
  (interactive (list (completing-read "Delete workspace: " (persp-names))))
  (persp-kill name))

(defun mp/workspace-kill-session ()
  "Kill every workspace, returning to a fresh initial one."
  (interactive)
  (persp-switch persp-initial-frame-name)
  (dolist (name (persp-names))
    (unless (equal name persp-initial-frame-name)
      (persp-kill name)))
  (message "Session cleared"))

(defun mp/workspace-other ()
  "Switch to the previously active workspace."
  (interactive)
  (persp-switch-last))

(defun mp/workspace--offset (offset)
  (let* ((names (mp/workspace-names))
         (pos (seq-position names (persp-current-name))))
    (persp-switch (nth (mod (+ pos offset) (length names)) names))))

(defun mp/workspace-switch-left ()  (interactive) (mp/workspace--offset -1))
(defun mp/workspace-switch-right () (interactive) (mp/workspace--offset 1))

(defun mp/workspace-switch-to-index (i)
  (let ((names (mp/workspace-names)))
    (if (< i (length names))
        (persp-switch (nth i names))
      (user-error "No workspace #%d" (1+ i)))))

(dotimes (i 9)
  (let ((idx i))
    (defalias (intern (format "mp/workspace-switch-to-%d" idx))
      (lambda () (interactive) (mp/workspace-switch-to-index idx))
      (format "Switch to workspace %d." (1+ idx)))))

(defun mp/workspace-switch-to-final ()
  (interactive)
  (persp-switch (car (last (mp/workspace-names)))))

(defun mp/workspace--project-root (name)
  "Best-known project root for workspace NAME.
Prefers the explicit assignment; falls back to the project of the first
file-visiting buffer in that workspace."
  (or (gethash name mp/workspace-project-roots)
      (when-let* ((persp (gethash name (perspectives-hash)))
                  (file (seq-some #'buffer-file-name (persp-buffers persp))))
        (locate-dominating-file file ".git"))))

(defun mp/workspace--empty-name (name)
  "Display name for a project-less workspace NAME: `empty workspace - NAME'.
Auto-created workspaces are already named `empty workspace - N', so avoid
doubling the prefix in that case."
  (if (string-prefix-p "empty workspace" name)
      name
    (format "empty workspace - %s" name)))

(defun mp/workspace--label (name)
  "Display label for workspace NAME.
With a project assigned: \"INDEX project\", where INDEX is the 1-based
position in `persp-names' (matching the SPC TAB 1..9 switch keys, so
killing a middle workspace renumbers the ones after it).  With no project:
`empty workspace - NAME'."
  (let ((idx (1+ (or (seq-position (mp/workspace-names) name) 0)))
        (root (mp/workspace--project-root name)))
    (if root
        (format "%d %s" idx (file-name-nondirectory (directory-file-name root)))
      (mp/workspace--empty-name name))))

;; Opening a project via `SPC p p' (projectile) assigns it to the current
;; workspace, so labels/dashboard know the association without using bundles.
(defun mp/workspace--record-project ()
  (when-let* ((root (and (fboundp 'projectile-project-root)
                         (projectile-project-root))))
    (puthash (persp-current-name) (file-name-as-directory root)
             mp/workspace-project-roots)))

(with-eval-after-load 'projectile
  (add-hook 'projectile-after-switch-project-hook #'mp/workspace--record-project))

(defun mp/workspace-display ()
  "Show the workspace list (with project names) in the echo area."
  (interactive)
  (let ((current (persp-current-name)))
    (message "%s"
             (mapconcat
              (lambda (name)
                (if (equal name current)
                    (propertize (format "[%s]" (mp/workspace--label name))
                                'face 'success)
                  (format " %s " (mp/workspace--label name))))
              (mp/workspace-names) " "))))

(defun mp/workspace-switch ()
  "Switch to a workspace picked from a labelled list.
Shows the same `INDEX project' labels, in the same creation order, as
`mp/workspace-display' (SPC TAB TAB) — not raw perspective names."
  (interactive)
  (let* ((names  (mp/workspace-names))
         (labels (mapcar #'mp/workspace--label names))
         ;; A table with `display-sort-function' identity keeps creation order
         ;; (prescient won't reorder it: vertico-prescient-override-sorting nil).
         (table  (lambda (str pred action)
                   (if (eq action 'metadata)
                       '(metadata (display-sort-function . identity)
                                  (category . mp-workspace))
                     (complete-with-action action labels str pred))))
         (choice (completing-read "Workspace: " table nil t))
         (idx    (seq-position labels choice #'equal)))
    (when idx (persp-switch (nth idx names)))))

(defun mp/workspace-close-window-or-workspace ()
  "Close the window; if it is the last one, kill the workspace."
  (interactive)
  (if (one-window-p)
      (mp/workspace-kill)
    (mp/close-window-preserve-buffer)))

;;; Project <-> workspace association (port of the Project management section)

(defun mp/current-workspace-project-root ()
  "Return the project root explicitly assigned to the current workspace."
  (gethash (mp/workspace-current-name) mp/workspace-project-roots))

(defun mp/open-project-root (project-dir)
  "Open PROJECT-DIR without Projectile's project-action prompt."
  (let* ((dir (file-name-as-directory (expand-file-name project-dir)))
         (preferred-files '("README.md" "package.json" "Cargo.toml" "pyproject.toml"))
         (file (seq-find
                (lambda (name)
                  (file-exists-p (expand-file-name name dir)))
                preferred-files)))
    (unless (file-directory-p dir)
      (user-error "Project directory does not exist: %s" dir))
    (projectile-add-known-project dir)
    (puthash (persp-current-name) dir mp/workspace-project-roots)
    (setq default-directory dir)
    (if file
        (find-file (expand-file-name file dir))
      (dired dir))))

(defun mp/open-project-bundle (bundle-name)
  "Open project bundle BUNDLE-NAME in separate workspaces."
  (interactive
   (list (completing-read "Bundle: " (mapcar #'car mp/project-bundles) nil t)))
  (let ((projects (cdr (assoc bundle-name mp/project-bundles))))
    (unless projects
      (user-error "Unknown bundle: %s" bundle-name))
    (dolist (project projects)
      (let* ((workspace (car project))
             (root (file-name-as-directory (expand-file-name (cdr project)))))
        (persp-switch workspace)
        (puthash workspace root mp/workspace-project-roots)
        (mp/open-project-root root)))))

(defun mp/project-menu ()
  "Project menu with colorized bundles plus Projectile projects."
  (interactive)
  (let* ((bundle-prefix "▶ Bundle: ")
         (bundle-candidates
          (mapcar
           (lambda (bundle)
             (let* ((name (car bundle))
                    (label (concat bundle-prefix name)))
               (cons (propertize label 'face '(:foreground "#a6e3a1" :weight bold))
                     label)))
           mp/project-bundles))
         (project-candidates
          (mapcar
           (lambda (project)
             (let* ((dir (directory-file-name project))
                    (name (file-name-nondirectory dir))
                    (parent (file-name-directory dir))
                    (label (concat parent
                                   (propertize name 'face '(:foreground "#89b4fa" :weight bold)))))
               (cons label project)))
           (projectile-relevant-known-projects)))
         (candidates (append bundle-candidates project-candidates))
         (choice (completing-read "Project: " candidates nil t)))
    (let ((real-value (cdr (assoc choice candidates))))
      (if (string-prefix-p bundle-prefix real-value)
          (mp/open-project-bundle (string-remove-prefix bundle-prefix real-value))
        (projectile-switch-project-by-name real-value)))))

;;; Persistence (new in vanilla: auto save/restore of workspaces)

(defvar mp/workspace-roots-file (expand-file-name "workspace-roots.eld" mp/var-dir))

(defun mp/workspace-save-session ()
  "Save all workspaces (buffers + layouts) and their project associations."
  (interactive)
  (persp-state-save persp-state-default-file)
  (with-temp-file mp/workspace-roots-file
    (let (alist)
      (maphash (lambda (k v) (push (cons k v) alist)) mp/workspace-project-roots)
      (prin1 alist (current-buffer))))
  (message "Workspaces saved (%d)" (length (persp-names))))

(defun mp/workspace-load-session ()
  "Restore workspaces and project associations from the last save."
  (interactive)
  (unless (file-exists-p persp-state-default-file)
    (user-error "No saved workspace session"))
  (persp-state-load persp-state-default-file)
  (when (file-exists-p mp/workspace-roots-file)
    (with-temp-buffer
      (insert-file-contents mp/workspace-roots-file)
      (dolist (pair (read (current-buffer)))
        (puthash (car pair) (cdr pair) mp/workspace-project-roots))))
  (message "Workspaces restored (%d)" (length (persp-names))))

(defun mp/workspace--autosave ()
  "Silent autosave of the workspace session."
  (when (bound-and-true-p persp-mode)
    (with-demoted-errors "workspace autosave: %S"
      (let ((inhibit-message t))
        (mp/workspace-save-session)))))

(add-hook 'kill-emacs-hook #'mp/workspace--autosave 90)
(run-with-idle-timer 300 t #'mp/workspace--autosave)

;; Auto-restore at startup, after elpaca has settled every queue.
;; Under a daemon there is no real frame at init time, so restoring then
;; would unpack the session into the invisible daemon frame — defer to the
;; first client frame instead.
(defun mp/workspace--autorestore ()
  (when (file-exists-p persp-state-default-file)
    (with-demoted-errors "workspace restore: %S"
      (mp/workspace-load-session))))

(defun mp/workspace--autorestore-on-first-frame ()
  (remove-hook 'server-after-make-frame-hook
               #'mp/workspace--autorestore-on-first-frame)
  (mp/workspace--autorestore))

(add-hook 'elpaca-after-init-hook
          (lambda ()
            (if (daemonp)
                (add-hook 'server-after-make-frame-hook
                          #'mp/workspace--autorestore-on-first-frame)
              (mp/workspace--autorestore)))
          95)

;;; Splash (dashboard replacement): workspace + project overview

(defvar mp/dashboard-buffer-name "*dashboard*"
  "Name of the workspace dashboard / fallback buffer.")

(defun mp/dashboard--ghostel-p (buf)
  "Non-nil if BUF is a Ghostel terminal."
  (and (buffer-live-p buf)
       (with-current-buffer buf (derived-mode-p 'ghostel-mode))))

(defun mp/dashboard--agent-p (buf)
  "Non-nil if BUF is an agent-shell buffer."
  (and (buffer-live-p buf)
       (let ((name (buffer-name buf)))
         (or (string-match-p "\\`Agent @ " name)
             (string-prefix-p "*agent-shell" name)
             (with-current-buffer buf (derived-mode-p 'agent-shell-mode))))))

(defface mp/dashboard-item '((t :inherit link :underline nil))
  "Clickable dashboard item — like a link but without the hanging underline."
  :group 'mp)

(defface mp/dashboard-active '((t :inherit link :underline nil :weight bold))
  "The active workspace row in the dashboard list."
  :group 'mp)

(defface mp/dashboard-hl '((t :inherit hl-line :extend t))
  "Highlight for the dashboard link at point.
`:extend' makes it cover whole lines, so multi-line links (agents) are
highlighted across both their lines while keeping the link line and the
description line visually distinct via their own foreground faces."
  :group 'mp)

;; Every clickable item is tagged as a `block' spanning all of its lines (one
;; line for most, two for agents) so the highlight can cover the whole link and
;; `]'/`[' can jump link-to-link.
(defvar mp/dashboard--block-counter 0)

(defmacro mp/dashboard--as-block (&rest body)
  "Run BODY (which inserts one item) and tag its inserted lines as one block."
  (declare (indent 0))
  (let ((start (make-symbol "start")))
    `(let ((,start (point)))
       (prog1 (progn ,@body)
         (put-text-property ,start (point) 'mp/dashboard-block
                            (cl-incf mp/dashboard--block-counter))))))

(defun mp/dashboard--icon (fn name)
  "Nerd-icon glyph NAME via FN, tinted like a heading; \"\" if unavailable."
  (if (fboundp fn)
      (or (ignore-errors (funcall fn name :face 'font-lock-keyword-face)) "")
    ""))

(defun mp/dashboard--heading (icon text)
  "Insert a section heading TEXT prefixed by ICON (a nerd-icon glyph)."
  (insert "  ")
  (unless (string-empty-p icon) (insert icon " "))
  (insert (propertize text 'face 'font-lock-keyword-face) "\n"))

(defun mp/dashboard--line (text &optional face)
  "Insert an indented, non-clickable dashboard TEXT line."
  (insert (propertize (format "    %s\n" text) 'face (or face 'font-lock-comment-face))))

(defun mp/dashboard--human (n)
  "Human-readable token count N: 820 -> 820, 220815 -> 221k, 1000000 -> 1m."
  (cond ((null n) "?")
        ((>= n 1000000) (let ((m (/ n 1e6)))
                          (if (= m (floor m)) (format "%dm" (floor m)) (format "%.1fm" m))))
        ((>= n 1000) (format "%dk" (round (/ n 1000.0))))
        (t (format "%d" n))))

(defun mp/dashboard--duration (secs)
  "Compact duration for SECS: 45 -> 45s, 3232 -> 53m, 7400 -> 2h3m."
  (let* ((s (floor secs)) (h (/ s 3600)) (m (/ (% s 3600) 60)))
    (cond ((> h 0) (format "%dh%dm" h m))
          ((> m 0) (format "%dm" m))
          (t (format "%ds" s)))))

;;;; Buffer -> workspace navigation

(defun mp/dashboard--buffer-workspace (buf)
  "Name of a perspective that owns BUF (preferring the current one), or nil."
  (when (and (bound-and-true-p persp-mode) (fboundp 'perspectives-hash))
    (let* ((cur (persp-current-name))
           (cur-persp (gethash cur (perspectives-hash))))
      (if (and cur-persp (memq buf (persp-buffers cur-persp)))
          cur
        (let (hit)
          (maphash (lambda (name persp)
                     (when (and (not hit) (memq buf (persp-buffers persp)))
                       (setq hit name)))
                   (perspectives-hash))
          hit)))))

(defun mp/dashboard--buffer-workspace-label (buf)
  "Display label of the workspace that owns BUF (e.g. \"2 elvou-app\"), or nil."
  (when-let* ((ws (mp/dashboard--buffer-workspace buf)))
    (mp/workspace--label ws)))

(defun mp/dashboard--goto-buffer (buf)
  "Switch to BUF, first switching to a workspace that owns it (if any)."
  (when (buffer-live-p buf)
    (when-let* ((ws (mp/dashboard--buffer-workspace buf)))
      (unless (equal ws (persp-current-name)) (persp-switch ws)))
    (switch-to-buffer buf)))

;;;; Git

(defun mp/dashboard--git-status (root)
  "Return a plist describing the git repo at ROOT.
Keys: :branch :upstream :ahead :behind :changes, where :changes is the list
of `git status --porcelain' file lines (nil when clean / not a repo)."
  (let* ((default-directory root)
         (lines (ignore-errors
                  (process-lines "git" "status" "--porcelain" "--branch")))
         (head (car lines))
         (changes (cdr lines))
         (branch nil) (upstream nil) (ahead 0) (behind 0))
    (when (and head (string-prefix-p "## " head))
      (let ((h (substring head 3)))
        ;; "branch...upstream [ahead N, behind M]" | "branch" | "HEAD (no branch)"
        (if (string-match "\\`\\(.+?\\)\\.\\.\\.\\([^ ]+\\)\\(?: \\[\\(.*\\)\\]\\)?\\'" h)
            (progn
              (setq branch (match-string 1 h) upstream (match-string 2 h))
              (when-let* ((ab (match-string 3 h)))
                (when (string-match "ahead \\([0-9]+\\)" ab)
                  (setq ahead (string-to-number (match-string 1 ab))))
                (when (string-match "behind \\([0-9]+\\)" ab)
                  (setq behind (string-to-number (match-string 1 ab))))))
          (setq branch h))))
    (list :branch branch :upstream upstream :ahead ahead :behind behind
          :changes changes)))

(defun mp/dashboard--git-face (code)
  "Face for a two-char porcelain status CODE (color by change kind)."
  (let ((c (string-trim code)))
    (cond ((string-prefix-p "?" c)       'font-lock-comment-face) ; untracked
          ((seq-contains-p c ?U)         'error)                  ; conflict
          ((seq-contains-p c ?D)         'error)                  ; deleted
          ((seq-contains-p c ?A)         'success)                ; added
          ((or (seq-contains-p c ?R)
               (seq-contains-p c ?C))    'font-lock-function-name-face) ; renamed/copied
          ((seq-contains-p c ?M)         'warning)                ; modified
          (t                             'default))))

;;;; Agent-shell status

(defvar-local mp/agent--last-prompt-time nil
  "Time the user last submitted a prompt in this agent-shell buffer.
Agent-shell's own `:last-activity-time' also ticks on every incoming
notification, so it can't answer \"how long since I last prompted\"; we
stamp this on `agent-shell-submit' instead.")

(defun mp/agent--stamp-prompt (&rest _)
  "Record the current time as this agent buffer's last prompt submission."
  (when (derived-mode-p 'agent-shell-mode)
    (setq mp/agent--last-prompt-time (current-time))))

(with-eval-after-load 'agent-shell
  (advice-add 'agent-shell-submit :after #'mp/agent--stamp-prompt))

(defun mp/dashboard--agent-runtime (buf)
  "Seconds since BUF's agent session started (parsed from its transcript path)."
  (when-let* ((f (with-current-buffer buf
                   (bound-and-true-p agent-shell--transcript-file)))
              (base (file-name-base f))
              ((string-match
                "\\`\\([0-9]+\\)-\\([0-9]+\\)-\\([0-9]+\\)-\\([0-9]+\\)-\\([0-9]+\\)-\\([0-9]+\\)"
                base)))
    (let ((start (encode-time
                  (list (string-to-number (match-string 6 base))
                        (string-to-number (match-string 5 base))
                        (string-to-number (match-string 4 base))
                        (string-to-number (match-string 3 base))
                        (string-to-number (match-string 2 base))
                        (string-to-number (match-string 1 base))
                        nil -1 nil))))
      (float-time (time-subtract (current-time) start)))))

(defun mp/dashboard--agent-title (buf)
  "The agent session title for BUF, falling back to the buffer name."
  (with-current-buffer buf
    (or (ignore-errors (map-nested-elt (agent-shell--state) '(:session :title)))
        (buffer-name buf))))

(defun mp/dashboard--agent-status (buf)
  "Return (SYMBOL . PROPERTIZED-STRING) for BUF: waiting / running / idle."
  (with-current-buffer buf
    (cond
     ((ignore-errors (agent-shell--permission-pending-p))
      (cons 'waiting (propertize "● waiting for you" 'face 'warning)))
     ((ignore-errors (agent-shell--active-requests-p (agent-shell--state)))
      (cons 'running (propertize "● running" 'face 'success)))
     (t (cons 'idle (propertize "○ idle" 'face 'font-lock-comment-face))))))

(defun mp/dashboard--agent-detail (buf)
  "One-line `model · effort · perms · context · total · since-prompt' for BUF."
  (with-current-buffer buf
    (ignore-errors
      (let* ((state  (agent-shell--state))
             (kind   (map-nested-elt state '(:agent-config :mode-line-name)))
             (model  (agent-shell-get-model-name state))
             (effort (agent-shell-get-thought-level-name state))
             (mode   (agent-shell-get-mode-name state))
             (usage  (map-elt state :usage))
             (used   (map-elt usage :context-used))
             (size   (map-elt usage :context-size))
             (total  (mp/dashboard--agent-runtime buf))
             (since  (when mp/agent--last-prompt-time
                       (float-time (time-subtract (current-time)
                                                  mp/agent--last-prompt-time))))
             (segs
              (delq nil
                    (list
                     (let ((m (replace-regexp-in-string " *(recommended)" "" (or model ""))))
                       (string-trim (format "%s %s" (or kind "") m)))
                     (when effort (format "effort %s" effort))
                     (when mode (format "perms %s" mode))
                     (when (and used size (> size 0))
                       (format "%s/%s (%d%%)" (mp/dashboard--human used)
                               (mp/dashboard--human size)
                               (round (* 100.0 (/ used (float size))))))
                     (when total (format "%s total" (mp/dashboard--duration total)))
                     (when since (format "%s since prompt" (mp/dashboard--duration since)))))))
        (mapconcat #'identity (delete "" segs) "  ·  ")))))

(cl-defun mp/dashboard--item (label action &key (indent "    ") (face 'mp/dashboard-item) help-echo)
  "Insert INDENT then a tight clickable LABEL running ACTION on RET/click.
The newline lives outside the button so its underline (if any) and the
indentation never extend across the line — no more hanging underlines."
  (mp/dashboard--as-block
    (insert indent)
    (insert-text-button label
                        'action action 'follow-link t 'mouse-face 'highlight
                        'face face 'help-echo help-echo)
    (insert "\n")))

;;;; Dashboard mode + workspace switching
;; `n'/`p' really switch the active workspace (so super-menu, magit, agent-shell
;; and everything else agree) while keeping the dashboard on screen for further
;; browsing.  `q' / RET-on-a-row enters a workspace, landing on its last buffer.

(defvar mp/dashboard-mode-map (make-sparse-keymap)
  "Keymap for `mp/dashboard-mode'.")

;; Top-level (not inside the `defvar' initializer) so reloading this file
;; actually updates the bindings — `defvar' won't reassign an already-bound map.
(define-key mp/dashboard-mode-map "n" #'mp/dashboard-switch-next)
(define-key mp/dashboard-mode-map "p" #'mp/dashboard-switch-prev)
(define-key mp/dashboard-mode-map "q" #'mp/dashboard-quit)
(define-key mp/dashboard-mode-map "g" #'mp/dashboard-refresh)
(define-key mp/dashboard-mode-map "]" #'mp/dashboard-next-link)
(define-key mp/dashboard-mode-map "[" #'mp/dashboard-prev-link)

(define-derived-mode mp/dashboard-mode special-mode "Dashboard"
  "Major mode for the workspace overview dashboard."
  ;; Follow point with a block-aware highlight (covers both lines of an agent).
  (add-hook 'post-command-hook #'mp/dashboard--hl-update nil t))

(with-eval-after-load 'evil
  ;; Single keys are shadowed by evil motion state; bind them in the dashboard's
  ;; own map for normal+motion so they win inside this buffer only.
  (evil-define-key '(normal motion) mp/dashboard-mode-map
    "n" #'mp/dashboard-switch-next
    "p" #'mp/dashboard-switch-prev
    "q" #'mp/dashboard-quit
    "]" #'mp/dashboard-next-link
    "[" #'mp/dashboard-prev-link
    "gr" #'mp/dashboard-refresh))

;;;; Link navigation + highlight

(defun mp/dashboard-next-link ()
  "Move point to the next link, wrapping around."
  (interactive) (forward-button 1 t nil t))

(defun mp/dashboard-prev-link ()
  "Move point to the previous link, wrapping around."
  (interactive) (backward-button 1 t nil t))

(defvar-local mp/dashboard--hl-overlay nil
  "Overlay highlighting the dashboard block (link) at point.")

(defun mp/dashboard--block-bounds ()
  "Bounds (BEG . END) of the block at point, or nil when point is not on one."
  (let ((id (get-text-property (point) 'mp/dashboard-block)))
    (when id
      (let ((beg (point)) (end (point)))
        (while (and (> beg (point-min))
                    (eq (get-text-property (1- beg) 'mp/dashboard-block) id))
          (setq beg (1- beg)))
        (while (and (< end (point-max))
                    (eq (get-text-property end 'mp/dashboard-block) id))
          (setq end (1+ end)))
        (cons beg end)))))

(defun mp/dashboard--hl-update ()
  "Move the highlight overlay to the block at point (or hide it)."
  (when (derived-mode-p 'mp/dashboard-mode)
    (let ((bounds (mp/dashboard--block-bounds)))
      (cond
       ((null bounds)
        (when mp/dashboard--hl-overlay (delete-overlay mp/dashboard--hl-overlay)))
       (t
        (unless (overlayp mp/dashboard--hl-overlay)
          (setq mp/dashboard--hl-overlay (make-overlay 1 1))
          (overlay-put mp/dashboard--hl-overlay 'face 'mp/dashboard-hl)
          (overlay-put mp/dashboard--hl-overlay 'priority -50))
        (move-overlay mp/dashboard--hl-overlay (car bounds) (cdr bounds)))))))

(defun mp/dashboard--current-persp-buffers ()
  "Buffers of the current perspective, in global most-recently-used order."
  (if (bound-and-true-p persp-mode)
      (let ((members (persp-current-buffers)))
        (seq-filter (lambda (b) (memq b members)) (buffer-list)))
    (buffer-list)))

(defun mp/dashboard-quit ()
  "Leave the dashboard for the current workspace's most-recent real buffer.
With no such buffer (an empty workspace) stay put."
  (interactive)
  (if-let* ((buf (seq-find #'mp/dashboard--interesting-p
                           (mp/dashboard--current-persp-buffers))))
      (switch-to-buffer buf)
    (message "No open buffer in this workspace")))

(defun mp/dashboard-enter (name)
  "Switch to workspace NAME and land on its most-recent real buffer."
  (persp-switch name)
  (mp/dashboard-quit))

(defun mp/dashboard--switch (step)
  "Switch to the STEP-neighbour workspace, keeping the dashboard on screen."
  (when (bound-and-true-p persp-mode)
    (let* ((names (mp/workspace-names))
           (pos (or (seq-position names (mp/workspace-current-name)) 0))
           (target (nth (mod (+ pos step) (length names)) names)))
      (unless (equal target (mp/workspace-current-name)) (persp-switch target))
      ;; `persp-switch' restores TARGET's window layout; collapse to a single
      ;; window showing the (refreshed) dashboard so browsing stays clean.
      (delete-other-windows)
      (switch-to-buffer (mp/dashboard-buffer)))))

(defun mp/dashboard-switch-next ()
  "Switch to the next workspace (staying on the dashboard)."
  (interactive) (mp/dashboard--switch 1))

(defun mp/dashboard-switch-prev ()
  "Switch to the previous workspace (staying on the dashboard)."
  (interactive) (mp/dashboard--switch -1))

(defun mp/dashboard-refresh ()
  "(Re)build the dashboard buffer for the current workspace.
Degrades gracefully when perspective isn't loaded yet (this runs as
`initial-buffer-choice' during startup, before elpaca settles — an error
here would silently fall back to *scratch*)."
  (let* ((buf (get-buffer-create mp/dashboard-buffer-name))
         (persp-ready (bound-and-true-p persp-mode))
         (active (and persp-ready (mp/workspace-current-name))))
    (with-current-buffer buf
      ;; Establish the mode up front: `define-derived-mode' runs
      ;; `kill-all-local-variables', which would otherwise clobber the
      ;; `default-directory' / preview state we set while rendering.
      (unless (derived-mode-p 'mp/dashboard-mode) (mp/dashboard-mode))
      (let* ((inhibit-read-only t)
             (current (or active "main"))
             ;; The workspace's *assigned* (or buffer-inferred) project — not a
             ;; projectile fallback — so "empty workspace" stays accurate.
             (root (and persp-ready (mp/workspace--project-root current)))
             (idx (1+ (or (and persp-ready
                               (seq-position (mp/workspace-names) current))
                          0))))
        ;; Keep the shared *dashboard* buffer's directory in sync with the shown
        ;; workspace so the svg header line reports the right project (it reads
        ;; `projectile-project-name' off `default-directory').
        (setq default-directory (or root (expand-file-name "~/")))
        (setq mp/dashboard--block-counter 0)
        (erase-buffer)
        (insert "\n\n")
        ;; Title: the same "INDEX project" label used everywhere else, or
        ;; "empty workspace - NAME" when nothing is assigned.
        (insert (propertize
                 (format "  %s\n"
                         (if root
                             (format "%d %s" idx
                                     (file-name-nondirectory (directory-file-name root)))
                           (mp/workspace--empty-name current)))
                 'face '(:height 1.6 :weight bold)))
        (insert (propertize (if root
                                (format "  %s\n" (abbreviate-file-name root))
                              "  no project — pick one below or SPC p p\n")
                            'face 'font-lock-comment-face))
        (insert "\n")

        ;; Workspaces.  `>' marks the active one; RET/click enters a workspace
        ;; (landing on its last buffer), `n'/`p' switch while staying here.
        (when persp-ready
          (mp/dashboard--heading
           (mp/dashboard--icon #'nerd-icons-mdicon "nf-md-view_dashboard") "Workspaces")
          (dolist (name (mp/workspace-names))
            (let* ((n name) (act (equal n current)))
              (mp/dashboard--item
               (mp/workspace--label n)
               (lambda (_) (mp/dashboard-enter n))
               ;; `>' marker lives in the (plain) indent so the button stays
               ;; tight to the label — nothing highlights past the text.
               :indent (if act "  > " "    ")
               :face (if act 'mp/dashboard-active 'mp/dashboard-item))))
          (insert "\n"))

        ;; Agents: each agent-shell with its own title header + live status
        ;; (running / waiting-for-you / idle) and workspace · model · effort ·
        ;; perms · context · runtime.  RET/click navigates to the owning workspace.
        ;; The title line is the link; the detail line below is its description —
        ;; both share one highlight block (see `mp/dashboard--as-block').
        (when-let* ((agents (seq-filter #'mp/dashboard--agent-p (buffer-list))))
          (mp/dashboard--heading
           (mp/dashboard--icon #'nerd-icons-mdicon "nf-md-robot") "Agents")
          (dolist (b agents)
            (let* ((sbuf b)
                   (status (mp/dashboard--agent-status sbuf))
                   (ws     (mp/dashboard--buffer-workspace-label sbuf))
                   (detail (mp/dashboard--agent-detail sbuf))
                   (sub    (mapconcat
                            #'identity
                            (delq nil (list ws (and detail (not (string-empty-p detail)) detail)))
                            "  ·  ")))
              (mp/dashboard--as-block
                (insert "    ")
                (insert-text-button
                 (truncate-string-to-width (mp/dashboard--agent-title sbuf) 52 nil nil "…")
                 'action (let ((sb sbuf)) (lambda (_) (mp/dashboard--goto-buffer sb)))
                 'follow-link t 'mouse-face 'highlight
                 'face 'mp/dashboard-item 'help-echo (buffer-name sbuf))
                (insert "  " (cdr status) "\n")
                (unless (string-empty-p sub) (mp/dashboard--line sub)))))
          (insert "\n"))

        ;; Git status of the current workspace's project (kept after Agents).
        (when root
          (mp/dashboard--heading
           (mp/dashboard--icon #'nerd-icons-octicon "nf-oct-git_branch") "Git")
          (let* ((st       (mp/dashboard--git-status root))
                 (branch   (plist-get st :branch))
                 (upstream (plist-get st :upstream))
                 (ahead    (plist-get st :ahead))
                 (behind   (plist-get st :behind))
                 (changes  (plist-get st :changes)))
            ;; Branch / upstream / ahead-behind.
            (insert "    "
                    (propertize (or branch "detached") 'face 'font-lock-function-name-face))
            (if upstream
                (progn
                  (insert (propertize (format " → %s" upstream) 'face 'font-lock-comment-face))
                  (when (> ahead 0)  (insert (propertize (format "  ↑%d" ahead) 'face 'success)))
                  (when (> behind 0) (insert (propertize (format "  ↓%d" behind) 'face 'warning)))
                  (when (and (zerop ahead) (zerop behind))
                    (insert (propertize "  ✓ up to date" 'face 'font-lock-comment-face))))
              (insert (propertize "  (no upstream)" 'face 'font-lock-comment-face)))
            (insert "\n")
            (mp/dashboard--line
             (if changes (format "%d changed" (length changes)) "working tree clean"))
            ;; Changed files: colored status code + clickable path (RET opens it).
            (dolist (line (seq-take changes 10))
              (let* ((code (substring line 0 2))
                     (path (let ((p (substring line 3)))
                             (if (string-match " -> " p) (substring p (match-end 0)) p)))
                     (full (expand-file-name path root)))
                (mp/dashboard--as-block
                  (insert "    "
                          (propertize (format "%-2s " code) 'face (mp/dashboard--git-face code)))
                  (insert-text-button path
                                      'action (let ((f full)) (lambda (_) (find-file f)))
                                      'follow-link t 'mouse-face 'highlight
                                      'face 'mp/dashboard-item 'help-echo full)
                  (insert "\n"))))
            (when (> (length changes) 10)
              (mp/dashboard--line (format "… %d more" (- (length changes) 10)))))
          (insert "\n"))

        ;; Terminals (ghostel): show its workspace and whether a command is
        ;; running, so it's clear if the terminal is safe to close.  RET/click
        ;; navigates to its workspace.
        (when-let* ((terms (seq-filter #'mp/dashboard--ghostel-p (buffer-list))))
          (mp/dashboard--heading
           (mp/dashboard--icon #'nerd-icons-octicon "nf-oct-terminal") "Terminals")
          (dolist (b terms)
            (let* ((tbuf b)
                   (running (with-current-buffer tbuf
                              (bound-and-true-p ghostel--command-running)))
                   (ws    (mp/dashboard--buffer-workspace-label tbuf))
                   (title (with-current-buffer tbuf
                            (or (bound-and-true-p ghostel--title) (buffer-name tbuf)))))
              (mp/dashboard--as-block
                (insert "    ")
                (insert-text-button
                 title
                 'action (let ((tb tbuf)) (lambda (_) (mp/dashboard--goto-buffer tb)))
                 'follow-link t 'mouse-face 'highlight
                 'face 'mp/dashboard-item 'help-echo (buffer-name tbuf))
                (insert "  " (if running
                                 (propertize "● running — unsafe to close" 'face 'warning)
                               (propertize "○ idle — safe to close" 'face 'font-lock-comment-face)))
                (when ws
                  (insert (propertize (format "  ·  %s" ws) 'face 'font-lock-comment-face)))
                (insert "\n"))))
          (insert "\n"))

        ;; Known projects (RET/click opens in THIS workspace).
        (mp/dashboard--heading
         (mp/dashboard--icon #'nerd-icons-octicon "nf-oct-repo") "Projects")
        (dolist (project (seq-take (and (fboundp 'projectile-relevant-known-projects)
                                        (projectile-relevant-known-projects))
                                   10))
          (let ((p project))
            (mp/dashboard--item
             (file-name-nondirectory (directory-file-name p))
             (lambda (_) (mp/open-project-root p))
             :help-echo p)))
        (insert "\n")

        (insert (propertize
                 "  ]/[ links · RET open · n/p switch workspace · q enter · SPC p p projects\n"
                 'face 'font-lock-comment-face)))
      ;; Park point on the first link so `]'/`[' have a starting point and the
      ;; highlight shows immediately; the block cursor stays hidden.
      (goto-char (point-min))
      (when-let* ((b (next-button (point-min)))) (goto-char (button-start b)))
      (setq-local cursor-type nil)
      (mp/dashboard--hl-update))
    buf))

(defun mp/dashboard-buffer ()
  "Return the dashboard buffer, refreshed."
  (mp/dashboard-refresh))

(defun mp/dashboard ()
  "Show the workspace dashboard.
When the dashboard is already the current buffer, re-render it in place
(picking up live agent/terminal/git status); otherwise switch to a
freshly-rebuilt dashboard."
  (interactive)
  (if (equal (buffer-name) mp/dashboard-buffer-name)
      (mp/dashboard-refresh)
    (switch-to-buffer (mp/dashboard-buffer))))

(setq initial-buffer-choice #'mp/dashboard-buffer)

;;; Dashboard as the workspace fallback buffer
;; Invariant: when the current workspace has no "interesting" buffer (a file,
;; terminal or agent) the selected window shows the dashboard; the moment a
;; real buffer is open again, a hidden dashboard is killed so it never lingers.

(defun mp/dashboard--interesting-p (buf)
  "Non-nil if BUF is worth keeping a workspace alive for."
  (and (buffer-live-p buf)
       (not (equal (buffer-name buf) mp/dashboard-buffer-name))
       (or (buffer-file-name (buffer-base-buffer buf))
           (mp/dashboard--ghostel-p buf)
           (mp/dashboard--agent-p buf))))

(defun mp/dashboard--workspace-buffers ()
  (if (fboundp 'persp-current-buffers)
      (seq-filter #'buffer-live-p (persp-current-buffers))
    (buffer-list)))

(defun mp/dashboard--workspace-empty-p ()
  (not (seq-some #'mp/dashboard--interesting-p (mp/dashboard--workspace-buffers))))

(defun mp/dashboard--throwaway-p (buf)
  "Non-nil if BUF is a boring placeholder the dashboard may replace.
Only scratch/messages/the-dashboard/an-empty-fundamental buffer count.
Anything the user deliberately opened — magit, help, dired, a compilation
buffer, etc. — is left alone even in an otherwise-empty workspace, so the
fallback never yanks such a buffer out from under them."
  (let ((name (buffer-name buf)))
    (or (string-prefix-p "*scratch*" name)
        (string= name "*Messages*")
        (string= name mp/dashboard-buffer-name)
        (with-current-buffer buf
          (and (eq major-mode 'fundamental-mode)
               (not (buffer-file-name))
               (= (buffer-size) 0))))))

(defvar mp/dashboard--enforcing nil
  "Reentrancy guard while the fallback enforcer mutates windows/buffers.")

(defun mp/dashboard--enforce ()
  "Keep the dashboard as the workspace fallback (see the invariant above)."
  (when (and (bound-and-true-p persp-mode)
             (not mp/dashboard--enforcing)
             (not (active-minibuffer-window))
             (window-live-p (selected-window)))
    (let ((mp/dashboard--enforcing t))
      (ignore-errors
        (if (mp/dashboard--workspace-empty-p)
            ;; Nothing real here -> surface the dashboard, but ONLY over a
            ;; throwaway placeholder.  A deliberately-opened buffer (magit,
            ;; help, dired…) stays, even though it isn't "interesting" enough
            ;; to keep the workspace alive on its own.
            (let ((shown (window-buffer (selected-window))))
              (when (and (mp/dashboard--throwaway-p shown)
                         (not (equal (buffer-name shown) mp/dashboard-buffer-name)))
                (switch-to-buffer (mp/dashboard-buffer))))
          ;; Real buffers exist -> don't let a hidden dashboard linger.
          (when-let* ((buf (get-buffer mp/dashboard-buffer-name)))
            (unless (get-buffer-window buf t)
              (kill-buffer buf))))))))

(defvar mp/dashboard--enforce-scheduled nil)

(defun mp/dashboard--schedule-enforce (&rest _)
  "Coalesce enforce triggers into one deferred run (safe from redisplay)."
  (unless mp/dashboard--enforce-scheduled
    (setq mp/dashboard--enforce-scheduled t)
    (run-at-time 0 nil (lambda ()
                         (setq mp/dashboard--enforce-scheduled nil)
                         (mp/dashboard--enforce)))))

(add-hook 'kill-buffer-hook #'mp/dashboard--schedule-enforce)
(add-hook 'window-buffer-change-functions #'mp/dashboard--schedule-enforce)

;;; Fresh splits (port of the Splits section; dashboard is the fresh buffer)

(defun mp/split-target-buffer ()
  "Populate a newly-created split.
Splitting from a Ghostel terminal opens a fresh terminal in the new
split; otherwise show the dashboard overview."
  (if (derived-mode-p 'ghostel-mode)
      (mp/ghostel-new)
    (switch-to-buffer (mp/dashboard-buffer))))

(defun mp/split-window-right-fresh ()
  "Split right and show a fresh buffer."
  (interactive)
  (select-window (split-window-right))
  (mp/split-target-buffer))

(defun mp/split-window-below-fresh ()
  "Split below and show a fresh buffer."
  (interactive)
  (select-window (split-window-below))
  (mp/split-target-buffer))

;;; Workspace-dependent custom packages

(mp/require-package "super-menu")
(mp/require-package "workspace-hud")

(provide 'mp-workspaces)
;;; mp-workspaces.el ends here
