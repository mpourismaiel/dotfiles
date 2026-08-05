;;; clutch-connections.el --- Load DB connections for clutch from connections.json  -*- lexical-binding: t; -*-
;;; Commentary:
;; Reads ~/.config/doom/connections.json (URI strings or plists) and feeds
;; them to the `clutch' SQL client as `clutch-connection-alist'.
;;; Code:

(require 'json)
(require 'subr-x)

(defvar mp/clutch-connections-file
  (expand-file-name "connections.json" doom-user-dir))

(defun mp/clutch--json-key-to-keyword (key)
  (intern (concat ":" key)))

(defun mp/clutch--json-object-to-plist (obj)
  (let (plist)
    (dolist (pair obj (nreverse plist))
      (let ((key (car pair))
            (value (cdr pair)))
        (setq plist
              (cons value
                    (cons (mp/clutch--json-key-to-keyword key)
                          plist)))))))

(defun mp/clutch--uri-to-plist (uri)
  (cond
   ;; PostgreSQL:
   ;; postgresql://user:pass@host:5432/database
   ((string-match
     "\\`\\(postgresql\\|postgres\\)://\\(?:\\([^:/@]+\\)\\(?::\\([^@/]*\\)\\)?@\\)?\\([^:/]+\\)\\(?::\\([0-9]+\\)\\)?/\\(.+\\)\\'"
     uri)
    (let ((user (match-string 2 uri))
          (password (match-string 3 uri))
          (host (match-string 4 uri))
          (port (match-string 5 uri))
          (database (match-string 6 uri)))
      (append
       (list :backend 'pg
             :host host
             :database (url-unhex-string database))
       (when port
         (list :port (string-to-number port)))
       (when user
         (list :user (url-unhex-string user)))
       (when password
         (list :password (url-unhex-string password))))))

   ;; MySQL:
   ;; mysql://user:pass@host:3306/database
   ((string-match
     "\\`mysql://\\(?:\\([^:/@]+\\)\\(?::\\([^@/]*\\)\\)?@\\)?\\([^:/]+\\)\\(?::\\([0-9]+\\)\\)?/\\(.+\\)\\'"
     uri)
    (let ((user (match-string 1 uri))
          (password (match-string 2 uri))
          (host (match-string 3 uri))
          (port (match-string 4 uri))
          (database (match-string 5 uri)))
      (append
       (list :backend 'mysql
             :host host
             :database (url-unhex-string database))
       (when port
         (list :port (string-to-number port)))
       (when user
         (list :user (url-unhex-string user)))
       (when password
         (list :password (url-unhex-string password))))))

   ;; SQLite:
   ;; sqlite:///home/mahdi/sqlite.db
   ((string-match "\\`sqlite://\\(.+\\)\\'" uri)
    (list :backend 'sqlite
          :database (url-unhex-string (match-string 1 uri))))

   (t
    (user-error "Unsupported connection URI: %s" uri))))

(defun mp/clutch--normalize-backend (plist)
  (let ((backend (plist-get plist :backend)))
    (plist-put plist :backend
               (cond
                ((symbolp backend) backend)
                ((string= backend "postgres") 'pg)
                ((string= backend "postgresql") 'pg)
                ((string= backend "pg") 'pg)
                ((string= backend "mysql") 'mysql)
                ((string= backend "sqlite") 'sqlite)
                (t (intern backend))))))

(defun mp/clutch--normalize-connection (value)
  (cond
   ((stringp value)
    (mp/clutch--uri-to-plist value))
   ((listp value)
    (mp/clutch--normalize-backend
     (mp/clutch--json-object-to-plist value)))
   (t
    (user-error "Invalid connection value: %S" value))))

(defun mp/clutch-load-connections ()
  (when (file-exists-p mp/clutch-connections-file)
    (let ((json-object-type 'alist)
          (json-array-type 'list)
          (json-key-type 'string))
      (mapcar
       (lambda (entry)
         (cons (car entry)
               (mp/clutch--normalize-connection (cdr entry))))
       (json-read-file mp/clutch-connections-file)))))

(defun mp/clutch-apply-connections ()
  (interactive)
  (setq clutch-connection-alist
        (mp/clutch-load-connections))
  (message "Loaded %d Clutch connections from %s"
           (length clutch-connection-alist)
           mp/clutch-connections-file))

(with-eval-after-load 'clutch
  (mp/clutch-apply-connections))

(provide 'clutch-connections)
;;; clutch-connections.el ends here
