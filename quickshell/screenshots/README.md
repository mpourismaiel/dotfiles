# Screenshot + animation harnesses (pill + emaqs)

Render **off-screen, mock-data** stills *and* short **animation clips** of the pill and
emaqs overlays without touching the live `~/.config/quickshell/*` configs or their DBus
names — so you can eyeball every UI state (and catch visual regressions), and record /
debug motion, even while both overlays are running.

## Usage

```sh
quickshell/screenshots/shoot.sh          # copy sources + render every still → PNGs
quickshell/screenshots/shoot.sh menu-tetris  # FAST: only pill states whose name contains
                                         #   this substring (pill-only; skips emaqs + contact
                                         #   sheets; leaves other PNGs untouched). ~2s vs ~35s.
quickshell/screenshots/check.sh          # same, then assert all stages rendered clean
quickshell/screenshots/animate.sh        # record animation scenes → mp4 + gif + frame strips
SHOT_DIR=/some/build/dir shoot.sh        # override the build dir (default /tmp/shot)
```

Use the targeted form (`shoot.sh <name-substring>`, or `SHOT_ONLY=<substring>`) for the
per-edit loop while iterating on one pane; run the **no-arg full pass when you're done**
to confirm nothing else regressed. State names are in `pill/harness.qml`'s `_states`
(e.g. `menu-tetris`, `dashboard`, `menu-finance-add`).

Output lands in `$SHOT_DIR/out` (default `/tmp/shot/out`): stills (PNGs +
`_pill-contact.png` / `_emaqs-contact.png` contact sheets) from `shoot.sh`; and per-scene
`<scene>.mp4`, `<scene>.gif`, a `<scene>-strip.png` sampled-frame contact strip, plus the
raw `frames/<scene>-f####.png` from `animate.sh`. Nothing is written under `~/.config`.

The strip PNG is the quick way to eyeball motion in a single image (10 evenly-spaced
frames, montaged); the mp4/gif play it back at speed.

Requires: a running Wayland session, `qs` (Quickshell), `magick` (contact
sheets/strips), `ffmpeg` (mp4/gif). Fonts: DM Serif Display, IBM Plex Sans/Mono, Material
Symbols Rounded, Newsreader, Instrument Serif.

## How it stays safe

`shoot.sh` copies the repo sources (`quickshell/{pill,emaqs}/`) to a throwaway
**build dir** (never the live config), neuters every python bridge (`winbridge`/`clipbridge`/`orgbridge`/`fswatch`/
`emaqsbridge`/`agentbridge`) to a sleep loop, and renders through harnesses that
never instantiate a `NotificationServer`, `winbridge`, or any `Process`/DBus source.

## Layout

| file | role |
|------|------|
| `shoot.sh` | copy sources → install mocks → neuter bridges → render stills → contact sheets |
| `check.sh` | run `shoot.sh` + assert all stages produced non-trivial PNGs |
| `animate.sh` | copy sources → install mocks → neuter bridges → play scenes, grab frames → encode mp4/gif + strips |
| `mk-emaqs.py` | rewrites the build-dir copy of emaqs `init.qml` into a `FloatingWindow` harness with a state-stepping grabber |
| `pill/harness.qml` | composition harness: hosts the **real** pill leaf components + menus against the mocks below (stills) |
| `pill/anim.qml` | animation harness: plays a named scene and grabs a burst of frames on a timer (`frameMs`) |
| `pill/Mock*.qml` | `MockNetState` / `MockNotifs` / `MockClip` / `MockOrg` / `MockBrightness` |
| `emaqs/Mock*.qml` | `MockEmacs` / `MockAgent` |

Two strategies: **emaqs** is a mechanical *transform* of its `init.qml` (its whole UI
is driven by the `emacs`/`agent` bridges, which the mocks replace); the **pill** is a
*composition* harness because its body is inline in the `PanelWindow` delegate — until
that body is extracted into a reusable `PillContent.qml`, the harness re-implements the
dashboard row layout (kept in sync by eye against `../pill/init.qml`).

`@OUT@` in `pill/harness.qml` / `pill/MockClip.qml` is a path placeholder filled in by
`shoot.sh`, so the repo sources stay path-agnostic.

## Stages rendered (stills)

The authoritative list is `pill/harness.qml` `_states` (mirrored in `check.sh`
`PILL_STATES` — keep the two in sync). Currently:

- **emaqs (7):** collapsed, working, finished, permission, bar, menu, confirm
- **pill (46):** resting, resting-rec, resting-due, resting-meeting, clock-styles,
  deadlines, dashboard, menu-network, menu-volume, menu-bluetooth, menu-battery,
  menu-clipboard, menu-calendar, menu-finance{,-add,-wishlist,-forecast,-plan,-register,-category},
  menu-games, menu-tetris{,-share}, menu-blockblast{,-combo,-share}, menu-brickbreaker,
  menu-snake, menu-minesweeper, menu-invaders{,-draft,-path,-laser,-vapor}, settings,
  settings-productivity, menu-emoji{,-search}, menu-done{,-loading}, menu-notifhistory,
  notif-stack, power-hush, power-blaze, power-ledger, power-split

**Every new game gets its own stage(s) — in the same change that adds the game.**
Recipe: seed a *mid-game* state in `mockSettings` (`mockSettings.<game>`, matching
the game's `save()` shape), add a `Component` + `_states` entry, and append the
stage name to `check.sh` `PILL_STATES`. Games open paused / behind veils, so the
stage usually needs a post-load `Timer` (unpause, reveal cells, roll a draft…) so
the PNG shows a real board. Then *look at the PNG* — stale-render bugs load clean
but screenshot as an empty board. This keeps the per-edit test loop at ~2s
(`shoot.sh menu-<game>`) instead of hand-driving the live pill.

## Animation scenes (`pill/anim.qml` `_scenes`)

- **deadlines** — the `AgendaMenu` drop-in entrance (fade + slide + scale from top).
- **droplet** — the notification **water-droplet drop-out**: a droplet detaches from the
  resting pill's bottom lip, falls, and splashes onto the deck floating below (the deck's
  entrance syncs to `NotificationDroplet.landed()`). See `../pill/NotificationDroplet.qml`.

Add a scene by appending `{ name, comp, settleMs, durationMs }` to `_scenes` and a matching
`Component` that exposes `function play()` (kick the animation from its start state). Keep
`animate.sh`'s `FPS` in sync with `anim.qml`'s `frameMs` (40ms → 25 fps).

> Note: `VolumeMenu`, `BluetoothMenu`, and the battery *rows* read Quickshell
> singletons directly (Pipewire/Bluetooth/UPower), so those render **live** system
> data, not mock. Extracting `VolumeState`/`BluetoothState` objects (like `NetState`)
> would make them injectable, testable, and fully mockable.
