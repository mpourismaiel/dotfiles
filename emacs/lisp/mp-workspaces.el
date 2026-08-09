;;; mp-workspaces.el --- Perspective workspaces, projectile, persistence, splash -*- lexical-binding: t; -*-

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

;; Everything below calls persp-* at command time, but the splash/session code
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
  "Make a newly-created workspace visibly fresh: one window, splash shown."
  (delete-other-windows)
  (switch-to-buffer (mp/splash-buffer)))

(defun mp/workspace-new ()
  "Create and switch to a new automatically-named workspace.
The new workspace opens on the splash overview (like the old dashboard),
so it is obvious the switch happened."
  (interactive)
  (let* ((taken (mp/workspace-names))
         (n (cl-loop for i from 1
                     unless (member (format "#%d" i) taken)
                     return i)))
    (persp-switch (format "#%d" n))
    (mp/workspace--show-fresh)))

(defun mp/workspace-new-named (name)
  "Create and switch to workspace NAME, showing the splash overview."
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
the splash overview instead of leaving a dead frame."
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

(defun mp/workspace--label (name)
  "Positional label for workspace NAME: \"INDEX project\" (or the raw name
when no project is assigned). Indices are 1-based positions in
`persp-names', so killing a middle workspace renumbers the ones after it —
matching the SPC TAB 1..9 switch keys."
  (let ((idx (1+ (or (seq-position (mp/workspace-names) name) 0)))
        (root (mp/workspace--project-root name)))
    (format "%d %s" idx
            (if root
                (file-name-nondirectory (directory-file-name root))
              name))))

;; Opening a project via `SPC p p' (projectile) assigns it to the current
;; workspace, so labels/splash know the association without using bundles.
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

(defun mp/splash--recent-project-files (root n)
  (when root
    (seq-take
     (seq-filter (lambda (f) (string-prefix-p (expand-file-name root)
                                              (expand-file-name f)))
                 recentf-list)
     n)))

(defun mp/splash--heading (text)
  (insert (propertize (format "   %s\n" text) 'face 'font-lock-keyword-face)))

(defun mp/splash-refresh ()
  "(Re)build the splash buffer for the current workspace.
Degrades gracefully when perspective isn't loaded yet (this runs as
`initial-buffer-choice' during startup, before elpaca settles — an error
here would silently fall back to *scratch*)."
  (let* ((buf (get-buffer-create "*splash*"))
         (persp-ready (bound-and-true-p persp-mode))
         (current (if persp-ready (mp/workspace-current-name) "main"))
         (root (and persp-ready
                    (or (mp/workspace--project-root current)
                        (and (fboundp 'projectile-project-root)
                             (projectile-project-root)))))
         (branch (when root
                   (let ((default-directory root))
                     (car (ignore-errors
                            (process-lines "git" "rev-parse" "--abbrev-ref" "HEAD")))))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "\n\n")
        (insert (propertize (format "   %s\n" current)
                            'face '(:height 1.6 :weight bold)))
        (insert (propertize (if root
                                (format "   %s%s\n"
                                        (abbreviate-file-name root)
                                        (if branch (format "  ·  %s" branch) ""))
                              "   no project — pick one below or SPC p p\n")
                            'face 'font-lock-comment-face))
        (insert "\n")

        ;; Active workspaces (RET/click switches).
        (when persp-ready
          (mp/splash--heading "Workspaces")
          (dolist (name (mp/workspace-names))
            (let ((n name))
              (insert-text-button
               (format "   %s%s\n"
                       (if (equal n current) "▶ " "  ")
                       (mp/workspace--label n))
               'action (lambda (_) (persp-switch n))
               'follow-link t)))
          (insert "\n"))

        ;; Known projects (RET/click opens in THIS workspace).
        (mp/splash--heading "Projects")
        (dolist (project (seq-take (and (fboundp 'projectile-relevant-known-projects)
                                        (projectile-relevant-known-projects))
                                   10))
          (let ((p project))
            (insert-text-button
             (format "     %s\n"
                     (file-name-nondirectory (directory-file-name p)))
             'action (lambda (_) (mp/open-project-root p))
             'follow-link t
             'help-echo p)))
        (insert "\n")

        ;; Recent files of the current project.
        (when-let* ((recent (mp/splash--recent-project-files root 6)))
          (mp/splash--heading "Recent")
          (dolist (file recent)
            (let ((f file))
              (insert-text-button
               (format "     %s\n" (file-relative-name f root))
               'action (lambda (_) (find-file f))
               'follow-link t)))
          (insert "\n"))

        (insert (propertize
                 "   SPC p p projects · SPC TAB n new workspace · SPC SPC menu\n"
                 'face 'font-lock-comment-face)))
      (goto-char (point-min))
      (special-mode)
      (setq-local cursor-type nil))
    buf))

(defun mp/splash-buffer ()
  "Return the splash buffer, refreshed."
  (mp/splash-refresh))

(setq initial-buffer-choice #'mp/splash-buffer)

;;; Fresh splits (port of the Splits section; dashboard -> splash)

(defun mp/split-target-buffer ()
  "Populate a newly-created split.
Splitting from a Ghostel terminal opens a fresh terminal in the new
split; otherwise show the splash overview."
  (if (derived-mode-p 'ghostel-mode)
      (mp/ghostel-new)
    (switch-to-buffer (mp/splash-buffer))))

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
