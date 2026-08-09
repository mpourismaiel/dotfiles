;;; mp-evil.el --- Evil + the full Doom-parity flotilla -*- lexical-binding: t; -*-

;;; Undo backend (must exist before evil loads)

(use-package undo-fu
  :demand t
  :config
  (setq undo-limit 67108864
        undo-strong-limit 100663296
        undo-outer-limit 1006632960))

(use-package undo-fu-session
  :demand t
  :config
  (setq undo-fu-session-directory (expand-file-name "undo-fu-session/" mp/var-dir)
        undo-fu-session-incompatible-files
        '("/COMMIT_EDITMSG\\'" "/git-rebase-todo\\'"))
  (undo-fu-session-global-mode 1))

(use-package vundo
  :commands (vundo)
  :config (setq vundo-glyph-alist vundo-unicode-symbols))

;;; Evil core

(use-package evil
  :demand t
  :init
  ;; Must be set before evil loads (values mirror Doom's).
  (setq evil-want-integration t
        evil-want-keybinding nil          ; evil-collection handles mode maps
        evil-want-C-u-scroll t
        evil-want-C-u-delete t
        evil-want-C-w-delete t
        evil-want-Y-yank-to-eol t
        evil-want-fine-undo t
        evil-symbol-word-search t
        evil-ex-search-vim-style-regexp t
        evil-ex-visual-char-range t
        evil-visual-state-cursor 'box
        evil-mode-line-format nil
        evil-kbd-macro-suppress-motion-error t
        evil-undo-system 'undo-fu
        evil-respect-visual-line-mode nil
        evil-split-window-below nil
        evil-vsplit-window-right nil)
  :config
  (evil-mode 1)
  ;; `gd'-adjacent defaults are overridden in mp-keys / lsp buffers.
  (evil-select-search-module 'evil-search-module 'evil-search))

(use-package evil-collection
  :after evil
  :demand t
  :config
  (setq evil-collection-setup-minibuffer nil)
  (evil-collection-init))

;; Force the queue: everything below this line (evil-define-key/operator at
;; top level) needs evil actually loaded, and elpaca defers use-package bodies.
(elpaca-wait)

;;; Flotilla (Doom :editor evil package set, verified against the live install)

(use-package evil-surround
  :after evil :demand t
  :config (global-evil-surround-mode 1))

(use-package evil-embrace
  :after evil-surround :demand t
  :config (evil-embrace-enable-evil-surround-integration))

(use-package evil-snipe
  :after evil :demand t
  :config
  (setq evil-snipe-smart-case t
        evil-snipe-scope 'line
        evil-snipe-repeat-scope 'visible
        evil-snipe-char-fold t)
  (evil-snipe-mode 1)
  (evil-snipe-override-mode 1))

(use-package evil-escape
  :after evil :demand t
  :config
  ;; Doom ships this with the key sequence disabled; kept for parity.
  (setq evil-escape-excluded-states '(normal visual multiedit emacs motion)
        evil-escape-excluded-major-modes '(vterm-mode ghostel-mode)
        evil-escape-key-sequence nil
        evil-escape-delay 0.15)
  (evil-escape-mode 1))

(use-package evil-easymotion
  :after evil :demand t
  :config
  ;; Doom: `gs' prefix holds the evilem motions, `gs/' the avy timer.
  (evilem-default-keybindings "gs")
  (define-key evilem-map "/" #'evil-avy-goto-char-timer))

(use-package avy
  :config (setq avy-all-windows nil avy-background t))

(use-package evil-visualstar
  :after evil :demand t
  :config (global-evil-visualstar-mode 1))

(use-package evil-exchange
  :after evil :demand t
  :config (evil-exchange-install))       ; gx / gX

(use-package evil-args
  :after evil
  :bind (:map evil-inner-text-objects-map ("a" . evil-inner-arg)
         :map evil-outer-text-objects-map ("a" . evil-outer-arg)))

(use-package evil-indent-plus
  :after evil :demand t
  :config (evil-indent-plus-default-bindings)) ; ii / ij / ik (+ outer)

(use-package evil-lion
  :after evil :demand t
  :config (evil-lion-mode 1))            ; gl / gL align

(use-package evil-nerd-commenter
  :after evil
  :commands (evilnc-comment-operator)
  :init
  (with-eval-after-load 'evil
    (evil-define-key '(normal visual) 'global "gc" #'evilnc-comment-operator)))

(use-package evil-numbers
  :after evil
  :init
  (with-eval-after-load 'evil
    (evil-define-key '(normal visual) 'global
      (kbd "g=") #'evil-numbers/inc-at-pt
      (kbd "g-") #'evil-numbers/dec-at-pt)))

(use-package evil-traces
  :after evil :demand t
  :config (evil-traces-mode 1))          ; live ex-command previews

(use-package evil-textobj-anyblock
  :after evil
  :bind (:map evil-inner-text-objects-map ("B" . evil-textobj-anyblock-inner-block)
         :map evil-outer-text-objects-map ("B" . evil-textobj-anyblock-a-block)))

(use-package exato                        ; ix / ax xml attributes
  :after evil
  :bind (:map evil-inner-text-objects-map ("x" . evil-inner-xml-attr)
         :map evil-outer-text-objects-map ("x" . evil-outer-xml-attr)))

(use-package anzu :defer t)
(use-package evil-anzu
  :after evil :demand t
  :config (global-anzu-mode 1))

(use-package evil-goggles
  :after evil :demand t
  :config
  (setq evil-goggles-duration 0.1)
  (evil-goggles-mode 1))

(use-package vi-tilde-fringe
  :hook ((prog-mode text-mode conf-mode) . vi-tilde-fringe-mode))

;; Arbitrary manual folds (zf), complementing treesit-fold in mp-treesit.
(use-package vimish-fold :after evil)
(use-package evil-vimish-fold
  :after vimish-fold :demand t
  :config
  (setq vimish-fold-dir (expand-file-name "vimish-fold/" mp/var-dir))
  (global-evil-vimish-fold-mode 1))

;;; Multiple cursors (config ported from config.org)

(use-package evil-mc
  :after evil :demand t
  :config
  (global-evil-mc-mode 1)

  (defun my/evil-mc-escape ()
    (interactive)
    (if (and (bound-and-true-p evil-mc-mode)
             evil-mc-cursor-list)
        (evil-mc-undo-all-cursors)
      (evil-force-normal-state)))

  (evil-define-key 'normal 'global
    (kbd "C-M-<down>")  #'evil-mc-make-cursor-move-next-line
    (kbd "C-M-<up>")    #'evil-mc-make-cursor-move-prev-line
    (kbd "C-M-<right>") #'evil-mc-make-all-cursors
    (kbd "<escape>")    #'my/evil-mc-escape)
  (evil-define-key 'insert 'global
    (kbd "<escape>")    #'my/evil-mc-escape))

(use-package evil-multiedit
  :after evil :demand t
  :config
  (evil-define-key '(normal visual) 'global
    (kbd "C-d") #'evil-multiedit-match-and-next)
  (evil-define-key 'insert 'global
    (kbd "C-d") #'evil-multiedit-toggle-marker-here))

;;; Ported Doom +evil helpers (referenced by the keymap manifest)

(defun mp/evil-window-split-and-follow ()
  "Split below and focus the new window (Doom's +evil/window-split-and-follow)."
  (interactive)
  (select-window (split-window-below)))

(defun mp/evil-window-vsplit-and-follow ()
  "Split right and focus the new window (Doom's +evil/window-vsplit-and-follow)."
  (interactive)
  (select-window (split-window-right)))

(defun mp/evil-insert-newline-below ()
  "Insert a newline below point without changing point or state."
  (interactive)
  (save-excursion (end-of-line) (newline)))

(defun mp/evil-insert-newline-above ()
  "Insert a newline above point without changing point or state."
  (interactive)
  (save-excursion (beginning-of-line) (open-line 1)))

(defun mp/window-move (dir)
  "Swap the current window's buffer state in direction DIR."
  (pcase dir
    ('left (windmove-swap-states-left))
    ('right (windmove-swap-states-right))
    ('up (windmove-swap-states-up))
    ('down (windmove-swap-states-down))))

(defun mp/evil-window-move-left ()  (interactive) (mp/window-move 'left))
(defun mp/evil-window-move-right () (interactive) (mp/window-move 'right))
(defun mp/evil-window-move-up ()    (interactive) (mp/window-move 'up))
(defun mp/evil-window-move-down () (interactive) (mp/window-move 'down))

(defun mp/neighbor-file (offset)
  "Visit the file OFFSET entries away in the current directory listing."
  (let* ((file (buffer-file-name))
         (files (and file
                     (seq-filter #'file-regular-p
                                 (directory-files (file-name-directory file)
                                                  'full "\\`[^.]"))))
         (pos (and files (seq-position files file))))
    (unless pos (user-error "Buffer is not visiting a file"))
    (let ((next (nth (mod (+ pos offset) (length files)) files)))
      (find-file next))))

(defun mp/evil-next-file ()     (interactive) (mp/neighbor-file 1))
(defun mp/evil-previous-file () (interactive) (mp/neighbor-file -1))

(defun mp/evil-reselect-paste ()
  "Reselect the last pasted region (Doom's +evil/reselect-paste, i.e. gp)."
  (interactive)
  (unless evil-last-paste (user-error "No paste to reselect"))
  (evil-visual-make-selection (nth 3 evil-last-paste)
                              (max (nth 3 evil-last-paste)
                                   (1- (nth 4 evil-last-paste)))))

(evil-define-operator mp/evil-yank-unindented (beg end type register _yank-handler)
  "Yank text, stripping the common leading indentation (Doom's g y)."
  :move-point nil
  (interactive "<R><x><y>")
  (let* ((text (buffer-substring-no-properties beg end))
         (lines (split-string text "\n"))
         (indent
          (seq-min
           (or (seq-keep (lambda (line)
                           (unless (string-match-p "\\`[ \t]*\\'" line)
                             (string-match "[^ \t]" line)))
                         lines)
               '(0))))
         (stripped (mapconcat (lambda (line)
                                (substring line (min indent (length line))))
                              lines "\n")))
    (evil-set-register (or register ?\") stripped)
    (kill-new stripped)))

(evil-define-text-object mp/evil-whole-buffer-txtobj (count &optional _beg _end type)
  "Text object selecting the whole buffer (ig / ag)."
  (evil-range (point-min) (point-max) type))

(evil-define-text-object mp/evil-inner-url-txtobj (count &optional _beg _end type)
  "Text object selecting the URL at point (iu)."
  (let ((bounds (bounds-of-thing-at-point 'url)))
    (unless bounds (user-error "No URL at point"))
    (evil-range (car bounds) (cdr bounds) type)))

(evil-define-text-object mp/evil-inner-any-quote (count &optional _beg _end type)
  "Text object selecting the nearest quoted string's contents (iq)."
  (let* ((positions
          (seq-filter
           #'identity
           (mapcar (lambda (q)
                     (ignore-errors
                       (save-excursion
                         (let ((range (evil-select-quote q (point) (point) type count nil)))
                           (and range (cons (nth 0 range) (nth 1 range)))))))
                   '(?\" ?\' ?\`))))
         (best (car (sort positions (lambda (a b)
                                      (< (- (cdr a) (car a))
                                         (- (cdr b) (car b))))))))
    (unless best (user-error "No quoted string at point"))
    (evil-range (car best) (cdr best) type)))

(evil-define-text-object mp/evil-outer-any-quote (count &optional _beg _end type)
  "Text object selecting the nearest quoted string incl. quotes (aq)."
  (let ((range (mp/evil-inner-any-quote count nil nil type)))
    (evil-range (max (point-min) (1- (nth 0 range)))
                (min (point-max) (1+ (nth 1 range)))
                type)))

(with-eval-after-load 'evil
  (define-key evil-inner-text-objects-map "g" #'mp/evil-whole-buffer-txtobj)
  (define-key evil-outer-text-objects-map "g" #'mp/evil-whole-buffer-txtobj)
  (define-key evil-inner-text-objects-map "u" #'mp/evil-inner-url-txtobj)
  (define-key evil-inner-text-objects-map "q" #'mp/evil-inner-any-quote)
  (define-key evil-outer-text-objects-map "q" #'mp/evil-outer-any-quote)
  (define-key evil-inner-text-objects-map "o" #'evil-inner-symbol)
  (define-key evil-outer-text-objects-map "o" #'evil-a-symbol))

(provide 'mp-evil)
;;; mp-evil.el ends here
