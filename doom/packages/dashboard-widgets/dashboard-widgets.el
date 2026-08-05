;;; dashboard-widgets.el --- Custom Doom dashboard: layout, project helpers and widgets  -*- lexical-binding: t; -*-
;;; Commentary:
;; Custom splash dashboard: layout and faces, project helpers, rendering
;; helpers and the widgets that make up the startup screen.
;;; Code:

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

(provide 'dashboard-widgets)
;;; dashboard-widgets.el ends here
