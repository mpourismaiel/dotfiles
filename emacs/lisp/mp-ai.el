;;; mp-ai.el --- Agent shell + ECA inline AI -*- lexical-binding: t; -*-

;;; Agent shell (chat)

(use-package shell-maker
  :defer t)

;; agent-shell needs acp at load time; the old config required both eagerly.
(use-package acp
  :demand t)

(use-package agent-shell
  :demand t
  :after acp)

(use-package agent-shell-notifications
  :ensure (:host github :repo "zackattackz/agent-shell-notifications")
  :after agent-shell
  :demand t)

;; Prompt editing keys. Defaults (from evil-collection-comint, inherited via
;; comint-mode-map) put SUBMIT on RET and prompt HISTORY on plain Up/Down,
;; which fights ordinary multi-line editing. Rebind on agent-shell-mode-map's
;; insert state (more specific than comint-mode-map, so it wins — this is the
;; same mechanism evil-collection-agent-shell uses for n/p):
;;   Enter      -> newline        C-<return> -> submit
;;   Up/Down    -> move cursor    C-Up/C-Down -> prompt history
(with-eval-after-load 'agent-shell
  (evil-define-key 'insert agent-shell-mode-map
    (kbd "<return>")   #'newline
    (kbd "RET")        #'newline
    (kbd "C-<return>") #'agent-shell-submit
    (kbd "<up>")       #'previous-line
    (kbd "<down>")     #'next-line
    (kbd "C-<up>")     #'comint-previous-input
    (kbd "C-<down>")   #'comint-next-input)
  ;; Submit from normal state too.
  (evil-define-key 'normal agent-shell-mode-map
    (kbd "C-<return>") #'agent-shell-submit))

;;; ECA (Editor Code Assistant) — inline completion & rewrite
;; eca-emacs is an editor-agnostic AI client (Emacs talks JSONRPC to an
;; external `eca' server, downloaded automatically on first use).  We use it
;; *only* for its two non-chat features — inline ghost-text completion and
;; region rewrite — since chat already lives in agent-shell.
;;
;; Unlike agent-shell, ECA does *not* speak ACP: the `eca' server connects to
;; Claude directly via Anthropic's API.  Provider, model and prompt choices
;; are server-side in ~/.config/eca/config.json, which points completion at a
;; fast model plus a strict code-only prompt file
;; (~/.config/eca/prompts/completion.md) and rewrite at Sonnet.  Authenticate
;; once per machine with /login → anthropic in an ECA chat; nothing here sets
;; an API key.

(use-package eca
  :ensure (:host github :repo "editor-code-assistant/eca-emacs" :files ("*.el"))
  :defer t
  :commands (eca eca-stop eca-completion-mode eca-rewrite)
  :init
  ;; Auto-enable ghost-text completion in code buffers (like Copilot's
  ;; prog-mode hook did) PLUS markdown and org.  markdown-mode, gfm-mode
  ;; (README.md) and org-mode all derive from `text-mode', not `prog-mode', so
  ;; the prog hook alone skips them — that's why .md/.org saw no suggestions.
  ;; markdown-mode-hook also covers gfm-mode (gfm-mode derives from it).
  ;; Harmless before a session exists: the auto-trigger only fires on
  ;; self-insert and when `(eca-session)' is live.
  (dolist (hook '(prog-mode-hook markdown-mode-hook org-mode-hook))
    (add-hook hook #'eca-completion-mode))
  :config
  (setq eca-completion-idle-delay 0.5        ; calmer than the 0.2 default
        eca-completion-syntax-highlight t
        eca-chat-focus-on-open nil           ; chat lives in agent-shell; don't steal focus
        ;; In-chat action buttons (tool-call accept/reject, questions, …) are
        ;; keyboard-only by default — `eca-buttonize' binds <mouse-1> to them
        ;; ONLY when this is non-nil.  Turn it on so the actions ECA prints with
        ;; their key hints are also clickable (RET / our C-<return> still work).
        eca-buttons-allow-mouse t)

  ;; --- Partial acceptance (upstream only ships whole-suggestion accept) ---
  (defun mp/eca-completion--accept-partial (transform-fn)
    "Accept the leading slice of the current ECA suggestion.
TRANSFORM-FN gets the full suggestion string and returns the leading substring
to insert now; the remainder stays shown as ghost text.  Falls back to a full
accept when that slice is empty or already the whole suggestion."
    (when (eca-completion--overlay-visible)
      (let* ((text    (overlay-get eca-completion--overlay 'completion))
             (id      (overlay-get eca-completion--overlay 'id))
             (partial (funcall transform-fn text)))
        (if (or (null partial)
                (= (length partial) 0)
                (>= (length partial) (length text)))
            (eca-completion-accept)
          (let ((rest (substring text (length partial))))
            (eca-completion--clear-overlay)
            (insert partial)
            (eca-completion--display-overlay-completion rest id (point) (point)))))))

  (defun mp/eca-completion-accept-word (&optional n)
    "Accept the next N words (default 1) of the ECA suggestion, keep the rest."
    (interactive "p")
    (mp/eca-completion--accept-partial
     (lambda (text)
       (let ((pos 0) (count 0) (len (length text)) (n (or n 1)))
         (while (and (< count n) (< pos len)
                     (string-match "[^[:alnum:]_]*[[:alnum:]_]+" text pos))
           (setq pos (match-end 0) count (1+ count)))
         (substring text 0 pos)))))

  (defun mp/eca-completion-accept-line ()
    "Accept up to the end of the next line of the ECA suggestion, keep the rest."
    (interactive)
    (mp/eca-completion--accept-partial
     (lambda (text)
       (let ((nl (string-search "\n" text)))
         (if nl (substring text 0 (1+ nl)) text)))))

  ;; TAB already accepts the whole suggestion (bound by ECA in its overlay
  ;; keymap).  Add word/line partial-accept beside it, once that map exists.
  (with-eval-after-load 'eca-completion
    (define-key eca-completion-map (kbd "C-<tab>")    #'mp/eca-completion-accept-word)
    (define-key eca-completion-map (kbd "C-TAB")      #'mp/eca-completion-accept-word)
    (define-key eca-completion-map (kbd "C-<return>") #'mp/eca-completion-accept-line)))

;; Chat prompt keys (the window `SPC d e' opens).  ECA's defaults put SUBMIT on
;; RET and a literal newline on S-RET, which fights ordinary multi-line editing
;; under evil.  Match the agent-shell setup above: Enter inserts a newline,
;; C-Enter submits.  Use eca-chat--key-pressed-newline (not plain `newline') so
;; it respects the prompt-field boundary and won't edit the read-only
;; transcript; S-Enter is left at its default (also newline).  Bind on
;; eca-chat-mode-map's insert state so it beats the mode map, and allow submit
;; from normal state too.  (A live completion popup still accepts on TAB, and on
;; C-Enter, since eca-chat--key-pressed-return accepts the popup when one is up.)
(with-eval-after-load 'eca-chat
  (evil-define-key 'insert eca-chat-mode-map
    (kbd "<return>")   #'eca-chat--key-pressed-newline
    (kbd "RET")        #'eca-chat--key-pressed-newline
    (kbd "C-<return>") #'eca-chat--key-pressed-return)
  (evil-define-key 'normal eca-chat-mode-map
    (kbd "C-<return>") #'eca-chat--key-pressed-return))

;;; Agent shell extras
;; Per-project Claude config dir, desktop notifications, default model and
;; custom faces layered on top of agent-shell.

(mp/require-package "agent-shell-extras")

(provide 'mp-ai)
;;; mp-ai.el ends here
