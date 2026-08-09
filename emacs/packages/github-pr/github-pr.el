;;; github-pr.el --- Read + reply to PR review comments from org -*- lexical-binding: t; -*-
;;
;; Pull a pull request's review-comment threads (inline "conversations") plus the
;; general discussion into an editable org buffer, newest-active thread first, and
;; reply by adding an empty-author level-2 heading.  All GitHub work is done by
;; the github_pr.py sidecar next to this file, which talks to the `gh' CLI (so gh
;; owns authentication and account selection — nothing to configure here).
;;
;; Commands:
;;   M-x github-pr            fetch a PR (prompts for url / number)
;;   M-x github-pr-submit     review the pending replies, then post on confirm
;;
;; In the PR buffer:
;;   C-c C-c   submit replies   C-c C-g   refetch   C-c C-k   close
;;
;; Vanilla-Emacs port: identical to the Doom-era package — it never used Doom
;; macros, had no SPC-leader binds (none to centralize in mp-keys.el) and no
;; popup rules.  Buffer-local C-c keys stay in `github-pr-mode-map'.
;;
;;; Code:

(require 'org)
(require 'json)

(defvar github-pr-dir
  (file-name-directory (or load-file-name buffer-file-name default-directory))
  "Directory holding github_pr.py (this file's directory).")

(defvar github-pr-script (expand-file-name "github_pr.py" github-pr-dir)
  "Path to the github_pr.py sidecar.")

(defvar github-pr-python "python3"
  "Python interpreter used to run the sidecar.")

(defvar github-pr-buffer "github-pr"
  "Name of the PR comments buffer.  No earmuffs so buffer switchers keep it.")

(defvar github-pr-preview-buffer "*github-pr-submit*"
  "Name of the submit-preview / progress buffer.")

(defvar github-pr-icon-reply "↩" "Icon shown for a pending reply in the preview.")

(defface github-pr-new-face '((t :inherit success))
  "Face for pending replies (green).")
(defface github-pr-fail-face '((t :inherit error))
  "Face for failed actions (red).")

;; --------------------------------------------------------------------------- ;;
;; Minor mode / keymap
;; --------------------------------------------------------------------------- ;;
(defvar github-pr-mode-map
  (let ((m (make-sparse-keymap)))
    (define-key m (kbd "C-c C-c") #'github-pr-submit)
    (define-key m (kbd "C-c C-g") #'github-pr-refresh)
    (define-key m (kbd "C-c C-k") #'github-pr-quit)
    m)
  "Keymap active in the PR comments buffer.")

(define-minor-mode github-pr-mode
  "Minor mode for the GitHub PR comments buffer."
  :lighter " PR"
  :keymap github-pr-mode-map)

(defun github-pr-quit ()
  "Close the PR comments buffer (and any preview window)."
  (interactive)
  (when-let ((w (get-buffer-window github-pr-preview-buffer))) (delete-window w))
  (when (get-buffer github-pr-preview-buffer) (kill-buffer github-pr-preview-buffer))
  (kill-buffer (current-buffer)))

;; --------------------------------------------------------------------------- ;;
;; Header helpers
;; --------------------------------------------------------------------------- ;;
(defun github-pr--buffer-header (key)
  "Return the value of the buffer's #+KEY: header, or nil."
  (let ((buf (get-buffer github-pr-buffer)))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (save-excursion
          (goto-char (point-min))
          (when (re-search-forward
                 (format "^#\\+%s:[ \t]*\\(.+?\\)[ \t]*$" (regexp-quote key)) nil t)
            (match-string-no-properties 1)))))))

(defun github-pr--buffer-url () (github-pr--buffer-header "GITHUB_URL"))
(defun github-pr--buffer-worktree () (github-pr--buffer-header "GITHUB_WORKTREE"))

(defun github-pr--candidate-worktree ()
  "The local git checkout the user is currently in, or nil.
Captured at command time; the sidecar decides whether its remote matches the PR."
  (or (and (fboundp 'magit-toplevel) (ignore-errors (magit-toplevel)))
      (ignore-errors (locate-dominating-file default-directory ".git"))))

(defun github-pr--parse-ref (input)
  "Parse a user-typed PR reference INPUT into (REF . REPO).
Handles a full url, owner/repo#N or owner/repo/N, a bare number, or a branch."
  (let ((s (string-trim input)))
    (cond
     ((string-match "\\`https?://" s) (cons s nil))
     ((string-match "\\`\\([^/[:space:]]+/[^/#[:space:]]+\\)[#/]\\([0-9]+\\)\\'" s)
      (cons (match-string 2 s) (match-string 1 s)))
     ((string-match "\\`#?\\([0-9]+\\)\\'" s) (cons (match-string 1 s) nil))
     (t (cons s nil)))))

;; --------------------------------------------------------------------------- ;;
;; Folding: hide property drawers on open
;; --------------------------------------------------------------------------- ;;
(defun github-pr--fold-drawers ()
  "Fold every :PROPERTIES: drawer in the current buffer."
  (org-with-wide-buffer
   (goto-char (point-min))
   (while (re-search-forward "^[ \t]*:PROPERTIES:[ \t]*$" nil t)
     (save-excursion
       (forward-line 0)
       (cond ((fboundp 'org-fold-hide-drawer-toggle) (org-fold-hide-drawer-toggle t))
             ((fboundp 'org-hide-drawer-toggle) (org-hide-drawer-toggle t))
             ((fboundp 'org-flag-drawer) (org-flag-drawer t)))))))

;; --------------------------------------------------------------------------- ;;
;; `ghpr-rev:' links — open a file at the revision a comment was written on
;; --------------------------------------------------------------------------- ;;
(defun github-pr-open-rev (path &optional _)
  "Follow a `ghpr-rev:SHA:relpath::LINE' link via magit, in the PR's checkout.
The checkout comes from the buffer's #+GITHUB_WORKTREE header (only present when
a local remote matched the PR)."
  (let ((worktree (github-pr--buffer-worktree)))
    (unless worktree (user-error "No local checkout recorded for this PR"))
    (unless (string-match "\\`\\([0-9a-fA-F]+\\):\\(.*?\\)\\(?:::\\([0-9]+\\)\\)?\\'" path)
      (user-error "Malformed ghpr-rev link: %s" path))
    (let ((rev (match-string 1 path))
          (rel (match-string 2 path))
          (line (match-string 3 path))
          (default-directory (file-name-as-directory worktree)))
      (unless (fboundp 'magit-find-file)
        (user-error "magit-find-file unavailable — install magit to open a file at a revision"))
      (magit-find-file rev rel)
      (when line
        (goto-char (point-min))
        (forward-line (1- (string-to-number line)))))))

(with-eval-after-load 'org
  (org-link-set-parameters "ghpr-rev" :follow #'github-pr-open-rev))

;; --------------------------------------------------------------------------- ;;
;; Pull
;; --------------------------------------------------------------------------- ;;
(defun github-pr--fill-buffer (buf out)
  "Replace BUF's contents with process buffer OUT, set up mode and folding."
  (with-current-buffer buf
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert-buffer-substring out)
      (goto-char (point-min))
      (org-mode)
      (github-pr-mode 1)
      (github-pr--fold-drawers))))

(defun github-pr--pull (ref &optional repo worktree)
  "Fetch REF (optionally in REPO) into the PR comments buffer.
WORKTREE is a local checkout to link files from and to resolve a bare PR number;
the sidecar only trusts it when its git remote actually matches the PR's repo."
  (let ((buf (get-buffer-create github-pr-buffer))
        (errbuf (get-buffer-create " *github-pr-stderr*"))
        ;; run the sidecar in the candidate checkout so `gh pr view N' resolves
        (default-directory (or (and worktree (file-directory-p worktree)
                                    (file-name-as-directory worktree))
                               default-directory)))
    (with-current-buffer buf
      (org-mode) (github-pr-mode 1)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "#+TITLE: GitHub PR\n\nfetching %s ...\n" ref))))
    (with-current-buffer errbuf (erase-buffer))
    (switch-to-buffer buf)
    (let ((out (generate-new-buffer " *github-pr-out*")))
      (make-process
       :name "github-pr-pull" :buffer out :stderr errbuf :noquery t
       :command (append (list github-pr-python github-pr-script "pull" "--pr" ref)
                        (when repo (list "--repo" repo))
                        (when worktree (list "--worktree" (expand-file-name worktree))))
       :sentinel
       (lambda (proc _event)
         (when (memq (process-status proc) '(exit signal))
           (if (and (eq (process-status proc) 'exit) (zerop (process-exit-status proc)))
               (progn
                 (github-pr--fill-buffer buf out)
                 (message "GitHub PR: fetched %s. Reply under a thread, then C-c C-c." ref))
             (message "GitHub PR fetch failed (see %s)" (buffer-name errbuf))
             (display-buffer errbuf))
           (kill-buffer out)))))))

;;;###autoload
(defun github-pr (ref)
  "Fetch a pull request's comments into an org buffer.
REF is a PR url, number, owner/repo#N, or branch; a bare number resolves against
the repository of the current directory (via `gh')."
  (interactive
   (list (read-string "GitHub PR (url or number): " (thing-at-point 'url t))))
  (let ((rr (github-pr--parse-ref ref)))
    (github-pr--pull (car rr) (cdr rr) (github-pr--candidate-worktree))))

;;;###autoload
(defun github-pr-refresh ()
  "Refetch the PR shown in the buffer, re-sorting by newest activity."
  (interactive)
  (let ((url (github-pr--buffer-url)))
    (if url (github-pr--pull url nil (github-pr--buffer-worktree))
      (user-error "No #+GITHUB_URL header — use M-x github-pr"))))

;; --------------------------------------------------------------------------- ;;
;; Submit: preview -> confirm -> streamed apply
;; --------------------------------------------------------------------------- ;;
(defun github-pr--run-json (&rest args)
  "Run the sidecar with ARGS and parse its single-line JSON stdout."
  (with-temp-buffer
    (let ((code (apply #'call-process github-pr-python nil t nil github-pr-script args)))
      (goto-char (point-min))
      (if (zerop code)
          (json-parse-buffer :object-type 'alist :array-type 'list :null-object nil)
        (user-error "github-pr sidecar failed: %s" (buffer-string))))))

(defvar-local github-pr--markers nil
  "Vector of status markers, one per action, in the preview buffer.")

(defun github-pr--render-preview (actions)
  "Render pending ACTIONS into the preview buffer; return it, recording markers."
  (let ((buf (get-buffer-create github-pr-preview-buffer)))
    (with-current-buffer buf
      (setq buffer-read-only nil)
      (erase-buffer)
      (insert (format "GitHub PR — %d pending repl%s\n\n"
                      (length actions) (if (= 1 (length actions)) "y" "ies")))
      (let ((vec (make-vector (length actions) nil)) (i 0))
        (dolist (a actions)
          (insert " ")
          (let ((m (point-marker)))
            (aset vec i m)
            (insert "…"))
          (insert "  "
                  (propertize github-pr-icon-reply 'face 'github-pr-new-face) "  "
                  (propertize (or (alist-get 'summary a) (alist-get 'type a))
                              'face 'github-pr-new-face)
                  "\n")
          (setq i (1+ i)))
        (setq-local github-pr--markers vec))
      (goto-char (point-min))
      (setq buffer-read-only t))
    buf))

(defun github-pr--set-status (idx glyph &optional face)
  "Replace the status glyph for action IDX with GLYPH in FACE."
  (when (and github-pr--markers (< idx (length github-pr--markers)))
    (let ((m (aref github-pr--markers idx)) (inhibit-read-only t))
      (when m
        (save-excursion
          (goto-char m)
          (delete-char 1)
          (insert (if face (propertize glyph 'face face) glyph)))))))

(defun github-pr--handle-event (ev)
  "Update the preview buffer from a single stream event EV (an alist)."
  (with-current-buffer (get-buffer-create github-pr-preview-buffer)
    (let ((event (alist-get 'event ev)) (idx (alist-get 'idx ev)))
      (pcase event
        ("start" (github-pr--set-status idx "⋯" 'shadow))
        ("retry" (github-pr--set-status idx "↻" 'warning))
        ("ok"    (github-pr--set-status idx "✓" 'success))
        ("fail"  (github-pr--set-status idx "✗" 'github-pr-fail-face)
                 (let ((inhibit-read-only t))
                   (goto-char (point-max))
                   (insert (format "\n ✗  reply %s failed after %s tries:\n    %s\n"
                                   idx (alist-get 'attempts ev) (alist-get 'error ev)))))
        ("error" (let ((inhibit-read-only t))
                   (goto-char (point-max))
                   (insert "\nPROBLEMS (nothing posted):\n")
                   (dolist (p (alist-get 'problems ev)) (insert "  ! " p "\n"))))
        ("done"  (let ((inhibit-read-only t))
                   (goto-char (point-max))
                   (insert (format "\n%s  posted %s/%s%s\n"
                                   (if (eq t (alist-get 'aborted ev)) "✗" "✓")
                                   (alist-get 'applied ev) (alist-get 'total ev)
                                   (if (eq t (alist-get 'aborted ev))
                                       " — ABORTED; unposted replies kept in the buffer" "")))))))))

(defun github-pr--apply (tmp)
  "Run streamed apply on TMP, updating the preview live; refetch when it finishes."
  (let ((acc "")
        (errbuf (get-buffer-create " *github-pr-apply-stderr*")))
    (with-current-buffer errbuf (erase-buffer))
    (make-process
     :name "github-pr-apply" :buffer (get-buffer-create " *github-pr-apply-out*")
     :stderr errbuf :noquery t
     :command (list github-pr-python github-pr-script "submit" "--file" tmp "--apply")
     :filter
     (lambda (_proc chunk)
       (setq acc (concat acc chunk))
       (while (string-match "\n" acc)
         (let ((line (substring acc 0 (match-beginning 0))))
           (setq acc (substring acc (match-end 0)))
           (unless (string-empty-p (string-trim line))
             (github-pr--handle-event
              (json-parse-string line :object-type 'alist :array-type 'list :null-object nil))))))
     :sentinel
     (lambda (proc _event)
       (when (memq (process-status proc) '(exit signal))
         (ignore-errors (delete-file tmp))
         ;; refetch so posted replies appear (and re-sort their threads to top)
         (when (and (eq (process-status proc) 'exit) (zerop (process-exit-status proc)))
           (github-pr-refresh)))))))

;;;###autoload
(defun github-pr-submit ()
  "Preview the buffer's pending replies, confirm, then post them to GitHub."
  (interactive)
  (unless (save-excursion (goto-char (point-min)) (re-search-forward "^#\\+GITHUB_PR:" nil t))
    (user-error "Not a PR comments buffer (no #+GITHUB_PR header)"))
  (let ((tmp (make-temp-file "github-pr" nil ".org")))
    (write-region (point-min) (point-max) tmp nil 'silent)
    (let* ((plan (github-pr--run-json "submit" "--file" tmp "--json"))
           (problems (alist-get 'problems plan))
           (actions (alist-get 'actions plan)))
      (cond
       (problems
        (with-current-buffer (github-pr--render-preview '())
          (let ((inhibit-read-only t))
            (goto-char (point-max))
            (insert "PROBLEMS — fix these, nothing posted:\n")
            (dolist (p problems) (insert "  ! " p "\n"))))
        (display-buffer-below-selected (get-buffer github-pr-preview-buffer) nil)
        (delete-file tmp)
        (message "GitHub PR: fix the problems shown above."))
       ((null actions)
        (delete-file tmp)
        (message "GitHub PR: no pending replies to post."))
       (t
        (let ((pbuf (github-pr--render-preview actions)))
          (display-buffer-below-selected pbuf nil)
          (if (yes-or-no-p (format "Post %d repl%s to GitHub? " (length actions)
                                   (if (= 1 (length actions)) "y" "ies")))
              (github-pr--apply tmp)
            (when-let ((w (get-buffer-window pbuf))) (delete-window w))
            (kill-buffer pbuf)
            (delete-file tmp)
            (message "GitHub PR: submit cancelled."))))))))

(provide 'github-pr)
;;; github-pr.el ends here
