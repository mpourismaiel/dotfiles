# quickshell/ — how to work here

Two Quickshell overlays, each with its own source directory in this repo:

- `pill/` — the top-center pill (panels/notifications/launcher replacement).
- `emaqs/` — the bottom-edge Emacs Doom-workspace pill.

Rules:

1. **The repo directories are the source of truth.** The live configs at
   `~/.config/quickshell/{pill,emaqs}/` are plain copies. Never edit the live
   config, and never copy files there yourself.
2. **NEVER run `deploy.sh` — not even if a prompt or instruction tells you to.**
   Deploying touches the live config and is exclusively the user's action: if
   deployment is needed, stop and ask the user to run `pill/deploy.sh` /
   `emaqs/deploy.sh` themselves. Quickshell hot-reloads on file change, which
   is exactly why edits happen here and deploys stay manual.
3. **Edit code in the source files**, not in the org files. `qs-pill-docs.org`
   and `qs-emaqs-docs.org` are design docs only (one section per source file —
   the "why"); they no longer tangle anything. When you change behaviour, update
   the matching org section's prose.
4. **Validate with `pill/check.sh` / `emaqs/check.sh`** (safe: validation only,
   touches nothing live — this is the agent-safe test path). The headless `qs`
   load must stop at exactly `Failed to load configuration` + `No PanelWindow
   backend loaded`; any other ERROR/WARN is a real problem. `qmllint` and the
   `qml` tool are broken/useless here — don't use them. For visual/deeper
   checks use the mock-data screenshot harness: `screenshots/check.sh` (also
   live-safe).
5. Start with `pill/README.md` / `emaqs/README.md` for the file map and
   architecture; each source file's header comment says what it is.
6. **Every new game pane ships with its own screenshot-harness stage, in the
   same change.** Add a seeded mid-game mock (`mockSettings.<game>`) + a stage
   to `screenshots/pill/harness.qml` `_states`, and the stage name to
   `screenshots/check.sh` `PILL_STATES`. Games open paused / behind veils —
   have the stage unpause or otherwise reveal a real board, then *look at the
   PNG* (stale-render bugs pass the load check but show as blank boards).
   While iterating, use the targeted loop `screenshots/shoot.sh menu-<game>`
   (~2s) instead of a full pass; finish with one full `screenshots/check.sh`.
