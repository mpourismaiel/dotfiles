;;; custom-shortcuts.el --- Complex custom keybindings / leader shortcuts  -*- lexical-binding: t; -*-
;;; Commentary:
;; The larger, non-trivial custom shortcuts and their helper commands,
;; kept out of the main keybindings module (mp-keys.el owns the SPC
;; leader bindings; this package provides the commands they call).
;;; Code:

(declare-function ghostel "ghostel")
(declare-function ghostel-project "ghostel")
(declare-function ghostel--project-buffers "ghostel")
(declare-function consult--read "consult")
(declare-function consult--buffer-preview "consult")
(declare-function mp/current-workspace-project-root "mp-workspaces")

(defun mp/project-root-default-directory (&optional dir)
  "Return the preferred project root for DIR, preferring explicit workspace roots."
  (or (mp/current-workspace-project-root)
      (let ((dir (file-name-as-directory
                  (expand-file-name (or dir default-directory)))))
        (or
         (when (fboundp 'projectile-project-root)
           (let ((default-directory dir))
             (ignore-errors
               (file-name-as-directory
                (expand-file-name (projectile-project-root))))))
         dir))))

(defun mp/ghostel-new ()
  "Spawn a fresh Ghostel, project-scoped when inside a project.
The `\\='(4)' prefix is Ghostel's \"force a brand-new buffer\" argument, so
this always creates a new terminal rather than reusing one."
  (interactive)
  (if (project-current nil)
      (ghostel-project '(4))
    (ghostel '(4))))

(defun mp/ghostel-consult-pick (bufs)
  "Pick among the project's Ghostel BUFS with live preview.
The first candidate always creates a brand-new project Ghostel; every
other candidate switches to that Ghostel in the current window."
  (let* ((new "＋ New Ghostel")
         (names (mapcar #'buffer-name bufs))
         (preview (consult--buffer-preview))
         (choice
          (consult--read
           (cons new names)
           :prompt "Ghostel: "
           :category 'buffer
           :require-match t
           :sort nil
           :history 'buffer-name-history
           :default new
           :state
           ;; Preview the buffer under point; the non-buffer "new" entry
           ;; passes nil, which `consult--buffer-preview' treats as "no
           ;; preview" (it restores the original window).
           (lambda (action cand)
             (funcall preview action (unless (equal cand new) cand))))))
    (if (equal choice new)
        (mp/ghostel-new)
      (switch-to-buffer choice))))

(defun mp/ghostel-open ()
  "Open a Ghostel for the current project (never a popup).

- Outside any project: open (or reuse) the default Ghostel.
- In a project with no Ghostel open: create a fresh project-scoped one.
- In a project that already has one or more Ghostels (focused or not):
  prompt with a `consult' menu (live preview) listing the project's
  Ghostel buffers.  The first entry always creates a brand-new Ghostel.

Project membership uses Ghostel's own scoping (`ghostel--project-buffers',
governed by `ghostel-project-buffer-scope')."
  (interactive)
  (if (not (project-current nil))
      (ghostel)
    (let ((bufs (ignore-errors (ghostel--project-buffers))))
      (if (null bufs)
          (ghostel-project)
        (mp/ghostel-consult-pick bufs)))))

;; Line-moving helpers (mp/line-move-bounds, mp/move-lines--apply) removed:
;; mp/move-lines / mp/move-lines-up / mp/move-lines-down now live in
;; emacs/lisp/mp-core.el.

;; Global GUI-style bindings.
;; C-` toggles a project terminal in every Evil state (ghostel's
;; `ghostel-keymap-exceptions' in mp-tools.el keeps it live inside term
;; buffers too).  C-/ (comment-line) is bound in mp-keys.el, not here.
(general-define-key
 :states '(normal visual insert motion emacs)
 "C-`" #'mp/ghostel-open)

(provide 'custom-shortcuts)
;;; custom-shortcuts.el ends here
