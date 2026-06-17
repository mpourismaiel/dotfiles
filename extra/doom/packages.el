;;; packages.el -*- lexical-binding: t; -*-

;; multi cursor
(package! evil-mc)
;; code position breadcrump
(package! breadcrumb)
;; expand selection
(package! expand-region)
;; org
(package! org-modern)
;; some minibuffer help
(package! vertico-posframe)
(package! consult-dir)
;; much better search and replace
(package! color-rg :recipe (:host github :repo "manateelazycat/color-rg"))
;; VSCode-like sorting for corfu/vertico (orderless still does the filtering)
(package! prescient)
(package! corfu-prescient)
(package! vertico-prescient)

(package! acp)
(package! agent-shell)
(package! agent-shell-notifications
  :recipe (:host github :repo "zackattackz/agent-shell-notifications"))
(package! minuet)

(package! eldoc-box)
;; Keep `pipenv` disabled, but leave the declaration so Doom won't re-enable it
;; if package state changes during future experiments.
(package! pipenv :disable t)
(package! renpy-mode :recipe (:host github :repo "Reagankm/renpy-mode"))

(package! shell-maker)
(package! olivetti)
(package! spacious-padding)
(package! rainbow-delimiters)

(package! clutch)
(package! pg)
(package! mysql)
