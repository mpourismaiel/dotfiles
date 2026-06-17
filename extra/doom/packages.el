;;; packages.el -*- lexical-binding: t; -*-

;; multi cursor
(package! evil-mc)
(package! breadcrumb)
(package! expand-region)
(package! org-modern)
(package! vertico-posframe)
(package! consult-dir)
(package! color-rg :recipe (:host github :repo "manateelazycat/color-rg"))

(package! acp)
(package! agent-shell)
(package! agent-shell-notifications
  :recipe (:host github :repo "zackattackz/agent-shell-notifications"))
(package! minuet)

(package! eldoc-box)
;; Keep `pipenv` disabled, but leave the declaration so Doom won't re-enable it
;; if package state changes during future experiments.
(package! pipenv :disable t)

(package! shell-maker)
(package! olivetti)
(package! spacious-padding)
(package! rainbow-delimiters)

(package! clutch)
(package! pg)
(package! mysql)
