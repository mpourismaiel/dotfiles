# VERIFY.md — live-verification backlog

Agents can validate headlessly (`check.sh`, screenshot harness, offline test
suites) but **cannot touch live processes** — the pill/emaqs live config, live
Firefox, or live Emacs. So almost every shipped feature lands as
"headless PASS, live UNVERIFIED" and that debt is invisible unless it lives
somewhere you can see it. This is that place.

**How to use:** when a feature ships and passes headless checks, an agent
appends a row with the exact manual step to confirm it live. You tick `[x]`
once you've used it for real. Keep this pruned — delete confirmed rows that no
longer teach anything.

Legend: `[ ]` awaiting live check · `[x]` confirmed live · `[~]` partially confirmed

---

## quickshell/pill

- [ ] **Tetris** (menu 9) — play a game, confirm 7-bag/rotation/wall-kick/line-clear + high score persists to `settings.tetris`.
- [ ] **Block Blast** (menu 10) — drag-drop with snap shadow, row+col clears, combo scoring; header-grip park drag.
- [ ] **Brick Breaker** (menu 12) — aim, launch balls one-by-one, specials fire, `settings.brickBreaker.best` persists.
- [ ] **Snake** (menu 14) — arrows/hjkl + P pause, digest-lump growth animation, best score persists.
- [ ] **Minesweeper** (menu 17) — Games list → open. Left-click reveals (first click always safe → opens an area), right-click flags, zero-cells flood-fill, adjacency numbers correct. Win = all safe cells cleared → "CLEARED" + time; mine → "BOOM" reveals field. Difficulty B/I/E resizes grid inside the same well; best time persists per difficulty across shell restart; click veil starts a new game.
- [ ] **Chicken Invaders** (menu 18) — Games list → open (list is now six cards in a taller pane — check no clipping). Big 495×490 starfield well with drifting parallax stars; eggs pop in and tumble, drop speed steps up every 3rd wave. ←→/H·L fly, egg hits cost hull with a blink-mercy window, a chicken past the red hull line costs hull. Run starts with an "ARM YOUR SHIP" draft — pick bullet / laser / vapor (locked for the run; try each: bullet = streams, laser = instant beam every 2s, vapor = rotating dps orbs; every hit pops a floating damage number, vapor's aggregated ~2×/s). Drafts return after even waves (2, 4 …) offering only your path + ship tracks (plating/thrusters/evasion), 15 picks max (sidebar shows loadout + PICKS n/15); arrows move the highlight (hover follows), Enter/Space picks, 1/2/3 jump-picks. Odd waves / dry pool → ~1.5s "next wave incoming" interlude. Die → "COOP COOKED", Enter re-arms a fresh run; `settings.invaders.best` survives shell restart and shows in the Games list.
- [ ] **Emoji picker** (menu 16) — search/category tabs/grid kbnav, Enter copies via wl-copy, right-click favorites.
- [ ] **Calculator breakdown** (Launcher) — per-term breakdown card, result chaining (click substitutes), Up restores formula, hover tooltip.
- [ ] **Appearance theming** (Settings → Appearance) — color pickers write to live `theme.json`, 5 presets, no white-wipe on load.
- [ ] **Clock & Agenda designs** (Settings → Appearance) — 7 collapsed styles (1a–1g), font-availability gating greys out unavailable ones.
- [ ] **Done work-history** (menu 15) — git CODE + AGENDA chapters render from real data bridges.
- [ ] **gcal events** — Google Calendar events via signond D-Bus SSO token; agent sandbox can't fetch the token, so this whole path is unverified.
- [ ] **Deadlines under-line** — resting-clock "⚑ N LATE · M TODAY" + OrgDeadlinesMenu popup against real Emacs org data.
- [ ] **Finance menu** (menu 8) — hledgerbridge against real journals; critical notifications never auto-expire.
- [ ] **Notification droplet** — NotificationDroplet water-drop detach + deck float against real notifications.
- [ ] **Capture** — screenshot captures the pill in current state then collapses to annotation mode; line/freehand/undo/redo; screen-record.
- [ ] **Record selected area** (2026-09-03 fix) — in Record, pick "Select area", draw a region, hit Record. Previously the button dropped straight back to idle (gpsr got a geometry on `-w` and exited non-zero). Now it should start recording; stop via the capture button and confirm the saved mp4 is cropped to the drawn region. Whole-screen record should still work unchanged.
- [ ] **Capture multi-monitor crop** (2026-09-01 fix) — with the external monitor connected, take a screenshot from EACH monitor (hover the cursor there, fire the shortcut) and confirm the crop matches the drawn region every time — especially after disconnecting + reconnecting the external monitor (the old race put the crop in a totally different area). The overlay should now appear only on the grabbed monitor. Retest a few times per monitor since the bug was intermittent.
- [ ] **DEMO mode** — `DEMO=true` fake-data across all 5 bridges for screen recording; taskbar/notifs/launcher stay real.
- [ ] **Focus model** — close-on-blur + restore-focus via KWin activate; verify the pill doesn't self-clobber lastActiveWindow.
- [ ] **Transcribe** — voice-to-text (faster-whisper + Claude polish); needs setup-transcribe.sh; SIGTERM-finalize + rnnoise untested.

## quickshell/emaqs

- [ ] **Permission card upgrade** — op-type labels, Model + Session-mode dropdowns, elapsed time; needs live Emacs reload (currently vanilla).

## emacs (vanilla)

- [ ] **Doom→vanilla migration** — full config launch never confirmed live; checklist in `__ignore__`.
- [ ] **ECA completion** — inline completion + rewrite via Anthropic API; live-unverified (user tangles/syncs/runs).
- [ ] **hledger rolling balance** — svg-header type:AL balances + `SPC o l a` completion annotations; live GUI render unverified.
- [ ] **Workspace HUD** (`SPC t W`) — click/scroll/agent-launch/dape controls unverified (compile + mocked render only).
- [ ] **Godot in Emacs** — eglot LSP 6005 + dape 6006 (need Godot editor open) + "Open in External Editor" routing; live-unverified.
- [ ] **Keyboard macros** (`emacs/packages/macros/`) — in a normal editing buffer, `q` starts recording (echo "Recording macro…"), `q` again stops + stores it ("Macro stored: …"). Confirm mode-specific `q`=quit (dired/magit/help) still quits, not records. `SPC m k k` lists macros — session macros first (blank group, shown as their key actions), then a **Saved** group by name; pick one, answer "Times:" (default 1), it runs N times. Record → `SPC m k a` → name it → restart Emacs → `SPC m k k` shows it under **Saved** (persisted to `var/macros.el`). `SPC m k d` → pick → `yes-or-no-p` deletes (saved deletions re-persist). svg-header resting line shows a `▸ <keys>` chip left of the icon buttons for the most-recent session macro; clicking it runs that macro once. Headless: byte-compile clean, logic + persist roundtrip + svg render (chip box + click cmd) all PASS.
- [ ] **Edit bundles** (`SPC p p` → pinned `✎ Edit bundles…`, always last, never reorders) — menu is `＋ Add bundle` / `🗑 Remove bundle` / `✎ Edit <name>` per bundle. **Add**: name → toggle-picker (selected float above the `available` separator; RET on an available selects it, RET on a selected removes it; `＋ Other directory…` adds an arbitrary dir; `✓ Done` finishes). **Remove**: pick bundle → echo-line `yes-or-no-p`. **Edit**: rename prompt (blank/unchanged keeps name) → same toggle-picker seeded with current projects. Persists to `var/project-bundles.eld`, survives restart (eld wins over the `private.el` seed); workspace name = dir basename. Confirm elvou/apex still list + open. Parse + toggle/create/edit/remove/round-trip logic pass headlessly.

## Teamwork (emacs/packages/teamwork)

- [ ] **Write paths** — 164 offline tests pass; live-unverified: write/uncomplete, completed-task fetch, task move, TODO-keyword done-state, inline labels, inline comments, lazy comment load (`C-c C-o`).
- [ ] **View filters** (`C-c C-v t`/`n`/`r`) — in a management (or timesheet) buffer: `C-c C-v t bounty` hides all but bounty-tagged task subtrees (matching task + its subtasks + list/project scaffolding stay). Stack `C-c C-v t mux` → only tasks with BOTH tags. `C-c C-v n <text>` filters on a title substring, stackable with tags. `C-c C-v r` reveals everything. Make local edits first (add a tag, rename a task, add a new task, delete one) then filter + reset → confirm every edit survived (overlays only, no text change). Headless algorithm test passes (`/tmp/tw-view-test.el`, all assertions).

## firefox/sine-workspaces

- [~] **Sidebery-style workspaces** — reproduced external-link + Ctrl+Shift+N fixes via isolated Xvfb harness; full live behavior on profile "testing 2" still broadly unverified.

## shledger

- [ ] **Web app** — all milestones done, mockhost-tested only; never run against a real multi-user deployment.
