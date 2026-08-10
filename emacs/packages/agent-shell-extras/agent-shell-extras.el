;;; agent-shell-extras.el --- agent-shell integrations: per-project dir, notifications, model, faces  -*- lexical-binding: t; -*-
;;; Commentary:
;; Local integrations layered on top of `agent-shell': a per-project Claude
;; config dir, desktop notifications, default model and custom faces.
;; Ported from the Doom package of the same name.
;;; Code:

(defvar mp/agent-shell-claude-config-dirs nil
  "Alist of (PROJECT-ROOT . CLAUDE-CONFIG-DIR) overrides.
When an agent-shell Claude client starts with a cwd under PROJECT-ROOT,
CLAUDE_CONFIG_DIR is set to CLAUDE-CONFIG-DIR so Claude uses that home
instead of the default ~/.claude/.  Longest match wins.
Populated from `private.el' (see the Project management section).")

(defun mp/agent-shell--claude-config-dir (dir)
  "Return the CLAUDE_CONFIG_DIR override for DIR, or nil.
Picks the entry in `mp/agent-shell-claude-config-dirs' whose PROJECT-ROOT
is the longest prefix of DIR."
  (let ((dir (expand-file-name (file-name-as-directory dir)))
        (best nil) (best-len -1))
    (dolist (entry mp/agent-shell-claude-config-dirs best)
      (let* ((root (expand-file-name (file-name-as-directory (car entry))))
             (len (length root)))
        (when (and (string-prefix-p root dir) (> len best-len))
          (setq best (expand-file-name (cdr entry)) best-len len))))))

(defun mp/agent-shell--claude-config-env (orig-fn &rest args)
  "Prepend a per-project CLAUDE_CONFIG_DIR when starting a Claude client.
ORIG-FN is `agent-shell-anthropic-make-claude-client', which runs in the
shell buffer whose `default-directory' is the resolved project cwd."
  (let* ((config-dir (mp/agent-shell--claude-config-dir default-directory))
         (agent-shell-anthropic-claude-environment
          (if config-dir
              (cons (format "CLAUDE_CONFIG_DIR=%s" config-dir)
                    agent-shell-anthropic-claude-environment)
            agent-shell-anthropic-claude-environment)))
    (apply orig-fn args)))

(advice-add 'agent-shell-anthropic-make-claude-client :around
            #'mp/agent-shell--claude-config-env)

;; `agent-shell-notifications' ships with `agent-shell' (declared elsewhere in
;; the config), so :ensure nil keeps elpaca from trying to install it.
(use-package agent-shell-notifications
  :ensure nil
  :hook (agent-shell-mode . agent-shell-notifications-mode)
  :config
  (require 'dbus nil t)
  (require 'json)

  ;; ---- emaqs transport (DBus) ----------------------------------------------
  (defconst mp/agent-shell--emaqs-service "org.kde.emaqs.agent")
  (defconst mp/agent-shell--emaqs-path "/Agent")
  (defconst mp/agent-shell--emaqs-iface "org.kde.emaqs.agent")

  (defun mp/agent-shell--emaqs-call (method &rest args)
    "Fire METHOD on the emaqs agent bridge with string ARGS (async, best-effort)."
    (when (fboundp 'dbus-call-method-asynchronously)
      (with-demoted-errors "emaqs agent bridge: %s"
        (apply #'dbus-call-method-asynchronously
               :session mp/agent-shell--emaqs-service mp/agent-shell--emaqs-path
               mp/agent-shell--emaqs-iface method nil args))))

  ;; ---- permission capture: stash respond fn/options by request-id -----------
  (defvar mp/agent-shell--permission-registry (make-hash-table :test 'equal)
    "Map a permission request-id to a plist of (:respond FN :options OPTS).")
  (defvar mp/agent-shell--emaqs-onaction (make-hash-table :test 'equal)
    "Map an emaqs notification id to its :on-action closure.")
  (defvar mp/agent-shell--prev-permission-responder nil
    "Responder in effect before we installed our capturing one.")

  (defun mp/agent-shell--capture-permission (permission)
    "Record PERMISSION's respond fn/options for the notification, then delegate.
Always records; returns whatever a previously configured responder returns so
an existing auto-approve responder keeps working (nil means show the dialog)."
    (when-let* ((request-id (map-nested-elt permission '(:tool-call :permission-request-id))))
      (puthash request-id
               (list :respond (map-elt permission :respond)
                     :options (map-elt permission :options))
               mp/agent-shell--permission-registry))
    (when (functionp mp/agent-shell--prev-permission-responder)
      (funcall mp/agent-shell--prev-permission-responder permission)))

  (unless (eq agent-shell-permission-responder-function
              #'mp/agent-shell--capture-permission)
    (setq mp/agent-shell--prev-permission-responder
          agent-shell-permission-responder-function
          agent-shell-permission-responder-function
          #'mp/agent-shell--capture-permission))

  (defun mp/agent-shell--forget-permission (&rest args)
    "Drop the registry entry once a request is answered (:before advice)."
    (when-let* ((request-id (plist-get args :request-id)))
      (remhash request-id mp/agent-shell--permission-registry)))
  (advice-add 'agent-shell--send-permission-response :before
              #'mp/agent-shell--forget-permission)

  (defun mp/agent-shell--option-id (options &rest kinds)
    "Return the :option-id of the first OPTION in OPTIONS matching a kind in KINDS."
    (seq-some (lambda (kind)
                (when-let* ((opt (seq-find (lambda (o) (equal (map-elt o :kind) kind))
                                           options)))
                  (map-elt opt :option-id)))
              kinds))

  ;; ---- which workspace owns a shell buffer (for the per-workspace pulse) ----
  ;; Doom's +workspace-* API replaced with perspective.el: (persp-names) for the
  ;; name list, (perspectives-hash) + persp-buffers for each perspective's
  ;; buffers, and mp/workspace-current-name for the current one.
  (defun mp/agent-shell--buffer-workspace (buf)
    "Return the perspective name that owns BUF, else the current workspace."
    (or (and (fboundp 'persp-names) (fboundp 'perspectives-hash)
             (seq-find
              (lambda (name)
                (when-let* ((p (ignore-errors (gethash name (perspectives-hash)))))
                  (and (fboundp 'persp-buffers) (memq buf (persp-buffers p)))))
              (persp-names)))
        (and (fboundp 'mp/workspace-current-name) (mp/workspace-current-name))
        ""))

  ;; ---- build the emaqs payload (title/body/actions) for both event types -----
  (defun mp/agent-shell--enrich-plist (orig-fn type shell-buffer event)
    "Attach emaqs metadata (id/kind/buffer/workspace/actions) to the plist.
For permission-request, wire Allow/Deny to the captured respond closure."
    (let* ((plist (funcall orig-fn type shell-buffer event))
           (bufname (buffer-name shell-buffer))
           (ws (mp/agent-shell--buffer-workspace shell-buffer)))
      (plist-put plist :emaqs-buffer bufname)
      (plist-put plist :emaqs-workspace ws)
      (pcase type
        ('permission-request
         (let* ((request-id (map-nested-elt event '(:data :request-id)))
                (entry (and request-id (gethash request-id mp/agent-shell--permission-registry)))
                (respond (plist-get entry :respond))
                (options (plist-get entry :options))
                (allow-id (and options (mp/agent-shell--option-id options "allow_once" "allow_always")))
                (deny-id (and options (mp/agent-shell--option-id options "reject_once" "reject_always")))
                (switch (plist-get plist :on-action))
                (msg (ignore-errors
                       (agent-shell-notifications--format-permission-message
                        (map-nested-elt event '(:data :tool-call))))))
           (plist-put plist :title bufname)
           (plist-put plist :body (or msg ""))
           (plist-put plist :emaqs-id (format "perm:%s" (or request-id "")))
           (plist-put plist :emaqs-kind "permission")
           (if (and respond allow-id deny-id)
               (progn
                 (plist-put plist :emaqs-actions
                            (list (list "allow" "Allow") (list "reject" "Deny")))
                 (plist-put plist :on-action
                            (lambda (id key)
                              (with-demoted-errors "agent-shell allow/deny: %s"
                                (pcase key
                                  ("allow" (funcall respond allow-id))
                                  ("reject" (funcall respond deny-id))
                                  (_ (when (functionp switch) (funcall switch id key))))))))
             (plist-put plist :emaqs-actions '()))
           plist))
        ('turn-complete
         (plist-put plist :title bufname)
         (plist-put plist :body "Agent finished!")
         (plist-put plist :emaqs-id (format "fin:%s" bufname))
         (plist-put plist :emaqs-kind "finished")
         (plist-put plist :emaqs-actions '())
         plist)
        (_ plist))))
  (advice-add 'agent-shell-notifications--make-notification-plist :around
              #'mp/agent-shell--enrich-plist)

  ;; ---- send/close: push to emaqs instead of freedesktop ----------------------
  (defun mp/agent-shell--emaqs-send (plist)
    "Send PLIST to emaqs, stash its :on-action by id, and return the id."
    (let ((id (or (plist-get plist :emaqs-id) "")))
      (when-let* ((fn (plist-get plist :on-action)))
        (puthash id fn mp/agent-shell--emaqs-onaction))
      (mp/agent-shell--emaqs-call
       "Notify" id
       (or (plist-get plist :emaqs-kind) "permission")
       (or (plist-get plist :emaqs-buffer) "")
       (or (plist-get plist :emaqs-workspace) "")
       (or (plist-get plist :title) "")
       (or (plist-get plist :body) "")
       (json-encode (vconcat (mapcar #'vconcat (or (plist-get plist :emaqs-actions) '())))))
      id))

  (defun mp/agent-shell--emaqs-close (id)
    "Tell emaqs to drop notification ID and forget its closure."
    (remhash id mp/agent-shell--emaqs-onaction)
    (mp/agent-shell--emaqs-call "Close" (or id "")))

  (setq agent-shell-notifications-send-function #'mp/agent-shell--emaqs-send
        agent-shell-notifications-close-function #'mp/agent-shell--emaqs-close)

  ;; ---- dismiss the emaqs "finished" card when its shell buffer is focused -----
  ;; `agent-shell-notifications' only closes notifications on window *selection*
  ;; change (`--on-window-activity'), which misses a same-window
  ;; `switch-to-buffer' — the window stays selected, only its buffer changes, so
  ;; focusing the shell that way would leave the finished card stuck on the emaqs
  ;; pill.  Close the "finished" card (id "fin:BUFFER") whenever an agent-shell
  ;; buffer becomes the selected window's buffer.
  (defun mp/agent-shell--emaqs-dismiss-on-focus (&rest _)
    "Close the emaqs finished card for the now-focused agent-shell buffer."
    (let ((buf (window-buffer (selected-window))))
      (when (and (buffer-live-p buf)
                 (with-current-buffer buf (derived-mode-p 'agent-shell-mode)))
        (mp/agent-shell--emaqs-close (format "fin:%s" (buffer-name buf))))))
  (add-hook 'window-buffer-change-functions #'mp/agent-shell--emaqs-dismiss-on-focus)

  ;; ---- dispatch an emaqs button/click back into Emacs ------------------------
  (defun mp/agent-shell-emaqs-action (id key)
    "Run the stashed :on-action for emaqs notification ID with KEY.
KEY is \"allow\", \"reject\" or \"default\" (a body click = switch to shell)."
    (when-let* ((fn (gethash id mp/agent-shell--emaqs-onaction)))
      (with-demoted-errors "agent-shell emaqs action: %s"
        (funcall fn id key))
      (remhash id mp/agent-shell--emaqs-onaction))
    nil)

  ;; ---- working state: three-dots chevron & per-workspace pulse ---------------
  (defun mp/agent-shell--emaqs-working (buf active)
    "Tell emaqs whether BUF's agent is ACTIVE (working)."
    (when (buffer-live-p buf)
      (mp/agent-shell--emaqs-call
       "Working" (buffer-name buf) (mp/agent-shell--buffer-workspace buf)
       (if active "1" "0"))))

  (defun mp/agent-shell--emaqs-working-start (&rest args)
    "Mark the shell working when a command is sent (:before advice)."
    (when-let* ((buf (plist-get args :shell-buffer)))
      (mp/agent-shell--emaqs-working buf t)))
  (advice-add 'agent-shell--send-command :before
              #'mp/agent-shell--emaqs-working-start)

  (defun mp/agent-shell--emaqs-working-stop (&rest _)
    "Clear the shell working state when its turn completes (:after advice)."
    (mp/agent-shell--emaqs-working (current-buffer) nil))
  (advice-add 'agent-shell-notifications--on-turn-complete :after
              #'mp/agent-shell--emaqs-working-stop))

(setq agent-shell-anthropic-default-model-id "default")

;; Doom's `custom-set-faces!' replaced with vanilla `custom-set-faces'
;; (same specs, wrapped in the ((t (...))) display form).
(let* ((bg-alt    "#171a24")   ; panels, org blocks — code surface
       (bg-dark   "#0a0c11")   ; deep shadow — language-label band
       (bg-light  "#212737")   ; lighter surface — keycaps
       (border    "#2a3142")   ; borders, boxes
       (user-bg   "#151d2b")   ; cool band behind a submitted user turn
       (fg        "#c5cdde")   ; primary text
       (fg-alt    "#9aa3ba")   ; secondary text
       (fg-dim    "#6b7488")   ; faint text, ids, borders
       (comment   "#69718a")   ; muted supporting text
       (red       "#ff6e7e")
       (orange    "#f78c6c")
       (yellow    "#ffcb6b")
       (green     "#c3e88d")
       (cyan      "#89ddff")
       (blue      "#82aaff")
       (purple    "#c792ea")
       (teal      "#56d6d6"))
  (custom-set-faces
   ;; -- mode-line & header ---------------------------------------------------
   `(agent-shell-model               ((t (:foreground ,teal   :weight bold))))
   `(agent-shell-thought-level       ((t (:foreground ,purple))))
   `(agent-shell-container-indicator ((t (:foreground ,orange))))
   `(agent-shell-buffer-name         ((t (:foreground ,fg     :weight bold))))

   ;; -- session metadata -----------------------------------------------------
   `(agent-shell-session-id          ((t (:foreground ,fg-dim))))
   `(agent-shell-session-mode        ((t (:foreground ,yellow))))
   `(agent-shell-session-title       ((t (:foreground ,cyan   :weight bold))))
   `(agent-shell-session-directory   ((t (:foreground ,green))))
   `(agent-shell-session-date        ((t (:foreground ,comment))))

   ;; -- collapsible sections (magit-like) ------------------------------------
   `(agent-shell-section-heading     ((t (:foreground ,blue   :weight bold))))
   `(agent-shell-section-annotation  ((t (:foreground ,fg-alt :slant italic))))
   `(agent-shell-secondary           ((t (:foreground ,comment))))

   ;; -- semantic status ------------------------------------------------------
   `(agent-shell-success             ((t (:foreground ,green  :weight bold))))
   `(agent-shell-warning             ((t (:foreground ,yellow :weight bold))))
   `(agent-shell-error               ((t (:foreground ,red    :weight bold))))
   `(agent-shell-pending             ((t (:foreground ,fg-dim :slant italic))))

   ;; -- "Available ..." listings ---------------------------------------------
   `(agent-shell-list-name           ((t (:foreground ,cyan))))
   `(agent-shell-list-value          ((t (:foreground ,orange))))

   ;; -- prompt & input (user turn) -------------------------------------------
   `(agent-shell-prompt              ((t (:foreground ,teal :weight bold))))
   `(agent-shell-input               ((t (:foreground ,fg :background ,user-bg :extend t))))
   `(agent-shell-key-binding         ((t (:foreground ,cyan :background ,bg-light
                                          :box (:line-width (1 . -1) :color ,border)))))
   `(agent-shell-link                ((t (:foreground ,cyan :underline t))))
   `(agent-shell-permission-title    ((t (:foreground ,yellow :weight bold))))

   ;; -- viewport -------------------------------------------------------------
   `(agent-shell-viewport-prompt        ((t (:foreground ,fg-alt :slant italic))))
   `(agent-shell-viewport-status-edit   ((t (:foreground ,green  :weight bold))))
   `(agent-shell-viewport-status-busy   ((t (:foreground ,yellow :weight bold))))
   `(agent-shell-viewport-status-view   ((t (:foreground ,fg-alt))))

   ;; -- markdown: inline emphasis --------------------------------------------
   `(agent-shell-markdown-bold          ((t (:foreground ,fg :weight bold))))
   `(agent-shell-markdown-italic        ((t (:foreground ,fg :slant italic))))
   `(agent-shell-markdown-strikethrough ((t (:foreground ,fg-dim :strike-through t))))
   `(agent-shell-markdown-inline-code   ((t (:foreground ,cyan :background ,bg-alt))))
   `(agent-shell-markdown-link          ((t (:foreground ,cyan :underline t))))
   `(agent-shell-markdown-blockquote    ((t (:foreground ,fg-alt :slant italic))))

   ;; -- markdown: headers (colored, only mild scaling to stay chat-compact) --
   `(agent-shell-markdown-header-1      ((t (:foreground ,blue   :weight bold :height 1.1))))
   `(agent-shell-markdown-header-2      ((t (:foreground ,purple :weight bold :height 1.05))))
   `(agent-shell-markdown-header-3      ((t (:foreground ,cyan   :weight bold))))
   `(agent-shell-markdown-header-4      ((t (:foreground ,green  :weight bold))))
   `(agent-shell-markdown-header-5      ((t (:foreground ,yellow :weight bold))))
   `(agent-shell-markdown-header-6      ((t (:foreground ,orange :weight bold))))

   ;; -- markdown: tables -----------------------------------------------------
   `(agent-shell-markdown-table-header  ((t (:foreground ,cyan :weight bold :background ,bg-alt))))
   `(agent-shell-markdown-table-border  ((t (:foreground ,fg-dim))))
   `(agent-shell-markdown-table-zebra   ((t (:background ,bg-alt))))

   ;; -- markdown: fenced code blocks -----------------------------------------
   ;; :foreground unspecified lets the language's font-lock colors show through.
   `(agent-shell-markdown-source-block  ((t (:background ,bg-alt :extend t))))
   `(agent-shell-markdown-source-block-language
     ((t (:foreground ,cyan :background ,bg-dark :slant italic :weight bold :extend t))))))

(provide 'agent-shell-extras)
;;; agent-shell-extras.el ends here
