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

(defvar mp/lsp-bridge-signature-width 72
  "Column width the lsp-bridge signature popup is hard-wrapped to.")

(defun mp/lsp-bridge-signature-show (str)
  "Render STR as the signature popup, hard-wrapped to `mp/lsp-bridge-signature-width'.
lsp-bridge sizes the signature frame to its longest line, so a huge
unwrapped type (e.g. a `StyleSheet.create' argument) smears full-width
across the screen.  Pre-wrapping the text bounds the frame width."
  (lsp-bridge-signature-show-with-frame
   (if (or (null str) (string-empty-p str))
       (or str "")
     (with-temp-buffer
       (insert str)
       (let ((fill-column mp/lsp-bridge-signature-width))
         (fill-region (point-min) (point-max)))
       (buffer-string)))))

(defun mp/lsp-bridge-signature-suppress-p (&rest _)
  "Non-nil when lsp-bridge signature help should stay hidden right now.

Only ever surface it in evil NORMAL state — never while inserting/typing —
and never while the acm completion menu is visible.  lsp-bridge hides the
signature on every command and re-fetches it on an idle timer whenever the
cursor moved, which otherwise flickers it back up in insert state and on top
of the acm menu at point."
  (or (and (boundp 'acm-menu-frame)
           (fboundp 'acm-frame-visible-p)
           (acm-frame-visible-p acm-menu-frame))
      (and (fboundp 'evil-normal-state-p)
           (not (evil-normal-state-p)))))

(defun mp/lsp-bridge-ref-open-and-quit ()
  "Jump to the reference on the current line and close the references list.

lsp-bridge's references buffer is color-rg-derived: a file-path header
followed by `LINE:COL:' match lines.  On a match line this jumps there; on
a file header it opens that file's FIRST match — the same as pressing RET
on its first reference line.

Unlike the native RET (`lsp-bridge-ref-open-file-and-stay', which leaves
the list window open) and `lsp-bridge-ref-quit' (which restores the layout
from before the search, snapping you back to where `g r' was pressed), this
lands you AT the reference with the list closed — RET means \"go to this
reference for good.\"  Keep SPC for preview-while-browsing (opens the file
but stays in the list)."
  (interactive)
  (beginning-of-line)
  (when (looking-at-p lsp-bridge-ref-regexp-file)
    (when-let ((pos (lsp-bridge-ref-find-next-position lsp-bridge-ref-regexp-position)))
      (goto-char pos)))
  (let ((req lsp-bridge-ref-request-search-window))
    ;; Native RET: open the reference in the request window and leave point IN
    ;; that file.
    (lsp-bridge-ref-open-file-and-stay)
    ;; Tear the list down BY HAND. Deliberately NOT `lsp-bridge-ref-quit': quit
    ;; restores the window layout captured when `g r' was pressed (snapping you
    ;; back to the origin) and kills the buffer you just navigated into. Just
    ;; drop the list's window + buffer and land in the request window, which now
    ;; shows the reference.
    (let ((ref-win (get-buffer-window lsp-bridge-ref-buffer)))
      (when (and ref-win (window-valid-p ref-win)
                 (not (eq ref-win req))
                 (> (length (window-list nil 'no-mini)) 1))
        (delete-window ref-win)))
    (when (buffer-live-p (get-buffer lsp-bridge-ref-buffer))
      (kill-buffer lsp-bridge-ref-buffer))
    (when (window-valid-p req)
      (select-window req))
    ;; Clear the saved layout so nothing later resurrects the pre-search state.
    (setq lsp-bridge-ref-window-configuration-before-search nil
          lsp-bridge-ref-buffer-point-before-search nil
          lsp-bridge-ref-request-search-window nil)))

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
  ;; Signature help = the tooltip showing the parameter/type of the call point
  ;; is inside. The default renderer (`message') dumps it into the echo area
  ;; over the mode line; render it in a child frame docked at point instead, so
  ;; it reads like VSCode's inline signature popup rather than an echo-area wrap.
  (setq lsp-bridge-enable-hover-diagnostic t
        lsp-bridge-enable-signature-help t
        lsp-bridge-signature-show-function 'mp/lsp-bridge-signature-show
        lsp-bridge-signature-show-with-frame-position "point"
        lsp-bridge-enable-search-words nil
        lsp-bridge-diagnostic-fetch-idle 1.0)
  ;; Stop the signature popup and the acm completion menu from stacking at
  ;; point: only fetch the signature on cursor movement, never while typing or
  ;; while the completion menu is up (see `mp/lsp-bridge-signature-suppress-p').
  (advice-add 'lsp-bridge-signature-help-fetch :before-while
              (lambda (&rest _) (not (mp/lsp-bridge-signature-suppress-p)))
              '((name . mp/lsp-bridge-signature-gate)))

  ;; References list. It's color-rg-derived (a fork), so no true inline peek is
  ;; possible; keep the default popup handler (a plain bottom split — the one
  ;; whose window `lsp-bridge-ref-quit'/`q' can delete cleanly) but stop it from
  ;; blowing away the code window, and route jumps back into the request window.
  (setq lsp-bridge-ref-delete-other-windows nil
        lsp-bridge-ref-open-file-in-request-window t)
  ;; The results buffer's single-key commands (q, RET, SPC, j/k, e, r, f, ...)
  ;; live in `lsp-bridge-ref-mode-map', but evil normal state shadows them all.
  ;; Give the buffer evil emacs-state so the native color-rg keys work — same
  ;; treatment this config already gives the real `color-rg-mode'.
  (with-eval-after-load 'evil
    (evil-set-initial-state 'lsp-bridge-ref-mode 'emacs))
  (with-eval-after-load 'lsp-bridge-ref
    ;; RET: jump to the reference and close the list (on a file header, open its
    ;; first match). SPC keeps the native preview-and-stay-in-list behaviour.
    (define-key lsp-bridge-ref-mode-map (kbd "RET") #'mp/lsp-bridge-ref-open-and-quit)
    (define-key lsp-bridge-ref-mode-map (kbd "C-m") #'mp/lsp-bridge-ref-open-and-quit)
    ;; Arrow keys mirror the native j/k and h/l. The buffer is evil emacs-state,
    ;; so bare <up>/<down> would otherwise crawl raw lines (file headers, blanks)
    ;; instead of jumping match-to-match; <left>/<right> step file-to-file.
    (define-key lsp-bridge-ref-mode-map (kbd "<down>")  #'lsp-bridge-ref-jump-next-keyword)
    (define-key lsp-bridge-ref-mode-map (kbd "<up>")    #'lsp-bridge-ref-jump-prev-keyword)
    (define-key lsp-bridge-ref-mode-map (kbd "<right>") #'lsp-bridge-ref-jump-next-file)
    (define-key lsp-bridge-ref-mode-map (kbd "<left>")  #'lsp-bridge-ref-jump-prev-file))
  ;; The results buffer is a normal (non-child-frame) buffer, so the global SVG
  ;; header-line would otherwise render on top of it — turn it off.
  (add-hook 'lsp-bridge-ref-mode-hook
            (lambda () (setq-local header-line-format nil)))

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
    ;; vim's gf: open the file whose path is under point (config files, plain
    ;; relative paths). For JS/TS imports use `gd' instead — the language server
    ;; resolves the module and its extension; ffap can't guess `./a' -> `./a.ts'.
    "gf"        #'find-file-at-point
    "K"         #'lsp-bridge-popup-documentation
    (kbd "] e") #'lsp-bridge-diagnostic-jump-next
    (kbd "[ e") #'lsp-bridge-diagnostic-jump-prev
    "gb"        #'lsp-bridge-find-def-return)
  (when (fboundp 'lsp-bridge-popup-complete-menu)
    (evil-define-key 'insert lsp-bridge-mode-map
      (kbd "C-SPC") #'lsp-bridge-popup-complete-menu))

  ;; lsp-bridge keeps its own jump ring (popped by `gb'/`lsp-bridge-find-def-return'),
  ;; separate from xref's marker stack. That leaves `g [' (xref-go-back) and
  ;; `g ]' (xref-go-forward) empty after a bridge `gd' — "start of xref jump
  ;; history". Push the origin onto xref's stack before each bridge jump so the
  ;; global back/forward keys navigate bridge jumps too. (Bridge jumps are
  ;; async; :before records point at call time — exactly where we want to
  ;; return.)
  (require 'xref)
  (dolist (fn '(lsp-bridge-find-def
                lsp-bridge-find-def-other-window
                lsp-bridge-find-impl
                lsp-bridge-find-impl-other-window
                lsp-bridge-find-type-def
                lsp-bridge-find-type-def-other-window))
    (advice-add fn :before
                (lambda (&rest _) (xref-push-marker-stack))
                '((name . mp/lsp-bridge-push-xref))))

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
