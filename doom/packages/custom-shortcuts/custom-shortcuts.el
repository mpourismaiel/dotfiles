;;; custom-shortcuts.el --- Complex custom keybindings / leader shortcuts  -*- lexical-binding: t; -*-
;;; Commentary:
;; The larger, non-trivial custom shortcuts and their helper commands,
;; kept out of the main keybindings section.
;;; Code:

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
         (when (fboundp 'doom-project-root)
           (ignore-errors
             (file-name-as-directory
              (expand-file-name (doom-project-root dir)))))
         dir))))

(defun mp/ghostel-new ()
  "Spawn a fresh Ghostel, project-scoped when inside a project.
The `\\='(4)' prefix is Ghostel's \"force a brand-new buffer\" argument, so
this always creates a new terminal rather than reusing one."
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

(defun mp/line-move-bounds ()
  "Return the line-aligned bounds for the current line or active region."
  (if (use-region-p)
      (cons (save-excursion
              (goto-char (region-beginning))
              (line-beginning-position))
            (save-excursion
              (goto-char (region-end))
              (if (bolp)
                  (point)
                (line-beginning-position 2))))
    (cons (line-beginning-position)
          (line-beginning-position 2))))

(defun mp/move-lines--apply (direction)
  "Move the current line or active region one line in DIRECTION."
  (let* ((bounds (mp/line-move-bounds))
         (had-region (use-region-p))
         (start (car bounds))
         (end (cdr bounds)))
    (save-excursion
      (goto-char (if (> direction 0) end start))
      (when (or (and (< direction 0) (= start (point-min)))
                (and (> direction 0) (= end (point-max))))
        (user-error "Cannot move further %s" (if (< direction 0) "up" "down"))))
    (let* ((line-count (count-lines start end))
           (column (current-column))
           (text (delete-and-extract-region start end)))
      (goto-char start)
      (forward-line direction)
      (let ((target (point)))
        (insert text)
        (if had-region
            (progn
              (set-mark target)
              (goto-char (+ target (length text)))
              (setq deactivate-mark nil))
          (goto-char target)
          (forward-line (if (> direction 0) (1- line-count) 0))
          (move-to-column column))))))

;; Global GUI-style bindings.
;; Keeps a terminal toggle, line commenting, and line movement available
;; through familiar keys.
(map! :g "C-`" #'mp/ghostel-open
      :g "C-/" #'comment-line)

(provide 'custom-shortcuts)
;;; custom-shortcuts.el ends here
