;;; org-src-formatter.el --- Format every src block in an Org buffer with external tools  -*- lexical-binding: t; -*-
;;; Commentary:
;; Runs a per-language external formatter (qmlformat, ruff, shfmt, ...) on
;; every recognised src block in an Org buffer.
;;; Code:

(defvar my/org-src-formatters
  ;; lang -> (FILE-EXTENSION PROGRAM ARGS...). The temp file path is appended,
  ;; so each tool must edit it in place.
  '(("qml"    . (".qml" "qmlformat" "-i" "-n")) ; -n = don't reorder imports
    ("python" . (".py"  "ruff" "format" "-q"))
    ("sh"     . (".sh"  "shfmt" "-w" "-i" "4" "-ci"))
    ("bash"   . (".sh"  "shfmt" "-w" "-i" "4" "-ci")))
  "Map of Org src-block language to its in-place formatter command.")

(defun my/format-string (str spec)
  "Format STR using SPEC = (EXT PROGRAM ARGS...).
Return the formatted text, or STR unchanged if PROGRAM is missing, exits
non-zero, or produces empty output."
  (let ((program (nth 1 spec)))
    (if (not (executable-find program))
        str
      (let ((tmp (make-temp-file "org-fmt" nil (nth 0 spec))))
        (unwind-protect
            (progn
              (with-temp-file tmp (insert str))
              (if (zerop (apply #'call-process program nil nil nil
                                (append (cddr spec) (list tmp))))
                  (let ((out (with-temp-buffer
                               (insert-file-contents tmp) (buffer-string))))
                    (if (string-blank-p out) str out))
                str))
          (delete-file tmp))))))

(defun my/org-format-src-blocks ()
  "Run a per-language formatter on every recognised src block in this buffer."
  (interactive)
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let ((case-fold-search t))
        (while (re-search-forward
                "^[ \t]*#\\+begin_src[ \t]+\\([^ \t\n]+\\)" nil t)
          (let* ((lang (downcase (match-string-no-properties 1)))
                 (spec (cdr (assoc lang my/org-src-formatters)))
                 (el   (org-element-at-point)))
            (when (and spec (eq (org-element-type el) 'src-block))
              (let* ((value     (org-element-property :value el))
                     (formatted (my/format-string value spec)))
                (when (and formatted (not (string= formatted value)))
                  (forward-line 1)             ; move to body start
                  (let ((body-start (point)))
                    (re-search-forward "^[ \t]*#\\+end_src" nil t)
                    (forward-line 0)
                    (delete-region body-start (point))
                    (goto-char body-start)
                    (insert formatted)
                    (unless (bolp) (insert "\n"))))))))))))

(provide 'org-src-formatter)
;;; org-src-formatter.el ends here
