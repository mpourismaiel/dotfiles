# workspace-hud

A togglable, pretty **workspace HUD that floats on the right edge of the frame**
as a borderless, non-focusable **child frame** — a real layer on top of your
windows, *not* a window in the tree. Because it isn't in the window tree,
magit/splits/`other-window` never interact with it (the reason the earlier
side-window version was dropped).

Its content is a single **SVG image** (same technique as `svg-header`), so the
styling is pixel-precise and derived from the current theme's faces.

## What it shows

For the buffer you're actually looking at (the parent frame's selected window):

- **Git** — project name (title); a magit icon on the section header (→ magit
  status); the branch (click → change/checkout branch); a **Dirty** row with a
  **commit icon** (click → stage everything incl. untracked + open the magit
  commit buffer); and the **changed files** under it (per-file line counts,
  untracked marked `new`, **click a file to open it**). The list is capped to fit.
- **Health** — LSP status; **Diagnostics** count `NE MW` (click → open the
  error/warning list). **Hidden entirely when no LSP server is running.**
- **Agents** — a `+ New agent` button (launches agent-shell), and for each active
  agent-shell: model, effort/thought-level, permission mode, a `working`/
  `asking`/`ready` status, context-usage %, and elapsed time of the current run.
- **Debugger** — only when a dape config matches the current buffer (or a session
  is live). Shows `paused`/`running` + the stop location, and **context-aware
  controls**: `cont/over/in/out/stop` when paused, `pause/stop` when running,
  `launch` when idle.

Icons are drawn as vector paths (uniform accent color). **Everything actionable
is clickable** — a `mouse-1` handler hit-tests regions in the SVG, and an image
`:map` gives a hand cursor + tooltip on hover. The **Debugger** section only
appears for buffers a dape config explicitly targets (prog-mode + matching
`modes`), so it stays hidden on org/text/etc.

## Behaviour

- **Event-driven.** Refreshes on a ~50 ms idle debounce when something happens:
  buffer switch, window selection/scroll, save (busts the git cache), diagnostics
  change, major-mode change, parent-frame resize, agent-shell events, and dape
  state changes. The only periodic timer is a 1 s tick that runs *solely while an
  agent is busy* (to advance the elapsed clock).
- Set `mp/workspace-hud-debug` to t to trace internals to `*workspace-hud-log*`.
- Docks to the right edge **between the header line and the mode line + echo
  area** — measured from the target window's inside pixel edges (robust to the
  svg-header changing height), with `mp/workspace-hud-top-margin` px of top gap.
- **Auto-hides over magit buffers** (and the commit-message buffer); see
  `mp/workspace-hud-suppress-modes`. Reappears when you leave them.
- Icons are drawn as **SVG vector paths**, so they render regardless of font
  glyph coverage. Uses the frame's default (editor) background — no card.
- **GUI only** — child frames need a graphical frame; `mp/workspace-hud-open`
  errors politely in a terminal.
- Passive: `no-accept-focus` / `no-focus-on-map`, so it never steals focus and
  you don't click into it (interaction can be added later).

## Usage

- `SPC t W` (or `M-x mp/workspace-hud-toggle`) — toggle.
- `mp/workspace-hud-open` / `mp/workspace-hud-close`.

## Customization

- `mp/workspace-hud-width` — child-frame width in pixels (default 360).
- `mp/workspace-hud-git-ttl` — git result cache lifetime in seconds (busted on
  save; default 1.5).
- `mp/workspace-hud-max-files` — cap on listed changed files before summarising
  with `… and N more` (default 14).
- `mp/workspace-hud-top-margin` — px gap below the header line (default 4).
- `mp/workspace-hud-suppress-modes` — modes over which the HUD auto-hides
  (default `(magit-mode)`).

Colors are pulled from `default`/`success`/`warning`/`error`/
`font-lock-keyword-face` at render time, so it blends with any theme.

## Notes / not yet done

- **True rounded card corners** would need a transparent child-frame background
  (`alpha-background`, compositor-dependent); for now the card is full-bleed with
  a left accent rail.
- Colors can't be previewed headlessly (a no-display Emacs mangles
  `color-name-to-rgb`); the SVG layout renders fine in batch, but colors only
  resolve correctly in a live GUI frame.

## Origin

Inspired by the [emacs-workspace-hud](https://github.com/nohzafk/emacs-workspace-hud)
screenshot (from [agent-shell-hud](https://github.com/nohzafk/agent-shell-hud)),
but that renders via an xwidget hosting a Rust/WASM egui app. This is a native
reimplementation — child frame for the floating surface, SVG for the look — with
no xwidget or WASM.
