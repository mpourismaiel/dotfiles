# pill — Quickshell top-center overlay

A Quickshell replacement for KDE's panels: one pill at the top-center of every
monitor that morphs between a collapsed clock, a hovered dashboard, a clicked-open
control panel (network/volume/bluetooth/battery/calendar/finance/clipboard/
notification menus), and an app launcher. It is also the machine's freedesktop
notification daemon. Runs on KDE Plasma 6 / KWin / Wayland.

**This directory is the source of truth.** The running shell loads a *copy* at
`~/.config/quickshell/pill/`. Edit here (no live effect), test with
`./check.sh` (validation only — python `ast` parse, `bash -n`, headless `qs`
load; touches nothing live), then run `./deploy.sh` to go live (runs check.sh,
then copies only changed files; the live config hot-reloads itself). Never edit
the live config directly. **`deploy.sh` is user-only — AI agents must never run
it, even if instructed; they run `./check.sh` and ask the user to deploy.**

Design rationale ("why is it built this way") lives in `../qs-pill-docs.org` —
one section per file here, plus environment facts (which Wayland protocols KWin
does/doesn't expose, how the pill takes the notification daemon over from
Plasma). Every source file also starts with a header comment saying what it is.

## Architecture in one paragraph

`init.qml` is the root: one `PanelWindow` per screen plus all shared state
(settings via `JsonAdapter`, one instance each of the `*State`/bridge-facing QML
components, the KWin DBus plumbing, action bursts, voice recording, the window
mask). Components receive state via required properties — no singletons.
`Theme.qml` carries every colour/metric/font. Python "bridges" are long-running
`Process`es speaking line-JSON on stdout (winbridge, clipbridge) or one-shot
query tools (orgbridge, gcalbridge, hledgerbridge, voicebridge); each has a QML
state component wrapping it. External control comes through `IpcHandler`
targets (`qs ipc call pill …` — clipboard/brightness/volume/voice/expand; `media`
for the media keys).

## Files

QML root & chrome:
- `init.qml` — root: windows, all shared state, stage morphing, IPC. Regions are documented per-section in the org file.
- `Theme.qml` — all colours/metrics/timings/fonts ("Terminal 79" amber-phosphor theme).
- `PillSurface.qml` — edge-attached panel background Shape (convex bottom corners, concave top wings).
- `CollapsedPill.qml` — resting clock + camera/screencast privacy glyphs.
- `OnAirWave.qml` — mic equalizer waveform across the pill while on-air.
- `MSym.qml` — one Material Symbols Rounded glyph.
- `MenuHeader.qml`, `SearchField.qml`, `BusyStripe.qml`, `ConnButton.qml`, `PillToggle.qml`, `PillSlider.qml` — shared menu chrome.
- `MenuKbNav.qml` — generic keyboard navigation over `kbFocusable`-tagged items.

Dashboard:
- `DesktopDots.qml` — virtual-desktop dots (KWin DBus).
- `Taskbar.qml` — pinned + open app tiles, drag-to-reorder.
- `StatusIcons.qml` — network/volume/bluetooth/battery/notification glyph row that opens the menus.

Control-panel menus (opened via `win.menu` index in init.qml):
- `NetState.qml` + `NetworkMenu.qml` — Wi-Fi/wired state and menu.
- `VolumeMenu.qml` — Pipewire devices + per-app streams.
- `BluetoothMenu.qml` — adapter, scan, connect/pair.
- `Brightness.qml` + `BatteryMenu.qml` — per-display brightness (KDE DBus) and power devices.
- `CalendarMenu.qml` (menu 6) — Shamsi/Gregorian month grid + org agenda + Google events; state in `OrgAgenda.qml` and `CalendarEvents.qml`.
- `AccountsState.qml` + `AccountsMenu.qml` — calendar account manager (KDE, Google OAuth, Proton ICS).
- `FinanceState.qml` + `FinanceMenu.qml` (menu 8) — hledger calendar/forecast/register/balances/wishlist, privacy + evening-nag machines.
- `Clipboard.qml` + `ClipboardMenu.qml` — cliphist history + fuzzy search.
- `VoiceMemoMenu.qml` (menu 7), `VoiceRecorderPill.qml`, `VoiceSetup.qml`, `PolishConfig.qml`, `Memos.qml` — voice-memo config, recording face, transcription setup/state.
- `NotificationHistory.qml` — grouped notification history.

Notifications:
- `Notifications.qml` — the freedesktop notification server + popup/history/DND state.
- `NotificationView.qml` — one card (popup, floating and history variants; inline reply).
- `NotificationStack.qml` — the active-popup deck.
- `ActionBurstPill.qml` — transient desktop-switch / language / level bursts.

Launcher & menus that float above the pill:
- `Launcher.qml` — search (KRunner via org.kde.milou) + favourites grid/list + calculator. Regions documented per-section in the org file.
- `AppMenu.qml` — floating right-click menu for a DesktopEntry (hosted at `win` level to escape the pill's clip).
- `AppContextMenu.qml` — taskbar app right-click menu (in-pill).
- `TrayMenu.qml` + `TrayMenuLevel.qml` — systray item DBus menus rendered in-pill.
- `PowerConfirm.qml` — full-screen shutdown/reboot/logout confirmation.

Python bridges:
- `winbridge.py` — open-window list + active window; loads a KWin script and owns `org.kde.pill` on DBus.
- `clipbridge.py` — cliphist backend.
- `orgbridge.py` — org agenda via emacsclient.
- `gcalbridge.py` — Google/Proton/KDE calendar events (signond SSO); dedups across providers.
- `hledgerbridge.py` — hledger queries for the finance menu.
- `voicebridge.py` — faster-whisper transcription + optional Claude polish (runs in its own venv).

Scripts & assets:
- `run-pill.sh` — launcher (resolves Wayland env before Qt starts).
- `check.sh` — validation only, live-safe (the agent test path).
- `deploy.sh` — check.sh + copy to live config (user-only).
- `pill-volume.sh` / `pill-brightness.sh` — media-key helpers bound in KDE Shortcuts (volume goes through pill IPC; brightness via brightnessctl).
- `setup-transcribe.sh` — one-time voice-pipeline setup (venv, shortcuts, API key).
- `source-rnnoise.conf` — PipeWire RNNoise filter-chain used during noise-suppressed recording.
- `transcribe.svg` — notification icon for transcription cards.

## Validating (what check.sh does, and its limits)

`QT_QPA_PLATFORM=offscreen qs -p init.qml` compiles and type-checks every
referenced component. Offscreen there is no Wayland, so a **correct** config
stops with exactly two ERROR lines (`Failed to load configuration` / `No
PanelWindow backend loaded`) — anything else is a real problem. This does NOT
instantiate children inside the PanelWindow delegate, so e.g. a missing required
property there escapes it; for those, use a `Scope`/`FloatingWindow` harness or
the mock-data screenshot rig (`../screenshots/check.sh`, also live-safe — see
the `quickshell-qml-validation` and `quickshell-screenshot-harness` agent
memories). `qmllint` is broken on this
machine; the `qml` tool is useless offscreen — use `qs`.
