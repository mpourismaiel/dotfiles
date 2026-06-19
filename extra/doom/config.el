;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

(require 'acp)
(require 'agent-shell)

(setq user-full-name "Mahdi Pourismaiel"
      user-mail-address "mpourismaiel@gmail.com")

(defun mp/nvm-add-to-path ()
  "Add the nvm default node bin directory to `exec-path' and PATH."
  (let* ((nvm-dir (expand-file-name "~/.nvm"))
         (alias-file (expand-file-name "alias/default" nvm-dir))
         (versions-dir (expand-file-name "versions/node" nvm-dir)))
    (when (file-readable-p alias-file)
      (let* ((alias (string-trim (with-temp-buffer
                                   (insert-file-contents alias-file)
                                   (buffer-string))))
             (match (car (last (sort
                                (seq-filter #'file-directory-p
                                            (file-expand-wildcards
                                             (expand-file-name (concat alias "*") versions-dir)))
                                #'string<))))
             (bin (when match (expand-file-name "bin" match))))
        (when (and bin (file-directory-p bin))
          (add-to-list 'exec-path bin)
          (setenv "PATH" (concat bin path-separator (getenv "PATH"))))))))

(mp/nvm-add-to-path)

(setq doom-theme nil)

(load-theme 'doom-one t)
(add-to-list 'custom-theme-load-path
             (expand-file-name "themes" doom-user-dir))
(load-theme 'dobri-c07 t)

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

(require 'subr-x)
(require 'seq)

(use-package! breadcrumb
  :defer t
  :init
  (setq breadcrumb-project-max-length 0.42
        breadcrumb-imenu-max-length 0.36
        breadcrumb-project-crumb-separator " / "
        breadcrumb-imenu-crumb-separator " > "))

(defvar mp/header-line-height 32
  "Target height of the custom header line, in pixels.")

(defvar mp/header-line-horizontal-padding " "
  "Horizontal padding inserted around each header line block.")

(defvar mp/header-line-buffer-foreground-faces
  '(doom-modeline-buffer-file mode-line-buffer-id mode-line)
  "Faces whose foreground is reused for header file and major-mode text.")

(defvar mp/header-line-position-foreground-faces
  '(doom-modeline mode-line line-number)
  "Faces whose foreground is reused for the header status text.")

(custom-set-faces!
  '(header-line :inherit mode-line))

(defun mp/header-line-color-value (value)
  "Return VALUE unless it is an unspecified face color."
  (unless (or (null value)
              (eq value 'unspecified)
              (and (stringp value)
                   (string-prefix-p "unspecified-" value)))
    value))

(defun mp/header-line-face-attribute (face attribute)
  "Return FACE ATTRIBUTE after resolving inheritance where possible."
  (when (facep face)
    (mp/header-line-color-value
     (face-attribute face attribute nil 'default))))

(defun mp/header-line-first-face-attribute (faces attribute fallback)
  "Return the first usable ATTRIBUTE from FACES, or FALLBACK."
  (or (catch 'value
        (dolist (face faces)
          (when-let ((value (mp/header-line-face-attribute face attribute)))
            (throw 'value value))))
      (mp/header-line-color-value fallback)))

(defun mp/header-line-background ()
  "Return the themed background color for the header line."
  (mp/header-line-first-face-attribute
   '(header-line mode-line default)
   :background
   (face-attribute 'default :background nil 'default)))

(defun mp/header-line-buffer-foreground ()
  "Return the themed modeline buffer-name foreground color."
  (mp/header-line-first-face-attribute
   mp/header-line-buffer-foreground-faces
   :foreground
   (face-attribute 'mode-line :foreground nil 'default)))

(defun mp/header-line-position-foreground ()
  "Return the themed modeline position foreground color."
  (mp/header-line-first-face-attribute
   mp/header-line-position-foreground-faces
   :foreground
   (face-attribute 'mode-line :foreground nil 'default)))

(defun mp/header-line-vertical-padding ()
  "Return vertical padding needed to approach `mp/header-line-height'."
  (if (display-graphic-p)
      (ceiling (max 0 (- mp/header-line-height (frame-char-height))) 2)
    0))

(defun mp/header-line-face (foreground background &optional weight)
  "Return a face plist for a padded header line block."
  (append
   (when foreground
     `(:foreground ,foreground))
   (when background
     `(:background ,background))
   (when weight
     `(:weight ,weight))
   (when-let ((padding (mp/header-line-vertical-padding)))
     (when (> padding 0)
       `(:box (:line-width (0 . ,padding)
               ,@(when background
                   `(:color ,background))))))))

(defun mp/header-line-block (text face)
  "Return TEXT as a padded header line block using FACE."
  (propertize
   (concat mp/header-line-horizontal-padding
           text
           mp/header-line-horizontal-padding)
   'face face))

(defun mp/header-line-buffer-name ()
  "Return the file name or buffer name for the header line."
  (or (when buffer-file-name
        (file-name-nondirectory buffer-file-name))
      (buffer-name)
      ""))

(defun mp/header-line-mode-name ()
  "Return the current major mode name for the header line."
  (let ((name (string-trim (format-mode-line mode-name))))
    (if (string-empty-p name)
        "unknown"
      (downcase name))))

(defun mp/header-line-buffer-status ()
  "Return the current buffer status label."
  (cond (buffer-read-only
         "RO")
        ((buffer-modified-p)
         "W!")
        (t
         "RW")))

(defun mp/header-line-nonempty-string-p (value)
  "Return non-nil when VALUE is a non-empty string."
  (and (stringp value)
       (not (string-empty-p (string-trim (substring-no-properties value))))))

(defun mp/header-line-breadcrumbs ()
  "Return breadcrumb project and imenu context for the header line."
  (when (fboundp 'breadcrumb-project-crumbs)
    (let* ((project (ignore-errors (breadcrumb-project-crumbs)))
           (imenu (ignore-errors (breadcrumb-imenu-crumbs)))
           (crumbs (seq-filter #'mp/header-line-nonempty-string-p
                               (list project imenu))))
      (when crumbs
        (let ((padding (propertize mp/header-line-horizontal-padding
                                   'face 'header-line))
              (separator (propertize "  >  "
                                     'face (if (facep 'breadcrumb-face)
                                               'breadcrumb-face
                                             'shadow))))
          (concat padding
                  (string-join crumbs separator)
                  padding))))))

(after! flycheck
  (defun mp/flycheck-counts ()
    "Return (errors warnings infos) for current buffer."
    (let ((errors 0)
          (warnings 0)
          (infos 0))
      (dolist (err flycheck-current-errors)
        (pcase (flycheck-error-level err)
          ('error (cl-incf errors))
          ('warning (cl-incf warnings))
          ('info (cl-incf infos))))
      (list errors warnings infos)))

  (defun mp/header-line-diagnostics ()
    "Return a prominent diagnostics block for the header line."
    (when (bound-and-true-p flycheck-mode)
      (pcase-let ((`(,errors ,warnings ,infos) (mp/flycheck-counts)))
        (cond
         ((> errors 0)
          (mp/header-line-block
           (format "E:%d W:%d" errors warnings)
           (mp/header-line-face "#ffffff" "#ff5370" 'bold)))
         ((> warnings 0)
          (mp/header-line-block
           (format "W:%d" warnings)
           (mp/header-line-face "#1f2430" "#ffcb6b" 'bold)))
         ((> infos 0)
          (mp/header-line-block
           (format "I:%d" infos)
           (mp/header-line-face "#ffffff" "#82aaff" 'bold))))))))

(defun mp/header-line-format ()
  "Return a left-aligned custom header line for the current buffer."
  (let* ((background (mp/header-line-background))
         (buffer-foreground (mp/header-line-buffer-foreground))
         (breadcrumbs (mp/header-line-breadcrumbs))
         (status-background "#ecbe7b")
         (status-foreground "#ffffff")
         (status-face (mp/header-line-face status-foreground status-background 'bold))
         (buffer-face (mp/header-line-face buffer-foreground background 'bold))
         (major-face (mp/header-line-face buffer-foreground background 'normal)))
    (delq nil
          (list
           (mp/header-line-block (mp/header-line-buffer-status) status-face)
           (or breadcrumbs
               (mp/header-line-block (mp/header-line-buffer-name) buffer-face))
           (mp/header-line-block (mp/header-line-mode-name) major-face)
           (when (fboundp 'mp/header-line-diagnostics)
             (mp/header-line-diagnostics))))))

(setq-default header-line-format '(:eval (mp/header-line-format)))

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

;; Disable annoying emacs exit confirmation message
(setq confirm-kill-emacs nil)

;; Send files to trash instead of fully deleting.
(setq delete-by-moving-to-trash t)

;; Save automatically.
(setq auto-save-default t)

(setq scroll-preserve-screen-position t
      scroll-conservatively 101
      scroll-margin 0
      mouse-wheel-follow-mouse t
      mouse-wheel-scroll-amount '(3 ((shift) . 1))
      mouse-wheel-progressive-speed nil)

(after! evil
  (setq evil-want-C-u-scroll t))

(use-package! expand-region
  :commands (er/expand-region er/contract-region)
  :init
  (map! :g "M-d" #'er/expand-region
        :g "M-D" #'er/contract-region))

(defvar mp/project-bundles nil
  "Private project bundles loaded from private.el.")

(defvar mp/workspace-project-roots (make-hash-table :test 'equal)
  "Map Doom workspace names to their intended project roots.")

(let ((private-config "~/.config/doom/private.el"))
  (when (file-exists-p private-config)
    (load-file private-config)))

(defun mp/current-workspace-project-root ()
  "Return the project root explicitly assigned to the current workspace."
  (when (fboundp '+workspace-current-name)
    (gethash (+workspace-current-name) mp/workspace-project-roots)))

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
    (setq default-directory dir)
    (if file
        (find-file (expand-file-name file dir))
      (dired dir))))

(defun mp/open-project-bundle (bundle-name)
  "Open project bundle BUNDLE-NAME in separate Doom workspaces."
  (interactive
   (list (completing-read "Bundle: " (mapcar #'car mp/project-bundles) nil t)))
  (let ((projects (cdr (assoc bundle-name mp/project-bundles))))
    (unless projects
      (user-error "Unknown bundle: %s" bundle-name))
    (dolist (project projects)
      (let* ((workspace (car project))
             (root (file-name-as-directory (expand-file-name (cdr project)))))
        (+workspace-switch workspace t)
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

(map! :leader
      :desc "Project menu"
      "p p" #'mp/project-menu)

(defun mp/split-target-buffer ()
  "Populate a newly-created split."
  (if (derived-mode-p 'vterm-mode)
      ;; If we're currently in vterm, create a fresh vterm.
      (mp/vterm-new)

    ;; Otherwise show the Doom dashboard.
    (cond
     ;; Reuse existing dashboard buffer.
     ((get-buffer "*doom*")
      (switch-to-buffer "*doom*"))

     ;; Create a dashboard if possible.
     ((fboundp '+doom-dashboard/open)
      (+doom-dashboard/open))

     ;; Fallback for non-dashboard Doom configs.
     (t
      (switch-to-buffer (generate-new-buffer "untitled"))))))

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

(map! :leader
      (:prefix ("w" . "window")
       :desc "Split right (fresh)" "v" #'mp/split-window-right-fresh
       :desc "Split below (fresh)" "s" #'mp/split-window-below-fresh))

(after! popup
  (set-popup-rule! "^\\*Flycheck errors" :side 'bottom :size 0.25 :select t :quit t)
  (set-popup-rule! "^\\*xref\\*"          :side 'bottom :size 0.3  :select t :quit t)
  (set-popup-rule! "^\\*Warnings\\*"      :side 'bottom :size 0.25 :select t :quit t)
  (set-popup-rule! "^\\*Backtrace\\*"     :side 'bottom :size 0.35 :select t :quit nil))

(defun mp/save-without-format ()
  "Save current buffer without running format-on-save hooks."
  (interactive)
  (let ((before-save-hook
         (remove #'+format/buffer before-save-hook)))
    (save-buffer)))

(map! :leader
      (:prefix ("f" . "file")
        :desc "Save without formatting" "!"
        #'mp/save-without-format))

(after! format-all
  (setq-hook! '(js-mode-hook
                js-ts-mode-hook
                typescript-mode-hook
                typescript-ts-mode-hook
                typescript-tsx-mode-hook
                tsx-ts-mode-hook
                web-mode-hook
                css-mode-hook
                css-ts-mode-hook
                scss-mode-hook)
    +format-with 'prettier))

;; ((nil . ((eval . (format-all-mode -1)))))

;; ((python-mode . ((+format-with . ("ruff" "format" "-"))))
;;  (python-ts-mode . ((+format-with . ("ruff" "format" "-")))))

(after! orderless
  ;; Make every component match as a fuzzy subsequence in addition to the
  ;; literal/regexp styles. This is the "VSCode fuzzy" half.
  (setq orderless-matching-styles
        '(orderless-literal orderless-regexp orderless-flex))

  (setq completion-styles '(orderless basic)
        completion-category-defaults nil
        completion-category-overrides
        '((file (styles orderless partial-completion))
          (lsp-capf (styles orderless basic)))))

(use-package! prescient
  :config
  (setq prescient-sort-full-matches-first t)
  (prescient-persist-mode 1))

(use-package! corfu-prescient
  :after corfu
  :config
  (setq corfu-prescient-enable-filtering nil   ; keep orderless for filtering
        corfu-prescient-enable-sorting t        ; let prescient sort
        corfu-prescient-override-sorting nil)
  (corfu-prescient-mode 1))

(use-package! vertico-prescient
  :after vertico
  :config
  (setq vertico-prescient-enable-filtering nil
        vertico-prescient-enable-sorting t
        vertico-prescient-override-sorting nil)
  (vertico-prescient-mode 1))

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

(use-package! evil-mc
  :after evil
  :config
  (global-evil-mc-mode 1)

  (map! :n "C-M-<down>"  #'evil-mc-make-cursor-move-next-line
        :n "C-M-<up>"    #'evil-mc-make-cursor-move-prev-line
        :n "C-M-<right>" #'evil-mc-make-all-cursors)

  (defun my/evil-mc-escape ()
    (interactive)
    (if (and (bound-and-true-p evil-mc-mode)
             evil-mc-cursor-list)
        (evil-mc-undo-all-cursors)
      (evil-force-normal-state)))

  (map! :i "<escape>" #'my/evil-mc-escape
        :n "<escape>" #'my/evil-mc-escape))

(map! :nv "C-d" #'evil-multiedit-match-and-next
      :i  "C-d" #'evil-multiedit-toggle-marker-here)

(use-package! color-rg
  :commands (color-rg-search-input
             color-rg-search-symbol
             color-rg-search-input-in-project
             color-rg-search-symbol-in-project
             color-rg-search-input-in-current-file
             color-rg-search-symbol-in-current-file)
  :init
  ;; `color-rg-mac-load-path-from-shell' only matters on macOS; Doom already
  ;; manages PATH (see the NVM Path section), so the shell import is unneeded.
  (setq color-rg-mac-load-path-from-shell nil)
  ;; NOTE: `SPC s r' is bound to `evil-show-marks' in Doom, so it can't become
  ;; a prefix until that binding is cleared. Unbind it first, then nest under it.
  (map! :leader
        (:prefix ("s" . "search")
         "r" nil
         (:prefix ("r" . "color-rg")
          :desc "Search in file"    "f" #'color-rg-search-input-in-current-file
          :desc "Search in project" "p" #'color-rg-search-input-in-project)))
  :config
  ;; Respect .gitignore so project searches stay focused like an IDE.
  ;; Toggle per-search inside the results buffer with `I'.
  (setq color-rg-search-no-ignore-file nil)
  ;; `color-rg-mode' derives from `text-mode' and ships its own single-key view
  ;; bindings (j/k navigate, e edit, r replace, q quit). Hand the buffer to
  ;; Evil's Emacs state so those keys aren't shadowed.
  (after! evil
    (evil-set-initial-state 'color-rg-mode 'emacs)))

(setq treesit-auto-install-grammar 'always)

(after! treesit-fold
  (dolist (mode '(js-mode js-ts-mode javascript-mode))
    (when-let ((cell (assq mode treesit-fold-range-alist)))
      (dolist (rule '((jsx_element  . treesit-fold-range-html)
                      (jsx_fragment . treesit-fold-range-html)))
        (unless (assq (car rule) (cdr cell))
          (setcdr cell (append (cdr cell) (list rule))))))))

(defun mp/treesit-fold-active-p ()
  "Return non-nil when `treesit-fold' can operate on the current buffer."
  (and (fboundp 'treesit-fold-ready-p)
       (treesit-fold-ready-p)
       (treesit-fold-usable-mode-p)))

(defun mp/treesit-fold--node-foldable-p (node)
  "Return non-nil when NODE defines a multi-line fold."
  (when-let ((range (treesit-fold--get-fold-range node)))
    (not (treesit-fold--range-on-same-line range))))

(defun mp/treesit-fold--depth (node)
  "Return the fold-nesting depth of NODE (1 = outermost foldable)."
  (let ((depth 0)
        (current node))
    (while current
      (when (mp/treesit-fold--node-foldable-p current)
        (cl-incf depth))
      (setq current (treesit-node-parent current)))
    depth))

(defun mp/treesit-fold--foldable-nodes ()
  "Return every multi-line foldable node in the buffer."
  (let* ((root (treesit-buffer-root-node))
         (ranges (alist-get major-mode treesit-fold-range-alist))
         (patterns (seq-mapcat (lambda (range) `((,(car range)) @name)) ranges))
         (query (treesit-query-compile (treesit-node-language root) patterns)))
    (cl-remove-if-not #'mp/treesit-fold--node-foldable-p
                      (mapcar #'cdr (treesit-query-capture root query)))))

(defun mp/treesit-fold-to-level (level)
  "Fold every node at LEVEL, keeping shallower levels open (VSCode-style).
If LEVEL is already folded, reveal everything instead."
  (let* ((nodes (mp/treesit-fold--foldable-nodes))
         (depths (mapcar #'mp/treesit-fold--depth nodes))
         (max-depth (if depths (apply #'max depths) 0)))
    (when (zerop max-depth)
      (user-error "Nothing foldable in this buffer"))
    (let* ((level (min level max-depth))
           (at-level (cl-loop for node in nodes
                              for depth in depths
                              when (= depth level) collect node))
           (folded (cl-some #'treesit-fold-overlay-at at-level)))
      (treesit-fold-open-all)
      (if folded
          (message "Fold level %d revealed" level)
        (dolist (node at-level)
          (treesit-fold-close node))
        (message "Folded to level %d" level)))))

(defvar-local mp/fold--last-level nil
  "Last fold level applied in a non-tree-sitter buffer, for toggling.")

(defun mp/fold--fallback-to-level (level)
  "Fold to LEVEL with hideshow/outline, toggling open on repeat."
  (if (eq mp/fold--last-level level)
      (progn (+fold/open-all)
             (setq mp/fold--last-level nil)
             (message "Fold level %d revealed" level))
    (+fold/open-all)
    (+fold/close-all level)
    (setq mp/fold--last-level level)
    (message "Folded to level %d" level)))

(defun mp/fold-to-level (&optional level)
  "Fold all regions down to LEVEL (1 = outermost), VSCode-style.
Re-invoking the same level reveals everything again.  When called from the
z1..z9 keys, LEVEL is read from the triggering digit."
  (interactive)
  (let ((level (or level
                   (let ((event last-command-event))
                     (and (characterp event)
                          (<= ?1 event ?9)
                          (- event ?0))))))
    (unless (and (integerp level) (<= 1 level 9))
      (user-error "Fold level must be between 1 and 9"))
    (if (mp/treesit-fold-active-p)
        (mp/treesit-fold-to-level level)
      (mp/fold--fallback-to-level level))))

(after! evil
  (dolist (level (number-sequence 1 9))
    (let ((key (vector ?z (+ ?0 level))))
      (define-key evil-normal-state-map key #'mp/fold-to-level)
      (define-key evil-motion-state-map key #'mp/fold-to-level))))

;;; org-basic.el --- sane Org defaults for Doom
(setq org-directory "~/org/")

;; Files scanned by org-agenda.
;; Only put actionable/date-based files here.
(setq org-agenda-files
      '("~/org/inbox.org"
        "~/org/tasks.org"
        "~/org/projects.org"
        "~/org/calendar.org"))

;; Basic TODO workflow.
;; TODO      = not started
;; NEXT      = next concrete action
;; WAIT      = blocked by someone/something
;; SOMEDAY   = intentionally inactive
;; DONE      = completed
;; CANCELLED = no longer relevant
(setq org-todo-keywords
      '((sequence "TODO(t)" "NEXT(n)" "WAIT(w)" "SOMEDAY(s)" "|"
                  "DONE(d)" "CANCELLED(c)")))

;; Save timestamp when marking DONE.
(setq org-log-done 'time)

;; Save note when moving into WAIT or CANCELLED.
(setq org-todo-keyword-faces
      '(("TODO" . warning)
        ("NEXT" . success)
        ("WAIT" . font-lock-constant-face)
        ("SOMEDAY" . font-lock-doc-face)
        ("DONE" . shadow)
        ("CANCELLED" . shadow)))

(setq org-todo-keywords
      '((sequence "TODO" "|" "DONE")))

;; Use fast todo selection.
(setq org-use-fast-todo-selection t)

;; Hide completed scheduled/deadline tasks from agenda after done.
(setq org-agenda-skip-scheduled-if-done t)
(setq org-agenda-skip-deadline-if-done t)

;; Show agenda starting today.
;; (setq org-agenda-start-on-weekday nil)

;; Show 14 days by default.
(setq org-agenda-span 14)

;; Warn about deadlines 7 days in advance.
(setq org-deadline-warning-days 7)

;; Make indentation readable.
(setq org-startup-indented t)

;; Hide leading stars visually.
(setq org-hide-leading-stars t)

;; Open folded files cleanly.
(setq org-startup-folded 'content)

;; Log state changes into a drawer to avoid visual noise.
(setq org-log-into-drawer t)

;; Refile targets.
;; This lets you move captured items from inbox.org into real files.
(setq org-refile-targets
      '(("~/org/tasks.org" :maxlevel . 3)
        ("~/org/projects.org" :maxlevel . 4)
        ("~/org/calendar.org" :maxlevel . 2)
        ("~/org/someday.org" :maxlevel . 2)))

;; Make refile completion use full paths.
(setq org-refile-use-outline-path 'file)
(setq org-outline-path-complete-in-steps nil)

;; Archive completed old tasks here.
(setq org-archive-location "~/org/archive.org::* From %s")

;; Capture templates.
(setq org-capture-templates
      '(("t" "Todo" entry
         (file "~/org/inbox.org")
         "* TODO %?\nCREATED: %U\n")

        ("d" "Todo with deadline" entry
         (file "~/org/inbox.org")
         "* TODO %?\nDEADLINE: %^t\nCREATED: %U\n")

        ("s" "Scheduled todo" entry
         (file "~/org/inbox.org")
         "* TODO %?\nSCHEDULED: %^t\nCREATED: %U\n")

        ("e" "Event / calendar date" entry
         (file "~/org/calendar.org")
         "* %?\n%^T\n")

        ("r" "Repeating event" entry
         (file "~/org/calendar.org")
         "* %?\n%^T\n")

        ("p" "Project task" entry
         (file "~/org/projects.org")
         "* TODO %?\nCREATED: %U\n")

        ("n" "Note" entry
         (file "~/org/notes.org")
         "* %?\nCREATED: %U\n")))

;; Custom agenda views.
(setq org-agenda-custom-commands
      '(("d" "Dashboard"
         ((agenda "" ((org-agenda-span 14)))
          (todo "NEXT"
                ((org-agenda-overriding-header "Next actions")))
          (todo "WAIT"
                ((org-agenda-overriding-header "Waiting")))
          (todo "TODO"
                ((org-agenda-overriding-header "Unprocessed todos")))))

        ("i" "Inbox"
         ((tags "REFILE|TODO"
                ((org-agenda-files '("~/org/inbox.org"))
                 (org-agenda-overriding-header "Inbox")))))

        ("p" "Projects"
         ((tags "project"
                ((org-agenda-overriding-header "Projects")))))))

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

(add-hook 'org-mode-hook 'visual-line-mode)
(add-hook 'org-mode-hook 'olivetti-mode)
(add-hook 'org-mode-hook (lambda () (display-line-numbers-mode -1)))

;; Show line numbers only in insert state, hide in normal state.
(add-hook 'evil-insert-state-entry-hook
          (lambda () (when (derived-mode-p 'org-mode) (display-line-numbers-mode 1))))
(add-hook 'evil-insert-state-exit-hook
          (lambda () (when (derived-mode-p 'org-mode) (display-line-numbers-mode -1))))

(after! org
  ;; Prevent alphabetical list markers from conflicting with checkbox parsing.
  (setq org-list-allow-alphabetical nil)

  (setq org-auto-align-tags nil
        org-tags-column 0
        org-fold-catch-invisible-edits 'show-and-error        org-special-ctrl-a/e t
        org-insert-heading-respect-content t
        org-hide-emphasis-markers t
        org-pretty-entities t
        org-agenda-tags-column 0
        org-ellipsis "…"))

(after! org-modern
  (setq org-modern-symbol 'caskaydia)
  (dolist (face '(window-divider
                  window-divider-first-pixel
                  window-divider-last-pixel))
    (face-spec-reset-face face)
    (set-face-foreground face (face-attribute 'default :background)))
  ;; (set-face-background 'fringe (face-attribute 'default :background))
  (setq org-modern-block-fringe t)
  (global-org-modern-mode))

(use-package doom-modeline
  :ensure t
  :hook (emacs-startup . doom-modeline-mode)
  :config (column-number-mode 1)
  :custom
  (doom-modeline-height 40)
  (doom-modeline-window-width-limit nil)

  (doom-modeline-buffer-file-name-style 'relative-from-project)

  (doom-modeline-icon t)
  (doom-modeline-major-mode-color-icon t)
  (doom-modeline-buffer-modification-icon t)
  (doom-modeline-buffer-state-icon t)

  (doom-modeline-indent-info t))

(use-package! vertico-posframe
  :after vertico
  :config
  (setq vertico-posframe-width 120
        vertico-posframe-height 18
        vertico-posframe-border-width 4
        vertico-posframe-poshandler #'posframe-poshandler-frame-center
        vertico-posframe-parameters
        '((left-fringe . 16)
          (right-fringe . 16)
          (internal-border-width . 12)
          (alpha-background . 96)
          (undecorated . t)))

  (vertico-posframe-mode 1))

(use-package! spacious-padding
  :custom
  (spacious-padding-widths
        '( :internal-border-width 8
           :header-line-width 0
           :mode-line-width 0
           :tab-width 4
           :right-divider-width 30
           :scroll-bar-width 8))

  (spacious-padding-mode 1))

(use-package! rainbow-delimiters
  :hook ((prog-mode . rainbow-delimiters-mode)))

(require 'svg)

(declare-function diff-hl-changes "diff-hl")
(declare-function diff-hl-changes-from-buffer "diff-hl")

(defvar mp/overview-ruler-width 3
  "Width of the overview ruler window, in columns.")

(defvar mp/overview-ruler-idle 0.3
  "Idle seconds before the overview ruler refreshes.")

(defconst mp/overview-ruler--buffer-name "*overview-ruler*")
(defvar mp/overview-ruler--timer nil)

;; Per-source-buffer git cache so we don't run a vc diff on every refresh.
(defvar-local mp/overview-ruler--git-cache nil)
(defvar-local mp/overview-ruler--git-tick nil)

(defun mp/overview-ruler--face-color (face attr fallback)
  "FACE's ATTR as a color string, or FALLBACK."
  (or (and (facep face)
           (let ((c (face-attribute face attr nil t)))
             (and (stringp c) c)))
      fallback))

(defun mp/overview-ruler--git-color (type)
  "Color string for a git change of TYPE."
  (pcase type
    ('insert (mp/overview-ruler--face-color 'diff-hl-insert :foreground "#3fb950"))
    ('delete (mp/overview-ruler--face-color 'diff-hl-delete :foreground "#f85149"))
    (_       (mp/overview-ruler--face-color 'diff-hl-change :foreground "#58a6ff"))))

(defun mp/overview-ruler--diag-color (sev)
  "Color string for a diagnostic of severity SEV."
  (pcase sev
    ('error   (mp/overview-ruler--face-color 'flycheck-fringe-error   :foreground "#f85149"))
    ('warning (mp/overview-ruler--face-color 'flycheck-fringe-warning :foreground "#d29922"))
    (_        (mp/overview-ruler--face-color 'flycheck-fringe-info    :foreground "#58a6ff"))))

(defun mp/overview-ruler--git-changes ()
  "List of (START-LINE NLINES TYPE) for the current buffer, or nil.
Reflects the last SAVED state unless `diff-hl-flydiff-mode' is on."
  (when (and (fboundp 'diff-hl-changes) buffer-file-name)
    (ignore-errors
      (let* ((alist (diff-hl-changes))
             (working (cdr (assq :working alist)))
             (changes (if (bufferp working)
                          (diff-hl-changes-from-buffer working)
                        working))
             res)
        (dolist (c changes)
          (pcase-let ((`(,line ,inserts ,_deletes ,type) c))
            (push (list line (if (eq type 'delete) 1 (max 1 inserts)) type) res)))
        (nreverse res)))))

(defun mp/overview-ruler--git ()
  "Cached `mp/overview-ruler--git-changes', recomputed only after edits."
  (let ((tick (buffer-modified-tick)))
    (unless (eql tick mp/overview-ruler--git-tick)
      (setq mp/overview-ruler--git-tick tick
            mp/overview-ruler--git-cache (mp/overview-ruler--git-changes)))
    mp/overview-ruler--git-cache))

(defun mp/overview-ruler--diagnostics ()
  "List of (LINE . SEVERITY) where SEVERITY is `error', `warning' or `info'."
  (cond
   ((bound-and-true-p flycheck-mode)
    (mapcar (lambda (e)
              (cons (flycheck-error-line e)
                    (pcase (flycheck-error-level e)
                      ('error 'error) ('warning 'warning) (_ 'info))))
            flycheck-current-errors))
   ((bound-and-true-p flymake-mode)
    (let (res)
      (dolist (d (flymake-diagnostics))
        (let ((name (format "%s" (flymake-diagnostic-type d))))
          (push (cons (line-number-at-pos (flymake-diagnostic-beg d))
                      (cond ((string-match-p "error" name) 'error)
                            ((string-match-p "warn"  name) 'warning)
                            (t 'info)))
                res)))
      res))))

(defun mp/overview-ruler--render (src-buf src-win ruler-win)
  "Draw the SVG ruler for SRC-BUF / SRC-WIN into RULER-WIN."
  (let ((w (max 8 (window-body-width ruler-win t)))
        (h (max 1 (window-body-height ruler-win t)))
        git diags n top-line bot-line)
    (with-current-buffer src-buf
      (setq n (max 1 (line-number-at-pos (point-max)))
            git (mp/overview-ruler--git)
            diags (mp/overview-ruler--diagnostics))
      (when (window-live-p src-win)
        (setq top-line (line-number-at-pos (window-start src-win))
              bot-line (line-number-at-pos (window-end src-win t)))))
    (let* ((svg (svg-create w h))
           (y-of (lambda (line) (floor (* (/ (float (1- (max 1 line))) n) h)))))
      (svg-rectangle svg 0 0 w h
                     :fill (mp/overview-ruler--face-color 'default :background "#0d1117"))
      (dolist (c git)
        (pcase-let ((`(,line ,nlines ,type) c))
          (svg-rectangle svg 0 (funcall y-of line)
                         w (max 3 (floor (* (/ (float nlines) n) h)))
                         :fill (mp/overview-ruler--git-color type))))
      (dolist (d diags)
        (svg-rectangle svg 0 (funcall y-of (car d))
                       w (max 3 (floor (/ (float h) n)))
                       :fill (mp/overview-ruler--diag-color (cdr d))))
      (when (and top-line bot-line)
        (let ((top (funcall y-of top-line))
              (bot (funcall y-of bot-line)))
          (svg-rectangle svg 0 top (1- w) (max 2 (- bot top))
                         :fill "none"
                         :stroke (mp/overview-ruler--face-color 'region :background "#6e7681")
                         :stroke-width 1)))
      (with-current-buffer (get-buffer-create mp/overview-ruler--buffer-name)
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert-image (svg-image svg)))))))

(defun mp/overview-ruler--setup-buffer (buf)
  "Initialize the ruler BUF: read-only, no chrome."
  (with-current-buffer buf
    (setq mode-line-format nil header-line-format nil cursor-type nil
          truncate-lines t buffer-read-only t)
    (buffer-disable-undo)))

(defun mp/overview-ruler--window ()
  "Return the ruler window, creating the buffer + side window if needed."
  (let ((buf (get-buffer-create mp/overview-ruler--buffer-name)))
    (mp/overview-ruler--setup-buffer buf)
    (or (get-buffer-window buf t)
        (let ((win (display-buffer-in-side-window
                    buf `((side . right) (slot . 1)
                          (window-width . ,mp/overview-ruler-width)
                          (window-parameters . ((no-other-window . t)
                                                (no-delete-other-windows . t)))))))
          (when win (set-window-fringes win 0 0))
          win))))

(defun mp/overview-ruler--refresh ()
  "Refresh the ruler for the currently selected file window."
  (when (bound-and-true-p mp/overview-ruler-mode)
    (let* ((win (selected-window))
           (buf (window-buffer win)))
      (unless (or (window-minibuffer-p win)
                  (string= (buffer-name buf) mp/overview-ruler--buffer-name)
                  (not (buffer-file-name (or (buffer-base-buffer buf) buf))))
        (let ((ruler (mp/overview-ruler--window)))
          (when (window-live-p ruler)
            (mp/overview-ruler--render buf win ruler)))))))

(define-minor-mode mp/overview-ruler-mode
  "Global VSCode-style overview ruler with git and diagnostic lanes."
  :global t
  (if mp/overview-ruler-mode
      (progn
        (unless (image-type-available-p 'svg)
          (setq mp/overview-ruler-mode nil)
          (user-error "overview-ruler needs an Emacs built with SVG (librsvg)"))
        (setq mp/overview-ruler--timer
              (run-with-idle-timer mp/overview-ruler-idle t #'mp/overview-ruler--refresh))
        (add-hook 'window-configuration-change-hook #'mp/overview-ruler--refresh))
    (when mp/overview-ruler--timer (cancel-timer mp/overview-ruler--timer))
    (setq mp/overview-ruler--timer nil)
    (remove-hook 'window-configuration-change-hook #'mp/overview-ruler--refresh)
    (let ((win (get-buffer-window mp/overview-ruler--buffer-name t)))
      (when (window-live-p win) (delete-window win)))
    (when (get-buffer mp/overview-ruler--buffer-name)
      (kill-buffer mp/overview-ruler--buffer-name))))

(map! :leader :desc "Overview ruler" "t o" #'mp/overview-ruler-mode)

;; On by default once Emacs has settled, but only when SVG is available so a
;; non-SVG build doesn't trip the mode's `user-error' during startup.
(add-hook 'doom-after-init-hook
          (lambda ()
            (when (image-type-available-p 'svg)
              (mp/overview-ruler-mode 1))))

(after! corfu
  (setq corfu-auto t
        corfu-preview-current nil
        corfu-preselect 'prompt
        corfu-cycle t
        corfu-on-exact-match nil))

(after! corfu-auto
  (setq corfu-auto-delay 0.12
        corfu-auto-prefix 2))

(after! corfu-popupinfo
  (setq corfu-popupinfo-delay '(0.35 . 0.2)))

;;; consult-buffer with history-sorted custom sources.

(defun mp/project-workspace-p ()
  "Return non-nil when the current workspace has a Projectile project."
  (and (bound-and-true-p projectile-mode)
       (projectile-project-p)))

(defun mp/workspace-buffers ()
  "Return buffers belonging to current Doom workspace."
  (if (fboundp '+workspace-buffer-list)
      (+workspace-buffer-list)
    (buffer-list)))

(defun mp/current-workspace-buffer-p (buf)
  "Return non-nil if BUF belongs to current Doom workspace."
  (memq buf (mp/workspace-buffers)))

(defun mp/vterm-buffer-p (buf)
  "Return non-nil if BUF is a vterm buffer."
  (with-current-buffer buf
    (derived-mode-p 'vterm-mode)))

(defun mp/agent-shell-buffer-p (buf)
  "Return non-nil if BUF is an agent-shell/Codex agent buffer."
  (let ((name (buffer-name buf)))
    (or (string-match-p "\\`Agent @ " name)
        (string-match-p "\\`\\*agent-shell" name)
        (with-current-buffer buf
          (or (derived-mode-p 'agent-shell-mode)
              (derived-mode-p 'codex-mode))))))

(defun mp/special-buffer-p (buf)
  "Return non-nil if BUF is a special star buffer."
  (string-prefix-p "*" (buffer-name buf)))

(defun mp/normal-buffer-p (buf)
  "Return non-nil for ordinary user-facing buffers."
  (and (buffer-live-p buf)
       (not (mp/special-buffer-p buf))
       (not (mp/agent-shell-buffer-p buf))
       (not (mp/vterm-buffer-p buf))))

(defun mp/history-index (item history)
  "Return ITEM position in HISTORY, or a large number."
  (or (cl-position item history :test #'equal)
      most-positive-fixnum))

(defun mp/sort-strings-by-history (items history)
  "Sort string ITEMS by their position in HISTORY."
  (sort items
        (lambda (a b)
          (< (mp/history-index a history)
             (mp/history-index b history)))))

(defun mp/sort-cons-candidates-by-history (candidates history)
  "Sort cons CANDIDATES by their cdr position in HISTORY."
  (sort candidates
        (lambda (a b)
          (< (mp/history-index (cdr a) history)
             (mp/history-index (cdr b) history)))))

(defvar mp/consult-source-workspace-buffer
  `(:name "[B]uffer"
    :narrow (?b . "Buffer")
    :category buffer
    :face consult-buffer
    :history buffer-name-history
    :state ,#'consult--buffer-state
    :default t
    :enabled ,#'mp/project-workspace-p
    :items ,(lambda ()
              (mp/sort-strings-by-history
               (consult--buffer-query
                :sort nil
                :as #'buffer-name
                :predicate
                (lambda (buf)
                  (and (mp/current-workspace-buffer-p buf)
                       (mp/normal-buffer-p buf))))
               buffer-name-history))))

(defvar mp/consult-source-all-buffer
  `(:name "[B]uffer"
    :narrow (?b . "Buffer")
    :category buffer
    :face consult-buffer
    :history buffer-name-history
    :state ,#'consult--buffer-state
    :default t
    :enabled ,(lambda () (not (mp/project-workspace-p)))
    :items ,(lambda ()
              (mp/sort-strings-by-history
               (consult--buffer-query
                :sort nil
                :as #'buffer-name
                :predicate #'mp/normal-buffer-p)
               buffer-name-history))))

(defvar mp/consult-source-agent-shell-buffer
  `(:name "[A]gent Shell"
    :narrow (?a . "Agent Shell")
    :category buffer
    :face consult-buffer
    :history buffer-name-history
    :state ,#'consult--buffer-state
    :action ,#'consult--buffer-action
    :items ,(lambda ()
              (mp/sort-strings-by-history
               (consult--buffer-query
                :sort nil
                :as #'buffer-name
                :predicate
                (lambda (buf)
                  (and (if (mp/project-workspace-p)
                           (mp/current-workspace-buffer-p buf)
                         t)
                       (mp/agent-shell-buffer-p buf))))
               buffer-name-history))))

(defvar mp/consult-source-vterm-buffer
  `(:name "[V]Term"
    :narrow (?v . "VTerm")
    :category buffer
    :face consult-buffer
    :history buffer-name-history
    :state ,#'consult--buffer-state
    :action ,#'consult--buffer-action
    :items ,(lambda ()
              (mp/sort-strings-by-history
               (consult--buffer-query
                :sort nil
                :as #'buffer-name
                :predicate
                (lambda (buf)
                  (and (if (mp/project-workspace-p)
                           (mp/current-workspace-buffer-p buf)
                         t)
                       (mp/vterm-buffer-p buf))))
               buffer-name-history))))

(defun mp/live-project-files (root)
  "Return live relative file list under ROOT using fd, falling back to Elisp."
  (let ((root (file-name-as-directory (expand-file-name root))))
    (if-let ((fd (executable-find "fd")))
        (let ((default-directory root))
          (process-lines fd "--type" "f" "--strip-cwd-prefix" "--color" "never" "."))
      (mapcar
       (lambda (file)
         (file-relative-name file root))
       (directory-files-recursively
        root ".*" nil
        (lambda (dir)
          (not (string-match-p "/\\.git\\(?:/\\|\\'\\)" dir))))))))

(defvar mp/super-menu--git-cache nil
  "Alist of (REPO-ROOT . HASH) caching git status during one menu invocation.
Reset by `mp/super-menu' so a fresh menu always sees current status.")

(defun mp/super-menu--git-status (dir)
  "Return a hash mapping absolute paths in DIR's repo to porcelain status codes.
Results are cached per repository for the lifetime of one menu invocation.
Returns nil when DIR is not inside a git work tree."
  (when (and dir (executable-find "git"))
    (let* ((default-directory (file-name-as-directory (expand-file-name dir)))
           (root (ignore-errors
                   (car (process-lines "git" "rev-parse" "--show-toplevel")))))
      (when root
        (or (cdr (assoc root mp/super-menu--git-cache))
            (let ((default-directory (file-name-as-directory root))
                  (map (make-hash-table :test 'equal)))
              (dolist (line (ignore-errors
                              (process-lines "git" "status" "--porcelain"
                                             "--ignored=no" "--no-renames")))
                (when (> (length line) 3)
                  (puthash (expand-file-name (substring line 3) root)
                           (string-trim (substring line 0 2))
                           map)))
              (push (cons root map) mp/super-menu--git-cache)
              map))))))

(defun mp/super-menu--git-face (code)
  "Return a face for git porcelain status CODE, or nil when unchanged."
  (cond
   ((null code) nil)
   ((string-prefix-p "?" code) 'success)    ; untracked
   ((string-match-p "U" code) 'error)       ; unmerged
   ((string-match-p "D" code) 'error)       ; deleted
   ((string-match-p "A" code) 'success)     ; added
   ((string-match-p "[MRC]" code) 'warning) ; modified / renamed / copied
   (t 'warning)))

(defun mp/super-menu--git-letter (code)
  "Return a single status letter for git porcelain CODE, or nil when unchanged."
  (cond
   ((null code) nil)
   ((string-prefix-p "?" code) "U")   ; untracked / created
   ((string-match-p "U" code) "!")    ; unmerged conflict
   ((string-match-p "A" code) "A")    ; added
   ((string-match-p "D" code) "D")    ; deleted
   ((string-match-p "R" code) "R")    ; renamed
   ((string-match-p "C" code) "C")    ; copied
   ((string-match-p "M" code) "M")    ; modified
   (t (string-trim code))))

(defun mp/super-menu--git-colorize (display abspath gitmap)
  "Return DISPLAY colour-coded and suffixed with ABSPATH's git status letter.
The status letter is appended after the name in a dim, normal-weight `shadow'
face; the name itself is coloured by `mp/super-menu--git-face'."
  (if-let* ((gitmap)
            (code (gethash abspath gitmap)))
      (concat (propertize display 'face (mp/super-menu--git-face code))
              (if-let* ((letter (mp/super-menu--git-letter code)))
                  (concat " " (propertize letter 'face 'shadow))
                ""))
    display))

(defvar mp/consult-source-live-project-file
  `(:name "[F]ile"
    :narrow (?f . "File")
    :category file
    :face consult-file
    :history file-name-history
    :state ,#'consult--file-state
    :action ,#'consult--file-action
    :new ,#'consult--file-action
    :enabled ,(lambda ()
                (or (mp/current-workspace-project-root)
                    (and (bound-and-true-p projectile-mode)
                         (projectile-project-p))))
    :items ,(lambda ()
              (let* ((root (file-name-as-directory
                            (expand-file-name
                             (or (mp/current-workspace-project-root)
                                 (projectile-project-root)))))
                     (gitmap (mp/super-menu--git-status root))
                     (candidates
                      (mapcar
                       (lambda (file)
                         (let ((abs (expand-file-name file root)))
                           (cons (mp/super-menu--git-colorize file abs gitmap)
                                 abs)))
                       (mp/live-project-files root))))
                (mp/sort-cons-candidates-by-history
                 candidates file-name-history)))))

(defvar mp/projectile-project-history nil
  "History for selecting Projectile projects through Consult.")

(defvar mp/consult-source-projectile-project
  `(:name "[P]roject"
    :narrow (?p . "Project")
    :category file
    :face consult-file
    :history mp/projectile-project-history
    :action ,(lambda (project)
               (projectile-switch-project-by-name project))
    :enabled ,(lambda ()
                (and (bound-and-true-p projectile-mode)
                     (not (mp/project-workspace-p))))
    :items ,(lambda ()
              (mp/sort-cons-candidates-by-history
               (mapcar
                (lambda (project)
                  (let* ((dir (directory-file-name project))
                         (name (file-name-nondirectory dir))
                         (parent (file-name-directory dir))
                         (label (concat parent name)))
                    (cons label project)))
                (projectile-relevant-known-projects))
               mp/projectile-project-history))))

;;; Current-directory browser + file actions for the super menu.

(defvar mp/super-menu-dir nil
  "Directory the super-menu's current-directory source is browsing.
When nil, the directory is derived from `mp/super-menu-origin-file'.
Set while navigating with the menu and reset by `mp/super-menu'.")

(defvar mp/super-menu-origin-file nil
  "File visited by the buffer that was active when the super menu opened.")

(defun mp/super-menu-directory ()
  "Return the directory the current-directory source should list, or nil."
  (or mp/super-menu-dir
      (and mp/super-menu-origin-file
           (file-name-directory mp/super-menu-origin-file))))

(defun mp/super-menu--icon (fn name)
  "Render nerd-icon NAME with function FN, or empty string when unavailable."
  (if (fboundp fn)
      (concat (funcall fn name) " ")
    ""))

(defun mp/super-menu--current-dir-items ()
  "Candidates for the files/sub-directories of the browsed directory.
Directories sort before files; a `../' entry is prepended unless at the
filesystem root."
  (when-let* ((dir (mp/super-menu-directory))
              (dir (file-name-as-directory (expand-file-name dir)))
              ((file-directory-p dir)))
    (let* ((entries (ignore-errors
                      (directory-files dir t directory-files-no-dot-files-regexp)))
           (entries (sort entries
                          (lambda (a b)
                            (let ((ad (file-directory-p a))
                                  (bd (file-directory-p b)))
                              (if (eq ad bd)
                                  (string-lessp (file-name-nondirectory a)
                                                (file-name-nondirectory b))
                                ad)))))
           (parent (file-name-directory (directory-file-name dir)))
           (gitmap (mp/super-menu--git-status dir))
           (items (mapcar
                   (lambda (path)
                     (if (file-directory-p path)
                         (cons (concat (file-name-nondirectory path) "/")
                               (file-name-as-directory path))
                       (cons (mp/super-menu--git-colorize
                              (file-name-nondirectory path) path gitmap)
                             path)))
                   entries)))
      (if (string-equal parent dir)
          items
        (cons (cons "../" parent) items)))))

(defun mp/super-menu-dir-file-action (path)
  "Open PATH, or browse into it (re-opening the menu) when it is a directory."
  (if (file-directory-p path)
      (progn
        (setq mp/super-menu-dir (file-name-as-directory path))
        (consult-buffer))
    (consult--file-action path)))

(defun mp/super-menu-dir-file-state ()
  "Preview state for the current-directory source that ignores directories."
  (let ((file-state (consult--file-state)))
    (lambda (action cand)
      (funcall file-state action
               (and cand (not (file-directory-p cand)) cand)))))

(defvar mp/consult-source-current-dir-file
  `(:name "[D]irectory"
    :narrow (?d . "Directory")
    :category file
    :face consult-file
    :history file-name-history
    :state ,#'mp/super-menu-dir-file-state
    :action ,#'mp/super-menu-dir-file-action
    :enabled ,(lambda () (and (mp/super-menu-directory) t))
    :items ,#'mp/super-menu--current-dir-items)
  "Files and sub-directories of the current buffer's directory.")

(defun mp/super-menu--with-origin-buffer (fn)
  "Call command FN inside the buffer visiting `mp/super-menu-origin-file'."
  (let ((buf (and mp/super-menu-origin-file
                  (find-buffer-visiting mp/super-menu-origin-file))))
    (if buf
        (with-current-buffer buf (call-interactively fn))
      (user-error "No file buffer to act on"))))

(defun mp/super-menu-run-action (action)
  "Run the chosen super-menu ACTION on the origin file or browsed directory."
  (pcase action
    ('rename   (mp/super-menu--with-origin-buffer #'doom/move-this-file))
    ('delete   (mp/super-menu--with-origin-buffer #'doom/delete-this-file))
    ('terminal (let ((default-directory (or (mp/super-menu-directory)
                                            default-directory)))
                 (+vterm/here t)))))

(defun mp/super-menu-action-annotation (action)
  "Marginalia annotation: the path super-menu ACTION will affect, right-aligned."
  (when-let* ((path (pcase action
                      ((or 'rename 'delete) mp/super-menu-origin-file)
                      ('terminal (mp/super-menu-directory)))))
    (concat (propertize " " 'marginalia--align t)
            marginalia-separator
            (propertize (abbreviate-file-name (directory-file-name path))
                        'face 'marginalia-file-name))))

(defvar mp/consult-source-current-dir-action
  `(:name "[X] Actions"
    :narrow (?x . "Actions")
    :category mp/super-action
    :action ,#'mp/super-menu-run-action
    :enabled ,(lambda () (and (mp/super-menu-directory) t))
    :items ,(lambda ()
              (delq nil
                    (list
                     (when mp/super-menu-origin-file
                       (cons (concat (mp/super-menu--icon 'nerd-icons-octicon "nf-oct-pencil")
                                     "Rename current file")
                             'rename))
                     (when mp/super-menu-origin-file
                       (cons (concat (mp/super-menu--icon 'nerd-icons-octicon "nf-oct-trash")
                                     "Delete current file")
                             'delete))
                     (cons (concat (mp/super-menu--icon 'nerd-icons-octicon "nf-oct-terminal")
                                   "Open terminal here")
                           'terminal)))))
  "Actions on the current file / browsed directory for the super menu.")

(defun mp/super-menu ()
  "Open the consult super menu, resetting the directory browser.
Records the active buffer's file so the current-directory and action
sources have something to anchor to."
  (interactive)
  (setq mp/super-menu-dir nil
        mp/super-menu--git-cache nil
        mp/super-menu-origin-file (buffer-file-name (buffer-base-buffer)))
  (consult-buffer))

(after! marginalia
  ;; Annotate the [X] Actions entries with the path they act on, dispatched via
  ;; their `mp/super-action' category just like buffers/files get their columns.
  (add-to-list 'marginalia-annotators
               '(mp/super-action mp/super-menu-action-annotation none)))

(with-eval-after-load 'consult
  (setq consult-buffer-sources
        '(mp/consult-source-workspace-buffer
          mp/consult-source-all-buffer
          mp/consult-source-agent-shell-buffer
          mp/consult-source-vterm-buffer
          mp/consult-source-current-dir-file
          mp/consult-source-current-dir-action
          mp/consult-source-live-project-file
          mp/consult-source-projectile-project
          consult-source-hidden-buffer
          consult-source-project-buffer-hidden
          consult-source-project-recent-file-hidden)))

(map! :leader "SPC" #'mp/super-menu)

(map! :leader :desc "File symbols" "m g f s" #'consult-lsp-file-symbols)

(after! olivetti
  (setq olivetti-body-width 100))

(setq which-key-idle-delay 0.2)

;; Give hover/help text enough room to be readable.
(setq eldoc-echo-area-use-multiline-p 3)

(use-package! eldoc-box
  :commands (eldoc-box-help-at-point)
  :init
  (map! :leader
        (:prefix ("c" . "code")
         :desc "Hover docs" "h" #'eldoc-box-help-at-point))
  :config
  (setq eldoc-box-max-pixel-width 900
        eldoc-box-max-pixel-height 520
        eldoc-box-cleanup-interval 0.35
        eldoc-box-only-multi-line nil))

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

(after! treemacs
  (setq treemacs-show-hidden-files t)

  (defun mp/treemacs-toggle-current-project ()
    "Toggle Treemacs, always scoped to the current project."
    (interactive)
    (pcase (treemacs-current-visibility)
      ('visible (delete-window (treemacs-get-local-window)))
      (_ (treemacs-display-current-project-exclusively))))

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
        magit-diff-fontify-hunk 'all
        ;; Keep whitespace visible inside refined hunks so indentation-only
        ;; changes are highlighted instead of being treated as irrelevant.
        magit-diff-refine-ignore-whitespace nil
        ;; Paint actual whitespace problems in both added and removed lines.
        magit-diff-paint-whitespace t
        magit-diff-paint-whitespace-lines 'both
        magit-diff-highlight-trailing t))

(use-package! clutch
  :defer t
  :config
  (setq clutch-connect-timeout-seconds 10
        clutch-read-idle-timeout-seconds 30
        clutch-query-timeout-seconds 20
        clutch-jdbc-rpc-timeout-seconds 15))

(require 'json)
(require 'subr-x)

(defvar mp/clutch-connections-file
  (expand-file-name "connections.json" doom-user-dir))

(defun mp/clutch--json-key-to-keyword (key)
  (intern (concat ":" key)))

(defun mp/clutch--json-object-to-plist (obj)
  (let (plist)
    (dolist (pair obj (nreverse plist))
      (let ((key (car pair))
            (value (cdr pair)))
        (setq plist
              (cons value
                    (cons (mp/clutch--json-key-to-keyword key)
                          plist)))))))

(defun mp/clutch--uri-to-plist (uri)
  (cond
   ;; PostgreSQL:
   ;; postgresql://user:pass@host:5432/database
   ((string-match
     "\\`\\(postgresql\\|postgres\\)://\\(?:\\([^:/@]+\\)\\(?::\\([^@/]*\\)\\)?@\\)?\\([^:/]+\\)\\(?::\\([0-9]+\\)\\)?/\\(.+\\)\\'"
     uri)
    (let ((user (match-string 2 uri))
          (password (match-string 3 uri))
          (host (match-string 4 uri))
          (port (match-string 5 uri))
          (database (match-string 6 uri)))
      (append
       (list :backend 'pg
             :host host
             :database (url-unhex-string database))
       (when port
         (list :port (string-to-number port)))
       (when user
         (list :user (url-unhex-string user)))
       (when password
         (list :password (url-unhex-string password))))))

   ;; MySQL:
   ;; mysql://user:pass@host:3306/database
   ((string-match
     "\\`mysql://\\(?:\\([^:/@]+\\)\\(?::\\([^@/]*\\)\\)?@\\)?\\([^:/]+\\)\\(?::\\([0-9]+\\)\\)?/\\(.+\\)\\'"
     uri)
    (let ((user (match-string 1 uri))
          (password (match-string 2 uri))
          (host (match-string 3 uri))
          (port (match-string 4 uri))
          (database (match-string 5 uri)))
      (append
       (list :backend 'mysql
             :host host
             :database (url-unhex-string database))
       (when port
         (list :port (string-to-number port)))
       (when user
         (list :user (url-unhex-string user)))
       (when password
         (list :password (url-unhex-string password))))))

   ;; SQLite:
   ;; sqlite:///home/mahdi/sqlite.db
   ((string-match "\\`sqlite://\\(.+\\)\\'" uri)
    (list :backend 'sqlite
          :database (url-unhex-string (match-string 1 uri))))

   (t
    (user-error "Unsupported connection URI: %s" uri))))

(defun mp/clutch--normalize-backend (plist)
  (let ((backend (plist-get plist :backend)))
    (plist-put plist :backend
               (cond
                ((symbolp backend) backend)
                ((string= backend "postgres") 'pg)
                ((string= backend "postgresql") 'pg)
                ((string= backend "pg") 'pg)
                ((string= backend "mysql") 'mysql)
                ((string= backend "sqlite") 'sqlite)
                (t (intern backend))))))

(defun mp/clutch--normalize-connection (value)
  (cond
   ((stringp value)
    (mp/clutch--uri-to-plist value))
   ((listp value)
    (mp/clutch--normalize-backend
     (mp/clutch--json-object-to-plist value)))
   (t
    (user-error "Invalid connection value: %S" value))))

(defun mp/clutch-load-connections ()
  (when (file-exists-p mp/clutch-connections-file)
    (let ((json-object-type 'alist)
          (json-array-type 'list)
          (json-key-type 'string))
      (mapcar
       (lambda (entry)
         (cons (car entry)
               (mp/clutch--normalize-connection (cdr entry))))
       (json-read-file mp/clutch-connections-file)))))

(defun mp/clutch-apply-connections ()
  (interactive)
  (setq clutch-connection-alist
        (mp/clutch-load-connections))
  (message "Loaded %d Clutch connections from %s"
           (length clutch-connection-alist)
           mp/clutch-connections-file))

(with-eval-after-load 'clutch
  (mp/clutch-apply-connections))

(map! :leader
      :desc "Clutch query console"
      "o s" #'clutch-query-console)

(use-package! agent-shell-notifications
  :hook (agent-shell-mode . agent-shell-notifications-mode))

(use-package! copilot
  :ensure t
  :bind (:map copilot-completion-map
              ("<tab>" . copilot-accept-completion)
              ("TAB" . copilot-accept-completion)
              ("C-<tab>" . copilot-accept-completion-by-word)
              ("C-TAB" . copilot-accept-completion-by-word)
              ("C-n" . copilot-next-completion)
              ("C-p" . copilot-previous-completion))
  :init
  (setq copilot-indent-offset-warning-disable t)
  :hook (prog-mode . copilot-mode))

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

(use-package! renpy-mode
  :ensure t
  :custom
  (renpy-program (or (getenv "RENPY_EXECUTABLE_PATH") "renpy"))
  :bind
  ;; Bind some useful commands.
  ("C-c C-c" . renpy-compile)
  ("C-c C-r" . renpy-run)
  ("C-c C-l" . renpy-lint)
  :hook
  ((renpy-mode . flymake-mode)
   (renpy-mode . outline-minor-mode)))

(map! :leader
      :desc "Run nearest test" "t t" #'+eval/test
      :desc "Run all project tests" "t a" #'+eval/test-all
      (:prefix ("d" . "agent")
       :desc "Agent shell" "a" #'agent-shell))

(map! :n "gr" #'xref-find-references
      :n "g[" #'xref-go-back
      :n "g]" #'xref-go-forward)

(global-set-key [mouse-8] #'xref-go-back)
(global-set-key [mouse-9] #'xref-go-forward)

(defun mp/project-root-default-directory (&optional dir)
  "Return the preferred project root for DIR, preferring explicit workspace roots."
  (or (mp/current-workspace-project-root)
      (let ((dir (file-name-as-directory
                  (expand-file-name (or dir default-directory)))))
        (or
         (when (fboundp 'projectile-project-root)
           (let ((default-directory dir))
             (ignore-errors
               (file-name-as-directory
                (expand-file-name (projectile-project-root))))))
         (when (fboundp 'doom-project-root)
           (ignore-errors
             (file-name-as-directory
              (expand-file-name (doom-project-root dir)))))
         dir))))

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

(defun mp/clipboard-copy ()
  (interactive)
  (clipboard-kill-ring-save (region-beginning) (region-end))
  (evil-exit-visual-state))

(after! evil
  (dolist (state-map (list evil-motion-state-map
                           evil-normal-state-map
                           evil-insert-state-map
                           evil-emacs-state-map
                           evil-visual-state-map))
    (define-key state-map (kbd "C-b") #'mp/treemacs-toggle-current-project)
    (define-key state-map (kbd "C-S-e") #'treemacs-find-file)
    (define-key state-map (kbd "C-S-c") #'mp/clipboard-copy)
    (define-key state-map (kbd "C-S-v") #'clipboard-yank)
    (define-key state-map (kbd "C-\\") #'mp/vterm-new)
    (define-key state-map (kbd "C-/") #'comment-line)
    (define-key state-map (kbd "M-d") #'er/expand-region)
    (define-key state-map (kbd "M-D") #'er/contract-region)
    (define-key state-map (kbd "M-<up>") #'mp/move-lines-up)
    (define-key state-map (kbd "M-<down>") #'mp/move-lines-down))

  (map! :leader
        (:prefix ("v" . "visual")
         :desc "Visual line" "v" #'evil-visual-line
         :desc "Visual block" "b" #'evil-visual-block)))

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
      "v" "visual"
      "w" "windows"
      "x" "text")))

(after! flycheck
  (map! :leader
        (:prefix ("e" . "errors")
         :desc "List errors" "l" #'flycheck-list-errors
         :desc "Next error" "n" #'flycheck-next-error
         :desc "Previous error" "p" #'flycheck-previous-error
         :desc "Verify checker" "v" #'flycheck-verify-setup)))

(defvar my/project-running-scripts (make-hash-table :test 'equal))

(defun my/project-scripts-dir ()
  (expand-file-name "__ignore__/scripts/" (projectile-project-root)))

(defun my/project-script-files ()
  (let ((dir (my/project-scripts-dir)))
    (when (file-directory-p dir)
      (directory-files dir t "\\.sh$"))))

(defun my/project-script-label (file)
  (let* ((project (projectile-project-root))
         (key (concat project "::" file))
         (name (file-name-base file)))
    (if (gethash key my/project-running-scripts)
        (concat "✓ " name)
      name)))

(defun my/run-project-script ()
  "Pick a project script and run it in a vterm buffer."
  (interactive)
  (let* ((project (projectile-project-root))
         (files (my/project-script-files)))
    (unless files
      (user-error "No scripts found in __ignore__/scripts/"))

    (let* ((choices
            (mapcar (lambda (file)
                      (cons (my/project-script-label file) file))
                    files))
           (picked-label (completing-read "Run script: " choices nil t))
           (file (cdr (assoc picked-label choices)))
           (name (file-name-base file))
           (key (concat project "::" file))
           (buf-name (format "*project:%s*" name)))

      (puthash key t my/project-running-scripts)

      (let ((default-directory project))
        (vterm buf-name)
        (vterm-send-string (shell-quote-argument file))
        (vterm-send-return)
        (delete-other-windows)))))

(map! :leader
      :desc "Run project script"
      "p S" #'my/run-project-script)
