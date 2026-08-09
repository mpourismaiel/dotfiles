;;; svg-header.el --- Tall SVG-rendered header line with breadcrumbs  -*- lexical-binding: t; -*-
;;; Commentary:
;; Replaces the header line with a fixed-height header rendered via SVG:
;; file name + major mode, project/imenu breadcrumbs, VCS and diagnostics.
;;
;; Vanilla Emacs port of the Doom package of the same name.  No leader-key
;; bindings live here (none existed in the Doom version either); commands
;; keep their original mp/header-svg-cmd-* names for external bindings.
;;; Code:

(require 'subr-x)
(require 'seq)
(require 'cl-lib)

(use-package breadcrumb
  :defer t
  :init
  (setq breadcrumb-project-max-length 0.42
        breadcrumb-imenu-max-length 0.36
        breadcrumb-project-crumb-separator " / "
        breadcrumb-imenu-crumb-separator " > "))

(defvar mp/header-line-height 32
  "Target height of the custom header line, in pixels.")

(defvar mp/header-line-horizontal-padding " "
  "Horizontal padding inserted around each header line block.")

(defvar mp/header-line-buffer-foreground-faces
  '(mode-line-buffer-id mode-line)
  "Faces whose foreground is reused for header file and major-mode text.")

(defvar mp/header-line-position-foreground-faces
  '(mode-line line-number)
  "Faces whose foreground is reused for the header status text.")

;; Doom's `custom-set-faces!' -> plain face tweak.
(set-face-attribute 'header-line nil :inherit 'mode-line)

(defun mp/header-line-color-value (value)
  "Return VALUE unless it is an unspecified face color."
  (unless (or (null value)
              (eq value 'unspecified)
              (and (stringp value)
                   (string-prefix-p "unspecified-" value)))
    value))

(defun mp/header-line-face-attribute (face attribute)
  "Return FACE ATTRIBUTE after resolving inheritance where possible."
  (when (facep face)
    (mp/header-line-color-value
     (face-attribute face attribute nil 'default))))

(defun mp/header-line-first-face-attribute (faces attribute fallback)
  "Return the first usable ATTRIBUTE from FACES, or FALLBACK."
  (or (catch 'value
        (dolist (face faces)
          (when-let ((value (mp/header-line-face-attribute face attribute)))
            (throw 'value value))))
      (mp/header-line-color-value fallback)))

(defun mp/header-line-background ()
  "Return the themed background color for the header line."
  (mp/header-line-first-face-attribute
   '(header-line mode-line default)
   :background
   (face-attribute 'default :background nil 'default)))

(defun mp/header-line-buffer-foreground ()
  "Return the themed modeline buffer-name foreground color."
  (mp/header-line-first-face-attribute
   mp/header-line-buffer-foreground-faces
   :foreground
   (face-attribute 'mode-line :foreground nil 'default)))

(defun mp/header-line-position-foreground ()
  "Return the themed modeline position foreground color."
  (mp/header-line-first-face-attribute
   mp/header-line-position-foreground-faces
   :foreground
   (face-attribute 'mode-line :foreground nil 'default)))

(defun mp/header-line-vertical-padding ()
  "Return vertical padding needed to approach `mp/header-line-height'."
  (if (display-graphic-p)
      (ceiling (max 0 (- mp/header-line-height (frame-char-height))) 2)
    0))

(defun mp/header-line-face (foreground background &optional weight)
  "Return a face plist for a padded header line block."
  (append
   (when foreground
     `(:foreground ,foreground))
   (when background
     `(:background ,background))
   (when weight
     `(:weight ,weight))
   (when-let ((padding (mp/header-line-vertical-padding)))
     (when (> padding 0)
       `(:box (:line-width (0 . ,padding)
               ,@(when background
                   `(:color ,background))))))))

(defun mp/header-line-block (text face)
  "Return TEXT as a padded header line block using FACE."
  (propertize
   (concat mp/header-line-horizontal-padding
           text
           mp/header-line-horizontal-padding)
   'face face))

(defun mp/header-line-buffer-name ()
  "Return the file name or buffer name for the header line."
  (or (buffer-name) ""))

(defun mp/header-line-mode-name ()
  "Return the current major mode name for the header line."
  (let ((name (string-trim (format-mode-line mode-name))))
    (if (string-empty-p name)
        "unknown"
      (downcase name))))

(defun mp/header-line-buffer-status ()
  "Return the current buffer status label."
  (cond (buffer-read-only
         "RO")
        ((buffer-modified-p)
         "W!")
        (t
         "RW")))

(defun mp/header-line-nonempty-string-p (value)
  "Return non-nil when VALUE is a non-empty string."
  (and (stringp value)
       (not (string-empty-p (string-trim (substring-no-properties value))))))

(defun mp/header-line-breadcrumbs ()
  "Return breadcrumb project and imenu context for the header line."
  (when (fboundp 'breadcrumb-project-crumbs)
    (let* ((project (ignore-errors (breadcrumb-project-crumbs)))
           (imenu (ignore-errors (breadcrumb-imenu-crumbs)))
           (crumbs (seq-filter #'mp/header-line-nonempty-string-p
                               (list project imenu))))
      (when crumbs
        (let ((padding (propertize mp/header-line-horizontal-padding
                                   'face 'header-line))
              (separator (propertize "  >  "
                                     'face (if (facep 'breadcrumb-face)
                                               'breadcrumb-face
                                             'shadow))))
          (concat padding
                  (string-join crumbs separator)
                  padding))))))

(with-eval-after-load 'flycheck
  (defun mp/flycheck-counts ()
    "Return (errors warnings infos) for current buffer."
    (let ((errors 0)
          (warnings 0)
          (infos 0))
      (dolist (err flycheck-current-errors)
        (pcase (flycheck-error-level err)
          ('error (cl-incf errors))
          ('warning (cl-incf warnings))
          ('info (cl-incf infos))))
      (list errors warnings infos)))

  (defun mp/header-line-diagnostics ()
    "Return a prominent diagnostics block for the header line."
    (when (bound-and-true-p flycheck-mode)
      (pcase-let ((`(,errors ,warnings ,infos) (mp/flycheck-counts)))
        (cond
         ((> errors 0)
          (mp/header-line-block
           (format "E:%d W:%d" errors warnings)
           (mp/header-line-face "#ffffff" "#ff5370" 'bold)))
         ((> warnings 0)
          (mp/header-line-block
           (format "W:%d" warnings)
           (mp/header-line-face "#1f2430" "#ffcb6b" 'bold)))
         ((> infos 0)
          (mp/header-line-block
           (format "I:%d" infos)
           (mp/header-line-face "#ffffff" "#82aaff" 'bold))))))))

(defun mp/header-line-format ()
  "Return a left-aligned custom header line for the current buffer."
  (let* ((background (mp/header-line-background))
         (buffer-foreground (mp/header-line-buffer-foreground))
         (breadcrumbs (mp/header-line-breadcrumbs))
         (status-background "#ecbe7b")
         (status-foreground "#ffffff")
         (status-face (mp/header-line-face status-foreground status-background 'bold))
         (buffer-face (mp/header-line-face buffer-foreground background 'bold))
         (major-face (mp/header-line-face buffer-foreground background 'normal)))
    (delq nil
          (list
           (mp/header-line-block (mp/header-line-buffer-status) status-face)
           (or breadcrumbs
               (mp/header-line-block (mp/header-line-buffer-name) buffer-face))
           (mp/header-line-block (mp/header-line-mode-name) major-face)
           (when (fboundp 'mp/header-line-diagnostics)
             (mp/header-line-diagnostics))))))

;; A single screen area (tab/header/mode line) is always ONE screen row --
;; embedding "\n" only shows ^J.  To get genuinely multiple lines we rasterize
;; the text into an SVG image and hand that image to `header-line-format' via a
;; `display' property; the tall image glyph makes the header line as many lines
;; tall as the SVG.  GUI frames only (needs image support).
(require 'svg)

(defconst mp/header-svg-nbsp (char-to-string #xA0)
  "No-break space; used so SVG text keeps every space (SVG collapses ASCII).")

(defvar mp/header-svg-max-parents 8
  "Maximum number of parent (context) lines shown under the header line.")

(defvar mp/header-svg-font-size 16
  "SVG header font size, in pixels.  When nil, derived from the frame font.")

(defvar mp/header-svg-line-number-width 4
  "Minimum width, in characters, of the simulated line-number gutter.")

(defvar mp/header-svg-extra-line-spacing nil
  "Extra pixels of leading between SVG header lines.
When nil, the buffer's `line-spacing' is used so rows match real text.")

(defvar mp/header-svg-accent-color nil
  "Fill color of the status pill.  When nil, the theme's yellow accent.")

(defvar mp/header-svg-project-color nil
  "Foreground of the project name.  When nil, a darker theme grey.")

(defun mp/header-svg-theme-color (key fallback)
  "Return a theme color approximating Doom palette KEY, or FALLBACK.

The Doom original asked `doom-color'; here KEY is mapped onto standard
faces (warning/error/shadow) and falls back to FALLBACK when the face
gives no usable color."
  (let* ((spec (pcase key
                 ('yellow '(warning . :foreground))
                 ('orange '(warning . :foreground))
                 ('red    '(error . :foreground))
                 ((or 'base5 'base7) '(shadow . :foreground))
                 ('base3  '(mode-line . :background))))
         (color (and spec
                     (mp/header-line-color-value
                      (face-attribute (car spec) (cdr spec) nil t)))))
    (or color fallback)))

(defun mp/header-svg-accent ()
  "Resolve the status-pill accent (yellow) color."
  (or mp/header-svg-accent-color
      (mp/header-svg-theme-color 'yellow "#ecbe7b")))

(defun mp/header-svg-project-fg ()
  "Resolve the project name's (darker) color."
  (or mp/header-svg-project-color
      (mp/header-svg-theme-color 'base5
       (or (face-attribute 'shadow :foreground nil t) "#5c6370"))))

(defvar mp/header-svg-icon-color nil
  "Foreground of the action-button icons.  When nil, a theme grey.")

(defun mp/header-svg-button-bg ()
  "Resolve the action buttons' dark background (distinct from the SVG bg)."
  (mp/header-svg-theme-color 'base3
   (or (face-attribute 'mode-line :background nil t) "#2a2e38")))

(defun mp/header-svg-icon-fg ()
  "Resolve the action-button icon color (a theme grey)."
  (or mp/header-svg-icon-color
      (mp/header-svg-theme-color 'base7
       (or (face-attribute 'shadow :foreground nil t) "#9ca0b0"))))

(defun mp/header-svg-icon (set name fallback)
  "Return (GLYPH . FAMILY) for nerd-icons SET/NAME, or (FALLBACK . nil)."
  (or (ignore-errors
        (let* ((fn (intern (format "nerd-icons-%s" set)))
               (s (and (fboundp fn) (funcall fn name))))
          (when (and (stringp s) (> (length s) 0))
            (cons (substring-no-properties s)
                  (mp/header-svg-face-attr (get-text-property 0 'face s)
                                           :family)))))
      (cons fallback nil)))

(defun mp/header-svg-cmd-dirvish ()
  "Open Dirvish (or Dired) at the buffer's directory."
  (interactive)
  (cond ((fboundp 'dirvish) (dirvish default-directory))
        ((fboundp 'dired-jump) (dired-jump))
        (t (dired default-directory))))

(defun mp/header-svg-cmd-terminal ()
  "Run whatever command is bound to \\`C-\\=`' (the terminal toggle)."
  (interactive)
  (let ((cmd (key-binding (kbd "C-`"))))
    (if (commandp cmd)
        (call-interactively cmd)
      (message "No C-` terminal binding"))))

(defun mp/header-svg-cmd-magit ()
  "Open Magit for the current project."
  (interactive)
  (if (fboundp 'magit-status)
      (call-interactively 'magit-status)
    (message "Magit is not available")))

(defun mp/header-svg-cmd-agent ()
  "Start agent-shell."
  (interactive)
  (if (fboundp 'agent-shell)
      (call-interactively 'agent-shell)
    (message "agent-shell is not available")))

(defvar mp/header-svg-buttons
  '(("octicon" "nf-oct-file_directory" "D" mp/header-svg-cmd-dirvish)
    ("octicon" "nf-oct-terminal"       ">" mp/header-svg-cmd-terminal)
    ("octicon" "nf-oct-git_branch"     "G" mp/header-svg-cmd-magit)
    ("mdicon"  "nf-md-robot"           "A" mp/header-svg-cmd-agent))
  "Right-side SVG header buttons: (NERD-SET ICON-NAME FALLBACK COMMAND).")

(defvar-local mp/header-svg-rows nil
  "Click geometry for the current SVG header.
A list (PAD-Y LINE-H (TARGET-LINE ...) ((X0 X1 COMMAND) ...)): row 0 is the
header line (whose BUTTON boxes are the 4th element); rows 1.. map to the
parent target lines.")

(defun mp/header-svg-click (event)
  "Move point to the parent line clicked in the SVG header, and recenter."
  (interactive "e")
  (let* ((posn (event-start event))
         (win (posn-window posn))
         (xy (posn-object-x-y posn)))
    (when (and (windowp win) xy)
      (with-selected-window win
        (let* ((geom mp/header-svg-rows)
               (pad-y (nth 0 geom))
               (line-h (nth 1 geom))
               (targets (nth 2 geom))
               (buttons (nth 3 geom))
               (dx (car xy))
               (dy (cdr xy)))
          (when (and pad-y line-h (> line-h 0))
            (let ((row (floor (- dy pad-y) line-h)))
              (cond
               ;; row 0: an action button?
               ((= row 0)
                (let ((hit (seq-find (lambda (b) (and (>= dx (nth 0 b))
                                                      (< dx (nth 1 b))))
                                     buttons)))
                  (when hit (call-interactively (nth 2 hit)))))
               ;; rows 1..: jump to that parent line
               ((and (>= row 1) (<= row (length targets)))
                (let ((target (nth (1- row) targets)))
                  (when target
                    (push-mark)
                    (goto-char (point-min))
                    (forward-line (1- target))
                    (recenter))))))))))))

(defvar mp/header-svg-keymap
  (let ((map (make-sparse-keymap)))
    (define-key map [header-line mouse-1] #'mp/header-svg-click)
    map)
  "Keymap on the SVG header line, enabling click-to-jump on parent rows.")

(defun mp/header-svg-project ()
  "Return the current project's name.

Always non-empty: falls back to the buffer's directory name so the project
slot is always shown."
  (or (ignore-errors
        (cond ((fboundp 'projectile-project-name)
               (let ((n (projectile-project-name)))
                 (unless (member n '(nil "" "-")) n)))
              ((and (fboundp 'project-current) (project-current))
               (project-name (project-current)))))
      (ignore-errors
        (let ((dir (or (and buffer-file-name
                            (file-name-directory buffer-file-name))
                       default-directory)))
          (file-name-nondirectory (directory-file-name dir))))
      "scratch"))

(defun mp/header-svg-filename ()
  "Return the buffer's file name (sans directory) or its buffer name."
  (if buffer-file-name (file-name-nondirectory buffer-file-name) (buffer-name)))

(defun mp/header-svg-error-text ()
  "Return (TEXT BG FG) for the flycheck error counter pill, or nil if none.

Only the non-zero of E/W is shown.  Any errors make it a red pill with white
text (to grab attention); warnings alone make an amber pill with dark text."
  (when (and (bound-and-true-p flycheck-mode) (fboundp 'mp/flycheck-counts))
    (pcase-let ((`(,errors ,warnings ,_infos) (mp/flycheck-counts)))
      (let ((parts (append (when (> errors 0) (list (format "E:%d" errors)))
                           (when (> warnings 0) (list (format "W:%d" warnings))))))
        (when parts
          (if (> errors 0)
              (list (string-join parts " ")
                    (mp/header-svg-theme-color 'red "#ff5370") "#ffffff")
            (list (string-join parts " ")
                  (mp/header-svg-theme-color 'orange "#ffcb6b")
                  (or (mp/header-line-background) "#1a1b26"))))))))

(defun mp/header-svg-logical-start ()
  "Move point to the first line of the statement owning the current line.

Climbs out of any still-open bracket so a continuation or closing line of a
multi-line statement (e.g. a Python signature's \"):\") resolves to the line
that opened it (the \"def ... (\")."
  (beginning-of-line)
  (let ((ppss (syntax-ppss (point)))
        (guard 0))
    (while (and (nth 1 ppss) (> (nth 0 ppss) 0) (< guard 200))
      (goto-char (nth 1 ppss))
      (beginning-of-line)
      (setq ppss (syntax-ppss (point))
            guard (1+ guard)))
    (beginning-of-line)))

(defun mp/header-svg-parent-lines ()
  "Return the off-screen parent/context lines for the current buffer.

Dispatches by mode: code structure in `prog-mode', outline ancestors in
`org-mode', and nothing elsewhere (so shells, magit, etc. show no context)."
  (cond ((derived-mode-p 'prog-mode) (mp/header-svg-prog-parents))
        ((derived-mode-p 'org-mode) (mp/header-svg-org-parents))
        (t nil)))

(defun mp/header-svg-org-parents ()
  "Return the off-screen ancestor Org headings of point, top to bottom."
  (when (derived-mode-p 'org-mode)
    (save-excursion
      (let ((win-start-line (line-number-at-pos (window-start)))
            (headings nil))
        (when (ignore-errors (org-back-to-heading t) t)
          (cl-flet ((grab ()
                      (let ((beg (line-beginning-position))
                            (end (line-end-position)))
                        (when (fboundp 'font-lock-ensure)
                          (ignore-errors (font-lock-ensure beg end)))
                        (cons (line-number-at-pos) (buffer-substring beg end)))))
            (push (grab) headings)
            (while (ignore-errors (org-up-heading-safe))
              (push (grab) headings))))
        (let ((offscreen (seq-filter (lambda (p) (< (car p) win-start-line))
                                     headings)))
          (if (> (length offscreen) mp/header-svg-max-parents)
              (nthcdr (- (length offscreen) mp/header-svg-max-parents) offscreen)
            offscreen))))))

(defun mp/header-svg-prog-parents ()
  "Return the off-screen enclosing lines of the current line.

Walks upward collecting non-blank lines of strictly decreasing indentation
(the block openers around point), resolving each to the opening line of its
statement, then keeps only those scrolled above the window's top.  Returns a
list of (LINE-NUMBER . PROPERTIZED-TEXT), ordered top to bottom, at most
`mp/header-svg-max-parents' long."
  (when (derived-mode-p 'prog-mode)
    (save-excursion
      (let ((win-start-line (line-number-at-pos (window-start)))
            (parents nil))
        (beginning-of-line)
        (let ((min-indent (current-indentation)))
          (while (and (> (line-number-at-pos) 1) (> min-indent 0))
            (forward-line -1)
            (unless (looking-at-p "[ \t]*$")
              (let ((indent (current-indentation)))
                (when (< indent min-indent)
                  ;; Resolve to the statement's opening line so multi-line
                  ;; definitions show the signature, not their closing ")".
                  (save-excursion
                    (mp/header-svg-logical-start)
                    (let ((beg (line-beginning-position))
                          (end (line-end-position))
                          (lnum (line-number-at-pos))
                          (lind (current-indentation)))
                      (setq min-indent (min indent lind))
                      (when (fboundp 'font-lock-ensure)
                        (ignore-errors (font-lock-ensure beg end)))
                      (unless (assq lnum parents)
                        (push (cons lnum (buffer-substring beg end))
                              parents)))))))))
        (let ((offscreen (seq-filter (lambda (p) (< (car p) win-start-line))
                                     parents)))
          (if (> (length offscreen) mp/header-svg-max-parents)
              (nthcdr (- (length offscreen) mp/header-svg-max-parents) offscreen)
            offscreen))))))

(defun mp/header-svg-cell (svg text x baseline cw fg weight family font-size)
  "Draw TEXT at X on the monospace CW grid; return the X past it.

Every space becomes a no-break space and the run is pinned to LEN*CW via
textLength/lengthAdjust, so glyph advance can never drift off the grid."
  (let ((w (* (length text) cw)))
    (when (> (length text) 0)
      (svg-text svg (replace-regexp-in-string " " mp/header-svg-nbsp text)
                :x x :y baseline :fill fg
                :font-family family :font-size font-size :font-weight weight
                :textLength (max 1 w) :lengthAdjust "spacingAndGlyphs"))
    (+ x w)))

(defvar mp/header-svg-cache nil
  "Cons of (KEY . IMAGE) memoizing the rendered header SVG.")

(defun mp/header-svg-face-attr (face attr)
  "Resolve ATTR (e.g. :foreground) from a `face' text-property value FACE.

FACE may be nil, an anonymous plist, a named face symbol, or a list of any
of those (earlier entries win, as in face merging).  Returns nil when the
attribute is unspecified so callers can fall back to a default."
  (cond
   ((null face) nil)
   ((keywordp (car-safe face)) (plist-get face attr))
   ((symbolp face)
    (let ((v (face-attribute face attr nil t)))
      (unless (memq v '(nil unspecified)) v)))
   ((consp face)
    (catch 'value
      (dolist (f face)
        (let ((v (mp/header-svg-face-attr f attr)))
          (when v (throw 'value v))))))
   (t nil)))

(defun mp/header-svg-weight (face)
  "Return an SVG font-weight string (\"bold\"/\"normal\") for FACE."
  (if (memq (mp/header-svg-face-attr face :weight)
            '(bold semi-bold demibold extra-bold ultra-bold black heavy))
      "bold"
    "normal"))

(defun mp/header-svg-runs (str)
  "Split STR into a list of (TEXT . FACE) runs of constant highlighting.

Considers both `face' and `font-lock-face' so syntax-highlighted buffer
text (jit-lock uses either) is grouped correctly."
  (let ((runs nil) (i 0) (len (length str)))
    (while (< i len)
      (let* ((face (or (get-text-property i 'face str)
                       (get-text-property i 'font-lock-face str)))
             (n1 (next-single-property-change i 'face str))
             (n2 (next-single-property-change i 'font-lock-face str))
             (next (min (or n1 len) (or n2 len))))
        (push (cons (substring-no-properties str i next) face) runs)
        (setq i next)))
    (nreverse runs)))

(defun mp/header-svg-expand-tabs (text)
  "Expand TAB characters in TEXT to `tab-width' spaces for SVG rendering."
  (if (string-search "\t" text)
      (replace-regexp-in-string "\t" (make-string tab-width ?\s) text)
    text))

(defun mp/header-svg-image ()
  "Return an SVG image for the header line.

Line 1: a centered status pill (RW/W!/RO), the project name, the file name,
and -- right-aligned -- the flycheck error count (omitted when clean).
Lines below: the current line's off-screen parent lines, with their real
syntax highlighting and a simulated line-number gutter."
  (let* ((width (max 1 (window-pixel-width)))
         (status (mp/header-line-buffer-status))
         (project (mp/header-svg-project))
         (filename (mp/header-svg-filename))
         (err (mp/header-svg-error-text))
         (parents (mp/header-svg-parent-lines))
         (fh (frame-char-height))
         (cw (frame-char-width))
         (font-size (or mp/header-svg-font-size
                        (ignore-errors (default-font-height))
                        (round (* cw 1.7))))
         (line-spacing-px
          (or mp/header-svg-extra-line-spacing
              (let ((ls (bound-and-true-p line-spacing)))
                (cond ((integerp ls) ls)
                      ((floatp ls) (round (* ls fh)))
                      (t 0)))))
         (line-h (+ fh line-spacing-px))
         (base-off (round (+ (/ (- line-h font-size) 2.0)
                             (* font-size 0.8))))
         (pad-x 8)
         (pad-y 4)
         (baseline0 (+ pad-y base-off))
         ;; fixed-size rounded pill / button metrics
         (pill-h (round (* fh 0.86)))
         (pill-y (+ pad-y (max 0 (/ (- line-h pill-h) 2))))
         (pill-rx (round (* pill-h 0.32)))
         (pill-w (max (round (* cw 3.4)) (+ (* (length status) cw) cw)))
         (bw (+ (round (* fh 1.2)) 4))
         (btn-h (+ pill-h 4))
         (btn-y (- pill-y 2))
         (gap-btn (max 2 (round (* cw 0.35))))
         (err-pad (round (* cw 0.5)))
         (err-w (if err (+ (* (length (nth 0 err)) cw) (* 2 err-pad)) 0))
         (err-gap cw)
         (nbtn (length mp/header-svg-buttons))
         (buttons-w (+ (* nbtn bw) (* (max 0 (1- nbtn)) gap-btn)))
         (cluster-w (+ (if err (+ err-w err-gap) 0) buttons-w))
         (cluster-x (max pad-x (- width pad-x cluster-w)))
         (btn-x0 (+ cluster-x (if err (+ err-w err-gap) 0)))
         (button-boxes
          (let ((res nil) (bi 0))
            (dolist (bdef mp/header-svg-buttons)
              (let ((bx (+ btn-x0 (* bi (+ bw gap-btn)))))
                (push (list bx (+ bx bw) (nth 3 bdef)) res))
              (setq bi (1+ bi)))
            (nreverse res)))
         (sig (list width status project filename err
                    (mapcar (lambda (p)
                              (cons (car p) (substring-no-properties (cdr p))))
                            parents))))
    ;; Remember geometry so a click maps back to a parent line or a button.
    (setq mp/header-svg-rows
          (list pad-y line-h (mapcar #'car parents) button-boxes))
    (if (and mp/header-svg-cache (equal (car mp/header-svg-cache) sig))
        (cdr mp/header-svg-cache)
      (let* ((bg (or (mp/header-line-background) "#1a1b26"))
             (fg (or (mp/header-line-buffer-foreground) "#c0caf5"))
             (dim (or (mp/header-line-position-foreground) "#7f8496"))
             (linenum-fg (or (face-attribute 'line-number :foreground nil t) dim))
             (accent (mp/header-svg-accent))
             (project-fg (mp/header-svg-project-fg))
             (btn-bg (mp/header-svg-button-bg))
             (icon-fg (mp/header-svg-icon-fg))
             (family (or (face-attribute 'default :family nil 'default)
                         "monospace"))
             (gap cw)
             (nlines (1+ (length parents)))
             (height (+ (* 2 pad-y) (* nlines line-h)))
             (svg (svg-create width height)))
        (svg-rectangle svg 0 0 width height :fill bg)
        ;; ---- line 1: status pill, project, filename ----
        (let* ((sx (+ pad-x (round (/ (- pill-w (* (length status) cw)) 2.0))))
               (x pad-x))
          (svg-rectangle svg pad-x pill-y pill-w pill-h :fill accent :rx pill-rx)
          (mp/header-svg-cell svg status sx baseline0 cw bg "bold" family font-size)
          (setq x (+ pad-x pill-w gap))
          ;; project: always shown, darker, ~1px smaller, 16px right margin
          (let* ((pfs (max 8 (1- font-size)))
                 (pcw (max 1 (round (* cw (/ (float pfs) font-size))))))
            (setq x (mp/header-svg-cell svg project x baseline0 pcw
                                        project-fg "normal" family pfs))
            (setq x (+ x 16)))
          (mp/header-svg-cell svg filename x baseline0 cw fg "bold" family font-size))
        ;; ---- right cluster: error pill + action buttons ----
        (when err
          (svg-rectangle svg cluster-x pill-y err-w pill-h
                         :fill (nth 1 err) :rx pill-rx)
          (mp/header-svg-cell svg (nth 0 err) (+ cluster-x err-pad) baseline0 cw
                              (nth 2 err) "bold" family font-size))
        (cl-loop for bdef in mp/header-svg-buttons
                 for box in button-boxes
                 do (let* ((bx (nth 0 box))
                           (icon (mp/header-svg-icon (nth 0 bdef) (nth 1 bdef)
                                                     (nth 2 bdef)))
                           (glyph (car icon))
                           (ifam (or (cdr icon) family)))
                      (svg-rectangle svg bx btn-y bw btn-h :fill btn-bg :rx pill-rx)
                      (svg-text svg glyph
                                :x (+ bx (round (/ bw 2.0))) :y baseline0
                                :fill icon-fg :font-family ifam
                                :font-size (max 6 (- font-size 2))
                                :text-anchor "middle")))
        ;; ---- parent context lines with a line-number gutter ----
        (when parents
          (let* ((gutter (max mp/header-svg-line-number-width
                              (apply #'max (mapcar (lambda (p)
                                                     (length (number-to-string (car p))))
                                                   parents))))
                 (gutter-px (* gutter cw))
                 (i 1))
            (dolist (p parents)
              (let* ((baseline (+ pad-y (* i line-h) base-off))
                     (num (number-to-string (car p)))
                     ;; right-align the number in the gutter (pad on the left)
                     (num-x (+ pad-x (- gutter-px (* (length num) cw))))
                     (x (+ pad-x gutter-px)))
                (mp/header-svg-cell svg num num-x baseline cw
                                    linenum-fg "normal" family font-size)
                (setq x (mp/header-svg-cell svg "  " x baseline cw
                                            linenum-fg "normal" family font-size))
                (dolist (run (mp/header-svg-runs (cdr p)))
                  (let* ((rtext (mp/header-svg-expand-tabs (car run)))
                         (rface (cdr run))
                         (rfg (or (mp/header-svg-face-attr rface :foreground) fg))
                         (rweight (mp/header-svg-weight rface)))
                    (setq x (mp/header-svg-cell svg rtext x baseline cw
                                                rfg rweight family font-size))))
                (setq i (1+ i))))))
        (let ((img (svg-image svg :ascent 'center :scale 1)))
          (setq mp/header-svg-cache (cons sig img))
          img)))))

(defun mp/header-svg-format ()
  "Header-line construct rendering the multi-line SVG (text fallback in TTY)."
  (if (display-graphic-p)
      (propertize " " 'display (mp/header-svg-image)
                  'keymap mp/header-svg-keymap
                  'pointer 'hand)
    (mp/header-line-format)))

(setq-default tab-line-format nil)
(setq-default header-line-format '(:eval (mp/header-svg-format)))

(provide 'svg-header)
;;; svg-header.el ends here
