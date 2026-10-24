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
- **URL rules** (glob / regex) route a new tab to a workspace **and a
  container** (per rule: a container, "No container", or the workspace's
  default) — **on creation only**; manual moves are sticky.
- **External links** (Slack, Telegram, …) open in the first matching rule's
  workspace + container, else the active workspace + its default container —
  and take you there. The container is enforced (Firefox would otherwise reuse
  the container of a tab already open on that host).
- **Folders are workspace-bound**: a tab in a tab group always carries the
  group's workspace.
- **Script API + `ffws` CLI** — list / open / move / group / close tabs from a
  script or an agent, with dry runs, never stealing focus unless asked.
- **Shortcuts**: `Ctrl+1…9` activate the Nth tab in the active workspace (pinned
  first; 9 = last); `Ctrl+Shift+1…9` switch workspace.
- **Manage page** (`chrome://sine-workspaces/content/manage/manage.html`):
  create / rename / reorder / delete workspaces, set icon + container + rules.

## Layout

```
firefox/sine-workspaces/
├── check.sh            # static validation (node --check, jq) — run before deploy
├── deploy.sh           # copy → profile sine-mods + register in mods.json
├── bin/ffws            # script-API CLI (see "Script API")
├── mod.entry.json      # the mods.json entry Sine reads to load this mod
└── mod/                # deployed payload → chrome/sine-mods/sine-workspaces/
    ├── sine-chrome.manifest   # registers chrome://sine-workspaces/content/
    ├── config/workspaces.default.json  # seed (live config is workspaces.json)
    ├── src/            # store, rules, containers, engine, strip, shortcuts, api, entry
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

## Script API (`bin/ffws`)

The mod watches a file mailbox in the profile
(`<profile>/sine-workspaces-ipc/`, no network socket). `bin/ffws` (Python,
stdlib only) talks to it and finds the running profile on its own
(`--profile DIR` / `$FFWS_PROFILE` to override).

```sh
ffws state --tree                 # workspaces → folders → tabs (ids, urls, containers)
ffws state                        # same as JSON — what an agent reads
ffws apply plan.json --dry-run    # validate + describe, change nothing
ffws apply plan.json              # run it (in the background)
ffws open URL… -w Work -c Personal --new-folder "Reading list" --color green
ffws ops                          # the op reference below
```

A plan is `{"ops": [...]}`, run in order. **Every op is validated first; if
any is invalid nothing changes.** Tab ids come from `state` and are valid for
the current browser session; a tab ref may be `{"id", "url"}` to fail on a
stale plan. Workspaces and containers take an id or a name; folders take a
group id, a unique label, or `"$name"` for one created earlier in the plan.

| op | fields | does |
|---|---|---|
| `open` | `urls` (str or `{url,title}`), `workspace?`, `container?`, `group?`, `newGroup?{label,color,ref}`, `load?` | open tabs, **unloaded** unless `load: true`; container defaults to the workspace's |
| `group` | `tabs`, `label`, `color?`, `workspace?`, `ref?` | new folder from tabs |
| `move` | `tabs`, `workspace?`, `group?` (null = out of folder), `position?: "end"` | move between workspaces / into folders / reorder |
| `close` / `unload` | `tabs` | close, or free memory keeping the tab |
| `container` | `tabs`, `container` | reopen in another container (loses history) |
| `editGroup` | `group`, `label?`, `color?`, `collapsed?` | |
| `ungroup` | `group` | dissolve the folder, tabs stay |
| `createWorkspace` | `name`, `icon?`, `container?`, `id?` | |

**Focus:** a request never selects a tab or switches workspace unless it sets
`"focus": true` (`--focus`) — then the last touched tab comes to the front.
So an agent can open 50 tabs while you keep working. Turn the mailbox off with
the pref `sine-workspaces.api.enabled = false`.

## How it plugs into Sine

- Scripts load from `chrome://sine/content/sine-workspaces/…` (Sine maps
  `chrome://sine/content/` → `sine-mods/`). Only the entry `workspaces.uc.mjs`
  is declared in `mods.json`; the helper modules are pulled in via its ES import
  graph.
- `"no-updates": true` keeps Sine's auto-updater from ever fetching/clobbering
  this local mod; `"origin": "store"` lets its scripts load.
