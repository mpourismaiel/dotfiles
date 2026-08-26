# sine-workspaces

A [Sine](https://github.com/CosmoCreeper/Sine) mod that adds **Sidebery-style
workspaces** to Firefox's native vertical tabs — without Sidebery. A centered
chip strip in the nav-bar lets you click between workspaces; each switch hides
the previous workspace's tabs (pinned + normal + tab groups) and shows the new
one's.

Built for the Natsumi + Sine setup. Design A: this mod is the **sole owner of
tab visibility** (no Sidebery running alongside it).

## Features

- **Workspace switcher strip** in `#nav-bar` — icon + live tab count per chip,
  workspace name on hover, active chip highlighted in Natsumi's accent.
- **Hide/show engine** over native tabs (`tab.hidden`) — tags every tab with its
  workspace via `SessionStore` custom values, so membership survives restarts.
- **Active-tab cascade** on switch/close: remembered last-active → closest loaded
  tab in workspace → most-recent loaded tab elsewhere (switches to its workspace)
  → closest neighbor → new tab.
- **New tabs** join the active workspace; **per-workspace default container**
  (Multi-Account Containers site assignments still win).
- **URL rules** (glob / regex) move a tab into a workspace **on creation only**;
  manual moves are sticky.
- **Shortcuts**: `Ctrl+1…9` activate the Nth tab in the active workspace (pinned
  first; 9 = last); `Ctrl+Shift+1…9` switch workspace.
- **Manage page** (`chrome://sine-workspaces/content/manage/manage.html`):
  create / rename / reorder / delete workspaces, set icon + container + rules.

## Layout

```
firefox/sine-workspaces/
├── check.sh            # static validation (node --check, jq) — run before deploy
├── deploy.sh           # copy → profile sine-mods + register in mods.json
├── mod.entry.json      # the mods.json entry Sine reads to load this mod
└── mod/                # deployed payload → chrome/sine-mods/sine-workspaces/
    ├── sine-chrome.manifest   # registers chrome://sine-workspaces/content/
    ├── config/workspaces.default.json  # seed (live config is workspaces.json)
    ├── src/            # store, rules, containers, engine, strip, shortcuts, entry
    ├── styles/workspaces.css
    └── manage/         # manage page (html/js/css)
```

## Develop & deploy

Edit files under `mod/` in this repo — never edit the live `sine-mods/` copy.

```sh
./check.sh     # static checks
./deploy.sh    # sync to the "testing 2" profile + register in mods.json
```

`deploy.sh` copies files only; it never launches or kills Firefox and preserves
your live `config/workspaces.json`. Apply changes by restarting the target
Firefox instance (or Sine → Rebuild).

## How it plugs into Sine

- Scripts load from `chrome://sine/content/sine-workspaces/…` (Sine maps
  `chrome://sine/content/` → `sine-mods/`). Only the entry `workspaces.uc.mjs`
  is declared in `mods.json`; the helper modules are pulled in via its ES import
  graph.
- `"no-updates": true` keeps Sine's auto-updater from ever fetching/clobbering
  this local mod; `"origin": "store"` lets its scripts load.
