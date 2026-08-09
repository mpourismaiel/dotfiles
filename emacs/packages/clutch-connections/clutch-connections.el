;;; clutch-connections.el --- Load & manage DB connections for clutch  -*- lexical-binding: t; -*-
;;; Commentary:
;; Stores database connections as full clutch objects and installs them as
;; `clutch-connection-alist'.  Storage backend is chosen via
;; `mp/clutch-connections-backend' (default `secret-service'):
;;   - `secret-service' : the freedesktop Secret Service (KWallet/gnome-keyring)
;;                        via `secrets.el' — unlocked once at login, no prompts.
;;   - `gpg'            : EasyPG-encrypted `connections.json.gpg' in `mp/emacs-dir'.
;;
;; Interactive management:
;;   `mp/clutch-connections'          -- dispatcher: pick a connection or create
;;   `mp/clutch-connection-create'    -- opens a prefilled JSONC edit buffer
;;   `mp/clutch-connection-edit'      -- opens the full-config JSONC edit buffer
;;   `mp/clutch-import-connection-string' -- (in the buffer) fill fields from a URL
;;   `mp/clutch-connection-connect'   -- open/connect a clutch query console
;;   `mp/clutch-connection-delete' / `-rename' / `-copy-uri'
;;
;; The edit buffer is JSONC (JSON + // comments): common keys are prefilled with
;; inline docs, optional keys shown as commented examples.  Empty values are
;; dropped on save.  Passwords are never shown in the completion annotations.
;;; Code:

(require 'json)
(require 'subr-x)
(require 'epa-file)

;; Make sure EasyPG transparently handles the `.gpg' file for read AND write.
(epa-file-enable)

;; `secrets' (Secret Service) and `clutch' are required lazily only when used,
;; so declare their functions to keep the byte-compiler quiet without forcing
;; D-Bus / clutch to load for GPG-only users.
(declare-function secrets-get-alias "secrets")
(declare-function secrets-get-secret "secrets")
(declare-function secrets-list-items "secrets")
(declare-function secrets-create-item "secrets")
(declare-function secrets-delete-item "secrets")
(declare-function clutch-query-console "clutch")

;; Defined in init.el (vanilla config root); declared for the byte-compiler.
(defvar mp/emacs-dir)

(defcustom mp/clutch-connections-backend 'secret-service
  "Where the connections store lives.

- `secret-service' : the freedesktop Secret Service (KWallet / gnome-keyring)
                     via `secrets.el'.  The keyring is unlocked once at login,
                     so there is no per-save password prompt.  This is the
                     default.
- `gpg'            : EasyPG-encrypted file `connections.json.gpg' (prompts
                     for a passphrase per save unless a key + gpg-agent is set)."
  :type '(choice (const :tag "Secret Service (KWallet/gnome-keyring)" secret-service)
                 (const :tag "Encrypted GPG file" gpg))
  :group 'clutch)

(defcustom mp/clutch-connections-gpg-recipient nil
  "GPG recipient (key id or email) used to encrypt the connections file.
When nil, EasyPG uses symmetric encryption and prompts for a passphrase.
Set to your key/email (e.g. \"mpourismaiel@gmail.com\") to encrypt to that
key instead — then gpg-agent can unlock it without retyping a passphrase.
Only relevant when `mp/clutch-connections-backend' is `gpg'."
  :type '(choice (const :tag "Symmetric (passphrase)" nil) string)
  :group 'clutch)

(defcustom mp/clutch-connections-ss-collection nil
  "Secret Service collection (keyring) to store connections in.
Nil means the default collection (usually \"Login\").  Only relevant when
`mp/clutch-connections-backend' is `secret-service'."
  :type '(choice (const :tag "Default collection" nil) string)
  :group 'clutch)

(defvar mp/clutch-connections-ss-label "Clutch DB connections"
  "Label of the single Secret Service item holding the connections JSON.")

;; Ported from Doom: `doom-user-dir' → `mp/emacs-dir' (deploy seeds
;; connections.json into the config root).
(defvar mp/clutch-connections-plain-file
  (expand-file-name "connections.json" mp/emacs-dir)
  "Legacy plaintext connections file (read-only fallback).")

(defvar mp/clutch-connections-gpg-file
  (expand-file-name "connections.json.gpg" mp/emacs-dir)
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

(defun mp/clutch--parse-uri-query (query)
  "Parse a URI QUERY string into a plist of extra clutch connection options.
Recognizes libpq-style `sslmode' (e.g. `?sslmode=verify-full').  Unknown
keys are ignored so pasted connection strings never break on extras."
  (when (and query (not (string-empty-p query)))
    (let (extra)
      (dolist (pair (split-string query "&" t))
        (let* ((kv (split-string pair "=" t))
               (key (downcase (url-unhex-string (car kv))))
               (val (and (cadr kv) (url-unhex-string (cadr kv)))))
          (pcase key
            ((or "sslmode" "ssl-mode")
             (setq extra (append extra (list :sslmode val))))
            (_ nil))))
      extra)))

(defun mp/clutch--uri-to-plist (uri)
  (cond
   ;; PostgreSQL:  postgresql://user:pass@host:5432/database[?sslmode=…]
   ((string-match
     "\\`\\(postgresql\\|postgres\\)://\\(?:\\([^:/@]+\\)\\(?::\\([^@/]*\\)\\)?@\\)?\\([^:/]+\\)\\(?::\\([0-9]+\\)\\)?/\\([^?]+\\)\\(?:\\?\\(.*\\)\\)?\\'"
     uri)
    (let ((user (match-string 2 uri))
          (password (match-string 3 uri))
          (host (match-string 4 uri))
          (port (match-string 5 uri))
          (database (match-string 6 uri))
          (query (match-string 7 uri)))
      (append
       (list :backend 'pg
             :host host
             :database (url-unhex-string database))
       (when port
         (list :port (string-to-number port)))
       (when user
         (list :user (url-unhex-string user)))
       (when password
         (list :password (url-unhex-string password)))
       (mp/clutch--parse-uri-query query))))

   ;; MySQL:  mysql://user:pass@host:3306/database[?…]
   ((string-match
     "\\`mysql://\\(?:\\([^:/@]+\\)\\(?::\\([^@/]*\\)\\)?@\\)?\\([^:/]+\\)\\(?::\\([0-9]+\\)\\)?/\\([^?]+\\)\\(?:\\?\\(.*\\)\\)?\\'"
     uri)
    (let ((user (match-string 1 uri))
          (password (match-string 2 uri))
          (host (match-string 3 uri))
          (port (match-string 4 uri))
          (database (match-string 5 uri))
          (query (match-string 6 uri)))
      (append
       (list :backend 'mysql
             :host host
             :database (url-unhex-string database))
       (when port
         (list :port (string-to-number port)))
       (when user
         (list :user (url-unhex-string user)))
       (when password
         (list :password (url-unhex-string password)))
       (mp/clutch--parse-uri-query query))))

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

(defun mp/clutch--encode-json (alist)
  "Pretty-print ALIST of connections to a JSON string."
  (let ((json-encoding-pretty-print t))
    (concat (json-encode alist) "\n")))

(defun mp/clutch--parse-json (string)
  "Parse a connections JSON STRING into a raw (NAME . VALUE) alist.
JSON `false' and `null' both map to nil so they prune cleanly."
  (when (and string (not (string-empty-p string)))
    (let ((json-object-type 'alist)
          (json-array-type 'list)
          (json-key-type 'string)
          (json-false nil)
          (json-null nil))
      (json-read-from-string string))))

;;;; ── Backend: encrypted GPG file ─────────────────────────────────────────

(defun mp/clutch--file-read-raw ()
  "Return the raw (NAME . VALUE) alist from the encrypted/plaintext file."
  (let ((file (mp/clutch--connections-file)))
    (when (file-exists-p file)
      (when (and (equal file mp/clutch-connections-plain-file)
                 (not (file-exists-p mp/clutch-connections-gpg-file)))
        (message "clutch: reading UNENCRYPTED %s (set a GPG recipient and re-save, or use the secret-service backend)"
                 mp/clutch-connections-plain-file))
      (let ((json-object-type 'alist)
            (json-array-type 'list)
            (json-key-type 'string))
        (json-read-file file)))))

(defun mp/clutch--file-write-raw (alist)
  "Write ALIST to the encrypted `connections.json.gpg' via EasyPG."
  (let ((epa-file-encrypt-to
         (and mp/clutch-connections-gpg-recipient
              (list mp/clutch-connections-gpg-recipient))))
    (with-temp-file mp/clutch-connections-gpg-file
      (insert (mp/clutch--encode-json alist))))
  (when (file-exists-p mp/clutch-connections-plain-file)
    (message "clutch: wrote encrypted store, but plaintext %s still exists — delete it to avoid a stale secret"
             mp/clutch-connections-plain-file)))

;;;; ── Backend: Secret Service (KWallet / gnome-keyring) ───────────────────

(defun mp/clutch--ss-collection ()
  "Return the Secret Service collection to use."
  (require 'secrets)
  (or mp/clutch-connections-ss-collection
      (secrets-get-alias "default")
      "Login"))

(defun mp/clutch--ss-read-raw ()
  "Return the raw connections alist from the Secret Service item, or nil."
  (require 'secrets)
  (mp/clutch--parse-json
   (secrets-get-secret (mp/clutch--ss-collection)
                       mp/clutch-connections-ss-label)))

(defun mp/clutch--ss-write-raw (alist)
  "Store ALIST as the single Secret Service connections item (replacing it)."
  (require 'secrets)
  (let ((coll (mp/clutch--ss-collection)))
    (when (member mp/clutch-connections-ss-label (secrets-list-items coll))
      (secrets-delete-item coll mp/clutch-connections-ss-label))
    (or (secrets-create-item coll
                             mp/clutch-connections-ss-label
                             (mp/clutch--encode-json alist)
                             :application "clutch" :name "connections")
        (user-error "Secret Service refused to store the item (keyring locked?)"))))

;;;; ── Backend dispatch ────────────────────────────────────────────────────

(defun mp/clutch--store-description ()
  "Human-readable description of the active store, for messages."
  (pcase mp/clutch-connections-backend
    ('secret-service (format "Secret Service (%s)" (mp/clutch--ss-collection)))
    (_ (mp/clutch--connections-file))))

(defun mp/clutch--read-raw ()
  "Return the raw (NAME . VALUE) alist from the active backend.
RAW-VALUE is an object alist (or a legacy URI string), preserved verbatim so
edits round-trip."
  (pcase mp/clutch-connections-backend
    ('secret-service (mp/clutch--ss-read-raw))
    (_ (mp/clutch--file-read-raw))))

(defun mp/clutch--write-raw (alist)
  "Persist ALIST to the active backend."
  (pcase mp/clutch-connections-backend
    ('secret-service (mp/clutch--ss-write-raw alist))
    (_ (mp/clutch--file-write-raw alist))))

;;;; ── Loading into clutch ─────────────────────────────────────────────────

(defun mp/clutch-load-connections ()
  (mapcar
   (lambda (entry)
     (cons (car entry)
           (mp/clutch--normalize-connection (cdr entry))))
   (mp/clutch--read-raw)))

(defun mp/clutch-apply-connections ()
  "Reload connections from the active backend into `clutch-connection-alist'."
  (interactive)
  (setq clutch-connection-alist
        (mp/clutch-load-connections))
  (message "Loaded %d Clutch connections from %s"
           (length clutch-connection-alist)
           (mp/clutch--store-description)))

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

;;;; ── Full-config edit buffer (JSONC) ─────────────────────────────────────

(defconst mp/clutch--edit-fields
  ;; (KEY DEFAULT COMMON-P COMMENT)  — COMMON keys are always active; the rest
  ;; render as commented examples unless the connection already sets them.
  '(("backend"         "pg"          t   "pg | mysql | sqlite | mongodb | oracle | sqlserver")
    ("host"            ""            t   "hostname or IP (omit for sqlite)")
    ("port"            5432          t   "pg 5432 · mysql 3306 · mongodb 27017 — a number, no quotes")
    ("user"            ""            t   "database user")
    ("password"        ""            t   "kept in the keyring; empty -> resolved via auth-source")
    ("database"        ""            t   "database name, or file path for sqlite")
    ("sslmode"         "verify-full" nil "PostgreSQL TLS: disable|prefer|require|verify-full  https://www.postgresql.org/docs/current/libpq-ssl.html")
    ("ssl-mode"        "disabled"    nil "MySQL only: \"disabled\" forces plaintext")
    ("schema"          "public"      nil "default schema / PostgreSQL search_path")
    ("ssh-host"        ""            nil "SSH tunnel via a ~/.ssh/config host (clutch runs ssh -N -L …)")
    ("sql-product"     "postgres"    nil "override the sql.el product if backend detection is wrong")
    ("connect-timeout" 10           nil "seconds — a number, no quotes")
    ("query-timeout"   20           nil "seconds — a number, no quotes")
    ("url"             ""            nil "JDBC URL for oracle/sqlserver/mongodb-sql backends")
    ("display-name"    ""            nil "friendly label shown in clutch's UI")
    ("auth-database"   "admin"       nil "MongoDB authentication database"))
  "Field spec driving the connection edit template.
Full key reference: the `clutch-connection-alist' docstring in clutch.")

(defconst mp/clutch--edit-header
  "// ══ Clutch connection ══════════════════════════════════════════════════
//  C-c C-c  save & close      C-c C-k  cancel      C-c C-i  import a URL string
//  Empty values are dropped on save; numbers (port, timeouts) must be unquoted.
//  Full key reference: `clutch-connection-alist' docstring · https://github.com/LuciusChen/clutch
"
  "Comment banner inserted at the top of the edit buffer.")

(defun mp/clutch--json-val (v)
  "Render V as a JSON literal string."
  (cond
   ((null v) "\"\"")
   ((eq v t) "true")
   ((numberp v) (number-to-string v))
   ((stringp v) (json-encode-string v))
   (t (json-encode v))))

(defun mp/clutch--plist->field-alist (pl)
  "Convert connection plist PL to a string-keyed alist for the template."
  (let (out)
    (while pl
      (let ((k (substring (symbol-name (car pl)) 1))
            (v (cadr pl)))
        (push (cons k (if (symbolp v) (symbol-name v) v)) out))
      (setq pl (cddr pl)))
    (nreverse out)))

(defun mp/clutch--value->field-alist (val)
  "Convert a stored connection VAL (object alist or legacy URI) to a field alist."
  (cond
   ((stringp val) (mp/clutch--plist->field-alist (mp/clutch--uri-to-plist val)))
   ((listp val) (copy-alist val))
   (t nil)))

(defun mp/clutch--render-edit-text (name config)
  "Return the JSONC edit text for NAME prefilled from CONFIG (field alist)."
  (with-temp-buffer
    (insert mp/clutch--edit-header)
    (insert "{\n")
    (insert (format "  \"name\": %s,   // identifier shown in the picker (required)\n"
                    (mp/clutch--json-val (or name ""))))
    (let ((known '("name")))
      (dolist (spec mp/clutch--edit-fields)
        (pcase-let ((`(,key ,default ,common ,comment) spec))
          (push key known)
          (let* ((cell (assoc key config))
                 (val (if cell (cdr cell) default)))
            (insert (format "  %s%s: %s,%s// %s\n"
                            (if (or common cell) "" "// ")
                            (mp/clutch--json-val key)
                            (mp/clutch--json-val val)
                            (make-string (max 1 (- 28 (length (mp/clutch--json-val val)))) ?\s)
                            comment)))))
      ;; Preserve any extra keys the connection already has (e.g. "props").
      (dolist (pair config)
        (unless (member (car pair) known)
          (insert (format "  %s: %s,\n"
                          (mp/clutch--json-val (car pair))
                          (mp/clutch--json-val (cdr pair)))))))
    (insert "  // \"props\": { \"key\": \"value\" },   // extra backend properties (object)\n")
    (insert "}\n")
    (buffer-string)))

(defun mp/clutch--jsonc-to-json (text)
  "Strip // and /* */ comments (string-aware) and trailing commas from TEXT."
  (let ((len (length text)) (i 0) (chars '()))
    (while (< i len)
      (let ((c (aref text i))
            (n (if (< (1+ i) len) (aref text (1+ i)) 0)))
        (cond
         ;; string literal — copy verbatim, honoring escapes
         ((eq c ?\")
          (push c chars) (setq i (1+ i))
          (while (and (< i len) (not (eq (aref text i) ?\")))
            (when (eq (aref text i) ?\\)
              (push (aref text i) chars) (setq i (1+ i)))
            (when (< i len) (push (aref text i) chars) (setq i (1+ i))))
          (when (< i len) (push (aref text i) chars) (setq i (1+ i))))
         ;; // line comment
         ((and (eq c ?/) (eq n ?/))
          (setq i (+ i 2))
          (while (and (< i len) (not (eq (aref text i) ?\n))) (setq i (1+ i))))
         ;; /* block comment */
         ((and (eq c ?/) (eq n ?*))
          (setq i (+ i 2))
          (while (and (< (1+ i) len)
                      (not (and (eq (aref text i) ?*) (eq (aref text (1+ i)) ?/))))
            (setq i (1+ i)))
          (setq i (+ i 2)))
         (t (push c chars) (setq i (1+ i))))))
    (replace-regexp-in-string
     ",\\([[:space:]\n\r]*[]}]\\)" "\\1"
     (apply #'string (nreverse chars)))))

(defun mp/clutch--parse-edit-buffer ()
  "Parse the current edit buffer's JSONC into an object alist."
  (let ((json-object-type 'alist)
        (json-array-type 'list)
        (json-key-type 'string)
        (json-false nil)
        (json-null nil))
    (json-read-from-string
     (mp/clutch--jsonc-to-json
      (buffer-substring-no-properties (point-min) (point-max))))))

(defun mp/clutch--prune-config (alist)
  "Drop empty/nil values from ALIST; coerce numeric port/timeout strings."
  (let (out)
    (dolist (pair alist (nreverse out))
      (let ((k (car pair)) (v (cdr pair)))
        (unless (or (null v)
                    (and (stringp v) (string-empty-p (string-trim v))))
          (when (and (member k '("port" "connect-timeout" "read-idle-timeout"
                                 "query-timeout" "rpc-timeout"))
                     (stringp v)
                     (string-match-p "\\`[0-9]+\\'" (string-trim v)))
            (setq v (string-to-number (string-trim v))))
          (push (cons k v) out))))))

(defvar-local mp/clutch--edit-original-name nil
  "Name of the connection being edited, or nil when creating a new one.")

(defvar mp/clutch-connection-edit-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'mp/clutch--edit-save)
    (define-key map (kbd "C-c C-k") #'mp/clutch--edit-cancel)
    (define-key map (kbd "C-c C-i") #'mp/clutch-import-connection-string)
    map)
  "Keymap for `mp/clutch-connection-edit-mode'.")

(defvar mp/clutch-connection-edit-mode-syntax-table
  (let ((st (make-syntax-table)))
    (modify-syntax-entry ?\" "\"" st)
    (modify-syntax-entry ?/ ". 12" st)
    (modify-syntax-entry ?\n ">" st)
    st)
  "Syntax table giving JSONC strings and // comments.")

(define-derived-mode mp/clutch-connection-edit-mode prog-mode "Clutch-Conn"
  "Major mode for editing a single clutch DB connection as JSONC.
\\{mp/clutch-connection-edit-mode-map}"
  (setq-local comment-start "// ")
  (setq-local comment-end "")
  (setq-local font-lock-defaults
              '(("\"\\([A-Za-z0-9_-]+\\)\"[[:space:]]*:" 1 font-lock-keyword-face))))

(defun mp/clutch--open-edit-buffer (original-name name config)
  "Open the JSONC edit buffer. ORIGINAL-NAME is nil for a new connection."
  (let ((buf (get-buffer-create "*clutch-connection*")))
    (with-current-buffer buf
      (mp/clutch-connection-edit-mode)
      (setq mp/clutch--edit-original-name original-name)
      (erase-buffer)
      (insert (mp/clutch--render-edit-text name config))
      (goto-char (point-min))
      (when (re-search-forward "\"name\": \"\\(\\)\"" nil t)
        (goto-char (match-beginning 1))))
    (pop-to-buffer buf)
    (message "Edit, then C-c C-c to save · C-c C-k cancel · C-c C-i import a URL string")))

;;;###autoload
(defun mp/clutch-connection-create ()
  "Open an edit buffer prefilled with a blank connection template."
  (interactive)
  (mp/clutch--open-edit-buffer nil "" nil))

;;;###autoload
(defun mp/clutch-connection-edit (name)
  "Open the full-config edit buffer for connection NAME."
  (interactive (list (mp/clutch--pick-connection "Edit connection: ")))
  (let ((cell (assoc name (mp/clutch--read-raw))))
    (unless cell (user-error "No such connection: %s" name))
    (mp/clutch--open-edit-buffer name name
                                 (mp/clutch--value->field-alist (cdr cell)))))

(defun mp/clutch--edit-save ()
  "Validate and persist the connection in the current edit buffer."
  (interactive)
  (let* ((obj (condition-case e (mp/clutch--parse-edit-buffer)
                (error (user-error "Invalid JSON: %s" (error-message-string e)))))
         (name (string-trim (or (cdr (assoc "name" obj)) "")))
         (config (mp/clutch--prune-config
                  (assoc-delete-all "name" (copy-alist obj))))
         (original mp/clutch--edit-original-name))
    (when (string-empty-p name) (user-error "\"name\" is required"))
    (let ((backend (cdr (assoc "backend" config))))
      (when (or (null backend) (and (stringp backend) (string-empty-p backend)))
        (user-error "\"backend\" is required (pg, mysql, sqlite, …)")))
    (condition-case e (mp/clutch--normalize-connection config)
      (error (user-error "Invalid connection: %s" (error-message-string e))))
    (let ((raw (mp/clutch--read-raw)))
      (when (and original (not (string= original name)))
        (setq raw (assoc-delete-all original (copy-alist raw))))
      (when (and (assoc name raw)
                 (not (equal original name))
                 (not (yes-or-no-p (format "Connection %s exists; overwrite? " name))))
        (user-error "Aborted"))
      (if (assoc name raw)
          (setcdr (assoc name raw) config)
        (setq raw (append raw (list (cons name config)))))
      (mp/clutch--write-raw raw)
      (mp/clutch-apply-connections)
      (message "Saved connection %s" name))
    (quit-window t)))

(defun mp/clutch--edit-cancel ()
  "Discard the edit buffer."
  (interactive)
  (quit-window t))

;;;###autoload
(defun mp/clutch-import-connection-string (uri)
  "Convert a DB connection URI into the fields of the current edit buffer.
Prompts for URI in the echo area; keeps whatever name you have already typed."
  (interactive (list (read-string
                      "Connection string (postgresql://…  mysql://…  sqlite://…): ")))
  (unless (derived-mode-p 'mp/clutch-connection-edit-mode)
    (user-error "Run this inside a clutch connection edit buffer (M-x mp/clutch-connection-create)"))
  (let* ((plist (condition-case e (mp/clutch--uri-to-plist (string-trim uri))
                  (error (user-error "%s" (error-message-string e)))))
         (config (mp/clutch--plist->field-alist plist))
         (name (condition-case nil
                   (or (cdr (assoc "name" (mp/clutch--parse-edit-buffer))) "")
                 (error ""))))
    (erase-buffer)
    (insert (mp/clutch--render-edit-text name config))
    (goto-char (point-min))
    (message "Imported %s connection from string — review and C-c C-c to save"
             (or (plist-get plist :backend) "?"))))

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

(with-eval-after-load 'clutch
  (mp/clutch-apply-connections))

(provide 'clutch-connections)
;;; clutch-connections.el ends here
