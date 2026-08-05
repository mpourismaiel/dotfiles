;;; overview-ruler.el --- Minimap-style overview ruler in the fringe/margin  -*- lexical-binding: t; -*-
;;; Commentary:
;; A scroll-overview ruler that marks matches, diagnostics and the viewport
;; along the buffer, VS Code minimap style.
;;; Code:

(require 'svg)

(declare-function diff-hl-changes "diff-hl")
(declare-function diff-hl-changes-from-buffer "diff-hl")

(defvar mp/overview-ruler-width 3
  "Width of the overview ruler window, in columns.")

(defvar mp/overview-ruler-idle 0.3
  "Idle seconds before the overview ruler refreshes.")

(defconst mp/overview-ruler--buffer-name "*overview-ruler*")
(defvar mp/overview-ruler--timer nil)
(defvar mp/overview-ruler--refreshing nil
  "Non-nil while a refresh is in flight, to guard against reentrancy when we
create or delete the side window inside `window-configuration-change-hook'.")

;; Set in the ruler buffer on each render so a click can map a pixel back to a
;; line in the source window it currently reflects.
(defvar-local mp/overview-ruler--src-win nil)
(defvar-local mp/overview-ruler--src-lines nil)
(defvar-local mp/overview-ruler--img-height nil)

;; Per-source-buffer git cache so we don't run a vc diff on every refresh.
(defvar-local mp/overview-ruler--git-cache nil)
(defvar-local mp/overview-ruler--git-tick nil)

(defun mp/overview-ruler--face-color (face attr fallback)
  "FACE's ATTR as a color string, or FALLBACK."
  (or (and (facep face)
           (let ((c (face-attribute face attr nil t)))
             (and (stringp c) c)))
      fallback))

(defvar mp/overview-ruler-colors
  '((git-add    . "#3fb950")   ; added lines    (left lane, green)
    (git-remove . "#f85149")   ; deleted lines  (left lane, red)
    (git-change . "#d29922")   ; modified lines (left lane, amber)
    (error      . "#f85149")   ; red            (right lane)
    (warning    . "#d29922")   ; amber          (right lane)
    (info       . "#58a6ff")   ; blue           (right lane)
    (conflict   . "#bc8cff"))  ; purple         (full width)
  "Color palette for the overview ruler's lanes.")

(defun mp/overview-ruler--color (key)
  "Palette color string for KEY, from `mp/overview-ruler-colors'."
  (alist-get key mp/overview-ruler-colors "#888888"))

(defun mp/overview-ruler--git-color (type)
  "Color string for a git change of TYPE."
  (mp/overview-ruler--color
   (pcase type ('insert 'git-add) ('delete 'git-remove) (_ 'git-change))))

(defun mp/overview-ruler--diag-color (sev)
  "Color string for a diagnostic of severity SEV."
  (mp/overview-ruler--color
   (pcase sev ('error 'error) ('warning 'warning) (_ 'info))))

(defun mp/overview-ruler--git-changes ()
  "List of (START-LINE NLINES TYPE) for the current buffer, or nil.
Reflects the last SAVED state unless `diff-hl-flydiff-mode' is on."
  (when (and (fboundp 'diff-hl-changes) buffer-file-name)
    (ignore-errors
      (let* ((alist (diff-hl-changes))
             (working (cdr (assq :working alist)))
             ;; `diff-hl-changes' hands back the diff *buffer name* (a string)
             ;; for the common case, an actual buffer sometimes, or a literal
             ;; change list for added/removed files.  Normalize all three.
             (working (if (stringp working) (get-buffer working) working))
             (changes (if (bufferp working)
                          (diff-hl-changes-from-buffer working)
                        working))
             res)
        (dolist (c changes)
          (pcase-let ((`(,line ,inserts ,_deletes ,type) c))
            (push (list line (if (eq type 'delete) 1 (max 1 inserts)) type) res)))
        (nreverse res)))))

(defun mp/overview-ruler--git ()
  "Cached `mp/overview-ruler--git-changes', recomputed only after edits."
  (let ((tick (buffer-modified-tick)))
    (unless (eql tick mp/overview-ruler--git-tick)
      (setq mp/overview-ruler--git-tick tick
            mp/overview-ruler--git-cache (mp/overview-ruler--git-changes)))
    mp/overview-ruler--git-cache))

(defun mp/overview-ruler--diagnostics ()
  "List of (LINE . SEVERITY) where SEVERITY is `error', `warning' or `info'."
  (cond
   ((bound-and-true-p flycheck-mode)
    (mapcar (lambda (e)
              (cons (flycheck-error-line e)
                    (pcase (flycheck-error-level e)
                      ('error 'error) ('warning 'warning) (_ 'info))))
            flycheck-current-errors))
   ((bound-and-true-p flymake-mode)
    (let (res)
      (dolist (d (flymake-diagnostics))
        (let ((name (format "%s" (flymake-diagnostic-type d))))
          (push (cons (line-number-at-pos (flymake-diagnostic-beg d))
                      (cond ((string-match-p "error" name) 'error)
                            ((string-match-p "warn"  name) 'warning)
                            (t 'info)))
                res)))
      res))))

(defvar-local mp/overview-ruler--conflict-cache nil)
(defvar-local mp/overview-ruler--conflict-tick nil)

(defun mp/overview-ruler--conflicts ()
  "List of (START-LINE NLINES) covering git merge-conflict regions, or nil.
Each region runs from a `<<<<<<<' marker to its matching `>>>>>>>'."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let (res)
        (while (re-search-forward "^<<<<<<< " nil t)
          (let ((start (line-number-at-pos (match-beginning 0))))
            (if (re-search-forward "^>>>>>>> " nil t)
                (let ((end (line-number-at-pos (match-beginning 0))))
                  (push (list start (max 1 (1+ (- end start)))) res))
              (push (list start 1) res))))
        (nreverse res)))))

(defun mp/overview-ruler--conflicts-cached ()
  "Cached `mp/overview-ruler--conflicts', recomputed only after edits."
  (let ((tick (buffer-modified-tick)))
    (unless (eql tick mp/overview-ruler--conflict-tick)
      (setq mp/overview-ruler--conflict-tick tick
            mp/overview-ruler--conflict-cache (mp/overview-ruler--conflicts)))
    mp/overview-ruler--conflict-cache))

(defun mp/overview-ruler--diag-merge (diags)
  "Collapse DIAGS to one (LINE . SEVERITY) per line; worst severity wins.
So a line carrying both a warning and an error draws as an error."
  (let ((rank '((info . 0) (warning . 1) (error . 2)))
        (tbl (make-hash-table :test 'eql))
        res)
    (dolist (d diags)
      (let ((cur (gethash (car d) tbl)))
        (when (or (null cur)
                  (> (alist-get (cdr d) rank 0) (alist-get cur rank 0)))
          (puthash (car d) (cdr d) tbl))))
    (maphash (lambda (line sev) (push (cons line sev) res)) tbl)
    res))

(defun mp/overview-ruler--render (src-buf src-win ruler-win)
  "Draw the SVG ruler for SRC-BUF / SRC-WIN into RULER-WIN.
Git changes take the left lane and diagnostics the right lane, so a line
that is both changed and flagged shows both colors. Merge conflicts span
the full width on top of both lanes."
  (let ((w (max 8 (window-body-width ruler-win t)))
        (h (max 1 (window-body-height ruler-win t)))
        git diags conflicts n top-line bot-line)
    (with-current-buffer src-buf
      (setq n (max 1 (line-number-at-pos (point-max)))
            git (mp/overview-ruler--git)
            diags (mp/overview-ruler--diag-merge (mp/overview-ruler--diagnostics))
            conflicts (mp/overview-ruler--conflicts-cached))
      (when (window-live-p src-win)
        (setq top-line (line-number-at-pos (window-start src-win))
              bot-line (line-number-at-pos (window-end src-win t)))))
    (let* ((svg (svg-create w h))
           (half (max 1 (floor w 2)))
           (y-of (lambda (line) (floor (* (/ (float (1- (max 1 line))) n) h))))
           (bar  (lambda (nlines) (max 3 (floor (* (/ (float (max 1 nlines)) n) h))))))
      (svg-rectangle svg 0 0 w h
                     :fill (mp/overview-ruler--face-color 'default :background "#0d1117"))
      ;; Git changes: left lane.
      (dolist (c git)
        (pcase-let ((`(,line ,nlines ,type) c))
          (svg-rectangle svg 0 (funcall y-of line)
                         half (funcall bar nlines)
                         :fill (mp/overview-ruler--git-color type))))
      ;; Diagnostics: right lane.
      (dolist (d diags)
        (svg-rectangle svg half (funcall y-of (car d))
                       (- w half) (funcall bar 1)
                       :fill (mp/overview-ruler--diag-color (cdr d))))
      ;; Merge conflicts: full width, on top of both lanes.
      (dolist (c conflicts)
        (pcase-let ((`(,line ,nlines) c))
          (svg-rectangle svg 0 (funcall y-of line)
                         w (funcall bar nlines)
                         :fill (mp/overview-ruler--color 'conflict))))
      (when (and top-line bot-line)
        (let ((top (funcall y-of top-line))
              (bot (funcall y-of bot-line))
              (edge (mp/overview-ruler--face-color 'region :background "#6e7681")))
          (svg-rectangle svg 0 top (1- w) (max 2 (- bot top))
                         :fill edge :fill-opacity 0.15
                         :stroke edge :stroke-width 1)))
      (with-current-buffer (get-buffer-create mp/overview-ruler--buffer-name)
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert-image (svg-image svg))
          (setq mp/overview-ruler--src-win src-win
                mp/overview-ruler--src-lines n
                mp/overview-ruler--img-height h))))))

(defun mp/overview-ruler--goto (event)
  "Move point in the source window to the line clicked on the ruler."
  (interactive "e")
  (let ((posn (event-start event)))
    (with-current-buffer (window-buffer (posn-window posn))
      (let* ((y (cdr (posn-object-x-y posn)))
             (win mp/overview-ruler--src-win)
             (n mp/overview-ruler--src-lines)
             (h mp/overview-ruler--img-height))
        (when (and y win (window-live-p win) n h (> h 0))
          (let ((line (max 1 (min n (1+ (floor (* (/ (float y) h) n)))))))
            (select-window win)
            (goto-char (point-min))
            (forward-line (1- line))
            (recenter)))))))

(defvar mp/overview-ruler--map
  (let ((m (make-sparse-keymap)))
    ;; Click to jump; swallow the press so no drag-select / drag-scroll happens.
    (define-key m [down-mouse-1] #'ignore)
    (define-key m [mouse-1] #'mp/overview-ruler--goto)
    m)
  "Keymap active in the ruler buffer.")

(defun mp/overview-ruler--setup-buffer (buf)
  "Initialize the ruler BUF: read-only, no chrome."
  (with-current-buffer buf
    (setq mode-line-format nil header-line-format nil cursor-type nil
          truncate-lines t buffer-read-only t)
    (use-local-map mp/overview-ruler--map)
    (buffer-disable-undo)))

(defun mp/overview-ruler--window ()
  "Return the ruler window, creating the buffer + side window if needed."
  (let ((buf (get-buffer-create mp/overview-ruler--buffer-name)))
    (mp/overview-ruler--setup-buffer buf)
    (or (get-buffer-window buf t)
        (let ((win (display-buffer-in-side-window
                    buf `((side . right) (slot . 1)
                          (window-width . ,mp/overview-ruler-width)
                          (window-parameters . ((no-other-window . t)
                                                (no-delete-other-windows . t)))))))
          (when win (set-window-fringes win 0 0))
          win))))

(defun mp/overview-ruler--hide ()
  "Delete the ruler side window if it is showing."
  (let ((win (get-buffer-window mp/overview-ruler--buffer-name t)))
    (when (window-live-p win) (delete-window win))))

(defun mp/overview-ruler--refresh ()
  "Refresh the ruler for the currently selected window.
Only `prog-mode' file buffers get a ruler; for anything else it is taken
down, so it never lingers over Org, dired, magit, help, etc."
  (when (and (bound-and-true-p mp/overview-ruler-mode)
             (not mp/overview-ruler--refreshing))
    (let* ((mp/overview-ruler--refreshing t)
           (win (selected-window))
           (buf (window-buffer win))
           (base (or (buffer-base-buffer buf) buf)))
      (cond
       ;; Transient focus (minibuffer, or the ruler itself): leave as is.
       ((or (window-minibuffer-p win)
            (string= (buffer-name buf) mp/overview-ruler--buffer-name))
        nil)
       ;; A prog-mode file buffer: show and (re)draw.
       ((and (buffer-file-name base)
             (with-current-buffer base (derived-mode-p 'prog-mode)))
        (let ((ruler (mp/overview-ruler--window)))
          (when (window-live-p ruler)
            (mp/overview-ruler--render buf win ruler))))
       ;; Anything else: take the ruler down.
       (t (mp/overview-ruler--hide))))))

(define-minor-mode mp/overview-ruler-mode
  "Global VSCode-style overview ruler with git and diagnostic lanes."
  :global t
  (if mp/overview-ruler-mode
      (progn
        (unless (image-type-available-p 'svg)
          (setq mp/overview-ruler-mode nil)
          (user-error "overview-ruler needs an Emacs built with SVG (librsvg)"))
        (setq mp/overview-ruler--timer
              (run-with-idle-timer mp/overview-ruler-idle t #'mp/overview-ruler--refresh))
        (add-hook 'window-configuration-change-hook #'mp/overview-ruler--refresh))
    (when mp/overview-ruler--timer (cancel-timer mp/overview-ruler--timer))
    (setq mp/overview-ruler--timer nil)
    (remove-hook 'window-configuration-change-hook #'mp/overview-ruler--refresh)
    (let ((win (get-buffer-window mp/overview-ruler--buffer-name t)))
      (when (window-live-p win) (delete-window win)))
    (when (get-buffer mp/overview-ruler--buffer-name)
      (kill-buffer mp/overview-ruler--buffer-name))))

(map! :leader :desc "Overview ruler" "t o" #'mp/overview-ruler-mode)

;; On by default once Emacs has settled, but only when SVG is available so a
;; non-SVG build doesn't trip the mode's `user-error' during startup.
(add-hook 'doom-after-init-hook
          (lambda ()
            (when (image-type-available-p 'svg)
              (mp/overview-ruler-mode 1))))

(provide 'overview-ruler)
;;; overview-ruler.el ends here
