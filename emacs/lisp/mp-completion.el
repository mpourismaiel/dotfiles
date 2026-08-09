;;; mp-completion.el --- Completion stack -*- lexical-binding: t; -*-

;;; Minibuffer: Vertico

(use-package vertico
  :hook (elpaca-after-init . vertico-mode)
  :config
  ;; Fill the 18-line posframe (prompt + 17 candidates); fewer leaves a dead
  ;; blank band at the bottom of the popup.
  (setq vertico-cycle t
        vertico-count 17)
  ;; vertico-repeat: remember past minibuffer sessions across restarts.
  (add-hook 'minibuffer-setup-hook #'vertico-repeat-save)
  (add-to-list 'savehist-additional-variables 'vertico-repeat-history))

;;; Annotations + icons

(use-package marginalia
  :hook (elpaca-after-init . marginalia-mode))

(use-package nerd-icons)

(use-package nerd-icons-completion
  :after marginalia
  :config
  (nerd-icons-completion-mode 1)
  (add-hook 'marginalia-mode-hook #'nerd-icons-completion-marginalia-setup))

;;; Consult

(use-package consult
  :config
  (setq xref-show-xrefs-function #'consult-xref
        xref-show-definitions-function #'consult-xref
        consult-narrow-key "<")
  (setq register-preview-function #'consult-register-window))

;;; Embark

(use-package embark)

(use-package embark-consult
  :after (embark consult)
  :hook (embark-collect-mode . consult-preview-at-point-mode))

;;; wgrep (editable grep buffers)

(use-package wgrep
  :defer t)

;;; Completion styles: Orderless as the matcher

(use-package orderless
  :config
  ;; Make every component match as a fuzzy subsequence in addition to the
  ;; literal/regexp styles. This is the "VSCode fuzzy" half.
  (setq orderless-matching-styles
        '(orderless-literal orderless-regexp orderless-flex))

  (setq completion-styles '(orderless basic)
        completion-category-defaults nil
        completion-category-overrides
        '((file (styles orderless partial-completion)))))

;;; Prescient as the sorter

(use-package prescient
  :config
  (setq prescient-save-file (expand-file-name "prescient-save.el" mp/var-dir)
        prescient-sort-full-matches-first t)
  (prescient-persist-mode 1))

(use-package corfu-prescient
  :after corfu
  :config
  (setq corfu-prescient-enable-filtering nil   ; keep orderless for filtering
        corfu-prescient-enable-sorting t        ; let prescient sort
        corfu-prescient-override-sorting nil)
  (corfu-prescient-mode 1))

(use-package vertico-prescient
  :after vertico
  :config
  (setq vertico-prescient-enable-filtering nil
        vertico-prescient-enable-sorting t
        vertico-prescient-override-sorting nil)
  (vertico-prescient-mode 1))

;;; In-buffer completion: Corfu

(use-package corfu
  :hook (elpaca-after-init . global-corfu-mode)
  :config
  (setq corfu-auto t
        corfu-preview-current nil
        corfu-preselect 'prompt
        corfu-cycle t
        corfu-on-exact-match nil
        corfu-auto-delay 0.12
        corfu-auto-prefix 2)
  (setq corfu-popupinfo-delay '(0.35 . 0.2))
  (corfu-popupinfo-mode 1))

;; NOTE: lsp-bridge (mp-lsp.el) disables corfu-mode locally in its own
;; buffers; nothing here should re-enable it there, so keep corfu global-only
;; with no extra prog-mode hooks.

(use-package nerd-icons-corfu
  :after corfu
  :config
  (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter))

;;; Cape: extra completion-at-point backends

(use-package cape
  :init
  ;; The cape functions are autoloaded, so referencing them here is safe.
  (add-hook 'completion-at-point-functions #'cape-dabbrev)
  (add-hook 'completion-at-point-functions #'cape-file))

;;; Minibuffer posframe

(use-package vertico-posframe
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

(provide 'mp-completion)
;;; mp-completion.el ends here
