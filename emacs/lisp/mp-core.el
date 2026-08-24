;;; mp-core.el --- Defaults, paths, private data -*- lexical-binding: t; -*-

;;; Identity

(setq user-full-name "Mahdi Pourismaiel"
      user-mail-address "mpourismaiel@gmail.com")

;;; GC (takes over from early-init's ceiling)

(use-package gcmh
  :demand t
  :config
  (setq gcmh-idle-delay 'auto
        gcmh-high-cons-threshold (* 128 1024 1024))
  (gcmh-mode 1))

;;; PATH — GUI Emacs doesn't read .bashrc

;; nvm's node bin, so executable-find resolves node LSP servers/formatters.
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

;; Doom injected the login shell's env via `doom env'; replicate with
;; exec-path-from-shell so tools installed via shell profiles resolve.
(use-package exec-path-from-shell
  :when (display-graphic-p)
  :demand t
  :config
  (setq exec-path-from-shell-arguments '("-l"))
  (exec-path-from-shell-initialize))

;; ~/.local/bin — where `pip install --user' and pipx drop console scripts
;; (e.g. gdformat from gdtoolkit).  It's only on the *interactive* shell PATH
;; here, so exec-path-from-shell's `-l' (non-interactive login) misses it.
;; Add it AFTER exec-path-from-shell, which rewrites `exec-path'/PATH wholesale
;; and would otherwise drop this prepend.
(let ((local-bin (expand-file-name "~/.local/bin")))
  (when (file-directory-p local-bin)
    (add-to-list 'exec-path local-bin)
    (setenv "PATH" (concat local-bin path-separator (getenv "PATH")))))

;; Go's tool bin (GOPATH/bin) — where `go install' drops gopls, dlv,
;; staticcheck, etc.  It isn't on the login-shell PATH here, so
;; exec-path-from-shell's `-l' misses it and Emacs can't find gopls (lsp-bridge
;; `gd'/`gr' silently no-op in Go) or dlv (dape debugging fails to launch).
;; GOBIN overrides the location; otherwise it's <GOPATH>/bin, default ~/go/bin.
(let ((go-bin (or (getenv "GOBIN")
                  (expand-file-name "bin" (or (getenv "GOPATH")
                                              (expand-file-name "~/go"))))))
  (when (file-directory-p go-bin)
    (add-to-list 'exec-path go-bin)
    (setenv "PATH" (concat go-bin path-separator (getenv "PATH")))))

;;; Files & state

(setq delete-by-moving-to-trash t
      confirm-kill-emacs nil
      auto-save-default t
      make-backup-files nil
      create-lockfiles nil
      require-final-newline t
      find-file-visit-truename t
      vc-follow-symlinks t)

;; Keep all state under var/.
(setq auto-save-list-file-prefix (expand-file-name "auto-save/" mp/var-dir)
      auto-save-file-name-transforms
      `((".*" ,(expand-file-name "auto-save/" mp/var-dir) t))
      backup-directory-alist `((".*" . ,(expand-file-name "backup/" mp/var-dir)))
      tramp-persistency-file-name (expand-file-name "tramp" mp/var-dir)
      bookmark-default-file (expand-file-name "bookmarks" mp/var-dir)
      project-list-file (expand-file-name "projects" mp/var-dir)
      transient-history-file (expand-file-name "transient-history.el" mp/var-dir))
(make-directory (expand-file-name "auto-save" mp/var-dir) t)
(make-directory (expand-file-name "backup" mp/var-dir) t)

(use-package recentf
  :ensure nil
  :demand t
  :config
  (setq recentf-save-file (expand-file-name "recentf" mp/var-dir)
        recentf-max-saved-items 200
        recentf-auto-cleanup 'mode)
  (recentf-mode 1))

(use-package savehist
  :ensure nil
  :demand t
  :config
  (setq savehist-file (expand-file-name "savehist" mp/var-dir))
  (savehist-mode 1))

(use-package saveplace
  :ensure nil
  :demand t
  :config
  (setq save-place-file (expand-file-name "saveplace" mp/var-dir))
  (save-place-mode 1))

(use-package autorevert
  :ensure nil
  :demand t
  :config
  (setq global-auto-revert-non-file-buffers t
        auto-revert-verbose nil)
  (global-auto-revert-mode 1))

(use-package so-long
  :ensure nil
  :demand t
  :config (global-so-long-mode 1))

(setq use-short-answers t
      ring-bell-function #'ignore
      uniquify-buffer-name-style 'forward
      sentence-end-double-space nil
      ;; Log warnings to *Warnings* without popping the window open at
      ;; startup; only real errors demand attention.
      warning-minimum-level :error)

(prefer-coding-system 'utf-8)

;;; Editing basics

(setq-default indent-tabs-mode nil
              tab-width 4
              fill-column 80)

(setq scroll-preserve-screen-position t
      scroll-conservatively 101
      scroll-margin 0
      mouse-wheel-follow-mouse t
      mouse-wheel-scroll-amount '(3 ((shift) . 1))
      mouse-wheel-progressive-speed nil)

(electric-indent-mode 1)
(delete-selection-mode 1)
(global-subword-mode 0)

;; Word deletion that never touches the kill ring (C-backspace/C-delete are
;; bound in mp-keys; M-backspace stays the stock word-kill).
(defun mp/delete-word-backward (arg)
  "Delete characters backward until the start of a word.
Unlike `backward-kill-word', this does NOT save the text to the kill ring."
  (interactive "p")
  (delete-region (point) (progn (backward-word arg) (point))))

(defun mp/delete-word-forward (arg)
  "Delete characters forward until the end of a word.
Unlike `kill-word', this does NOT save the text to the kill ring."
  (interactive "p")
  (delete-region (point) (progn (forward-word arg) (point))))

;; Line moving (Doom-era mp/move-lines-* lived in custom-shortcuts; the core
;; commands are generic editing utilities, so they live here now).
(defun mp/move-lines (n)
  "Move the current line or active region N lines (negative = up)."
  (let* ((use-region (use-region-p))
         (beg (if use-region (region-beginning) (line-beginning-position)))
         (end (if use-region (region-end) (line-end-position)))
         (beg (save-excursion (goto-char beg) (line-beginning-position)))
         (end (save-excursion (goto-char end) (min (point-max) (1+ (line-end-position)))))
         (text (delete-and-extract-region beg end))
         (col (current-column)))
    (forward-line n)
    (let ((insert-at (point)))
      (insert text)
      (goto-char insert-at)
      (move-to-column col))))

(defun mp/move-lines-up (&optional n)
  "Move current line or region up N lines."
  (interactive "p")
  (mp/move-lines (- (or n 1))))

(defun mp/move-lines-down (&optional n)
  "Move current line or region down N lines."
  (interactive "p")
  (mp/move-lines (or n 1)))

;;; Help — Doom remapped describe-* onto helpful

(use-package helpful
  :bind (([remap describe-function] . helpful-callable)
         ([remap describe-command]  . helpful-command)
         ([remap describe-variable] . helpful-variable)
         ([remap describe-key]      . helpful-key)
         ([remap describe-symbol]   . helpful-symbol)))

;;; Private data (seeded into the deployed dir by deploy.sh)

(defvar mp/project-bundles nil
  "Private project bundles loaded from private.el.")

(defvar mp/workspace-project-roots (make-hash-table :test 'equal)
  "Map workspace (perspective) names to their intended project roots.")

(let ((private-config (expand-file-name "private.el" mp/emacs-dir)))
  (when (file-exists-p private-config)
    (load-file private-config)))

;;; Emacs server
;; So `emacsclient' — and the Godot editor's "Open in External Editor" bridge
;; (see `mp/open-file-in-project-workspace' in mp-langs.el) — can reach this
;; Emacs.  A daemon already runs a server; only a plain `emacs' needs this.

(require 'server)
(unless (or (daemonp) (server-running-p))
  (server-start))

(provide 'mp-core)
;;; mp-core.el ends here
