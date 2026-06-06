;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

(require 'acp)
(require 'agent-shell)

(setq user-full-name "Mahdi Pourismaiel"
      user-mail-address "mpourismaiel@gmail.com")

(use-package! agent-shell-notifications
  :hook (agent-shell-mode . agent-shell-notifications-mode))

(setq doom-theme 'doom-one)
(setq doom-font (font-spec :family "CaskaydiaCove Nerd Font Mono" :size 16))

;; Let Treemacs use richer git-state highlighting when Python is available.
(setq +treemacs-git-mode 'deferred)

(defvar mp/editor-line-spacing 0.6
  "Preferred extra line spacing for editing buffers.")

(defun mp/apply-editor-line-spacing-h ()
  "Apply comfortable line spacing to editable buffers."
  (setq-local line-spacing mp/editor-line-spacing))

(add-hook 'text-mode-hook #'mp/apply-editor-line-spacing-h)
(add-hook 'prog-mode-hook #'mp/apply-editor-line-spacing-h)
(add-hook 'conf-mode-hook #'mp/apply-editor-line-spacing-h)

(setq display-line-numbers-type t)

(setq org-directory "~/org/")

;; Send files to trash instead of fully deleting.
(setq delete-by-moving-to-trash t)

;; Save automatically.
(setq auto-save-default t)

(after! org
  (defun mp/doom-config-org-file-p (&optional file)
    "Return non-nil when FILE is the Doom literate config."
    (let ((file (or file buffer-file-name)))
      (and file
           (file-equal-p (file-truename file)
                         (file-truename (expand-file-name "config.org" doom-user-dir))))))

  (defun mp/org-babel-tangle-doom-config-h ()
    "Tangle the Doom literate config after saving `config.org'."
    (when (mp/doom-config-org-file-p)
      (let ((org-confirm-babel-evaluate nil))
        (org-babel-tangle))))

  (defun mp/enable-doom-config-auto-tangle-h ()
    "Enable local auto-tangling for the Doom literate config buffer."
    (when (mp/doom-config-org-file-p)
      (add-hook 'after-save-hook #'mp/org-babel-tangle-doom-config-h nil t)))

  (add-hook 'org-mode-hook #'mp/enable-doom-config-auto-tangle-h))

(setq which-key-idle-delay 0.2)

;; Give hover/help text enough room to be readable.
(setq eldoc-echo-area-use-multiline-p 3)

(when (modulep! :ui dashboard)
  (require 'cl-lib)
  (require 'project)
  (require 'recentf)

  (setq +dashboard-anchor '(top . center)
        +dashboard-banner-vertical-padding '(1 . 1))

  (defvar mp/dashboard-card-width 72
    "Width of the custom dashboard card.")

  (defun mp/dashboard-first-available-font (&rest families)
    "Return the first installed font family from FAMILIES."
    (cl-find-if (lambda (family)
                  (find-font (font-spec :family family)))
                families))

  (defvar mp/dashboard-display-font
    (mp/dashboard-first-available-font
     "CaskaydiaCove Nerd Font Mono"
     "JetBrainsMono Nerd Font Mono"
     "DejaVu Sans Mono")
    "Preferred fixed-pitch font family for dashboard headings.")

  (defface mp/dashboard-card-face
    '((t (:inherit default)))
    "Face for the dashboard card body.")

  (defface mp/dashboard-card-border-face
    '((t (:inherit shadow)))
    "Face for the dashboard card border.")

  (defface mp/dashboard-heading-face
    '((t (:inherit bold)))
    "Face for dashboard section headings.")

  (defface mp/dashboard-action-face
    '((t (:inherit link)))
    "Face for dashboard action buttons.")

  (defface mp/dashboard-meta-face
    '((t (:inherit shadow)))
    "Face for dashboard secondary text.")

  (custom-set-faces!
    '(mp/dashboard-card-face
      :inherit fixed-pitch
      :background "#1e222a"
      :foreground "#c8ccd4")
    '(mp/dashboard-card-border-face
      :inherit fixed-pitch
      :foreground "#5b6268")
    '(mp/dashboard-heading-face
      :inherit fixed-pitch
      :foreground "#e5e9f0"
      :weight ultra-bold)
    '(mp/dashboard-action-face
      :inherit fixed-pitch
      :foreground "#8fbcbb"
      :weight semi-bold)
    '(mp/dashboard-meta-face
      :inherit fixed-pitch
      :foreground "#7b8591"))

  (defun mp/dashboard-buffer-setup-h ()
    "Keep the dashboard layout independent from editor line spacing."
    (setq-local line-spacing nil)
    (when mp/dashboard-display-font
      (set-face-attribute 'mp/dashboard-heading-face nil
                          :family mp/dashboard-display-font
                          :weight 'ultra-bold
                          :height 1.0)
      (set-face-attribute 'mp/dashboard-action-face nil
                          :family mp/dashboard-display-font
                          :weight 'semi-bold)
      (set-face-attribute 'mp/dashboard-meta-face nil
                          :family mp/dashboard-display-font))
    (set-face-attribute 'mp/dashboard-card-face nil :inherit 'fixed-pitch)
    (set-face-attribute 'mp/dashboard-card-border-face nil :inherit 'fixed-pitch))

  (add-hook '+dashboard-mode-hook #'mp/dashboard-buffer-setup-h)

(defun mp/dashboard-project-root ()
  "Return the current dashboard project root, if any."
  (or (when (fboundp 'doom-project-root)
        (ignore-errors (doom-project-root default-directory)))
      (let ((default-directory default-directory))
        (when-let ((project (project-current nil)))
          (expand-file-name (project-root project))))))

(defun mp/dashboard-project-name ()
  "Return a readable name for the current dashboard project."
  (when-let ((root (mp/dashboard-project-root)))
    (file-name-nondirectory (directory-file-name root))))

(defun mp/dashboard-open-project ()
  "Jump to a file in the current project."
  (interactive)
  (if-let ((root (mp/dashboard-project-root)))
      (doom-project-find-file root)
    (call-interactively #'projectile-switch-project)))

(defun mp/dashboard-open-project-scratch ()
  "Open a scratch buffer scoped to the current project when possible."
  (interactive)
  (if (mp/dashboard-project-root)
      (doom/open-project-scratch-buffer)
    (doom/open-scratch-buffer)))

(defun mp/dashboard-magit-status ()
  "Open Magit status for the current dashboard directory."
  (interactive)
  (let ((default-directory default-directory))
    (call-interactively #'magit-status)))

(defun mp/dashboard-recent-files (&optional limit)
  "Return up to LIMIT recent files, preferring the current project."
  (let* ((root (mp/dashboard-project-root))
         (files (cl-remove-if-not #'file-exists-p recentf-list))
         (files (if root
                    (cl-remove-if-not
                     (lambda (file) (file-in-directory-p file root))
                     files)
                  files)))
    (cl-subseq files 0 (min (or limit 5) (length files)))))

(defun mp/dashboard-insert-block-title (title &optional subtitle)
  "Insert a centered TITLE and optional SUBTITLE."
  (+dashboard-insert
   (propertize title 'face '+dashboard-menu-title))
  (when subtitle
    (+dashboard-insert
     (propertize subtitle 'face '+dashboard-menu-desc))))

(defun mp/dashboard-open-recent-file (file)
  "Open FILE from the dashboard."
  (interactive)
  (find-file file))

(defun mp/dashboard--card-inner-width ()
  "Return the inner text width of the dashboard card."
  (- mp/dashboard-card-width 4))

(defun mp/dashboard--pad-string (text width)
  "Pad or truncate TEXT to WIDTH display columns."
  (let* ((text (truncate-string-to-width text width 0 nil "…"))
         (padding (max 0 (- width (string-width text)))))
    (concat text (make-string padding ? ))))

(defun mp/dashboard--card-text (text &optional face)
  "Return TEXT styled for use inside the card."
  (let ((text (copy-sequence (or text ""))))
    (add-face-text-property 0 (length text) (or face 'mp/dashboard-card-face) 'append text)
    text))

(defun mp/dashboard-card-line (&optional text)
  "Return a single centered card line for TEXT."
  (let* ((inner-width (mp/dashboard--card-inner-width))
         (body (mp/dashboard--pad-string (or text "") inner-width))
         (body (mp/dashboard--card-text body 'mp/dashboard-card-face)))
    (concat
     (propertize "│ " 'face 'mp/dashboard-card-border-face)
     body
     (propertize " │" 'face 'mp/dashboard-card-border-face))))

(defun mp/dashboard-card-rule ()
  "Return the top or bottom border for the dashboard card."
  (concat
   (propertize "╭" 'face 'mp/dashboard-card-border-face)
   (propertize (make-string (- mp/dashboard-card-width 2) ?─)
               'face 'mp/dashboard-card-border-face)
   (propertize "╮" 'face 'mp/dashboard-card-border-face)))

(defun mp/dashboard-card-rule-bottom ()
  "Return the bottom border for the dashboard card."
  (concat
   (propertize "╰" 'face 'mp/dashboard-card-border-face)
   (propertize (make-string (- mp/dashboard-card-width 2) ?─)
               'face 'mp/dashboard-card-border-face)
   (propertize "╯" 'face 'mp/dashboard-card-border-face)))

(defun mp/dashboard-insert-card-line (&optional text)
  "Insert TEXT as a centered line inside the dashboard card."
  (+dashboard-insert (mp/dashboard-card-line text)))

(defun mp/dashboard-insert-heading (title)
  "Insert TITLE as a dashboard section heading."
  (mp/dashboard-insert-card-line
   (propertize title 'face 'mp/dashboard-heading-face)))

(defun mp/dashboard-insert-button-line (label action &optional help-echo face)
  "Insert a clickable dashboard line."
  (let ((line
         (with-temp-buffer
           (insert-text-button label
                               'action action
                               'follow-link t
                               'help-echo help-echo
                               'face (or face 'mp/dashboard-action-face))
           (buffer-string))))
    (mp/dashboard-insert-card-line line)))

(defun mp/dashboard-insert-text-line (text &optional face)
  "Insert TEXT as a styled card line."
  (mp/dashboard-insert-card-line
   (propertize text 'face (or face 'mp/dashboard-meta-face))))

(defun mp/dashboard-widget-recent-files ()
  "Show the five most recent files for the active project."
  (let* ((root (mp/dashboard-project-root))
         (files (mp/dashboard-recent-files 5))
         (title (if root
                    (format "Recent files in %s" (mp/dashboard-project-name))
                  "Recent files")))
    (mp/dashboard-insert-block-title title)
    (if files
        (dolist (file files)
          (mp/dashboard-insert-centered-button
           (if root
               (file-relative-name file root)
             (abbreviate-file-name file))
           `(lambda (_) (mp/dashboard-open-recent-file ,file))
           file
           '+dashboard-menu-desc))
      (+dashboard-insert
       (propertize "No recent files available yet." 'face '+dashboard-menu-desc)))))

(defun mp/dashboard-git-summary ()
  "Return a summary plist for the git repo at `default-directory'."
  (when-let ((root (ignore-errors (magit-toplevel default-directory))))
    (let ((default-directory root)
          (staged 0)
          (unstaged 0)
          (untracked 0))
      (dolist (line (magit-git-lines "status" "--short"))
        (cond
         ((string-prefix-p "??" line)
          (cl-incf untracked))
         (t
          (let ((x (aref line 0))
                (y (aref line 1)))
            (unless (eq x ?\s)
              (cl-incf staged))
            (unless (eq y ?\s)
              (cl-incf unstaged))))))
      (list :root root
            :branch (or (magit-get-current-branch) "detached")
            :staged staged
            :unstaged unstaged
            :untracked untracked))))

(defun mp/dashboard-widget-git ()
  "Show lightweight git information for the active project."
  (when-let* ((summary (mp/dashboard-git-summary))
              (branch (plist-get summary :branch)))
    (mp/dashboard-insert-block-title
     (format "Git: %s" branch)
     (format "Staged %d  Unstaged %d  Untracked %d"
             (plist-get summary :staged)
             (plist-get summary :unstaged)
             (plist-get summary :untracked)))
    (mp/dashboard-insert-centered-button
     "Open Magit status"
     (lambda (_) (mp/dashboard-magit-status))
     "Inspect the current repository with Magit"
     '+dashboard-menu-desc)))

(defun mp/dashboard-widget-main ()
  "Render a plain, robust dashboard body."
  (let ((root (mp/dashboard-project-root))
        (recent-files (mp/dashboard-recent-files 5))
        (git (mp/dashboard-git-summary)))
    (+dashboard-insert "")
    (+dashboard-insert (mp/dashboard-card-rule))
    (mp/dashboard-insert-card-line
     (propertize "Workspace" 'face 'mp/dashboard-meta-face))
    (mp/dashboard-insert-heading "Actions")
    (mp/dashboard-insert-button-line
     "Find file in project"
     (lambda (_) (mp/dashboard-open-project))
     "Jump to a file in the current project")
    (mp/dashboard-insert-button-line
     "Open project scratch"
     (lambda (_) (mp/dashboard-open-project-scratch))
     "Open a project scratch buffer")
    (when git
      (mp/dashboard-insert-button-line
       "Open Magit status"
       (lambda (_) (mp/dashboard-magit-status))
       "Inspect the current repository with Magit"))
    (mp/dashboard-insert-button-line
     "Recent files picker"
     (lambda (_) (call-interactively #'recentf-open-files))
     "Open the global recent files picker")
    (when (fboundp 'org-agenda)
      (mp/dashboard-insert-button-line
       "Open org-agenda"
       (lambda (_) (call-interactively #'org-agenda))
       "Open org-agenda"))
    (when (file-directory-p doom-user-dir)
      (mp/dashboard-insert-button-line
       "Open private configuration"
       (lambda (_) (call-interactively #'doom/open-private-config))
       "Open your Doom private config"))
    (mp/dashboard-insert-button-line
     "Open documentation"
     (lambda (_) (call-interactively #'doom/help))
     "Open Doom documentation")

    (mp/dashboard-insert-card-line)
    (mp/dashboard-insert-heading
     (if root
         (format "Recent Files in %s" (mp/dashboard-project-name))
       "Recent Files"))
    (if recent-files
        (dolist (file recent-files)
          (mp/dashboard-insert-button-line
           (if root
               (file-relative-name file root)
             (abbreviate-file-name file))
           `(lambda (_) (mp/dashboard-open-recent-file ,file))
           file
           'mp/dashboard-meta-face))
      (mp/dashboard-insert-text-line "No recent files available yet."))

    (when git
      (mp/dashboard-insert-card-line)
      (mp/dashboard-insert-heading
       (format "Git: %s" (plist-get git :branch)))
      (mp/dashboard-insert-text-line
       (format "Staged: %d   Unstaged: %d   Untracked: %d"
               (plist-get git :staged)
               (plist-get git :unstaged)
               (plist-get git :untracked))))
    (+dashboard-insert (mp/dashboard-card-rule-bottom))))

(setq +dashboard-menu-sections
      '(("Find file in project"
         :icon (nerd-icons-octicon "nf-oct-file_directory_open" :face '+dashboard-menu-title)
         :action mp/dashboard-open-project)
        ("Open project scratch"
         :icon (nerd-icons-octicon "nf-oct-pencil" :face '+dashboard-menu-title)
         :action mp/dashboard-open-project-scratch)
        ("Open Magit status"
         :icon (nerd-icons-octicon "nf-oct-git_branch" :face '+dashboard-menu-title)
         :when (ignore-errors (magit-toplevel default-directory))
         :action mp/dashboard-magit-status)
        ("Recent files picker"
         :icon (nerd-icons-octicon "nf-oct-history" :face '+dashboard-menu-title)
         :action recentf-open-files)
        ("Open org-agenda"
         :icon (nerd-icons-octicon "nf-oct-calendar" :face '+dashboard-menu-title)
         :when (fboundp 'org-agenda)
         :action org-agenda)
        ("Open private configuration"
         :icon (nerd-icons-octicon "nf-oct-tools" :face '+dashboard-menu-title)
         :when (file-directory-p doom-user-dir)
         :action doom/open-private-config)
        ("Open documentation"
         :icon (nerd-icons-octicon "nf-oct-book" :face '+dashboard-menu-title)
         :action doom/help)))

(setq +dashboard-functions
      '(+dashboard-widget-banner
        mp/dashboard-widget-main
        +dashboard-widget-loaded
        +dashboard-widget-footer)))

(defun mp/show-indent-style-h ()
  "Show tabs and spaces visibly in code-like buffers."
  (setq-local whitespace-style
              '(face tabs tab-mark spaces space-mark trailing))
  (setq-local whitespace-display-mappings
              '((tab-mark ?\t [?\u2192 ?\t] [?\\ ?\t])
                (space-mark ?\  [?\u00b7] [?.])))
  (whitespace-mode +1))

(add-hook 'prog-mode-hook #'mp/show-indent-style-h)
(add-hook 'conf-mode-hook #'mp/show-indent-style-h)

;; Never let Doom infer or create a Pipenv project at a monorepo root.
;; Only an already-existing ancestor Pipfile counts as a valid Pipenv root.
(defun mp/pipenv-project-p (&optional dir)
  (when-let ((root (locate-dominating-file (or dir default-directory) "Pipfile")))
    (expand-file-name root)))

(defun mp/pipenv-allowed-p (&optional dir)
  (not (null (mp/pipenv-project-p dir))))

(defun mp/pipenv-command-p (program)
  (and (stringp program)
       (string= (file-name-nondirectory program) "pipenv")))

(defun mp/pipenv-command-list-p (command)
  (and (consp command)
       (mp/pipenv-command-p (car command))))

(defun mp/block-pipenv-outside-project (origin &optional dir)
  (unless (mp/pipenv-allowed-p dir)
    (user-error "Blocked %s outside a directory that already contains an ancestor Pipfile" origin)))

(defun mp/call-process-guard-a (fn program &rest args)
  (when (mp/pipenv-command-p program)
    (mp/block-pipenv-outside-project 'call-process default-directory))
  (apply fn program args))

(defun mp/process-file-guard-a (fn program &rest args)
  (when (mp/pipenv-command-p program)
    (mp/block-pipenv-outside-project 'process-file default-directory))
  (apply fn program args))

(defun mp/start-file-process-guard-a (fn name buffer program &rest program-args)
  (when (mp/pipenv-command-p program)
    (mp/block-pipenv-outside-project 'start-file-process default-directory))
  (apply fn name buffer program program-args))

(defun mp/make-process-guard-a (fn &rest args)
  (let ((command (plist-get args :command))
        (dir (or (plist-get args :default-directory) default-directory)))
    (when (mp/pipenv-command-list-p command)
      (mp/block-pipenv-outside-project 'make-process dir)))
  (apply fn args))

;; Define this early so any stale autoloads or callers resolve to the safe
;; version even if the `pipenv' package is disabled.
(defalias 'pipenv-project-p #'mp/pipenv-project-p)
(advice-add 'call-process :around #'mp/call-process-guard-a)
(advice-add 'process-file :around #'mp/process-file-guard-a)
(advice-add 'start-file-process :around #'mp/start-file-process-guard-a)
(advice-add 'make-process :around #'mp/make-process-guard-a)

(after! python
  ;; Stop Doom/python-mode from auto-enabling pipenv.
  (remove-hook 'python-mode-local-vars-hook #'pipenv-mode)
  (remove-hook 'python-ts-mode-local-vars-hook #'pipenv-mode)

  ;; Hard-disable pipenv-mode if loaded.
  (setq pipenv-with-projectile nil)

  ;; Doom's default REPL helper tries to route through pipenv when available.
  ;; Force plain `run-python' so opening a REPL never shells out to pipenv.
  (defun mp/+python/open-repl-no-pipenv ()
    (interactive)
    (require 'python)
    (unless python-shell-interpreter
      (user-error "`python-shell-interpreter' isn't set"))
    (pop-to-buffer
     (process-buffer
      (run-python nil (bound-and-true-p python-shell-dedicated) t))))

  (advice-add '+python/open-repl :override #'mp/+python/open-repl-no-pipenv)

  ;; Likewise, project script execution should run the interpreter directly.
  (set-eval-handler! '(python-mode python-ts-mode)
    '((:command . (lambda () python-shell-interpreter))
      (:exec . (lambda () "%c %o %s %a"))
      (:description . "Run Python script"))))

(after! pipenv
  (advice-add 'pipenv-project-p :override #'mp/pipenv-project-p)
  (pipenv-mode -1))

(after! doom-modeline
  ;; The Python env segment can shell out to `pipenv run ...` on Python buffers.
  ;; Disable it so merely visiting files can't hit pipenv.
  (setq doom-modeline-env-enable-python nil))

(after! projectile
  ;; Doom's Python helpers still consult Projectile in a few places.
  ;; Make sure `server/Pipfile` counts as a project root before `.git` does.
  (add-to-list 'projectile-project-root-files "Pipfile"))

(after! project
  (defun mp/project-root-from-markers (dir markers)
    "Return the first project root above DIR matching one of MARKERS."
    (when-let ((root (seq-some (lambda (marker)
                                 (locate-dominating-file dir marker))
                               markers)))
      (cons 'transient root)))

  ;; Prefer language-specific roots inside monorepos over the repository root.
  ;; This keeps `server/` Python tooling anchored to its own Pipfile/pyproject
  ;; instead of falling back to the top-level `.git` directory.
  (add-hook 'project-find-functions
            (lambda (dir)
              (or (mp/project-root-from-markers dir '("go.mod"))
                  (mp/project-root-from-markers dir '("Cargo.toml"))
                  (mp/project-root-from-markers dir '("package.json"))
                  (mp/project-root-from-markers
                   dir
                   '("Pipfile" "pyproject.toml" "setup.py" "requirements.txt"))
                  (mp/project-root-from-markers dir '(".git"))))))

(map! :leader
      :desc "Run nearest test" "t t" #'+eval/test
      :desc "Run all project tests" "t a" #'+eval/test-all
      (:prefix ("d" . "agent")
       :desc "Agent shell" "a" #'agent-shell))

(map! :n "gr" #'xref-find-references)

(global-set-key [mouse-8] #'xref-go-back)
(global-set-key [mouse-9] #'xref-go-forward)

(defun mp/project-root-default-directory (&optional dir)
  "Return the preferred project root for DIR, or `default-directory'."
  (let ((dir (file-name-as-directory
              (expand-file-name (or dir default-directory)))))
    (or (when (fboundp 'projectile-project-root)
          (let ((default-directory dir))
            (ignore-errors
              (file-name-as-directory
               (expand-file-name (projectile-project-root))))))
        (when (fboundp 'doom-project-root)
          (ignore-errors
            (file-name-as-directory
             (expand-file-name (doom-project-root dir)))))
        dir)))

(defun mp/vterm-toggle ()
  "Toggle the vterm popup from the current project root."
  (interactive)
  (let ((default-directory (mp/project-root-default-directory)))
    (+vterm/toggle nil)))

(defun mp/vterm-new ()
  "Open a fresh vterm buffer in the current window at project root."
  (interactive)
  (require 'vterm)
  (let* ((default-directory (mp/project-root-default-directory))
         (buffer-name (format "*vterm:%s*" (format-time-string "%Y%m%d-%H%M%S")))
         (buffer (generate-new-buffer buffer-name))
         (display-buffer-alist nil))
    (with-current-buffer buffer
      (vterm-mode))
    (switch-to-buffer buffer)))

(defun mp/line-move-bounds ()
  "Return the line-aligned bounds for the current line or active region."
  (if (use-region-p)
      (cons (save-excursion
              (goto-char (region-beginning))
              (line-beginning-position))
            (save-excursion
              (goto-char (region-end))
              (if (bolp)
                  (point)
                (line-beginning-position 2))))
    (cons (line-beginning-position)
          (line-beginning-position 2))))

(defun mp/move-lines--apply (direction)
  "Move the current line or active region one line in DIRECTION."
  (let* ((bounds (mp/line-move-bounds))
         (had-region (use-region-p))
         (start (car bounds))
         (end (cdr bounds)))
    (save-excursion
      (goto-char (if (> direction 0) end start))
      (when (or (and (< direction 0) (= start (point-min)))
                (and (> direction 0) (= end (point-max))))
        (user-error "Cannot move further %s" (if (< direction 0) "up" "down"))))
    (let* ((line-count (count-lines start end))
           (column (current-column))
           (text (delete-and-extract-region start end)))
      (goto-char start)
      (forward-line direction)
      (let ((target (point)))
        (insert text)
        (if had-region
            (progn
              (set-mark target)
              (goto-char (+ target (length text)))
              (setq deactivate-mark nil))
          (goto-char target)
          (forward-line (if (> direction 0) (1- line-count) 0))
          (move-to-column column))))))

(defun mp/move-lines-up ()
  "Move the current line or active region up by one line."
  (interactive)
  (mp/move-lines--apply -1))

(defun mp/move-lines-down ()
  "Move the current line or active region down by one line."
  (interactive)
  (mp/move-lines--apply 1))

;; Global GUI-style bindings.
;; Keeps a terminal toggle, line commenting, and line movement available
;; through familiar keys.
(map! :g "C-`" #'mp/vterm-toggle
      :g "C-\\" #'mp/vterm-new
      :g "C-/" #'comment-line
      :g "M-<up>" #'mp/move-lines-up
      :g "M-<down>" #'mp/move-lines-down)

(after! evil
  (dolist (state-map (list evil-motion-state-map
                           evil-normal-state-map
                           evil-insert-state-map
                           evil-emacs-state-map
                           evil-visual-state-map))
    (define-key state-map (kbd "C-b") #'treemacs)
    (define-key state-map (kbd "C-\\") #'mp/vterm-new)
    (define-key state-map (kbd "C-/") #'comment-line)
    (define-key state-map (kbd "M-<up>") #'mp/move-lines-up)
    (define-key state-map (kbd "M-<down>") #'mp/move-lines-down)))

(defun mp/close-window-preserve-buffer ()
  "Close the selected window without killing popup or terminal buffers."
  (interactive)
  (if (and (featurep '+popup)
           (+popup-window-p))
      (let* ((window (selected-window))
             (buffer (window-buffer window))
             (+popup--inhibit-transient t)
             (ignore-window-parameters t))
        (if-let ((wconf (window-parameter window 'saved-wconf)))
            (set-window-configuration wconf)
          (delete-window window))
        (when (buffer-live-p buffer)
          (with-current-buffer buffer
            (set-buffer-modified-p nil)
            (when (bound-and-true-p +popup-buffer-mode)
              (+popup-buffer-mode -1))
            (bury-buffer buffer))))
    (call-interactively #'delete-window)))

(after! workspaces
  (map! :leader
        (:prefix ("w" . "workspaces/windows")
         :desc "Delete window" "d" #'mp/close-window-preserve-buffer
         :desc "Delete window/workspace" "D" #'+workspace/close-window-or-workspace))
  (map! :map evil-window-map
        "d" #'mp/close-window-preserve-buffer
        "D" #'+workspace/close-window-or-workspace))

(use-package! consult-dir
  :defer t
  :config
  (map! :leader
        :desc "Find file from directory" "." #'find-file
        :desc "Switch directory" "f d" #'consult-dir)
  (map! :map minibuffer-local-completion-map
        "C-x C-d" #'consult-dir
        "C-x C-j" #'consult-dir-jump-file))

(after! which-key
  (when (boundp 'doom-leader-map)
    (which-key-add-keymap-based-replacements doom-leader-map
      "TAB" "workspace"
      "a" "actions"
      "b" "buffers"
      "c" "code"
      "d" "agent"
      "f" "files"
      "g" "git"
      "h" "help"
      "i" "insert"
      "n" "notes"
      "o" "open"
      "p" "project"
      "q" "quit/session"
      "s" "search"
      "t" "toggle"
      "w" "windows"
      "x" "text")))

(after! treemacs
  (setq treemacs-show-hidden-files t)

  (defface mp/treemacs-dotfile-face
    '((t :inherit shadow :slant italic))
    "Face used to de-emphasize visible dotfiles in Treemacs.")

  (set-face-attribute 'treemacs-git-ignored-face nil
                      :inherit 'shadow
                      :slant 'italic)
  (set-face-attribute 'treemacs-git-untracked-face nil
                      :foreground "#98c379")
  (set-face-attribute 'treemacs-git-modified-face nil
                      :foreground "#e5c07b"
                      :weight 'semi-bold)
  (set-face-attribute 'treemacs-git-added-face nil
                      :foreground "#61afef"
                      :weight 'semi-bold)
  (set-face-attribute 'treemacs-git-renamed-face nil
                      :foreground "#c678dd")
  (set-face-attribute 'treemacs-git-conflict-face nil
                      :foreground "#e06c75"
                      :weight 'bold)

  (defun mp/treemacs--dotfile-p (path)
    "Return non-nil when PATH points to a visible dotfile or dotdir."
    (let ((name (file-name-nondirectory (directory-file-name path))))
      (and (string-prefix-p "." name)
           (not (member name '("." ".."))))))

  (defun mp/treemacs--append-face (start end face)
    "Append FACE to the existing face property between START and END."
    (let* ((existing (get-text-property start 'face))
           (faces (delete-dups
                   (append (if (listp existing) existing (list existing))
                           (list face)))))
      (put-text-property start end 'face (delq nil faces))))

  (defun mp/treemacs-apply-dotfile-face-h ()
    "Dim dotfiles in the current Treemacs buffer without hiding git status."
    (when (derived-mode-p 'treemacs-mode)
      (let ((inhibit-read-only t)
            (btn (next-button (point-min) t)))
        (while btn
          (let ((path (ignore-errors (treemacs-button-get btn :path))))
            (when (and (stringp path)
                       (mp/treemacs--dotfile-p path))
              (mp/treemacs--append-face
               (button-start btn)
               (button-end btn)
               'mp/treemacs-dotfile-face)))
          (setq btn (next-button (button-end btn) t))))))

  (add-hook 'treemacs-post-buffer-init-hook #'mp/treemacs-apply-dotfile-face-h)
  (add-hook 'treemacs-post-refresh-hook #'mp/treemacs-apply-dotfile-face-h))

(after! magit
  (setq magit-diff-refine-hunk 'all
        ;; Keep whitespace visible inside refined hunks so indentation-only
        ;; changes are highlighted instead of being treated as irrelevant.
        magit-diff-refine-ignore-whitespace nil
        ;; Paint actual whitespace problems in both added and removed lines.
        magit-diff-paint-whitespace t
        magit-diff-paint-whitespace-lines 'both
        magit-diff-highlight-trailing t))

(use-package! eldoc-box
  :after eglot
  :hook (eglot-managed-mode . eldoc-box-hover-at-point-mode)
  :config
  (setq eldoc-box-clear-with-C-g t
        eldoc-box-only-multi-line t
        eldoc-box-max-pixel-width 720
        eldoc-box-max-pixel-height 360
        eldoc-box-offset '(16 12 16)))

(setq confirm-kill-emacs nil)
