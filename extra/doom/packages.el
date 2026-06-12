;;; packages.el -*- lexical-binding: t; -*-

;; multi cursor
(package! evil-mc)
(package! org-modern)
(package! vertico-posframe)
(package! consult-dir)

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
(package! dimmer)

(package! clutch)
(package! pg)
(package! mysql)
