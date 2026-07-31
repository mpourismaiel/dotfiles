# Screenshot harnesses (pill + emaqs)

Render **off-screen, mock-data** screenshots of the pill and emaqs overlays without
touching the live `~/.config/quickshell/*` configs or their DBus names — so you can
eyeball every UI state (and catch visual regressions) even while both overlays are
running.

## Usage

```sh
quickshell/screenshots/shoot.sh          # copy sources + render everything → PNGs
quickshell/screenshots/check.sh          # same, then assert all 18 stages rendered clean
SHOT_DIR=/some/build/dir shoot.sh        # override the build dir (default /tmp/shot)
```

Output (PNGs + `_pill-contact.png` / `_emaqs-contact.png` contact sheets) lands in
`$SHOT_DIR/out` (default `/tmp/shot/out`). Nothing is written under `~/.config`.

Requires: a running Wayland session, `qs` (Quickshell), `magick` (contact
sheets). Fonts: DM Serif Display, IBM Plex Sans/Mono, Material
Symbols Rounded, Newsreader, Instrument Serif.

## How it stays safe

`shoot.sh` copies the repo sources (`quickshell/{pill,emaqs}/`) to a throwaway
**build dir** (never the live config), neuters every python bridge (`winbridge`/`clipbridge`/`orgbridge`/`fswatch`/
`emaqsbridge`/`agentbridge`) to a sleep loop, and renders through harnesses that
never instantiate a `NotificationServer`, `winbridge`, or any `Process`/DBus source.

## Layout

| file | role |
|------|------|
| `shoot.sh` | copy sources → install mocks → neuter bridges → render → contact sheets |
| `check.sh` | run `shoot.sh` + assert all stages produced non-trivial PNGs |
| `mk-emaqs.py` | rewrites the build-dir copy of emaqs `init.qml` into a `FloatingWindow` harness with a state-stepping grabber |
| `pill/harness.qml` | composition harness: hosts the **real** pill leaf components + menus against the mocks below |
| `pill/Mock*.qml` | `MockNetState` / `MockNotifs` / `MockClip` / `MockOrg` / `MockBrightness` |
| `emaqs/Mock*.qml` | `MockEmacs` / `MockAgent` |

Two strategies: **emaqs** is a mechanical *transform* of its `init.qml` (its whole UI
is driven by the `emacs`/`agent` bridges, which the mocks replace); the **pill** is a
*composition* harness because its body is inline in the `PanelWindow` delegate — until
that body is extracted into a reusable `PillContent.qml`, the harness re-implements the
dashboard row layout (kept in sync by eye against `../pill/init.qml`).

`@OUT@` in `pill/harness.qml` / `pill/MockClip.qml` is a path placeholder filled in by
`shoot.sh`, so the repo sources stay path-agnostic.

## Stages rendered

- **emaqs (7):** collapsed, working, finished, permission, bar, menu, confirm
- **pill (11):** resting, resting-rec, dashboard, menu-network, menu-volume,
  menu-bluetooth, menu-battery, menu-clipboard, menu-calendar, menu-notifhistory,
  notif-stack

> Note: `VolumeMenu`, `BluetoothMenu`, and the battery *rows* read Quickshell
> singletons directly (Pipewire/Bluetooth/UPower), so those render **live** system
> data, not mock. Extracting `VolumeState`/`BluetoothState` objects (like `NetState`)
> would make them injectable, testable, and fully mockable.
