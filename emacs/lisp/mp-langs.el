;;; mp-langs.el --- Per-language setup -*- lexical-binding: t; -*-

;; Python/pipenv process guards, Godot/GDScript + dape debugging, a
;; self-contained twee-mode for Twine/SugarCube authoring, and simple
;; deferred installs for the remaining languages. LSP clients, apheleia
;; and quickrun live elsewhere (mp-lsp.el / mp-tools.el).

;;; ---------------------------------------------------------------------------
;;; Python And Pipenv Safeguards
;; Stop Pipenv from being inferred, created, or invoked in the wrong
;; directory, especially inside monorepos where a repository root is not the
;; correct Python project root. pipenv.el itself is not installed; these
;; guards block any stray `pipenv' subprocess regardless of caller.

;; Never infer or create a Pipenv project at a monorepo root.
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

;;; ---------------------------------------------------------------------------
;;; Godot / GDScript
;; LSP comes from Godot's built-in language server on port 6005 (eglot,
;; wired in mp-lsp.el); debugging talks to Godot's Debug Adapter on port
;; 6006 via dape. Both need the Godot editor open, so eglot startup must
;; never error when it isn't.

(defun mp/gdscript-eglot-maybe ()
  "Start eglot for GDScript, tolerating an absent Godot editor.
Godot's language server only listens while the editor is open; opening a
.gd file without it must not signal."
  (ignore-errors (eglot-ensure)))

(defun mp/gdscript-lsp-connect ()
  "Attach (or re-attach) eglot to Godot's language server for this buffer.
Godot's LSP (port 6005) only listens while its editor is open, so when a
.gd buffer is opened first and Godot started afterwards eglot isn't
connected — run this (SPC m l, or plain `M-x eglot') to connect."
  (interactive)
  (let ((server (and (fboundp 'eglot-current-server) (eglot-current-server))))
    (if server
        (eglot-reconnect server)
      (eglot-ensure))))

;; gdscript-mode soft-requires hydra (`require 'hydra nil t') and powers
;; `gdscript-hydra-show' — a launcher menu (run project/scene/script, debug
;; flags, format, history).  hydra isn't a hard dependency, so pull it in
;; explicitly; without it that command just errors.  NOTE: gdscript-hydra.el
;; must be byte-compiled *after* hydra exists, so on first setup rebuild the
;; package once: `M-x elpaca-rebuild RET gdscript-mode RET' then restart.
(use-package hydra
  :demand t)

;; Tree-sitter GDScript gives far richer highlighting than the hand-written
;; font-lock (types, enums, members, etc).  Register the grammar source so it
;; can be fetched+built with `M-x treesit-install-language-grammar RET gdscript
;; RET' (needs a C compiler + git); once the grammar is present, `.gd' opens in
;; `gdscript-ts-mode' via the remap below.  Restart Emacs after installing it.
(when (require 'treesit nil t)
  (add-to-list 'treesit-language-source-alist
               '(gdscript "https://github.com/PrestonKnopp/tree-sitter-gdscript"))
  (when (treesit-ready-p 'gdscript t)
    (add-to-list 'major-mode-remap-alist '(gdscript-mode . gdscript-ts-mode))))

(use-package gdscript-mode
  :after hydra
  :mode ("\\.gd\\'" . gdscript-mode)
  ;; Autoloaded so the tree-sitter remap above can start it.
  :commands (gdscript-ts-mode)
  :config
  (add-hook 'gdscript-mode-hook #'mp/gdscript-eglot-maybe)
  (when (boundp 'gdscript-ts-mode-hook)
    (add-hook 'gdscript-ts-mode-hook #'mp/gdscript-eglot-maybe)))

;; Localleader: the module's own run/help commands (per the Doom keymap
;; manifest) plus a dape-backed debug prefix. gdscript-ts-mode derives from
;; gdscript-mode, so binding gdscript-mode-map covers both.
(mp/localleader
  :keymaps 'gdscript-mode-map
  "d"   '(:ignore t :which-key "debug")
  "d d" #'dape
  "d b" #'dape-breakpoint-toggle
  "d c" #'dape-continue
  "d n" #'dape-next
  "d s" #'dape-step-in
  "d o" #'dape-step-out
  "d p" #'dape-pause
  "d r" #'dape-restart
  "d q" #'dape-quit
  "d i" #'dape-info
  "d R" #'dape-repl
  "l"   '(mp/gdscript-lsp-connect :which-key "connect LSP")
  "r"   '(:ignore t :which-key "run")
  "r r" #'gdscript-hydra-show          ; launcher menu (also on C-c r)
  "r p" #'gdscript-godot-run-project
  "r d" #'gdscript-godot-run-project-debug
  "r s" #'gdscript-godot-run-current-scene
  "r e" #'gdscript-godot-open-project-in-editor
  "h"   '(:ignore t :which-key "help")
  "h f" #'gdscript-docs-browse-symbol-at-point
  "h b" #'gdscript-docs-browse-api)

;;; ---------------------------------------------------------------------------
;;; Godot -> Emacs "Open in External Editor" routing
;; Godot hands a script to `emacsclient' via bin/godot-emacsclient, which calls
;; `mp/open-file-in-project-workspace'.  Rather than dropping the file into
;; whatever workspace happens to be current, we route it to the workspace bound
;; to its project — creating that workspace, a git repo, and a Projectile entry
;; if they don't exist yet — so completion, debugging and the dashboard all
;; light up for the project.

(defun mp/project-root-for-file (file)
  "Best project root for FILE, as a directory name with a trailing slash.
Prefers the Godot project (the directory holding `project.godot'), then a
VCS root, then a Projectile root, and finally FILE's own directory."
  (let ((dir (file-name-directory (expand-file-name file))))
    (file-name-as-directory
     (expand-file-name
      (or (locate-dominating-file dir "project.godot")
          (locate-dominating-file dir ".git")
          (and (fboundp 'projectile-project-root)
               (let ((default-directory dir))
                 (ignore-errors (projectile-project-root))))
          dir)))))

(defun mp/ensure-git-repo (root)
  "Make sure ROOT is a git repository, running `git init' if it is not.
Projectile treats `.git' as a project marker and the dashboard's git panel
needs a repo to read, so a bare Godot project (no VCS) is given one.
Returns ROOT unchanged."
  (unless (file-directory-p (expand-file-name ".git" root))
    (let ((default-directory root))
      (with-demoted-errors "git init failed: %S"
        (call-process "git" nil nil nil "init"))))
  root)

(defun mp/workspace-bound-to-root (root)
  "Name of the existing workspace whose project is ROOT, or nil."
  (let ((root (file-name-as-directory (expand-file-name root))))
    (seq-find
     (lambda (name)
       (when-let* ((r (mp/workspace--project-root name)))
         (equal (file-name-as-directory (expand-file-name r)) root)))
     (persp-names))))

(defun mp/fresh-workspace-name-for-root (root)
  "A perspective name for ROOT: its basename, disambiguated if already taken."
  (let* ((base (file-name-nondirectory (directory-file-name root)))
         (name base) (n 2))
    (while (member name (persp-names))
      (setq name (format "%s<%d>" base n))
      (cl-incf n))
    name))

(defun mp/open-file-in-project-workspace (file &optional line col)
  "Visit FILE in the workspace bound to its project, at LINE:COL.
Ensures the project is a git repo and a known Projectile project, switches
to (creating if needed) the perspective bound to that project, records the
binding, then opens FILE.  Entry point for the Godot editor via
bin/godot-emacsclient."
  (let* ((file (expand-file-name file))
         (root (mp/project-root-for-file file)))
    (mp/ensure-git-repo root)
    (when (fboundp 'projectile-add-known-project)
      (projectile-add-known-project root))
    (when (bound-and-true-p persp-mode)
      (let ((ws (or (mp/workspace-bound-to-root root)
                    (mp/fresh-workspace-name-for-root root))))
        (persp-switch ws)
        (puthash ws root mp/workspace-project-roots)))
    (setq default-directory root)
    (find-file file)
    (when (and (integerp line) (> line 0))
      (goto-char (point-min))
      (forward-line (1- line))
      (when (and (integerp col) (> col 0))
        (move-to-column (1- col))))
    (when (fboundp 'select-frame-set-input-focus)
      (select-frame-set-input-focus (selected-frame)))
    (current-buffer)))

;;; ---------------------------------------------------------------------------
;;; dape (debug adapter client; ships a `godot' config out of the box)

(use-package dape
  :defer t
  :init
  ;; Info + REPL windows on the right, source on the left.
  (setq dape-buffer-window-arrangement 'right)
  :config
  ;; Persist breakpoints across Emacs sessions (guarded: no-ops when no file).
  (setq dape-default-breakpoints-file
        (expand-file-name "dape-breakpoints" mp/var-dir))
  (add-hook 'kill-emacs-hook #'dape-breakpoint-save)
  (dape-breakpoint-load))

;;; ---------------------------------------------------------------------------
;;; Twine / Twee (SugarCube)
;; Authoring Twine 2 interactive fiction as Tweego .twee source, compiled to
;; a single HTML file. The system-wide `tweego' binary ships sugarcube-2 as
;; its default story format. There is no SugarCube major mode on MELPA, so
;; this is a small self-contained twee-mode plus tweego build/watch commands.

(defvar twee-mode-syntax-table
  (let ((table (make-syntax-table)))
    ;; C-style /* ... */ block comments. SugarCube also has /% %/ and
    ;; <!-- -->, but only the C-style pair maps cleanly onto a syntax table.
    (modify-syntax-entry ?/ ". 14" table)
    (modify-syntax-entry ?* ". 23" table)
    (modify-syntax-entry ?$ "_" table)
    (modify-syntax-entry ?_ "_" table)
    table)
  "Syntax table for `twee-mode'.")

(defvar twee-font-lock-keywords
  `(;; Passage headers: ":: Name [tags] {position}".
    ("^\\(::\\)[ \t]*\\([^[{\n]*\\)\\(\\[[^]\n]*\\]\\)?[ \t]*\\({[^}\n]*}\\)?"
     (1 font-lock-comment-delimiter-face)
     (2 font-lock-function-name-face)
     (3 font-lock-type-face nil t)
     (4 font-lock-preprocessor-face nil t))
    ;; SugarCube macros: <<macro ...>> and <</macro>>.
    ("\\(<<\\)\\(/?\\)\\([A-Za-z_][A-Za-z0-9_-]*\\)"
     (1 font-lock-keyword-face)
     (3 font-lock-keyword-face))
    ("\\(>>\\)" (1 font-lock-keyword-face))
    ;; Story ($) and temporary (_) variables.
    ("\\(?:^\\|[^A-Za-z0-9_]\\)\\([$_][A-Za-z][A-Za-z0-9_.]*\\)"
     (1 font-lock-variable-name-face))
    ;; Links: [[target]], [[text|target]], [[text->target]], [[target<-text]].
    ("\\[\\[[^]\n]*\\]\\]" . font-lock-constant-face))
  "Font-lock keywords for `twee-mode'.")

(define-derived-mode twee-mode prog-mode "Twee"
  "Major mode for editing Twee 3 / SugarCube interactive-fiction source."
  :syntax-table twee-mode-syntax-table
  (setq-local comment-start "/* ")
  (setq-local comment-end " */")
  (setq-local font-lock-defaults '(twee-font-lock-keywords)))

(dolist (ext '("\\.twee\\'" "\\.tw\\'" "\\.tw2\\'" "\\.twee2\\'"))
  (add-to-list 'auto-mode-alist (cons ext #'twee-mode)))

;; Tweego build commands. Build the whole project directory to one HTML file
;; named after the project root.

(defvar mp/tweego--last-output nil
  "Absolute path of the HTML file produced by the last `mp/tweego-build'.")

(defcustom mp/tweego-format "sugarcube-2"
  "Story-format ID passed to tweego's -f flag."
  :type 'string
  :group 'twee)

(defun mp/tweego--root ()
  "Best-guess project root for a Twee build."
  (or (and (fboundp 'projectile-project-root) (projectile-project-root))
      (when-let ((proj (project-current))) (project-root proj))
      default-directory))

(defun mp/tweego--output (root)
  "Absolute path of the HTML output for ROOT, named after the project."
  (expand-file-name
   (concat (file-name-nondirectory (directory-file-name root)) ".html")
   root))

(defun mp/tweego-build (&optional test)
  "Compile the current Twee project to HTML with tweego.
With prefix arg TEST, build in test mode (-t)."
  (interactive "P")
  (let* ((root (mp/tweego--root))
         (out  (mp/tweego--output root))
         (default-directory root))
    (setq mp/tweego--last-output out)
    (compile (format "tweego -f %s%s -o %s ."
                     (shell-quote-argument mp/tweego-format)
                     (if test " -t" "")
                     (shell-quote-argument (file-relative-name out root))))))

(defun mp/tweego-watch ()
  "Watch the current Twee project and rebuild the HTML on every change."
  (interactive)
  (let* ((root (mp/tweego--root))
         (out  (mp/tweego--output root))
         (default-directory root)
         (compilation-buffer-name-function (lambda (_mode) "*tweego-watch*")))
    (setq mp/tweego--last-output out)
    (compile (format "tweego -w -f %s -o %s ."
                     (shell-quote-argument mp/tweego-format)
                     (shell-quote-argument (file-relative-name out root))))))

(defun mp/tweego-open ()
  "Open the last-built HTML story in the default browser."
  (interactive)
  (let ((out (or mp/tweego--last-output
                 (mp/tweego--output (mp/tweego--root)))))
    (if (file-exists-p out)
        (browse-url-of-file out)
      (user-error "No build found at %s -- run a build first" out))))

(mp/localleader
  :keymaps 'twee-mode-map
  "b" #'mp/tweego-build
  "t" (lambda () (interactive) (mp/tweego-build t))
  "w" #'mp/tweego-watch
  "o" #'mp/tweego-open)

;;; ---------------------------------------------------------------------------
;;; Other languages (simple deferred installs)

(use-package markdown-mode
  :mode (("README\\.md\\'" . gfm-mode)
         ("\\.md\\'" . markdown-mode)
         ("\\.markdown\\'" . markdown-mode)))

;; web-mode for template-heavy formats. .tsx is deliberately NOT here:
;; tsx-ts-mode (via treesit-auto in mp-treesit) handles it.
(use-package web-mode
  :mode ("\\.vue\\'" "\\.blade\\.php\\'" "\\.ejs\\'" "\\.hbs\\'"
         "\\.njk\\'" "\\.twig\\'"))

(use-package emmet-mode
  :hook (web-mode css-mode css-ts-mode html-mode html-ts-mode mhtml-mode))

(use-package php-mode
  :mode "\\.php\\'")

(use-package lua-mode
  :mode "\\.lua\\'")

(use-package graphql-mode
  :mode ("\\.graphql\\'" "\\.gql\\'"))

(use-package qml-mode
  :mode "\\.qml\\'")

(use-package csv-mode
  :mode ("\\.csv\\'" "\\.tsv\\'"))

;; Minimal here: the hledger custom package (loaded in mp-tools) does the
;; real configuration.
(use-package ledger-mode
  :mode ("\\.journal\\'" "\\.hledger\\'" "\\.ledger\\'"))

(use-package restclient
  :mode ("\\.http\\'" . restclient-mode))

(use-package renpy-mode
  :ensure (:host github :repo "Reagankm/renpy-mode")
  :mode "\\.rpy\\'")

;; Go: built-in go-ts-mode (treesit-auto maps it in mp-treesit); Go uses tabs.
(use-package go-ts-mode
  :ensure nil
  :defer t
  :config
  (setq go-ts-mode-indent-offset 4)
  (add-hook 'go-ts-mode-hook
            (lambda ()
              (setq-local tab-width 4
                          indent-tabs-mode t))))

;; json/yaml/sh/css/js/ts: built-in tree-sitter modes via treesit-auto
;; (configured in mp-treesit) -- nothing needed here.

(provide 'mp-langs)
;;; mp-langs.el ends here
