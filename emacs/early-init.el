;;; early-init.el --- Pre-init setup -*- lexical-binding: t; -*-

;; This config is managed in the `awesome' repo under emacs/ and deployed to
;; ~/.config/emacs-vanilla/ via deploy.sh. Do not edit the deployed copy.

;; Elpaca manages packages; keep package.el fully out of the way.
(setq package-enable-at-startup nil)

;; Defer GC during startup; gcmh (loaded in mp-core) takes over afterwards.
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6)

;; Quiet native compilation; keep the eln cache inside this config's var dir.
(setq native-comp-async-report-warnings-errors 'silent)
(when (fboundp 'startup-redirect-eln-cache)
  (startup-redirect-eln-cache
   (expand-file-name "var/eln-cache/" user-emacs-directory)))

;; Frame chrome off before the first frame is drawn (avoids flicker).
(push '(menu-bar-lines . 0) default-frame-alist)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars) default-frame-alist)
(setq frame-inhibit-implied-resize t
      frame-resize-pixelwise t)

;; No startup screen / echo-area noise.
(setq inhibit-startup-screen t
      inhibit-startup-echo-area-message user-login-name
      initial-scratch-message nil)

;; Slightly faster startup: don't search for special file handlers while
;; loading pre-compiled init files.
(defvar mp/file-name-handler-alist file-name-handler-alist)
(setq file-name-handler-alist nil)
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq file-name-handler-alist mp/file-name-handler-alist)))

;;; early-init.el ends here
