;;; dobri-next-c07.el -*- lexical-binding: t; -*-
;;
;; Dobri Next "C07" port for Emacs / Doom.
;;
;; Tuned to match the dobri-next web design language (see extra/doom/preview.html):
;; a calm, neutral-dark Material Ocean surface with the Palenight accent palette
;; (#82aaff / #c792ea / #89ddff / #c3e88d / #ffcb6b).  Compared to the first port
;; the base background is lifted out of near-black, the foreground is brighter for
;; readability, and syntax highlighting is fleshed out so code actually "pops".
;;
;; The whole palette lives in the `let*' below; tweak a value there and every face
;; that references it follows.  No external dependency (autothemer et al.) so a
;; missed `doom sync' can never leave you without a theme.

(deftheme dobri-c07 "Dobri Next C07 — Material Ocean surface, Palenight accents.")

(let* (;; --- Surfaces --------------------------------------------------------
       (bg        "#0f1118")   ; main editing surface (design --bg #101114)
       (bg-alt    "#171a24")   ; panels, mode-line, org blocks (design --panel)
       (bg-dark   "#0a0c11")   ; inactive mode-line, deep shadow, posframe edge
       (bg-light  "#212737")   ; popups / completion / lighter surface (--panel-2)
       (bg-region "#2b3346")   ; active region selection
       (bg-hl     "#172033")   ; current-line highlight (subtle blue lift)
       (bg-sel    "#233148")   ; stronger highlight / lazy match
       (border    "#2a3142")   ; borders, dividers, boxes (design --border)

       ;; --- Text ------------------------------------------------------------
       (fg        "#c5cdde")   ; primary text (brighter than stock Material)
       (fg-alt    "#9aa3ba")   ; secondary text / muted (design --muted)
       (fg-dim    "#6b7488")   ; faint text, punctuation (design --faint)
       (comment   "#69718a")   ; comments — readable muted blue-grey

       ;; --- Accents (Palenight) --------------------------------------------
       (red       "#ff6e7e")   ; errors, deletions
       (coral     "#f78c9c")   ; variables, properties
       (orange    "#f78c6c")   ; constants, numbers, escapes
       (yellow    "#ffcb6b")   ; types / classes, warnings, html tags (--essential)
       (green     "#c3e88d")   ; strings, additions, success (--accent-2)
       (cyan      "#89ddff")   ; builtins, operators, accents (--accent)
       (blue      "#82aaff")   ; functions, links
       (purple    "#c792ea")   ; keywords
       (teal      "#56d6d6")   ; cursor, modeline bar, special accents

       (black     "#0a0c11"))

  (custom-theme-set-faces
   'dobri-c07

   ;; ---------------------------------------------------------------- base ---
   `(default            ((t (:background ,bg :foreground ,fg))))
   `(cursor             ((t (:background ,teal))))
   `(fringe             ((t (:background ,bg :foreground ,fg-dim))))
   `(region             ((t (:background ,bg-region :extend t))))
   `(secondary-selection ((t (:background ,bg-sel :extend t))))
   `(highlight          ((t (:background ,bg-sel :foreground ,fg))))
   `(hl-line            ((t (:background ,bg-hl :extend t))))
   `(shadow             ((t (:foreground ,fg-dim))))
   `(link               ((t (:foreground ,cyan :underline t))))
   `(link-visited       ((t (:foreground ,purple :underline t))))
   `(match              ((t (:background ,bg-sel :foreground ,fg))))
   `(trailing-whitespace ((t (:background ,red))))
   `(escape-glyph       ((t (:foreground ,orange))))
   `(homoglyph          ((t (:foreground ,orange))))
   `(tooltip            ((t (:background ,bg-light :foreground ,fg))))
   `(vertical-border    ((t (:foreground ,border))))
   `(window-divider     ((t (:foreground ,border))))
   `(window-divider-first-pixel ((t (:foreground ,border))))
   `(window-divider-last-pixel  ((t (:foreground ,border))))
   `(fill-column-indicator ((t (:foreground ,bg-alt))))
   `(error              ((t (:foreground ,red :weight bold))))
   `(warning            ((t (:foreground ,yellow :weight bold))))
   `(success            ((t (:foreground ,green :weight bold))))

   ;; -------------------------------------------------------- line numbers ---
   `(line-number              ((t (:background ,bg :foreground ,fg-dim))))
   `(line-number-current-line ((t (:background ,bg-hl :foreground ,fg :weight bold))))
   `(line-number-major-tick   ((t (:background ,bg :foreground ,fg-alt))))
   `(line-number-minor-tick   ((t (:background ,bg :foreground ,fg-dim))))

   ;; ------------------------------------------------------- mode/header ----
   `(mode-line          ((t (:background ,bg-alt :foreground ,fg
                             :box (:line-width 1 :color ,bg-alt)))))
   `(mode-line-active   ((t (:background ,bg-alt :foreground ,fg
                             :box (:line-width 1 :color ,bg-alt)))))
   `(mode-line-inactive ((t (:background ,bg-dark :foreground ,fg-dim
                             :box (:line-width 1 :color ,bg-dark)))))
   `(mode-line-emphasis ((t (:foreground ,cyan :weight bold))))
   `(mode-line-highlight ((t (:foreground ,teal))))
   `(mode-line-buffer-id ((t (:foreground ,fg :weight bold))))
   `(header-line        ((t (:background ,bg-alt :foreground ,fg))))

   ;; --------------------------------------------------------- font-lock ----
   `(font-lock-comment-face           ((t (:foreground ,comment :slant italic))))
   `(font-lock-comment-delimiter-face ((t (:foreground ,comment :slant italic))))
   `(font-lock-doc-face               ((t (:foreground ,comment :slant italic))))
   `(font-lock-doc-markup-face        ((t (:foreground ,cyan))))
   `(font-lock-string-face            ((t (:foreground ,green))))
   `(font-lock-keyword-face           ((t (:foreground ,purple :weight bold))))
   `(font-lock-builtin-face           ((t (:foreground ,cyan))))
   `(font-lock-function-name-face     ((t (:foreground ,blue :weight bold))))
   `(font-lock-function-call-face     ((t (:foreground ,blue))))
   `(font-lock-variable-name-face     ((t (:foreground ,coral))))
   `(font-lock-variable-use-face      ((t (:foreground ,fg))))
   `(font-lock-type-face              ((t (:foreground ,yellow :weight bold))))
   `(font-lock-constant-face          ((t (:foreground ,orange))))
   `(font-lock-number-face            ((t (:foreground ,orange))))
   `(font-lock-operator-face          ((t (:foreground ,cyan))))
   `(font-lock-property-name-face     ((t (:foreground ,coral))))
   `(font-lock-property-use-face      ((t (:foreground ,cyan))))
   `(font-lock-punctuation-face       ((t (:foreground ,fg-dim))))
   `(font-lock-bracket-face           ((t (:foreground ,fg-alt))))
   `(font-lock-delimiter-face         ((t (:foreground ,fg-alt))))
   `(font-lock-preprocessor-face      ((t (:foreground ,purple))))
   `(font-lock-negation-char-face     ((t (:foreground ,cyan))))
   `(font-lock-escape-face            ((t (:foreground ,orange))))
   `(font-lock-regexp-grouping-construct ((t (:foreground ,cyan :weight bold))))
   `(font-lock-regexp-grouping-backslash ((t (:foreground ,orange))))
   `(font-lock-warning-face           ((t (:foreground ,yellow :weight bold))))

   ;; -------------------------------------------- tree-sitter (legacy pkg) ---
   `(tree-sitter-hl-face:function          ((t (:foreground ,blue :weight bold))))
   `(tree-sitter-hl-face:function.call     ((t (:foreground ,blue))))
   `(tree-sitter-hl-face:function.builtin  ((t (:foreground ,cyan))))
   `(tree-sitter-hl-face:function.method   ((t (:foreground ,blue))))
   `(tree-sitter-hl-face:method            ((t (:foreground ,blue))))
   `(tree-sitter-hl-face:method.call       ((t (:foreground ,blue))))
   `(tree-sitter-hl-face:keyword           ((t (:foreground ,purple :weight bold))))
   `(tree-sitter-hl-face:string            ((t (:foreground ,green))))
   `(tree-sitter-hl-face:string.special    ((t (:foreground ,orange))))
   `(tree-sitter-hl-face:escape            ((t (:foreground ,orange))))
   `(tree-sitter-hl-face:comment           ((t (:foreground ,comment :slant italic))))
   `(tree-sitter-hl-face:type              ((t (:foreground ,yellow :weight bold))))
   `(tree-sitter-hl-face:type.builtin      ((t (:foreground ,yellow))))
   `(tree-sitter-hl-face:type.parameter    ((t (:foreground ,coral :slant italic))))
   `(tree-sitter-hl-face:constant          ((t (:foreground ,orange))))
   `(tree-sitter-hl-face:constant.builtin  ((t (:foreground ,orange))))
   `(tree-sitter-hl-face:number            ((t (:foreground ,orange))))
   `(tree-sitter-hl-face:constructor       ((t (:foreground ,yellow))))
   `(tree-sitter-hl-face:variable          ((t (:foreground ,fg))))
   `(tree-sitter-hl-face:variable.builtin  ((t (:foreground ,red))))
   `(tree-sitter-hl-face:variable.parameter ((t (:foreground ,coral :slant italic))))
   `(tree-sitter-hl-face:property          ((t (:foreground ,coral))))
   `(tree-sitter-hl-face:property.definition ((t (:foreground ,coral))))
   `(tree-sitter-hl-face:label             ((t (:foreground ,cyan))))
   `(tree-sitter-hl-face:operator          ((t (:foreground ,cyan))))
   `(tree-sitter-hl-face:punctuation       ((t (:foreground ,fg-dim))))
   `(tree-sitter-hl-face:punctuation.bracket ((t (:foreground ,fg-alt))))
   `(tree-sitter-hl-face:punctuation.delimiter ((t (:foreground ,fg-alt))))
   `(tree-sitter-hl-face:punctuation.special ((t (:foreground ,cyan))))
   `(tree-sitter-hl-face:tag               ((t (:foreground ,yellow :weight bold))))
   `(tree-sitter-hl-face:attribute         ((t (:foreground ,blue))))
   `(tree-sitter-hl-face:embedded          ((t (:foreground ,fg))))

   ;; ------------------------------------------------------- search / pair ---
   `(isearch            ((t (:background ,yellow :foreground ,black :weight bold))))
   `(isearch-fail       ((t (:background ,red :foreground ,black))))
   `(lazy-highlight     ((t (:background ,bg-sel :foreground ,fg))))
   `(evil-ex-search     ((t (:background ,yellow :foreground ,black :weight bold))))
   `(evil-ex-lazy-highlight ((t (:background ,bg-sel :foreground ,fg))))
   `(show-paren-match   ((t (:background ,bg-sel :foreground ,teal :weight bold))))
   `(show-paren-mismatch ((t (:background ,red :foreground ,black :weight bold))))
   `(minibuffer-prompt  ((t (:foreground ,cyan :weight bold))))

   ;; ----------------------------------------------- rainbow-delimiters -----
   `(rainbow-delimiters-depth-1-face ((t (:foreground ,blue))))
   `(rainbow-delimiters-depth-2-face ((t (:foreground ,purple))))
   `(rainbow-delimiters-depth-3-face ((t (:foreground ,green))))
   `(rainbow-delimiters-depth-4-face ((t (:foreground ,cyan))))
   `(rainbow-delimiters-depth-5-face ((t (:foreground ,yellow))))
   `(rainbow-delimiters-depth-6-face ((t (:foreground ,orange))))
   `(rainbow-delimiters-depth-7-face ((t (:foreground ,coral))))
   `(rainbow-delimiters-depth-8-face ((t (:foreground ,teal))))
   `(rainbow-delimiters-depth-9-face ((t (:foreground ,fg-alt))))
   `(rainbow-delimiters-unmatched-face ((t (:foreground ,red :weight bold))))
   `(rainbow-delimiters-mismatched-face ((t (:foreground ,red :weight bold))))

   ;; --------------------------------------------- solaire (doom surfaces) ---
   `(solaire-default-face          ((t (:background ,bg-alt :foreground ,fg))))
   `(solaire-hl-line-face          ((t (:background ,bg-hl :extend t))))
   `(solaire-line-number-face      ((t (:background ,bg-alt :foreground ,fg-dim))))
   `(solaire-fringe-face           ((t (:background ,bg-alt))))
   `(solaire-mode-line-face        ((t (:background ,bg-alt :foreground ,fg))))
   `(solaire-mode-line-inactive-face ((t (:background ,bg-dark :foreground ,fg-dim))))

   ;; --------------------------------------------------------- doom modeline -
   `(doom-modeline-bar              ((t (:background ,teal))))
   `(doom-modeline-bar-inactive     ((t (:background ,bg-dark))))
   `(doom-modeline-buffer-file      ((t (:foreground ,fg :weight bold))))
   `(doom-modeline-buffer-modified  ((t (:foreground ,yellow :weight bold))))
   `(doom-modeline-buffer-path      ((t (:foreground ,fg-alt))))
   `(doom-modeline-project-dir      ((t (:foreground ,cyan :weight bold))))
   `(doom-modeline-project-root-dir ((t (:foreground ,fg-alt))))
   `(doom-modeline-info             ((t (:foreground ,green))))
   `(doom-modeline-warning          ((t (:foreground ,yellow))))
   `(doom-modeline-urgent           ((t (:foreground ,red))))
   `(doom-modeline-buffer-major-mode ((t (:foreground ,purple :weight bold))))
   `(doom-modeline-panel            ((t (:background ,bg-light :foreground ,fg))))
   `(doom-modeline-evil-normal-state   ((t (:foreground ,cyan :weight bold))))
   `(doom-modeline-evil-insert-state   ((t (:foreground ,green :weight bold))))
   `(doom-modeline-evil-visual-state   ((t (:foreground ,purple :weight bold))))
   `(doom-modeline-evil-replace-state  ((t (:foreground ,red :weight bold))))
   `(doom-modeline-evil-operator-state ((t (:foreground ,blue :weight bold))))
   `(doom-modeline-evil-motion-state   ((t (:foreground ,fg-alt :weight bold))))

   ;; --------------------------------------------- vertico / completion -----
   `(vertico-current        ((t (:background ,bg-sel :weight bold :extend t))))
   `(vertico-group-title    ((t (:foreground ,purple :weight bold))))
   `(vertico-group-separator ((t (:foreground ,border :strike-through t))))
   `(vertico-posframe        ((t (:background ,bg-light :foreground ,fg))))
   `(vertico-posframe-border ((t (:background ,border))))
   `(completions-common-part ((t (:foreground ,cyan :weight bold))))
   `(completions-first-difference ((t (:foreground ,fg))))
   `(completions-highlight  ((t (:background ,bg-sel))))
   `(completions-annotations ((t (:foreground ,fg-dim :slant italic))))
   `(orderless-match-face-0  ((t (:foreground ,cyan :weight bold))))
   `(orderless-match-face-1  ((t (:foreground ,purple :weight bold))))
   `(orderless-match-face-2  ((t (:foreground ,green :weight bold))))
   `(orderless-match-face-3  ((t (:foreground ,yellow :weight bold))))

   ;; -------------------------------------------------------- corfu / company
   `(corfu-default          ((t (:background ,bg-light :foreground ,fg))))
   `(corfu-current          ((t (:background ,bg-sel :foreground ,fg))))
   `(corfu-bar              ((t (:background ,cyan))))
   `(corfu-border           ((t (:background ,border))))
   `(corfu-annotations      ((t (:foreground ,fg-dim))))
   `(company-tooltip            ((t (:background ,bg-light :foreground ,fg))))
   `(company-tooltip-selection  ((t (:background ,bg-sel :foreground ,fg))))
   `(company-tooltip-common     ((t (:foreground ,cyan :weight bold))))
   `(company-tooltip-annotation ((t (:foreground ,fg-dim))))
   `(company-scrollbar-bg       ((t (:background ,bg-dark))))
   `(company-scrollbar-fg       ((t (:background ,cyan))))

   ;; -------------------------------------------------------------- consult --
   `(consult-preview-match  ((t (:background ,bg-sel :foreground ,fg))))
   `(consult-preview-line   ((t (:background ,bg-hl :extend t))))
   `(consult-file           ((t (:foreground ,fg-alt))))
   `(consult-bookmark       ((t (:foreground ,purple))))
   `(consult-async-split    ((t (:foreground ,orange))))
   `(marginalia-key         ((t (:foreground ,cyan))))
   `(marginalia-documentation ((t (:foreground ,comment :slant italic))))
   `(marginalia-type        ((t (:foreground ,yellow))))
   `(which-key-key-face            ((t (:foreground ,cyan :weight bold))))
   `(which-key-command-description-face ((t (:foreground ,fg))))
   `(which-key-group-description-face   ((t (:foreground ,purple))))

   ;; -------------------------------------------------------- web / markup ---
   `(web-mode-html-tag-face          ((t (:foreground ,yellow :weight bold))))
   `(web-mode-html-tag-bracket-face  ((t (:foreground ,yellow))))
   `(web-mode-html-attr-name-face    ((t (:foreground ,blue))))
   `(web-mode-html-attr-value-face   ((t (:foreground ,green))))
   `(web-mode-html-attr-equal-face   ((t (:foreground ,fg-dim))))
   `(web-mode-function-call-face     ((t (:foreground ,blue))))
   `(web-mode-function-name-face     ((t (:foreground ,blue :weight bold))))
   `(web-mode-constant-face          ((t (:foreground ,orange))))
   `(web-mode-keyword-face           ((t (:foreground ,purple :weight bold))))
   `(web-mode-string-face            ((t (:foreground ,green))))
   `(web-mode-type-face              ((t (:foreground ,yellow :weight bold))))
   `(web-mode-current-element-highlight-face ((t (:background ,bg-sel))))
   `(web-mode-css-selector-face      ((t (:foreground ,purple))))
   `(web-mode-css-property-name-face ((t (:foreground ,cyan))))
   `(web-mode-css-pseudo-class-face  ((t (:foreground ,yellow))))
   `(css-selector                    ((t (:foreground ,purple))))
   `(css-property                    ((t (:foreground ,cyan))))
   `(js2-function-param              ((t (:foreground ,coral :slant italic))))
   `(js2-jsdoc-tag                   ((t (:foreground ,purple))))
   `(typescript-jsdoc-tag           ((t (:foreground ,purple))))

   ;; ------------------------------------------------------------------ org --
   `(org-document-title  ((t (:foreground ,cyan :weight bold :height 1.3))))
   `(org-document-info   ((t (:foreground ,fg-alt))))
   `(org-document-info-keyword ((t (:foreground ,comment))))
   `(org-level-1         ((t (:foreground ,blue :weight bold :height 1.15))))
   `(org-level-2         ((t (:foreground ,purple :weight bold :height 1.1))))
   `(org-level-3         ((t (:foreground ,cyan :weight bold))))
   `(org-level-4         ((t (:foreground ,green :weight bold))))
   `(org-level-5         ((t (:foreground ,yellow :weight bold))))
   `(org-level-6         ((t (:foreground ,orange :weight bold))))
   `(org-level-7         ((t (:foreground ,coral :weight bold))))
   `(org-level-8         ((t (:foreground ,fg-alt :weight bold))))
   `(org-block           ((t (:background ,bg-alt :foreground ,fg :extend t))))
   `(org-block-begin-line ((t (:background ,bg-dark :foreground ,comment :slant italic :extend t))))
   `(org-block-end-line  ((t (:background ,bg-dark :foreground ,comment :slant italic :extend t))))
   `(org-code            ((t (:background ,bg-alt :foreground ,cyan))))
   `(org-verbatim        ((t (:background ,bg-alt :foreground ,green))))
   `(org-quote           ((t (:background ,bg-alt :foreground ,fg-alt :slant italic :extend t))))
   `(org-table           ((t (:foreground ,fg-alt :background ,bg-alt))))
   `(org-link            ((t (:foreground ,cyan :underline t))))
   `(org-footnote        ((t (:foreground ,cyan :underline t))))
   `(org-date            ((t (:foreground ,teal :underline t))))
   `(org-todo            ((t (:foreground ,red :weight bold))))
   `(org-done            ((t (:foreground ,green :weight bold))))
   `(org-headline-done   ((t (:foreground ,comment))))
   `(org-checkbox        ((t (:foreground ,cyan))))
   `(org-tag             ((t (:foreground ,fg-dim :weight normal))))
   `(org-special-keyword ((t (:foreground ,purple))))
   `(org-drawer          ((t (:foreground ,comment))))
   `(org-meta-line       ((t (:foreground ,comment :slant italic))))
   `(org-ellipsis        ((t (:foreground ,fg-dim :underline nil))))
   `(org-hide            ((t (:foreground ,bg))))
   `(org-agenda-date     ((t (:foreground ,cyan :weight bold))))
   `(org-agenda-date-today ((t (:foreground ,teal :weight bold))))
   `(org-agenda-structure ((t (:foreground ,purple :weight bold))))
   `(org-modern-label    ((t (:foreground ,fg :background ,bg-light))))

   ;; -------------------------------------------------------------- markdown -
   `(markdown-header-face-1 ((t (:foreground ,blue :weight bold :height 1.15))))
   `(markdown-header-face-2 ((t (:foreground ,purple :weight bold :height 1.1))))
   `(markdown-header-face-3 ((t (:foreground ,cyan :weight bold))))
   `(markdown-header-face-4 ((t (:foreground ,green :weight bold))))
   `(markdown-code-face     ((t (:background ,bg-alt :foreground ,cyan :extend t))))
   `(markdown-inline-code-face ((t (:background ,bg-alt :foreground ,cyan))))
   `(markdown-pre-face      ((t (:background ,bg-alt :foreground ,fg))))
   `(markdown-link-face     ((t (:foreground ,cyan :underline t))))
   `(markdown-url-face      ((t (:foreground ,fg-dim))))
   `(markdown-bold-face     ((t (:foreground ,fg :weight bold))))
   `(markdown-italic-face   ((t (:foreground ,fg :slant italic))))
   `(markdown-blockquote-face ((t (:foreground ,fg-alt :slant italic))))

   ;; ----------------------------------------------------- diff / magit -----
   `(diff-added         ((t (:background "#16241a" :foreground ,green :extend t))))
   `(diff-removed       ((t (:background "#2a1a1f" :foreground ,red :extend t))))
   `(diff-changed       ((t (:background "#252033" :foreground ,yellow :extend t))))
   `(diff-refine-added  ((t (:background "#1f3a28" :foreground ,green))))
   `(diff-refine-removed ((t (:background "#43232b" :foreground ,red))))
   `(diff-header        ((t (:background ,bg-alt :foreground ,fg))))
   `(diff-file-header   ((t (:background ,bg-alt :foreground ,cyan :weight bold))))
   `(diff-hunk-header   ((t (:background ,bg-dark :foreground ,purple))))
   `(diff-hl-insert     ((t (:foreground ,green :background ,green))))
   `(diff-hl-delete     ((t (:foreground ,red :background ,red))))
   `(diff-hl-change     ((t (:foreground ,yellow :background ,yellow))))
   `(magit-section-heading      ((t (:foreground ,yellow :weight bold))))
   `(magit-section-highlight    ((t (:background ,bg-hl :extend t))))
   `(magit-diff-added           ((t (:background "#16241a" :foreground ,green :extend t))))
   `(magit-diff-added-highlight ((t (:background "#1c2e20" :foreground ,green :extend t))))
   `(magit-diff-removed         ((t (:background "#2a1a1f" :foreground ,red :extend t))))
   `(magit-diff-removed-highlight ((t (:background "#341f25" :foreground ,red :extend t))))
   `(magit-diff-context         ((t (:foreground ,fg-alt :extend t))))
   `(magit-diff-context-highlight ((t (:background ,bg-alt :foreground ,fg-alt :extend t))))
   `(magit-diff-hunk-heading    ((t (:background ,bg-dark :foreground ,fg-alt :extend t))))
   `(magit-diff-hunk-heading-highlight ((t (:background ,bg-light :foreground ,fg :extend t))))
   `(magit-branch-local         ((t (:foreground ,cyan :weight bold))))
   `(magit-branch-remote        ((t (:foreground ,green :weight bold))))
   `(magit-hash                 ((t (:foreground ,fg-dim))))
   `(magit-tag                  ((t (:foreground ,yellow))))
   `(magit-log-author           ((t (:foreground ,coral))))
   `(magit-log-date             ((t (:foreground ,fg-dim))))

   ;; ------------------------------------------------- flycheck / flymake ----
   `(flycheck-error    ((t (:underline (:style wave :color ,red)))))
   `(flycheck-warning  ((t (:underline (:style wave :color ,yellow)))))
   `(flycheck-info     ((t (:underline (:style wave :color ,cyan)))))
   `(flymake-error     ((t (:underline (:style wave :color ,red)))))
   `(flymake-warning   ((t (:underline (:style wave :color ,yellow)))))
   `(flymake-note      ((t (:underline (:style wave :color ,cyan)))))
   `(flyspell-incorrect ((t (:underline (:style wave :color ,red)))))
   `(flyspell-duplicate ((t (:underline (:style wave :color ,yellow)))))
   `(hl-todo           ((t (:foreground ,yellow :weight bold))))

   ;; -------------------------------------------------------------- eglot ----
   `(eglot-highlight-symbol-face ((t (:background ,bg-sel :weight bold))))
   `(eglot-inlay-hint-face       ((t (:foreground ,fg-dim :slant italic))))
   `(lsp-face-highlight-textual  ((t (:background ,bg-sel))))
   `(lsp-face-highlight-read     ((t (:background ,bg-sel))))
   `(lsp-face-highlight-write    ((t (:background ,bg-sel :weight bold))))
   `(eldoc-highlight-function-argument ((t (:foreground ,orange :weight bold))))

   ;; ----------------------------------------------------------- treemacs ----
   `(treemacs-root-face            ((t (:foreground ,cyan :weight bold :height 1.1))))
   `(treemacs-directory-face       ((t (:foreground ,fg))))
   `(treemacs-directory-collapsed-face ((t (:foreground ,fg-alt))))
   `(treemacs-file-face            ((t (:foreground ,fg-alt))))
   `(treemacs-fringe-indicator-face ((t (:foreground ,cyan))))
   `(treemacs-git-modified-face    ((t (:foreground ,yellow))))
   `(treemacs-git-added-face       ((t (:foreground ,green))))
   `(treemacs-git-renamed-face     ((t (:foreground ,purple))))
   `(treemacs-git-ignored-face     ((t (:foreground ,fg-dim))))
   `(treemacs-git-untracked-face   ((t (:foreground ,green))))
   `(treemacs-git-conflict-face    ((t (:foreground ,red :weight bold))))
   `(treemacs-on-success-pulse-face ((t (:background ,green :foreground ,black))))

   ;; -------------------------------------------------------------- dired ----
   `(dired-directory   ((t (:foreground ,cyan :weight bold))))
   `(dired-symlink     ((t (:foreground ,teal))))
   `(dired-header      ((t (:foreground ,purple :weight bold))))
   `(dired-flagged     ((t (:foreground ,red))))
   `(dired-marked      ((t (:foreground ,yellow :weight bold))))
   `(dired-perm-write  ((t (:foreground ,orange))))
   `(dired-ignored     ((t (:foreground ,fg-dim))))

   ;; ----------------------------------------------------------- tab-bar -----
   `(tab-bar             ((t (:background ,bg-dark :foreground ,fg-alt))))
   `(tab-bar-tab         ((t (:background ,bg :foreground ,fg :weight bold
                              :box (:line-width 2 :color ,bg)))))
   `(tab-bar-tab-inactive ((t (:background ,bg-dark :foreground ,fg-dim
                               :box (:line-width 2 :color ,bg-dark)))))
   `(tab-line            ((t (:background ,bg-dark :foreground ,fg-alt))))

   ;; ----------------------------------------------------------- ansi/term ---
   `(ansi-color-black   ((t (:foreground ,bg-dark :background ,bg-dark))))
   `(ansi-color-red     ((t (:foreground ,red :background ,red))))
   `(ansi-color-green   ((t (:foreground ,green :background ,green))))
   `(ansi-color-yellow  ((t (:foreground ,yellow :background ,yellow))))
   `(ansi-color-blue    ((t (:foreground ,blue :background ,blue))))
   `(ansi-color-magenta ((t (:foreground ,purple :background ,purple))))
   `(ansi-color-cyan    ((t (:foreground ,cyan :background ,cyan))))
   `(ansi-color-white   ((t (:foreground ,fg :background ,fg)))))

  ;; Frame / fringe niceties that aren't faces.
  (custom-theme-set-variables
   'dobri-c07
   `(ansi-color-names-vector
     [,bg-dark ,red ,green ,yellow ,blue ,purple ,cyan ,fg])))

(when (and (boundp 'custom-theme-load-path) load-file-name)
  (add-to-list 'custom-theme-load-path
               (file-name-as-directory (file-name-directory load-file-name))))

(provide-theme 'dobri-c07)

;;; dobri-next-c07.el ends here
