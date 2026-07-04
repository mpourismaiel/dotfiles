;;; packages.el -*- lexical-binding: t; -*-

;; multi cursor
(package! evil-mc)
;; code position breadcrump
(package! breadcrumb)
;; expand selection
(package! expand-region)
;; syntax-aware Evil text objects: vif/vac/viv (function/class/variable)
(package! evil-textobj-tree-sitter)
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
(package! copilot
  :recipe (:host github :repo "copilot-emacs/copilot.el" :files ("*.el")))

(package! eldoc-box)
;; Keep `pipenv` disabled, but leave the declaration so Doom won't re-enable it
;; if package state changes during future experiments.
(package! pipenv :disable t)
(package! renpy-mode :recipe (:host github :repo "Reagankm/renpy-mode"))

(package! lsp-bridge
  :recipe (:host github :repo "manateelazycat/lsp-bridge"
           :files (:defaults "*.py" "acm" "core" "langserver" "multiserver" "resources")
           :build (:not compile)))

(package! shell-maker)
(package! olivetti)
(package! spacious-padding)
(package! rainbow-delimiters)

(package! clutch)
(package! pg)
(package! mysql)
