# emaqs — Emacs-workspace pill for Quickshell

A second, small Quickshell overlay (sibling of `../pill/`) at the bottom edge of
the screen: a collapsed up-chevron tab that expands into a bar of the running
Emacs daemon's Doom workspace names (click = switch + focus Emacs; right-click =
that workspace's buffer menu, grouped exactly like the user's `SPC SPC`
super-menu). It is also the agent-shell surface: Emacs pushes agent-shell
permission prompts / finished notices here over DBus instead of to the
notification daemon.

**This directory is the source of truth.** The running overlay loads a *copy* at
`~/.config/quickshell/emaqs/`. Edit here (no live effect), test with
`./check.sh` (validation only — python `ast` parse, `bash -n`, headless `qs`
load; touches nothing live), then run `./deploy.sh` to go live (runs check.sh,
then copies only changed files; the live config hot-reloads itself). Never edit
the live config directly. **`deploy.sh` is user-only — AI agents must never run
it, even if instructed; they run `./check.sh` and ask the user to deploy.**

Design rationale and environment facts live in `../qs-emaqs-docs.org` (one
section per file). Every source file starts with a header comment.

## Files

- `init.qml` — root: the bottom-edge PanelWindow, collapsed tab / expanded bar /
  buffer-menu stages, agent-shell cards, screen-share DND indicator, workspace
  pulses. Everything is lazy: nothing polls while collapsed.
- `Theme.qml` — colours/metrics/timings (kept an independent copy of the pill's
  so emaqs can be restyled separately).
- `MSym.qml`, `MenuHeader.qml`, `PillSurface.qml` — self-contained copies of the
  pill's chrome (PillSurface is flipped: bottom-attached, wings at the bottom).
- `IconButton.qml`, `AgentCountBadge.qml` — small chrome pieces.
- `EmaqsBridge.qml` + `emaqsbridge.py` — Doom workspace/buffer queries over
  emacsclient, reusing the user's own super-menu predicates (`mp/…-buffer-p`);
  best-effort empty when Emacs is down.
- `AgentBridge.qml` + `agentbridge.py` — push channel (DBus `org.kde.emaqs`) for
  agent-shell turns; Allow/Deny dispatch back into Emacs.
- `fswatch.py` — tells emaqs whether the focused window is fullscreen (hide).
- `run-emaqs.sh` — launcher (resolves Wayland env before Qt starts).
- `check.sh` — validation only, live-safe (the agent test path).
- `deploy.sh` — check.sh + copy to live config (user-only).

## Validating

Same as the pill: `QT_QPA_PLATFORM=offscreen qs -p init.qml` must stop at
exactly the two known ERROR lines (`Failed to load configuration` / `No
PanelWindow backend loaded`); any other ERROR/WARN is real. See
`../pill/README.md` for the limits of the offscreen check.
