;;; super-menu.el --- Consult-powered command super menu  -*- lexical-binding: t; -*-
;;; Commentary:
;; A single discoverable `consult'-driven menu that gathers the actions
;; scattered across the config behind one entry point.
;;; Code:

;;; consult-buffer with history-sorted custom sources.

(defun mp/project-workspace-p ()
  "Return non-nil when the current workspace has a Projectile project."
  (and (bound-and-true-p projectile-mode)
       (projectile-project-p)))

(defun mp/workspace-buffers ()
  "Return buffers belonging to current Doom workspace."
  (if (fboundp '+workspace-buffer-list)
      (+workspace-buffer-list)
    (buffer-list)))

(defun mp/current-workspace-buffer-p (buf)
  "Return non-nil if BUF belongs to current Doom workspace."
  (memq buf (mp/workspace-buffers)))

(defun mp/ghostel-buffer-p (buf)
  "Return non-nil if BUF is a Ghostel terminal buffer.
Ghostel renames buffers to their OSC 2 title (see
`ghostel-buffer-name-function'), which usually drops the leading
`*', so a mode check is needed to keep terminals out of the plain
buffer list."
  (with-current-buffer buf
    (derived-mode-p 'ghostel-mode)))

(defun mp/agent-shell-buffer-p (buf)
  "Return non-nil if BUF is an agent-shell/Codex agent buffer."
  (let ((name (buffer-name buf)))
    (or (string-match-p "\\`Agent @ " name)
        (string-match-p "\\`\\*agent-shell" name)
        (with-current-buffer buf
          (or (derived-mode-p 'agent-shell-mode)
              (derived-mode-p 'codex-mode))))))

(defun mp/special-buffer-p (buf)
  "Return non-nil if BUF is a special star buffer."
  (string-prefix-p "*" (buffer-name buf)))

(defun mp/package-buffer-p (buf)
  "Return non-nil if BUF belongs to a local package (Teamwork / GitHub PR).
Matches their main buffers and companions (submit/preview/logs/accounts) while
skipping the leading-space internal process buffers."
  (let ((name (buffer-name buf)))
    (and (not (string-prefix-p " " name))
         (string-match-p "\\(teamwork\\|github-pr\\)" name))))

(defun mp/normal-buffer-p (buf)
  "Return non-nil for ordinary user-facing buffers."
  (and (buffer-live-p buf)
       (not (mp/special-buffer-p buf))
       (not (mp/agent-shell-buffer-p buf))
       (not (mp/ghostel-buffer-p buf))
       (not (mp/package-buffer-p buf))))

(defun mp/history-index (item history)
  "Return ITEM position in HISTORY, or a large number."
  (or (cl-position item history :test #'equal)
      most-positive-fixnum))

(defun mp/sort-strings-by-history (items history)
  "Sort string ITEMS by their position in HISTORY."
  (sort items
        (lambda (a b)
          (< (mp/history-index a history)
             (mp/history-index b history)))))

(defun mp/sort-cons-candidates-by-history (candidates history)
  "Sort cons CANDIDATES by their cdr position in HISTORY."
  (sort candidates
        (lambda (a b)
          (< (mp/history-index (cdr a) history)
             (mp/history-index (cdr b) history)))))

(defvar mp/consult-source-workspace-buffer
  `(:name "[B]uffer"
    :narrow (?b . "Buffer")
    :category buffer
    :face consult-buffer
    :history buffer-name-history
    :state ,#'consult--buffer-state
    :default t
    :enabled ,#'mp/project-workspace-p
    :items ,(lambda ()
              (mp/sort-strings-by-history
               (consult--buffer-query
                :sort nil
                :as #'buffer-name
                :predicate
                (lambda (buf)
                  (and (mp/current-workspace-buffer-p buf)
                       (mp/normal-buffer-p buf))))
               buffer-name-history))))

(defvar mp/consult-source-all-buffer
  `(:name "[B]uffer"
    :narrow (?b . "Buffer")
    :category buffer
    :face consult-buffer
    :history buffer-name-history
    :state ,#'consult--buffer-state
    :default t
    :enabled ,(lambda () (not (mp/project-workspace-p)))
    :items ,(lambda ()
              (mp/sort-strings-by-history
               (consult--buffer-query
                :sort nil
                :as #'buffer-name
                :predicate #'mp/normal-buffer-p)
               buffer-name-history))))

(defvar mp/consult-source-agent-shell-buffer
  `(:name "[A]gent Shell"
    :narrow (?a . "Agent Shell")
    :category buffer
    :face consult-buffer
    :history buffer-name-history
    :state ,#'consult--buffer-state
    :action ,#'consult--buffer-action
    :items ,(lambda ()
              (mp/sort-strings-by-history
               (consult--buffer-query
                :sort nil
                :as #'buffer-name
                :predicate
                (lambda (buf)
                  (and (if (mp/project-workspace-p)
                           (mp/current-workspace-buffer-p buf)
                         t)
                       (mp/agent-shell-buffer-p buf))))
               buffer-name-history))))

(defvar mp/consult-source-ghostel-buffer
  `(:name "Ghos[t]el"
    :narrow (?t . "Ghostel")
    :category buffer
    :face consult-buffer
    :history buffer-name-history
    :state ,#'consult--buffer-state
    :action ,#'consult--buffer-action
    :items ,(lambda ()
              (mp/sort-strings-by-history
               (consult--buffer-query
                :sort nil
                :as #'buffer-name
                :predicate
                (lambda (buf)
                  (and (if (mp/project-workspace-p)
                           (mp/current-workspace-buffer-p buf)
                         t)
                       (mp/ghostel-buffer-p buf))))
               buffer-name-history))))

(defvar mp/consult-source-package-buffer
  `(:name "[P]ackages"
    :narrow (?P . "Packages")
    :category buffer
    :face consult-buffer
    :history buffer-name-history
    :state ,#'consult--buffer-state
    :action ,#'consult--buffer-action
    :items ,(lambda ()
              (mp/sort-strings-by-history
               (consult--buffer-query
                :sort nil
                :as #'buffer-name
                :predicate #'mp/package-buffer-p)
               buffer-name-history)))
  "Buffers from local packages (Teamwork timesheet, GitHub PR) for the super menu.")

(defun mp/live-project-files (root)
  "Return live relative file list under ROOT using fd, falling back to Elisp."
  (let ((root (file-name-as-directory (expand-file-name root))))
    (if-let ((fd (executable-find "fd")))
        (let ((default-directory root))
          (process-lines fd "--type" "f" "--strip-cwd-prefix" "--color" "never" "."))
      (mapcar
       (lambda (file)
         (file-relative-name file root))
       (directory-files-recursively
        root ".*" nil
        (lambda (dir)
          (not (string-match-p "/\\.git\\(?:/\\|\\'\\)" dir))))))))

(defvar mp/super-menu--git-cache nil
  "Alist of (REPO-ROOT . HASH) caching git status during one menu invocation.
Reset by `mp/super-menu' so a fresh menu always sees current status.")

(defun mp/super-menu--git-status (dir)
  "Return a hash mapping absolute paths in DIR's repo to porcelain status codes.
Results are cached per repository for the lifetime of one menu invocation.
Returns nil when DIR is not inside a git work tree."
  (when (and dir (executable-find "git"))
    (let* ((default-directory (file-name-as-directory (expand-file-name dir)))
           (root (ignore-errors
                   (car (process-lines "git" "rev-parse" "--show-toplevel")))))
      (when root
        (or (cdr (assoc root mp/super-menu--git-cache))
            (let ((default-directory (file-name-as-directory root))
                  (map (make-hash-table :test 'equal)))
              (dolist (line (ignore-errors
                              (process-lines "git" "status" "--porcelain"
                                             "--ignored=no" "--no-renames")))
                (when (> (length line) 3)
                  (puthash (expand-file-name (substring line 3) root)
                           (string-trim (substring line 0 2))
                           map)))
              (push (cons root map) mp/super-menu--git-cache)
              map))))))

(defun mp/super-menu--git-face (code)
  "Return a face for git porcelain status CODE, or nil when unchanged."
  (cond
   ((null code) nil)
   ((string-prefix-p "?" code) 'success)    ; untracked
   ((string-match-p "U" code) 'error)       ; unmerged
   ((string-match-p "D" code) 'error)       ; deleted
   ((string-match-p "A" code) 'success)     ; added
   ((string-match-p "[MRC]" code) 'warning) ; modified / renamed / copied
   (t 'warning)))

(defun mp/super-menu--git-letter (code)
  "Return a single status letter for git porcelain CODE, or nil when unchanged."
  (cond
   ((null code) nil)
   ((string-prefix-p "?" code) "U")   ; untracked / created
   ((string-match-p "U" code) "!")    ; unmerged conflict
   ((string-match-p "A" code) "A")    ; added
   ((string-match-p "D" code) "D")    ; deleted
   ((string-match-p "R" code) "R")    ; renamed
   ((string-match-p "C" code) "C")    ; copied
   ((string-match-p "M" code) "M")    ; modified
   (t (string-trim code))))

(defun mp/super-menu--git-colorize (display abspath gitmap)
  "Return DISPLAY colour-coded and suffixed with ABSPATH's git status letter.
The status letter is appended after the name in a dim, normal-weight `shadow'
face; the name itself is coloured by `mp/super-menu--git-face'."
  (if-let* ((gitmap)
            (code (gethash abspath gitmap)))
      (concat (propertize display 'face (mp/super-menu--git-face code))
              (if-let* ((letter (mp/super-menu--git-letter code)))
                  (concat " " (propertize letter 'face 'shadow))
                ""))
    display))

(defvar mp/consult-source-live-project-file
  `(:name "[F]ile"
    :narrow (?f . "File")
    :category file
    :face consult-file
    :history file-name-history
    :state ,#'consult--file-state
    :action ,#'consult--file-action
    :new ,#'consult--file-action
    :enabled ,(lambda ()
                (or (mp/current-workspace-project-root)
                    (and (bound-and-true-p projectile-mode)
                         (projectile-project-p))))
    :items ,(lambda ()
              (let* ((root (file-name-as-directory
                            (expand-file-name
                             (or (mp/current-workspace-project-root)
                                 (projectile-project-root)))))
                     (gitmap (mp/super-menu--git-status root))
                     (candidates
                      (mapcar
                       (lambda (file)
                         (let ((abs (expand-file-name file root)))
                           (cons (mp/super-menu--git-colorize file abs gitmap)
                                 abs)))
                       (mp/live-project-files root))))
                (mp/sort-cons-candidates-by-history
                 candidates file-name-history)))))

(defvar mp/projectile-project-history nil
  "History for selecting Projectile projects through Consult.")

(defvar mp/consult-source-projectile-project
  `(:name "[P]roject"
    :narrow (?p . "Project")
    :category file
    :face consult-file
    :history mp/projectile-project-history
    :action ,(lambda (project)
               (projectile-switch-project-by-name project))
    :enabled ,(lambda ()
                (and (bound-and-true-p projectile-mode)
                     (not (mp/project-workspace-p))))
    :items ,(lambda ()
              (mp/sort-cons-candidates-by-history
               (mapcar
                (lambda (project)
                  (let* ((dir (directory-file-name project))
                         (name (file-name-nondirectory dir))
                         (parent (file-name-directory dir))
                         (label (concat parent name)))
                    (cons label project)))
                (projectile-relevant-known-projects))
               mp/projectile-project-history))))

;;; Current-directory browser + file actions for the super menu.

(defvar mp/super-menu-dir nil
  "Directory the super-menu's current-directory source is browsing.
When nil, the directory is derived from `mp/super-menu-origin-file'.
Set while navigating with the menu and reset by `mp/super-menu'.")

(defvar mp/super-menu-origin-file nil
  "File visited by the buffer that was active when the super menu opened.")

(defun mp/super-menu-directory ()
  "Return the directory the current-directory source should list, or nil."
  (or mp/super-menu-dir
      (and mp/super-menu-origin-file
           (file-name-directory mp/super-menu-origin-file))))

(defun mp/super-menu--icon (fn name)
  "Render nerd-icon NAME with function FN, or empty string when unavailable."
  (if (fboundp fn)
      (concat (funcall fn name) " ")
    ""))

(defun mp/super-menu--current-dir-items ()
  "Candidates for the files/sub-directories of the browsed directory.
Directories sort before files; a `../' entry is prepended unless at the
filesystem root."
  (when-let* ((dir (mp/super-menu-directory))
              (dir (file-name-as-directory (expand-file-name dir)))
              ((file-directory-p dir)))
    (let* ((entries (ignore-errors
                      (directory-files dir t directory-files-no-dot-files-regexp)))
           (entries (sort entries
                          (lambda (a b)
                            (let ((ad (file-directory-p a))
                                  (bd (file-directory-p b)))
                              (if (eq ad bd)
                                  (string-lessp (file-name-nondirectory a)
                                                (file-name-nondirectory b))
                                ad)))))
           (parent (file-name-directory (directory-file-name dir)))
           (gitmap (mp/super-menu--git-status dir))
           (items (mapcar
                   (lambda (path)
                     (if (file-directory-p path)
                         (cons (concat (file-name-nondirectory path) "/")
                               (file-name-as-directory path))
                       (cons (mp/super-menu--git-colorize
                              (file-name-nondirectory path) path gitmap)
                             path)))
                   entries)))
      (if (string-equal parent dir)
          items
        (cons (cons "../" parent) items)))))

(defun mp/super-menu-dir-file-action (path)
  "Open PATH, or browse into it (re-opening the menu) when it is a directory."
  (if (file-directory-p path)
      (progn
        (setq mp/super-menu-dir (file-name-as-directory path))
        (consult-buffer))
    (consult--file-action path)))

(defun mp/super-menu-dir-file-state ()
  "Preview state for the current-directory source that ignores directories."
  (let ((file-state (consult--file-state)))
    (lambda (action cand)
      (funcall file-state action
               (and cand (not (file-directory-p cand)) cand)))))

(defvar mp/consult-source-current-dir-file
  `(:name "[D]irectory"
    :narrow (?d . "Directory")
    :category file
    :face consult-file
    :history file-name-history
    :state ,#'mp/super-menu-dir-file-state
    :action ,#'mp/super-menu-dir-file-action
    :enabled ,(lambda () (and (mp/super-menu-directory) t))
    :items ,#'mp/super-menu--current-dir-items)
  "Files and sub-directories of the current buffer's directory.")

(defun mp/super-menu--with-origin-buffer (fn)
  "Call command FN inside the buffer visiting `mp/super-menu-origin-file'."
  (let ((buf (and mp/super-menu-origin-file
                  (find-buffer-visiting mp/super-menu-origin-file))))
    (if buf
        (with-current-buffer buf (call-interactively fn))
      (user-error "No file buffer to act on"))))

(defun mp/super-menu-run-action (action)
  "Run the chosen super-menu ACTION on the origin file or browsed directory."
  (pcase action
    ('rename   (mp/super-menu--with-origin-buffer #'doom/move-this-file))
    ('delete   (mp/super-menu--with-origin-buffer #'doom/delete-this-file))
    ('terminal (let ((default-directory (or (mp/super-menu-directory)
                                            default-directory)))
                 ;; Fresh Ghostel rooted in the browsed directory.
                 (ghostel '(4))))))

(defun mp/super-menu-action-annotation (action)
  "Marginalia annotation: the path super-menu ACTION will affect, right-aligned."
  (when-let* ((path (pcase action
                      ((or 'rename 'delete) mp/super-menu-origin-file)
                      ('terminal (mp/super-menu-directory)))))
    (concat (propertize " " 'marginalia--align t)
            marginalia-separator
            (propertize (abbreviate-file-name (directory-file-name path))
                        'face 'marginalia-file-name))))

(defvar mp/consult-source-current-dir-action
  `(:name "[X] Actions"
    :narrow (?x . "Actions")
    :category mp/super-action
    :action ,#'mp/super-menu-run-action
    :enabled ,(lambda () (and (mp/super-menu-directory) t))
    :items ,(lambda ()
              (delq nil
                    (list
                     (when mp/super-menu-origin-file
                       (cons (concat (mp/super-menu--icon 'nerd-icons-octicon "nf-oct-pencil")
                                     "Rename current file")
                             'rename))
                     (when mp/super-menu-origin-file
                       (cons (concat (mp/super-menu--icon 'nerd-icons-octicon "nf-oct-trash")
                                     "Delete current file")
                             'delete))
                     (cons (concat (mp/super-menu--icon 'nerd-icons-octicon "nf-oct-terminal")
                                   "Open terminal here")
                           'terminal)))))
  "Actions on the current file / browsed directory for the super menu.")

(defun mp/super-menu ()
  "Open the consult super menu, resetting the directory browser.
Records the active buffer's file so the current-directory and action
sources have something to anchor to."
  (interactive)
  (setq mp/super-menu-dir nil
        mp/super-menu--git-cache nil
        mp/super-menu-origin-file (buffer-file-name (buffer-base-buffer)))
  (consult-buffer))

(after! marginalia
  ;; Annotate the [X] Actions entries with the path they act on, dispatched via
  ;; their `mp/super-action' category just like buffers/files get their columns.
  (add-to-list 'marginalia-annotators
               '(mp/super-action mp/super-menu-action-annotation none)))

(with-eval-after-load 'consult
  (setq consult-buffer-sources
        '(mp/consult-source-workspace-buffer
          mp/consult-source-all-buffer
          mp/consult-source-agent-shell-buffer
          mp/consult-source-ghostel-buffer
          mp/consult-source-package-buffer
          mp/consult-source-current-dir-file
          mp/consult-source-current-dir-action
          mp/consult-source-live-project-file
          mp/consult-source-projectile-project
          consult-source-hidden-buffer
          consult-source-project-buffer-hidden
          consult-source-project-recent-file-hidden)))

(map! :leader "SPC" #'mp/super-menu)

(provide 'super-menu)
;;; super-menu.el ends here
