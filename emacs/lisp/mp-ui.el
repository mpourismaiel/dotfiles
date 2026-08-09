;;; mp-ui.el --- Theme, modeline, popups, visual polish -*- lexical-binding: t; -*-

;;; Theme

;; `doom-one' comes from the doom-themes package, so both themes load in
;; :config once the package is available. `dobri-c07' (plain `deftheme',
;; no doom-themes macros) layers on top; custom-theme-load-path already
;; includes emacs/themes/ (init.el).
(use-package doom-themes
  :demand t
  :config
  (setq doom-themes-enable-bold t
        doom-themes-enable-italic t)
  (load-theme 'doom-one t)
  (load-theme 'dobri-c07 t)
  (mp/hide-window-dividers))

;;; Fonts

;; Doom's :ui doom module ships solaire-mode: file buffers get the "bright"
;; background while popups/sidebars/minibuffer keep the darker one. The
;; dobri-c07 theme defines solaire faces, so without this layer the whole
;; two-tone look (incl. the completion posframe) reads as a theme mismatch.
(use-package solaire-mode
  :hook (elpaca-after-init . solaire-global-mode))

;; Doom's `(font-spec ... :size 16)' means 16 PIXELS (integer = px, float =
;; pt). Match it exactly; a point-based height renders visibly larger.
(set-face-attribute 'default nil
                    :font (font-spec :family "CaskaydiaCove Nerd Font Mono"
                                     :size 16))
(push '(font . "CaskaydiaCove Nerd Font Mono:pixelsize=16") default-frame-alist)

;;; Comfortable editing spacing

(defvar mp/editor-line-spacing 0.6
  "Preferred extra line spacing for editing buffers.")

(defvar mp/prog-line-spacing 0.9
  "Preferred extra line spacing for code buffers (taller than prose).")

(defun mp/apply-editor-line-spacing-h ()
  "Apply comfortable line spacing to editable buffers."
  (setq-local line-spacing mp/editor-line-spacing))

(defun mp/apply-prog-line-spacing-h ()
  "Apply a taller line spacing to code buffers."
  (setq-local line-spacing mp/prog-line-spacing))

(add-hook 'text-mode-hook #'mp/apply-editor-line-spacing-h)
(add-hook 'prog-mode-hook #'mp/apply-prog-line-spacing-h)
(add-hook 'conf-mode-hook #'mp/apply-editor-line-spacing-h)

;;; Line numbers

(setq display-line-numbers-type t)
(add-hook 'prog-mode-hook #'display-line-numbers-mode)
(add-hook 'text-mode-hook #'display-line-numbers-mode)
(add-hook 'conf-mode-hook #'display-line-numbers-mode)

;;; Whitespace and indentation

(defun mp/show-indent-style-h ()
  "Show tabs and spaces visibly in code-like buffers."
  (setq-local whitespace-style
              '(face tabs tab-mark spaces space-mark trailing))
  (setq-local whitespace-display-mappings
              '((tab-mark ?\t [?→ ?\t] [?\\ ?\t])
                (space-mark ?\  [?·] [?.])))
  (whitespace-mode +1))

(add-hook 'prog-mode-hook #'mp/show-indent-style-h)
(add-hook 'conf-mode-hook #'mp/show-indent-style-h)

;;; Invisible window dividers

;; Hide window dividers by painting them the background colour. Re-run on
;; every theme load so the colour tracks the active theme; applied once in
;; doom-themes :config for the themes loaded at startup.
(defun mp/hide-window-dividers (&rest _)
  "Paint window-divider faces the default background so they vanish."
  (dolist (face '(window-divider
                  window-divider-first-pixel
                  window-divider-last-pixel))
    (face-spec-reset-face face)
    (set-face-foreground face (face-attribute 'default :background))))
(add-hook 'enable-theme-functions #'mp/hide-window-dividers)

;;; Mode line

(use-package doom-modeline
  :hook (elpaca-after-init . doom-modeline-mode)
  :config (column-number-mode 1)
  :custom
  (doom-modeline-height 40)
  (doom-modeline-window-width-limit nil)

  (doom-modeline-buffer-file-name-style 'relative-from-project)

  (doom-modeline-icon t)
  (doom-modeline-major-mode-color-icon t)
  (doom-modeline-buffer-modification-icon t)
  (doom-modeline-buffer-state-icon t)

  (doom-modeline-indent-info t)
  (doom-modeline-env-enable-python nil)
  (doom-modeline-persp-name t))

;;; Popups

(use-package popper
  :hook ((elpaca-after-init . popper-mode)
         (elpaca-after-init . popper-echo-mode))
  :init
  (setq popper-reference-buffers
        '("\\*Flycheck errors\\*"
          "\\*xref\\*"
          "\\*Warnings\\*"
          "\\*Backtrace\\*"
          "\\*quickrun\\*")))

;; Doom-era popup-rule geometry, reproduced with display-buffer-alist.
(dolist (rule '(("\\*Flycheck errors\\*" 0.25 t)
                ("\\*xref\\*" 0.3 t)
                ("\\*Warnings\\*" 0.25 nil)
                ("\\*Backtrace\\*" 0.35 nil)))
  (add-to-list 'display-buffer-alist
               `(,(nth 0 rule)
                 (display-buffer-in-side-window)
                 (side . bottom)
                 (window-height . ,(nth 1 rule))
                 ,@(when (nth 2 rule)
                     '((body-function . select-window))))))

(defun mp/close-window-preserve-buffer ()
  "Close the selected window without killing or losing its buffer.
Popper popups are buried through popper so their state survives;
other windows are simply deleted. The buffer is never killed."
  (interactive)
  (cond
   ((and (fboundp 'popper-popup-p)
         (popper-popup-p (current-buffer)))
    (popper-toggle))
   ((window-parameter (selected-window) 'window-side)
    (delete-window))
   ((one-window-p)
    (message "Only one window; leaving it in place"))
   (t
    (delete-window))))

;;; Version-control gutter

(use-package diff-hl
  :hook ((elpaca-after-init . global-diff-hl-mode)
         (elpaca-after-init . diff-hl-flydiff-mode)
         (dired-mode . diff-hl-dired-mode)
         (magit-pre-refresh . diff-hl-magit-pre-refresh)
         (magit-post-refresh . diff-hl-magit-post-refresh)))

;;; TODO/FIXME highlighting

(use-package hl-todo
  :hook (elpaca-after-init . global-hl-todo-mode))

;;; Indent guides

(use-package indent-bars
  :hook (prog-mode . indent-bars-mode)
  :custom
  (indent-bars-treesit-support t))

;;; Ligatures

(use-package ligature
  :config
  ;; Standard Cascadia Code ligature set (per the ligature.el README).
  (ligature-set-ligatures
   'prog-mode
   '("|||>" "<|||" "<==>" "<!--" "####" "~~>" "***" "||=" "||>"
     ":::" "::=" "=:=" "===" "==>" "=!=" "=>>" "=<<" "=/=" "!=="
     "!!." ">=>" ">>=" ">>>" ">>-" ">->" "->>" "-->" "---" "-<<"
     "<~~" "<~>" "<*>" "<||" "<|>" "<$>" "<==" "<=>" "<=<" "<->"
     "<--" "<-<" "<<=" "<<-" "<<<" "<+>" "</>" "###" "#_(" "..<"
     "..." "+++" "/==" "///" "_|_" "www" "&&" "^=" "~~" "~@" "~="
     "~>" "~-" "**" "*>" "*/" "||" "|}" "|]" "|=" "|>" "|-" "{|"
     "[|" "]#" "::" ":=" ":>" ":<" "$>" "==" "=>" "!=" "!!" ">:"
     ">=" ">>" ">-" "-~" "-|" "->" "--" "-<" "<~" "<*" "<|" "<:"
     "<$" "<=" "<>" "<-" "<<" "<+" "</" "#{" "#[" "#:" "#=" "#!"
     "##" "#(" "#?" "#_" "%%" ".=" ".-" ".." ".?" "+>" "++" "?:"
     "?=" "?." "??" ";;" "/*" "/=" "/>" "//" "__" "(*" "*)" "\\\\"
     "://"))
  (global-ligature-mode t))

;;; Smooth pixel scrolling

(use-package ultra-scroll
  :ensure (:host github :repo "jdtsmith/ultra-scroll")
  :init
  (setq scroll-conservatively 101
        scroll-margin 0)
  :config
  (ultra-scroll-mode 1))

;;; Emoji

;; Global emojify is heavy; scope it to prose buffers.
(use-package emojify
  :hook ((text-mode . emojify-mode)
         (org-mode . emojify-mode))
  :init
  ;; Keep the downloaded emoji assets under var/ — the deploy rsync --delete
  ;; would wipe them from the config root and re-trigger the download prompt
  ;; on every deploy. Download without asking.
  (setq emojify-emojis-dir (expand-file-name "emojis/" mp/var-dir)
        emojify-download-emojis-p t))

;;; Rainbow delimiters

(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

;;; Spacious padding

(use-package spacious-padding
  :custom
  (spacious-padding-widths
   '( :internal-border-width 8
      :header-line-width 0
      :mode-line-width 0
      :tab-width 4
      :right-divider-width 30
      :scroll-bar-width 8))
  :config
  (spacious-padding-mode 1))

;;; Olivetti

;; Setting only; the org-mode hooks that enable it live in mp-org.
(use-package olivetti
  :defer t
  :custom
  (olivetti-body-width 160))

;;; Trailing whitespace (only on touched lines)

(use-package ws-butler
  :hook ((prog-mode . ws-butler-mode)
         (text-mode . ws-butler-mode)
         (conf-mode . ws-butler-mode)))

;;; Indent-style guessing

(use-package dtrt-indent
  :hook (elpaca-after-init . dtrt-indent-global-mode))

;;; Adaptive wrap for visual-line buffers

(use-package adaptive-wrap
  :hook (visual-line-mode . adaptive-wrap-prefix-mode))

;;; Window management helpers

(winner-mode 1)

(use-package ace-window
  :defer t)

;;; Pairs

(use-package smartparens
  :hook (elpaca-after-init . smartparens-global-mode)
  :config
  (require 'smartparens-config)
  (show-paren-mode 1))

;;; Header line (custom svg-header package)

(mp/require-package "svg-header")

(provide 'mp-ui)
