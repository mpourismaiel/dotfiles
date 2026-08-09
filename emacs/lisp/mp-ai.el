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
  ;; Auto-enable ghost-text completion in every code buffer, like Copilot's
  ;; prog-mode hook did.  Harmless before a session exists: the auto-trigger
  ;; only fires on self-insert and when `(eca-session)' is live.
  (add-hook 'prog-mode-hook #'eca-completion-mode)
  :config
  (setq eca-completion-idle-delay 0.5        ; calmer than the 0.2 default
        eca-completion-syntax-highlight t
        eca-chat-focus-on-open nil)          ; chat lives in agent-shell; don't steal focus

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

;;; Agent shell extras
;; Per-project Claude config dir, desktop notifications, default model and
;; custom faces layered on top of agent-shell.

(mp/require-package "agent-shell-extras")

(provide 'mp-ai)
;;; mp-ai.el ends here
