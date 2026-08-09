;;; mp-treesit.el --- Tree-sitter: grammars, folding, text objects -*- lexical-binding: t; -*-

;;; Tree-sitter grammars

;; Without a grammar, a `*-ts-mode' silently falls back to its non-tree-sitter
;; counterpart, which is what makes JSX folding collapse the whole function
;; body and breaks tree-sitter-aware editing. Install grammars on demand
;; instead of asking each time (needs a C compiler and network access on first
;; use).
;; Emacs 31's built-in on-demand installer variable; inert on 30 but harmless.
(setq treesit-auto-install-grammar 'always)

;; Maximum font-lock detail from tree-sitter.
(setq treesit-font-lock-level 4)

;; treesit-auto remaps major modes to their `*-ts-mode' counterparts when a
;; grammar is (or can be) installed, replacing Doom's mode remapping.
;; `treesit-auto-install' is the variable that actually auto-installs on
;; Emacs 30 — t = install without prompting (needs a C compiler + network the
;; first time a language is opened; grammars land in <config>/tree-sitter/).
(use-package treesit-auto
  :demand t
  :config
  (setq treesit-auto-install t)
  (treesit-auto-add-to-auto-mode-alist 'all)
  (global-treesit-auto-mode 1)

  ;; treesit-auto installs a grammar when a ts-mode ACTIVATES — but buffers
  ;; restored by workspace persistence activate their modes during startup,
  ;; before the global mode is on, so they end up grammarless with no install.
  ;; Sweep open buffers once after startup (and expose the sweep as a command).
  (defun mp/treesit-install-missing-grammars ()
    "Install grammars for any open ts-mode buffer that lacks one, then revert."
    (interactive)
    (dolist (buf (buffer-list))
      (with-current-buffer buf
        (when (and (derived-mode-p 'prog-mode)
                   (string-suffix-p "-ts-mode" (symbol-name major-mode))
                   (fboundp 'treesit-auto--maybe-install-grammar))
          (with-demoted-errors "treesit grammar install: %S"
            (treesit-auto--maybe-install-grammar))))))
  (add-hook 'elpaca-after-init-hook #'mp/treesit-install-missing-grammars 99))

;;; Tree-sitter text objects

;; Evil text objects that select by *syntax* rather than by delimiter, powered
;; by the tree-sitter parser you already run. (LSP can't do this — it has no
;; concept of "the function around point"; tree-sitter is the right tool.)
;; They fire in any `*-ts-mode' buffer; elsewhere they no-op.
;;
;; - vif / vaf — inside / around the *function* at point. Works with every
;;   operator, so daf, yaf, cif … all do what you'd expect.
;; - vic / vac — inside / around the *class*.
;; - viv / vav — the *variable*: the whole assignment statement, falling back
;;   to the function parameter under point.
(use-package evil-textobj-tree-sitter
  :after evil
  :config
  ;; f = function, c = class, v = variable (assignment, falling back to a
  ;; function parameter). Bound under the i/a text-object maps so they compose
  ;; with every operator: vif, daf, yac, civ, …
  (define-key evil-outer-text-objects-map "f"
    (evil-textobj-tree-sitter-get-textobj "function.outer"))
  (define-key evil-inner-text-objects-map "f"
    (evil-textobj-tree-sitter-get-textobj "function.inner"))
  (define-key evil-outer-text-objects-map "c"
    (evil-textobj-tree-sitter-get-textobj "class.outer"))
  (define-key evil-inner-text-objects-map "c"
    (evil-textobj-tree-sitter-get-textobj "class.inner"))
  ;; NB: this is a *macro* — pass multiple groups as an unquoted literal list.
  (define-key evil-outer-text-objects-map "v"
    (evil-textobj-tree-sitter-get-textobj ("assignment.outer" "parameter.outer")))
  (define-key evil-inner-text-objects-map "v"
    (evil-textobj-tree-sitter-get-textobj ("assignment.inner" "parameter.inner"))))

;;; Code folding

;; With grammars installed, folding routes through `treesit-fold' and operates
;; on the syntax tree, so the stock Evil keys do what an IDE does:
;;
;; - zc folds the innermost element/block at point (the direct parent of the
;;   current line).
;; - zo opens the fold on the current line (where the … ellipsis shows).
;; - za toggles, zr opens every fold, zm folds everything.
(use-package treesit-fold
  :demand t
  :config
  (global-treesit-fold-mode 1))

;; `tsx-ts-mode' (used for .jsx and .tsx) already folds JSX elements. The
;; block below extends the plain JS modes so JSX embedded in a .js file folds
;; at the element level too, instead of only collapsing the enclosing
;; function.
(with-eval-after-load 'treesit-fold
  (dolist (mode '(js-mode js-ts-mode javascript-mode))
    (when-let ((cell (assq mode treesit-fold-range-alist)))
      (dolist (rule '((jsx_element  . treesit-fold-range-html)
                      (jsx_fragment . treesit-fold-range-html)))
        (unless (assq (car rule) (cdr cell))
          (setcdr cell (append (cdr cell) (list rule))))))))

;; Non-tree-sitter folding fallback.
(add-hook 'prog-mode-hook #'hs-minor-mode)

;;; Fold by level

;; VSCode-style "fold everything to level N", bound to z1 … z9 (z then a
;; digit). Level 1 is the outermost construct, higher numbers reveal more
;; nesting, and the level is clamped to the deepest fold the buffer actually
;; has (so z9 in a shallow file folds the innermost level). Shallower levels
;; stay open, anything deeper is hidden inside the folded level—exactly the
;; VSCode behaviour.
;;
;; It toggles: pressing the same level again, while that level is folded,
;; reveals everything. In tree-sitter buffers this walks the syntax tree to
;; compute true nesting depth; elsewhere it falls back to hideshow/outline
;; level folding.

(defun mp/treesit-fold-active-p ()
  "Return non-nil when `treesit-fold' can operate on the current buffer."
  (and (fboundp 'treesit-fold-ready-p)
       (treesit-fold-ready-p)
       (treesit-fold-usable-mode-p)))

(defun mp/treesit-fold--node-foldable-p (node)
  "Return non-nil when NODE defines a multi-line fold."
  (when-let ((range (treesit-fold--get-fold-range node)))
    (not (treesit-fold--range-on-same-line range))))

(defun mp/treesit-fold--depth (node)
  "Return the fold-nesting depth of NODE (1 = outermost foldable)."
  (let ((depth 0)
        (current node))
    (while current
      (when (mp/treesit-fold--node-foldable-p current)
        (cl-incf depth))
      (setq current (treesit-node-parent current)))
    depth))

(defun mp/treesit-fold--foldable-nodes ()
  "Return every multi-line foldable node in the buffer."
  (let* ((root (treesit-buffer-root-node))
         (ranges (alist-get major-mode treesit-fold-range-alist))
         (patterns (seq-mapcat (lambda (range) `((,(car range)) @name)) ranges))
         (query (treesit-query-compile (treesit-node-language root) patterns)))
    (cl-remove-if-not #'mp/treesit-fold--node-foldable-p
                      (mapcar #'cdr (treesit-query-capture root query)))))

(defun mp/treesit-fold-to-level (level)
  "Fold every node at LEVEL, keeping shallower levels open (VSCode-style).
If LEVEL is already folded, reveal everything instead."
  (let* ((nodes (mp/treesit-fold--foldable-nodes))
         (depths (mapcar #'mp/treesit-fold--depth nodes))
         (max-depth (if depths (apply #'max depths) 0)))
    (when (zerop max-depth)
      (user-error "Nothing foldable in this buffer"))
    (let* ((level (min level max-depth))
           (at-level (cl-loop for node in nodes
                              for depth in depths
                              when (= depth level) collect node))
           (folded (cl-some #'treesit-fold-overlay-at at-level)))
      (treesit-fold-open-all)
      (if folded
          (message "Fold level %d revealed" level)
        (dolist (node at-level)
          (treesit-fold-close node))
        (message "Folded to level %d" level)))))

(defvar-local mp/fold--last-level nil
  "Last fold level applied in a non-tree-sitter buffer, for toggling.")

(defun mp/fold-open-all ()
  "Open every fold in the buffer with whichever backend is active."
  (cond ((mp/treesit-fold-active-p)
         (treesit-fold-open-all))
        ((or (bound-and-true-p hs-minor-mode)
             (and (derived-mode-p 'prog-mode)
                  (progn (hs-minor-mode 1) t)))
         (hs-show-all))
        ((bound-and-true-p outline-minor-mode)
         (outline-show-all))))

(defun mp/fold-close-all (level)
  "Fold the buffer down to LEVEL with hideshow, or outline as a fallback."
  (if (or (bound-and-true-p hs-minor-mode)
          (and (derived-mode-p 'prog-mode)
               (progn (hs-minor-mode 1) t)))
      (hs-hide-level level)
    (outline-hide-sublevels level)))

(defun mp/fold--fallback-to-level (level)
  "Fold to LEVEL with hideshow/outline, toggling open on repeat."
  (if (eq mp/fold--last-level level)
      (progn (mp/fold-open-all)
             (setq mp/fold--last-level nil)
             (message "Fold level %d revealed" level))
    (mp/fold-open-all)
    (mp/fold-close-all level)
    (setq mp/fold--last-level level)
    (message "Folded to level %d" level)))

(defun mp/fold-to-level (&optional level)
  "Fold all regions down to LEVEL (1 = outermost), VSCode-style.
Re-invoking the same level reveals everything again.  When called from the
z1..z9 keys, LEVEL is read from the triggering digit."
  (interactive)
  (let ((level (or level
                   (let ((event last-command-event))
                     (and (characterp event)
                          (<= ?1 event ?9)
                          (- event ?0))))))
    (unless (and (integerp level) (<= 1 level 9))
      (user-error "Fold level must be between 1 and 9"))
    (if (mp/treesit-fold-active-p)
        (mp/treesit-fold-to-level level)
      (mp/fold--fallback-to-level level))))

;; z1 … z9 — evil is already loaded, so bind directly.
(dolist (level (number-sequence 1 9))
  (let ((key (vector ?z (+ ?0 level))))
    (define-key evil-normal-state-map key #'mp/fold-to-level)
    (define-key evil-motion-state-map key #'mp/fold-to-level)))

(provide 'mp-treesit)
;;; mp-treesit.el ends here
