;;; mp-keys.el --- Leader engine + full Doom bindings port -*- lexical-binding: t; -*-

;; Source of truth: __ignore__/doom-keymap-manifest.txt (dumped from live Doom).
;; Intentional diffs from that manifest are listed in emacs/README.md.

(use-package general
  :demand t)
(elpaca-wait)

(general-override-mode 1)

(general-create-definer mp/leader
  :states '(normal visual motion)
  :keymaps 'override
  :prefix "SPC")

(general-create-definer mp/localleader
  :states '(normal visual motion)
  :prefix "SPC m")

;;; which-key (built into Emacs 30)

(use-package which-key
  :ensure nil
  :demand t
  :config
  (setq which-key-idle-delay 0.2
        which-key-sort-order 'which-key-key-order-alpha
        which-key-min-display-lines 6
        which-key-max-display-columns nil
        which-key-side-window-max-height 0.25)
  (which-key-mode 1))

(setq eldoc-echo-area-use-multiline-p 3)

;;; ---------------------------------------------------------------------------
;;; Helper commands (ports of doom/* and +default/* referenced by the manifest)

;; Buffers
(defun mp/kill-all-buffers (&optional _)
  "Kill all buffers, leaving the splash/scratch."
  (interactive)
  (mapc #'kill-buffer (buffer-list))
  (delete-other-windows))

(defun mp/kill-other-buffers ()
  "Kill all file-visiting buffers except the current one."
  (interactive)
  (dolist (buf (buffer-list))
    (unless (or (eq buf (current-buffer)) (null (buffer-file-name buf)))
      (kill-buffer buf)))
  (message "Other buffers killed"))

(defun mp/kill-buried-buffers ()
  "Kill buffers not visible in any window."
  (interactive)
  (dolist (buf (buffer-list))
    (unless (get-buffer-window buf t)
      (when (buffer-file-name buf) (kill-buffer buf)))))

(defun mp/save-and-kill-buffer ()
  "Save the current buffer, then kill it (Doom's ZX)."
  (interactive)
  (save-buffer)
  (kill-current-buffer))

(defun mp/yank-buffer-contents ()
  "Copy the whole buffer to the kill ring."
  (interactive)
  (kill-new (buffer-substring-no-properties (point-min) (point-max)))
  (message "Buffer contents copied"))

;; Files
(defun mp/sudo-find-file (file)
  "Open FILE with root privileges via TRAMP."
  (interactive "FSudo find file: ")
  (find-file (concat "/sudo:root@localhost:" (expand-file-name file))))

(defun mp/sudo-this-file ()
  "Reopen the current file with root privileges."
  (interactive)
  (if buffer-file-name
      (find-file (concat "/sudo:root@localhost:" buffer-file-name))
    (user-error "Buffer is not visiting a file")))

(defun mp/sudo-save-buffer ()
  "Save the current buffer as root."
  (interactive)
  (if buffer-file-name
      (let ((f (concat "/sudo:root@localhost:" buffer-file-name)))
        (write-region (point-min) (point-max) f)
        (set-buffer-modified-p nil))
    (user-error "Buffer is not visiting a file")))

(defun mp/move-this-file (new-path)
  "Rename the current file to NEW-PATH."
  (interactive (list (read-file-name "Move file to: ")))
  (let ((old (or buffer-file-name (user-error "Not visiting a file"))))
    (rename-file old new-path 1)
    (set-visited-file-name new-path t t)
    (message "Moved to %s" new-path)))

(defun mp/copy-this-file (new-path)
  "Copy the current file to NEW-PATH and visit it."
  (interactive (list (read-file-name "Copy file to: ")))
  (let ((old (or buffer-file-name (user-error "Not visiting a file"))))
    (copy-file old new-path 1)
    (find-file new-path)))

(defun mp/delete-this-file ()
  "Delete the current file (to trash) and kill its buffer."
  (interactive)
  (let ((file (or buffer-file-name (user-error "Not visiting a file"))))
    (when (y-or-n-p (format "Delete %s? " (abbreviate-file-name file)))
      (delete-file file 'trash)
      (kill-current-buffer))))

(defun mp/yank-buffer-path ()
  "Copy the current buffer's absolute path."
  (interactive)
  (if-let* ((path (or buffer-file-name default-directory)))
      (progn (kill-new (abbreviate-file-name path)) (message "%s" path))
    (user-error "No path")))

(defun mp/yank-buffer-path-relative-to-project ()
  "Copy the current buffer's path relative to the project root."
  (interactive)
  (let* ((path (or buffer-file-name (user-error "Not visiting a file")))
         (root (or (and (fboundp 'projectile-project-root) (projectile-project-root))
                   default-directory)))
    (kill-new (file-relative-name path root))
    (message "%s" (file-relative-name path root))))

(defun mp/insert-file-path (file)
  "Insert a path selected via the minibuffer."
  (interactive "fInsert path of: ")
  (insert (abbreviate-file-name (expand-file-name file))))

(defun mp/find-file-in-emacsd ()
  "Find a file inside this Emacs config."
  (interactive)
  (let ((default-directory mp/emacs-dir))
    (call-interactively #'find-file)))

(defun mp/browse-emacsd ()
  "Dired into this Emacs config."
  (interactive)
  (dired mp/emacs-dir))

;; Search (consult-backed)
(defun mp/search-buffer ()
  (interactive) (call-interactively #'consult-line))

(defun mp/search-symbol-at-point ()
  "Search the buffer for the symbol at point."
  (interactive)
  (consult-line (thing-at-point 'symbol)))

(defun mp/search-project (&optional dir initial)
  "Ripgrep the current project (or DIR)."
  (interactive)
  (consult-ripgrep (or dir (and (fboundp 'projectile-project-root)
                                (projectile-project-root))
                       default-directory)
                   initial))

(defun mp/search-project-for-symbol-at-point ()
  (interactive)
  (mp/search-project nil (thing-at-point 'symbol)))

(defun mp/search-other-project ()
  "Ripgrep a project chosen from the known-project list."
  (interactive)
  (mp/search-project
   (completing-read "Search project: " (projectile-relevant-known-projects))))

(defun mp/search-cwd ()
  (interactive) (consult-ripgrep default-directory))

(defun mp/search-other-cwd ()
  (interactive)
  (consult-ripgrep (read-directory-name "Search directory: ")))

(defun mp/search-emacsd ()
  (interactive) (consult-ripgrep mp/emacs-dir))

(defun mp/search-online (query)
  "Search the web for QUERY (thing at point as default)."
  (interactive
   (list (read-string "Search online: " (thing-at-point 'symbol t))))
  (browse-url (concat "https://duckduckgo.com/?q=" (url-hexify-string query))))

;; Lookup dispatchers: lsp-bridge buffers use bridge, eglot buffers use
;; eglot/xref, everything else plain xref (with dumb-jump as backend of last
;; resort — see mp-lsp).
(defun mp/lookup-definition ()
  (interactive)
  (cond ((bound-and-true-p lsp-bridge-mode) (call-interactively #'lsp-bridge-find-def))
        (t (call-interactively #'xref-find-definitions))))

(defun mp/lookup-references ()
  (interactive)
  (cond ((bound-and-true-p lsp-bridge-mode) (call-interactively #'lsp-bridge-find-references))
        (t (call-interactively #'xref-find-references))))

(defun mp/lookup-implementations ()
  (interactive)
  (cond ((bound-and-true-p lsp-bridge-mode) (call-interactively #'lsp-bridge-find-impl))
        ((bound-and-true-p eglot--managed-mode) (call-interactively #'eglot-find-implementation))
        (t (user-error "No LSP client active"))))

(defun mp/lookup-type-definition ()
  (interactive)
  (cond ((and (bound-and-true-p lsp-bridge-mode) (fboundp 'lsp-bridge-find-type-def))
         (call-interactively #'lsp-bridge-find-type-def))
        ((bound-and-true-p eglot--managed-mode) (call-interactively #'eglot-find-typeDefinition))
        (t (user-error "No LSP client active"))))

(defun mp/lookup-documentation ()
  (interactive)
  (cond ((bound-and-true-p lsp-bridge-mode) (call-interactively #'lsp-bridge-popup-documentation))
        (t (call-interactively #'eldoc-box-help-at-point))))

;; Diagnostics dispatchers
(defun mp/next-error ()
  (interactive)
  (if (bound-and-true-p lsp-bridge-mode)
      (call-interactively #'lsp-bridge-diagnostic-jump-next)
    (call-interactively #'flycheck-next-error)))

(defun mp/previous-error ()
  (interactive)
  (if (bound-and-true-p lsp-bridge-mode)
      (call-interactively #'lsp-bridge-diagnostic-jump-prev)
    (call-interactively #'flycheck-previous-error)))

(defun mp/list-errors ()
  (interactive)
  (if (bound-and-true-p lsp-bridge-mode)
      (call-interactively #'lsp-bridge-diagnostic-list)
    (call-interactively #'flycheck-list-errors)))

;; Code actions / rename / symbols dispatchers
(defun mp/lsp-rename ()
  (interactive)
  (cond ((bound-and-true-p lsp-bridge-mode) (call-interactively #'lsp-bridge-rename))
        ((bound-and-true-p eglot--managed-mode) (call-interactively #'eglot-rename))
        (t (user-error "No LSP client active"))))

(defun mp/lsp-code-actions ()
  (interactive)
  (cond ((bound-and-true-p lsp-bridge-mode) (call-interactively #'lsp-bridge-code-action))
        ((bound-and-true-p eglot--managed-mode) (call-interactively #'eglot-code-actions))
        (t (user-error "No LSP client active"))))

(defun mp/lsp-organize-imports ()
  (interactive)
  (cond ((bound-and-true-p eglot--managed-mode) (call-interactively #'eglot-code-action-organize-imports))
        ((bound-and-true-p lsp-bridge-mode) (call-interactively #'lsp-bridge-code-action))
        (t (user-error "No LSP client active"))))

(defun mp/workspace-symbols ()
  (interactive)
  (cond ((bound-and-true-p lsp-bridge-mode) (call-interactively #'lsp-bridge-workspace-list-symbols))
        (t (call-interactively #'consult-imenu-multi))))

;; Eval / REPL (:tools eval parity via quickrun)
(defun mp/eval-buffer-or-region ()
  "Evaluate the region or buffer: elisp natively, other languages via quickrun."
  (interactive)
  (if (derived-mode-p 'emacs-lisp-mode 'lisp-interaction-mode)
      (if (use-region-p)
          (eval-region (region-beginning) (region-end) t)
        (eval-buffer nil t))
    (if (use-region-p)
        (quickrun-region (region-beginning) (region-end))
      (quickrun))))

(defun mp/eval-replace-region ()
  "Replace the region with its evaluated result."
  (interactive)
  (if (derived-mode-p 'emacs-lisp-mode 'lisp-interaction-mode)
      (call-interactively #'eval-region)
    (quickrun-replace-region (region-beginning) (region-end))))

(defun mp/open-repl ()
  "Open a REPL for the current major mode."
  (interactive)
  (pcase major-mode
    ((or 'emacs-lisp-mode 'lisp-interaction-mode) (ielm))
    ((or 'python-mode 'python-ts-mode) (run-python nil nil t))
    ((or 'js-mode 'js-ts-mode 'typescript-ts-mode) (quickrun-shell))
    (_ (quickrun-shell))))

(defun mp/run-tests ()
  "Run the project's tests.
Replaces Doom-era `+eval/test' (which was an unbound command)."
  (interactive)
  (call-interactively #'projectile-test-project))

;; UI toggles / misc
(defun mp/toggle-line-numbers ()
  "Cycle line numbers: absolute -> relative -> off."
  (interactive)
  (setq display-line-numbers
        (pcase display-line-numbers
          ('nil t)
          ('t 'relative)
          (_ nil)))
  (message "Line numbers: %s" (or display-line-numbers "off")))

(defun mp/toggle-indent-style ()
  "Toggle between tabs and spaces in this buffer."
  (interactive)
  (setq-local indent-tabs-mode (not indent-tabs-mode))
  (message "Indenting with %s" (if indent-tabs-mode "tabs" "spaces")))

(defun mp/toggle-narrow-buffer (beg end)
  "Narrow to the region, or widen if already narrowed."
  (interactive "r")
  (if (buffer-narrowed-p)
      (widen)
    (if (use-region-p)
        (narrow-to-region beg end)
      (narrow-to-defun))))

(defvar mp/font-size-step 10)
(defvar mp/font-default-height nil)

(defun mp/increase-font-size ()
  "Increase the default face height frame-wide."
  (interactive)
  (unless mp/font-default-height
    (setq mp/font-default-height (face-attribute 'default :height)))
  (set-face-attribute 'default nil :height
                      (+ (face-attribute 'default :height) mp/font-size-step)))

(defun mp/decrease-font-size ()
  "Decrease the default face height frame-wide."
  (interactive)
  (unless mp/font-default-height
    (setq mp/font-default-height (face-attribute 'default :height)))
  (set-face-attribute 'default nil :height
                      (- (face-attribute 'default :height) mp/font-size-step)))

(defun mp/reset-font-size ()
  "Reset the default face height."
  (interactive)
  (when mp/font-default-height
    (set-face-attribute 'default nil :height mp/font-default-height)))

;; Windows
(defun mp/window-maximize-buffer ()
  "Delete other windows; call again (via winner-undo) to restore."
  (interactive)
  (if (one-window-p)
      (when (fboundp 'winner-undo) (winner-undo))
    (delete-other-windows)))

(defun mp/window-enlargen ()
  "Grow the selected window without deleting the others."
  (interactive)
  (maximize-window))

(defun mp/window-maximize-vertically ()
  (interactive)
  (enlarge-window (frame-height)))

(defun mp/window-maximize-horizontally ()
  (interactive)
  (enlarge-window-horizontally (frame-width)))

(defun mp/reload-init ()
  "Reload init.el (best effort; a restart is cleaner)."
  (interactive)
  (load-file (expand-file-name "init.el" mp/emacs-dir)))

;; Git links (git-link package underneath, like Doom's +vc/git-link).
;; Declared special so the let-bindings below stay dynamic even when this
;; file is byte-compiled before git-link has loaded.
(defvar git-link-open-in-browser)
(defun mp/git-link-kill ()
  "Copy a web link to the current line/region on the remote."
  (interactive)
  (require 'git-link)
  (let ((git-link-open-in-browser nil))
    (call-interactively #'git-link)))

(defun mp/git-link-open ()
  "Open a web link to the current line/region on the remote."
  (interactive)
  (require 'git-link)
  (let ((git-link-open-in-browser t))
    (call-interactively #'git-link)))

(defun mp/git-link-homepage-kill ()
  (interactive)
  (require 'git-link)
  (let ((git-link-open-in-browser nil))
    (call-interactively #'git-link-homepage)))

(defun mp/git-link-homepage-open ()
  (interactive)
  (require 'git-link)
  (let ((git-link-open-in-browser t))
    (call-interactively #'git-link-homepage)))

;; Projects
(defun mp/find-file-in-other-project ()
  "Find a file in another known project."
  (interactive)
  (let ((proj (completing-read "Project: " (projectile-relevant-known-projects))))
    (projectile-find-file-in-directory proj)))

(defun mp/browse-project ()
  "Browse files from the project root."
  (interactive)
  (let ((default-directory
         (or (projectile-project-root) default-directory)))
    (call-interactively #'find-file)))

(defun mp/browse-in-other-project ()
  (interactive)
  (let ((default-directory
         (completing-read "Browse project: " (projectile-relevant-known-projects))))
    (call-interactively #'find-file)))

;;; ---------------------------------------------------------------------------
;;; Global evil-state bindings (Evil State Overrides + manifest customs)

(general-define-key
 :states '(normal visual insert motion emacs)
 "C-S-c" #'mp/clipboard-copy
 "C-S-v" #'clipboard-yank
 "C-/"   #'comment-line
 "M-d"   #'er/expand-region
 "M-D"   #'er/contract-region
 "M-<up>"   #'mp/move-lines-up
 "M-<down>" #'mp/move-lines-down)

(defun mp/clipboard-copy ()
  (interactive)
  (clipboard-kill-ring-save (region-beginning) (region-end))
  (evil-exit-visual-state))

(autoload 'View-scroll-page-forward "view" nil t)
(autoload 'View-scroll-page-backward "view" nil t)

(general-define-key
 :states '(normal)
 "C-j" #'View-scroll-page-forward
 "C-k" #'View-scroll-page-backward
 "g r" #'xref-find-references
 "g [" #'xref-go-back
 "g ]" #'xref-go-forward
 "g d" #'mp/lookup-definition
 "g D" #'mp/lookup-references
 "g I" #'mp/lookup-implementations
 "g f" #'find-file-at-point
 "g O" #'imenu
 "g p" #'mp/evil-reselect-paste
 "g y" #'mp/evil-yank-unindented
 "g Q" #'mp/format-region-or-buffer   ; defined in mp-lsp (apheleia)
 "g R" #'mp/eval-buffer-or-region
 "K"   #'mp/lookup-documentation
 "Z X" #'mp/save-and-kill-buffer
 "z x" #'kill-current-buffer
 "z n" #'mp/toggle-narrow-buffer
 "z N" #'widen
 "C-t"   #'mp/workspace-new           ; defined in mp-workspaces
 "C-S-t" #'mp/workspace-display
 "C-="   #'text-scale-increase
 "C--"   #'text-scale-decrease
 "C-+"   #'mp/reset-font-size
 "C-M-=" #'mp/increase-font-size
 "C-M--" #'mp/decrease-font-size
 "C-S-f" #'toggle-frame-fullscreen
 "C-<return>"   #'mp/evil-insert-newline-below
 "C-S-<return>" #'mp/evil-insert-newline-above)

;; Unimpaired-style pairs
(general-define-key
 :states '(normal motion)
 "] b" #'next-buffer
 "[ b" #'previous-buffer
 "] w" #'mp/workspace-switch-right
 "[ w" #'mp/workspace-switch-left
 "] f" #'mp/evil-next-file
 "[ f" #'mp/evil-previous-file
 "] F" #'other-frame
 "[ F" (lambda () (interactive) (other-frame -1))
 "] o" #'mp/evil-insert-newline-below
 "[ o" #'mp/evil-insert-newline-above
 "] SPC" #'mp/evil-insert-newline-below
 "[ SPC" #'mp/evil-insert-newline-above
 "] e" #'mp/next-error
 "[ e" #'mp/previous-error
 "] d" #'diff-hl-next-hunk
 "[ d" #'diff-hl-previous-hunk)

;; Word deletion without the kill ring — global + insert (covers minibuffer).
(general-define-key
 :states '(normal insert)
 "C-<backspace>" #'mp/delete-word-backward
 "C-<delete>"    #'mp/delete-word-forward)
(general-define-key
 "C-<backspace>" #'mp/delete-word-backward
 "C-<delete>"    #'mp/delete-word-forward)

;; Mouse: back/forward buttons navigate the xref stack.
(global-set-key [mouse-8] #'xref-go-back)
(global-set-key [mouse-9] #'xref-go-forward)

;; VSCode muscle memory: C-SPC triggers completion (reclaimed from
;; set-mark-command; corfu/acm handle it further in their own maps).
(global-set-key (kbd "C-SPC") #'completion-at-point)
(general-define-key :states '(insert) "C-SPC" #'completion-at-point)

;;; ---------------------------------------------------------------------------
;;; Window map (evil-window-map tweaks; SPC w points at the same map)

(with-eval-after-load 'evil
  (define-key evil-window-map "d" #'mp/close-window-preserve-buffer) ; mp-ui
  (define-key evil-window-map "D" #'mp/workspace-close-window-or-workspace)
  (define-key evil-window-map "v" #'mp/split-window-right-fresh)     ; mp-workspaces
  (define-key evil-window-map "s" #'mp/split-window-below-fresh)
  (define-key evil-window-map "V" #'mp/evil-window-vsplit-and-follow)
  (define-key evil-window-map "S" #'mp/evil-window-split-and-follow)
  (define-key evil-window-map "u" #'winner-undo)
  (define-key evil-window-map (kbd "C-u") #'winner-undo)
  (define-key evil-window-map (kbd "C-r") #'winner-redo)
  (define-key evil-window-map "o" #'mp/window-enlargen)
  (define-key evil-window-map "O" #'delete-other-windows)
  (define-key evil-window-map "T" #'tear-off-window)
  (define-key evil-window-map "f" #'ffap-other-window)
  (define-key evil-window-map (kbd "C-S-w") #'ace-swap-window)
  (define-key evil-window-map (kbd "C-c") #'ace-delete-window)
  (define-key evil-window-map "H" #'mp/evil-window-move-left)
  (define-key evil-window-map "J" #'mp/evil-window-move-down)
  (define-key evil-window-map "K" #'mp/evil-window-move-up)
  (define-key evil-window-map "L" #'mp/evil-window-move-right)
  (define-key evil-window-map "m" (let ((m (make-sparse-keymap)))
                                    (define-key m "m" #'mp/window-maximize-buffer)
                                    (define-key m "v" #'mp/window-maximize-vertically)
                                    (define-key m "s" #'mp/window-maximize-horizontally)
                                    m)))

;;; ---------------------------------------------------------------------------
;;; Leader tree (mirrors the manifest, minus killed modules)

(mp/leader
  "" nil
  ;; Top level
  "RET" #'bookmark-jump
  "SPC" #'mp/super-menu
  "/"   #'mp/search-project
  "*"   #'mp/search-project-for-symbol-at-point
  "'"   #'vertico-repeat
  "`"   #'evil-switch-to-windows-last-buffer
  "<"   #'switch-to-buffer
  ","   #'persp-switch-to-buffer*
  "."   #'find-file
  "~"   #'popper-toggle
  ":"   #'execute-extended-command
  ";"   #'pp-eval-expression
  "a"   #'embark-act
  "u"   #'universal-argument
  "X"   #'org-capture
  "x"   #'scratch-buffer

  ;; b — buffers
  "b"   '(:ignore t :which-key "buffers")
  "b b" #'persp-switch-to-buffer*
  "b B" #'switch-to-buffer
  "b c" #'clone-indirect-buffer
  "b C" #'clone-indirect-buffer-other-window
  "b d" #'kill-current-buffer
  "b i" #'ibuffer
  "b I" #'persp-ibuffer
  "b k" #'kill-current-buffer
  "b K" #'mp/kill-all-buffers
  "b l" #'evil-switch-to-windows-last-buffer
  "b m" #'bookmark-set
  "b M" #'bookmark-delete
  "b n" #'next-buffer
  "b N" #'evil-buffer-new
  "b O" #'mp/kill-other-buffers
  "b p" #'previous-buffer
  "b r" #'revert-buffer
  "b R" #'rename-buffer
  "b s" #'basic-save-buffer
  "b S" #'evil-write-all
  "b u" #'mp/sudo-save-buffer
  "b x" #'scratch-buffer
  "b X" #'scratch-buffer
  "b y" #'mp/yank-buffer-contents
  "b z" #'bury-buffer
  "b Z" #'mp/kill-buried-buffers
  "b h" #'mp/dashboard          ; workspace dashboard / home
  "b ]" #'next-buffer
  "b [" #'previous-buffer
  "b -" #'mp/toggle-narrow-buffer

  ;; c — code
  "c"   '(:ignore t :which-key "code")
  "c a" #'mp/lsp-code-actions
  "c c" #'compile
  "c C" #'recompile
  "c d" #'mp/lookup-definition
  "c D" #'mp/lookup-references
  "c e" #'mp/eval-buffer-or-region
  "c E" #'mp/eval-replace-region
  "c f" #'mp/format-region-or-buffer
  "c h" #'eldoc-box-help-at-point
  "c i" #'mp/lookup-implementations
  "c j" #'mp/workspace-symbols
  "c k" #'mp/lookup-documentation
  "c o" #'mp/lsp-organize-imports
  "c r" #'mp/lsp-rename
  "c s" #'mp/open-repl
  "c t" #'mp/lookup-type-definition
  "c w" #'delete-trailing-whitespace
  "c x" #'mp/list-errors

  ;; d — agent
  "d"   '(:ignore t :which-key "agent")
  "d a" #'agent-shell
  "d e" #'eca
  "d E" #'eca-stop
  "d c" #'eca-completion-mode
  "d r" #'eca-rewrite

  ;; e — errors
  "e"   '(:ignore t :which-key "errors")
  "e l" #'mp/list-errors
  "e n" #'mp/next-error
  "e p" #'mp/previous-error
  "e v" #'flycheck-verify-setup

  ;; f — files
  "f"   '(:ignore t :which-key "files")
  "f !" #'mp/save-without-format      ; mp-lsp
  "f c" #'editorconfig-find-current-editorconfig
  "f C" #'mp/copy-this-file
  "f d" #'dired-jump
  "f D" #'mp/delete-this-file
  "f e" #'mp/find-file-in-emacsd
  "f E" #'mp/browse-emacsd
  "f f" #'find-file
  "f F" #'mp/browse-project
  "f l" #'locate
  "f p" #'mp/find-file-in-emacsd
  "f P" #'mp/browse-emacsd
  "f r" #'consult-recent-file
  "f R" #'mp/move-this-file
  "f s" #'basic-save-buffer
  "f S" #'write-file
  "f u" #'mp/sudo-find-file
  "f U" #'mp/sudo-this-file
  "f y" #'mp/yank-buffer-path
  "f Y" #'mp/yank-buffer-path-relative-to-project

  ;; g — git
  "g"   '(:ignore t :which-key "git")
  "g g" #'magit-status
  "g G" #'magit-status-here
  "g b" #'magit-branch-checkout
  "g B" #'magit-blame-addition
  "g C" #'magit-clone
  "g D" #'magit-file-delete
  "g F" #'magit-fetch
  "g L" #'magit-log-buffer-file
  "g S" #'magit-stage-file
  "g U" #'magit-unstage-file
  "g R" #'vc-revert
  "g t" #'git-timemachine-toggle
  "g y" #'mp/git-link-kill
  "g Y" #'mp/git-link-homepage-kill
  "g /" #'magit-dispatch
  "g ." #'magit-file-dispatch
  "g [" #'diff-hl-previous-hunk
  "g ]" #'diff-hl-next-hunk
  "g s" #'diff-hl-stage-current-hunk
  "g r" #'diff-hl-revert-hunk
  "g c" '(:ignore t :which-key "create")
  "g c r" #'magit-init
  "g c R" #'magit-clone
  "g c c" #'magit-commit-create
  "g c f" #'magit-commit-fixup
  "g c b" #'magit-branch-and-checkout
  "g f" '(:ignore t :which-key "find")
  "g f f" #'magit-find-file
  "g f g" #'magit-find-git-config-file
  "g f c" #'magit-show-commit
  "g l" '(:ignore t :which-key "list")
  "g l r" #'magit-list-repositories
  "g l s" #'magit-list-submodules
  "g o" '(:ignore t :which-key "open in browser")
  "g o o" #'mp/git-link-open
  "g o h" #'mp/git-link-homepage-open

  ;; h — help: reuse the stock help-map wholesale (like Doom did), so every
  ;; C-h entry (h C-a about, h RET manual, ...) comes along for free. The
  ;; Doom-style customizations are applied to help-map itself below.
  "h"   '(:keymap help-map :which-key "help")

  ;; i — insert
  "i"   '(:ignore t :which-key "insert")
  "i e" #'emoji-search
  "i f" #'mp/insert-file-path
  "i r" #'evil-show-registers
  "i u" #'insert-char
  "i y" #'consult-yank-pop

  ;; n — notes
  "n"   '(:ignore t :which-key "notes")
  "n a" #'org-agenda
  "n c" #'org-clock-in-last
  "n C" #'org-clock-cancel
  "n f" #'mp/find-in-notes          ; mp-org
  "n F" #'mp/browse-notes
  "n l" #'org-store-link
  "n m" #'org-tags-view
  "n n" #'org-capture
  "n N" #'org-capture-goto-target
  "n o" #'org-clock-goto
  "n s" #'mp/search-notes
  "n t" #'org-todo-list
  "n v" #'org-search-view
  "n y" #'mp/org-export-to-clipboard

  ;; o — open
  "o"   '(:ignore t :which-key "open")
  "o a" '(:ignore t :which-key "org agenda")
  "o a a" #'org-agenda
  "o a t" #'org-todo-list
  "o a m" #'org-tags-view
  "o a v" #'org-search-view
  "o A" #'org-agenda
  "o b" #'browse-url-of-file
  "o d" #'dape
  "o D" #'docker
  "o e" #'mp/ghostel-open            ; custom-shortcuts pkg (replaces eshell)
  "o E" #'mp/ghostel-new
  "o f" #'make-frame
  "o F" #'select-frame-by-name
  "o p" #'dirvish-side
  "o /" #'dirvish
  "o -" #'dired-jump
  "o r" #'mp/open-repl
  "o R" #'mp/open-repl
  "o s" #'clutch-query-console
  "o t" '(:ignore t :which-key "teamwork")
  "o t t" #'teamwork-timesheet
  "o t m" #'teamwork-management
  "o t c" #'teamwork-comments
  "o l" '(:ignore t :which-key "finance")
  "o l l" #'mp/hledger-open-journal
  "o l L" #'mp/hledger-open-current-month
  "o l a" #'mp/hledger-add-transaction
  "o l f" #'mp/hledger-forecast
  "o l F" #'mp/hledger-open-forecast
  "o l b" #'mp/hledger-balance-sheet
  "o l i" #'mp/hledger-income-statement
  "o l e" #'mp/hledger-expenses
  "o l r" #'mp/hledger-register
  "o l v" #'mp/hledger-value
  "o l p" #'mp/hledger-open-prices
  "o l w" #'mp/hledger-wishlist
  "o l W" #'mp/hledger-open-wishlist
  "o l k" #'mp/hledger-plan
  "o l P" #'mp/hledger-open-plan-config
  "o l x" #'mp/hledger-switch-entity
  "o l n" #'mp/hledger-new-book
  "o l c" #'mp/hledger-check
  "o l s" #'mp/hledger-stats

  ;; p — project
  "p"   '(:ignore t :which-key "project")
  "p p" #'mp/project-menu            ; mp-workspaces
  "p a" #'projectile-add-known-project
  "p b" #'projectile-switch-to-buffer
  "p c" #'projectile-compile-project
  "p C" #'projectile-repeat-last-command
  "p d" #'projectile-remove-known-project
  "p D" #'projectile-discover-projects-in-search-path
  "p e" #'projectile-edit-dir-locals
  "p f" #'projectile-find-file
  "p F" #'mp/find-file-in-other-project
  "p g" #'projectile-configure-project
  "p i" #'projectile-invalidate-cache
  "p k" #'projectile-kill-buffers
  "p o" #'find-sibling-file
  "p r" #'projectile-recentf
  "p R" #'projectile-run-project
  "p s" #'projectile-save-project-buffers
  "p S" #'my/run-project-script      ; project-scripts pkg
  "p T" #'projectile-test-project
  "p x" #'scratch-buffer
  "p !" #'projectile-run-shell-command-in-root
  "p &" #'projectile-run-async-shell-command-in-root
  "p ." #'mp/browse-project
  "p >" #'mp/browse-in-other-project

  ;; q — quit/session
  "q"   '(:ignore t :which-key "quit/session")
  "q q" #'save-buffers-kill-terminal
  "q Q" #'evil-quit-all-with-error-code
  "q K" #'save-buffers-kill-emacs
  "q f" #'delete-frame
  "q F" #'mp/kill-all-buffers
  "q r" #'restart-emacs
  "q s" #'mp/workspace-save-session  ; mp-workspaces
  "q S" #'mp/workspace-save-session
  "q l" #'mp/workspace-load-session
  "q L" #'mp/workspace-load-session

  ;; s — search
  "s"   '(:ignore t :which-key "search")
  "s b" #'mp/search-buffer
  "s s" #'mp/search-buffer
  "s S" #'mp/search-symbol-at-point
  "s d" #'mp/search-cwd
  "s D" #'mp/search-other-cwd
  "s e" #'mp/search-emacsd
  "s f" #'locate
  "s i" #'consult-imenu
  "s I" #'consult-imenu-multi
  "s j" #'evil-show-jumps
  "s l" #'link-hint-open-link
  "s L" #'ffap-menu
  "s m" #'bookmark-jump
  "s o" #'mp/search-online
  "s O" #'mp/search-online
  "s p" #'mp/search-project
  "s P" #'mp/search-other-project
  "s t" #'dictionary-search
  "s T" #'dictionary-search
  "s u" #'vundo
  "s r" '(:ignore t :which-key "replace (color-rg)")
  "s r f" #'color-rg-search-input-in-current-file
  "s r p" #'color-rg-search-input-in-project

  ;; t — toggle
  "t"   '(:ignore t :which-key "toggle")
  "t b" #'mp/lsp-bridge-toggle       ; mp-lsp (inverted semantics)
  "t c" #'global-display-fill-column-indicator-mode
  "t d" #'diff-hl-mode
  "t f" #'flycheck-mode
  "t F" #'toggle-frame-fullscreen
  "t g" #'evil-goggles-mode
  "t i" #'indent-bars-mode
  "t I" #'mp/toggle-indent-style
  "t l" #'mp/toggle-line-numbers
  "t r" #'read-only-mode
  "t v" #'visible-mode
  "t w" #'visual-line-mode
  "t t" #'mp/run-tests
  "t a" #'projectile-test-project
  "t W" #'mp/workspace-hud-toggle    ; workspace-hud pkg

  ;; v — visual
  "v"   '(:ignore t :which-key "visual")
  "v v" #'evil-visual-line
  "v b" #'evil-visual-block

  ;; w — windows: reuse evil-window-map (already customized above)
  "w"   '(:keymap evil-window-map :which-key "windows")

  ;; m — code navigation splits (global SPC m; localleaders shadow per mode)
  "m"   '(:ignore t :which-key "<localleader>")
  "m g" '(:ignore t :which-key "goto")
  "m g d v" #'mp/goto-definition-split-right
  "m g d s" #'mp/goto-definition-split-below
  "m g r v" #'mp/goto-references-split-right
  "m g r s" #'mp/goto-references-split-below
  "m g f s" #'consult-imenu

  ;; TAB — workspaces (perspective-backed, defined in mp-workspaces)
  "TAB" '(:ignore t :which-key "workspace")
  "TAB TAB" #'mp/workspace-display
  "TAB n" #'mp/workspace-new
  "TAB N" #'mp/workspace-new-named
  "TAB d" #'mp/workspace-kill
  "TAB D" #'mp/workspace-delete
  "TAB r" #'mp/workspace-rename
  "TAB s" #'mp/workspace-save-session
  "TAB l" #'mp/workspace-load-session
  "TAB `" #'mp/workspace-other
  "TAB ." #'mp/workspace-switch
  "TAB [" #'mp/workspace-switch-left
  "TAB ]" #'mp/workspace-switch-right
  "TAB 1" #'mp/workspace-switch-to-0
  "TAB 2" #'mp/workspace-switch-to-1
  "TAB 3" #'mp/workspace-switch-to-2
  "TAB 4" #'mp/workspace-switch-to-3
  "TAB 5" #'mp/workspace-switch-to-4
  "TAB 6" #'mp/workspace-switch-to-5
  "TAB 7" #'mp/workspace-switch-to-6
  "TAB 8" #'mp/workspace-switch-to-7
  "TAB 9" #'mp/workspace-switch-to-8
  "TAB 0" #'mp/workspace-switch-to-final

  ;; GUI Emacs sends <tab>, not TAB (C-i), and the function-key fallback does
  ;; not fire inside the leader prefix — mirror the whole workspace submenu.
  "<tab>" '(:ignore t :which-key "workspace")
  "<tab> <tab>" #'mp/workspace-display
  "<tab> TAB" #'mp/workspace-display
  "<tab> n" #'mp/workspace-new
  "<tab> N" #'mp/workspace-new-named
  "<tab> d" #'mp/workspace-kill
  "<tab> D" #'mp/workspace-delete
  "<tab> r" #'mp/workspace-rename
  "<tab> R" #'mp/workspace-load-session
  "<tab> s" #'mp/workspace-save-session
  "<tab> l" #'mp/workspace-load-session
  "<tab> x" #'mp/workspace-kill-session
  "<tab> `" #'mp/workspace-other
  "<tab> ." #'mp/workspace-switch
  "<tab> [" #'mp/workspace-switch-left
  "<tab> ]" #'mp/workspace-switch-right
  "<tab> 1" #'mp/workspace-switch-to-0
  "<tab> 2" #'mp/workspace-switch-to-1
  "<tab> 3" #'mp/workspace-switch-to-2
  "<tab> 4" #'mp/workspace-switch-to-3
  "<tab> 5" #'mp/workspace-switch-to-4
  "<tab> 6" #'mp/workspace-switch-to-5
  "<tab> 7" #'mp/workspace-switch-to-6
  "<tab> 8" #'mp/workspace-switch-to-7
  "<tab> 9" #'mp/workspace-switch-to-8
  "<tab> 0" #'mp/workspace-switch-to-final)

;; help-map customizations (shared by SPC h and C-h; helpful's remaps in
;; mp-core cover f/v/k/o/x already)
(define-key help-map "a" #'apropos)
(define-key help-map "A" #'apropos-documentation)
(define-key help-map "F" #'describe-face)
(define-key help-map "M" #'describe-minor-mode)
(define-key help-map "p" #'describe-package)
(define-key help-map "P" #'find-library)
(define-key help-map "t" #'load-theme)
(define-key help-map "W" #'woman)
(define-key help-map "'" #'describe-char)
(define-key help-map "O" #'mp/search-online)
(define-key help-map (kbd "C-k") #'describe-key-briefly)
(define-key help-map (kbd "C-l") #'describe-language-environment)
(define-key help-map "b"
            (let ((m (make-sparse-keymap)))
              (define-key m "b" #'describe-bindings)
              (define-key m "f" #'which-key-show-full-keymap)
              (define-key m "i" #'which-key-show-minor-mode-keymap)
              (define-key m "k" #'which-key-show-keymap)
              (define-key m "m" #'which-key-show-major-mode)
              (define-key m "t" #'which-key-show-top-level)
              m))
(define-key help-map "r"
            (let ((m (make-sparse-keymap)))
              (define-key m "r" #'mp/reload-init)
              m))

;; Small ports surfaced by the keymap diff
(defun mp/delete-trailing-newlines ()
  "Trim trailing newlines at end of buffer."
  (interactive)
  (save-excursion
    (goto-char (point-max))
    (skip-chars-backward "\n")
    (unless (eobp)
      (delete-region (min (point-max) (1+ (point))) (point-max)))))

(defun mp/search-notes-for-symbol-at-point ()
  "Ripgrep the org notes directory for the symbol at point."
  (interactive)
  (consult-ripgrep org-directory (thing-at-point 'symbol)))

(defun mp/dirvish-side-follow ()
  "Open the dirvish side panel and follow the current file."
  (interactive)
  (dirvish-side)
  (when (fboundp 'dirvish-side-follow-mode)
    (dirvish-side-follow-mode 1)))

(mp/leader
  "c W"   #'mp/delete-trailing-newlines
  "TAB R" #'mp/workspace-load-session
  "TAB x" #'mp/workspace-kill-session
  "n *"   #'mp/search-notes-for-symbol-at-point
  "n S"   #'consult-org-agenda
  "o P"   #'mp/dirvish-side-follow
  "p X"   #'scratch-buffer)

(with-eval-after-load 'evil
  (define-key evil-window-map (kbd "C-w") #'other-window))

;; Split-jump commands (Code Navigation section of config.org)
(defun mp/split-and-run (split-fn cmd)
  "Create a split via SPLIT-FN, focus it, then run CMD there."
  (select-window (funcall split-fn))
  (call-interactively cmd))

(defun mp/goto-definition-split-right ()
  "Jump to definition in a split to the right."
  (interactive)
  (mp/split-and-run #'split-window-right #'mp/lookup-definition))

(defun mp/goto-definition-split-below ()
  "Jump to definition in a split below."
  (interactive)
  (mp/split-and-run #'split-window-below #'mp/lookup-definition))

(defun mp/goto-references-split-right ()
  "Find references in a split to the right."
  (interactive)
  (mp/split-and-run #'split-window-right #'xref-find-references))

(defun mp/goto-references-split-below ()
  "Find references in a split below."
  (interactive)
  (mp/split-and-run #'split-window-below #'xref-find-references))

(provide 'mp-keys)
;;; mp-keys.el ends here
