;;; clutch-connections.el --- Load & manage DB connections for clutch  -*- lexical-binding: t; -*-
;;; Commentary:
;; Reads database connections (URI strings or plists) from an EasyPG-encrypted
;; file `~/.config/doom/connections.json.gpg' and installs them as
;; `clutch-connection-alist'.  Plaintext `connections.json' is still read as a
;; fallback (with a nag to migrate) so nothing breaks mid-transition.
;;
;; Interactive management (edit / create / delete / rename), designed to be
;; driven from the minibuffer with consult/vertico:
;;   `mp/clutch-connections'          -- dispatcher: pick a connection or create
;;   `mp/clutch-connection-create'
;;   `mp/clutch-connection-edit'
;;   `mp/clutch-connection-delete'
;;   `mp/clutch-connection-rename'
;;   `mp/clutch-connection-copy-uri'
;;   `mp/clutch-migrate-to-gpg'       -- encrypt an existing plaintext file
;;
;; Secrets live only in the encrypted `.gpg' file.  Passwords are never shown
;; in the completion annotations (only backend/host/db/user).
;;; Code:

(require 'json)
(require 'subr-x)
(require 'epa-file)

;; Make sure EasyPG transparently handles the `.gpg' file for read AND write.
(epa-file-enable)

(defcustom mp/clutch-connections-gpg-recipient nil
  "GPG recipient (key id or email) used to encrypt the connections file.
When nil, EasyPG uses symmetric encryption and prompts for a passphrase.
Set to your key/email (e.g. \"mpourismaiel@gmail.com\") to encrypt to that
key instead — then gpg-agent can unlock it without retyping a passphrase."
  :type '(choice (const :tag "Symmetric (passphrase)" nil) string)
  :group 'clutch)

(defvar mp/clutch-connections-plain-file
  (expand-file-name "connections.json" doom-user-dir)
  "Legacy plaintext connections file (read-only fallback).")

(defvar mp/clutch-connections-gpg-file
  (expand-file-name "connections.json.gpg" doom-user-dir)
  "Encrypted connections file — the canonical, writable store.")

(defun mp/clutch--connections-file ()
  "Return the connections file to read from, preferring the encrypted one."
  (cond
   ((file-exists-p mp/clutch-connections-gpg-file) mp/clutch-connections-gpg-file)
   ((file-exists-p mp/clutch-connections-plain-file) mp/clutch-connections-plain-file)
   (t mp/clutch-connections-gpg-file)))

;;;; ── URI / plist normalization (unchanged behavior) ──────────────────────

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
   ;; PostgreSQL:  postgresql://user:pass@host:5432/database
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

   ;; MySQL:  mysql://user:pass@host:3306/database
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

   ;; SQLite:  sqlite:///home/mahdi/sqlite.db
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

;;;; ── Raw read / write (round-trips the on-disk JSON values) ──────────────

(defun mp/clutch--read-raw ()
  "Return an alist of (NAME . RAW-VALUE) from the connections file.
RAW-VALUE is a URI string or an alist (for object entries), preserved
verbatim so edits round-trip.  Reading a `.gpg' file decrypts transparently."
  (let ((file (mp/clutch--connections-file)))
    (when (file-exists-p file)
      (let ((json-object-type 'alist)
            (json-array-type 'list)
            (json-key-type 'string))
        (json-read-file file)))))

(defun mp/clutch--write-raw (alist)
  "Serialize ALIST to JSON and (re)write the ENCRYPTED connections file.
Always targets `mp/clutch-connections-gpg-file'; EasyPG encrypts on save."
  (let ((json-encoding-pretty-print t)
        ;; Encrypt to a specific key when configured, else symmetric.
        (epa-file-encrypt-to
         (and mp/clutch-connections-gpg-recipient
              (list mp/clutch-connections-gpg-recipient))))
    (with-temp-file mp/clutch-connections-gpg-file
      (insert (json-encode alist) "\n")))
  ;; If a stale plaintext copy is still lying around, warn loudly.
  (when (file-exists-p mp/clutch-connections-plain-file)
    (message "clutch: wrote encrypted store, but plaintext %s still exists — run M-x mp/clutch-migrate-to-gpg to remove it"
             mp/clutch-connections-plain-file)))

;;;; ── Loading into clutch ─────────────────────────────────────────────────

(defun mp/clutch-load-connections ()
  (let ((file (mp/clutch--connections-file)))
    (when (file-exists-p file)
      (when (and (equal file mp/clutch-connections-plain-file)
                 (not (file-exists-p mp/clutch-connections-gpg-file)))
        (message "clutch: connections are UNENCRYPTED (%s); run M-x mp/clutch-migrate-to-gpg"
                 mp/clutch-connections-plain-file))
      (let ((json-object-type 'alist)
            (json-array-type 'list)
            (json-key-type 'string))
        (mapcar
         (lambda (entry)
           (cons (car entry)
                 (mp/clutch--normalize-connection (cdr entry))))
         (json-read-file file))))))

(defun mp/clutch-apply-connections ()
  "Reload connections from disk into `clutch-connection-alist'."
  (interactive)
  (setq clutch-connection-alist
        (mp/clutch-load-connections))
  (message "Loaded %d Clutch connections from %s"
           (length clutch-connection-alist)
           (mp/clutch--connections-file)))

;;;; ── Interactive management (consult/minibuffer-friendly) ────────────────

(defun mp/clutch--summary (raw)
  "One-line, PASSWORD-FREE summary of a RAW connection value, for annotations."
  (condition-case _
      (let* ((pl   (mp/clutch--normalize-connection raw))
             (back (plist-get pl :backend))
             (host (plist-get pl :host))
             (port (plist-get pl :port))
             (db   (plist-get pl :database))
             (user (plist-get pl :user)))
        (string-trim
         (format "%s  %s%s%s%s"
                 (or back "?")
                 (or host "")
                 (if port (format ":%d" port) "")
                 (if db (format "/%s" db) "")
                 (if user (format "  (user %s)" user) ""))))
    (error "<unparseable entry>")))

(defvar mp/clutch--new-label "＋ New connection…"
  "Pseudo-candidate used to trigger connection creation.")

(defun mp/clutch--sort-candidates (cands)
  "Keep `mp/clutch--new-label' pinned first; preserve file order otherwise.
Used as the completion `display-sort-function' so the create entry never gets
sorted down among the saved connections."
  (if (member mp/clutch--new-label cands)
      (cons mp/clutch--new-label
            (remove mp/clutch--new-label (copy-sequence cands)))
    cands))

(defun mp/clutch--completion-table (names raw)
  "Build a completion table over NAMES annotated from RAW alist."
  (let ((annot
         (lambda (name)
           (if (string= name mp/clutch--new-label)
               ""
             (let ((v (cdr (assoc name raw))))
               (concat "  "
                       (propertize (mp/clutch--summary v)
                                   'face 'font-lock-comment-face)))))))
    (lambda (str pred action)
      (if (eq action 'metadata)
          `(metadata (annotation-function . ,annot)
                     (display-sort-function . mp/clutch--sort-candidates)
                     (cycle-sort-function . mp/clutch--sort-candidates)
                     (category . mp/clutch-connection))
        (complete-with-action action names str pred)))))

(defun mp/clutch--pick-connection (prompt)
  "Read an existing connection NAME with annotated completion."
  (let* ((raw (mp/clutch--read-raw)))
    (unless raw (user-error "No connections defined yet"))
    (completing-read prompt
                     (mp/clutch--completion-table (mapcar #'car raw) raw)
                     nil t)))

;;;###autoload
(defun mp/clutch-connections ()
  "Dispatcher: pick a connection to act on, or create a new one.
Uses `completing-read', so vertico/consult render it with live annotations."
  (interactive)
  (let* ((raw   (mp/clutch--read-raw))
         (names (mapcar #'car raw))
         (cands (cons mp/clutch--new-label names))
         (pick  (completing-read
                 "Clutch connection: "
                 (mp/clutch--completion-table cands raw)
                 nil t)))
    (if (string= pick mp/clutch--new-label)
        (mp/clutch-connection-create)
      (mp/clutch--connection-action pick))))

(defun mp/clutch--connection-action (name)
  "Prompt for an action to run against connection NAME."
  (pcase (completing-read (format "Connection %s → " name)
                          '("Connect" "Edit" "Copy URI" "Rename" "Delete")
                          nil t)
    ("Connect"  (mp/clutch-connection-connect name))
    ("Edit"     (mp/clutch-connection-edit name))
    ("Copy URI" (mp/clutch-connection-copy-uri name))
    ("Rename"   (mp/clutch-connection-rename name))
    ("Delete"   (mp/clutch-connection-delete name))))

;;;###autoload
(defun mp/clutch-connection-connect (name)
  "Open a clutch query console connected to saved connection NAME."
  (interactive (list (mp/clutch--pick-connection "Connect to: ")))
  (require 'clutch)
  ;; Make sure clutch sees the current on-disk connections before connecting.
  (mp/clutch-apply-connections)
  (clutch-query-console name))

;;;###autoload
(defun mp/clutch-connection-create ()
  "Create a new connection and save it to the encrypted store."
  (interactive)
  (let* ((raw  (mp/clutch--read-raw))
         (name (string-trim
                (read-string "New connection name (e.g. proj/env): ")))
         (_    (when (string-empty-p name)
                 (user-error "Name must not be empty")))
         (__   (when (assoc name raw)
                 (user-error "Connection %s already exists" name)))
         (uri  (read-string
                "Connection URI (postgresql://…  mysql://…  sqlite://…): ")))
    (mp/clutch--normalize-connection uri) ; validate before saving
    (mp/clutch--write-raw (append raw (list (cons name uri))))
    (mp/clutch-apply-connections)
    (message "Created connection %s" name)))

;;;###autoload
(defun mp/clutch-connection-edit (name)
  "Edit connection NAME in the minibuffer and re-save."
  (interactive (list (mp/clutch--pick-connection "Edit connection: ")))
  (let* ((raw  (mp/clutch--read-raw))
         (cell (assoc name raw)))
    (unless cell (user-error "No such connection: %s" name))
    (let ((val (cdr cell)))
      (if (stringp val)
          (setcdr cell (read-string (format "URI for %s: " name) val))
        ;; Object entry: edit its JSON text.
        (let* ((json-encoding-pretty-print nil)
               (new (read-string (format "JSON for %s: " name)
                                 (json-encode val)))
               (json-object-type 'alist)
               (json-array-type 'list)
               (json-key-type 'string))
          (setcdr cell (json-read-from-string new)))))
    (mp/clutch--normalize-connection (cdr cell)) ; validate
    (mp/clutch--write-raw raw)
    (mp/clutch-apply-connections)
    (message "Updated connection %s" name)))

;;;###autoload
(defun mp/clutch-connection-rename (name)
  "Rename connection NAME."
  (interactive (list (mp/clutch--pick-connection "Rename connection: ")))
  (let* ((raw  (mp/clutch--read-raw))
         (cell (assoc name raw))
         (new  (string-trim (read-string (format "Rename %s to: " name) name))))
    (unless cell (user-error "No such connection: %s" name))
    (when (string-empty-p new) (user-error "Name must not be empty"))
    (when (and (not (string= new name)) (assoc new raw))
      (user-error "Connection %s already exists" new))
    (setcar cell new)
    (mp/clutch--write-raw raw)
    (mp/clutch-apply-connections)
    (message "Renamed %s → %s" name new)))

;;;###autoload
(defun mp/clutch-connection-delete (name)
  "Delete connection NAME after confirmation."
  (interactive (list (mp/clutch--pick-connection "Delete connection: ")))
  (let ((raw (mp/clutch--read-raw)))
    (unless (assoc name raw) (user-error "No such connection: %s" name))
    (when (yes-or-no-p (format "Delete connection %s? " name))
      (mp/clutch--write-raw (assoc-delete-all name (copy-sequence raw)))
      (mp/clutch-apply-connections)
      (message "Deleted connection %s" name))))

;;;###autoload
(defun mp/clutch-connection-copy-uri (name)
  "Copy connection NAME's URI/JSON to the kill-ring (contains the password!)."
  (interactive (list (mp/clutch--pick-connection "Copy URI of: ")))
  (let ((val (cdr (assoc name (mp/clutch--read-raw)))))
    (unless val (user-error "No such connection: %s" name))
    (kill-new (if (stringp val) val (json-encode val)))
    (message "Copied %s to kill-ring (includes credentials)" name)))

;;;; ── Migration: plaintext → encrypted ────────────────────────────────────

(defun mp/clutch--shred (file)
  "Best-effort secure delete of FILE."
  (if (executable-find "shred")
      (call-process "shred" nil nil nil "-u" file)
    (delete-file file)))

;;;###autoload
(defun mp/clutch-migrate-to-gpg ()
  "Encrypt an existing plaintext `connections.json' into `connections.json.gpg'.
Offers to securely delete the plaintext afterwards."
  (interactive)
  (unless (file-exists-p mp/clutch-connections-plain-file)
    (user-error "No plaintext %s to migrate" mp/clutch-connections-plain-file))
  (when (and (file-exists-p mp/clutch-connections-gpg-file)
             (not (yes-or-no-p "connections.json.gpg already exists; overwrite from plaintext? ")))
    (user-error "Aborted"))
  (let* ((json-object-type 'alist)
         (json-array-type 'list)
         (json-key-type 'string)
         (raw (json-read-file mp/clutch-connections-plain-file)))
    (mp/clutch--write-raw raw)
    (mp/clutch-apply-connections)
    (message "Encrypted %d connections into %s"
             (length raw) mp/clutch-connections-gpg-file)
    (when (yes-or-no-p
           (format "Securely delete plaintext %s now? "
                   mp/clutch-connections-plain-file))
      (mp/clutch--shred mp/clutch-connections-plain-file)
      (message "Deleted plaintext connections.json — now ROTATE any credentials that were committed to git"))))

(with-eval-after-load 'clutch
  (mp/clutch-apply-connections))

(provide 'clutch-connections)
;;; clutch-connections.el ends here
