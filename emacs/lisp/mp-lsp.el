;;; mp-lsp.el --- lsp-bridge default, eglot fallback, flycheck, apheleia -*- lexical-binding: t; -*-

;; Architecture (decided at migration): lsp-bridge is the DEFAULT LSP client +
;; completion UI in prog buffers it supports. Built-in eglot covers languages
;; lsp-bridge can't (gdscript talks TCP to a running Godot editor). Corfu
;; (mp-completion) serves buffers neither client manages. `SPC t b' toggles
;; bridge OFF per buffer, restoring corfu/eglot.

;;; Flycheck (non-bridge diagnostics: elisp, hledger, fallback buffers)

(use-package flycheck
  :hook (elpaca-after-init . global-flycheck-mode)
  :config
  (setq flycheck-emacs-lisp-load-path 'inherit
        flycheck-idle-change-delay 0.8)
  ;; Bridge buffers surface their own diagnostics; don't double-report.
  (add-hook 'lsp-bridge-mode-hook
            (lambda () (when (bound-and-true-p flycheck-mode) (flycheck-mode -1)))))

;;; Formatting (apheleia replaces Doom's format +onsave)

(use-package apheleia
  :hook (elpaca-after-init . apheleia-global-mode)
  :config
  ;; Prettier for the JS/TS/web family (port of the +format-with list).
  (dolist (pair '((js-mode . prettier)
                  (js-ts-mode . prettier)
                  (typescript-ts-mode . prettier)
                  (tsx-ts-mode . prettier)
                  (web-mode . prettier)
                  (css-mode . prettier)
                  (css-ts-mode . prettier)
                  (scss-mode . prettier)))
    (setf (alist-get (car pair) apheleia-mode-alist) (cdr pair)))
  ;; GDScript via gdtoolkit (pip install "gdtoolkit>=4").
  (setf (alist-get 'gdformat apheleia-formatters)
        '("gdformat" "-"))
  (dolist (mode '(gdscript-mode gdscript-ts-mode))
    (setf (alist-get mode apheleia-mode-alist) 'gdformat)))

;; Declared special so the let-binding stays dynamic under byte-compilation.
(defvar apheleia-mode)

(defun mp/save-without-format ()
  "Save current buffer without running the on-save formatter."
  (interactive)
  (let ((apheleia-mode nil))
    (save-buffer)))

(defun mp/format-region-or-buffer ()
  "Format the buffer with apheleia (elisp regions indent natively)."
  (interactive)
  (if (and (use-region-p) (derived-mode-p 'emacs-lisp-mode))
      (indent-region (region-beginning) (region-end))
    (call-interactively #'apheleia-format-buffer)))

;;; eldoc / hover

(use-package eldoc-box
  :commands (eldoc-box-help-at-point)
  :config
  (setq eldoc-box-max-pixel-width 900
        eldoc-box-max-pixel-height 520
        eldoc-box-cleanup-interval 0.35
        eldoc-box-only-multi-line nil))

;;; Xref fallback of last resort

(use-package dumb-jump
  :defer t
  :init
  (add-hook 'xref-backend-functions #'dumb-jump-xref-activate 100))

;;; eglot — fallback client for languages lsp-bridge lacks

(use-package eglot
  :ensure nil
  :defer t
  :config
  (setq eglot-autoshutdown t
        eglot-sync-connect nil)
  ;; Godot's LSP is a TCP server inside the running editor (port 6005).
  (add-to-list 'eglot-server-programs
               '((gdscript-mode gdscript-ts-mode) "localhost" 6005)))

;;; lsp-bridge — the default client

(defvar mp/lsp-bridge-modes
  '(python-mode python-ts-mode
    js-mode js-ts-mode typescript-ts-mode tsx-ts-mode
    go-mode go-ts-mode
    lua-mode lua-ts-mode
    php-mode php-ts-mode
    web-mode css-mode css-ts-mode scss-mode
    json-mode json-ts-mode yaml-mode yaml-ts-mode
    sh-mode bash-ts-mode
    graphql-mode qml-mode qml-ts-mode
    c-mode c-ts-mode c++-mode c++-ts-mode
    rust-mode rust-ts-mode)
  "Major modes where lsp-bridge is enabled by default.
gdscript is deliberately absent (Godot LSP is TCP-only -> eglot).")

;; lsp-bridge hard-requires yasnippet (acm -> acm-backend-yas). The snippets
;; FEATURE stays killed: no snippet libraries, no file templates, and the acm
;; snippet suggestions are disabled below — yasnippet exists solely so LSP
;; completion placeholders (function args etc.) can expand.
(use-package yasnippet
  :defer t
  :init (setq yas-snippet-dirs nil))

;; NOTE: lsp-bridge's Package-Requires pulls in markdown-mode, which mp-langs
;; also declares first-class. That re-declaration conflict (and the whole class
;; of transitive-dep-also-declared-first-class) is neutralised globally by the
;; `mp/elpaca--enqueue-tolerant-a' advice in init.el.

(defun mp/lsp-bridge-project-root (filename)
  "Return the lsp-bridge project root for FILENAME.
JS/TS-family files root at their nearest package.json/tsconfig.json so
language servers resolve the project-local toolchain (typescript,
tsconfig, eslint) in monorepos where the frontend lives in a
subdirectory — the .git root would sit above it and tsserver would fail
to find a TypeScript install.  Everything else falls back to the .git
toplevel, which is lsp-bridge's default."
  (let* ((dir (file-name-directory (or filename default-directory)))
         (node (when (member (file-name-extension filename)
                             '("ts" "tsx" "cts" "mts" "js" "jsx" "cjs" "mjs"))
                 (or (locate-dominating-file dir "tsconfig.json")
                     (locate-dominating-file dir "package.json")))))
    (directory-file-name
     (expand-file-name
      (or node (locate-dominating-file dir ".git") dir)))))

(use-package lsp-bridge
  :ensure (:host github :repo "manateelazycat/lsp-bridge"
           :files (:defaults "*.py" "acm" "core" "langserver" "multiserver" "resources")
           :build (:not elpaca--byte-compile))
  :hook (elpaca-after-init . mp/lsp-bridge-enable-defaults)
  :init
  ;; Dedicated venv keeps the backend off the system Python. Create it once:
  ;;   python -m venv <var>/lsp-bridge-venv
  ;;   <venv>/bin/pip install epc orjson sexpdata six setuptools paramiko rapidfuzz watchdog packaging
  (setq lsp-bridge-python-command
        (expand-file-name "lsp-bridge-venv/bin/python" mp/var-dir))
  :config
  ;; ACM completion UI — tuned to the established "VSCode feel".
  (setq acm-enable-icon t
        acm-enable-doc t
        acm-enable-quick-access nil
        acm-enable-tabnine nil
        acm-enable-copilot nil
        acm-enable-yas nil               ; no snippet suggestions in the menu
        acm-candidate-match-function 'orderless-flex)
  ;; yas-minor-mode must be active for LSP placeholder expansion.
  (add-hook 'lsp-bridge-mode-hook #'yas-minor-mode)
  (setq lsp-bridge-enable-hover-diagnostic t
        lsp-bridge-enable-signature-help t
        lsp-bridge-signature-show-function 'lsp-bridge-signature-show-with-frame
        lsp-bridge-enable-search-words nil
        lsp-bridge-diagnostic-fetch-idle 1.0)

  ;; References as a "peek": don't blow away the layout. The default handler
  ;; runs `delete-other-windows' then splits fullscreen; instead keep the code
  ;; window and open a compact panel below it, with jumps reusing the code
  ;; window above — VSCode/lsp-ui-peek feel (lsp-bridge has no inline overlay).
  (setq lsp-bridge-ref-delete-other-windows nil
        lsp-bridge-ref-open-file-in-request-window t)

  ;; Monorepo TS/JS: root at the nearest package.json/tsconfig.json (e.g. a
  ;; `client/' subfolder) rather than the .git toplevel, so the language server
  ;; finds the project-local typescript install + tsconfig. Without this, a
  ;; frontend nested under a backend git root fails: "Could not find a valid
  ;; TypeScript installation". Non-JS files keep the default .git root.
  (setq lsp-bridge-get-project-path-by-filepath #'mp/lsp-bridge-project-root)

  ;; IDE navigation inside bridge buffers (port; now the default nav).
  (evil-define-key 'normal lsp-bridge-mode-map
    "gd"        #'lsp-bridge-find-def
    "gD"        #'lsp-bridge-find-references
    "gi"        #'lsp-bridge-find-impl
    "gr"        #'lsp-bridge-find-references
    "gR"        #'lsp-bridge-rename
    "K"         #'lsp-bridge-popup-documentation
    (kbd "] e") #'lsp-bridge-diagnostic-jump-next
    (kbd "[ e") #'lsp-bridge-diagnostic-jump-prev
    "gb"        #'lsp-bridge-find-def-return)
  (when (fboundp 'lsp-bridge-popup-complete-menu)
    (evil-define-key 'insert lsp-bridge-mode-map
      (kbd "C-SPC") #'lsp-bridge-popup-complete-menu))

  ;; Bridge owns completion in its buffers; corfu must stand down.
  (add-hook 'lsp-bridge-mode-hook
            (lambda ()
              (when (fboundp 'corfu-mode)
                (corfu-mode (if lsp-bridge-mode -1 1))))))

(defun mp/lsp-bridge--supported-p ()
  (and (apply #'derived-mode-p mp/lsp-bridge-modes)
       ;; The backend needs its venv; degrade gracefully when missing.
       (file-executable-p lsp-bridge-python-command)))

(defvar-local mp/lsp-bridge-opted-out nil
  "Non-nil when the user toggled lsp-bridge off in this buffer.")

(defvar mp/lsp-bridge--warned-no-venv nil)

(defun mp/lsp-bridge-maybe-enable ()
  "Enable lsp-bridge in supported buffers unless opted out.
Warns once per session when the backend venv is missing, since that
otherwise degrades silently to no completion at all."
  (cond
   ((and (apply #'derived-mode-p mp/lsp-bridge-modes)
         (not (file-executable-p lsp-bridge-python-command))
         (not mp/lsp-bridge--warned-no-venv))
    (setq mp/lsp-bridge--warned-no-venv t)
    (message "lsp-bridge is OFF: backend venv missing at %s — see README \"First launch\" step 2"
             lsp-bridge-python-command))
   ((and (mp/lsp-bridge--supported-p)
         (not mp/lsp-bridge-opted-out)
         (not (bound-and-true-p lsp-bridge-mode)))
    (lsp-bridge-mode 1))))

(defun mp/lsp-bridge-enable-defaults ()
  "Turn on bridge-by-default for all future (and current) prog buffers."
  (add-hook 'prog-mode-hook #'mp/lsp-bridge-maybe-enable)
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (derived-mode-p 'prog-mode)
        (mp/lsp-bridge-maybe-enable)))))

(defvar mp/lsp-server-binaries
  '(((python-mode python-ts-mode) . ("basedpyright-langserver" "pyright-langserver"))
    ((js-mode js-ts-mode typescript-ts-mode tsx-ts-mode) . ("typescript-language-server"))
    ((go-mode go-ts-mode) . ("gopls"))
    ((php-mode php-ts-mode) . ("intelephense" "phpactor"))
    ((lua-mode lua-ts-mode) . ("lua-language-server" "lua-lsp"))
    ((qml-mode qml-ts-mode) . ("qmlls"))
    ((graphql-mode) . ("graphql-lsp"))
    ((sh-mode bash-ts-mode) . ("bash-language-server"))
    ((css-mode css-ts-mode scss-mode web-mode) . ("vscode-css-language-server"))
    ((json-mode json-ts-mode) . ("vscode-json-language-server"))
    ((yaml-mode yaml-ts-mode) . ("yaml-language-server")))
  "Per-mode language-server executables lsp-bridge shells out to.")

(defun mp/lsp-doctor ()
  "Explain why LSP completion may not be working in this buffer."
  (interactive)
  (let* ((venv-ok (file-executable-p lsp-bridge-python-command))
         (bridge-on (bound-and-true-p lsp-bridge-mode))
         ;; The EPC backend process is named `lsp-bridge-name' ("*lsp-bridge*"),
         ;; so `get-process "lsp-bridge"' never matched. Ask lsp-bridge itself.
         (proc (and (fboundp 'lsp-bridge-process-live-p)
                    (lsp-bridge-process-live-p)))
         (servers (cdr (seq-find (lambda (cell) (apply #'derived-mode-p (car cell)))
                                 mp/lsp-server-binaries)))
         (found (and servers (seq-find #'executable-find servers))))
    (message
     "%s | %s | %s | %s%s"
     (if venv-ok "venv OK"
       (format "venv MISSING at %s (README step 2)" lsp-bridge-python-command))
     (if bridge-on "bridge ON in buffer" "bridge OFF (corfu/dabbrev fallback)")
     (if proc "backend process running" "backend process NOT running")
     (cond ((null servers) "no server mapping for this mode (eglot/none)")
           (found (format "server: %s" found))
           (t (format "server NOT FOUND — install one of: %s"
                      (string-join servers ", "))))
     (cond ((and venv-ok bridge-on proc (or (null servers) found)) "")
           ((and venv-ok (not bridge-on) (or (null servers) found))
            ;; Everything installed but this buffer predates it: the
            ;; enable-check ran when the venv was still missing.
            " → SPC t b here (or restart Emacs) to attach the bridge")
           (t " → completion falls back to word matching until all are green")))))

(defun mp/lsp-bridge-toggle ()
  "Toggle lsp-bridge in this buffer (default is ON in supported modes).
Turning it off restores corfu, and eglot where configured (gdscript)."
  (interactive)
  (if (bound-and-true-p lsp-bridge-mode)
      (progn
        (setq mp/lsp-bridge-opted-out t)
        (lsp-bridge-mode -1)
        (when (fboundp 'corfu-mode) (corfu-mode 1))
        (message "lsp-bridge OFF — corfu restored%s"
                 (if (bound-and-true-p eglot--managed-mode) " (eglot active)" "")))
    (setq mp/lsp-bridge-opted-out nil)
    (if (mp/lsp-bridge--supported-p)
        (progn
          (when (bound-and-true-p eglot--managed-mode) (ignore-errors (eglot-shutdown (eglot-current-server))))
          (when (fboundp 'corfu-mode) (corfu-mode -1))
          (lsp-bridge-mode 1)
          (message "lsp-bridge ON"))
      (user-error "lsp-bridge doesn't support %s (or its venv is missing)" major-mode))))

(provide 'mp-lsp)
;;; mp-lsp.el ends here
