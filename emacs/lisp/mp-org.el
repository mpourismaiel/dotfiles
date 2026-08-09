;;; mp-org.el --- Org -*- lexical-binding: t; -*-

;;; Commentary:
;; Org defaults, display tweaks, evil-org/org-appear, the org localleader
;; tree, and the notes helpers used by the SPC leader (bound in mp-keys.el).

;;; Code:

;; org-directory must be set BEFORE Org loads (agenda/capture/refile paths
;; below are derived from it, and other files may consult it at load time),
;; so it stays OUTSIDE the deferred use-package/with-eval-after-load body.
(setq org-directory "~/org/")

;;; Display helpers ----------------------------------------------------------

(defun mp/org--tune-display ()
  "Per-buffer Org display tweaks: no line numbers, deferred fontification.
A source-block face spans the whole block, so the block is one
font-lock-multiline region: the moment a block's top/bottom edge scrolls
into view, jit-lock re-fontifies the entire block on the redisplay path,
which stutters on big blocks.  Defer fontification to idle time so
scrolling stays smooth; colours fill in the instant you stop.  Scoped to
Org so code buffers keep eager fontification."
  (display-line-numbers-mode -1)
  (setq-local jit-lock-defer-time 0.05))

;; Show line numbers only in insert state, hide in normal state.
(defun mp/org--line-numbers-on ()
  (when (derived-mode-p 'org-mode) (display-line-numbers-mode 1)))
(defun mp/org--line-numbers-off ()
  (when (derived-mode-p 'org-mode) (display-line-numbers-mode -1)))
(add-hook 'evil-insert-state-entry-hook #'mp/org--line-numbers-on)
(add-hook 'evil-insert-state-exit-hook #'mp/org--line-numbers-off)

;; Reopening a large Org file with point restored deep inside (save-place) can
;; leave the src block at point un-fontified and Olivetti margins unapplied
;; until you scroll back to the top — the text was folded/invisible when it was
;; first fontified, so the glitch sticks.  Once folding, save-place and the
;; window have settled, re-fontify the visible region and re-apply Olivetti.
(defun mp/org-settle-display ()
  "Fix deep-restore redisplay glitches in Org buffers."
  (when (derived-mode-p 'org-mode)
    (let ((buf (current-buffer)))
      (run-with-idle-timer
       0.1 nil
       (lambda ()
         (when (buffer-live-p buf)
           (dolist (win (get-buffer-window-list buf nil t))
             (with-selected-window win
               (font-lock-flush (window-start) (window-end nil t))
               (font-lock-ensure (window-start) (window-end nil t))
               (when (bound-and-true-p olivetti-mode)
                 (olivetti-mode 1))))))))))

;;; Notes helpers (bound on the SPC leader in mp-keys.el) ---------------------

(defun mp/find-in-notes ()
  "Find a file, starting in `org-directory'."
  (interactive)
  (let ((default-directory (file-name-as-directory org-directory)))
    (call-interactively #'find-file)))

(defun mp/browse-notes ()
  "Open `org-directory' in Dired."
  (interactive)
  (dired org-directory))

(defun mp/search-notes ()
  "Ripgrep across `org-directory'."
  (interactive)
  (consult-ripgrep org-directory))

(defun mp/org-export-to-clipboard ()
  "Export the region (or whole buffer) as plain ASCII into the kill ring."
  (interactive)
  (require 'ox-ascii)
  (let* ((beg (if (use-region-p) (region-beginning) (point-min)))
         (end (if (use-region-p) (region-end) (point-max)))
         (text (org-export-string-as
                (buffer-substring-no-properties beg end) 'ascii t)))
    (kill-new text)
    (message "Copied ASCII export to kill ring (%d chars)" (length text))))

;;; Org itself ----------------------------------------------------------------

(use-package org
  :ensure nil
  :hook ((org-mode . visual-line-mode)
         (org-mode . olivetti-mode)
         (org-mode . mp/org--tune-display)
         (org-mode . mp/org-settle-display))
  :config
  ;; Formerly `after! org' in the Doom config: these must run after Org loads
  ;; so nothing else (and no early default) clobbers them.

  ;; Which files the agenda scans.  Point at the whole org directory: org
  ;; re-expands a directory entry to every .org file in it each time the
  ;; agenda is built, so anything you drop in ~/org/ (todo.org, inbox.org,
  ;; projects.org, ...) shows up automatically — no per-file bookkeeping.
  (setq org-agenda-files (list org-directory))

  ;; Basic TODO workflow.
  ;; TODO      = not started
  ;; NEXT      = next concrete action
  ;; WAIT      = blocked by someone/something
  ;; SOMEDAY   = intentionally inactive
  ;; DONE      = completed
  ;; CANCELLED = no longer relevant
  (setq org-todo-keywords
        '((sequence "TODO(t)" "NEXT(n)" "WAIT(w)" "SOMEDAY(s)" "|"
                    "DONE(d)" "CANCELLED(c)")))

  ;; Save timestamp when marking DONE.
  (setq org-log-done 'time)

  (setq org-todo-keyword-faces
        '(("TODO" . warning)
          ("NEXT" . success)
          ("WAIT" . font-lock-constant-face)
          ("SOMEDAY" . font-lock-doc-face)
          ("DONE" . shadow)
          ("CANCELLED" . shadow)))

  ;; Use fast todo selection.
  (setq org-use-fast-todo-selection t)

  ;; Warn about deadlines 7 days in advance.
  (setq org-deadline-warning-days 7)

  ;; Make indentation readable.
  (setq org-startup-indented t)

  ;; Hide leading stars visually.
  (setq org-hide-leading-stars t)

  ;; Open folded files cleanly.
  (setq org-startup-folded 'content)

  ;; Log state changes into a drawer to avoid visual noise.
  (setq org-log-into-drawer t)

  ;; Refile targets.
  ;; This lets you move captured items from inbox.org into real files.
  (setq org-refile-targets
        '(("~/org/tasks.org" :maxlevel . 3)
          ("~/org/projects.org" :maxlevel . 4)
          ("~/org/calendar.org" :maxlevel . 2)
          ("~/org/someday.org" :maxlevel . 2)))

  ;; Make refile completion use full paths.
  (setq org-refile-use-outline-path 'file)
  (setq org-outline-path-complete-in-steps nil)

  ;; Archive completed old tasks here.
  (setq org-archive-location "~/org/archive.org::* From %s")

  ;; Capture templates.
  (setq org-capture-templates
        '(("t" "Todo" entry
           (file "~/org/inbox.org")
           "* TODO %?\nCREATED: %U\n")

          ("d" "Todo with deadline" entry
           (file "~/org/inbox.org")
           "* TODO %?\nDEADLINE: %^t\nCREATED: %U\n")

          ("s" "Scheduled todo" entry
           (file "~/org/inbox.org")
           "* TODO %?\nSCHEDULED: %^t\nCREATED: %U\n")

          ("e" "Event / calendar date" entry
           (file "~/org/calendar.org")
           "* %?\n%^T\n")

          ("r" "Repeating event" entry
           (file "~/org/calendar.org")
           "* %?\n%^T\n")

          ("p" "Project task" entry
           (file "~/org/projects.org")
           "* TODO %?\nCREATED: %U\n")

          ("n" "Note" entry
           (file "~/org/notes.org")
           "* %?\nCREATED: %U\n")))

  ;; Prevent alphabetical list markers from conflicting with checkbox parsing.
  (setq org-list-allow-alphabetical nil)

  (setq org-auto-align-tags nil
        org-tags-column 0
        org-fold-catch-invisible-edits 'show-and-error
        org-special-ctrl-a/e t
        org-insert-heading-respect-content t
        org-hide-emphasis-markers t
        org-pretty-entities t
        org-ellipsis "…"))

;;; Evil integration ----------------------------------------------------------

(use-package evil-org
  :hook (org-mode . evil-org-mode)
  :init
  (setq evil-org-key-theme
        '(navigation insert textobjects additional calendar todo heading))
  :config
  (require 'evil-org-agenda)
  (evil-org-agenda-set-keys))

;;; Appear --------------------------------------------------------------------

(use-package org-appear
  :hook (org-mode . org-appear-mode)
  :custom
  (org-appear-autolinks t)
  (org-appear-autoemphasis t)
  (org-appear-autosubmarkers t))

;;; Localleader ---------------------------------------------------------------

(mp/localleader
  :keymaps 'org-mode-map
  "#" #'org-update-statistics-cookies
  "'" #'org-edit-special
  "*" #'org-ctrl-c-star
  "-" #'org-ctrl-c-minus
  "," #'org-switchb
  "." #'consult-org-heading
  "/" #'consult-org-agenda
  "@" #'org-cite-insert
  "A" #'org-archive-subtree-default
  "e" #'org-export-dispatch
  "f" #'org-footnote-action
  "h" #'org-toggle-heading
  "i" #'org-toggle-item
  "I" #'org-id-get-create
  "k" #'org-babel-remove-result
  "n" #'org-store-link
  "o" #'org-set-property
  "q" #'org-set-tags-command
  "t" #'org-todo
  "T" #'org-todo-list
  "x" #'org-toggle-checkbox

  "a" '(:ignore t :which-key "attach")
  "a a" #'org-attach
  "a d" #'org-attach-delete-one
  "a D" #'org-attach-delete-all
  "a n" #'org-attach-new
  "a o" #'org-attach-open
  "a O" #'org-attach-open-in-emacs
  "a r" #'org-attach-reveal
  "a R" #'org-attach-reveal-in-emacs
  "a s" #'org-attach-set-directory
  "a S" #'org-attach-sync
  "a u" #'org-attach-url

  "b" '(:ignore t :which-key "tables")
  "b -" #'org-table-insert-hline
  "b a" #'org-table-align
  "b b" #'org-table-blank-field
  "b c" #'org-table-create-or-convert-from-region
  "b e" #'org-table-edit-field
  "b f" #'org-table-edit-formulas
  "b h" #'org-table-field-info
  "b r" #'org-table-recalculate
  "b R" #'org-table-recalculate-buffer-tables
  "b s" #'org-table-sort-lines
  "b d" '(:ignore t :which-key "delete")
  "b d c" #'org-table-delete-column
  "b d r" #'org-table-kill-row
  "b i" '(:ignore t :which-key "insert")
  "b i c" #'org-table-insert-column
  "b i h" #'org-table-insert-hline
  "b i H" #'org-table-hline-and-move
  "b i r" #'org-table-insert-row
  "b t" '(:ignore t :which-key "toggle")
  "b t f" #'org-table-toggle-formula-debugger
  "b t o" #'org-table-toggle-coordinate-overlays

  "c" '(:ignore t :which-key "clock")
  "c c" #'org-clock-cancel
  "c d" #'org-clock-mark-default-task
  "c e" #'org-clock-modify-effort-estimate
  "c E" #'org-set-effort
  "c g" #'org-clock-goto
  "c i" #'org-clock-in
  "c I" #'org-clock-in-last
  "c o" #'org-clock-out
  "c r" #'org-resolve-clocks
  "c R" #'org-clock-report
  "c t" #'org-evaluate-time-range
  "c =" #'org-clock-timestamps-up
  "c -" #'org-clock-timestamps-down

  "d" '(:ignore t :which-key "date/deadline")
  "d d" #'org-deadline
  "d s" #'org-schedule
  "d t" #'org-time-stamp
  "d T" #'org-time-stamp-inactive

  "g" '(:ignore t :which-key "goto")
  "g g" #'consult-org-heading
  "g G" #'consult-org-agenda
  "g c" #'org-clock-goto
  "g i" #'org-id-goto
  "g r" #'org-refile-goto-last-stored
  "g x" #'org-capture-goto-last-stored

  "l" '(:ignore t :which-key "links")
  "l i" #'org-id-store-link
  "l l" #'org-insert-link
  "l L" #'org-insert-all-links
  "l s" #'org-store-link
  "l S" #'org-insert-last-stored-link
  "l t" #'org-toggle-link-display

  "P" '(:ignore t :which-key "publish")
  "P a" #'org-publish-all
  "P f" #'org-publish-current-file
  "P p" #'org-publish
  "P P" #'org-publish-current-project
  "P s" #'org-publish-sitemap

  "p" '(:ignore t :which-key "priority")
  "p d" #'org-priority-down
  "p p" #'org-priority
  "p u" #'org-priority-up

  "r" '(:ignore t :which-key "refile")
  "r r" #'org-refile
  "r R" #'org-refile-reverse

  "s" '(:ignore t :which-key "subtree")
  "s a" #'org-toggle-archive-tag
  "s A" #'org-archive-subtree-default
  "s b" #'org-tree-to-indirect-buffer
  "s c" #'org-clone-subtree-with-time-shift
  "s d" #'org-cut-subtree
  "s h" #'org-promote-subtree
  "s j" #'org-move-subtree-down
  "s k" #'org-move-subtree-up
  "s l" #'org-demote-subtree
  "s n" #'org-narrow-to-subtree
  "s N" #'widen
  "s r" #'org-refile
  "s s" #'org-sparse-tree
  "s S" #'org-sort)

;; Skipped Doom-specific localleader binds:
;;   r v    +org/refile-to-visible
;;   r O    +org/refile-to-other-buffer
;;   r o    +org/refile-to-other-window
;;   r f    +org/refile-to-file
;;   r l    +org/refile-to-last-location
;;   r c    +org/refile-to-running-clock
;;   r .    +org/refile-to-current-file
;;   l y    +org/yank-link
;;   l d    +org/remove-link
;;   l c    org-cliplink (third-party package, not installed here)
;;   g v    +org/goto-visible
;;   c l    +org/toggle-last-clock
;;   a l    +org/attach-file-and-insert-link
;;   a f    +org/find-file-in-attachments
;;   K      +org/remove-result-blocks
;;   g r s / g r v / g d s / g d v / g f s
;;          mp/goto-{references,definition}-split-* + consult-lsp-file-symbols
;;          (global LSP localleader binds leaked into the manifest listing;
;;          handled centrally in mp-keys.el, not org-specific)
;; No org-agenda-mode localleader section exists in the manifest.

(mp/require-package "org-src-formatter")

(provide 'mp-org)
;;; mp-org.el ends here
