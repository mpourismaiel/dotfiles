;;; dobri-next-c07.el -*- lexical-binding: t; -*-

(deftheme dobri-c07 "Dobri Next C07 port for Emacs/Doom.")

(let ((bg        "#0b1015")
      (bg-alt    "#111820")
      (bg-dark   "#080b0f")
      (fg        "#97a7c8")
      (fg-alt    "#abb2bf")
      (comment   "#5C6370")
      (selection "#3d4148")
      (line      "#14344B")
      (red       "#FB467B")
      (orange    "#F78C6C")
      (yellow    "#FFCC00")
      (green     "#98c379")
      (cyan      "#56D6D6")
      (blue      "#61afef")
      (purple    "#CB6CFE"))

  (custom-theme-set-faces
   'dobri-c07

   `(default ((t (:background ,bg :foreground ,fg))))
   `(cursor ((t (:background ,cyan))))
   `(fringe ((t (:background ,bg :foreground ,comment))))
   `(region ((t (:background ,selection))))
   `(highlight ((t (:background ,line))))
   `(hl-line ((t (:background ,line))))
   `(line-number ((t (:background ,bg :foreground ,comment))))
   `(line-number-current-line ((t (:background ,line :foreground ,fg))))

   `(mode-line ((t (:background ,bg-alt :foreground ,fg))))
   `(mode-line-inactive ((t (:background ,bg-dark :foreground ,comment))))
   `(header-line ((t (:background ,bg-alt :foreground ,fg))))

   `(font-lock-comment-face ((t (:foreground ,comment :slant italic))))
   `(font-lock-doc-face ((t (:foreground ,comment :slant italic))))
   `(font-lock-string-face ((t (:foreground ,green))))
   `(font-lock-keyword-face ((t (:foreground ,purple))))
   `(font-lock-builtin-face ((t (:foreground ,cyan))))
   `(font-lock-function-name-face ((t (:foreground ,blue :weight bold))))
   `(font-lock-variable-name-face ((t (:foreground ,red))))
   `(font-lock-type-face ((t (:foreground ,yellow))))
   `(font-lock-constant-face ((t (:foreground ,orange))))
   `(font-lock-warning-face ((t (:foreground ,yellow :weight bold))))

   `(isearch ((t (:background ,orange :foreground ,bg))))
   `(lazy-highlight ((t (:background ,selection :foreground ,fg))))

   `(show-paren-match ((t (:background ,selection :foreground ,cyan :weight bold))))
   `(show-paren-mismatch ((t (:background ,red :foreground ,bg))))

   `(vertical-border ((t (:foreground ,bg-alt))))

   `(error ((t (:foreground ,red))))
   `(warning ((t (:foreground ,yellow))))
   `(success ((t (:foreground ,green))))

   ;; Tree-sitter faces, important in your Doom config.
   `(tree-sitter-hl-face:function ((t (:foreground ,blue))))
   `(tree-sitter-hl-face:method ((t (:foreground ,blue))))
   `(tree-sitter-hl-face:keyword ((t (:foreground ,purple :weight bold))))
   `(tree-sitter-hl-face:string ((t (:foreground ,green))))
   `(tree-sitter-hl-face:comment ((t (:foreground ,comment :slant italic))))
   `(tree-sitter-hl-face:type ((t (:foreground ,yellow))))
   `(tree-sitter-hl-face:constant ((t (:foreground ,orange))))
   `(tree-sitter-hl-face:variable ((t (:foreground ,red))))

   ;; Web / JSX / TSX
   `(web-mode-html-tag-face ((t (:foreground ,red))))
   `(web-mode-html-tag-bracket-face ((t (:foreground ,comment))))
   `(web-mode-html-attr-name-face ((t (:foreground ,orange))))
   `(web-mode-html-attr-value-face ((t (:foreground ,green))))

   ;; vertico
   `(minibuffer-prompt ((t (:foreground ,orange :weight bold))))
   `(vertico-current ((t (:background ,selection :weight bold))))
   `(vertico-posframe ((t (:background ,bg))))
   '(vertico-posframe-border ((t (:background "#3b4252"))))

   `(completions-highlight ((t (:background ,selection))))
   `(consult-preview-match ((t (:background ,selection :foreground ,fg))))

   `(org-block ((t (:background ,bg-alt :foreground ,fg))))
   `(org-block-begin-line ((t (:background ,bg-dark :foreground ,comment))))
   `(org-block-end-line ((t (:background ,bg-dark :foreground ,comment))))
   `(org-code ((t (:background ,bg-alt :foreground ,cyan))))
   `(org-verbatim ((t (:background ,bg-alt :foreground ,green))))
   `(org-quote ((t (:background ,bg-alt :foreground ,fg :slant italic))))

   ;; Doom modeline
   `(doom-modeline-bar ((t (:background ,cyan))))
   `(doom-modeline-buffer-file ((t (:foreground ,fg :weight bold))))
   `(doom-modeline-buffer-modified ((t (:foreground ,yellow))))))

(provide-theme 'dobri-c07)
