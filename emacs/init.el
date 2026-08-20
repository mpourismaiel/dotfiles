;;; init.el --- Vanilla Emacs config (ported from Doom) -*- lexical-binding: t; -*-

;;; Commentary:

;; Layout:
;;   lisp/mp-*.el      configuration modules, loaded in order below
;;   packages/<name>/  self-contained custom features (ported Doom packages)
;;   themes/           custom themes (dobri-c07)
;; Deployed to ~/.config/emacs-vanilla/ by deploy.sh; launch with
;;   emacs --init-directory=~/.config/emacs-vanilla

;;; Code:

;;; Directories

(defvar mp/emacs-dir (file-name-directory (or load-file-name buffer-file-name))
  "Root of this Emacs configuration.")
(defvar mp/lisp-dir (expand-file-name "lisp/" mp/emacs-dir)
  "Directory holding the mp-*.el config modules.")
(defvar mp/packages-dir (expand-file-name "packages/" mp/emacs-dir)
  "Directory holding self-contained custom packages.")
(defvar mp/var-dir (expand-file-name "var/" mp/emacs-dir)
  "Directory for state files (history, undo, workspaces, ...). Not synced.")

(make-directory mp/var-dir t)
(add-to-list 'load-path mp/lisp-dir)
(add-to-list 'custom-theme-load-path (expand-file-name "themes/" mp/emacs-dir))

;; Keep customize noise out of init.el.
(setq custom-file (expand-file-name "custom.el" mp/var-dir))
(when (file-exists-p custom-file)
  (load custom-file nil 'nomessage))

;;; Elpaca bootstrap (official installer, v0.12)

(defvar elpaca-installer-version 0.12)
(defvar elpaca-directory (expand-file-name "elpaca/" user-emacs-directory))
(defvar elpaca-builds-directory (expand-file-name "builds/" elpaca-directory))
(defvar elpaca-sources-directory (expand-file-name "sources/" elpaca-directory))
(defvar elpaca-order '(elpaca :repo "https://github.com/progfolio/elpaca.git"
                              :ref nil :depth 1 :inherit ignore
                              :files (:defaults "elpaca-test.el" (:exclude "extensions"))
                              :build (:not elpaca-activate)))
(let* ((repo  (expand-file-name "elpaca/" elpaca-sources-directory))
       (build (expand-file-name "elpaca/" elpaca-builds-directory))
       (order (cdr elpaca-order))
       (default-directory repo))
  (add-to-list 'load-path (if (file-exists-p build) build repo))
  (unless (file-exists-p repo)
    (make-directory repo t)
    (when (<= emacs-major-version 28) (require 'subr-x))
    (condition-case-unless-debug err
        (if-let* ((buffer (pop-to-buffer-same-window "*elpaca-bootstrap*"))
                  ((zerop (apply #'call-process
                                 `("git" nil ,buffer t "clone"
                                   ,@(when-let* ((depth (plist-get order :depth)))
                                       (list (format "--depth=%d" depth)
                                             "--no-single-branch"))
                                   ,(plist-get order :repo) ,repo))))
                  ((zerop (call-process "git" nil buffer t "checkout"
                                        (or (plist-get order :ref) "--"))))
                  (emacs (concat invocation-directory invocation-name))
                  ((zerop (call-process
                           emacs nil buffer nil "-Q" "-L" "." "--batch"
                           "--eval" "(byte-recompile-directory \".\" 0 'force)")))
                  ((require 'elpaca))
                  ((elpaca-generate-autoloads "elpaca" repo)))
            (progn (message "%s" (buffer-string)) (kill-buffer buffer))
          (error "%s" (with-current-buffer buffer (buffer-string))))
      ((error) (warn "%s" err) (delete-directory repo 'recursive))))
  (unless (require 'elpaca-autoloads nil t)
    (require 'elpaca)
    (elpaca-generate-autoloads "elpaca" repo)
    (let ((load-source-file-function nil)) (load "./elpaca-autoloads"))))
(add-hook 'after-init-hook #'elpaca-process-queues)
(elpaca `(,@elpaca-order))

;; Lockfile: written by __ignore__/scripts (see README) after a good sync,
;; consumed on fresh machines so package revisions are reproducible.
(defvar mp/lock-file (expand-file-name "lockfile/lock.eld" mp/emacs-dir))
(when (file-exists-p mp/lock-file)
  (setq elpaca-lock-file mp/lock-file))

;; Tolerate re-declaring a package that elpaca already pulled in as a
;; transitive dependency (e.g. markdown-mode via lsp-bridge, expand-region via
;; embrace). Before `after-init-time' is set — i.e. during normal/daemon
;; startup, though NOT during `-batch -l init.el' where it is already set —
;; `elpaca--enqueue' takes a conflict branch that `warn's and returns a string
;; instead of an elpaca struct, which crashes the use-package expansion and
;; aborts the rest of init. Force elpaca's own post-init branch (a harmless
;; re-enqueue) for those duplicate orders. Installed before any module loads.
(defun mp/elpaca--enqueue-tolerant-a (fn &rest args)
  "Around advice: neutralise elpaca's init-time re-declaration crash."
  (let ((after-init-time (or after-init-time t)))
    (apply fn args)))
;; elpaca is already loaded by the bootstrap above.
(advice-add 'elpaca--enqueue :around #'mp/elpaca--enqueue-tolerant-a)

;; use-package integration: every use-package call defers to elpaca via
;; `:ensure t'. Built-ins opt out with `:ensure nil'.
(elpaca elpaca-use-package
  (elpaca-use-package-mode)
  (setq use-package-always-ensure t))

;; Block until core packages are installed on first run, so the module loads
;; below can rely on them.
(elpaca-wait)

;;; Helper for custom packages (successor of Doom-era mp/require-package)

(defun mp/require-package (name)
  "Load custom package NAME from `mp/packages-dir'.
Guarded: a missing package logs a message instead of breaking startup."
  (let ((file (expand-file-name (format "%s/%s.el" name name) mp/packages-dir)))
    (if (file-exists-p file)
        (load file nil 'nomessage)
      (message "mp: package `%s' missing from %s" name mp/packages-dir))))

;;; Modules (order matters)

;; Load each module in isolation: a failure in one (a bad recipe, an elpaca
;; queue conflict, ...) must not abort the requires that follow it — otherwise
;; a single broken package silently takes out every later module. Errors are
;; collected and surfaced instead of aborting startup.
(defvar mp/module-load-errors nil
  "Alist of (MODULE . ERROR) for modules that failed to load.")

(dolist (module '(mp-core        ; defaults, paths, NVM, private data, helpful
                  mp-evil        ; evil + flotilla + evil-collection
                  mp-keys        ; general.el leader engine + global bindings
                  mp-completion  ; vertico/consult/embark/corfu/orderless
                  mp-ui          ; theme, modeline, popups, visual polish
                  mp-treesit     ; grammars, folding, text objects
                  mp-lsp         ; lsp-bridge, eglot, flycheck, apheleia
                  mp-workspaces  ; perspective + projectile + persistence + splash
                  mp-org         ; org
                  mp-langs       ; per-language setup (incl. python guards)
                  mp-tools       ; magit, ghostel, dape, color-rg, clutch, ...
                  mp-ai))        ; agent-shell + eca
  (condition-case err
      (require module)
    (error
     (push (cons module err) mp/module-load-errors)
     (message "mp: module `%s' failed to load: %S" module err))))

(when mp/module-load-errors
  (add-hook 'elpaca-after-init-hook
            (lambda ()
              (display-warning
               'mp (format "%d config module(s) failed to load: %s.  See *Messages*."
                           (length mp/module-load-errors)
                           (mapconcat (lambda (e) (symbol-name (car e)))
                                      mp/module-load-errors ", "))
               :error))))

;;; init.el ends here
