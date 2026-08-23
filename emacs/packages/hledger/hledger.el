;;; hledger.el --- hledger finance commands -*- lexical-binding: t; -*-

;; Ported from the Doom-era doom/packages/hledger/hledger.el.

(defvar mp/hledger-directory (expand-file-name "~/Documents/finance/")
  "Base directory holding the finance BOOKS (entities).")

(defvar mp/hledger-entity "personal"
  "The active finance book. `personal' is the set of journals sitting directly
in `mp/hledger-directory'; any other value names a subfolder of it that has its
own main.journal (e.g. \"company\"). `mp/hledger-switch-entity' changes it.")

(defvar mp/hledger-bridge
  (expand-file-name "~/.config/quickshell/pill/hledgerbridge.py")
  "The Python bridge shared with the Quickshell pill. Emacs shells out to it for
the savings plan and the wishlist so that math lives in exactly ONE place.")

(defun mp/hledger--entity-dir (&optional entity)
  "Directory of the finance book ENTITY (default `mp/hledger-entity').
`personal' resolves to the base dir when it holds the root journals, otherwise
to base/personal; any other name is a subfolder of the base dir."
  (let ((e (or entity mp/hledger-entity)))
    (if (member e '("personal" "" nil))
        (if (file-exists-p (expand-file-name "main.journal" mp/hledger-directory))
            (file-name-as-directory mp/hledger-directory)
          (file-name-as-directory (expand-file-name "personal" mp/hledger-directory)))
      (file-name-as-directory (expand-file-name e mp/hledger-directory)))))

(defun mp/hledger--main-file ()
  "Entry-point journal of the current book; every hledger call reads through it."
  (expand-file-name "main.journal" (mp/hledger--entity-dir)))

;; ledger-mode drives .journal buffers, with hledger as the binary. All the
;; editing features (font-lock, TAB alignment, account completion) work on
;; buffer text, so they are hledger-compatible; only the ledger-CLI-calling
;; commands (ledger-add-transaction, ledger-reconcile) are off-limits.
;; ledger-mode itself is installed/associated by mp-langs.el; this only adds
;; the config it needs to speak hledger.
(add-to-list 'auto-mode-alist '("\\.journal\\'" . ledger-mode))

(with-eval-after-load 'ledger-mode
  (setq ledger-binary-path "hledger"
        ledger-default-date-format ledger-iso-date-format
        ledger-clear-whole-transactions 1
        ;; CRITICAL for hledger: on activation `ledger-mode' runs
        ;; `ledger-check-version', which shells out with ledger-CLI-only flags
        ;; (`--date-format %Y-%m-%d'). hledger doesn't understand `--date-format'
        ;; and parses the format string as a subcommand -> "command %Y-%m-%d is
        ;; not recognized" on every journal open. Doom's :lang ledger module set
        ;; this nil; the port dropped it. Never version-check against hledger.
        ledger-mode-should-check-version nil
        ;; account declarations in main.journal feed completion everywhere
        ledger-accounts-file (mp/hledger--main-file))

  ;; Fail gracefully if the binary is missing, instead of erroring.
  (advice-add 'ledger-check-version :around
              (lambda (fn)
                (if (executable-find ledger-binary-path)
                    (funcall fn)
                  (message "Couldn't find `%s' executable" ledger-binary-path))))

  (add-hook 'ledger-mode-hook #'outline-minor-mode)

  ;; imenu support (jump to outline headings / transactions).
  (add-hook 'ledger-mode-hook
            (lambda ()
              (setq-local imenu-generic-expression
                          `((nil ,(concat
                                   "^[\\*]+[ \t]+\\([^\n\r]+\\)\\|"
                                   "^[0-9]\\{4\\}[-/.][0-9]\\{2\\}[-/.][0-9]\\{2\\}[ \t]+[^\n]+")
                                 0))))))

;; The stock `ledger' flycheck checker shells out with ledger-CLI-only flags;
;; flycheck-hledger is the hledger-native replacement.
(with-eval-after-load 'flycheck
  (add-to-list 'flycheck-disabled-checkers 'ledger))

;; flycheck runs on the CURRENT buffer's file. Because commodity/account
;; declarations live only in main.journal, checking a monthly file standalone
;; with --strict falsely reports "IRT/<account> not declared". So keep live
;; flycheck NON-strict (it still catches parse errors, unbalanced entries and
;; failed balance assertions — the useful per-buffer feedback). The real
;; declared-ness check runs against the whole journal on demand: `SPC o l c`.
;; This is the ONLY declaration of flycheck-hledger; use-package-always-ensure
;; installs it from MELPA.
(use-package flycheck-hledger
  :after (flycheck ledger-mode)
  :config
  (setq flycheck-hledger-strict nil))

(defvar-local mp/hledger--report-rerun nil
  "Closure that regenerates the current report buffer.")

(define-derived-mode mp/hledger-report-mode special-mode "hledger"
  "Read-only display for hledger reports.")

(defun mp/hledger-report-refresh ()
  "Re-run the command that produced this report buffer."
  (interactive)
  (when mp/hledger--report-rerun
    (funcall mp/hledger--report-rerun)))

(evil-define-key 'normal mp/hledger-report-mode-map
  "g" #'mp/hledger-report-refresh
  "q" #'quit-window)

;; Doom's `set-popup-rule!' "^\\*hledger" :side bottom :size 0.5 :select t,
;; reproduced with display-buffer-alist + popper.
(add-to-list 'display-buffer-alist
             '("^\\*hledger"
               (display-buffer-in-side-window)
               (side . bottom)
               (window-height . 0.5)
               (body-function . select-window)))
(with-eval-after-load 'popper
  (setq popper-reference-buffers
        (append popper-reference-buffers '("^\\*hledger"))))

(defun mp/hledger--display (name text rerun)
  "Show TEXT in the report buffer *hledger: NAME*; `g' calls RERUN."
  (let ((buf (get-buffer-create (format "*hledger: %s*" name))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert text)
        (ansi-color-apply-on-region (point-min) (point-max))
        (goto-char (point-min)))
      (mp/hledger-report-mode)
      (setq mp/hledger--report-rerun rerun))
    (pop-to-buffer buf)))

(defun mp/hledger--output (args &optional file)
  "Run hledger ARGS against FILE (default: current book's main) → (EXIT . OUTPUT)."
  (with-temp-buffer
    (let ((exit (apply #'call-process "hledger" nil t nil
                       "-f" (or file (mp/hledger--main-file)) args)))
      (cons exit (buffer-string)))))

(defun mp/hledger--run (name args &optional file)
  "Run hledger ARGS (colorized) and display the output as report NAME.
Non-personal books get their name prefixed so the buffer says which book."
  (let* ((name (if (string= mp/hledger-entity "personal") name
                 (format "%s · %s" mp/hledger-entity name)))
         (res (mp/hledger--output (append args '("--color=always")) file))
         (text (if (zerop (car res))
                   (cdr res)
                 (concat (propertize (format "hledger exited %d\n\n" (car res))
                                     'face 'error)
                         (cdr res)))))
    (mp/hledger--display name text (lambda () (mp/hledger--run name args file)))))

(defun mp/hledger--bridge (&rest args)
  "Run the shared Python bridge for the current book; return parsed JSON or nil.
JSON false → :false, null → nil, objects → alists, arrays → lists."
  (with-temp-buffer
    (when (zerop (apply #'call-process "python3" nil t nil
                        mp/hledger-bridge "--entity" mp/hledger-entity args))
      (goto-char (point-min))
      (ignore-errors
        (json-parse-buffer :object-type 'alist :array-type 'list
                           :false-object :false :null-object nil)))))

(defun mp/hledger--month-file (&optional time)
  "Monthly journal path for TIME (default: now) in the current book."
  (expand-file-name (downcase (format-time-string "%Y-%B.journal" time))
                    (mp/hledger--entity-dir)))

(defun mp/hledger--ensure-month-file (file)
  "Create the monthly journal FILE with a header comment if missing."
  (unless (file-exists-p file)
    (with-temp-file file
      (insert "; " (file-name-nondirectory file) "\n")))
  file)

(defun mp/hledger--journal-files ()
  "Journal file names in the current book, current month first, then
main/forecast/wishlist, then past months newest-first."
  (let* ((all (directory-files (mp/hledger--entity-dir) nil "\\.journal\\'"))
         (head (list (file-name-nondirectory (mp/hledger--month-file))
                     "main.journal" "forecast.journal" "wishlist.journal"))
         (rest (sort (seq-difference all head) #'string>)))
    (append (seq-filter (lambda (f) (member f all)) head) rest)))

(defun mp/hledger--accounts ()
  "All account names known to hledger (declared or used)."
  (split-string (cdr (mp/hledger--output '("accounts"))) "\n" t))

(defun mp/hledger--read-amount ()
  "Read an amount with commodity, e.g. \"12.50 EUR\" or \"500,000 IRT\".
Asks for the commodity separately when it was left off. Validation stays
permissive — hledger itself checks the entry after it is written."
  (let ((amt (string-trim (read-string "Amount (e.g. 12.50 EUR): "))))
    (if (string-match-p "[[:alpha:]]" amt)
        amt
      (concat amt " " (completing-read "Commodity: " '("EUR" "IRT") nil nil)))))

(defun mp/hledger--parse-bare-tsv (args &optional file)
  "Run hledger ARGS with a bare TSV layout; return rows as string lists.
Each row is (ACCOUNT COMMODITY BALANCE); the header row is dropped, and
balances come back as plain unformatted numbers."
  (let ((res (mp/hledger--output (append args '("--layout" "bare" "-O" "tsv")) file)))
    (when (zerop (car res))
      (cdr (mapcar (lambda (l) (split-string l "\t"))
                   (split-string (cdr res) "\n" t))))))

(defun mp/hledger--fmt-num (n)
  "Format N with thousands separators; two decimals unless it is whole.
Handles negatives (the sign stays attached, not split off by the grouping)."
  (let* ((neg (< n 0))
         (n (abs n))
         (whole (= n (ftruncate n)))
         (s (if whole (format "%d" (truncate n)) (format "%.2f" n)))
         (parts (split-string s "\\."))
         (int (car parts))
         (out ""))
    (while (> (length int) 3)
      (setq out (concat "," (substring int -3) out)
            int (substring int 0 -3)))
    (concat (and neg "-") int out (if (cdr parts) (concat "." (cadr parts)) ""))))

(defun mp/hledger--fmt-money (n cur)
  "Format number N with a currency suffix, e.g. \"1,234.50 EUR\"."
  (format "%s %s" (mp/hledger--fmt-num (float (or n 0))) cur))

;;;; Rolling balances (SVG header + add-transaction annotations)
;;
;; "Balance accounts" = the balance-sheet accounts that carry a running total
;; (assets + liabilities, hledger `type:AL'), as opposed to the flow accounts
;; (income/expenses). Their current balances are shown live in the SVG header
;; of every `.journal' buffer, and offered as completion annotations while
;; adding a transaction (`SPC o l a'), so you always see where each account
;; stands as you edit. Both read from one place so the numbers agree.

(defface mp/hledger-amount-positive '((t :inherit success))
  "Face for non-negative balances in the header/annotations.")

(defface mp/hledger-amount-negative '((t :inherit error))
  "Face for negative balances (money owed) in the header/annotations.")

(defvar mp/hledger-header-max-accounts 12
  "Maximum number of balance accounts shown in the journal SVG header.")

(defun mp/hledger--journal-buffer-p ()
  "Non-nil when the current buffer visits an hledger `.journal' file."
  (and buffer-file-name (string-suffix-p ".journal" buffer-file-name)))

(defun mp/hledger--balance-alist (&optional query)
  "Return an alist of ACCOUNT -> \"AMT CUR[, AMT CUR]\" via `hledger balance'.
QUERY is an extra query argument list (e.g. \\='(\"type:AL\")) narrowing which
accounts to include.  Accounts holding more than one commodity get their
per-commodity amounts comma-joined into a single string.  Order follows
hledger's output (accounts with no balance are already omitted)."
  (let ((rows (mp/hledger--parse-bare-tsv
               (append '("balance" "-N" "--flat") query)))
        (map (make-hash-table :test 'equal))
        (order nil))
    (dolist (r rows)
      (pcase-let ((`(,acct ,cur ,bal) r))
        (when (and acct cur bal)
          (unless (member acct order) (push acct order))
          (let ((amt (mp/hledger--fmt-money (string-to-number bal) cur)))
            (puthash acct
                     (if (gethash acct map)
                         (concat (gethash acct map) ", " amt)
                       amt)
                     map)))))
    (mapcar (lambda (a) (cons a (gethash a map))) (nreverse order))))

(defun mp/hledger--amount-face (amount)
  "Return the face for the balance string AMOUNT (negative → owed)."
  (if (string-prefix-p "-" amount)
      'mp/hledger-amount-negative
    'mp/hledger-amount-positive))

;;; SVG-header cache.  `mp/hledger-header-balance-rows' is called on every
;;; redisplay, so it must be cheap: it shells out only when a journal was just
;;; saved (`mp/hledger--header-dirty') or the active book changed, and serves
;;; the cached rows otherwise.  Cache is book-global (all journals of a book
;;; share its balances), not per-buffer.

(defvar mp/hledger--header-rows nil
  "Cached list of propertized balance-account rows for the header.")
(defvar mp/hledger--header-rows-entity nil
  "Book (`mp/hledger-entity') the header cache was computed for.")
(defvar mp/hledger--header-dirty t
  "Non-nil when the header balance cache must be recomputed.")

(defun mp/hledger--header-compute ()
  "Compute propertized balance-account rows for the SVG header.
One line per balance account: the account name (dimmed, left-padded to a
common width) followed by its current balance, coloured by sign."
  (let* ((alist (seq-take (mp/hledger--balance-alist '("type:AL"))
                          mp/hledger-header-max-accounts))
         (width (if alist
                    (apply #'max (mapcar (lambda (c) (length (car c))) alist))
                  0)))
    (mapcar
     (lambda (cell)
       (let* ((acct (car cell))
              (amt (or (cdr cell) ""))
              (pad (make-string (max 0 (- width (length acct))) ?\s)))
         (concat
          (propertize (concat acct pad) 'face 'shadow)
          "  "
          (propertize amt 'face (mp/hledger--amount-face amt)))))
     alist)))

(defun mp/hledger-header-balance-rows ()
  "Cached propertized balance-account rows for the journal SVG header.
Cheap on redisplay: recomputes only when a journal was saved or the active
book changed.  Returns a list of already-propertized strings, or nil when the
current buffer is not a journal."
  (when (mp/hledger--journal-buffer-p)
    (when (or mp/hledger--header-dirty
              (not (equal mp/hledger--header-rows-entity mp/hledger-entity)))
      (setq mp/hledger--header-rows
            (ignore-errors (mp/hledger--header-compute))
            mp/hledger--header-rows-entity mp/hledger-entity
            mp/hledger--header-dirty nil))
    mp/hledger--header-rows))

(defun mp/hledger--header-invalidate (&rest _)
  "Mark the header balance cache stale so the next redisplay recomputes it."
  (setq mp/hledger--header-dirty t))

;; Any journal save changes the balances shown in the header.
(add-hook 'after-save-hook
          (lambda ()
            (when (mp/hledger--journal-buffer-p)
              (mp/hledger--header-invalidate))))

(defun mp/hledger--account-collection (accounts balances)
  "Return a completion table over ACCOUNTS annotating each with its balance.
BALANCES is an alist ACCOUNT -> balance-string (from
`mp/hledger--balance-alist'); the current balance is shown, dimmed, to the
right of each candidate so you see where an account stands while picking it."
  (lambda (string pred action)
    (if (eq action 'metadata)
        `(metadata
          (annotation-function
           . ,(lambda (cand)
                (when-let ((bal (cdr (assoc cand balances))))
                  (concat "  " (propertize bal 'face 'shadow))))))
      (complete-with-action action accounts string pred))))

(defun mp/hledger-open-journal ()
  "Pick and open a journal file (current month offered first)."
  (interactive)
  (find-file (expand-file-name
              (completing-read "Journal: " (mp/hledger--journal-files) nil t)
              mp/hledger-directory)))

(defun mp/hledger-open-current-month ()
  "Open this month's journal, creating it from the template if missing.
This is also how a new month's file is born — main.journal's include glob
picks it up automatically."
  (interactive)
  (find-file (mp/hledger--ensure-month-file (mp/hledger--month-file))))

(defun mp/hledger-open-forecast ()
  "Open the current book's forecast.journal."
  (interactive)
  (find-file (expand-file-name "forecast.journal" (mp/hledger--entity-dir))))

(defun mp/hledger-open-wishlist ()
  "Open the current book's wishlist.journal."
  (interactive)
  (find-file (expand-file-name "wishlist.journal" (mp/hledger--entity-dir))))

(defun mp/hledger-open-plan-config ()
  "Open the current book's plan.conf (buffer + savings goal for the plan)."
  (interactive)
  (find-file (expand-file-name "plan.conf" (mp/hledger--entity-dir))))

(defun mp/hledger-add-transaction ()
  "Guided quick-add: append a transaction to the right monthly journal.
Prompts for date, description, target account, amount and source account,
appends an aligned entry, saves, and runs `hledger check' on the result."
  (interactive)
  (let* ((date (read-string "Date: " (format-time-string "%Y-%m-%d")))
         (desc (read-string "Description: "))
         (accounts (mp/hledger--accounts))
         ;; Current per-account balances, shown as completion annotations so the
         ;; rolling balance of each account is visible while choosing it.
         (balances (mp/hledger--balance-alist))
         (table (mp/hledger--account-collection accounts balances))
         (target (completing-read "Account (to): " table nil nil "expenses:"))
         (amount (mp/hledger--read-amount))
         (source (completing-read "Account (from): " table nil nil "assets:"))
         (parsed (parse-time-string date))
         (time (encode-time 0 0 0 (or (nth 3 parsed) 1) (nth 4 parsed) (nth 5 parsed)))
         (file (mp/hledger--ensure-month-file (mp/hledger--month-file time))))
    (with-current-buffer (find-file-noselect file)
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (insert "\n" date " " desc "\n"
              (format "    %-28s  %s\n" target amount)
              "    " source "\n")
      (save-buffer))
    (let ((res (mp/hledger--output '("check"))))
      (if (zerop (car res))
          (message "Added to %s — journal OK" (file-name-nondirectory file))
        (mp/hledger--display
         "check" (cdr res)
         (lambda () (mp/hledger-check)))))))

(defun mp/hledger-balance-sheet ()
  "Balance sheet (assets and liabilities)."
  (interactive)
  (mp/hledger--run "balance sheet" '("balancesheet")))

(defun mp/hledger-income-statement ()
  "Monthly income statement since the start of last quarter."
  (interactive)
  (mp/hledger--run "income statement" '("incomestatement" "-M" "-b" "lastquarter")))

(defun mp/hledger-expenses ()
  "This month's expenses, largest first."
  (interactive)
  (mp/hledger--run "expenses" '("balance" "expenses" "-p" "thismonth" "-S" "--flat")))

(defun mp/hledger-register ()
  "Transaction register, optionally filtered to one account."
  (interactive)
  (let ((acct (completing-read "Account (empty for all): "
                               (mp/hledger--accounts))))
    (mp/hledger--run (if (string-empty-p acct) "register" (concat "register " acct))
                     (if (string-empty-p acct)
                         '("register")
                       (list "register" acct)))))

(defun mp/hledger-check ()
  "Validate the whole journal with `hledger check --strict'."
  (interactive)
  (let ((res (mp/hledger--output '("check" "--strict"))))
    (if (zerop (car res))
        (message "hledger: journal OK")
      (mp/hledger--display "check" (cdr res) #'mp/hledger-check))))

(defun mp/hledger-stats ()
  "Journal statistics."
  (interactive)
  (mp/hledger--run "stats" '("stats")))

(defun mp/hledger-value ()
  "Show a report valued in a single currency (EUR or IRT).
Rates come from your real conversions (`@@' costs) plus any P directives in
prices.journal, via --infer-market-prices."
  (interactive)
  (let* ((cur (completing-read "Value everything in: " '("EUR" "IRT") nil t))
         (report (completing-read "Report: "
                                  '("balances" "balance sheet" "net worth"
                                    "register" "forecast timeline"
                                    "forecast balances" "at cost (-B)")
                                  nil t nil nil "balances"))
         ;; forecast views need a horizon; ~6 months ahead.
         (in6 (format-time-string "%Y-%m-%d" (time-add nil (days-to-time 184))))
         (val (list "-X" cur "--infer-market-prices"))
         (args (pcase report
                 ("balances"      (append '("balance" "assets" "liabilities") val))
                 ("balance sheet" (append '("balancesheet") val))
                 ("net worth"     (append '("balance" "assets" "liabilities"
                                            "--depth" "1") val))
                 ("register"      (append '("register") val))
                 ;; the pill's timeline, valued into one currency: a running
                 ;; assets projection (-H seeds it with today's real total).
                 ("forecast timeline"
                  (append (list "register" "assets" "--forecast" "-H" "-e" in6) val))
                 ;; projected end-of-month asset balances in one currency.
                 ("forecast balances"
                  (append (list "balance" "assets" "--forecast" "-H" "-M"
                                "-e" in6) val))
                 ("at cost (-B)"  '("balance" "assets" "liabilities" "-B")))))
    (mp/hledger--run (format "%s in %s" report cur) args)))

(defun mp/hledger-open-prices ()
  "Open the current book's prices.journal (manual P exchange-rate directives)."
  (interactive)
  (find-file (expand-file-name "prices.journal" (mp/hledger--entity-dir))))

(defun mp/hledger-forecast ()
  "Pick a forecast view: upcoming transactions or projected reports."
  (interactive)
  (let ((in30 (format-time-string "%Y-%m-%d" (time-add nil (days-to-time 31))))
        (in92 (format-time-string "%Y-%m-%d" (time-add nil (days-to-time 92)))))
    (pcase (completing-read
            "Forecast: "
            '("Upcoming 30 days" "Next 3 months balances" "Projected income statement")
            nil t)
      ("Upcoming 30 days"
       ;; -H seeds the running balance with the current asset total; without the
       ;; tag filter the projection includes already-recorded future-dated real
       ;; txns too, so the balance column reflects where you actually land.
       (mp/hledger--run "forecast: upcoming"
                        (list "register" "assets" "--forecast=today.."
                              "-H" "-e" in30)))
      ("Next 3 months balances"
       ;; -H makes each month column the projected end-of-month balance
       ;; (opening balance carried in) instead of just that month's change.
       (mp/hledger--run "forecast: balances"
                        (list "balance" "--forecast" "-H" "-M" "-e" in92)))
      ("Projected income statement"
       (mp/hledger--run "forecast: income statement"
                        (list "incomestatement" "-M" "--forecast" "-e" in92))))))

(defun mp/hledger--format-wishlist (d)
  "Render the bridge `wishlist' payload D (an alist) as report text."
  (let ((cur (alist-get 'currency d))
        (items (alist-get 'items d)))
    (concat
     (format "Liquid %s   −  buffer %s   =  spendable %s\n\nWishlist (buy order):\n"
             (mp/hledger--fmt-money (alist-get 'liquid d) cur)
             (mp/hledger--fmt-money (alist-get 'buffer d) cur)
             (mp/hledger--fmt-money (alist-get 'spendable d) cur))
     (if items
         (mapconcat
          (lambda (it)
            (let ((aff (alist-get 'affordable it)))
              (format "  %-22s %14s %s   %s"
                      (alist-get 'description it)
                      (mp/hledger--fmt-num (float (alist-get 'amount it)))
                      (alist-get 'currency it)
                      (cond
                       ((eq aff t) (propertize "can afford" 'face 'success))
                       ((eq aff :false)
                        (propertize "would dip into buffer" 'face 'warning))
                       (t "no rate to compare")))))
          items "\n")
       "  (empty)")
     "\n")))

(defun mp/hledger-wishlist ()
  "Show the wishlist with buffer-aware affordability (a wish is affordable only
when liquid assets MINUS the base buffer cover it). Computed by the shared
Python bridge, so Emacs and the pill agree — see `mp/hledger-plan' for the
schedule of WHEN each becomes affordable."
  (interactive)
  (let ((d (mp/hledger--bridge "wishlist")))
    (mp/hledger--display
     (if (string= mp/hledger-entity "personal") "wishlist"
       (format "%s · wishlist" mp/hledger-entity))
     (if d (mp/hledger--format-wishlist d)
       "  (no wishlist data — is the bridge available?)\n")
     #'mp/hledger-wishlist)))

(defun mp/hledger--format-plan (d)
  "Render the bridge `plan' payload D (an alist) as report text."
  (let* ((cur (alist-get 'currency d))
         (goal (alist-get 'goal d))
         (gdate (alist-get 'goal_date d))
         (months (alist-get 'months d))
         (items (alist-get 'items d))
         (unbuyable (seq-filter (lambda (it) (null (alist-get 'month it))) items)))
    (concat
     (format "Plan for %s — buffer %s%s\n\n"
             (if (string= mp/hledger-entity "personal") "personal" mp/hledger-entity)
             (mp/hledger--fmt-money (alist-get 'buffer d) cur)
             (if goal (format ", goal %s by %s"
                              (mp/hledger--fmt-money goal cur) gdate)
               ""))
     (if months
         (mapconcat
          (lambda (m)
            (let ((buys (alist-get 'purchases m)))
              (concat
               (format "%s   save %12s   → have %14s   (cushion %s)"
                       (alist-get 'month m)
                       (mp/hledger--fmt-money (alist-get 'net m) cur)
                       (mp/hledger--fmt-money (alist-get 'projected m) cur)
                       (mp/hledger--fmt-money (alist-get 'cushion m) cur))
               (when buys
                 (propertize (concat "\n              ↳ buy: "
                                     (string-join buys ", "))
                             'face 'success)))))
          months "\n")
       "  (no forecast data)")
     (when unbuyable
       (concat "\n\nNot yet affordable within the horizon:\n"
               (mapconcat
                (lambda (it)
                  (format "  %-22s need %s more"
                          (alist-get 'description it)
                          (mp/hledger--fmt-money (alist-get 'shortfall it) cur)))
                unbuyable "\n")))
     "\n")))

(defun mp/hledger-plan ()
  "Show the current book's savings + wishlist-purchase plan (see the bridge's
`plan'). Targets come from the book's plan.conf — edit them with
`mp/hledger-open-plan-config' (SPC o l P)."
  (interactive)
  (let ((d (mp/hledger--bridge "plan")))
    (mp/hledger--display
     (if (string= mp/hledger-entity "personal") "plan"
       (format "%s · plan" mp/hledger-entity))
     (if d (mp/hledger--format-plan d)
       "  (no plan data — is the bridge available?)\n")
     #'mp/hledger-plan)))

(defun mp/hledger-switch-entity ()
  "Switch the active finance book (personal, company, …)."
  (interactive)
  (let* ((ents (mp/hledger--bridge "entities"))
         (names (or (mapcar (lambda (e) (alist-get 'name e)) ents) '("personal"))))
    (setq mp/hledger-entity
          (completing-read "Book: " names nil t nil nil "personal"))
    (message "Finance book: %s" mp/hledger-entity)))

(defun mp/hledger-new-book (name)
  "Scaffold a new finance book NAME (a subfolder with starter journals) and
switch to it. NAME must be a plain folder name, not \"personal\"."
  (interactive "sNew book name: ")
  (when (member name '("" "personal"))
    (user-error "Pick a name other than \"personal\""))
  (let* ((dir (file-name-as-directory (expand-file-name name mp/hledger-directory)))
         (main (expand-file-name "main.journal" dir)))
    (when (file-exists-p main)
      (user-error "Book %s already exists" name))
    (make-directory dir t)
    (with-temp-file main
      (insert "; " name "/main.journal — entry point for the " name " book.\n\n"
              "commodity 1,000.00 EUR\n"
              "commodity 1,000,000. IRT\n\n"
              "; Declare accounts here for `check --strict' (SPC o l c).\n"
              "account assets:bank\n"
              "account assets:cash\n"
              "account income:other\n"
              "account expenses:misc\n"
              "account liabilities:debts\n"
              "account equity:opening\n\n"
              "include ????-*.journal\n"
              "include forecast.journal\n"
              "include prices.journal\n"))
    (with-temp-file (expand-file-name "forecast.journal" dir)
      (insert "; forecast.journal for the " name " book — periodic rules.\n"))
    (with-temp-file (expand-file-name "wishlist.journal" dir)
      (insert "; wishlist.journal for the " name " book (not included in main).\n"
              "commodity 1,000.00 EUR\n"
              "commodity 1,000,000. IRT\n"))
    (with-temp-file (expand-file-name "prices.journal" dir)
      (insert "; prices.journal for the " name " book — P exchange rates.\n"))
    (with-temp-file (expand-file-name "plan.conf" dir)
      (insert "currency EUR\nbuffer 0\ngoal\ngoal-date\n"))
    (setq mp/hledger-entity name)
    (find-file main)
    (message "Created book %s and switched to it" name)))

;; Doom-era `map! :leader' SPC o l bindings removed: mp-keys.el binds the whole
;; `SPC o l' finance tree (with the "finance" which-key label) to these exact
;; mp/hledger-* commands.
