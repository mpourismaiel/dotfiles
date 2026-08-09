;;; workspace-hud.el --- Floating SVG workspace HUD (child frame)  -*- lexical-binding: t; -*-
;;; Commentary:
;; A togglable, pretty workspace HUD that floats on the RIGHT edge of the frame
;; as a borderless, non-focusable child frame — a real layer on top of your
;; windows, not a window in the tree (so magit/splits/other-window never touch
;; it).  Its content is rendered as a single SVG image (same technique as the
;; svg-header package), so the styling is pixel-precise and theme-derived.
;;
;; It shows, for the buffer you are actually looking at:
;;   - project / git branch (+ahead/behind) / dirty diff stats
;;   - the changed files, indented under Dirty, with per-file lines changed
;;   - LSP status / diagnostics count
;;   - active major mode
;;
;; It refreshes only when something happens (buffer switch, save, diagnostics,
;; mode change, frame resize) on a tiny idle debounce — never on a periodic
;; timer.  GUI only (child frames need a graphical frame).
;;
;; Toggle with `mp/workspace-hud-toggle'.
;;
;; Vanilla-Emacs port notes (from the Doom-era package):
;;   - No keybinding is defined here; SPC t W is bound to
;;     `mp/workspace-hud-toggle' in lisp/mp-keys.el.
;;   - The Health/LSP probe reports lsp-bridge (`lsp-bridge-mode') and eglot
;;     (`eglot--managed-mode' / `eglot-current-server') instead of lsp-mode.
;;   - Everything else (agent-shell, dape, magit auto-hide) is unchanged; all
;;     optional integrations remain guarded with `fboundp'/`boundp' so elpaca's
;;     deferred packages never break loading.
;;; Code:

(require 'cl-lib)
(require 'color)
(require 'map)
(require 'subr-x)

;; Optional integrations — all calls are guarded at runtime with `fboundp'.
(declare-function agent-shell-buffers "agent-shell")
(declare-function agent-shell-status "agent-shell")
(declare-function agent-shell-get-model-name "agent-shell")
(declare-function agent-shell-get-thought-level-name "agent-shell")
(declare-function dape--config-mode-p "dape")
(declare-function dape--live-connection "dape")
(declare-function dape--state "dape")
(declare-function dape--state-reason "dape")
(declare-function dape--current-stack-frame "dape")
(declare-function eglot-current-server "eglot")

(defgroup mp/workspace-hud nil
  "Floating SVG workspace HUD."
  :group 'convenience
  :prefix "mp/workspace-hud-")

(defcustom mp/workspace-hud-width 360
  "Width of the HUD child frame, in pixels."
  :type 'integer :group 'mp/workspace-hud)

(defcustom mp/workspace-hud-git-ttl 1.5
  "Seconds to cache git results per repo root (busted on save)."
  :type 'number :group 'mp/workspace-hud)

(defcustom mp/workspace-hud-max-files 14
  "Maximum number of changed files to list before summarising the rest."
  :type 'integer :group 'mp/workspace-hud)


(defconst mp/workspace-hud--buffer-name " *workspace-hud*")

(defcustom mp/workspace-hud-debug nil
  "When non-nil, log HUD internals to the *workspace-hud-log* buffer."
  :type 'boolean :group 'mp/workspace-hud)

(defvar mp/workspace-hud--frame nil "The live child frame, or nil.")
(defvar mp/workspace-hud--parent nil "The parent frame the HUD is docked onto.")
(defvar mp/workspace-hud--enabled nil
  "Non-nil when the user has the HUD on (it may still be auto-hidden).")
(defvar mp/workspace-hud--tick nil "1s timer that ticks while an agent is busy.")
(defvar mp/workspace-hud--agent-busy (make-hash-table :test 'eq)
  "Agent-shell buffer -> time its current busy/blocked run started.")
(defvar-local mp/workspace-hud--buttons nil
  "List of (X0 Y0 X1 Y1 . ACTION) clickable regions for the current render.")

(defun mp/workspace-hud--log (fmt &rest args)
  "Append a timestamped FMT/ARGS line to the debug log when enabled."
  (when mp/workspace-hud-debug
    (let ((line (apply #'format fmt args)))
      (with-current-buffer (get-buffer-create "*workspace-hud-log*")
        (goto-char (point-max))
        (insert (format-time-string "[%H:%M:%S.%3N] ") line "\n")))))
(defvar mp/workspace-hud--pending nil "One-shot debounce timer, or nil.")
(defvar mp/workspace-hud--git-cache (make-hash-table :test 'equal)
  "ROOT -> (TIMESTAMP BRANCH UPSTREAM CHANGES FILES).")

;; ---------------------------------------------------------------------------
;; Theme-derived palette
;; ---------------------------------------------------------------------------

(defun mp/workspace-hud--color (face attr fallback)
  "FACE's ATTR as a usable color string, or FALLBACK."
  (let ((c (face-attribute face attr nil t)))
    (if (and (stringp c)
             (not (string-prefix-p "unspecified" c))
             (color-defined-p c))
        c fallback)))

(defun mp/workspace-hud--blend (a b ratio)
  "Blend hex/name colors A and B, RATIO toward B, as #rrggbb."
  (let ((ca (color-name-to-rgb a))
        (cb (color-name-to-rgb b)))
    (if (and ca cb)
        (apply #'color-rgb-to-hex
               (append (cl-mapcar (lambda (x y) (+ (* x (- 1 ratio)) (* y ratio))) ca cb)
                       (list 2)))
      a)))

(defun mp/workspace-hud--palette ()
  "Return a plist of colors + font family derived from the current theme."
  ;; `success' / `warning' / `error' are standard Emacs faces (also what the
  ;; Doom version used), so nothing to translate here.
  (let* ((bg (mp/workspace-hud--color 'default :background "#1b1e26"))
         (fg (mp/workspace-hud--color 'default :foreground "#e4e7f1")))
    (list :bg      (mp/workspace-hud--blend bg fg 0.05)   ; panel card
          :fg      fg
          :heading (mp/workspace-hud--blend bg fg 0.60)   ; section headers + files
          :muted   (mp/workspace-hud--blend bg fg 0.42)
          :faint   (mp/workspace-hud--blend bg fg 0.30)
          :border  (mp/workspace-hud--blend bg fg 0.22)
          :ok     (mp/workspace-hud--color 'success             :foreground "#98be65")
          :warn   (mp/workspace-hud--color 'warning             :foreground "#ecbe7b")
          :err    (mp/workspace-hud--color 'error               :foreground "#ff6c6b")
          :accent (mp/workspace-hud--color 'font-lock-keyword-face :foreground "#7aa2f7")
          :family (or (face-attribute 'default :family nil t) "monospace"))))

(defun mp/workspace-hud--status-color (pal status)
  "Return the color in PAL for STATUS string."
  (pcase status
    ("ok"   (plist-get pal :ok))
    ("warn" (plist-get pal :warn))
    ("err"  (plist-get pal :err))
    (_      (plist-get pal :muted))))

;; ---------------------------------------------------------------------------
;; Data collection (git / health / buffer)
;; ---------------------------------------------------------------------------

(defun mp/workspace-hud--repo-root (&optional dir)
  "Return the git repo root for DIR (or `default-directory'), or nil."
  (let ((default-directory (or dir default-directory)))
    (or (ignore-errors (vc-root-dir))
        (locate-dominating-file default-directory ".git"))))

(defun mp/workspace-hud--git (root &rest args)
  "Run git ARGS in ROOT, returning trimmed stdout or nil."
  (let ((default-directory (file-name-as-directory root)))
    (ignore-errors
      (with-temp-buffer
        (when (eq 0 (apply #'process-file "git" nil t nil args))
          (string-trim (buffer-string)))))))

(defun mp/workspace-hud--upstream (root)
  "Return an ahead/behind display string for ROOT, or an empty string."
  (let ((out (mp/workspace-hud--git
              root "rev-list" "--left-right" "--count" "@{upstream}...HEAD")))
    (if (and out (string-match "\\`\\([0-9]+\\)[[:space:]]+\\([0-9]+\\)\\'" out))
        (let ((behind (string-to-number (match-string 1 out)))
              (ahead  (string-to-number (match-string 2 out)))
              parts)
          (when (> ahead 0)  (push (format "↑%d" ahead) parts))
          (when (> behind 0) (push (format "↓%d" behind) parts))
          (if parts (mapconcat #'identity (nreverse parts) " ") "synced"))
      "")))

(defun mp/workspace-hud--numstat (out)
  "Return (INSERTIONS . DELETIONS) from git numstat OUT."
  (let ((ins 0) (del 0))
    (dolist (line (and out (split-string out "\n" t)))
      (let ((cols (split-string line "\t")))
        (when (>= (length cols) 2)
          (when (string-match-p "\\`[0-9]+\\'" (nth 0 cols))
            (cl-incf ins (string-to-number (nth 0 cols))))
          (when (string-match-p "\\`[0-9]+\\'" (nth 1 cols))
            (cl-incf del (string-to-number (nth 1 cols)))))))
    (cons ins del)))

(defun mp/workspace-hud--changes (root)
  "Return human-readable change stats for ROOT (e.g. \"+2 -17\")."
  (let* ((u (mp/workspace-hud--numstat (mp/workspace-hud--git root "diff" "--numstat" "--" ".")))
         (s (mp/workspace-hud--numstat (mp/workspace-hud--git root "diff" "--cached" "--numstat" "--" ".")))
         (ins (+ (car u) (car s)))
         (del (+ (cdr u) (cdr s)))
         (n (length (split-string (or (mp/workspace-hud--git root "status" "--porcelain") "") "\n" t))))
    (cond ((or (> ins 0) (> del 0)) (format "+%d -%d" ins del))
          ((> n 0) (format "%d file%s" n (if (= n 1) "" "s")))
          (t "clean"))))

(defun mp/workspace-hud--changed-files (root)
  "Return a list of (PATH INS DEL) for ROOT's changed files.
Tracked changes (staged + unstaged) come from `git diff --numstat HEAD'; INS/DEL
are numbers, or nil for binary.  Untracked files come out as (PATH new nil)."
  (let ((files '()))
    (dolist (line (split-string (or (mp/workspace-hud--git root "diff" "--numstat" "HEAD") "") "\n" t))
      (let ((cols (split-string line "\t")))
        (when (>= (length cols) 3)
          (push (list (nth 2 cols)
                      (and (string-match-p "\\`[0-9]+\\'" (nth 0 cols)) (string-to-number (nth 0 cols)))
                      (and (string-match-p "\\`[0-9]+\\'" (nth 1 cols)) (string-to-number (nth 1 cols))))
                files))))
    (dolist (path (split-string (or (mp/workspace-hud--git root "ls-files" "--others" "--exclude-standard") "") "\n" t))
      (push (list path 'new nil) files))
    (nreverse files)))

(defun mp/workspace-hud--git-info (root)
  "Return (BRANCH UPSTREAM CHANGES FILES) for ROOT, cached briefly.
Cache lifetime is `mp/workspace-hud-git-ttl' seconds."
  (let ((entry (gethash root mp/workspace-hud--git-cache))
        (now (float-time)))
    (if (and entry (< (- now (car entry)) mp/workspace-hud-git-ttl))
        (cdr entry)
      (let* ((branch (or (mp/workspace-hud--git root "rev-parse" "--abbrev-ref" "HEAD") "—"))
             (info (list branch
                         (mp/workspace-hud--upstream root)
                         (mp/workspace-hud--changes root)
                         (mp/workspace-hud--changed-files root))))
        (puthash root (cons now info) mp/workspace-hud--git-cache)
        info))))

(defun mp/workspace-hud--lsp-backend ()
  "Return the name of the LSP backend active in the current buffer, or nil.
This config runs lsp-bridge and/or eglot (not lsp-mode); both probes are
guarded so neither package needs to be loaded."
  (cond
   ((and (bound-and-true-p eglot--managed-mode)
         (fboundp 'eglot-current-server)
         (ignore-errors (eglot-current-server)))
    "eglot")
   ((bound-and-true-p lsp-bridge-mode) "lsp-bridge")))

(defun mp/workspace-hud--lsp-status ()
  "Return \"online\"/\"offline\"/\"n/a\" for the current buffer."
  (cond
   ((mp/workspace-hud--lsp-backend) "online")
   ((derived-mode-p 'prog-mode) "offline")
   (t "n/a")))

(defun mp/workspace-hud--diagnostics ()
  "Return (ERRORS WARNINGS NOTES) for the current buffer.
Counts flycheck or flymake diagnostics (eglot reports through flymake);
lsp-bridge keeps its own diagnostic store and is not counted here."
  (cond
   ((and (bound-and-true-p flycheck-mode)
         (boundp 'flycheck-current-errors) (fboundp 'flycheck-error-level))
    (let ((e 0) (w 0) (n 0))
      (dolist (d flycheck-current-errors)
        (pcase (ignore-errors (funcall (symbol-function 'flycheck-error-level) d))
          ('error (cl-incf e)) ('warning (cl-incf w)) ((or 'info 'notice) (cl-incf n))))
      (list e w n)))
   ((and (bound-and-true-p flymake-mode) (fboundp 'flymake-diagnostics))
    (let ((e 0) (w 0) (n 0))
      (dolist (d (ignore-errors (funcall (symbol-function 'flymake-diagnostics) (point-min) (point-max))))
        (pcase (ignore-errors (funcall (symbol-function 'flymake-diagnostic-type) d))
          ((or :error 'error) (cl-incf e))
          ((or :warning 'warning) (cl-incf w))
          ((or :note :info 'note 'info) (cl-incf n))))
      (list e w n)))
   (t (list 0 0 0))))

(defun mp/workspace-hud--diag-display (e w n)
  "Format diagnostic counts E W N into a short string."
  (cond ((and (= e 0) (= w 0) (= n 0)) "0 err")
        ((and (= e 0) (= w 0)) (format "%d info" n))
        ((= e 0) (format "%d warn" w))
        ((= w 0) (format "%d err" e))
        (t (format "%dE %dW" e w))))

(defun mp/workspace-hud--collect (buf)
  "Collect all HUD fields from BUF as a plist."
  (with-current-buffer buf
    (let* ((root (mp/workspace-hud--repo-root))
           (git (and root (mp/workspace-hud--git-info root)))
           (changes (nth 2 git))
           (backend (mp/workspace-hud--lsp-backend))
           (lsp (mp/workspace-hud--lsp-status))
           (dc (mp/workspace-hud--diagnostics))
           (e (nth 0 dc)) (w (nth 1 dc)) (n (nth 2 dc))
           (major (let ((m (format-mode-line mode-name)))
                    (if (and (stringp m) (> (length m) 0))
                        (substring-no-properties m)
                      (capitalize (replace-regexp-in-string "-mode\\'" ""
                                                            (symbol-name major-mode)))))))
      (list :project (file-name-nondirectory
                      (directory-file-name (or root default-directory)))
            :root root
            :in-repo (and root t)
            :branch (or (nth 0 git) "no repo")
            :upstream (or (nth 1 git) "")
            :dirty (or changes "—")
            :dirty-status (if (and changes (not (equal changes "clean"))) "warn" "muted")
            :lsp lsp
            :lsp-label (or backend "no LSP")
            :lsp-status (cond ((string= lsp "online") "ok")
                              ((string= lsp "offline") "err")
                              (t "muted"))
            :diag (mp/workspace-hud--diag-display e w n)
            :diag-status (cond ((> e 0) "err") ((> w 0) "warn") (t "muted"))
            :major major
            :files (nth 3 git)))))

;; ---------------------------------------------------------------------------
;; Agent-shell collection
;; ---------------------------------------------------------------------------

(defun mp/workspace-hud--agent-buffers ()
  "Return live agent-shell shell buffers (not viewports)."
  (when (fboundp 'agent-shell-buffers)
    (cl-remove-if-not
     (lambda (b) (and (buffer-live-p b)
                      (with-current-buffer b (derived-mode-p 'agent-shell-mode))))
     (ignore-errors (agent-shell-buffers)))))

(defun mp/workspace-hud--agent-info (buf)
  "Collect a plist of display fields for agent-shell BUF."
  (with-current-buffer buf
    (let* ((state (and (boundp 'agent-shell--state) agent-shell--state))
           (status (or (ignore-errors (agent-shell-status :shell-buffer buf)) 'ready))
           (usage (ignore-errors (map-elt state :usage)))
           (used (ignore-errors (map-elt usage :context-used)))
           (size (ignore-errors (map-elt usage :context-size)))
           (busy (memq status '(busy blocked)))
           (since (gethash buf mp/workspace-hud--agent-busy)))
      ;; maintain the busy-since clock
      (if busy
          (unless since (setq since (current-time))
                  (puthash buf since mp/workspace-hud--agent-busy))
        (remhash buf mp/workspace-hud--agent-busy)
        (setq since nil))
      (list :name (string-trim (replace-regexp-in-string
                                "\\*" "" (buffer-name buf)))
            :model (ignore-errors (agent-shell-get-model-name state))
            :effort (ignore-errors (agent-shell-get-thought-level-name state))
            :mode (ignore-errors (map-nested-elt state '(:session :mode-id)))
            :status status
            :ctx-used used :ctx-size size
            :ctx-pct (and (numberp used) (numberp size) (> size 0)
                          (round (* 100.0 (/ (float used) size))))
            :since since))))

;; ---------------------------------------------------------------------------
;; Debugger (dape) collection
;; ---------------------------------------------------------------------------

(defun mp/workspace-hud--dape-available-p (buf)
  "Return non-nil when a dape config EXPLICITLY targets BUF's major mode.
Stricter than `dape--config-mode-p' (which matches mode-less configs), so the
Debugger section stays hidden in org/text/etc."
  (and (boundp 'dape-configs)
       (with-current-buffer buf
         (and (derived-mode-p 'prog-mode)
              (cl-some (lambda (cfg)
                         (let ((modes (plist-get (cdr cfg) 'modes)))
                           (and modes (apply #'derived-mode-p modes))))
                       dape-configs)))))

(defun mp/workspace-hud--dape-conn ()
  "Return the most relevant live dape connection, or nil."
  (when (fboundp 'dape--live-connection)
    (or (ignore-errors (dape--live-connection 'stopped t))
        (ignore-errors (dape--live-connection 'running t))
        (ignore-errors (dape--live-connection 'last t)))))

(defun mp/workspace-hud--dape-info (buf)
  "Collect a plist describing the debugger state for BUF."
  (let ((conn (mp/workspace-hud--dape-conn)))
    (if conn
        (let* ((state (ignore-errors (dape--state conn)))
               (reason (ignore-errors (dape--state-reason conn)))
               (frame (and (eq state 'stopped)
                           (ignore-errors (dape--current-stack-frame conn))))
               (src (and frame (plist-get frame :source)))
               (path (and src (plist-get src :path)))
               (line (and frame (plist-get frame :line))))
          (list :active t :state state :reason reason
                :func (and frame (plist-get frame :name))
                :where (and path line (format "%s:%s" (file-name-nondirectory path) line))))
      (list :active nil :available (and (mp/workspace-hud--dape-available-p buf) t)))))

;; ---------------------------------------------------------------------------
;; Click actions (run in the target window's context via `--run-action')
;; ---------------------------------------------------------------------------

(defun mp/workspace-hud--act-magit-status ()
  "Open magit-status for the current project."
  (if (fboundp 'magit-status) (magit-status) (message "magit not available")))

(defun mp/workspace-hud--act-magit-branch ()
  "Open magit's change-branch (checkout) interface."
  (cond ((fboundp 'magit-branch-checkout) (call-interactively 'magit-branch-checkout))
        ((fboundp 'magit-branch) (call-interactively 'magit-branch))
        (t (message "magit not available"))))

(defun mp/workspace-hud--act-commit-all ()
  "Stage everything dirty (incl. untracked) and open the magit commit buffer."
  (if (fboundp 'magit-commit-create)
      (progn (when (fboundp 'magit-stage-modified) (magit-stage-modified t))
             (magit-commit-create))
    (message "magit not available")))

(defun mp/workspace-hud--act-show-diagnostics ()
  "Open the diagnostics/error list for the current buffer."
  (cond ((and (bound-and-true-p flycheck-mode) (fboundp 'flycheck-list-errors))
         (flycheck-list-errors))
        ((fboundp 'consult-flymake) (consult-flymake))
        ((and (bound-and-true-p flymake-mode) (fboundp 'flymake-show-buffer-diagnostics))
         (flymake-show-buffer-diagnostics))
        (t (message "no diagnostics backend"))))

;; ---------------------------------------------------------------------------
;; SVG rendering
;; ---------------------------------------------------------------------------

(defun mp/workspace-hud--esc (s)
  "XML-escape string S."
  (setq s (or s ""))
  (dolist (pair '(("&" . "&amp;") ("<" . "&lt;") (">" . "&gt;") ("\"" . "&quot;")))
    (setq s (replace-regexp-in-string (regexp-quote (car pair)) (cdr pair) s t t)))
  s)

(defun mp/workspace-hud--txt (x y s size fill &rest props)
  "Return an SVG <text> node.  PROPS: :anchor :weight :spacing :opacity :family."
  (format "<text x='%s' y='%s' font-size='%s' fill='%s'%s%s%s%s%s>%s</text>"
          x y size fill
          (if-let ((a (plist-get props :anchor)))  (format " text-anchor='%s'" a) "")
          (if-let ((w (plist-get props :weight)))  (format " font-weight='%s'" w) "")
          (if-let ((l (plist-get props :spacing))) (format " letter-spacing='%s'" l) "")
          (if-let ((o (plist-get props :opacity))) (format " opacity='%s'" o) "")
          (if-let ((f (plist-get props :family)))  (format " font-family='%s'" f) "")
          (mp/workspace-hud--esc s)))

(defun mp/workspace-hud--short-path (path max)
  "Shorten PATH to at most MAX chars, keeping the file name and its parent dir."
  (if (<= (length path) max)
      path
    (let* ((base (file-name-nondirectory path))
           (dir (directory-file-name (or (file-name-directory path) "")))
           (parent (file-name-nondirectory dir)))
      (if (> (length parent) 0)
          (let ((s (format "…/%s/%s" parent base)))
            (if (<= (length s) max) s (format "…/%s" base)))
        (format "…/%s" base)))))

(defun mp/workspace-hud--icon-svg (key x ytop color)
  "Return an SVG line-icon for KEY in a 12x12 box at (X . YTOP), stroked COLOR.
Drawn as vector paths so it renders regardless of font glyph coverage."
  (let ((body
         (pcase key
           ('project "<path d='M1 3.6h3.3l1 1.3H11v6H1z'/>")
           ('branch  (concat "<circle cx='3' cy='3' r='1.5'/><circle cx='3' cy='9' r='1.5'/>"
                             "<circle cx='9' cy='3.2' r='1.5'/><path d='M3 4.5v3'/>"
                             "<path d='M8.6 4.5C8 6.4 4.9 6 3.5 7.1'/>"))
           ('changes (concat "<path d='M2.2 9.8l.55-2.2 4.9-4.9 1.65 1.65-4.9 4.9-2.2.55z'/>"
                             "<path d='M6.8 3.35l1.65 1.65'/>"))
           ('lsp     (concat "<rect x='1.5' y='2.4' width='9' height='3.1' rx='0.8'/>"
                             "<rect x='1.5' y='6.4' width='9' height='3.1' rx='0.8'/>"
                             (format "<circle cx='3.3' cy='3.95' r='0.55' fill='%s' stroke='none'/>" color)
                             (format "<circle cx='3.3' cy='7.95' r='0.55' fill='%s' stroke='none'/>" color)))
           ('diag    (concat "<path d='M6 1.7l4.7 8.2H1.3z'/><path d='M6 4.7v2.3'/>"
                             (format "<circle cx='6' cy='8.5' r='0.6' fill='%s' stroke='none'/>" color)))
           ('mode    "<path d='M4 3L1.4 6 4 9'/><path d='M8 3l2.6 3L8 9'/>")
           ('agent   (concat "<path d='M1.6 2.4h8.8v5.4H5.4l-2.3 2v-2H1.6z'/>"
                             (format "<circle cx='4' cy='5.1' r='0.55' fill='%s' stroke='none'/>" color)
                             (format "<circle cx='6' cy='5.1' r='0.55' fill='%s' stroke='none'/>" color)
                             (format "<circle cx='8' cy='5.1' r='0.55' fill='%s' stroke='none'/>" color)))
           ('debug   (concat "<ellipse cx='6' cy='6.4' rx='2.5' ry='3'/><path d='M6 3.4V2'/>"
                             "<path d='M3.5 6H1.6M8.5 6h1.9M3.7 8.7l-1.3 1.1M8.3 8.7l1.3 1.1"
                             "M3.7 4.1L2.5 3M8.3 4.1L9.5 3'/>"))
           ('commit  (concat "<circle cx='6' cy='6' r='2.3'/><path d='M6 1.2v2.5M6 8.3v2.5'/>"))
           ('git     (concat "<circle cx='3' cy='8.6' r='1.5'/><circle cx='9' cy='8.6' r='1.5'/>"
                             "<circle cx='6' cy='3' r='1.5'/><path d='M6 4.5v2.6M4.2 7.4 7.8 7.4'/>"))
           (_        "<circle cx='6' cy='6' r='1.4'/>"))))
    (format "<g transform='translate(%s %s)' stroke='%s' stroke-width='1.3' fill='none' stroke-linecap='round' stroke-linejoin='round'>%s</g>"
            x ytop color body)))

(defun mp/workspace-hud--elapsed-str (since)
  "Return a compact elapsed string for time SINCE."
  (let* ((s (max 0 (floor (float-time (time-subtract (current-time) since))))))
    (if (< s 60) (format "%ds" s)
      (format "%d:%02d" (/ s 60) (% s 60)))))

(defun mp/workspace-hud--build-svg (buf w h)
  "Build the HUD for BUF at W x H.  Return (SVG-STRING . BUTTONS).
BUTTONS is a list of (X0 Y0 X1 Y1 . ACTION) clickable regions."
  (let* ((pal (mp/workspace-hud--palette))
         (fam (plist-get pal :family))
         (fg (plist-get pal :fg))
         (heading (plist-get pal :heading))
         (faint (plist-get pal :faint))
         (border (plist-get pal :border))
         (accent (plist-get pal :accent))
         (iconc accent)     ; all icons share one color
         (ok (plist-get pal :ok)) (warn (plist-get pal :warn)) (err (plist-get pal :err))
         (data (mp/workspace-hud--collect buf))
         (agents (mapcar #'mp/workspace-hud--agent-info (mp/workspace-hud--agent-buffers)))
         (dape (mp/workspace-hud--dape-info buf))
         (health-shown (string= (plist-get data :lsp) "online"))
         (dape-shown (or (plist-get dape :active) (plist-get dape :available)))
         (padx 14) (labelx 32) (filex 34)
         (rightx (- w padx 4))   ; right edge for content, inset 4px to avoid clipping
         (nodes '()) (buttons '())
         (y 0))
    (cl-labels
        ((add (node) (push node nodes))
         (rect (x0 y0 x1 y1 action &optional label)
           (push (list x0 y0 x1 y1 action label) buttons))
         (iconbtn (x cy key action label &optional tone)   ; small icon button
           (add (mp/workspace-hud--icon-svg key x (- cy 10) (or tone iconc)))
           (rect (- x 3) (- cy 13) (+ x 15) (+ cy 4) action label))
         (header (title &optional rkey raction rlabel)
           (cl-incf y 24)
           (add (mp/workspace-hud--txt padx y (upcase title) 10 heading :weight 600 :spacing 2))
           (when rkey (iconbtn (- rightx 12) y rkey raction rlabel heading))
           (add (format "<line x1='%d' y1='%s' x2='%d' y2='%s' stroke='%s' stroke-width='1'/>"
                        padx (+ y 7) rightx (+ y 7) border))
           (cl-incf y 8))
         (row (ic label value status &optional action alabel)
           (cl-incf y 21)
           (add (mp/workspace-hud--icon-svg ic padx (- y 10) iconc))
           (add (mp/workspace-hud--txt labelx y label 13 fg))
           (when (and value (> (length value) 0))
             (add (mp/workspace-hud--txt rightx y value 12.5
                                         (mp/workspace-hud--status-color pal status) :anchor "end")))
           (when action (rect padx (- y 16) rightx (+ y 6) action alabel)))
         (gap (n) (cl-incf y n))
         (filerow (path ins del action)
           (cl-incf y 17)
           (add (mp/workspace-hud--txt filex y (mp/workspace-hud--short-path path 30) 11.5 heading))
           (cond
            ((eq ins 'new)
             (add (mp/workspace-hud--txt rightx y "new" 11 accent :anchor "end")))
            ((or (and ins (> ins 0)) (and del (> del 0)))
             (add (format "<text x='%d' y='%s' font-size='11' text-anchor='end'>%s%s</text>"
                          rightx y
                          (if (and ins (> ins 0)) (format "<tspan fill='%s'>+%d</tspan> " ok ins) "")
                          (if (and del (> del 0)) (format "<tspan fill='%s'>-%d</tspan>" err del) "")))))
           (when action (rect (- filex 4) (- y 15) rightx (+ y 5) action path)))
         (chip (x cy label action tone)   ; horizontal control button; returns next x
           (let* ((bw (+ (ceiling (* (length label) 6.3)) 16)) (top (- cy 13)) (bh 18)
                  (c (or tone fg)))
             (add (format "<rect x='%d' y='%d' width='%d' height='%d' rx='5' fill='none' stroke='%s' stroke-width='1'/>"
                          x top bw bh c))
             (add (mp/workspace-hud--txt (+ x (/ bw 2)) (- cy 4) label 10.5 c :anchor "middle"))
             (rect x top (+ x bw) (+ top bh) action label)
             (+ x bw 6)))
         (bigbtn (label action &optional tone)
           (cl-incf y 25)
           (let ((top (- y 15)) (bh 22) (c (or tone accent)))
             (add (format "<rect x='%d' y='%d' width='%d' height='%d' rx='6' fill='none' stroke='%s' stroke-width='1'/>"
                          padx top (- rightx padx) bh c))
             (add (mp/workspace-hud--txt (/ (+ padx rightx) 2) (- y 1) label 12 c :anchor "middle" :weight 600))
             (rect padx top rightx (+ top bh) action label))
           (cl-incf y 8))
         (commiticon (cy action)   ; right-aligned commit button on the Dirty row
           (add (mp/workspace-hud--icon-svg 'commit (- rightx 12) (- cy 10) accent))
           (rect (- rightx 16) (- cy 13) (+ rightx 2) (+ cy 4) action "stage all + commit"))
         (agent-block (a)
           (let ((st (plist-get a :status)))
             (cl-incf y 21)
             (add (mp/workspace-hud--icon-svg 'agent padx (- y 10) iconc))
             (add (mp/workspace-hud--txt labelx y
                                         (or (plist-get a :model) (plist-get a :name)) 12.5 fg :weight 600))
             (add (mp/workspace-hud--txt rightx y
                                         (pcase st ('busy "working") ('blocked "asking") (_ "ready")) 10.5
                                         (pcase st ('busy ok) ('blocked warn) (_ (plist-get pal :muted)))
                                         :anchor "end"))
             (let ((meta (string-join
                          (delq nil (list (plist-get a :effort)
                                          (and (plist-get a :mode) (format "mode %s" (plist-get a :mode)))))
                          "  ·  ")))
               (when (> (length meta) 0)
                 (cl-incf y 15)
                 (add (mp/workspace-hud--txt filex y meta 10 faint))))
             (when (plist-get a :ctx-pct)
               (cl-incf y 15)
               (add (mp/workspace-hud--txt filex y "context" 10 heading))
               (add (mp/workspace-hud--txt rightx y (format "%d%%" (plist-get a :ctx-pct)) 10
                                           (if (> (plist-get a :ctx-pct) 80) warn heading) :anchor "end")))
             (when (plist-get a :since)
               (cl-incf y 15)
               (add (mp/workspace-hud--txt filex y
                                           (format "running %s" (mp/workspace-hud--elapsed-str (plist-get a :since)))
                                           10 faint))))))

      ;; ---- title ------------------------------------------------------------
      (cl-incf y 30)
      (add (mp/workspace-hud--icon-svg 'project padx (- y 12) iconc))
      (add (mp/workspace-hud--txt labelx y (plist-get data :project) 15 fg :weight 700))
      (gap 4)

      ;; ---- GIT --------------------------------------------------------------
      (let ((root (plist-get data :root))
            (dirty (plist-get data :dirty)))
        (header "Git" (and root 'git) #'mp/workspace-hud--act-magit-status "open magit")
        ;; branch — click to change branch
        (row 'branch (plist-get data :branch) (plist-get data :upstream) "muted"
             (and root #'mp/workspace-hud--act-magit-branch) "change branch")
        ;; Dirty — commit icon (stage all + commit) instead of the total count
        (cl-incf y 21)
        (add (mp/workspace-hud--icon-svg 'changes padx (- y 10) iconc))
        (add (mp/workspace-hud--txt labelx y "Dirty" 13 fg))
        (if (and root (not (equal dirty "clean")))
            (commiticon y #'mp/workspace-hud--act-commit-all)
          (add (mp/workspace-hud--txt rightx y "clean" 12.5 (plist-get pal :muted) :anchor "end")))
        ;; changed files under Dirty — click a file to open it
        (let* ((files (plist-get data :files))
               (total (length files))
               (reserve (+ (if health-shown 72 0)
                           (* (length agents) 84)
                           (if agents 0 18) 36 33
                           (if dape-shown 96 0) 34))
               (avail (- h y reserve))
               (fit (max 0 (floor (/ (float avail) 17))))
               (cap (max 0 (min mp/workspace-hud-max-files fit)))
               (shown (if (> total cap) (cl-subseq files 0 cap) files)))
          (gap 3)
          (dolist (f shown)
            (let ((abs (and root (expand-file-name (nth 0 f) root))))
              (filerow (nth 0 f) (nth 1 f) (nth 2 f)
                       (and abs (lambda () (find-file abs))))))
          (when (> total (length shown))
            (cl-incf y 16)
            (add (mp/workspace-hud--txt filex y
                                        (format "… and %d more" (- total (length shown)))
                                        10 faint :opacity 0.85)))))
      (gap 10)

      ;; ---- HEALTH (only when an LSP server is running) ----------------------
      (when health-shown
        (header "Health")
        (row 'lsp "LSP" (plist-get data :lsp-label) (plist-get data :lsp-status))
        ;; Diagnostics — click to open the error/warning list
        (row 'diag "Diagnostics" (plist-get data :diag) (plist-get data :diag-status)
             #'mp/workspace-hud--act-show-diagnostics "list diagnostics")
        (gap 10))

      ;; ---- AGENTS -----------------------------------------------------------
      (header "Agents")
      (bigbtn "+ New agent"
              (lambda () (call-interactively
                          (cond ((fboundp 'agent-shell-new-shell) 'agent-shell-new-shell)
                                ((fboundp 'agent-shell) 'agent-shell)
                                (t 'ignore)))))
      (if (null agents)
          (progn (cl-incf y 16)
                 (add (mp/workspace-hud--txt filex y "no active agents" 10.5 faint)))
        (dolist (a agents) (agent-block a)))
      (gap 10)

      ;; ---- DEBUGGER (only when available or a session is live) --------------
      (when dape-shown
        (header "Debugger")
        (if (plist-get dape :active)
            (let ((state (plist-get dape :state)))
              (cl-incf y 21)
              (add (mp/workspace-hud--icon-svg 'debug padx (- y 10) iconc))
              (add (mp/workspace-hud--txt labelx y
                                          (pcase state ('stopped "paused") ('running "running")
                                                 ('initialized "starting") (_ (format "%s" state)))
                                          13 (pcase state ('stopped warn) ('running ok) (_ (plist-get pal :muted)))
                                          :weight 600))
              (when (plist-get dape :where)
                (cl-incf y 15)
                (add (mp/workspace-hud--txt filex y
                                            (concat (plist-get dape :where)
                                                    (and (plist-get dape :func)
                                                         (format "  %s" (plist-get dape :func))))
                                            10 faint)))
              (cl-incf y 23)
              (let ((cx padx))
                (if (eq state 'stopped)
                    (progn
                      (setq cx (chip cx y "cont" (lambda () (call-interactively 'dape-continue)) ok))
                      (setq cx (chip cx y "over" (lambda () (call-interactively 'dape-next)) fg))
                      (setq cx (chip cx y "in"   (lambda () (call-interactively 'dape-step-in)) fg))
                      (setq cx (chip cx y "out"  (lambda () (call-interactively 'dape-step-out)) fg))
                      (chip cx y "stop" (lambda () (call-interactively 'dape-quit)) err))
                  (progn
                    (when (eq state 'running)
                      (setq cx (chip cx y "pause" (lambda () (call-interactively 'dape-pause)) fg)))
                    (chip cx y "stop" (lambda () (call-interactively 'dape-quit)) err)))))
          ;; available but not started
          (progn
            (cl-incf y 21)
            (add (mp/workspace-hud--icon-svg 'debug padx (- y 10) iconc))
            (add (mp/workspace-hud--txt labelx y "ready to debug" 13 (plist-get pal :muted)))
            (cl-incf y 23)
            (chip padx y "launch" (lambda () (call-interactively 'dape)) accent)))
        (gap 10))

      (cons (format "<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d' font-family='%s'>%s</svg>"
                    w h (mp/workspace-hud--esc fam)
                    (mapconcat #'identity (nreverse nodes) ""))
            (nreverse buttons)))))

;; ---------------------------------------------------------------------------
;; Child frame lifecycle
;; ---------------------------------------------------------------------------

(defvar mp/workspace-hud-mode-map
  (let ((m (make-sparse-keymap)))
    ;; Clicking an image :map hot-spot dispatches as [<id> mouse-1]; all our
    ;; hot-spots share the id `wshud', so bind that.  Also bind bare mouse-1
    ;; for clicks that miss a hot-spot.
    (define-key m [wshud mouse-1] #'mp/workspace-hud--click)
    (define-key m [wshud mouse-2] #'mp/workspace-hud--click)
    (define-key m [mouse-1] #'mp/workspace-hud--click)
    m)
  "Keymap for `mp/workspace-hud-mode' (handles button clicks).")

(define-derived-mode mp/workspace-hud-mode special-mode "WS-HUD"
  "Major mode for the workspace HUD child frame."
  (setq-local mode-line-format nil
              header-line-format nil
              cursor-type nil
              cursor-in-non-selected-windows nil
              left-margin-width 0
              right-margin-width 0
              line-spacing 0
              truncate-lines t)
  (buffer-disable-undo))

(defun mp/workspace-hud--run-action (action)
  "Run ACTION in the target window's context, then return focus to the parent."
  (let ((win (mp/workspace-hud--target-window)))
    ;; hand OS focus back to the editor before running, so the command's own
    ;; window management (magit popups, find-file, dape) lands in the parent.
    (when (frame-live-p mp/workspace-hud--parent)
      (select-frame-set-input-focus mp/workspace-hud--parent))
    (if (window-live-p win)
        (with-selected-frame mp/workspace-hud--parent
          (with-selected-window win
            (condition-case e (funcall action)
              (error (mp/workspace-hud--log "action error: %s" (error-message-string e))
                     (message "workspace-hud: %s" (error-message-string e))))))
      (funcall action))))

(defun mp/workspace-hud--click (ev)
  "Dispatch a click EV to the button under the pointer, if any."
  (interactive "e")
  (let* ((pos (event-start ev))
         (xy (posn-object-x-y pos))
         (x (and xy (car xy))) (y (and xy (cdr xy))))
    (mp/workspace-hud--log "click at (%s,%s); %d buttons" x y (length mp/workspace-hud--buttons))
    (if (null xy)
        (mp/workspace-hud--log "click had no object coords")
      (let ((hit (cl-find-if (lambda (b) (and (>= x (nth 0 b)) (< x (nth 2 b))
                                              (>= y (nth 1 b)) (< y (nth 3 b))))
                             mp/workspace-hud--buttons)))
        (if hit
            (progn (mp/workspace-hud--log "hit button rect %S" (list (nth 0 hit) (nth 1 hit) (nth 2 hit) (nth 3 hit)))
                   (mp/workspace-hud--run-action (nth 4 hit)))
          (mp/workspace-hud--log "no button under click"))))))

(defun mp/workspace-hud--get-buffer ()
  "Return the HUD buffer, creating it if needed."
  (or (get-buffer mp/workspace-hud--buffer-name)
      (with-current-buffer (get-buffer-create mp/workspace-hud--buffer-name)
        (mp/workspace-hud-mode)
        (current-buffer))))

(defun mp/workspace-hud--make-frame (parent)
  "Create (invisible) the HUD child frame docked onto PARENT."
  (let* ((buf (mp/workspace-hud--get-buffer))
         (frame (make-frame
                 `((parent-frame . ,parent)
                   (name . "workspace-hud")
                   (minibuffer . nil)
                   (undecorated . t)
                   ;; NOTE: the frame must accept focus, otherwise pgtk never
                   ;; delivers mouse-1 to its window and buttons don't work.
                   ;; It won't grab focus on show (no-focus-on-map); after a
                   ;; click we hand focus straight back to the parent.
                   (no-accept-focus . nil)
                   (no-focus-on-map . t)
                   (no-other-frame . t)
                   (unsplittable . t)
                   (desktop-dont-save . t)
                   (visibility . nil)
                   (width . (text-pixels . ,mp/workspace-hud-width))
                   (height . (text-pixels . 400))
                   (min-width . 0) (min-height . 0)
                   (internal-border-width . 0)
                   (child-frame-border-width . 0)
                   (left-fringe . 0) (right-fringe . 0)
                   (vertical-scroll-bars . nil)
                   (horizontal-scroll-bars . nil)
                   (menu-bar-lines . 0) (tool-bar-lines . 0) (tab-bar-lines . 0)
                   (line-spacing . 0)
                   (cursor-type . nil)))))
    ;; No background modification: the frame just uses the default (editor)
    ;; background, so it blends with the buffer it floats over.
    (let ((win (frame-root-window frame)))
      (set-window-buffer win buf)
      (set-window-parameter win 'no-other-window t)
      (set-window-dedicated-p win t)
      (set-window-margins win 0 0)
      (set-window-fringes win 0 0))
    frame))

(defcustom mp/workspace-hud-top-margin 4
  "Pixels of breathing room between the header line and the HUD top."
  :type 'integer :group 'mp/workspace-hud)

(defcustom mp/workspace-hud-bottom-margin 4
  "Pixels of breathing room between the HUD bottom and the mode line."
  :type 'integer :group 'mp/workspace-hud)

(defcustom mp/workspace-hud-right-margin 8
  "Pixels of gap between the HUD right edge and the frame's right edge."
  :type 'integer :group 'mp/workspace-hud)

(defun mp/workspace-hud--target-window ()
  "Return the real (non-minibuffer) window the user is looking at on PARENT."
  (let* ((parent mp/workspace-hud--parent)
         (win (and (frame-live-p parent) (frame-selected-window parent))))
    (if (or (null win) (not (window-live-p win)) (window-minibuffer-p win))
        (get-mru-window parent nil nil t)
      win)))

(defun mp/workspace-hud--sync-geometry ()
  "Dock the HUD to the right edge, below the header line and above the modeline.
Uses the target window's inside pixel edges — which already exclude the
header line (top), mode line (bottom) and echo area — so it is robust to the
svg-header changing height, then applies `mp/workspace-hud-top-margin'."
  (when (and (frame-live-p mp/workspace-hud--frame)
             (frame-live-p mp/workspace-hud--parent))
    (let* ((frame-resize-pixelwise t)
           (parent mp/workspace-hud--parent)
           (win (mp/workspace-hud--target-window))
           (edges (and (window-live-p win) (window-inside-pixel-edges win)))
           ;; Only TOP/BOTTOM come from the window's inside edges (to clear the
           ;; header line / mode line).  The RIGHT anchor uses the frame width,
           ;; NOT the text-area edge — otherwise olivetti's centred column would
           ;; drag the HUD far left.
           (top (if edges (nth 1 edges) 0))
           (bottom (if edges (nth 3 edges) (frame-inner-height parent)))
           (pw (frame-inner-width parent))
           (w mp/workspace-hud-width)
           (x (max 0 (- pw w mp/workspace-hud-right-margin)))
           (m mp/workspace-hud-top-margin)
           (y (+ top m))
           (h (max 40 (- bottom top m mp/workspace-hud-bottom-margin)))
           (geom (list x y w h)))
      (let ((changed (not (equal geom (frame-parameter mp/workspace-hud--frame 'mp/geom)))))
        (mp/workspace-hud--log "geom win=%s edges=%s -> x=%s y=%s w=%s h=%s changed=%s"
                               (and (window-live-p win) (buffer-name (window-buffer win)))
                               edges x y w h changed)
        (when changed
          (set-frame-size mp/workspace-hud--frame w h t)
          (set-frame-position mp/workspace-hud--frame x y)
          (set-frame-parameter mp/workspace-hud--frame 'mp/geom geom))
        changed))))

(defun mp/workspace-hud--target-buffer ()
  "Return the buffer shown in the target window."
  (let ((win (mp/workspace-hud--target-window)))
    (if (window-live-p win) (window-buffer win) (current-buffer))))

(defun mp/workspace-hud--image-map (btns)
  "Build an Emacs image :map from BTNS for hover cursor + tooltips.
All hot-spots share the id `wshud' so a click dispatches as the single key
sequence [wshud mouse-1] (see `mp/workspace-hud-mode-map'); the exact button is
then resolved by pixel hit-testing in `mp/workspace-hud--click'."
  (let (map)
    (dolist (b btns (nreverse map))
      (push (list (cons 'rect (cons (cons (nth 0 b) (nth 1 b))
                                    (cons (nth 2 b) (nth 3 b))))
                  'wshud
                  (list 'pointer 'hand 'help-echo (or (nth 5 b) "")))
            map))))

(defun mp/workspace-hud--render ()
  "Render the current target into the HUD buffer."
  (when (frame-live-p mp/workspace-hud--frame)
    (let* ((buf (mp/workspace-hud--get-buffer))
           (w (frame-inner-width mp/workspace-hud--frame))
           (h (frame-inner-height mp/workspace-hud--frame))
           (built (mp/workspace-hud--build-svg (mp/workspace-hud--target-buffer) w h))
           (svg (car built))
           (btns (cdr built)))
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert-image (create-image svg 'svg t
                                      :map (mp/workspace-hud--image-map btns)))
          (goto-char (point-min))
          (setq-local mp/workspace-hud--buttons btns))))))

;; ---------------------------------------------------------------------------
;; Event-driven refresh (no periodic timer)
;; ---------------------------------------------------------------------------

(defcustom mp/workspace-hud-suppress-modes '(magit-mode)
  "Major modes (matched with `derived-mode-p') that auto-hide the HUD.
Also hidden: any buffer whose mode name or buffer name starts with \"magit\",
and the git commit message buffer."
  :type '(repeat symbol) :group 'mp/workspace-hud)

(defun mp/workspace-hud--suppress-p (buf)
  "Return non-nil when BUF is a buffer over which the HUD should hide."
  (and (buffer-live-p buf)
       (with-current-buffer buf
         (or (apply #'derived-mode-p mp/workspace-hud-suppress-modes)
             (string-prefix-p "magit" (symbol-name major-mode))
             (string-prefix-p "magit" (buffer-name))
             (string-prefix-p "COMMIT_EDITMSG" (buffer-name))))))

(defvar mp/workspace-hud--geom-pending nil
  "Idle timer that re-docks the frame after activity settles, or nil.")

(defun mp/workspace-hud--refresh-now ()
  "Refresh CONTENT + visibility only; geometry is handled elsewhere.
Geometry is intentionally decoupled (see `mp/workspace-hud--geom-now'): moving
or resizing a pgtk child frame during the parent's scroll/redisplay makes it
vanish, so we only re-dock once activity settles."
  (setq mp/workspace-hud--pending nil)
  (when (and mp/workspace-hud--enabled (frame-live-p mp/workspace-hud--frame))
    (let ((target (mp/workspace-hud--target-buffer)))
      (if (mp/workspace-hud--suppress-p target)
          (progn
            (mp/workspace-hud--log "suppress: hiding over %s" (buffer-name target))
            (when (frame-visible-p mp/workspace-hud--frame)
              (make-frame-invisible mp/workspace-hud--frame)))
        (mp/workspace-hud--log "refresh: target=%s visible=%s"
                               (buffer-name target) (frame-visible-p mp/workspace-hud--frame))
        (mp/workspace-hud--render)
        (unless (frame-visible-p mp/workspace-hud--frame)
          (mp/workspace-hud--log "making frame visible")
          (make-frame-visible mp/workspace-hud--frame))
        (mp/workspace-hud--maybe-tick)))))

(defun mp/workspace-hud--geom-now ()
  "Re-dock the frame to the current geometry.  Runs from an idle timer, so it
fires only after scrolling/resizing has settled — never mid-scroll."
  (setq mp/workspace-hud--geom-pending nil)
  (when (and mp/workspace-hud--enabled (frame-live-p mp/workspace-hud--frame)
             (not (mp/workspace-hud--suppress-p (mp/workspace-hud--target-buffer))))
    (when (mp/workspace-hud--sync-geometry)
      ;; force a repaint: pgtk sometimes drops the child frame after a move
      (redraw-frame mp/workspace-hud--frame))))

(defun mp/workspace-hud--maybe-tick ()
  "Arm a 1s timer while an agent is busy (to tick elapsed), else cancel it."
  (let ((busy (> (hash-table-count mp/workspace-hud--agent-busy) 0)))
    (cond
     ((and busy (not mp/workspace-hud--tick))
      (setq mp/workspace-hud--tick
            (run-with-timer 1 1 (lambda ()
                                  (if (and mp/workspace-hud--enabled
                                           (> (hash-table-count mp/workspace-hud--agent-busy) 0))
                                      (mp/workspace-hud--render)
                                    (mp/workspace-hud--stop-tick))))))
     ((and (not busy) mp/workspace-hud--tick)
      (mp/workspace-hud--stop-tick)))))

(defun mp/workspace-hud--stop-tick ()
  "Cancel the busy tick timer."
  (when mp/workspace-hud--tick
    (cancel-timer mp/workspace-hud--tick)
    (setq mp/workspace-hud--tick nil)))

(defun mp/workspace-hud--schedule (&rest _)
  "Coalesce a CONTENT refresh onto a short idle debounce."
  (when (and mp/workspace-hud--frame (frame-live-p mp/workspace-hud--frame)
             (not mp/workspace-hud--pending))
    (setq mp/workspace-hud--pending
          (run-with-idle-timer 0.05 nil #'mp/workspace-hud--refresh-now))))

(defun mp/workspace-hud--schedule-geom (&rest _)
  "Schedule a re-dock once activity settles (a longer idle timer).
Because it is an idle timer it never fires mid-scroll — only after the user
pauses — which is what keeps the frame from vanishing during scroll."
  (when (and mp/workspace-hud--frame (frame-live-p mp/workspace-hud--frame)
             (not mp/workspace-hud--geom-pending))
    (setq mp/workspace-hud--geom-pending
          (run-with-idle-timer 0.25 nil #'mp/workspace-hud--geom-now))))

(defun mp/workspace-hud--schedule-both (&rest _)
  "Refresh content soon and re-dock after settle."
  (mp/workspace-hud--schedule)
  (mp/workspace-hud--schedule-geom))

(defun mp/workspace-hud--on-save ()
  "Bust the git cache on save so dirtiness updates immediately."
  (clrhash mp/workspace-hud--git-cache)
  (mp/workspace-hud--schedule))

(defun mp/workspace-hud--on-size-change (frame)
  "Re-dock (after settle) when the PARENT frame (not our own) changes size.
This also fires when the svg-header changes height; routing it through the
settle timer is what prevents the mid-scroll disappearance."
  (unless (eq frame mp/workspace-hud--frame)
    (mp/workspace-hud--schedule-geom)))

(defvar mp/workspace-hud--hooks-installed nil)

(defun mp/workspace-hud--add-hooks ()
  "Install the event hooks that drive refreshes."
  (unless mp/workspace-hud--hooks-installed
    ;; buffer/window changes: refresh content AND re-dock (window edges moved)
    (add-hook 'window-buffer-change-functions #'mp/workspace-hud--schedule-both)
    (add-hook 'window-selection-change-functions #'mp/workspace-hud--schedule-both)
    ;; size/header-height changes: geometry only, on the settle timer
    (add-hook 'window-size-change-functions #'mp/workspace-hud--on-size-change)
    ;; NOTE: intentionally no `window-scroll-functions' hook — scrolling must
    ;; not move the frame (that caused the vanish); geometry follows via the
    ;; settle timer above.
    (add-hook 'after-save-hook #'mp/workspace-hud--on-save)
    (add-hook 'after-change-major-mode-hook #'mp/workspace-hud--schedule)
    (when (boundp 'flycheck-after-syntax-check-hook)
      (add-hook 'flycheck-after-syntax-check-hook #'mp/workspace-hud--schedule))
    (when (fboundp 'flymake--handle-report)
      (advice-add 'flymake--handle-report :after #'mp/workspace-hud--schedule))
    ;; agent-shell: refresh on any agent event (busy/tool/turn/permission)
    (when (fboundp 'agent-shell--emit-event)
      (advice-add 'agent-shell--emit-event :after #'mp/workspace-hud--schedule))
    ;; dape: refresh on session + UI state changes
    (dolist (h '(dape-update-ui-hook dape-active-mode-hook dape-stopped-hook))
      (when (boundp h) (add-hook h #'mp/workspace-hud--schedule)))
    (setq mp/workspace-hud--hooks-installed t)))

(defun mp/workspace-hud--remove-hooks ()
  "Remove the event hooks."
  (remove-hook 'window-buffer-change-functions #'mp/workspace-hud--schedule-both)
  (remove-hook 'window-selection-change-functions #'mp/workspace-hud--schedule-both)
  (remove-hook 'window-size-change-functions #'mp/workspace-hud--on-size-change)
  (remove-hook 'after-save-hook #'mp/workspace-hud--on-save)
  (remove-hook 'after-change-major-mode-hook #'mp/workspace-hud--schedule)
  (when (boundp 'flycheck-after-syntax-check-hook)
    (remove-hook 'flycheck-after-syntax-check-hook #'mp/workspace-hud--schedule))
  (when (fboundp 'flymake--handle-report)
    (advice-remove 'flymake--handle-report #'mp/workspace-hud--schedule))
  (when (fboundp 'agent-shell--emit-event)
    (advice-remove 'agent-shell--emit-event #'mp/workspace-hud--schedule))
  (dolist (h '(dape-update-ui-hook dape-active-mode-hook dape-stopped-hook))
    (when (boundp h) (remove-hook h #'mp/workspace-hud--schedule)))
  (setq mp/workspace-hud--hooks-installed nil))

;; ---------------------------------------------------------------------------
;; Public commands
;; ---------------------------------------------------------------------------

;; NOTE: no `map!'/leader binding here (Doom-era `SPC t W' now lives in
;; lisp/mp-keys.el, bound to `mp/workspace-hud-toggle').

(defun mp/workspace-hud-visible-p ()
  "Return non-nil when the user has the HUD on (even if momentarily auto-hidden)."
  mp/workspace-hud--enabled)

;;;###autoload
(defun mp/workspace-hud-open ()
  "Show the workspace HUD."
  (interactive)
  (unless (display-graphic-p)
    (user-error "workspace-hud needs a graphical frame"))
  (setq mp/workspace-hud--parent (window-frame (selected-window)))
  (unless (and mp/workspace-hud--frame (frame-live-p mp/workspace-hud--frame))
    (setq mp/workspace-hud--frame (mp/workspace-hud--make-frame mp/workspace-hud--parent)))
  (setq mp/workspace-hud--enabled t)
  (mp/workspace-hud--log "open: parent=%s frame=%s" mp/workspace-hud--parent mp/workspace-hud--frame)
  (mp/workspace-hud--add-hooks)
  (mp/workspace-hud--sync-geometry)   ; dock once, up front
  (mp/workspace-hud--refresh-now))

;;;###autoload
(defun mp/workspace-hud-close ()
  "Hide the workspace HUD."
  (interactive)
  (setq mp/workspace-hud--enabled nil)
  (mp/workspace-hud--log "close")
  (mp/workspace-hud--remove-hooks)
  (mp/workspace-hud--stop-tick)
  (clrhash mp/workspace-hud--agent-busy)
  (when mp/workspace-hud--pending
    (cancel-timer mp/workspace-hud--pending)
    (setq mp/workspace-hud--pending nil))
  (when mp/workspace-hud--geom-pending
    (cancel-timer mp/workspace-hud--geom-pending)
    (setq mp/workspace-hud--geom-pending nil))
  (when (frame-live-p mp/workspace-hud--frame)
    (delete-frame mp/workspace-hud--frame))
  (setq mp/workspace-hud--frame nil))

;;;###autoload
(defun mp/workspace-hud-toggle ()
  "Toggle the workspace HUD."
  (interactive)
  (if mp/workspace-hud--enabled
      (mp/workspace-hud-close)
    (mp/workspace-hud-open)))

(provide 'workspace-hud)
;;; workspace-hud.el ends here
