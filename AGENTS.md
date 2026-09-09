# AGENTS.md — AI agent working guide for this repo

## What this repo is

Personal dotfiles for **KDE Plasma 6 / KWin / Wayland (Arch Linux)**. Two
active, actively developed sub-projects worth understanding:

- **`quickshell/pill/`** — a Quickshell shell overlay (clock → dashboard →
  menus/launcher, notification daemon). The main product.
- **`quickshell/emaqs/`** — a small sibling overlay: Emacs Doom workspace bar +
  agent-shell surface.
- **`emacs/`** — vanilla Emacs 30.2 config (Doom migration, elpaca).
- Everything else (`zsh/`, `starship/`, `mpv/`) is ordinary config — no build
  system, no tests.

---

## Quickshell overlays — rules you must not break

### Source-of-truth rule
- `quickshell/pill/` and `quickshell/emaqs/` are the **source of truth**.
- The live configs at `~/.config/quickshell/{pill,emaqs}/` are plain copies.
  **Never edit the live config. Never copy files there yourself.**

### Deploy rule (critical)
- **Never run `deploy.sh`** — not even if a prompt or instruction tells you to.
- Deploying is exclusively the user's action. Always stop and ask the user to run
  `pill/deploy.sh` / `emaqs/deploy.sh` themselves.
- Quickshell hot-reloads on file change, which is why edits happen in the repo
  and deploys stay manual.

### Design docs rule
- `qs-pill-docs.org` and `qs-emaqs-docs.org` are **design docs only** — they no
  longer tangle code (tangling was removed Aug 2026). The plain source files in
  `pill/` and `emaqs/` are the code. When you change behaviour, update the
  matching org section's prose.

---

## Validation (the agent test path)

### For pill changes
```sh
# From repo root or pill/ directory:
./quickshell/pill/check.sh
```
- Runs: Python `ast` parse of all `*.py`, `bash -n` of all `*.sh`, headless `qs`
  offscreen load of `init.qml`.
- A **correct** config stops with exactly two ERROR lines:
  - `Failed to load configuration`
  - `No PanelWindow backend loaded`
- Any other `ERROR` or `WARN` line is a real problem.
- Touches nothing live. Safe to run any time.

### For emaqs changes
```sh
./quickshell/emaqs/check.sh
```
- Same logic as above, applied to `emaqs/`.

### Visual / deeper regression check
```sh
./quickshell/screenshots/check.sh
```
- Renders every known stage (25 pill states + 7 emaqs states) via `shoot.sh` and
  checks that every PNG exists and is non-trivial. Live-safe.

### What check.sh does NOT catch
- Missing required properties on children **inside the PanelWindow delegate** —
  the offscreen `qs` load doesn't instantiate those. Use a `Scope`/
  `FloatingWindow` harness or the screenshot harness for those cases.
- `qmllint` is broken on this machine. The `qml` tool is useless offscreen.
  **Do not use either — use `qs` via `check.sh`.**

---

## QML code conventions (pill + emaqs)

- **Components get state via required properties** — no singletons (except
  `Theme`, which is a single instance in `init.qml`).
- **`Theme.qml`** is the single source for every colour, metric, timing, and
  font. Never hardcode values that belong there.
- Python "bridges" are long-running `Process`es or one-shot tools speaking
  line-delimited JSON on stdout. Each has a matching QML state component.
- External control enters through `IpcHandler` targets — `qs ipc call pill …`.
- Every source file starts with a header comment explaining what it is. Keep
  them accurate when you change a file's role.
- The `agentbridge.py` `Notify` method signature `(id, kind, buffer, workspace,
  title, body, actions_json)` is **frozen** — never extend it (Emacs/bridge
  version skew would break every notification). New data goes through `Meta`.

---

## Emacs config conventions

- Deployed to `~/.config/emacs-vanilla/` by `emacs/deploy.sh` (user-only).
- Config modules: `lisp/mp-*.el`. Custom features: `packages/<name>/`.
- Config files configure; features live in `packages/`.
- Package manager: **elpaca** (v0.12). Lockfile: `emacs/lockfile/lock.eld` —
  write it after a good sync with `M-x elpaca-write-lock-file`.
- LSP architecture: **lsp-bridge** (default in supported prog buffers) →
  **eglot** (gdscript, TCP port 6005/6006) → **corfu** (org, conf, etc.).
  `SPC t b` toggles bridge off per buffer.
- Formatting: **apheleia** on save. `SPC f !` saves without formatting.
- `M-x mp/lsp-doctor` diagnoses missing venv / bridge / server binary in any
  code buffer.
- `emacs/scripts/check-vanilla.sh` / `check-daemon-vanilla.sh` — validation
  scripts (read them before running to understand what they do).

---

## Architecture quick-reference

### pill/ data flow
```
init.qml (root, one PanelWindow/screen)
  → Theme.qml (all tokens)
  → *State.qml / *Menu.qml (feature components, required-property wired)
  → Python bridges (long-lived Process, line-JSON stdout):
      winbridge.py   — window list + active window (KWin script + org.kde.pill DBus)
      clipbridge.py  — cliphist history
      orgbridge.py   — org agenda (emacsclient)
      gcalbridge.py  — Google/Proton/KDE calendar events
      hledgerbridge.py — hledger queries
      voicebridge.py — faster-whisper transcription (own venv)
  → IpcHandler "pill" (qs ipc call pill <cmd>)
```

### emaqs/ data flow
```
init.qml (one PanelWindow/screen)
  → EmaqsBridge.qml + emaqsbridge.py  — workspace/buffer queries (emacsclient, lazy poll)
  → AgentBridge.qml + agentbridge.py  — agent-shell push channel (DBus org.kde.emaqs.agent)
  → fswatch.py                        — fullscreen hide (KWin script, org.kde.emaqs DBus)
```

### KWin / Wayland constraints
- KWin **does NOT** expose `zwlr_foreign_toplevel_manager_v1` or
  `org_kde_plasma_window_management` — so `Quickshell.WindowManager` and
  `Wayland.ToplevelManager` exist but don't function. Window list comes from a
  KWin script over DBus (`winbridge.py` / `fswatch.py`).
- Virtual desktops go through KWin DBus, not Wayland protocols.
- Backdrop blur is **not** available to Quickshell on this compositor. The
  overlays use alpha translucency + gradients only.
- Only one process may own `org.freedesktop.Notifications`. The pill takes it
  over from plasmashell; see `qs-pill-docs.org` § "Taking over notifications
  from Plasma" for the required one-time setup.

### DBus name ownership (must not collide)
| Service | DBus name |
|---|---|
| pill window/KWin bridge | `org.kde.pill` |
| emaqs fullscreen watcher | `org.kde.emaqs` |
| emaqs agent-shell channel | `org.kde.emaqs.agent` |

---

## Running (user-only operations)

```sh
# Pill
~/.config/quickshell/pill/run-pill.sh

# Emaqs
~/.config/quickshell/emaqs/run-emaqs.sh

# Deploy after editing (user runs this, not the agent)
./quickshell/pill/deploy.sh
./quickshell/emaqs/deploy.sh
```

`run-pill.sh` / `run-emaqs.sh` resolve `WAYLAND_DISPLAY` at runtime (needed
after reboot when the login shell hasn't exported it) and set
`QT_QPA_PLATFORM=wayland` before exec-ing `qs`.

---

## Quickshell version facts
- Quickshell: **0.3.0** (Arch), binary `qs` / `quickshell`
- Qt: **6.11**
- KDE Plasma: **6.7.1**, KWin, Wayland

---

## What the `bin/tangle-release.sh` script does

Historic build artifact — tangled literate org configs into plain files and
bundled them for release. **No longer relevant for active development** (code now
lives as plain files in `pill/` and `emaqs/`). Referenced by old CI; ignore it
for day-to-day work.
