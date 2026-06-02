;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!

(require 'acp)
(require 'agent-shell)

(setq user-full-name "Mahdi Pourismaiel"
      user-mail-address "mpourismaiel@gmail.com")

;; Some functionality uses this to identify you, e.g. GPG configuration, email
;; clients, file templates and snippets. It is optional.
;; (setq user-full-name "John Doe"
;;       user-mail-address "john@doe.com")

;; Doom exposes five (optional) variables for controlling fonts in Doom:
;;
;; - `doom-font' -- the primary font to use
;; - `doom-variable-pitch-font' -- a non-monospace font (where applicable)
;; - `doom-big-font' -- used for `doom-big-font-mode'; use this for
;;   presentations or streaming.
;; - `doom-symbol-font' -- for symbols
;; - `doom-serif-font' -- for the `fixed-pitch-serif' face
;;
;; See 'C-h v doom-font' for documentation and more examples of what they
;; accept. For example:
;;
;;(setq doom-font (font-spec :family "Fira Code" :size 12 :weight 'semi-light)
;;      doom-variable-pitch-font (font-spec :family "Fira Sans" :size 13))
;;
;; If you or Emacs can't find your font, use 'M-x describe-font' to look them
;; up, `M-x eval-region' to execute elisp code, and 'M-x doom/reload-font' to
;; refresh your font settings. If Emacs still can't find your font, it likely
;; wasn't installed correctly. Font issues are rarely Doom issues!

;; There are two ways to load a theme. Both assume the theme is installed and
;; available. You can either set `doom-theme' or manually load a theme with the
;; `load-theme' function. This is the default:
(setq doom-theme 'doom-one)
(setq doom-font (font-spec :family "CaskaydiaCove Nerd Font Mono" :size 16))
(setq line-spacing 0.6)

;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type t)

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/org/")


;; Whenever you reconfigure a package, make sure to wrap your config in an
;; `with-eval-after-load' block, otherwise Doom's defaults may override your
;; settings. E.g.
;;
;;   (with-eval-after-load 'PACKAGE
;;     (setq x y))
;;
;; The exceptions to this rule:
;;
;;   - Setting file/directory variables (like `org-directory')
;;   - Setting variables which explicitly tell you to set them before their
;;     package is loaded (see 'C-h v VARIABLE' to look them up).
;;   - Setting doom variables (which start with 'doom-' or '+').
;;
;; Here are some additional functions/macros that will help you configure Doom.
;;
;; - `load!' for loading external *.el files relative to this one
;; - `add-load-path!' for adding directories to the `load-path', relative to
;;   this file. Emacs searches the `load-path' when you load packages with
;;   `require' or `use-package'.
;; - `map!' for binding new keys
;;
;; To get information about any of these functions/macros, move the cursor over
;; the highlighted symbol at press 'K' (non-evil users must press 'C-c c k').
;; This will open documentation for it, including demos of how they are used.
;; Alternatively, use `C-h o' to look up a symbol (functions, variables, faces,
;; etc).
;;
;; You can also try 'gd' (or 'C-c c d') to jump to their definition and see how
;; they are implemented.

;; Send files to trash instead of fully deleting
(setq delete-by-moving-to-trash t)
;; Save automatically
(setq auto-save-default t)

;; Speed of which-key popup
(setq which-key-idle-delay 0.2)

;; Never let Doom infer or create a Pipenv project at a monorepo root.
;; Only an already-existing ancestor Pipfile counts as a valid Pipenv root.
(defun mp/pipenv-project-p (&optional dir)
  (when-let ((root (locate-dominating-file (or dir default-directory) "Pipfile")))
    (expand-file-name root)))

(defun mp/pipenv-allowed-p (&optional dir)
  (and (mp/pipenv-project-p dir) t))

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
  ;; Prefer language-specific roots inside monorepos over the repository root.
  ;; This keeps `server/` Python tooling anchored to its own Pipfile/pyproject
  ;; instead of falling back to the top-level `.git` directory.
  (add-hook 'project-find-functions
            (lambda (dir)
              (cond
               ;; Go projects
               ((locate-dominating-file dir "go.mod")
                (cons 'transient (locate-dominating-file dir "go.mod")))

               ;; Rust projects
               ((locate-dominating-file dir "Cargo.toml")
                (cons 'transient (locate-dominating-file dir "Cargo.toml")))

               ;; Node.js projects
               ((locate-dominating-file dir "package.json")
                (cons 'transient (locate-dominating-file dir "package.json")))

               ;; Python projects (multiple markers)
               ((or (locate-dominating-file dir "Pipfile")
                    (locate-dominating-file dir "pyproject.toml")
                    (locate-dominating-file dir "setup.py")
                    (locate-dominating-file dir "requirements.txt"))
                (cons 'transient (or (locate-dominating-file dir "Pipfile")
                                     (locate-dominating-file dir "pyproject.toml")
                                     (locate-dominating-file dir "setup.py")
                                     (locate-dominating-file dir "requirements.txt"))))

               ;; Generic git projects (fallback)
               ((locate-dominating-file dir ".git")
                (cons 'transient (locate-dominating-file dir ".git")))))))

(map! :leader
      :desc "Run nearest test" "t t" #'+eval/test
      :desc "Run all project tests" "t a" #'+eval/test-all)

(use-package! consult-dir
  :defer t
  :config
  (map! :leader
        :desc "Find file from directory" "." #'find-file
        :desc "Switch directory" "f d" #'consult-dir)
  (map! :map minibuffer-local-completion-map
        "C-x C-d" #'consult-dir
        "C-x C-j" #'consult-dir-jump-file))
