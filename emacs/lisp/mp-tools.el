;;; mp-tools.el --- Magit, terminal, and tool integrations -*- lexical-binding: t; -*-

;;; Magit

;; Emacs 30 ships transient 0.7.x built-in, but magit requires a much newer
;; release. Declare transient explicitly (queued BEFORE magit) so elpaca
;; installs the current version instead of trusting the built-in — otherwise
;; magit fails to build with "Outdated dependency: transient".
(use-package transient :defer t)

;; Refine diff hunks to show the exact changed characters inside a line
;; instead of only marking the entire line as added or removed. That also
;; makes indentation-only edits much easier to see.
(use-package magit
  :defer t
  :config
  ;; Open magit-status in the current window (Doom behavior), keeping
  ;; diffs/logs from a status buffer in their usual side windows.
  (setq magit-display-buffer-function
        #'magit-display-buffer-same-window-except-diff-v1)
  (setq magit-diff-refine-hunk 'all
        magit-diff-fontify-hunk 'all
        ;; Keep whitespace visible inside refined hunks so indentation-only
        ;; changes are highlighted instead of being treated as irrelevant.
        magit-diff-refine-ignore-whitespace nil
        ;; Paint actual whitespace problems in both added and removed lines.
        magit-diff-paint-whitespace t
        magit-diff-paint-whitespace-lines 'both
        magit-diff-highlight-trailing t))

;; Commands are autoloaded; mp-keys binds them.
(use-package git-link
  :defer t)

(use-package git-timemachine
  :defer t)

(use-package link-hint
  :defer t)

;;; Quickrun (mp-keys eval helpers call it)

(use-package quickrun
  :defer t)

;;; Terminal (Ghostel)

;; Ghostel is the terminal emulator, replacing vterm. The recipe mirrors the
;; upstream MELPA recipe so the shell-integration/terminfo assets under etc/
;; are bundled.
(use-package ghostel
  :ensure (:host github :repo "dakra/ghostel"
           :files (:defaults "etc" "src" "vendor"
                   "build.zig" "build.zig.zon" "symbols.map"))
  :defer t
  :config
  (setq ghostel-project-buffer-scope 'both)
  (unless (member "C-`" ghostel-keymap-exceptions)
    (customize-set-variable 'ghostel-keymap-exceptions
                            (cons "C-`" ghostel-keymap-exceptions))))

;; evil-ghostel starts terminals in insert state and keeps Evil out of the
;; terminal's way.
(use-package evil-ghostel
  :ensure (:host github :repo "dakra/ghostel"
           :files ("extensions/evil-ghostel/evil-ghostel.el"))
  :after ghostel
  :hook (ghostel-mode . evil-ghostel-mode))

;;; Find in project (color-rg)

;; color-rg provides a ripgrep results buffer you can navigate, filter, and
;; edit in place to refactor matches across a project. Inside a result buffer:
;; j/k move between matches, h/l jump between files, e switches to edit mode
;; (C-c C-c applies, C-c C-v cancels), r replaces all matches, I toggles
;; whether ignore files are respected, and q quits.
(use-package color-rg
  :ensure (:host github :repo "manateelazycat/color-rg")
  :commands (color-rg-search-input
             color-rg-search-symbol
             color-rg-search-input-in-project
             color-rg-search-symbol-in-project
             color-rg-search-input-in-current-file
             color-rg-search-symbol-in-current-file)
  :init
  ;; `color-rg-mac-load-path-from-shell' only matters on macOS; PATH is
  ;; already managed (see mp-core), so the shell import is unneeded.
  (setq color-rg-mac-load-path-from-shell nil)
  :config
  ;; Respect .gitignore so project searches stay focused like an IDE.
  ;; Toggle per-search inside the results buffer with `I'.
  (setq color-rg-search-no-ignore-file nil)
  ;; `color-rg-mode' derives from `text-mode' and ships its own single-key view
  ;; bindings (j/k navigate, e edit, r replace, q quit). Hand the buffer to
  ;; Evil's Emacs state so those keys aren't shadowed.
  (with-eval-after-load 'evil
    (evil-set-initial-state 'color-rg-mode 'emacs)))

;;; Editing helpers

(use-package expand-region
  :commands (er/expand-region er/contract-region))

;;; Project environments

(use-package envrc
  :hook (elpaca-after-init . envrc-global-mode))

(use-package editorconfig
  :hook (elpaca-after-init . editorconfig-mode))

;;; Docker

(use-package docker
  :defer t)

;;; Tramp

(use-package tramp
  :ensure nil
  :defer t
  :config
  (setq tramp-default-method "ssh"))

;;; Database (Clutch)

(use-package clutch
  :ensure (:host github :repo "LuciusChen/clutch")
  :defer t
  :config
  (setq clutch-connect-timeout-seconds 10
        clutch-read-idle-timeout-seconds 30
        clutch-query-timeout-seconds 20
        clutch-jdbc-rpc-timeout-seconds 15))

;; Libraries clutch uses for PostgreSQL/MySQL connections.
(use-package pg
  :ensure (:host github :repo "emarsden/pg-el")
  :defer t)

(use-package mysql
  :ensure (:host github :repo "LuciusChen/mysql.el")
  :defer t)

;;; Dirvish

(use-package dirvish
  ;; `dirvish-override-dired-mode' would normally live in :init, but elpaca
  ;; defers :init too — run it once startup settles instead.
  :hook (elpaca-after-init . dirvish-override-dired-mode)
  :config
  (dirvish-override-dired-mode)
  (setq dirvish-cache-dir (expand-file-name "dirvish/" mp/var-dir)
        dirvish-attributes '(vc-state subtree-state nerd-icons collapse file-size)
        ;; Don't keep the session alive in the background: one `q' tears the
        ;; whole dirvish down (kills its dired + preview buffers) and restores
        ;; the window layout you came from, like Doom.
        dirvish-reuse-session nil
        dired-listing-switches
        "-l --almost-all --human-readable --group-directories-first --no-group")
  ;; evil-collection's dired `q' (quit-window, one buffer at a time) shadows
  ;; dirvish's quit; rebind it to the real teardown.
  (with-eval-after-load 'evil
    (evil-define-key 'normal dirvish-mode-map "q" #'dirvish-quit)))

;;; Custom packages

(mp/require-package "custom-shortcuts")
(mp/require-package "project-scripts")
(mp/require-package "clutch-connections")
(mp/require-package "teamwork")
(mp/require-package "github-pr")
(mp/require-package "hledger")

(provide 'mp-tools)
