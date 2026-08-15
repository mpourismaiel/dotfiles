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
(declare-function consult--multi "consult")
(declare-function consult--buffer-preview "consult")
(declare-function mp/current-workspace-project-root "mp-workspaces")
(declare-function my/project-script-files "project-scripts")
(declare-function my/project-script-label "project-scripts")
(declare-function my/run-project-script-file "project-scripts")

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

(defun mp/ghostel-menu (bufs scripts)
  "Grouped picker for the C-` menu: Actions, Terminals, Project Scripts.

BUFS are the project's Ghostel buffers, SCRIPTS its `__ignore__/scripts/'
files.  Sections (in order): \"Actions\" (always, with \"New Ghostel\" on
top as the default), \"Terminals\" (BUFS, with live preview, switched to on
select), and \"Project Scripts\" (SCRIPTS, run in a Ghostel).  Narrow with
the section keys `a' / `t' / `s' (after `consult-narrow-key')."
  (let* ((new "＋ New Ghostel")
         (script-alist (mapcar (lambda (f) (cons (my/project-script-label f) f))
                               scripts)))
    (consult--multi
     (list
      `( :name "Actions"
         :narrow ?a
         :category ghostel-action
         :default t                     ; makes "New Ghostel" the RET default
         :items (,new)
         :action ,(lambda (_) (mp/ghostel-new)))
      `( :name "Terminals"
         :narrow ?t
         :category buffer
         :items ,(mapcar #'buffer-name bufs)
         ;; `consult--buffer-preview' is itself a state generator (0-arg,
         ;; returns the (action cand) fn), exactly what :state wants.
         :state ,#'consult--buffer-preview
         :action ,#'switch-to-buffer)
      `( :name "Project Scripts"
         :narrow ?s
         :category ghostel-script
         :items ,(mapcar #'car script-alist)
         :action ,(lambda (cand)
                    (when-let* ((file (cdr (assoc cand script-alist))))
                      (my/run-project-script-file file)))))
     :prompt "Ghostel: "
     :require-match t
     :sort nil
     :history 'buffer-name-history)))

(defun mp/ghostel-open ()
  "Always pop the grouped Ghostel menu (Actions / Terminals / Project Scripts).

Even with no terminal open the menu still shows; its top, default \"New
Ghostel\" entry makes one on a bare RET.  Terminals and scripts are
project-scoped (`ghostel--project-buffers' — governed by
`ghostel-project-buffer-scope' — and `my/project-script-files'); both
degrade to empty outside a project, where \"New Ghostel\" falls back to a
non-project terminal."
  (interactive)
  (mp/ghostel-menu
   (ignore-errors (ghostel--project-buffers))
   (ignore-errors (my/project-script-files))))

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
