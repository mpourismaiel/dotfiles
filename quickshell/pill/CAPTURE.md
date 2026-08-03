# Quickshell Capture — Screenshot + Screen Record (Flameshot-style, pill-integrated)

Design/implementation spec. Personal use, KWin/Wayland/Plasma 6.7, Quickshell 0.3.0.
This file is the source of truth for the build. Ticked decisions below are final unless the user says otherwise.

## ARCHITECTURE (current — fully in the pill)

Everything lives in `pill/` (the standalone `capture/` dir was removed). The CONTROLS are a new pill morph;
the FULLSCREEN part is a separate layer window.

- **Controls in the pill** (`win.capCtl` = mode `annotating` || `recConfig`): `captureLoader` shows
  `CaptureToolbar` (screenshot) or `RecordControls` (record); the pill width/height ternaries size to it.
  No REC timer while recording — the pill stays normal; stop via the row-2 capture button or IPC.
- **Fullscreen canvas** (`capWin`, declared BEFORE the pill so the pill stacks on top): `CaptureOverlay`
  (frozen grab + region + annotations) and `RecordCanvas` (transparent region + `WebcamOverlay`). While
  recording its input mask is empty (click-through); the webcam is still drawn (captured into the video).
- **Export is signal-driven**: pill toolbar → `CaptureState.requestCopy/Save` → `exportRequested` →
  `CaptureOverlay._export` (grabToImage full composite → `magick` crop to region → wl-copy / save).
- **Capture button** in dashboard row 2 (left of the network glyph): left = screenshot, right = record,
  click-while-recording = stop. IPC (`target: pill`): `screenshot` / `record` / `recordStop` / `captureCancel`.
- Grabber = `spectacle -b -n -m` (only one that works on this KWin; swappable via `CaptureState.grabCmd`).
- Record = `gpu-screen-recorder -w portal` (restore token) with no-hardcode encoder.

## STATUS

- **Phase 1 (screenshot): implemented + headless-validated.** grab → freeze →
  region → annotate → copy/save; tools select/text/arrow/rect/rectFill + colour +
  width + move/resize/delete.
- **Phase 2 (record): implemented + headless-validated.** transparent overlay →
  optional region → sources (mic + speaker dropdowns) + fps/codec/quality/cursor →
  `gpu-screen-recorder` via the KWin portal (persistent restore token) → SIGINT stop
  → copy file URI + save to `~/Videos`. **Encoder never hardcoded** (`-encoder gpu
  -fallback-cpu-encoding yes`; codec/quality user-selectable). During recording the
  window masks input to just the REC pill so the desktop stays clickable.
- **Phase 3 (webcam): implemented + headless-validated.** A live webcam overlay
  (QtMultimedia `Camera`+`VideoOutput`) rendered onto the record surface so it is
  captured into the recording (gpsr does NOT composite it). Config row: device
  dropdown, size, roundness (via `MultiEffect` mask), opacity, shadow, corner-snap
  + drag. **≥50%-visible collision gate** with a "Record anyway / Reposition" alert
  before recording. The headless harness renders a placeholder (never opens
  `/dev/video*`); the live camera preview is the user's to verify.
- Runs as a standalone Quickshell instance in `capture/`, entry `shell.qml`,
  selectable by name: `qs -c capture`. IPC: `screenshot` / `record` / `recordStop`
  / `cancel`. `capture/check.sh` passes (renders screenshot + record + recording
  stages offscreen). **The live grab, live record, audio/portal, and camera are the
  user's to verify** (agents can't run capture headlessly).
- **Pill integration (first cut): implemented + offscreen-validated.** The capture
  components are copied into `pill/`; `init.qml` gains `CaptureState` + `RecordController`,
  IPC verbs (`screenshot`/`record`/`recordStop`/`captureCancel` on target `pill`), a
  full-screen capture canvas window (declared last → stacks over the pill), and a
  **capture button** in dashboard row 2 (left of the network glyph): left-click =
  screenshot, right-click = record, click-while-recording = stop. `pill/check.sh`
  passes. FIRST-CUT caveats to verify live + iterate: the screenshot toolbar renders
  as a top-centre pill-styled bar over the frozen grab (not yet threaded through the
  pill's geometry ternaries as a true second-row morph); the capture button does
  direct actions (a dropdown menu is the next refinement); REC indicator may overlap
  the resting pill during record.
- **UI refinements (2026-08-03, second round):**
  - The capture morphs (chooser / screenshot toolbar / record settings) now carry a
    standard menu header — a back chevron + serif title (`CaptureHeader.qml`) top-left,
    like every control-panel menu — and the old close/X buttons are gone (the chevron
    cancels the capture: `state.cancel()`; the chooser's chevron just closes the menu).
  - An action burst (volume / brightness / desktop / language) fired **while the
    capture UI owns the pill** no longer strips the controls' background or paints over
    them: the `PillSurface` stays up during `capShow`, and `burstLoader` floats the
    burst mini-pill 8px BELOW the pill instead of centring it over the controls.
  - Record options are **preserved** across recordings: `beginRecord()` no longer clears
    the region (it persists like screenshots), and the sources/quality/webcam settings
    already live in the once-owned `RecordController`, so reopening record restores the
    last setup.
  - Webcam sizing is now **fine + live**: the record panel's discrete S/M/L + □/▢/◯
    segments are replaced by W / H / RADIUS steppers writing `rc.webcam*` directly
    (WebcamOverlay binds them, so changes apply immediately).
  - **8-point resize** (`ResizeHandles.qml` — 4 corner + 4 edge grips, clamped to the
    screen box and a min size) overlays the **record region**, the **webcam**, AND the
    **screenshot region** (annotating). The record region can be **dragged from the
    middle** to reposition (like the webcam); the webcam keeps its own middle-drag
    (`WebcamOverlay`), and the screenshot region is resize-only so its interior stays
    free for annotating (both use `moveEnabled: false`).
- **UI refinements (2026-08-03, third round):**
  - The capture morph is now a **self-contained menu mode, not the pill**: while it is
    up (`capShow`) the resting-pill interactions are all suppressed — click-to-expand,
    right-click deadlines, scroll-to-change-volume, the on-air equalizer, and the
    voice-recorder face + its floating cancel X (`voiceMorph` now excludes `capShow`;
    the take keeps running underneath and returns when capture closes).
  - The webcam **releases /dev/video\*** the moment the record controls close:
    `WebcamOverlay.live` (fed `rec.config || rec.live`) now gates the `Camera`, so the
    device is no longer left powered while the pill is idle.
  - A `gpu-screen-recorder` run that **dies immediately** (portal denied, no encoder,
    stale restore token) no longer masquerades as an instant "Recording saved": a
    non-zero gpsr exit is treated as a failure — `RecordController.failed(why)` fires
    with the captured stderr and the pill shows a "Recording failed" toast instead of
    copying/notifying a phantom file. (If your Record button "instantly saves", read
    that toast — it's the gpsr/portal error to fix.)
- Bug fixes (earlier round): annotations are NO LONGER clipped to the region (drawn over
  the whole image; region only crops the exported result via ImageMagick); the region
  PERSISTS across screenshots (next grab reuses it → straight to annotating; "reselect"
  toolbar button re-enters region draw); a new screenshot CLEARS old annotations.
- **DUPLICATION**: capture components now live in BOTH `capture/` (standalone dev +
  the check/harness) and `pill/` (production, deployed with the pill). Keep in sync —
  edit in `capture/`, run `capture/check.sh`, then copy the changed `*.qml` to `pill/`
  and run `pill/check.sh`.
- Remaining refinements: true second-row morph in the pill geometry, per-output
  multi-monitor cropping, restore-annotations button.

## 0. Environment facts (probed 2026-08-03, this machine)

- **grim / wf-recorder / wl-screenrec are DEAD here** — KWin advertises no `wlr-screencopy`
  (`grim` → "compositor doesn't support the screen capture protocol"). Do not use them.
- **Grab path = Spectacle** `spectacle -b -n -m -o <path>` (background, no-notify, current monitor).
  VERIFIED working live (2560×1440 PNG). Earlier "spectacle is dead" was WRONG — it was the test
  shell missing `WAYLAND_DISPLAY`; with the Wayland env (which the running qs instance has and passes
  to the subprocess) spectacle 6.7.3 works. The other paths were tried and REJECTED on this KWin:
    - `org.kde.KWin.ScreenShot2` DBus → `NoAuthorized` (KWin only allows allow-listed callers)
    - freedesktop `Screenshot` portal (`interactive:false`) → Response code 2 (backend refuses)
    - grim → no `wlr-screencopy`
  The grabber is a swappable seam (`CaptureState.grabCmd`, writes to `%o`, file loaded on clean exit);
  `screenshotbridge.py` remains as the portal alternate for machines where the portal works.
- **Record path = `gpu-screen-recorder`** (`extra/gpu-screen-recorder`, official repo). Drives the
  ScreenCast portal (`org.freedesktop.portal.ScreenCast`, present via xdg-desktop-portal-kde),
  hardware-encodes, restore-token capable, takes audio device args. Stop via SIGINT → clean finalize.
- **Webcam preview is feasible** — Quickshell 0.3.0 ships `libquickmultimediaplugin.so` and QtMultimedia
  QML is present, so `Camera` + `VideoOutput` overlay is buildable. Live `/dev/video0..3` present.
- **Audio**: PipeWire, 6 sources / 3 sinks. `Services.Pipewire` works natively in the pill.
  Record a sink's `.monitor` source for speaker capture.
- **Clipboard**: `wl-copy` present. Image → copy bytes. Video → `wl-copy --type text/uri-list` with `file://…`.
- **KWin gotcha**: Meta+Q / Alt+F4 while a layer surface holds the keyboard KILLS the pill
  (see quickshell-kwin-constraints memory). This tool is mouse-driven; only the hotkey trigger + Escape
  use keys, and the overlay releases keyboard focus otherwise. Do not grab Meta+Q/Alt+F4.

## 1. The load-bearing architecture: the file seam

Agents **cannot run any live capture** (no session in sandbox: portal grab, gpsr, and camera are all inert).
So the build is split by a file seam:

```
  [LIVE, user-only]                 [FILE SEAM]        [HEADLESS, agent-testable]
  portal Screenshot  ──────────►  /tmp/cap-*.png  ──►  region select · annotate · crop · export · wl-copy
  gpu-screen-recorder ─────────►  /tmp/rec-*.mp4  ──►  finalize · region-crop (ffmpeg) · copy · progress notif
  Camera → /dev/video0            (live preview)  ──►  webcam overlay UI built vs module, gated on user's live check
```

- **Agents build & validate everything right of the seam** against fixtures — a fake-desktop PNG for the
  screenshot editor, a stub file for the finalize/copy flow. Never run live capture.
- **User validates the three live seams**: the portal grab, the gpsr record, the webcam `/dev/video0` open.

## 2. Modes & flow

### Screenshot (grab-first)
1. Hotkey / IPC `screenshot` fires → **immediately** portal-grab the full screen to `/tmp/cap-<ts>.png`
   (resting pill baked in — accepted). No overlay is up yet, so nothing to hide.
2. Show `CaptureOverlay` fullscreen = the frozen PNG, dimmed outside the (not-yet-drawn) region.
3. Rubber-band region select on the frozen image (mouse click+drag). Pill **morphs** to show the tool row.
4. Annotate on the frozen image: tools = **text, arrow, rectangle (stroke), rectangle (filled)** [phase 1].
   Placed annotations are a **vector scene**: select, move, delete. Color + stroke-width picker.
5. Finish: `Ctrl+C` / copy button → copy cropped-image bytes to clipboard.
   `Ctrl+S` / save button → write `~/Pictures/Screenshots/<ts>.png` **and** copy. Escape cancels.
   Copy always happens on any finish (so it's immediately pasteable).

### Screen record (no grab)
1. Hotkey / IPC `record` → show `CaptureOverlay` **fully transparent** (live desktop shows through).
2. Configure via the overlay + pill morph:
   - Region select (click+drag) OR whole-screen (default).
   - **Screen** (which output): portal picker via restore-token; if token invalid → button shows
     "click to select" placeholder (best-effort; may reappear after a KWin/portal update — accepted).
   - **Mic** toggle → dropdown of sources, sane default auto-selected.
   - **Speaker** toggle → dropdown of sink monitors, sane default auto-selected.
   - **Webcam** toggle → third row: device, position (drag), roundness, shadow, opacity.
     `WebcamOverlay` renders live and STAYS during recording (baked in — wanted).
3. **Record button** (height = two action rows + margin). On press:
   - Collision check: if webcam enabled and <50% of it is on-screen → blocking alert, prevent start,
     let user reposition, re-confirm.
   - Hide all tools/controls (pill reverts to resting state — resting pill baked into video, accepted).
   - Start `gpu-screen-recorder` on the chosen output with mic/speaker args → `/tmp/rec-<ts>.mp4`.
4. Stop: pill's **screen-tools menu → "stop & save"**, or IPC `recordStop` → SIGINT gpsr → finalize.
   - Region record = record full output then `ffmpeg` crop to the region (extra pass → progress notif).
   - On finish: copy the file as `text/uri-list` so it's pasteable; save to `~/Videos/<ts>.mp4`.

## 3. Components

New dir `quickshell/capture/` (built/tested headless; sibling of `pill/`, `emaqs/`):

- `CaptureState.qml` — mode machine (idle / shot-select / shot-annotate / rec-config / recording),
  region rect, active tool + style (color/width), annotation model, record options
  (output/restore-token, mic{on,dev}, speaker{on,dev}, webcam{on,dev,x,y,round,shadow,opacity}), signals.
- `CaptureOverlay.qml` — fullscreen transparent layer-shell window, **above normal windows, below the pill**.
  Screenshot role: frozen PNG + dim mask + rubber-band + `AnnotationScene`.
  Record role: transparent + rubber-band + `WebcamOverlay` + collision check.
- `AnnotationScene.qml` + `AnnText.qml` / `AnnArrow.qml` / `AnnRect.qml` — vector items with move/select/delete
  handles. Export = render the scene over the cropped image to PNG.
- `WebcamOverlay.qml` — live `Camera` + `VideoOutput`, draggable, styled (roundness/shadow/opacity).
- `screenshotbridge.py` — portal `Screenshot` (non-interactive) handshake; prints saved PNG path.
  **Swappable seam**: `CaptureState` calls one `grab(path)` entry point; the grabber is selected by a
  single `grabCmd` string so the portal impl can be replaced (spectacle/ScreenShot2 helper/other) with
  no editor changes. If the portal proves flaky live, swap `grabCmd` — do NOT relentlessly debug it.
- `recordbridge.py` — build + run `gpu-screen-recorder`; on stop finalize, ffmpeg-crop for region,
  `wl-copy` the result, emit progress lines for the notification. (Consistent with winbridge/orgbridge pattern.)

Pill integration (`quickshell/pill/`):
- Capture morph: tool row (screenshot) / record-option rows (record) in the expanded pill.
- New **menu icon button left of the network icon** → `CaptureMenu`: default = Screenshot / Screen record;
  while recording = Stop & save.
- IPC verbs on `IpcHandler pill` (or new target `capture`): `screenshot`, `record`, `recordStop`, `cancel`.
- **Progress notification**: no timer, dismissable, progress bar, auto-dismiss on done. App-side (pill owns
  the NotificationServer). Used for the record finalize/crop pass (screenshots are instant).

## 4. Test harness (agents)

`quickshell/capture/check.sh` (extends the `screenshots/`/`check.sh` pattern):
- Generates a **fake-desktop PNG fixture** (ImageMagick/ffmpeg gradient + shapes) as the frozen capture.
- Loads `CaptureOverlay` in the screenshot role over the fixture in an offscreen `qs` (FloatingWindow/Scope harness).
- Agents validate: region rubber-band, each annotation tool, select/move/delete, crop math, PNG export,
  `wl-copy` invocation (stubbed), the pill morphs (via animate.sh-style capture).
- Agents DO NOT run: portal grab, gpu-screen-recorder, live camera. Those print a clear "user-only" skip.
- Never touch the live pill config or run any `deploy.sh` (user deploys himself — per repo memory).

## 5. Phasing

- **Phase 1 — Screenshot**: grab bridge, freeze overlay, region select, annotation editor
  (text/arrow/rect stroke+filled, color+width, move/select/delete), copy+save, pill morph + tool row,
  menu button, IPC `screenshot`/`cancel`, fake-desktop test harness.
- **Phase 2 — Record**: transparent overlay region select, record-option rows (screen+restore-token,
  mic dropdown, speaker dropdown), `recordbridge.py` + gpu-screen-recorder, stop via pill menu + IPC
  `recordStop`, region crop via ffmpeg, copy file uri, progress notification.
- **Phase 3 — Webcam** (may slip; user validates live): `WebcamOverlay` live preview, positioning/styling,
  ≥50% collision gate. Built against the QtMultimedia module headless; live camera open is user-only.
- **Phase 2.5 (optional)** — extra annotation tools: line, pen/freehand, highlighter.

## 6. Install prerequisites

- **`gpu-screen-recorder`** (`sudo pacman -S gpu-screen-recorder`) — the ONLY required install.
  **NEVER hardcode the HW encoder** (user swaps hardware) — default to gpsr auto-detect; expose
  encoder/codec/quality as selectable options in the record settings row (second row → settings menu).
- Already present, no action: `xdg-desktop-portal-kde` (grab + screencast), `pipewire`, `wl-clipboard`,
  `ffmpeg`, Quickshell QtMultimedia plugin.

## 7. Open/assumed decisions (correct me if wrong)

- Save dirs: screenshots → `~/Pictures/Screenshots/`, videos → `~/Videos/`, timestamped names.
- Always copy on any finish (image bytes / video uri) so it's immediately pasteable.
- Phase-1 annotation tools exactly: text, arrow, rectangle-stroke, rectangle-filled (+ color & width).
  Line/pen/highlight deferred to 2.5.
- Region-record = full-output record + ffmpeg crop (no native sub-region record in gpsr).
- Resting pill baked into screenshots AND recordings is accepted/expected.
