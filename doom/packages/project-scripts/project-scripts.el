;;; project-scripts.el --- Pick and run a project script in a Ghostel terminal  -*- lexical-binding: t; -*-
;;; Commentary:
;; Run an executable from the project's __ignore__/scripts/ in a named
;; Ghostel terminal buffer, marking scripts already run this session.
;;; Code:

(defvar my/project-running-scripts (make-hash-table :test 'equal))

(defun my/project-scripts-dir ()
  (expand-file-name "__ignore__/scripts/" (projectile-project-root)))

(defun my/project-script-files ()
  (let ((dir (my/project-scripts-dir)))
    (when (file-directory-p dir)
      (directory-files dir t "\\.sh$"))))

(defun my/project-script-label (file)
  (let* ((project (projectile-project-root))
         (key (concat project "::" file))
         (name (file-name-base file)))
    (if (gethash key my/project-running-scripts)
        (concat "✓ " name)
      name)))

(defun my/run-project-script ()
  "Pick a project script and run it in a Ghostel terminal buffer."
  (interactive)
  (let* ((project (projectile-project-root))
         (files (my/project-script-files)))
    (unless files
      (user-error "No scripts found in __ignore__/scripts/"))

    (let* ((choices
            (mapcar (lambda (file)
                      (cons (my/project-script-label file) file))
                    files))
           (picked-label (completing-read "Run script: " choices nil t))
           (file (cdr (assoc picked-label choices)))
           (name (file-name-base file))
           (key (concat project "::" file))
           (buf-name (format "*project:%s*" name)))

      (puthash key t my/project-running-scripts)

      (let ((default-directory project)
            (existing (get-buffer buf-name)))
        ;; Reuse the script's terminal if it's still alive (rerun in the same
        ;; buffer), otherwise spawn a fresh Ghostel named for the script.
        (if (and existing
                 (buffer-live-p existing)
                 (buffer-local-value 'ghostel--term existing))
            (pop-to-buffer existing)
          (ghostel '(4))
          ;; Ghostel names buffers from `ghostel-buffer-name'; rename after the
          ;; fact instead of let-binding that defcustom (which trips a
          ;; lexical/dynamic error under lexical-binding when ghostel isn't
          ;; loaded yet). Renaming also makes Ghostel treat the buffer as
          ;; manually named, so shell OSC title reports won't rename it away.
          (rename-buffer buf-name t))
        (ghostel-send-string (shell-quote-argument file))
        (ghostel-send-key "return")
        (delete-other-windows)))))

(map! :leader
      :desc "Run project script"
      "p S" #'my/run-project-script)

(provide 'project-scripts)
;;; project-scripts.el ends here
