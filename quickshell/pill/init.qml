pragma ComponentBehavior: Bound
// ----------------------------------------------------------------------------
// init.qml — morphing "pill" overlay for KDE Plasma 6 / KWin / Wayland.
//
// Stages: collapsed (hh:mm) -> focused (click to reveal the dashboard, two balanced
// rows; attaches flush to the top edge, "rounded out", and holds until a click
// elsewhere) -> clicked (control panel). See qs-pill-docs.org for the full notes.
//
// Run with:  qs -p quickshell/init.qml
// ----------------------------------------------------------------------------
import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

ShellRoot {
    id: root
    property var desktops: []
    property string currentDesktop: ""
    property var windows: []          // [{id, uuid, title, icon, cls, dfile, seq}]
    property string _winJson: ""      // last windows payload, to skip no-op rebuilds
    property string activeWindow: ""  // active window uuid "{...}"
    property string activeScreen: ""  // output name of the focused window's monitor
    property bool activeFullscreen: false  // is the focused window fullscreen?
    // last *real* focused window — opening the pill (layer-shell keyboard grab)
    // can momentarily clear activeWindow on KWin, so we keep the last non-empty
    // value and re-activate it when the pill closes (KWin doesn't restore focus
    // to the previously-active window on its own when a layer surface lets go).
    property string lastActiveWindow: ""
    onActiveWindowChanged: if (activeWindow !== "") lastActiveWindow = activeWindow
    
    // requested via the Meta+D global shortcut (KWin script -> winbridge -> here)
    signal launcherShortcut(string screen)
    // requested via IPC (`qs ipc call pill clipboard`) — bind a KDE custom shortcut to
    // that command (e.g. Super+V) to open the clipboard-history menu. Empty screen ->
    // every pill responds (right for a single monitor); a name targets one monitor.
    signal clipboardShortcut(string screen)
    // requested via IPC (`qs ipc call pill notifications`) — opens the notification
    // history pane (menu 4) for keyboard-driven triage. Same empty-screen / named-screen
    // rule as the clipboard shortcut.
    signal notifShortcut(string screen)
    // requested via IPC (`qs ipc call pill expand`) — opens the expanded dashboard
    // (like clicking the collapsed pill) in keyboard-nav mode: arrows move the focus
    // square between the dashboard items, Enter clicks, f/c/n/w/v/b jump to a menu,
    // Escape steps back (menu -> dashboard -> closed). Same screen rule as above.
    signal expandShortcut(string screen)
    IpcHandler {
        target: "pill"
        function clipboard(): void { root.clipboardShortcut(""); }
        function clipboardOn(screen: string): void { root.clipboardShortcut(screen); }
        // open (or toggle shut) the notification history pane — bind to a KDE custom
        // shortcut to review/triage notifications from the keyboard (arrows to move,
        // Enter to open, i to reply, x/Delete to dismiss — see NotificationHistory.qml).
        function notifications(): void { root.notifShortcut(""); }
        function notificationsOn(screen: string): void { root.notifShortcut(screen); }
        // open (or toggle shut) the expanded dashboard in keyboard-nav mode — bind to
        // a KDE custom shortcut to drive the whole pill from the keyboard (arrows /
        // Enter / f c n w v b / Escape — see the per-monitor overlay notes).
        function expand(): void { root.expandShortcut(""); }
        function expandOn(screen: string): void { root.expandShortcut(screen); }
        // ---- capture (screenshot + screen-record) ----
        // screenshot: grab the current monitor, then region-select + annotate in the
        // full-screen overlay with the toolbar in the pill. record: transparent
        // overlay to pick a region + sources, then record via gpu-screen-recorder;
        // recordStop finalizes. Bind these to KDE custom shortcuts.
        function screenshot(): void { capture.beginScreenshot(); }
        // like screenshot, but REUSES the last selected crop (draws one if none yet).
        function screenshotRegion(): void { capture.beginScreenshotRegion(); }
        function record(): void { capture.beginRecord(); }
        function recordStop(): void { capRec.stop(); }
        function captureCancel(): void { if (capture.mode !== "recording") capture.cancel(); }
        // dismiss every popup currently on screen but KEEP them in history — the "I'm
        // busy, not now" one-key sweep (mirrors the deck's "Dismiss all"). Bind to a KDE
        // custom shortcut. Unlike clearNotifications this does NOT touch history, so the
        // unread strip / badge stays and they're still reviewable in the pane later.
        // (`notifs` is an id, not a property of root — `root.notifs` is undefined.)
        function dismissNotifications(): void { notifs.dismissAll(); }
        // clear every notification from history at once (no menu needed) — bind to a
        // KDE custom shortcut for a one-key "clear all". Mirrors the pane's "Clear all";
        // this DOES wipe history (the harder sweep vs dismissNotifications above).
        function clearNotifications(): void { notifs.clearAll(); }
        // step the *active monitor's* brightness up/down by ~5% and flash a level burst
        // (icon + Brightness title + from->to bar). Bind these to KDE custom-command
        // shortcuts; the active monitor is the focused window's output (activeScreen).
        function brightnessUp(): void   { root.brightnessStep(root.activeScreen, 1); }
        function brightnessDown(): void { root.brightnessStep(root.activeScreen, -1); }
        // target a named monitor explicitly (skip the active-window lookup)
        function brightnessUpOn(screen: string): void   { root.brightnessStep(screen, 1); }
        function brightnessDownOn(screen: string): void { root.brightnessStep(screen, -1); }
        // step the *active speaker* (the default sink — the one checked in the volume
        // menu) up/down by ~5%, or toggle its mute, each flashing a level burst. Bind
        // these to KDE custom-command shortcuts on the volume keys (free the keys from
        // Plasma's own volume actions first, so only our burst shows — no double OSD).
        function volumeUp(): void   { root.volumeStep(1); }
        function volumeDown(): void { root.volumeStep(-1); }
        function volumeMute(): void { root.volumeToggleMute(); }
        // voice-to-text (see § init.qml — voice recording). Both start a take when
        // idle; the one that STOPS it picks the route: voiceToggle -> raw transcript
        // to the clipboard, voicePolishToggle -> Claude-polished text. Bind to KDE
        // custom-command shortcuts (setup-transcribe.sh registers Meta+X / Meta+Shift+X).
        // voiceToggle: quick raw note — start immediately when idle, stop when recording.
        function voiceToggle(): void {
            if (root.voiceState === "recording") root.voiceStop();
            else if (root.voiceState === "idle") root.voiceStartQuick();
        }
        // voicePolishToggle: opens the memo config menu when idle (type + polish/org
        // switches, then Start); stops the take when recording.
        function voicePolishToggle(): void {
            if (root.voiceState === "recording") root.voiceStop();
            else if (root.voiceState === "idle") root.voiceMemoRequested();
        }
    }
    // pick the volume glyph for a level/mute state (matches the dashboard status icon).
    function volumeGlyph(v, muted) {
        if (muted) return "volume_off";
        if (v <= 0.001) return "volume_mute";
        if (v < 0.5) return "volume_down";
        return "volume_up";
    }
    // step the default sink's volume by ~5% and flash a level burst (from -> to).
    function volumeStep(sign) {
        const sink = Pipewire.defaultAudioSink;
        if (!sink || !sink.audio) return;
        const from = sink.audio.volume;
        const to = Math.max(0, Math.min(1, from + sign * 0.05));
        sink.audio.volume = to;
        root.startLevelBurst(root.volumeGlyph(to, sink.audio.muted), "Volume", from, to);
    }
    // toggle the default sink's mute and flash a level burst at the current level.
    function volumeToggleMute() {
        const sink = Pipewire.defaultAudioSink;
        if (!sink || !sink.audio) return;
        const m = !sink.audio.muted;
        sink.audio.muted = m;
        const v = sink.audio.volume;
        root.startLevelBurst(root.volumeGlyph(v, m), m ? "Muted" : "Volume", v, v);
    }
    // step the active monitor's brightness by ~5% (via the shared Brightness state) and
    // flash a level burst from the last-known ratio to the clamped target.
    function brightnessStep(screen, sign) {
        const d = brightness.displayForScreen(screen);
        const from = d ? d.value : 0;
        const to = Math.max(0, Math.min(1, from + sign * 0.05));
        brightness.stepActive(screen, sign);
        root.startLevelBurst("brightness_high", "Brightness", from, to);
    }
    
    Theme { id: theme; overrides: themeAdapter.colors }
    // keep the default sink bound so the dashboard volume icon reflects mute live
    PwObjectTracker { objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : [] }
    
    // ---- privacy indicators (resting pill) ----
    // camera + screen-capture in use show an icon next to the collapsed clock and make
    // the resting pill opaque (drops the idle translucency) so it can't be missed. A
    // hot mic is deliberately ignored (see privacyActive below).
    //   camera — poll for any process holding a /dev/video* node open (fuser).
    //   screen — a live screencast: xdg-desktop-portal / KWin exposes the captured
    //            frames as a "Stream/Output/Video" PipeWire node while the screen is
    //            shared or recorded (cameras are "Video/Source" and consumers are
    //            "Stream/Input/Video", so a video *output* stream uniquely means the
    //            screen itself is being captured). Shown as a pulsing red dot.
    property bool cameraInUse: false
    // keep every PipeWire node bound so a screencast node's media.class is readable
    // the moment it appears (and disappears) — this drives screenRecording below.
    PwObjectTracker { objects: Pipewire.nodes ? Pipewire.nodes.values : [] }
    readonly property bool screenRecording: {
        const ns = Pipewire.nodes ? Pipewire.nodes.values : [];
        for (let i = 0; i < ns.length; i++) {
            const p = ns[i].properties;
            if (p && p["media.class"] === "Stream/Output/Video") return true;
        }
        return false;
    }
    // only a live camera or an active screencast count as privacy indicators — a hot
    // mic is deliberately ignored (an unmuted mic is a routine resting state, and
    // flagging it was more noise than signal). These drive the indicator glyphs, the
    // solid resting surface (privacyRest), and staying visible over a fullscreen
    // window (fsHide).
    readonly property bool privacyActive: cameraInUse || screenRecording
    readonly property int  privacyCount: (cameraInUse ? 1 : 0) + (screenRecording ? 1 : 0)
    
    // ---- resting-pill notification indicator footprint ----
    // At rest the collapsed pill shows one app icon per app that has un-cleared
    // notifications (deduped via notifs.grouped), so a glance reveals *which* apps
    // are waiting. Capped at `notifAppIconsMax` with a "+N" overflow chip. In
    // do-not-disturb (which a live screencast auto-enters) the app icons are hidden
    // and a single generic unread dot stands in — so during a sensitive share the
    // pill doesn't reveal notification sources, while dropping DND brings the icons
    // back for showcasing. `notifRestWidth` is the extra pill width that footprint
    // needs (used in the resting width below).
    readonly property int notifAppIconsMax: 4
    readonly property int notifRestWidth: {
        if (!notifs || notifs.grouped.length === 0) return 0;
        if (notifs.dnd) return 14;                           // generic unread dot only
        const overflow = notifs.grouped.length > root.notifAppIconsMax ? 1 : 0;
        const n = Math.min(notifs.grouped.length, root.notifAppIconsMax) + overflow;
        return n * 20;                                        // ~14px icon + spacing each
    }
    
    // ---- microphone state for the "on-air" equalizer (OnAirWave) ----
    // Only meaningful while a camera or screencast is live. `micUnmuted` decides the
    // wavy-vs-flat line; `micPeak.peak` is the live input level driving the amplitude.
    // Bind the default source into a tracker so its `audio` (hence `muted`) populates,
    // and only run the peak monitor while on-air + unmuted so it isn't metering for
    // nothing.
    readonly property bool micUnmuted: (Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio)
                                       ? !Pipewire.defaultAudioSource.audio.muted : false
    PwObjectTracker { objects: Pipewire.defaultAudioSource ? [Pipewire.defaultAudioSource] : [] }
    PwNodePeakMonitor {
        id: micPeak
        node: Pipewire.defaultAudioSource
        // meters while on-air (the OnAirWave equalizer) OR while a voice note is
        // recording (the VoiceRecorderPill waveform) — off otherwise.
        enabled: (root.privacyActive && root.micUnmuted) || root.voiceState === "recording"
    }
    
    Process {
        id: cameraProc
        command: ["sh", "-c", "fuser /dev/video* >/dev/null 2>&1 && echo busy || echo idle"]
        stdout: StdioCollector { onStreamFinished: root.cameraInUse = (this.text.indexOf("busy") !== -1) }
    }
    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true
            onTriggered: cameraProc.running = true }
    // ---- notifications (freedesktop server + popup/history state) ----
    // Owns org.freedesktop.Notifications; requires Plasma's own notifications to
    // be disabled first (System Tray Settings -> Notifications -> Disabled), since
    // plasmashell registers the name without ALLOW_REPLACEMENT. Shared with every
    // monitor's pill (the morph + floating cards) and the history menu.
    Notifications {
        id: notifs
    
        theme: theme
        // auto-enter DND while a screencast is live; on stop it restores the prior DND
        // state and posts a "you missed N" summary (see Notifications.qml).
        screenShare: root.screenRecording
    }
    // ---- clipboard history (cliphist watchers + shared state) ----
    Clipboard { id: clipboard }
    // permanent voice-memo store (~/Documents/memos), shown in the clipboard menu's
    // Memos tab; shares the settings adapter for the re-polish model ids.
    Memos { id: memos; settings: settings }
    // in-pill transcription setup (cloud keys + local-model download) for the
    // Transcribe tab — replaces setup-transcribe.sh's key prompt / model pull.
    VoiceSetup { id: voiceSetup; settings: settings }
    Process {
        running: true
        command: ["python", Quickshell.shellPath("clipbridge.py"), "watch"]
    }
    // ---- org agenda state (Emacs daemon via orgbridge.py), shared with the calendar ----
    // Gated by the Settings page: off → no orgbridge calls, no dots/deadlines; the
    // configured dir overrides Emacs's org-agenda-files so it's not tied to one setup.
    OrgAgenda {
        id: orgAgenda
        enabled: settings.orgAgendaEnabled
        agendaDir: settings.orgAgendaDir
    }
    // ---- Google Calendar events (KDE accounts + signond via gcalbridge.py), shared ----
    CalendarEvents {
        id: calEvents
    }
    // ---- calendar account manager (KDE + pill Google/Proton accounts), shared with the
    //      launcher's settings page; refetches calEvents whenever accounts change ----
    AccountsState {
        id: accounts
        cal: calEvents
    }
    // ---- finance state (hledger via hledgerbridge.py), shared with the menus,
    //      launcher privacy toggle and the status-icon nag ----
    FinanceState {
        id: finance
        settings: settings
        enabled: settings.financeEnabled
        financeDir: settings.financeDir
        screenShare: root.screenRecording
        now: sysclock.date
    }
    // ---- network state (Wi-Fi native + LAN/VPN via nmcli), shared ----
    NetState {
        id: netState
    }
    // ---- screen brightness (per-display, KDE ScreenBrightness / DDC), shared ----
    Brightness {
        id: brightness
    }

    // ---- capture (screenshot + screen-record), shared. The canvas lives in the
    // full-screen captureVars window below; the pill hosts the toolbar/menu button.
    // See ../capture/PLAN.md. Driven by the IPC verbs + the row-2 capture button.
    CaptureState {
        id: capture
        onCancelled: { /* overlay hides via captureVars visibility */ }
        // no notify-send for screenshots — when the cropped PNG is on disk we raise an
        // in-pill card (same NotificationView + droplet as any notification) showing a
        // live thumbnail; clicking it opens the shot with the desktop opener.
        onShotReady: (p) => notifs.postLocal({
            appName: "Screenshot", appIcon: "image",
            summary: "Screenshot ready", body: "Copied to clipboard — click to open",
            imagePath: "file://" + p, openPath: p
        })
    }
    RecordController {
        id: capRec
        state: capture
        onFinished: (p) => root.captureNotify("Recording saved", p)
        // a gpsr run that dies immediately (portal denied / no encoder / stale
        // restore token) surfaces here instead of a phantom "saved" toast
        onFailed: (why) => root.captureNotify("Recording failed", why || "gpu-screen-recorder could not start")
    }
    // a resettable close after a screenshot copy/save lands
    Timer { id: captureReset; interval: 250; onTriggered: capture.reset() }
    Connections {
        target: capture
        function onCopied() { captureReset.restart(); }
        function onSaved(p) { captureReset.restart(); }
    }
    // best-effort desktop note when a file lands (uses our own notification server)
    function captureNotify(summary, path) {
        captureNotifyProc.command = ["notify-send", "-a", "Capture", "-i", "camera-photo", summary, path];
        captureNotifyProc.running = true;
    }
    Process { id: captureNotifyProc }

    // ---- KWin virtual desktops over DBus (org.kde.KWin /VirtualDesktopManager) ----
    Process {
        id: fetchDesktops
        running: true
        command: ["gdbus", "call", "--session", "--dest", "org.kde.KWin",
            "--object-path", "/VirtualDesktopManager", "--method",
            "org.freedesktop.DBus.Properties.Get",
            "org.kde.KWin.VirtualDesktopManager", "desktops"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                const re = /\(\s*(?:uint32\s+)?\d+\s*,\s*'([^']*)'\s*,\s*'([^']*)'\s*\)/g;
                let m;
                while ((m = re.exec(this.text)) !== null) {
                    out.push({ id: m[1], name: m[2] });
                }
                root.desktops = out;
            }
        }
    }
    Process {
        running: true
        command: ["gdbus", "call", "--session", "--dest", "org.kde.KWin",
            "--object-path", "/VirtualDesktopManager", "--method",
            "org.freedesktop.DBus.Properties.Get",
            "org.kde.KWin.VirtualDesktopManager", "current"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = this.text.match(/'([^']*)'/);
                if (m) {
                    root.currentDesktop = m[1];
                }
            }
        }
    }
    Process {
        running: true
        command: ["gdbus", "monitor", "--session", "--dest", "org.kde.KWin",
            "--object-path", "/VirtualDesktopManager"]
        stdout: SplitParser {
            onRead: line => {
                if (line.indexOf("currentChanged") !== -1) {
                    const m = line.match(/'([^']*)'/); if (m) root.currentDesktop = m[1];
                } else if (line.indexOf("desktopCreated") !== -1 || line.indexOf("desktopRemoved") !== -1) {
                    fetchDesktops.running = true;
                }
            }
        }
    }
    function switchDesktop(id) {
        switchProc.command = ["gdbus", "call", "--session", "--dest", "org.kde.KWin",
            "--object-path", "/VirtualDesktopManager", "--method",
            "org.freedesktop.DBus.Properties.Set",
            "org.kde.KWin.VirtualDesktopManager", "current", "<'" + id + "'>"];
        switchProc.running = true;
    }
    Process { id: switchProc }
    
    // ---- keyboard layout (org.kde.keyboard /Layouts) for the language burst ----
    // getLayoutsList -> a(sss) = (code, customLabel, longName); show the custom
    // label if the user set one in System Settings, else the uppercased code
    // (us -> US, ir -> IR). getLayout -> the current index into that list;
    // layoutChanged(u)/layoutListChanged() keep both live.
    property var kbLayouts: []        // short labels, one per layout index
    property int kbIndex: 0
    Process {
        id: fetchLayouts
        running: true
        command: ["gdbus", "call", "--session", "--dest", "org.kde.keyboard",
            "--object-path", "/Layouts", "--method",
            "org.kde.KeyboardLayouts.getLayoutsList"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                const re = /\(\s*'([^']*)'\s*,\s*'([^']*)'\s*,\s*'([^']*)'\s*\)/g;
                let m;
                while ((m = re.exec(this.text)) !== null)
                    out.push(m[2] !== "" ? m[2] : m[1].toUpperCase());
                root.kbLayouts = out;
            }
        }
    }
    Process {
        running: true
        command: ["gdbus", "call", "--session", "--dest", "org.kde.keyboard",
            "--object-path", "/Layouts", "--method",
            "org.kde.KeyboardLayouts.getLayout"]
        stdout: StdioCollector {
            // gdbus prints the index as "(uint32 N,)" — match the digits *after*
            // "uint32", else a bare /\d+/ grabs the "32" inside "uint32".
            // Also seed prevKbIndex: kbIndex defaults to 0, so if the fetched value
            // is also 0 the change handler never fires to consume the initial value
            // — without this the first *real* switch would be swallowed.
            onStreamFinished: {
                const m = this.text.match(/uint32\s+(\d+)/);
                if (m) { root.kbIndex = parseInt(m[1]); if (root.prevKbIndex === -1) root.prevKbIndex = root.kbIndex; }
            }
        }
    }
    Process {
        running: true
        command: ["gdbus", "monitor", "--session", "--dest", "org.kde.keyboard",
            "--object-path", "/Layouts"]
        stdout: SplitParser {
            onRead: line => {
                if (line.indexOf("layoutChanged") !== -1) {
                    // signal payload prints as "(uint32 N,)" — match after "uint32"
                    const m = line.match(/uint32\s+(\d+)/);
                    if (m) root.kbIndex = parseInt(m[1]);
                } else if (line.indexOf("layoutListChanged") !== -1) {
                    fetchLayouts.running = true;
                }
            }
        }
    }
    
    // ---- transient action bursts (desktop switch / layout change) ----
    // A 1s overlay that briefly takes over the resting pill to show what just
    // changed, then reverts: phase 1 settle (100ms) -> phase 2 animate (300ms)
    // -> phase 3 settle (600ms) -> done. Driven from root so every monitor's
    // pill shows it; the pill suppresses notifMorph while bursting and floats
    // the notification deck below instead (so notifications slide down). Both kinds
    // can be live at once (a desktop switch + a layout change within the same
    // window) — then *two* pills show side by side and pop apart on entry.
    property bool   burstDesk: false
    property bool   burstLang: false
    property bool   burstLevel: false        // volume / brightness level burst
    readonly property bool burstActive: burstDesk || burstLang || burstLevel
    // one row per live burst, NEWEST FIRST (index 0 = top of the column). A ListModel
    // (not a rebuilt array) so inserting a new burst at the top animates the existing
    // rows *rolling down* rather than recreating every delegate. burstAdd() puts the
    // kind at the top (or lifts it there if it's already showing).
    ListModel { id: burstModel }
    function burstAdd(kind) {
        for (let i = 0; i < burstModel.count; i++) {
            if (burstModel.get(i).kind === kind) {
                if (i !== 0) burstModel.move(i, 0, 1);
                return;
            }
        }
        burstModel.insert(0, { kind: kind });
    }
    property int    burstPhase: 0      // 0 idle, 1 pre, 2 animate, 3 post
    property string burstFromDesktop: ""
    property string burstToDesktop: ""
    property string burstFromLabel: ""
    property string burstToLabel: ""
    // level burst payload (volume / brightness): glyph + title + from->to fill
    property string burstLevelIcon: ""
    property string burstLevelTitle: ""
    property real   burstLevelFrom: 0
    property real   burstLevelTo: 0
    // index of the active desktop (also drives the sliding dot in the hovered Row 1)
    readonly property int deskActiveIdx: desktops.findIndex(d => d.id === currentDesktop)
    readonly property int burstFromIdx: desktops.findIndex(d => d.id === burstFromDesktop)
    readonly property int burstToIdx:   desktops.findIndex(d => d.id === burstToDesktop)
    // index of the moving active dot: the new slot once we start animating
    readonly property int burstDotIdx: burstPhase >= 2 ? Math.max(0, burstToIdx)
                                                       : Math.max(0, burstFromIdx)
    function startBurst(kind) {
        if (kind === "desktops") burstDesk = true;
        else if (kind === "language") burstLang = true;
        else if (kind === "level") burstLevel = true;
        burstAdd(kind);                // add / lift the row to the top of the column
        burstPhase = 1;                // (re)start the shared timeline from the top
        burstTimer.restart();
    }
    // fire a volume/brightness level burst: glyph + title over a bar that animates
    // from `from` to `to` (both ratios in [0,1]). Reused by the volume IPC handlers
    // and the brightness step below.
    function startLevelBurst(icon, title, from, to) {
        burstLevelIcon = icon;
        burstLevelTitle = title;
        burstLevelFrom = Math.max(0, Math.min(1, from));
        burstLevelTo = Math.max(0, Math.min(1, to));
        startBurst("level");
    }
    Timer {
        id: burstTimer
        interval: root.burstPhase === 1 ? 100 : root.burstPhase === 2 ? 300 : 600
        repeat: false
        onTriggered: {
            if (root.burstPhase < 3) { root.burstPhase++; burstTimer.restart(); }
            else { root.burstPhase = 0; root.burstDesk = false; root.burstLang = false; root.burstLevel = false; burstModel.clear(); }
        }
    }
    // fire the bursts on a *real* change (skip the initial value on startup; QML
    // change handlers don't carry the old value, so we keep the previous one).
    property string prevDesktop: ""
    property int    prevKbIndex: -1
    onCurrentDesktopChanged: {
        if (prevDesktop === "") { prevDesktop = currentDesktop; return; }
        if (currentDesktop === prevDesktop || currentDesktop === "") return;
        burstFromDesktop = prevDesktop;
        burstToDesktop = currentDesktop;
        prevDesktop = currentDesktop;
        startBurst("desktops");
    }
    onKbIndexChanged: {
        if (prevKbIndex === -1) { prevKbIndex = kbIndex; return; }
        if (kbIndex === prevKbIndex) return;
        burstFromLabel = prevKbIndex < kbLayouts.length ? kbLayouts[prevKbIndex] : "";
        burstToLabel = kbIndex < kbLayouts.length ? kbLayouts[kbIndex] : "";
        prevKbIndex = kbIndex;
        startBurst("language");
    }
    
    // ---- voice recording -> whisper transcription (VoiceRecorderPill) ----
    // idle -> recording -> transcribing -> idle. Root-owned: one recording, one
    // pw-record, one bridge — every monitor's pill just renders it (voiceMorph).
    property string voiceState: "idle"     // "idle" | "recording" | "transcribing"
    readonly property bool voiceActive: voiceState !== "idle"
    // per-memo config, set before a take begins: voiceToggle -> a quick raw note;
    // voicePolishToggle -> the VoiceMemoMenu (type + polish/org switches) sets these.
    property string voiceMemoType: "note"  // meeting | task | prompt | note
    property bool voicePolishEnabled: false
    property bool voiceOrgEnabled: false
    property string voiceOrgCategory: "note" // todo | note (for the org-agenda entry)
    property string voiceWavPath: ""
    // requested by voicePolishToggle when idle — a window opens the config menu (7)
    signal voiceMemoRequested()
    property bool voiceDiscard: false      // cancel: exit handlers clean up, no chaining
    property bool voicePendingStart: false // waiting for the rnnoise node before pw-record
    property bool voiceBridgeReported: false // bridge printed its JSON (it notifies itself)
    property int  voiceSeconds: 0          // elapsed take time (VoiceRecorderPill's clock)
    readonly property Timer voiceTick: Timer {
        interval: 1000; repeat: true
        running: root.voiceState === "recording"
        onTriggered: root.voiceSeconds++
    }
    
    // rnnoise readiness: the filter-chain's virtual source appears on the graph as
    // node.name "rnnoise_source" (keep in lockstep with source-rnnoise.conf). Only
    // meaningful while voicePendingStart; the fallback timer gives up after 1.5s
    // and records the raw default source instead.
    readonly property bool voiceRnnoiseUp: {
        const ns = Pipewire.nodes ? Pipewire.nodes.values : [];
        for (let i = 0; i < ns.length; i++)
            if (ns[i].name === "rnnoise_source") return true;
        return false;
    }
    onVoiceRnnoiseUpChanged: if (voiceRnnoiseUp && voicePendingStart) startVoiceRec(true)
    readonly property Timer voiceRnnoiseFallback: Timer {
        interval: 1500
        onTriggered: if (root.voicePendingStart) root.startVoiceRec(false)
    }
    
    // voiceToggle (idle): a quick raw note — no menu, no polish, no org.
    function voiceStartQuick() {
        if (voiceState !== "idle") return;
        voiceMemoType = "note";
        voicePolishEnabled = false;
        voiceOrgEnabled = false;
        voiceOrgCategory = "note";
        voiceBeginRecord();
    }
    // voicePolishToggle (idle) opens the config menu; its Start commits here.
    function voiceStartConfigured(memoType, polish, org, orgCategory) {
        if (voiceState !== "idle") return;
        voiceMemoType = memoType;
        voicePolishEnabled = polish;
        voiceOrgEnabled = org;
        voiceOrgCategory = orgCategory;
        voiceBeginRecord();
    }
    function voiceBeginRecord() {
        voiceDiscard = false;
        voiceBridgeReported = false;
        voiceSeconds = 0;
        voiceWavPath = "/tmp/pill-voice-" + Date.now() + ".wav";
        voiceState = "recording";              // UI flips immediately
        if (settings.voiceNoiseSuppress) {
            voicePendingStart = true;
            voiceRnnoiseProc.running = true;   // pipewire -c source-rnnoise.conf
            voiceRnnoiseFallback.restart();
        } else {
            startVoiceRec(false);
        }
    }
    function startVoiceRec(useRnnoise) {
        voicePendingStart = false;
        voiceRnnoiseFallback.stop();
        const cmd = ["pw-record", "--rate", "16000", "--channels", "1", "--format", "s16"];
        if (useRnnoise) { cmd.push("--target"); cmd.push("rnnoise_source"); }
        cmd.push(voiceWavPath);
        voiceRecProc.command = cmd;
        voiceRecProc.running = true;
    }
    function voiceStop() {
        if (voiceState !== "recording") return;
        voiceState = "transcribing";
        // SIGTERM lets pw-record finalize the wav header; onExited chains the bridge.
        if (voiceRecProc.running) voiceRecProc.signal(15);
        else { voiceDiscard = true; voiceCleanup(); }   // stopped before pw-record spawned
    }
    function voiceCancel() {
        voiceDiscard = true;
        if (voiceRecProc.running) voiceRecProc.signal(15);
        else if (voiceTranscribeProc.running) voiceTranscribeProc.signal(15);
        else voiceCleanup();                            // pending-rnnoise edge
    }
    function voiceCleanup() {
        voicePendingStart = false;
        voiceRnnoiseFallback.stop();
        voiceRnnoiseProc.running = false;
        if (voiceDiscard && voiceWavPath !== "")
            Quickshell.execDetached(["rm", "-f", voiceWavPath]);
        voiceWavPath = "";
        voiceState = "idle";
    }
    
    Process {
        id: voiceRecProc
        onExited: {
            voiceRnnoiseProc.running = false;           // wav closed — suppression done
            if (root.voiceDiscard) { root.voiceCleanup(); return; }
            if (root.voiceState === "transcribing") {
                // stop requested: hand the wav to the bridge (venv python — the
                // system python has neither faster-whisper nor the anthropic SDK).
                voiceTranscribeProc.command = [
                    Quickshell.env("HOME") + "/.local/share/pill-transcribe/venv/bin/python",
                    Quickshell.shellPath("voicebridge.py"),
                    root.voiceWavPath, root.voicePolishEnabled ? "polish" : "raw",
                    settings.whisperModel, settings.whisperLanguage, settings.whisperDevice,
                    settings.voiceVad ? "vad" : "novad",
                    settings.claudeModel, settings.localModel,
                    root.voiceMemoType,
                    root.voiceOrgEnabled ? "org" : "noorg",
                    root.voiceOrgCategory];
                voiceTranscribeProc.running = true;
            } else {
                // pw-record died mid-take (unplugged mic, pipewire hiccup)
                Quickshell.execDetached(["notify-send", "-a", "Transcribe", "-u", "critical",
                    "-i", Quickshell.shellPath("transcribe.svg"),
                    "Recording failed", "pw-record exited unexpectedly"]);
                root.voiceDiscard = true;
                root.voiceCleanup();
            }
        }
    }
    // the RNNoise filter-chain — alive only while a suppressed take records
    Process {
        id: voiceRnnoiseProc
        command: ["pipewire", "-c", Quickshell.shellPath("source-rnnoise.conf")]
    }
    Process {
        id: voiceTranscribeProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.voiceDiscard) return;          // cancelled mid-transcribe
                try {
                    const r = JSON.parse(this.text);
                    if (r && r.mode !== undefined) root.voiceBridgeReported = true;
                } catch (e) {}
            }
        }
        onExited: {
            // the bridge notifies for itself (success AND failure); only report here
            // when it died without printing its JSON — venv missing, python gone.
            if (!root.voiceDiscard && !root.voiceBridgeReported)
                Quickshell.execDetached(["notify-send", "-a", "Transcribe", "-u", "critical",
                    "-i", Quickshell.shellPath("transcribe.svg"),
                    "Transcription failed",
                    "voicebridge did not run — is the venv set up? (run setup-transcribe.sh)"]);
            root.voiceDiscard = true;                   // bridge already deleted the wav; rm -f is harmless
            root.voiceCleanup();
        }
    }
    
    // ---- open windows (taskbar) + active window via winbridge.py ----
    // (KRunner windows runner for the list + a tiny KWin script for the active
    //  window — see winbridge.py. Emits one JSON line per update.)
    Process {
        running: true
        command: ["python", Quickshell.shellPath("winbridge.py")]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const d = JSON.parse(line);
                    if (d.event === "launcher") { root.launcherShortcut(d.screen || ""); return; }
                    // winbridge re-emits every second; only replace `windows` (which
                    // rebuilds the taskbar tiles) when it actually changed, so the
                    // shared hover square doesn't flicker while pointing at a tile.
                    const wj = JSON.stringify(d.windows);
                    if (wj !== root._winJson) { root._winJson = wj; root.windows = d.windows; }
                    root.activeWindow = d.active;
                    root.activeScreen = d.screen || "";
                    root.activeFullscreen = !!d.fullscreen;
                } catch (e) {}
            }
        }
    }
    function activateWindow(id) {
        runProc.command = ["gdbus", "call", "--session", "--dest", "org.kde.KWin",
            "--object-path", "/WindowsRunner", "--method", "org.kde.krunner1.Run", id, ""];
        runProc.running = true;
    }
    Process { id: runProc }
    // re-focus the window that was active before the pill grabbed the keyboard
    // (called when the pill is dismissed without launching anything).
    function restoreFocus() {
        const u = root.lastActiveWindow;
        if (!u) return;
        const w = root.windows.find(x => x.uuid === u);
        if (w) root.activateWindow(w.id);
    }
    Process { id: launchProc }
    function launch(execString) { launchProc.command = ["sh", "-c", execString]; launchProc.startDetached(); }
    // run a pre-split argv detached (no shell) — safe for paths/args with spaces.
    function launchArgs(argv) { launchProc.command = argv; launchProc.startDetached(); }
    
    // KWin window actions for the taskbar right-click menu. winbridge.py owns the
    // org.kde.pill service and turns this into a one-shot KWin script that finds the
    // windows in `uuids` by internalId and applies `verb`: minimize|maximize|above|
    // below|close toggle the aggregate state; desktop:<id> / desktop:all move them.
    // The menu passes either the whole group's uuids (whole-app actions) or one
    // window's uuid (a per-window submenu). No-op if KWin/winbridge is absent.
    Process { id: actionProc }
    function windowAction(uuids, verb) {
        if (!uuids || !uuids.length) return;
        actionProc.command = ["gdbus", "call", "--session", "--dest", "org.kde.pill",
            "--object-path", "/Active", "--method", "org.kde.pill.Action",
            JSON.stringify(uuids), verb];
        actionProc.running = true;
    }
    
    // best DesktopEntry for a window: try its desktopFileName, then resourceClass,
    // then the KRunner icon name (heuristicLookup is fuzzy). Used to group windows of
    // one app together and to resolve a real icon — the bare KRunner icon name often
    // isn't a themed icon, which is why some tiles fell back to the generic glyph.
    function winEntry(w) {
        const cands = [w.dfile, w.cls, w.icon];
        for (const c of cands) {
            if (!c || !c.length) continue;
            const e = DesktopEntries.heuristicLookup(String(c).replace(/\.desktop$/i, ""));
            if (e) return e;
        }
        return null;
    }
    // session-only (non-persisted) order for the *unpinned* taskbar tiles: a list of
    // their keys ("win:"+class). Dragging an open, unpinned app in the taskbar sets a
    // temporary order here; it resets on restart. Pinned order lives in settings.pinned.
    property var unpinnedOrder: []
    
    // the taskbar model: pinned apps first (in settings.pinned order, whether or not
    // they're running), then the remaining open apps (unpinned). Open windows are
    // grouped by app class; a pinned app that's also open merges its windows into its
    // pinned tile. Each tile: { key, icon, entry, wins, desks, onAll, pinned }. A
    // pinned-but-unopened tile has wins: [] (clicking it launches the app).
    readonly property var appGroups: {
        // ---- 1. group open windows by app class, in open order ----
        // `windows` already arrives in open order (winbridge sorts by seq), so the
        // first-seen group order is open order — keep it.
        const g = {}, order = [];
        for (const w of windows) {
            const key = (w.cls && w.cls.length) ? w.cls.toLowerCase()
                      : (w.icon && w.icon.length) ? w.icon.toLowerCase() : w.uuid;
            if (!g[key]) {
                const e = root.winEntry(w);
                // icon: prefer the resolved entry's icon, else the KRunner name, else
                // the class / desktop file. `entry` is reused by the context menu.
                g[key] = {
                    classKey: key,
                    icon: (e && e.icon) ? e.icon : (w.icon || w.cls || w.dfile || ""),
                    entry: e,
                    wins: []
                };
                order.push(key);
            }
            g[key].wins.push(w);
        }
        // per-group virtual-desktop occupancy (for the right-click Move-to-Desktop
        // marker): `desks` = the unique desktop ids the group's windows sit on,
        // `onAll` = any window is on all desktops. `desk` per window comes from
        // winbridge (the KWin script).
        const byEntryId = {};
        for (const k of order) {
            const grp = g[k];
            const desks = [];
            let onAll = false;
            for (const w of grp.wins) {
                if (w.desk === "all") onAll = true;
                else if (w.desk && desks.indexOf(w.desk) < 0) desks.push(w.desk);
            }
            grp.desks = desks;
            grp.onAll = onAll;
            if (grp.entry && grp.entry.id) byEntryId[grp.entry.id] = grp;   // for pin merging
        }
        // ---- 2. pinned tiles first (settings.pinned order) ----
        const appById = {};
        for (const a of appList) appById[a.id] = a;
        const tiles = [], usedClass = {};
        for (const id of (settings.pinned || [])) {
            const entry = appById[id];
            if (!entry) continue;                          // pinned app no longer installed
            const og = byEntryId[id];                      // its open windows, if running
            if (og) usedClass[og.classKey] = true;         // don't list it again as unpinned
            tiles.push({
                key: "pin:" + id,
                appId: id,                                 // plain id → re-resolve to launch
                icon: entry.icon ? entry.icon : (og ? og.icon : ""),
                entry: entry,
                wins: og ? og.wins : [],
                desks: og ? og.desks : [],
                onAll: og ? og.onAll : false,
                pinned: true
            });
        }
        // ---- 3. remaining open apps (unpinned), in the temporary order else open order ----
        const unpinned = order.filter(k => !usedClass[k]).map(k => {
            const grp = g[k];
            return { key: "win:" + k, appId: (grp.entry && grp.entry.id) ? grp.entry.id : "",
                     icon: grp.icon, entry: grp.entry, wins: grp.wins,
                     desks: grp.desks, onAll: grp.onAll, pinned: false };
        });
        const ord = root.unpinnedOrder || [];
        unpinned.sort((a, b) => {                           // stable: unknown keys keep open order
            const ia = ord.indexOf(a.key), ib = ord.indexOf(b.key);
            if (ia < 0 && ib < 0) return 0;
            if (ia < 0) return 1;
            if (ib < 0) return -1;
            return ia - ib;
        });
        return tiles.concat(unpinned);
    }
    // (Taskbar computes per-group "active" itself from `activeWindow`.)
    function cycleGroup(grp) {
        const i = grp.wins.findIndex(w => w.uuid === root.activeWindow);
        root.activateWindow(grp.wins[i >= 0 ? (i + 1) % grp.wins.length : 0].id);
    }
    // left-click a taskbar tile: cycle its windows if running, else launch the app
    // (a pinned-but-unopened tile behaves like clicking the app in the launcher). We
    // re-resolve a *live* DesktopEntry from appList by id (the entry nested in the tile
    // object doesn't survive the model/signal round-trip, but the id string does), then
    // launch it by running its Exec line detached via the shell — DesktopEntry.execute()
    // proved unreliable from the dashboard, whereas root.launch (used by the context
    // menu's launcher actions) works. Field codes (%U/%F/%i/…) are stripped first.
    function taskbarActivate(grp) {
        if (grp.wins && grp.wins.length > 0) { root.cycleGroup(grp); return; }
        const e = grp.appId ? root.appList.find(a => a.id === grp.appId) : null;
        if (!e) return;
        // prefer the parsed argv (`command`, field codes already handled by Quickshell),
        // run detached without a shell; strip any stray "%x" field-code args just in case.
        if (e.command && e.command.length) {
            root.launchArgs(e.command.filter(a => a && a.charAt(0) !== "%"));
        } else if (e.execString) {
            root.launch(e.execString.replace(/%[a-zA-Z]/g, " ").replace(/\s+/g, " ").trim());
        } else if (e.execute) {
            e.execute();                        // last resort
        }
    }
    // commit a taskbar drag: `keys` is the new full tile order. Split it back into the
    // persisted pinned order (entry ids) and the temporary unpinned order (keys).
    function taskbarReorder(keys) {
        const byKey = {};
        for (const gr of root.appGroups) byKey[gr.key] = gr;
        const pins = [], unpins = [];
        for (const k of keys) {
            const gr = byKey[k];
            if (!gr) continue;
            if (gr.pinned && gr.entry) pins.push(gr.entry.id);
            else if (!gr.pinned) unpins.push(k);
        }
        settings.pinned = pins;
        root.unpinnedOrder = unpins;
    }
    // taskbar pin state + toggle (pinning is only offered from the app menus).
    function isPinned(a) { return a ? (settings.pinned || []).indexOf(a.id) >= 0 : false; }
    function togglePin(a) {
        if (!a) return;
        const f = (settings.pinned || []).slice();
        const i = f.indexOf(a.id);
        if (i >= 0) f.splice(i, 1); else f.push(a.id);
        settings.pinned = f;
    }
    
    // ---- launcher app list ----
    // Built once here (the long-lived root) and shared with every monitor's
    // Launcher, so it survives open/close and is computed in the background at
    // startup rather than on first open. Reactive to DesktopEntries, so it
    // auto-updates when apps are installed or removed.
    readonly property var appList: {
        const src = DesktopEntries.applications ? DesktopEntries.applications.values : [];
        const a = src.filter(e => e && !e.noDisplay);
        a.sort((x, y) => x.name.localeCompare(y.name));
        return a;
    }
    
    // ---- persisted launcher settings (grid mode + favourite app ids) ----
    // Stored as JSON in the shell's state dir; survives restarts. The adapter is
    // shared with every monitor's Launcher, which mutates it directly; writes are
    // flushed automatically on any change (onAdapterUpdated -> writeAdapter).
    FileView {
        id: settingsFile
        path: Quickshell.stateDir + "/launcher.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) writeAdapter(); }
        JsonAdapter {
            id: settings
            property bool grid: false
            property var favorites: []      // [DesktopEntry.id] — launcher favourites
            property var pinned: []         // [DesktopEntry.id] — taskbar pins, in order
            property var tetris: ({})        // saved Tetris game (board/piece/queue/score) — see TetrisMenu
            property var blockBlast: ({})    // saved Block Blast game (board/tray/score/combo) — see BlockBlastMenu
            property var brickBreaker: ({})  // saved Brick Breaker game (grid/round/balls/launchX/best) — see BrickBreakerMenu
            property var snake: ({})         // saved Snake game (body/dir/apple/score/best) — see SnakeMenu
            // ---- optional features (configured from the launcher's Settings page) ----
            // Both ship OFF so a fresh checkout works without an org/hledger setup;
            // enabling them in Settings persists here and points the bridges at a
            // user-chosen directory (nothing is hard-coded anymore).
            property bool orgAgendaEnabled: false      // show org agenda in calendar + agenda popup
            property string orgAgendaDir: ""           // dir of .org files (org-agenda-files override)
            property bool financeEnabled: false        // enable the hledger finance menu + nag
            property string financeDir: ""             // the hledger finance repo (BASE_DIR override)
            // ---- finance (see FinanceState) ----
            property bool financePrivacy: false        // manual privacy choice (masks amounts)
            property string financeNagDismissedUntil: "" // ISO timestamp; "" = not dismissed
            property string financeNagNotifiedOn: ""   // "YYYY-MM-DD" the 23:00 one-shot fired
            // ---- voice transcription (the volume menu's Transcribe tab) ----
            property string whisperModel: "small"     // tiny/base/small/medium/large-v3-turbo
            property string whisperLanguage: "auto"   // auto | ISO code (en, fa, …)
            property string whisperDevice: "auto"     // auto | cuda | cpu
            property bool voiceNoiseSuppress: false   // record through the RNNoise filter chain
            property bool voiceVad: true              // whisper's built-in voice-activity filter
            property string claudeModel: "claude-opus-4-8"  // polish model: a claude-* id, or "local"
            property string localModel: "qwen2.5:3b"  // ollama model used when claudeModel === "local"
        }
    }

    // ---- persisted theme overrides (Settings → Appearance) -------------------
    // Lives in the LIVE pill config dir (~/.config/quickshell/pill/theme.json), NOT
    // in the repo — so `deploy.sh` (which only copies repo files) never clobbers it.
    // The path is resolved from XDG_CONFIG_HOME directly rather than shellPath() so
    // it always points at the installed pill dir, even when the config is loaded by
    // path during check.sh. No auto-create on FileNotFound: the file only appears
    // once the user actually customises a colour, so a headless check writes nothing.
    // `colors` is a { "<paletteKey>": "<css colour>" } map; Theme binds it as its
    // `overrides`, and the Appearance page rewrites it whole (reassign, not mutate,
    // so the JsonAdapter flushes and every Theme binding re-evaluates).
    FileView {
        id: themeFile
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config"))
              + "/quickshell/pill/theme.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        JsonAdapter {
            id: themeAdapter
            property var colors: ({})   // paletteKey → css colour string (blank = default)
        }
    }
    // ---- one full-screen overlay window per monitor ----
    Variants {
        model: Quickshell.screens
    
        PanelWindow {
            id: win
    
            required property var modelData
            property bool open: false
            property bool launcher: false // app launcher (wider open state)
            property var ctxGroup: null // app group whose right-click menu is shown
            property var trayItem: null // SystemTrayItem whose DBus menu is shown in-pill
            // "ctx mode": an in-pill right-click menu is up (either the taskbar app
            // menu or a system-tray item menu). Both reuse the same pill machinery —
            // dashboard rows fade out, the pill sizes to the menu loader, the mask and
            // backdrop go full-screen — so mode/size/fade bindings key off this, while
            // each menu's own Loader keys off its specific state (ctxGroup / trayItem).
            readonly property bool ctxMode: ctxGroup !== null || trayItem !== null
            // "focus mode": clicking the collapsed pill reveals the dashboard and holds
            // it (no hover reveal); it stays until a click elsewhere (backdrop) moves
            // focus away. Set true by the collapsed-pill click, cleared by the backdrop.
            property bool focused: false
            // "keyboard-nav mode": entered via the `expand` IPC. The pill grabs the
            // keyboard for the whole stay: arrows move the dashboard focus square
            // (win.hoverItem — hover and keyboard share it, so mousing over anything
            // re-focuses it), Enter clicks, f/c/n/w/v/b jump straight to a menu, and
            // Escape steps back (menu -> dashboard -> closed). Menus opened while in
            // this mode run MenuKbNav; closing them returns to the dashboard instead
            // of dismissing the pill. Cleared automatically when the pill fully
            // closes (dash false), so mouse-opened pills keep the hands-off focus
            // policy.
            property bool kbNav: false
            // the floating org-deadlines list is up (right-click the resting pill or
            // click its deadline under-line). NOT part of `dash`: the pill stays a
            // collapsed clock while the panel floats below it (see AgendaMenu).
            property bool deadlines: false
            // the org agenda / deadline signals hide under the finance privacy toggle
            // (the launcher eye), so the resting-pill under-line and the deadlines popup
            // go dark alongside the finance + calendar sections it already gates.
            readonly property bool orgHidden: finance.privacy
            onOrgHiddenChanged: if (orgHidden) deadlines = false
            // the resting pill's under-line is present when a deadline is due/overdue
            // OR a meeting is imminent — both suppressed under the privacy toggle.
            readonly property bool restUnderline: !orgHidden
                && (orgAgenda.hasDue || calEvents.hasMeetingSoon)
            property bool dash: open || launcher || focused || ctxMode
            property int menu: 4 // 0 net, 1 vol, 2 bt, 3 batt, 5 clipboard, 6 calendar, 7 voice memo, 8 finance, 9 tetris, 10 block blast, 11 games, 12 brick breaker, 4 notif (default pane)
            // keyboard-focus gating. The pill grabs the compositor keyboard ONLY while
            // it actually needs it: the launcher, clipboard, or notification menu is up
            // (they auto-focus a field / drive arrow-key nav), or *some* editable field
            // inside the pill currently has focus (wifi password, notification reply). Otherwise it
            // stays hands-off (KeyboardFocus.None), so browsing menus/toggles never steals
            // focus from the active window — and there's nothing to "restore" on dismiss.
            // `kbProbe` (below) reports the window's current focus item; our editable
            // fields tag themselves with objectName "pillKbInput".
            readonly property bool kbInputFocused: {
                const it = kbProbe.focusItem;
                return !!it && it.objectName === "pillKbInput";
            }
            // The notification pane (menu 4) also grabs the keyboard: it drives its own
            // arrow/Enter/i/x navigation (see NotificationHistory.qml) and its inline-reply
            // field wants the keystrokes from the first press.
            readonly property bool grabsKeyboard: win.launcher || (win.open && (win.menu === 5 || win.menu === 4 || win.menu === 9 || win.menu === 12 || win.menu === 14)) || win.kbInputFocused || win.kbNav || win.deadlines
            // open-state pill geometry, in ONE place: the control panel and the
            // launcher both lay out to these, so resizing the open/launcher pill here
            // can't leave the launcher mis-sized (the bug from the last resize).
            readonly property int launcherWidth: 600
            // launcher pill width
            // the calendar menu is wider than the other panes — it puts the month grid
            // next to a selected-day / Org-agenda detail column.
            readonly property int calWidth: 760
            // the Settings pane (menu 13) runs wide + tall: the Appearance page shows
            // a preset grid + a scrolling wall of per-colour rows next to a sidebar.
            readonly property int settingsWidth: 860
            readonly property int settingsHeight: 580
            // the game panes (menu 9 Tetris, 10 Block Blast, 12 Brick Breaker) run
            // wider + taller than a normal menu so the board and its side column both
            // get room to breathe (Tetris' 10×24px well is 240px; the others fit too).
            readonly property int tetrisWidth: 480
            readonly property int tetrisHeight: 556
            // Brick Breaker (menu 12) has its own size — its 6×10 field is a square
            // 300×300 well, but the side column (stats + specials legend + rules +
            // buttons) is the taller element, so the pane is sized to fit that
            // (~side height + 64px chrome), and wider than tall (well + side column).
            readonly property int brickWidth: 576
            readonly property int brickHeight: 416
            // Snake (menu 14) reuses Brick Breaker's pane layout: a square 300×300
            // well beside a stats/rules/buttons column. The side column is shorter
            // (no specials legend), so the field is the tall element here.
            readonly property int snakeWidth: 560
            readonly property int snakeHeight: 400
            // the game panes are draggable-to-park by the same machinery — only one is
            // ever open at a time, so they share the tetris* park state below.
            readonly property bool gamePane: win.open && (win.menu === 9 || win.menu === 10 || win.menu === 12 || win.menu === 14)
            readonly property int openHeight: 470
            // open + launcher pill height
            // the clipboard-history menu runs 200px taller than the other panes so more
            // history is visible; every other open menu (and the launcher) uses openHeight.
            readonly property int openPaneHeight: (open && menu === 5) ? openHeight + 200 : (open && menu === 7) ? 440 : (open && menu === 13) ? settingsHeight : (open && menu === 12) ? brickHeight : (open && menu === 14) ? snakeHeight : (open && (menu === 9 || menu === 10)) ? tetrisHeight : openHeight
            // hovered dashboard geometry (its own generous, HTML-scale size — distinct
            // from the open menu's 520 so the two rows can breathe).
            readonly property int hoverWidth: 640
            readonly property int hoverHeight: 150
            // NOTE: the pill no longer morphs into the notification card — that took
            // the pill over and made it inaccessible (no clock, no dashboard hover,
            // burst UI had to appear elsewhere). Instead, at rest a water droplet
            // drops out of the pill's bottom lip and the deck floats below (see
            // `notifRest` + the "resting notification" block). `notifMorph` is kept as
            // a hard-false so the many `!notifMorph` gates below (which keep the normal
            // resting/dashboard pill enabled) all read true; its old takeover branches
            // in the pill's width/height/y are now dead.
            property bool notifMorph: false
            // a notification is showing at true rest (no panel / launcher / ctx menu /
            // voice take): the deck floats below the pill and, on arrival, a droplet
            // detaches from the pill. While clicked/launcher/ctx/voice, the deck floats
            // below via the other stack (no droplet) instead. Action bursts are
            // independent — they morph the pill in place and no longer suppress this,
            // so the resting deck stays put right through a burst.
            readonly property bool notifRest: notifs.current !== null && !open && !launcher && !ctxMode && !voiceMorph
            // a transient action burst (desktop switch / layout change) takes over
            // the *resting* pill for 1s; it yields to hover/open/launcher/ctx (those
            // already show richer UI). It is independent of notifications: the pill
            // morphs in place and the resting notification deck is left untouched.
            property bool showBurst: root.burstActive && !dash && !root.voiceActive
            // hide the resting pill while a fullscreen window is focused (games,
            // video, etc.) — only at true rest: hovering, opening, or a morphing
            // notification all override it, so notifications still appear normally.
            // A live camera or an active screencast keeps it visible regardless
            // (privacy indicator); a hot mic is not treated as a privacy indicator.
            // A running voice take also wins — without this the mask would go
            // emptyRegion and the recorder would render unclickable over fullscreen.
            property bool fsHide: root.activeFullscreen && !dash && !notifRest && !root.privacyActive && !root.voiceActive
            // resting pill with a live camera/recording: solid (no idle translucency),
            // clock paired with the privacy icon(s).
            property bool privacyRest: root.privacyActive && !dash && !notifMorph && !showBurst && !root.voiceActive
            // ---- voice recorder owns the resting pill (all monitors) ----
            // While a voice take records/transcribes, the resting pill becomes the
            // VoiceRecorderPill (larger, 220x36). It beats the notification morph,
            // bursts and fsHide (gates above) but still yields to an open panel /
            // launcher / ctx menu — the take keeps running underneath; the recorder
            // face returns when the panel closes. Starting a take also clears
            // `focused` (Connections below) so the dashboard can't sit over it.
            // the capture morph is a self-contained menu mode: it suppresses the
            // voice-recorder face too (the take keeps running underneath, like it
            // does for open/launcher/ctx) so nothing but the capture controls shows.
            readonly property bool voiceMorph: root.voiceActive && !dash && !capShow
            // capture "control" morph: the pill becomes the screenshot toolbar
            // (annotating) or the record settings (recConfig). The fullscreen canvas
            // (region/annotations/webcam) is a separate window; this is just the
            // controls, sized to captureLoader. Recording/grabbing/selecting keep the
            // pill normal (no timer while recording).
            readonly property bool capCtl: capture.mode === "annotating" || capture.mode === "recConfig"
            // the capture button opens a small chooser first (screenshot vs record,
            // or stop while recording) — like opening a status menu, not a direct fire.
            property bool capMenu: false
            // the pill shows capture UI (chooser OR controls); drives the morph gates.
            readonly property bool capShow: capCtl || capMenu

            // ---- movable capture pill (so the controls never block the shot) ----
            // The capture controls can leave their top-centre home two ways:
            //   • MANUAL drag (capManual): grab the pill and drop it. Near the top edge
            //     it re-attaches with wings at the drop x; elsewhere it floats fully
            //     rounded. Overrides auto-avoid for the rest of the session.
            //   • AUTO-avoid (capAutoAvoid): while a crop / record region is set, the
            //     pill slides to the first screen slot that doesn't cover it.
            // `capPositioned` = "not at the default top-centre"; `capAttached` = docked
            // to the top edge (wings) vs floating (no wings, fully rounded). Everything
            // resets when the capture ends.
            property bool capPositioned: false
            property bool capManual: false
            property bool capAttached: true
            property bool capDragging: false
            property real capPosX: 0
            property real capPosY: 0
            readonly property int capSnapY: 44        // drop within this of the top → dock
            // whether the pill is currently floating (rounded, no wings)
            readonly property bool capFloating: capDragging || (capShow && capPositioned && !capAttached)
            // the open game panes (menu 9 / 10) are draggable-to-park like the capture
            // pill — but only by the little grip beside the title (the pane body no
            // longer drags). Free-float, clamped on-screen, no snap; resets to centre
            // when the pane closes (see onOpenChanged). Only these props feed the pill
            // position while a game is the active menu. `_gameGrabOX/OY` hold the
            // pointer-to-pill offset captured when a grip-drag begins.
            property bool tetrisMoved: false
            property bool tetrisDragging: false
            property real tetrisPosX: 0
            property real tetrisPosY: 0
            property real _gameGrabOX: 0
            property real _gameGrabOY: 0

            // ---- movable idle pill ----
            // The resting pill can be dragged anywhere on screen (X and Y). This is a
            // convenience while working — park the pill wherever, still know where to
            // look. The spot is per-session only (never persisted; each launch starts
            // top-centre) and applies ONLY while the pill is idle/collapsed. Expanding
            // it (dashboard / menu / launcher / capture) snaps it back to the top-centre
            // home so panels always open from the same place; collapsing restores the
            // dragged spot. Attached elements (notifications, action burst, agenda
            // popup) all read pill.x/pill.y, so they follow the pill and drop below it.
            // Like the capture pill: dropped near the top edge it re-attaches (flush,
            // y=0, with wings at the dragged x); dropped lower it floats fully rounded.
            property bool idleMoved: false      // dragged off top-centre this session
            property bool idleDragging: false
            property bool idleAttached: true    // docked to the top edge (wings) vs floating
            property real idlePosX: 0
            property real idlePosY: 0
            property real idleCenterX: 0        // dragged spot as a CENTRE (drives pillCenterX)
            readonly property int idleSnapY: capSnapY   // drop within this of the top → dock

            // The pill's target horizontal CENTRE. Everything centres on screen except a
            // dragged idle pill (its parked centre) and a positioned capture pill (its
            // left + half width). pill.x = pillCenterX - pill.width/2, and it is THIS
            // that animates (not x): so expand grows the width symmetrically about the
            // centre while the centre glides to screen-middle — one fluid motion. Frozen
            // while either drag is live so the pill tracks the pointer 1:1.
            property real pillCenterX:
                capShow ? (capPositioned ? capPosX + pill.width / 2 : width / 2)
                : (tetrisMoved && gamePane) ? tetrisPosX + pill.width / 2
                : (idleMoved && !dash) ? idleCenterX
                : width / 2
            Behavior on pillCenterX {
                enabled: !capDragging && !idleDragging && !tetrisDragging
                NumberAnimation { duration: theme.anim; easing.type: Easing.OutCubic }
            }
            // send the pill back to its top-centre home (middle-click on the resting
            // pill). Clearing idleMoved re-points pillCenterX at screen-centre and y at
            // 0; both animate there via their Behaviors, and the wings grow back as
            // idleFloating drops — one smooth glide home.
            function idleReset() {
                win.idleMoved = false;
                win.idleAttached = true;
                win.idlePosX = 0; win.idlePosY = 0;
                win.idleCenterX = width / 2;
            }
            // idle pill floating (rounded, no wings): while dragging, or parked away
            // from the top edge. A shared `pillFloating` unions this with the capture
            // case so the surface morph reacts to either.
            readonly property bool idleFloating: idleDragging || (idleMoved && !dash && !capShow && !idleAttached)
            // a game pane (Tetris / Block Blast) parked off its top-centre home floats
            // fully rounded like the capture / idle pill — it never re-docks (no snap),
            // so any move rounds it; a fresh, un-moved pane stays edge-attached (wings).
            readonly property bool gameFloating: gamePane && tetrisMoved
            readonly property bool pillFloating: capFloating || idleFloating || gameFloating

            // Keep the controls near the selection but off it. If the default
            // top-centre home doesn't cover the selection, stay there. Otherwise hug
            // the selection: try just ABOVE it, then just BELOW (per the "go below if
            // above collides" rule), then to its right / left — each horizontally (or
            // vertically) centred on the selection and clamped on-screen. If nothing
            // clean fits (huge selection), take the least-overlapping clamped spot.
            // A manual drag or no region leaves it alone.
            function capAutoAvoid() {
                if (!win.capShow || win.capManual) return;
                const reg = capture.region;
                const hasReg = reg.width > 1 && reg.height > 1;
                const pw = pill.width, ph = pill.height;
                if (!hasReg || pw < 1 || ph < 1) {
                    win.capPositioned = false; win.capAttached = true; return;
                }
                // a full-screen selection (the fast-shot default) covers everything, so
                // there's no clear slot to dodge to — keep the top-centre home instead
                // of fleeing to the least-bad corner.
                if (reg.x <= 2 && reg.y <= 2 && reg.x + reg.width >= win.width - 2
                        && reg.y + reg.height >= win.height - 2) {
                    win.capPositioned = false; win.capAttached = true; return;
                }
                const W = win.width, H = win.height, m = 12, gap = 12;
                const rl = reg.x, rt = reg.y, rr = reg.x + reg.width, rb = reg.y + reg.height;
                const area = (x, y) => {
                    const ix = Math.min(x + pw, rr) - Math.max(x, rl);
                    const iy = Math.min(y + ph, rb) - Math.max(y, rt);
                    return Math.max(0, ix) * Math.max(0, iy);
                };
                const homeX = (W - pw) / 2;
                if (area(homeX, 0) === 0) {          // top-centre home is already clear
                    win.capPositioned = false; win.capAttached = true; return;
                }
                // hug the selection, centred on it, clamped on-screen
                const cxx = Math.max(m, Math.min(rl + reg.width / 2 - pw / 2, W - pw - m));
                const cyy = Math.max(m, Math.min(rt + reg.height / 2 - ph / 2, H - ph - m));
                const above = { x: cxx, y: rt - gap - ph };
                const below = { x: cxx, y: rb + gap };
                const right = { x: rr + gap, y: cyy };
                const left  = { x: rl - gap - pw, y: cyy };
                const fits = (c) => c.x >= m && c.y >= m && c.x + pw <= W - m
                                 && c.y + ph <= H - m && area(c.x, c.y) === 0;
                let best = null;
                for (const c of [above, below, right, left]) if (fits(c)) { best = c; break; }
                if (!best) {                          // nothing clean fits — least overlap, clamped
                    let bo = Infinity;
                    for (const c of [below, above, right, left, { x: homeX, y: 0 }]) {
                        const x = Math.max(m, Math.min(c.x, W - pw - m));
                        const y = Math.max(m, Math.min(c.y, H - ph - m));
                        const o = area(x, y);
                        if (o < bo) { bo = o; best = { x: x, y: y }; }
                    }
                }
                win.capPosX = best.x; win.capPosY = best.y;
                win.capAttached = best.y <= win.capSnapY;   // near the top edge → dock with wings
                win.capPositioned = true;
            }
            // re-evaluate auto-avoid when the region, the controls' size, or the capture
            // mode changes (cheap; only acts while capShow and not manually placed).
            Connections {
                target: capture
                function onRegionChanged() { win.capAutoAvoid(); }
                function onModeChanged() { win.capAutoAvoid(); }
            }
            onCapShowChanged: win.capAutoAvoid()

            // entering a capture collapses every other expanded state so the pill
            // shows ONLY the capture controls (never the dashboard/menu underneath);
            // leaving it resets the movable-pill position back to the top-centre home.
            Connections {
                target: capture
                function onActiveChanged() {
                    if (!capture.active) {
                        win.capPositioned = false; win.capManual = false;
                        win.capAttached = true; win.capDragging = false;
                        win.capPosX = 0; win.capPosY = 0;
                        return;
                    }
                    win.open = false; win.launcher = false; win.focused = false;
                    win.kbNav = false; win.deadlines = false;
                    win.ctxGroup = null; win.trayItem = null; win.capMenu = false;
                }
            }
            // ---- shared hover indicator ----
            // One rounded faded square (drawn once, below the rows) jumps to whatever
            // dashboard item — app tile, launcher, status icon, tray icon — the pointer
            // is over, instead of every item drawing its own highlight. Items report
            // themselves via hoverEnter on enter only; the square *stays* on the last
            // item once the pointer leaves it (it does not snap back), and only resets
            // to the launcher icon (the default target, when `hoverItem` is null) when
            // the dashboard collapses.
            property var hoverItem: null
            // ---- full-screen power confirmation ----
            // shutdown / reboot / logout route through here instead of firing at
            // once: a full-screen page takes over until the user answers. Nothing
            // runs unless `confirm()` (the "yes" button) is pressed.
            property string confirmAction: ""
            // "shutdown"/"reboot"/"logout"; "" hidden
            property var confirmCmd: null
            property string confirmMsg: ""
            // which design the current confirmation renders ("1a".."1d"); resolved in
            // requestConfirm from theme.confirmation, so "random" re-rolls per open.
            property string confirmVariant: "1a"
            readonly property bool confirmActive: confirmAction !== ""
    
            function hoverEnter(it) {
                win.hoverItem = it;
            }
    
            function requestConfirm(action, cmd) {
                const msgs = ["Really?", "Are you serious?", "No kidding?", "No shit!", "Dayum?"];
                win.confirmMsg = msgs[Math.floor(Math.random() * msgs.length)];
                const variants = ["1a", "1b", "1c", "1d"];
                win.confirmVariant = theme.confirmation === "random" ? variants[Math.floor(Math.random() * variants.length)] : theme.confirmation;
                win.confirmCmd = cmd;
                win.confirmAction = action;
            }
    
            function confirm() {
                if (win.confirmCmd) {
                    confirmProc.command = win.confirmCmd;
                    confirmProc.startDetached();
                }
                win.confirmAction = "";
                win.confirmCmd = null;
            }
    
            function cancelConfirm() {
                win.confirmAction = "";
                win.confirmCmd = null;
            }
    
            // toggle the launcher (used by the Meta+D global shortcut). Restores
            // focus to the previously-active window when the shortcut closes it.
            function toggleLauncher() {
                if (win.launcher) {
                    win.launcher = false;
                    root.restoreFocus();
                } else {
                    win.open = false;
                    win.ctxGroup = null;
                    win.trayItem = null;
                    win.menu = 4;
                    win.launcher = true;
                }
            }
    
            // open (or toggle shut) the clipboard-history menu — bound to the IPC
            // clipboard shortcut. Mirrors toggleLauncher: re-firing while it's already
            // showing closes it and restores focus to the previously-active window.
            function openClipboard() {
                if (win.open && win.menu === 5) {
                    win.open = false;
                    root.restoreFocus();
                } else {
                    win.launcher = false;
                    win.ctxGroup = null;
                    win.trayItem = null;
                    win.menu = 5;
                    win.open = true;
                }
            }
    
            // open (or toggle shut) the notification history pane (menu 4) — bound to the
            // IPC notifications shortcut. Mirrors openClipboard: re-firing while it's up
            // closes it and restores focus. The pane grabs the keyboard (see grabsKeyboard)
            // so its arrow/Enter/i/x navigation works from the first keystroke.
            function openNotifications() {
                if (win.open && win.menu === 4) {
                    const wasGrabbing = win.grabsKeyboard;
                    win.open = false;
                    if (wasGrabbing)
                        root.restoreFocus();
    
                } else {
                    win.launcher = false;
                    win.ctxGroup = null;
                    win.trayItem = null;
                    win.menu = 4;
                    win.open = true;
                }
            }
    
            // open the voice-memo config panel (menu 7) — fired by voicePolishToggle
            // when idle. Re-firing while it's showing closes it (the shortcut also
            // stops a running take, handled in the IPC handler).
            function openVoiceMemo() {
                if (win.open && win.menu === 7) {
                    win.open = false;
                } else {
                    win.launcher = false;
                    win.ctxGroup = null;
                    win.trayItem = null;
                    win.menu = 7;
                    win.open = true;
                }
            }
    
            // open (or toggle shut) the expanded dashboard in keyboard-nav mode —
            // bound to the IPC expand shortcut. Re-firing while any keyboard-nav pill
            // is up closes everything (Escape does the same, stage by stage); firing
            // over a mouse-opened dashboard upgrades it to keyboard-nav in place.
            function openExpanded() {
                if (win.kbNav) {
                    win.open = false;
                    win.launcher = false;
                    win.ctxGroup = null;
                    win.trayItem = null;
                    win.focused = false; // dash drops -> kbNav auto-clears
                    root.restoreFocus();
                } else {
                    win.open = false;
                    win.launcher = false;
                    win.ctxGroup = null;
                    win.trayItem = null;
                    win.kbNav = true;
                    win.focused = true;
                    win.hoverItem = dateTimeBlock; // clock/calendar is the default focus
                }
            }
    
            // open (or toggle shut) the calendar pane — fired by clicking the dashboard
            // date/time. Mirrors openClipboard: re-firing while it's showing closes it.
            function openCalendar() {
                if (win.open && win.menu === 6) {
                    const wasGrabbing = win.grabsKeyboard;
                    win.open = false;
                    if (wasGrabbing)
                        root.restoreFocus();
    
                } else {
                    win.launcher = false;
                    win.ctxGroup = null;
                    win.trayItem = null;
                    win.menu = 6;
                    win.open = true;
                }
            }

            // open (or toggle shut) the Tetris pane — fired by the tiny tetromino
            // button beside the expanded-pill clock. Mirrors openCalendar.
            function openTetris() {
                if (win.open && win.menu === 9) {
                    const wasGrabbing = win.grabsKeyboard;
                    win.open = false;
                    if (wasGrabbing)
                        root.restoreFocus();

                } else {
                    win.launcher = false;
                    win.ctxGroup = null;
                    win.trayItem = null;
                    win.menu = 9;
                    win.open = true;
                }
            }

            // open (or toggle shut) the Block Blast pane (menu 10) — fired by the tiny
            // plus/T button below the Tetris button. Mirrors openTetris.
            function openBlockBlast() {
                if (win.open && win.menu === 10) {
                    const wasGrabbing = win.grabsKeyboard;
                    win.open = false;
                    if (wasGrabbing)
                        root.restoreFocus();

                } else {
                    win.launcher = false;
                    win.ctxGroup = null;
                    win.trayItem = null;
                    win.menu = 10;
                    win.open = true;
                }
            }

            // open (or toggle shut) the games menu (menu 11) — the little arcade
            // list, fired by the game-controller button right of the desktop dots.
            // Picking a game there routes to openTetris / openBlockBlast (see the
            // menuLoader Connections). Mirrors openBlockBlast.
            function openGames() {
                if (win.open && win.menu === 11) {
                    const wasGrabbing = win.grabsKeyboard;
                    win.open = false;
                    if (wasGrabbing)
                        root.restoreFocus();

                } else {
                    win.launcher = false;
                    win.ctxGroup = null;
                    win.trayItem = null;
                    win.menu = 11;
                    win.open = true;
                }
            }

            // open (or toggle shut) the Settings pane (menu 13) — the gear right of
            // the games button on the expanded dashboard. Default page is Appearance
            // (theme editor); also hosts Online Accounts / Org Agenda / Finance.
            // Refresh the calendar accounts on open (the Online Accounts page needs
            // them), mirroring the old launcher-overlay behaviour.
            function openSettings() {
                if (win.open && win.menu === 13) {
                    const wasGrabbing = win.grabsKeyboard;
                    win.open = false;
                    if (wasGrabbing)
                        root.restoreFocus();

                } else {
                    win.launcher = false;
                    win.ctxGroup = null;
                    win.trayItem = null;
                    win.menu = 13;
                    win.open = true;
                    if (accounts)
                        accounts.load();
                }
            }

            // open (or toggle shut) the Brick Breaker pane (menu 12) — routed from the
            // games list (see the menuLoader Connections). Mirrors openBlockBlast.
            function openBrickBreaker() {
                if (win.open && win.menu === 12) {
                    const wasGrabbing = win.grabsKeyboard;
                    win.open = false;
                    if (wasGrabbing)
                        root.restoreFocus();

                } else {
                    win.launcher = false;
                    win.ctxGroup = null;
                    win.trayItem = null;
                    win.menu = 12;
                    win.open = true;
                }
            }

            // open (or toggle shut) the Snake pane (menu 14) — routed from the games
            // list (see the menuLoader Connections). Mirrors openBrickBreaker.
            function openSnake() {
                if (win.open && win.menu === 14) {
                    const wasGrabbing = win.grabsKeyboard;
                    win.open = false;
                    if (wasGrabbing)
                        root.restoreFocus();

                } else {
                    win.launcher = false;
                    win.ctxGroup = null;
                    win.trayItem = null;
                    win.menu = 14;
                    win.open = true;
                }
            }

            onDashChanged: {
                if (!win.dash) {
                    win.hoverItem = null;
                    win.kbNav = false;
                }
            }
            // a closed (or non-game) pane forgets the dragged park position, so
            // reopening a game starts centred again.
            onOpenChanged: if (!win.open) win.tetrisMoved = false;
            onMenuChanged: if (win.menu !== 9 && win.menu !== 10 && win.menu !== 12 && win.menu !== 14) win.tetrisMoved = false;
            screen: modelData
            WlrLayershell.layer: WlrLayer.Overlay
            // grab the keyboard only when the pill genuinely needs it (see
            // `grabsKeyboard`): the launcher/clipboard is up, or an editable field has
            // focus. Everything else — collapsed/hovered pill, an appearing notification,
            // a menu you're only clicking toggles in — stays KeyboardFocus.None and never
            // touches the active window's focus. The launcher and clipboard need
            // *Exclusive* so their search field grabs the keyboard even when opened by a
            // shortcut/IPC (no click to trigger focus) and arrow-key nav works from the
            // first keystroke; a wifi-password / reply field pulls Exclusive the moment it
            // takes focus (its own `focus:`/click), so typing works without a stray grab.
            WlrLayershell.keyboardFocus: win.grabsKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            // capShow deliberately falls through to pillRegion (NOT fullRegion): the
            // pill captures input only over its controls, so clicks elsewhere reach
            // the fullscreen capture canvas below (region draw / annotation).
            mask: (win.open || win.launcher || win.ctxMode || win.confirmActive || win.focused || win.deadlines) ? fullRegion : (win.fsHide ? emptyRegion : pillRegion)
    
            Process {
                id: confirmProc
            }
    
            Connections {
                function onLauncherShortcut(screen) {
                    // with one monitor, ignore the screen hint (names may not match);
                    // with several, only the pill on the active screen responds
                    if (screen !== "" && Quickshell.screens.length > 1 && win.screen && screen !== win.screen.name)
                        return ;
    
                    win.toggleLauncher();
                }
    
                // same active-screen rule as the launcher shortcut
                function onClipboardShortcut(screen) {
                    if (screen !== "" && Quickshell.screens.length > 1 && win.screen && screen !== win.screen.name)
                        return ;
    
                    win.openClipboard();
                }
    
                // same active-screen rule; opens the notification history pane (menu 4)
                function onNotifShortcut(screen) {
                    if (screen !== "" && Quickshell.screens.length > 1 && win.screen && screen !== win.screen.name)
                        return ;
    
                    win.openNotifications();
                }
    
                // same active-screen rule; opens the expanded dashboard in kb-nav mode
                function onExpandShortcut(screen) {
                    if (screen !== "" && Quickshell.screens.length > 1 && win.screen && screen !== win.screen.name)
                        return ;
    
                    win.openExpanded();
                }
    
                // voicePolishToggle (idle) opens the config panel on every pill (like
                // the clipboard shortcut); Start closes them all via onVoiceStateChanged.
                function onVoiceMemoRequested() {
                    win.openVoiceMemo();
                }
    
                // a starting voice take drops focus mode so the dashboard can't sit
                // over the recorder (voiceMorph is gated on !dash), and closes the
                // config panel on every monitor. Open non-voice panels / the launcher
                // are left alone — the recorder just waits them out.
                function onVoiceStateChanged() {
                    if (root.voiceState === "recording") {
                        win.focused = false;
                        if (win.open && win.menu === 7)
                            win.open = false;
                    }
                }
    
                target: root
            }
    
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
    
            // reports the window's current active-focus item (reactive via
            // Window.activeFocusItemChanged) so `kbInputFocused` can tell whether one of
            // our editable fields (objectName "pillKbInput") holds focus.
            Item {
                id: kbProbe
    
                readonly property var focusItem: Window.activeFocusItem
            }
    
            // keyboard-nav mode: the expanded dashboard's key sink. Focused only while
            // the dashboard itself shows — an open menu runs MenuKbNav (or, for the
            // notification/clipboard panes and the launcher, its own key handling).
            // Focus is win.hoverItem, so the roving hover square doubles as the focus
            // square and mousing over any item re-focuses it. Zones per the layout:
            // clock/date (default) | taskbar tiles (Row 1) | launcher icon (Row 2
            // left) | tray + status icons as one strip (Row 2 right).
            Item {
                id: dashKb
    
                focus: win.kbNav && !win.open && !win.launcher && !win.ctxMode && !win.confirmActive
                Keys.onPressed: (event) => {
                    // zone lists, rebuilt per keypress (delegates churn freely)
                    const tasks = [];
                    for (let i = 0; i < taskbar.tileCount; i++) {
                        const t = taskbar.tileAt(i);
                        if (t)
                            tasks.push(t);
    
                    }
                    const strip = [];
                    for (let i = 0; i < trayRep.count; i++) {
                        const t = trayRep.itemAt(i);
                        if (t)
                            strip.push(t);
    
                    }
                    for (let i = 0; i < statusIcons.iconCount; i++) {
                        const t = statusIcons.iconAt(i);
                        if (t)
                            strip.push(t);
    
                    }
                    let cur = win.hoverItem;
                    const iT = tasks.indexOf(cur);
                    const iS = strip.indexOf(cur);
                    if (cur !== dateTimeBlock && cur !== launcherIcon && iT < 0 && iS < 0)
                        cur = dateTimeBlock; // stale / unset focus -> back to the clock
    
                    const go = (it) => {
                        if (it)
                            win.hoverItem = it;
    
                    };
                    if (event.key === Qt.Key_Escape) {
                        // Escape on the dashboard closes the pill entirely
                        win.open = false;
                        win.launcher = false;
                        win.ctxGroup = null;
                        win.trayItem = null;
                        win.focused = false; // dash drops -> kbNav auto-clears
                        root.restoreFocus();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (cur && cur.keyClick)
                            cur.keyClick();
    
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Left) {
                        if (iT > 0)
                            go(tasks[iT - 1]);
                        else if (iT === 0)
                            go(dateTimeBlock);
                        else if (iS > 0)
                            go(strip[iS - 1]);
                        else if (iS === 0)
                            go(launcherIcon);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Right) {
                        if (cur === dateTimeBlock)
                            go(tasks.length ? tasks[0] : (strip.length ? strip[0] : null));
                        else if (cur === launcherIcon)
                            go(strip.length ? strip[0] : null);
                        else if (iT >= 0 && iT < tasks.length - 1)
                            go(tasks[iT + 1]);
                        else if (iS >= 0 && iS < strip.length - 1)
                            go(strip[iS + 1]);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Down) {
                        if (cur === dateTimeBlock)
                            go(launcherIcon);
                        else if (iT >= 0)
                            go(strip.length ? strip[0] : launcherIcon);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Up) {
                        if (cur === launcherIcon)
                            go(dateTimeBlock);
                        else if (iS >= 0)
                            go(tasks.length ? tasks[tasks.length - 1] : dateTimeBlock);
                        event.accepted = true;
                    } else {
                        // first-level menu jumps, mirrored in the calendar menu
                        // (finance is skipped when the feature is off); g = games menu
                        const m = event.key === Qt.Key_F ? (settings.financeEnabled ? 8 : -1) : event.key === Qt.Key_C ? 6 : event.key === Qt.Key_N ? 4 : event.key === Qt.Key_W ? 0 : event.key === Qt.Key_V ? 1 : event.key === Qt.Key_B ? 2 : event.key === Qt.Key_G ? 11 : -1;
                        if (m >= 0) {
                            win.launcher = false;
                            win.menu = m;
                            win.open = true;
                            event.accepted = true;
                        }
                    }
                }
            }
    
            Region {
                id: pillRegion
    
                item: pill
                // union in the floating voice-cancel X (child regions combine by
                // default); when its Loader is inactive it is 0x0 and adds nothing.
                Region {
                    item: voiceCancelLoader
                }
                // and the resting notification deck floating below the pill, but only
                // while it is actually shown (else its rect would eat clicks in the
                // empty space below the resting pill).
                Region {
                    item: win.notifRest ? restDeck : null
                }
            }

            Region {
                id: fullRegion
    
                item: backdrop
            }
            // no items -> whole window is click-through
    
            Region {
                id: emptyRegion
            }
    
            MouseArea {
                id: backdrop
    
                anchors.fill: parent
                enabled: win.open || win.launcher || win.ctxMode || win.focused || win.deadlines
                // dismiss without launching -> hand focus back to the active window, but
                // only if the pill actually held the keyboard (otherwise there's nothing
                // to restore and re-activating the last window is just disruptive).
                // (deadlines is cleared here too as a safety net — its own popup
                // backdrop normally handles the outside click first.)
                onClicked: {
                    const wasGrabbing = win.grabsKeyboard;
                    win.open = false;
                    win.launcher = false;
                    win.ctxGroup = null;
                    win.trayItem = null;
                    win.focused = false;
                    win.deadlines = false;
                    if (wasGrabbing)
                        root.restoreFocus();
    
                }
            }
    
            Item {
                id: pill
    
                // x is DERIVED from the target centre (win.pillCenterX) minus half the
                // current width, with NO Behavior of its own — so as the pill's width
                // animates on expand/collapse it grows symmetrically about the centre,
                // and the centre itself animates (see win.pillCenterX) so the grow and
                // the move happen together instead of grow-from-the-left-then-slide.
                // (Binding x directly to an animating width made its Behavior chase a
                // moving target and lag a full duration behind.)
                x: win.pillCenterX - width / 2
                // attached flush to the top edge in every stage — the resting clock pill,
                // the expanded dashboard / panel, AND a burst (which now replaces the
                // clock in place, so it stays pinned to the edge and grows downward) —
                // "rounded out" via the PillSurface background below. Only a legacy
                // notification morph floated 6px below the edge; a positioned capture
                // pill, or a dragged idle pill, uses its own y.
                y: win.capShow ? (win.capPositioned ? win.capPosY : 0)
                   : (win.tetrisMoved && win.gamePane) ? win.tetrisPosY
                   : (win.idleMoved && !win.dash) ? win.idlePosY
                   : win.notifMorph ? 6 : 0
                // animate y for every non-drag transition (expand, snap, reset-home) —
                // matches pillCenterX so a reset glides both axes, not just x. Frozen
                // only while a drag is live so the pill tracks the pointer 1:1.
                Behavior on y { enabled: !win.capDragging && !win.idleDragging && !win.tetrisDragging; NumberAnimation { duration: theme.anim; easing.type: Easing.OutCubic } }

                // drag the capture pill by its body (buttons still click — the handler
                // only steals the grab once you drag past threshold). Drop near the top
                // → dock with wings at that x; drop lower → float rounded. Sets capManual
                // so auto-avoid yields to the hand-placed spot until the capture ends.
                DragHandler {
                    id: capDrag
                    enabled: win.capShow
                    target: null
                    property real _ox: 0
                    property real _oy: 0
                    onActiveChanged: {
                        if (capDrag.active) {
                            capDrag._ox = capDrag.centroid.position.x;
                            capDrag._oy = capDrag.centroid.position.y;
                            win.capPosX = pill.x; win.capPosY = pill.y;   // seed → no jump
                            win.capManual = true; win.capPositioned = true; win.capDragging = true;
                        } else {
                            win.capDragging = false;
                            win.capAttached = win.capPosY <= win.capSnapY;
                            if (win.capAttached) win.capPosY = 0;
                        }
                    }
                    onCentroidChanged: {
                        if (!capDrag.active) return;
                        const sp = capDrag.centroid.scenePosition;
                        win.capPosX = Math.max(0, Math.min(sp.x - capDrag._ox, win.width - pill.width));
                        win.capPosY = Math.max(0, Math.min(sp.y - capDrag._oy, win.height - pill.height));
                    }
                }

                // drag the resting pill anywhere by its body (clicks still open the
                // dashboard / deadlines — the handler only steals the grab past the drag
                // threshold). Enabled only while idle: expanding, the launcher/menus, a
                // capture, or a voice take own the pill and place it themselves. Free
                // move, clamped on-screen; no snap and no persistence (idleMoved just
                // parks it for this session — expand recentres, collapse restores).
                DragHandler {
                    id: idleDrag
                    enabled: !win.capShow && !win.dash && !win.voiceMorph
                    target: null
                    property real _ox: 0
                    property real _oy: 0
                    onActiveChanged: {
                        if (idleDrag.active) {
                            idleDrag._ox = idleDrag.centroid.position.x;
                            idleDrag._oy = idleDrag.centroid.position.y;
                            win.idlePosX = pill.x; win.idlePosY = pill.y;   // seed → no jump
                            win.idleCenterX = pill.x + pill.width / 2;
                            win.idleMoved = true; win.idleDragging = true;
                        } else {
                            win.idleDragging = false;
                            // dropped near the top edge → dock flush with wings; lower → float
                            win.idleAttached = win.idlePosY <= win.idleSnapY;
                            if (win.idleAttached) win.idlePosY = 0;
                        }
                    }
                    onCentroidChanged: {
                        if (!idleDrag.active) return;
                        const sp = idleDrag.centroid.scenePosition;
                        win.idlePosX = Math.max(0, Math.min(sp.x - idleDrag._ox, win.width - pill.width));
                        win.idlePosY = Math.max(0, Math.min(sp.y - idleDrag._oy, win.height - pill.height));
                        win.idleCenterX = win.idlePosX + pill.width / 2;
                    }
                }

                // NOTE: the game panes (Tetris / Block Blast) are NOT dragged by their
                // body — a stray drag while playing Block Blast would fight the block
                // drag-and-drop. Instead each game's header carries a little grip that
                // emits parkDrag* signals; the menuLoader Connections block (below)
                // translates those into the tetris* park position, driving pill.x/y
                // exactly as the old body handler did.
                // the voice recorder leads the chains: a larger resting pill (220x36,
                // iPhone-memo style) — voiceMorph already yields to open/launcher/ctx.
                width: win.capShow ? (captureLoader.item ? captureLoader.item.implicitWidth + theme.pad * 2 : 520) : win.voiceMorph ? 220 : win.showBurst ? (burstLoader.item ? burstLoader.item.implicitWidth : 96) : win.launcher ? win.launcherWidth : win.ctxMode ? 520 : (win.notifMorph ? (morphStack.item ? morphStack.item.implicitWidth : 420) : (win.open ? (win.menu === 13 ? win.settingsWidth : win.menu === 6 || win.menu === 8 ? win.calWidth : win.menu === 12 ? win.brickWidth : win.menu === 14 ? win.snakeWidth : (win.menu === 9 || win.menu === 10) ? win.tetrisWidth : 520) : (win.dash ? win.hoverWidth : Math.max(56 + root.privacyCount * 20 + root.notifRestWidth, win.restUnderline ? collapsedPill.implicitWidth + 28 : 0))))
                // in ctx mode the pill sizes to whichever menu loader is active (app
                // context menu or tray menu).
                height: win.capShow ? (captureLoader.item ? captureLoader.item.implicitHeight + theme.pad * 2 : 120) : win.voiceMorph ? 36 : win.showBurst ? (burstLoader.item ? burstLoader.item.implicitHeight : 28) : (win.open || win.launcher) ? win.openPaneHeight : win.ctxMode ? Math.min(win.openHeight, ((ctxLoader.item || trayLoader.item) ? (ctxLoader.item || trayLoader.item).implicitHeight + theme.pad * 2 : 300)) : (win.notifMorph ? morphStack.implicitHeight : (win.dash ? win.hoverHeight : (win.restUnderline ? 48 : 28)))
                // resting (collapsed, un-hovered) pill is dimmed; full opacity once
                // hovered / open / a notification is morphing it (or a camera/recording
                // is live, or a voice take is recording, or the agenda popup is up);
                // fully hidden while a fullscreen window is focused (fsHide)
                opacity: win.capShow ? 1 : win.voiceMorph ? 1 : win.showBurst ? 1 : (win.fsHide ? 0 : ((win.dash || win.notifMorph || win.privacyRest || win.deadlines || win.idleDragging) ? 1 : theme.idleOpacity))
    
                HoverHandler {
                    id: hover
                }
    
                // scroll anywhere over the pill — the resting clock pill OR the
                // hovered dashboard — to nudge the active speaker's volume up/down.
                // Gated OUT of the open control panel / menus, the launcher, a ctx
                // menu, the notification morph, and the action-burst / voice-recorder
                // takes (those either scroll their own content or shouldn't hijack the
                // wheel). Forced topmost (z) so it sees the wheel before the Row 2
                // status icons / the resting clock; acceptedButtons NoButton so clicks
                // + hover fall straight through to the body (reveal dashboard / open
                // launcher) and the icons underneath — this only claims the wheel.
                MouseArea {
                    anchors.fill: parent
                    z: 100
                    enabled: !win.open && !win.launcher && !win.ctxMode && !win.notifMorph && !win.showBurst && !win.voiceMorph && !win.capShow
                    acceptedButtons: Qt.NoButton
                    onWheel: (wheel) => {
                        const sink = Pipewire.defaultAudioSink;
                        if (!sink || !sink.audio)
                            return ;
    
                        // angleDelta is in eighths of a degree; a full mouse notch is
                        // 120, but hi-res / free-spinning wheels report many smaller
                        // ticks — so scale the step by the actual amount (120 = 5%)
                        // instead of stepping a fixed 5% per event. Some devices
                        // report on x, so fall back to it.
                        const dy = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
                        if (dy === 0)
                            return ;
    
                        const v = Math.max(0, Math.min(1, sink.audio.volume + (dy / 120) * 0.05));
                        sink.audio.volume = v;
                    }
                }
    
                // background: attached to the top edge in every non-notification stage
                // (resting clock pill AND the expanded dashboard / panel), borderless,
                // with convex free (bottom) corners and concave "wing" top corners that
                // melt into the edge. The wings flare OUTWARD via negative horizontal
                // margins — the surface is 2*wing wider than the pill — so the content
                // keeps its full width and never spills over the wings. Transparent
                // (hidden) only while a notification or action-burst owns the pill.
                PillSurface {
                    id: surface
    
                    // small flare on the narrow resting pill, a big one on the wide
                    // dashboard so the "rounded out" reads at 640px. A floating pill —
                    // capture OR idle, dragged or dropped away from the top edge — drops
                    // its wings entirely and becomes a plain fully-rounded rectangle.
                    readonly property int wingW: win.pillFloating ? 0 : (win.dash ? 34 : 12)
    
                    anchors.fill: parent
                    anchors.leftMargin: -wingW
                    anchors.rightMargin: -wingW
                    theme: theme
                    radius: (win.dash || win.pillFloating) ? theme.radiusPanel : Math.min(theme.radiusPanel, height / 2)
                    wing: wingW
                    // detached capture / idle pill → uniformly rounded (top corners = bottom)
                    rounded: win.pillFloating
                    // solid when expanded, a camera/recording is live, a voice take is
                    // running, the agenda popup is up, OR a burst is replacing the clock
                    // (the burst now lives INSIDE the pill surface); translucent at rest.
                    fillColor: (win.capShow || win.dash || win.privacyRest || win.voiceMorph || win.deadlines || win.showBurst) ? theme.bg : theme.bgTranslucent
                    // the surface stays up through a burst now — the burst replaces the
                    // clock in place and the pill resizes around it (only during a capture
                    // does the burst float below in its own box; see burstLoader). Hidden
                    // only while a notification morph owns the pill.
                    visible: !win.notifMorph
                    opacity: visible ? 1 : 0
    
                    Behavior on opacity {
                        NumberAnimation {
                            duration: theme.animFast
                        }
    
                    }
    
                    Behavior on anchors.leftMargin {
                        NumberAnimation {
                            duration: theme.anim
                            easing.type: Easing.OutCubic
                        }
    
                    }
    
                    Behavior on anchors.rightMargin {
                        NumberAnimation {
                            duration: theme.anim
                            easing.type: Easing.OutCubic
                        }
    
                    }
    
                }
    
                // clicking the hovered pill body (empty area) opens the launcher;
                // the Row-2 status icons / app icons handle their own clicks above
                MouseArea {
                    anchors.fill: parent
                    enabled: win.dash && !win.open && !win.launcher && !win.notifMorph && !win.ctxMode
                    onClicked: {
                        win.launcher = true;
                    }
                }
    
                MouseArea {
                    anchors.fill: parent
                    enabled: win.open || win.launcher
                    onClicked: {
                    }
                }
    
                // ---- on-air equalizer: a wavy (mic open) / flat (muted) line across the
                // vertical middle of the collapsed pill while a camera / screencast is
                // live. Drawn BEFORE the clock (below it in the stack) and filling the pill
                // edge-to-edge (its amplitude tapers to the centre-line at both ends, which
                // sits at the pill's widest point, so it reaches the edges without spilling
                // past the rounded corners / wings). The time stays legible through it.
                OnAirWave {
                    anchors.fill: parent
                    theme: theme
                    active: !win.dash && !win.notifMorph && !win.showBurst && !win.voiceMorph && !win.capShow && root.privacyActive
                    micOn: root.micUnmuted
                    level: micPeak.peak
                }
    
                // ---- collapsed: clock (hh:mm) + privacy icons (camera / screen) ----
                CollapsedPill {
                    id: collapsedPill
                    anchors.centerIn: parent
                    // lifted above the resting focus MouseArea below so the deadline
                    // under-line's own MouseArea intercepts its clicks (the clock /
                    // glyphs don't accept mouse, so those still fall through to focus).
                    z: 1
                    // stays rendered through a burst (no showBurst gate) so it can
                    // *revolve away* as the burst revolves in: it folds down about its
                    // top edge (+90°) and fades, then unfolds back when the burst clears.
                    visible: !win.dash && !win.notifMorph && !win.voiceMorph && !win.capShow
                    opacity: win.showBurst ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: theme.animFast } }
                    transform: Rotation {
                        origin.x: collapsedPill.width / 2; origin.y: 0
                        axis { x: 1; y: 0; z: 0 }
                        angle: win.showBurst ? 90 : 0
                        Behavior on angle { NumberAnimation { duration: theme.anim; easing.type: Easing.OutCubic } }
                    }
                    theme: theme
                    clock: root.clockShort
                    solid: win.privacyRest
                    cameraOn: root.cameraInUse
                    recordingOn: root.screenRecording
                    hasUnread: notifs.unreadCount > 0
                    // do-not-disturb (auto-on during a screencast) hides the app-icon
                    // strip and shows the generic unread dot instead
                    dnd: notifs.dnd
                    // one entry per app with un-cleared notifications (deduped,
                    // newest-app-first) → an app-icon glance strip before the privacy icons
                    notifGroups: notifs.grouped
                    iconsMax: root.notifAppIconsMax
                    // org-deadline under-line (overdue / due-today counts); zeroed
                    // under the finance privacy toggle so the under-line disappears
                    lateCount: win.orgHidden ? 0 : orgAgenda.lateCount
                    todayCount: win.orgHidden ? 0 : orgAgenda.todayCount
                    // imminent-meeting notice in the same under-line (also privacy-gated)
                    meetingMins: win.orgHidden ? -1 : calEvents.nextMeetingMins
                    onDeadlinesActivated: win.deadlines = true
                }
    
                // focus mode: click the collapsed pill to reveal + hold the dashboard.
                // Disabled once expanded / morphing so the dashboard's own icons, the
                // notification cards and the burst keep their clicks — and while the
                // voice recorder owns the pill (its clicks stop the take, not expand).
                MouseArea {
                    anchors.fill: parent
                    enabled: !win.dash && !win.notifMorph && !win.showBurst && !win.voiceMorph && !win.capShow
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    // left-click reveals the dashboard; right-click anywhere on the
                    // resting pill opens the org-deadlines list (available even when
                    // nothing is due — it then shows the "nothing due" empty state);
                    // middle-click sends a dragged pill back to its top-centre home.
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.RightButton) {
                            // org deadlines hide under the finance privacy toggle
                            if (!win.orgHidden)
                                win.deadlines = true;
                        } else if (mouse.button === Qt.MiddleButton) {
                            win.idleReset();
                        } else {
                            // reveal the dashboard AND grab the keyboard, so arrows
                            // navigate, first-level letters jump to a menu, Escape
                            // closes, and any pane opened from here (e.g. Tetris) keeps
                            // the keyboard. Mirrors the `expand` IPC (openExpanded).
                            win.focused = true;
                            win.kbNav = true;
                            win.hoverItem = dateTimeBlock;
                        }
                    }
                }
    
                // ---- notification morph: the collapsed pill becomes a stack ----
                // The active-notification deck (NotificationStack) is the pill
                // body; pill.height tracks its implicit height, which grows when
                // hovered and the deck drops into a full list. The pill's own
                // background is hidden here so the cards are the only surface.
                Item {
                    anchors.fill: parent
                    clip: true
    
                    Loader {
                        id: morphStack
    
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 0
                        active: win.notifMorph
                        sourceComponent: cStack
                        opacity: win.notifMorph ? 1 : 0
                        visible: opacity > 0
    
                        Behavior on opacity {
                            NumberAnimation {
                                duration: theme.animFast
                            }
    
                        }
    
                    }
    
                }
    
                // ---- action burst overlay (desktop switch / layout change) ----
                // Replaces the collapsed clock: a vertical column of burst rows that
                // fills the pill (which resizes to it). While the capture UI owns the
                // pill the burst floats just BELOW it in its own box (boxed) instead, so
                // it never covers or strips the controls. z above the resting content so
                // the rows revolve in over the folding-away clock.
                Loader {
                    id: burstLoader
                    z: 5

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: win.capShow ? parent.height + 8 : (parent.height - height) / 2
                    active: win.showBurst
                    sourceComponent: cBurst
                    opacity: win.showBurst ? 1 : 0
                    visible: opacity > 0
    
                    Behavior on opacity {
                        NumberAnimation {
                            duration: theme.animFast
                        }

                    }

                }

                // burst content, defined here in `win` scope so `boxed` can read this
                // monitor's capShow (the burst gets its own surface only while floating
                // below the capture pill; replacing the clock it uses the pill surface).
                Component {
                    id: cBurst
                    ActionBurstPill {
                        theme: theme
                        model: burstModel
                        desktops: root.desktops
                        boxed: win.capShow
                        phase: root.burstPhase
                        fromLabel: root.burstFromLabel
                        toLabel: root.burstToLabel
                        dotIdx: root.burstDotIdx
                        levelIcon: root.burstLevelIcon
                        levelTitle: root.burstLevelTitle
                        levelFrom: root.burstLevelFrom
                        levelTo: root.burstLevelTo
                    }
                }

                // ---- voice recorder: the resting pill becomes an iPhone-style memo
                // recorder while a take records / transcribes (see § init.qml — voice
                // recording). Clicks stop the take; the floating X beside the pill
                // (a sibling of `pill`, below) cancels it.
                Loader {
                    id: voiceLoader
    
                    // fill the whole pill — VoiceRecorderPill self-insets its content
                    // by the stadium's corner radius so the busy stripe / waveform
                    // fill the straight section edge-to-edge.
                    anchors.fill: parent
                    active: win.voiceMorph
                    opacity: win.voiceMorph ? 1 : 0
                    visible: opacity > 0
    
                    sourceComponent: VoiceRecorderPill {
                        theme: theme
                        mode: root.voiceState === "transcribing" ? "transcribing" : "recording"
                        level: micPeak.peak
                        seconds: root.voiceSeconds
                        // the in-pill stop affordance == the raw route (voiceToggle)
                        onStopRequested: root.voiceStop()
                    }
    
                    Behavior on opacity {
                        NumberAnimation {
                            duration: theme.animFast
                        }

                    }

                }

                // ---- capture controls: the pill becomes the screenshot toolbar
                // (annotating) or the record settings (recConfig). z high so it sits
                // over the resting/dashboard content; the pill is sized to it by the
                // width/height ternaries above. The fullscreen canvas is capWin.
                Loader {
                    id: captureLoader
                    z: 50
                    anchors.centerIn: parent
                    active: win.capShow
                    opacity: win.capShow ? 1 : 0
                    visible: opacity > 0
                    sourceComponent: win.capMenu ? cCaptureMenu
                                   : (capture.mode === "recConfig" ? cRecordControls : cCaptureToolbar)
                    Behavior on opacity { NumberAnimation { duration: theme.animFast } }
                }
                Component {
                    id: cCaptureMenu
                    CaptureMenu {
                        theme: theme
                        recording: capture.mode === "recording"
                        onScreenshot: { win.capMenu = false; capture.beginScreenshot(); }
                        onScreenshotRegion: { win.capMenu = false; capture.beginScreenshotRegion(); }
                        onRecord: { win.capMenu = false; capture.beginRecord(); }
                        onStop: { win.capMenu = false; capRec.stop(); }
                        onDismiss: win.capMenu = false
                    }
                }
                Component {
                    id: cCaptureToolbar
                    CaptureToolbar { state: capture; theme: theme }
                }
                Component {
                    id: cRecordControls
                    RecordControls { state: capture; theme: theme; rc: capRec }
                }

                // ---- shared hover indicator (one square that jumps between items) ----
                // Declared before the rows so it sits *behind* their icons. Its target
                // is the hovered item (win.hoverItem) or, when none, the launcher icon;
                // geometry is mapped from that item into `pill`'s coordinate space and
                // animated, so the square slides from item to item. Re-maps on stage /
                // pill-size changes too, so it stays glued through morphs.
                Rectangle {
                    id: hoverInd
    
                    // the roving square appears over app tiles / tray / status icons,
                    // the date/time block and the launcher icon. Most report a plain
                    // faded-gray square; the launcher asks for the accent-soft launcher
                    // colour via `hoverColor`, so the same square recolours as it lands.
                    readonly property var target: win.hoverItem
                    readonly property point pos: {
                        const _dep = [win.dash, win.open, win.launcher, pill.width, pill.height];
                        return hoverInd.target ? pill.mapFromItem(hoverInd.target, 0, 0) : Qt.point(0, 0);
                    }
                    // items may ask for extra padding around themselves (the app tiles
                    // do, since their icons are larger) so the square grows a little
                    // when it sits behind them; everything else gets a snug fit.
                    readonly property int pad: (target && target.hoverPad) ? target.hoverPad : 0
                    // some targets (the clock) want a snugger vertical fit than
                    // their horizontal padding gives — they expose `hoverPadY`;
                    // everything else just reuses `pad` in both directions.
                    readonly property int padY: (target && target.hoverPadY !== undefined) ? target.hoverPadY : pad
                    // some targets (the clock) sit a hair high inside their box, so
                    // they can nudge the square down a few px via `hoverOffsetY`.
                    readonly property int offY: (target && target.hoverOffsetY !== undefined) ? target.hoverOffsetY : 0
    
                    radius: theme.radiusSmall
                    // per-target tint: the launcher exposes `hoverColor` (accent-soft);
                    // everything else falls back to the shared faded-gray hover.
                    color: (target && target.hoverColor) ? target.hoverColor : theme.bgHover
                    opacity: (win.dash && !win.open && !win.launcher && !win.notifMorph && !win.ctxMode && target) ? 1 : 0
                    visible: opacity > 0
                    x: pos.x - pad
                    y: pos.y - padY + offY
                    width: target ? target.width + pad * 2 : 0
                    height: target ? target.height + padY * 2 : 0
    
                    Behavior on color {
                        ColorAnimation {
                            duration: theme.animFast
                        }
    
                    }
    
                    Behavior on x {
                        NumberAnimation {
                            duration: theme.animFast
                            easing.type: Easing.OutCubic
                        }
    
                    }
    
                    Behavior on y {
                        NumberAnimation {
                            duration: theme.animFast
                            easing.type: Easing.OutCubic
                        }
    
                    }
    
                    Behavior on width {
                        NumberAnimation {
                            duration: theme.animFast
                            easing.type: Easing.OutCubic
                        }
    
                    }
    
                    Behavior on height {
                        NumberAnimation {
                            duration: theme.animFast
                            easing.type: Easing.OutCubic
                        }
    
                    }
    
                    Behavior on opacity {
                        NumberAnimation {
                            duration: theme.animFast
                        }
    
                    }
    
                }
    
                // ========= Row 1: datetime + virtual desktops (left) | apps (right) =========
                Item {
                    x: theme.pad + 8
                    y: 20
                    width: pill.width - (theme.pad + 8) * 2
                    height: 36
                    opacity: (win.dash && !win.open && !win.launcher && !win.notifMorph && !win.ctxMode) ? 1 : 0
                    visible: opacity > 0
    
                    // date/time with the virtual-desktop dots stacked beneath it
                    // (top-anchored so the dots spill into the gap above Row 2).
                    Column {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        // DM Serif Display carries ~10px of empty ascent above the
                        // digits, so the clock's line-box top sits well below the
                        // taskbar icon tops (which are top-anchored). Pull the whole
                        // block up by that gap so the clock's cap-top lines up with
                        // the taskbar top (tune this one number if it over/undershoots).
                        anchors.topMargin: -10
                        spacing: 9
    
                        // the clock block. Held at ≥56px tall (its old height, back when
                        // the two game buttons sat stacked to its right) so the desktop
                        // dots / hairline baseline below it stays exactly where it was
                        // after the game buttons moved down next to the dots — the row
                        // heights below (dots at y≈86, Row 2 at y:100) are hard-coded to
                        // that baseline.
                        Item {
                            id: dtRow
                            implicitWidth: dateTimeBlock.implicitWidth
                            implicitHeight: Math.max(dateTimeBlock.implicitHeight, 56)
                            width: implicitWidth
                            height: implicitHeight

                        // time over date — clicking it opens the calendar pane, and the
                        // shared hover square jumps here (a plain faded-gray square, so
                        // no `hoverColor`). Wrapped in an Item so the MouseArea overlays
                        // the text instead of taking a slot in the Column.
                        Item {
                            id: dateTimeBlock

                            anchors.left: parent.left
                            anchors.top: parent.top

                            // grow the roving square a touch past the tight text box
                            // horizontally, but keep it snugger vertically — the
                            // clock's line boxes already carry leading, so the full
                            // `hoverPad` on top/bottom makes the square look too tall.
                            readonly property int hoverPad: 6
                            readonly property int hoverPadY: 0
                            readonly property int hoverOffsetY: 2
    
                            // keyboard nav: Enter = click (open the calendar pane)
                            function keyClick() { win.openCalendar(); }
    
                            implicitWidth: dtCol.implicitWidth
                            implicitHeight: dtCol.implicitHeight
                            width: implicitWidth
                            height: implicitHeight
    
                            Column {
                                id: dtCol
    
                                spacing: 1
    
                                // big time, prominent — set in the serif display face
                                Text {
                                    id: clockTime
                                    text: root.clockShort
                                    color: theme.text
                                    font.family: theme.serif
                                    font.pixelSize: 34
                                    lineHeight: 0.9
                                }
    
                                // date, dim underneath — uppercase mono label
                                Text {
                                    text: root.clockDate
                                    color: theme.textDim
                                    font.family: theme.mono
                                    font.pixelSize: theme.fsSmall
                                    font.letterSpacing: theme.labelSpacing
                                    font.capitalization: Font.AllUppercase
                                    lineHeight: 0.95
                                }
    
                            }
    
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onContainsMouseChanged: {
                                    if (containsMouse)
                                        win.hoverEnter(dateTimeBlock);
    
                                }
                                onClicked: win.openCalendar()
                            }

                        }

                        }

                        // the virtual-desktop dots + the games button, on one baseline.
                        // The dots hide when there's only a single virtual desktop (nothing
                        // to switch between); the games button then slides left into their
                        // place and the hairline rule below follows (its x keys off
                        // deskRow.width). The row keeps the dots' 9px height so the button —
                        // taller — just overhangs it, centred, leaving the dots exactly on
                        // their original baseline.
                        Item {
                            id: deskRow
                            implicitWidth: settingsMenuBtn.x + settingsMenuBtn.width
                            implicitHeight: deskDots.implicitHeight
                            width: implicitWidth
                            height: implicitHeight

                            // hollow dots (click to switch) + one filled dot that slides
                            // to the active desktop — the same move as the desktop burst.
                            // Hidden (and taking no width — Row/anchors skip it) when only
                            // one desktop exists.
                            DesktopDots {
                                id: deskDots

                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.desktops.length > 1
                                theme: theme
                                desktops: root.desktops
                                activeIdx: root.deskActiveIdx
                                interactive: true
                                onSwitchRequested: (id) => {
                                    return root.switchDesktop(id);
                                }
                            }

                            // games button — a game-controller glyph that opens the games
                            // menu (menu 11: Tetris, Block Blast, …). Sits right of the
                            // dots, or at the row's left edge when the dots are hidden.
                            Rectangle {
                                id: gameMenuBtn

                                anchors.left: deskDots.visible ? deskDots.right : parent.left
                                anchors.leftMargin: deskDots.visible ? 12 : 0
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22
                                height: 22
                                radius: theme.radiusSmall
                                color: (gameMa.containsMouse || (win.open && win.menu === 11)) ? theme.accentSoft : "transparent"

                                MSym {
                                    anchors.centerIn: parent
                                    icon: "sports_esports"
                                    size: 16
                                    fill: (win.open && win.menu === 11) ? 1 : 0
                                    color: (gameMa.containsMouse || (win.open && win.menu === 11)) ? theme.text : theme.accent
                                }

                                MouseArea {
                                    id: gameMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: win.openGames()
                                }

                                Behavior on color {
                                    ColorAnimation {
                                        duration: theme.animFast
                                    }

                                }

                            }

                            // settings button — a gear glyph that opens the Settings
                            // pane (menu 13: Appearance / Online Accounts / Org Agenda /
                            // Finance). Sits right of the games button; the Settings page
                            // used to open from the launcher's gear (now moved here).
                            Rectangle {
                                id: settingsMenuBtn

                                anchors.left: gameMenuBtn.right
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22
                                height: 22
                                radius: theme.radiusSmall
                                color: (setMa.containsMouse || (win.open && win.menu === 13)) ? theme.accentSoft : "transparent"

                                MSym {
                                    anchors.centerIn: parent
                                    icon: "settings"
                                    size: 16
                                    fill: (win.open && win.menu === 13) ? 1 : 0
                                    color: (setMa.containsMouse || (win.open && win.menu === 13)) ? theme.text : theme.accent
                                }

                                MouseArea {
                                    id: setMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: win.openSettings()
                                }

                                Behavior on color {
                                    ColorAnimation {
                                        duration: theme.animFast
                                    }

                                }

                            }

                        }

                    }

                    // grouped app icons (taskbar)
                    Taskbar {
                        id: taskbar
    
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        theme: theme
                        groups: root.appGroups
                        activeWindow: root.activeWindow
                        onActivated: (grp) => {
                            return root.taskbarActivate(grp);
                        }
                        onContextRequested: (grp) => {
                            return win.ctxGroup = grp;
                        }
                        onReordered: (keys) => {
                            return root.taskbarReorder(keys);
                        }
                        onItemEntered: (it) => {
                            return win.hoverEnter(it);
                        }
                    }
    
                    Behavior on opacity {
                        NumberAnimation {
                            duration: theme.animFast
                        }
    
                    }
    
                }
    
                // hairline rule separating the two dashboard rows (hover state only).
                // Starts just to the right of the desktop-dots + games-button row
                // (deskRow) — which shrinks to just the button when the dots hide, so
                // the rule automatically extends left to fill that space — and runs to
                // the pill's right edge.
                Rectangle {
                    x: theme.pad + 8 + deskRow.width + 16
                    y: 86
                    width: pill.width - (theme.pad + 8) - x
                    height: 1
                    color: theme.divider
                    opacity: (win.dash && !win.open && !win.launcher && !win.notifMorph && !win.ctxMode) ? 1 : 0
                    visible: opacity > 0
    
                    Behavior on opacity {
                        NumberAnimation {
                            duration: theme.animFast
                        }
    
                    }
    
                }
    
                // ============ Row 2: launcher icon (left) | tray + status (right) ============
                Item {
                    x: theme.pad + 8
                    y: 100
                    width: pill.width - (theme.pad + 8) * 2
                    height: 42
                    opacity: (win.dash && !win.open && !win.launcher && !win.notifMorph && !win.ctxMode) ? 1 : 0
                    visible: opacity > 0
    
                    // open the app launcher — an accent grid glyph. It now shares the
                    // roving hover square like the other dashboard items, but exposes
                    // `hoverColor` so the square recolours to the accent-soft launcher
                    // tint (instead of the faded gray) as it lands here. Transparent at
                    // rest, so it doesn't read as permanently highlighted.
                    Rectangle {
                        id: launcherIcon
    
                        // the roving square asks for this tint when it sits behind us
                        readonly property color hoverColor: theme.accentSoft
    
                        // keyboard nav: Enter = click (open the launcher)
                        function keyClick() {
                            win.open = false;
                            win.launcher = true;
                        }
    
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 42
                        height: 42
                        radius: 12
                        color: "transparent"
    
                        MSym {
                            anchors.centerIn: parent
                            icon: "grid_view"
                            size: 22
                            fill: 1
                            weight: 500
                            color: theme.accent
                        }
    
                        MouseArea {
                            id: launchMa
    
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onContainsMouseChanged: {
                                if (launchMa.containsMouse)
                                    win.hoverEnter(launcherIcon);
    
                            }
                            onClicked: {
                                win.open = false;
                                win.launcher = true;
                            }
                        }
    
                    }
    
                    // system tray (left of the menu icons) + status/menu icons (right)
                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: theme.iconSpacing + 4
    
                        // system tray — sits to the LEFT of the menu icons
                        Repeater {
                            id: trayRep
    
                            model: SystemTray.items
    
                            delegate: Item {
                                id: trayItem
    
                                required property SystemTrayItem modelData
    
                                // keyboard nav: Enter = left-click (activate, or open
                                // the menu for menu-only items)
                                function keyClick() {
                                    const it = trayItem.modelData;
                                    if (it.onlyMenu && it.hasMenu)
                                        win.trayItem = it;
                                    else
                                        it.activate();
                                }
    
                                width: theme.iconCell + 4
                                height: theme.iconCell + 4
    
                                Image {
                                    anchors.centerIn: parent
                                    width: 20
                                    height: 20
                                    source: trayItem.modelData.icon
                                    fillMode: Image.PreserveAspectFit
                                }
    
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onContainsMouseChanged: {
                                        if (containsMouse)
                                            win.hoverEnter(trayItem);
    
                                    }
                                    // left-click activates (or opens the menu for
                                    // menu-only items); right-click opens the item's
                                    // DBus menu *inside the pill* (TrayMenu), matching
                                    // the taskbar app menus rather than a native popup.
                                    onClicked: (mouse) => {
                                        const it = trayItem.modelData;
                                        if (mouse.button === Qt.LeftButton) {
                                            if (it.onlyMenu && it.hasMenu)
                                                win.trayItem = it;
                                            else
                                                it.activate();
                                        } else if (it.hasMenu) {
                                            win.launcher = false;
                                            win.open = false;
                                            win.trayItem = it;
                                        } else {
                                            it.secondaryActivate();
                                        }
                                    }
                                }
    
                            }
    
                        }
    
                        // capture button (left of the status icons / network glyph):
                        // left-click = screenshot, right-click = screen record, and
                        // while recording = stop & save. (A dropdown menu of these is
                        // the next refinement; the actions + IPC verbs work now.)
                        Rectangle {
                            id: captureBtn
                            readonly property bool recording: capture.mode === "recording"
                            width: theme.iconCell + 4; height: theme.iconCell + 4
                            radius: theme.radiusBtn
                            color: (capture.active || captureMa.containsMouse) ? theme.accentDim : "transparent"
                            Behavior on color { ColorAnimation { duration: theme.animFast } }
                            MSym {
                                anchors.centerIn: parent
                                icon: captureBtn.recording ? "stop_circle" : "screenshot_monitor"
                                size: 21
                                fill: captureBtn.recording ? 1 : 0
                                color: capture.active ? theme.accent : theme.textDim
                            }
                            MouseArea {
                                id: captureMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton
                                onContainsMouseChanged: if (containsMouse) win.hoverEnter(captureBtn)
                                // open the chooser (screenshot / record / stop) — like
                                // opening a status menu, not a direct fire. Collapse the
                                // dashboard so only the menu shows.
                                onClicked: {
                                    win.open = false; win.launcher = false; win.focused = false;
                                    win.capMenu = true;
                                }
                            }
                        }

                        // status icons -> open panel to that menu (active one highlighted)
                        StatusIcons {
                            id: statusIcons
    
                            theme: theme
                            notifs: notifs
                            netState: netState
                            fin: finance
                            open: win.open
                            menu: win.menu
                            // close the launcher too, else both panes stack on top of each other
                            onMenuRequested: (m) => {
                                win.launcher = false;
                                win.menu = m;
                                win.open = true;
                            }
                            onItemEntered: (it) => {
                                return win.hoverEnter(it);
                            }
                        }
    
                    }
    
                    Behavior on opacity {
                        NumberAnimation {
                            duration: theme.animFast
                        }
    
                    }
    
                }
    
                // ===================== control panel (open) =====================
                // The two dashboard rows fade out when a panel opens, so the menu
                // fills the pill from the top. Full-width — no icon rail; each menu
                // carries its own back chevron + title via MenuHeader (the chevron
                // collapses the panel back to the dashboard).
                Item {
                    x: theme.pad
                    y: theme.pad
                    width: pill.width - theme.pad * 2
                    height: pill.height - theme.pad * 2
                    opacity: win.open ? 1 : 0
                    visible: opacity > 0
    
                    Loader {
                        id: menuLoader
    
                        anchors.fill: parent
                        active: win.open
                        sourceComponent: win.menu === 0 ? cNet : win.menu === 1 ? cVol : win.menu === 2 ? cBt : win.menu === 3 ? cBatt : win.menu === 5 ? cClip : win.menu === 6 ? cCal : win.menu === 7 ? cVoice : win.menu === 8 ? cFin : win.menu === 9 ? cTetris : win.menu === 10 ? cBlockBlast : win.menu === 11 ? cGames : win.menu === 12 ? cBrickBreaker : win.menu === 13 ? cSettings : win.menu === 14 ? cSnake : cNotif
                    }
                    // chevron back -> collapse panel
    
                    Connections {
                        function onCloseRequested() {
                            const wasGrabbing = win.grabsKeyboard;
                            win.open = false;
                            // keyboard-nav mode: back to the expanded dashboard (the
                            // pill keeps the keyboard); Escape there closes for real.
                            if (win.kbNav)
                                return ;
    
                            if (wasGrabbing)
                                root.restoreFocus();
    
                        }
    
                        // VoiceMemoMenu (menu 7) Start: commit the config + begin a take
                        // (onVoiceStateChanged then closes the panel on every monitor).
                        function onStartRequested(memoType, polish, org, orgCategory) {
                            root.voiceStartConfigured(memoType, polish, org, orgCategory);
                        }
    
                        // calendar wallet button ⇄ finance calendar button (menus 6/8)
                        function onFinanceRequested() {
                            win.menu = 8;
                        }
                        function onCalendarRequested() {
                            win.menu = 6;
                        }

                        // GamesMenu (menu 11) row picked → hand off to that game's own
                        // pane (Tetris 9 / Block Blast 10 / Brick Breaker 12).
                        function onPlayRequested(gameMenu) {
                            if (gameMenu === 9)
                                win.openTetris();
                            else if (gameMenu === 10)
                                win.openBlockBlast();
                            else if (gameMenu === 12)
                                win.openBrickBreaker();
                            else if (gameMenu === 14)
                                win.openSnake();
                        }

                        // game park-drag (Tetris / Block Blast header grip): translate the
                        // grip's scene-space drag into the shared tetris* park position, so
                        // pill.x/y follow it exactly as the old body DragHandler did.
                        function onParkDragStart(sx, sy) {
                            win.tetrisPosX = pill.x; win.tetrisPosY = pill.y;   // seed → no jump
                            win._gameGrabOX = sx - pill.x;
                            win._gameGrabOY = sy - pill.y;
                            win.tetrisMoved = true; win.tetrisDragging = true;
                        }
                        function onParkDragMove(sx, sy) {
                            win.tetrisPosX = Math.max(0, Math.min(sx - win._gameGrabOX, win.width - pill.width));
                            win.tetrisPosY = Math.max(0, Math.min(sy - win._gameGrabOY, win.height - pill.height));
                        }
                        function onParkDragEnd() {
                            win.tetrisDragging = false;
                        }

                        target: menuLoader.item
                        ignoreUnknownSignals: true
                    }
    
                    // keyboard-nav mode: generic arrows/Enter focus for the menus. The
                    // notification (4) and clipboard (5) panes run their own keyboard
                    // handling, so they're excluded; the calendar menu (6) also gets
                    // the f/c/n/w/v/b first-level jumps (its grid stays mouse-only).
                    MenuKbNav {
                        anchors.fill: parent
                        // below the menu loader: the floating highlight square draws
                        // BEHIND the menu content (opaque rows self-style instead)
                        z: -1
                        theme: theme
                        target: menuLoader.item
                        active: win.kbNav && win.open && win.menu !== 4 && win.menu !== 5 && win.menu !== 9 && win.menu !== 10 && win.menu !== 12 && win.menu !== 13
                        shortcuts: win.menu === 6
                        onEscaped: win.open = false // back to the expanded dashboard
                        onShortcutRequested: (m) => {
                            if (m === 8 && !settings.financeEnabled)
                                return; // finance feature is off
                            win.menu = m;
                        }
                    }
    
                    Behavior on opacity {
                        NumberAnimation {
                            duration: theme.anim
                        }
    
                    }
    
                }
    
                // ===================== launcher (wider open state) =====================
                // Like the control panel: the two dashboard rows fade out, so the
                // launcher fills the pill from the top.
                Item {
                    x: theme.pad
                    y: theme.pad
                    width: pill.width - theme.pad * 2
                    height: pill.height - theme.pad * 2
                    clip: true
                    opacity: win.launcher ? 1 : 0
                    visible: opacity > 0
    
                    // Kept instantiated (not gated on win.launcher) so the list
                    // virtualises and pre-warms its icons in the background at
                    // startup; subsequent opens are instant. Sized to the open
                    // dimensions regardless of the pill's current animation so
                    // the ListView always has room to lay out; the panel clips.
                    Launcher {
                        id: launcherItem
    
                        y: 0
                        width: win.launcherWidth - theme.pad * 2
                        // sized to the fixed open dimensions (not the animating pill)
                        // so the ListView always has room; the container clips.
                        height: win.openHeight - theme.pad * 2
                        theme: theme
                        apps: root.appList
                        settings: settings
                        notifs: notifs
                        fin: finance
                        onLaunched: {
                            win.launcher = false;
                            // keyboard-nav mode holds an Exclusive grab — drop the
                            // whole pill so the launched app can take the keyboard.
                            if (win.kbNav)
                                win.focused = false;
    
                        }
                        onCloseRequested: {
                            win.launcher = false;
                            // keyboard-nav mode: Escape returns to the expanded
                            // dashboard instead of dismissing the pill (the Meta+D /
                            // mouse-opened launcher still closes outright).
                            if (!win.kbNav)
                                root.restoreFocus();
    
                        }
                        // right-click on an app: show the floating AppMenu at the click.
                        // The point arrives in the Launcher's coordinates; map it into
                        // the full-screen menu overlay so it can drop out of the pill.
                        onAppMenuRequested: (app, fav, pinned, x, y) => {
                            const p = launcherItem.mapToItem(launcherMenu, x, y);
                            launcherMenu.openFor(app, p.x, p.y, {
                                "fav": fav,
                                "showFav": true,
                                "pinned": pinned,
                                "showPin": true
                            });
                        }
                        onConfirmPower: (action, cmd) => {
                            return win.requestConfirm(action, cmd);
                        }
                    }
    
                    // focus the search field on open; release it on close so the
                    // pill drops the keyboard grab and the active window gets it back
                    Connections {
                        function onLauncherChanged() {
                            if (win.launcher) {
                                launcherItem.open();
                            } else {
                                launcherItem.close();
                                launcherMenu.close(); // a right-click menu never outlives the launcher
                            }
                        }
    
                        target: win
                    }
    
                    Behavior on opacity {
                        NumberAnimation {
                            duration: theme.anim
                        }
    
                    }
    
                }
    
                // ================= app right-click (context) menu =================
                // Rendered INSIDE the pill like the control panel (not a floating
                // popup): the dashboard rows fade out and the AppContextMenu fills the
                // pill from the top. The pill's ctx-mode height binds to this menu's
                // implicitHeight (see the `width`/`height` bindings above). Acting on a
                // row (launcher action / window action) also clears win.ctxGroup so the
                // menu closes, matching Plasma.
                Item {
                    x: theme.pad
                    y: theme.pad
                    width: pill.width - theme.pad * 2
                    height: pill.height - theme.pad * 2
                    opacity: win.ctxGroup !== null ? 1 : 0
                    visible: opacity > 0
    
                    Loader {
                        id: ctxLoader
    
                        anchors.fill: parent
                        active: win.ctxGroup !== null
    
                        sourceComponent: AppContextMenu {
                            theme: theme
                            group: win.ctxGroup
                            desktops: root.desktops
                            isPinned: win.ctxGroup ? root.isPinned(win.ctxGroup.entry || DesktopEntries.heuristicLookup(win.ctxGroup.icon)) : false
                            onLaunchRequested: (s) => {
                                root.launch(s);
                                win.ctxGroup = null;
                            }
                            onActivateRequested: (id) => {
                                root.activateWindow(id);
                                win.ctxGroup = null;
                            }
                            onWindowAction: (verb, uuids) => {
                                root.windowAction(uuids, verb);
                                win.ctxGroup = null;
                            }
                            onPinToggled: (e) => {
                                if (e)
                                    root.togglePin(e);
    
                                win.ctxGroup = null;
                            }
                            onCloseRequested: win.ctxGroup = null
                        }
    
                    }
    
                    Behavior on opacity {
                        NumberAnimation {
                            duration: theme.anim
                        }
    
                    }
    
                }
    
                // ================= system-tray item (context) menu =================
                // The right-clicked tray item's DBus menu, rendered INSIDE the pill the
                // same way as the app context menu above (TrayMenu walks the menu via
                // QsMenuOpener). Shares the ctx-mode pill sizing/fade; triggering a leaf
                // clears win.trayItem so the menu closes.
                Item {
                    x: theme.pad
                    y: theme.pad
                    width: pill.width - theme.pad * 2
                    height: pill.height - theme.pad * 2
                    opacity: win.trayItem !== null ? 1 : 0
                    visible: opacity > 0
    
                    Loader {
                        id: trayLoader
    
                        anchors.fill: parent
                        active: win.trayItem !== null
    
                        sourceComponent: TrayMenu {
                            theme: theme
                            trayItem: win.trayItem
                            onCloseRequested: win.trayItem = null
                        }
    
                    }
    
                    Behavior on opacity {
                        NumberAnimation {
                            duration: theme.anim
                        }
    
                    }
    
                }
    
                Behavior on y {
                    NumberAnimation {
                        duration: theme.anim
                        easing.type: Easing.OutCubic
                    }
    
                }
    
                Behavior on width {
                    NumberAnimation {
                        duration: theme.anim
                        easing.type: Easing.OutCubic
                    }
    
                }
    
                Behavior on height {
                    NumberAnimation {
                        duration: theme.anim
                        easing.type: Easing.OutCubic
                    }
    
                }
    
                Behavior on opacity {
                    NumberAnimation {
                        duration: theme.animFast
                    }
    
                }
    
            }
    
            // ==================== voice cancel: floating X beside the pill ====================
            // A circular X that floats NEXT TO the recorder pill (a sibling of `pill`,
            // like the floating deck, so the pill's own clip/margins can't eat it) for
            // the whole take — recording AND transcribing, so a slow transcription can
            // still be bailed out of. Clicking any monitor's X cancels the one root
            // recording and discards the wav. Offset past the PillSurface's 12px
            // resting wing so it doesn't collide with the flare; its input rectangle
            // is unioned into pillRegion (child Region below), and an inactive Loader
            // is 0x0, so no mask conditionals are needed.
            Loader {
                id: voiceCancelLoader

                // hidden while the capture morph owns the pill (a self-contained menu
                // mode) — the take keeps running underneath and its X returns after
                active: root.voiceActive && !win.capShow
                x: pill.x + pill.width + 22
                y: pill.y + (pill.height - 26) / 2
                width: active ? 26 : 0
                height: active ? 26 : 0
    
                sourceComponent: Rectangle {
                    radius: 13
                    color: cancelMa.containsMouse ? theme.bgHover : theme.bg
                    border.width: 1
                    border.color: theme.borderStrong
    
                    MSym {
                        anchors.centerIn: parent
                        icon: "close"
                        size: 14
                        color: cancelMa.containsMouse ? theme.text : theme.textDim
                    }
    
                    MouseArea {
                        id: cancelMa
    
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.voiceCancel()
                    }
    
                }
    
            }
    
            // ================= launcher app right-click menu (floating) =================
            // The launcher's per-app context menu (AppMenu), hosted here at the
            // full-screen `win` level — NOT inside the launcher's clipped body — so it
            // renders above the pill and can drop out of it without being clipped. The
            // Launcher emits appMenuRequested with the point in its own coordinates;
            // launcherItem.onAppMenuRequested maps that into this overlay and opens the
            // menu. Favourites are toggled back into the launcher's settings; the menu
            // closes with the launcher (see the launcher Connections above). z keeps it
            // above the pill and the floating notifications.
            AppMenu {
                id: launcherMenu
    
                anchors.fill: parent
                z: 1000
                theme: theme
                onFavouriteToggled: (e) => {
                    return launcherItem.toggleFav(e);
                }
                onPinToggled: (e) => {
                    return launcherItem.togglePin(e);
                }
                onLaunched: {
                    win.launcher = false;
                    if (win.kbNav)
                        win.focused = false;
    
                }
            }
    
            // ===================== org deadlines list (floating) =====================
            // The right-click / under-line deadlines panel, hosted here at the
            // full-screen `win` level (like AppMenu) so it drops below the resting
            // pill without being clipped. Centred under the pill and clamped on
            // screen by the component. Backdrop / Esc / opening an item closes it.
            AgendaMenu {
                id: deadlinesMenu
                anchors.fill: parent
                z: 1000
                theme: theme
                org: orgAgenda
                cal: calEvents
                open: win.deadlines
                // centre the 400px panel under the pill (component clamps on screen)
                px: pill.x + pill.width / 2 - 200
                py: pill.y + pill.height + 8
                onDismissed: {
                    const wasGrabbing = win.grabsKeyboard;
                    win.deadlines = false;
                    if (wasGrabbing)
                        root.restoreFocus();
                }
            }

            // ===================== notifications below an open pill =====================
            // When the pill is clicked-open / launcher / app-menu — or while the voice
            // recorder owns it — there is no resting droplet, so the same deck floats
            // below the taken-over pill instead (otherwise notifications would be
            // invisible for the whole take). Action bursts are NOT routed through here:
            // they morph the pill in place and leave the resting droplet deck alone.
            Loader {
                // centred under the pill (follows a dragged idle pill; an expanded pill
                // sits top-centre so this reads as screen-centre there too).
                x: pill.x + (pill.width - width) / 2
                y: pill.y + pill.height + 8
                active: ((win.open || win.launcher || win.ctxMode) || win.voiceMorph) && notifs.active.length > 0
                sourceComponent: cStack
            }

            // ===================== resting notification (droplet drop-out) =====================
            // At true rest a notification no longer morphs the pill (which hid the
            // clock / dashboard). Instead a water droplet wells out of the pill's
            // bottom lip and *expands into* the notification card floating `dropGap`
            // (a tight 8px) below it: the droplet's final rectangle matches the card's
            // size/colour, and the real card fades in over it on `landed()` so the
            // rectangle becomes the notification. Fires only while `notifRest` (the
            // other stack above owns the open/launcher/voice cases, no droplet); action
            // bursts don't affect it — the droplet deck rests on through a burst.
            Item {
                id: restNotif
                anchors.fill: parent
                z: 900
                readonly property int dropGap: 8
                // the card is revealed when the drop lands (or a short fallback, so a
                // notification always shows even if the droplet is skipped); reset when
                // the resting notification goes away so the next one re-animates.
                property bool cardIn: false

                Timer { id: cardFallback; interval: 640; onTriggered: restNotif.cardIn = true }

                Connections {
                    target: win
                    function onNotifRestChanged() {
                        if (win.notifRest) cardFallback.restart();
                        else { restNotif.cardIn = false; cardFallback.stop(); notifDroplet.reset(); }
                    }
                }
                // a genuine popup arrived: drop a droplet, but only when we're actually
                // at rest (open/launcher/etc. show the deck above without a droplet).
                Connections {
                    target: notifs
                    function onPopped(n) { if (win.notifRest) notifDroplet.play(); }
                }

                // droplet first so it renders BEHIND the deck — the real card fades in
                // over the expanded rect and covers it (both are the card colour).
                NotificationDroplet {
                    id: notifDroplet
                    x: pill.x
                    width: pill.width
                    y: pill.y + pill.height
                    height: restNotif.dropGap
                    theme: theme
                    fallDistance: restNotif.dropGap
                    // expand into the top card's actual footprint / colour
                    cardWidth: restDeck.topCardWidth
                    cardHeight: restDeck.topCardHeight
                    cardRadius: theme.radiusCard
                    bgColor: theme.bg
                    accentColor: theme.accent
                    cardColor: theme.card
                    onLanded: restNotif.cardIn = true
                }

                NotificationStack {
                    id: restDeck
                    // centred under the pill so the deck follows a dragged idle pill
                    // (at the top-centre home this is identical to screen-centre).
                    x: pill.x + (pill.width - width) / 2
                    y: pill.y + pill.height + restNotif.dropGap
                    theme: theme
                    notifs: notifs
                    // just fade in over the droplet's expanded rect (the droplet does
                    // the growth, so no scale here — a scale would fight the expand).
                    // A short lead PAUSE lets the accent rect finish growing to the
                    // card footprint before the card content resolves over it, so the
                    // rectangle reads as *becoming* the notification.
                    opacity: (win.notifRest && restNotif.cardIn) ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity {
                        SequentialAnimation {
                            PauseAnimation { duration: 150 }
                            NumberAnimation { duration: theme.anim; easing.type: Easing.OutCubic }
                        }
                    }
                }
            }

            // ===================== power confirmation (full-screen) =====================
            // Full-screen shutdown / reboot / logout confirmation — four interchangeable
            // designs, selected per-open by theme.confirmation (see PowerConfirm.qml).
            // Nothing runs unless confirmed; Escape / "no" backs out, Enter confirms.
            PowerConfirm {
                anchors.fill: parent
                z: 1000
                theme: theme
                active: win.confirmActive
                action: win.confirmAction
                msg: win.confirmMsg
                variant: win.confirmVariant
                clock: root.clockShort
                onConfirmed: win.confirm()
                onCancelled: win.cancelConfirm()
            }
    
        }
    
    }
    
    // ---- menu components ----
    Component { id: cNet;  NetworkMenu   { theme: theme; netState: netState } }
    Component { id: cVol;  VolumeMenu    { theme: theme; settings: settings; setup: voiceSetup } }
    Component { id: cBt;   BluetoothMenu { theme: theme } }
    Component { id: cBatt; BatteryMenu   { theme: theme; brightness: brightness } }
    Component { id: cClip; ClipboardMenu { theme: theme; clip: clipboard; memos: memos } }
    Component { id: cCal;  CalendarMenu  { theme: theme; org: orgAgenda; fin: finance; cal: calEvents } }
    Component { id: cFin;  FinanceMenu   { theme: theme; fin: finance } }
    Component { id: cTetris; TetrisMenu   { theme: theme; settings: settings } }
    Component { id: cBlockBlast; BlockBlastMenu { theme: theme; settings: settings } }
    Component { id: cGames; GamesMenu { theme: theme; settings: settings } }
    Component { id: cBrickBreaker; BrickBreakerMenu { theme: theme; settings: settings } }
    Component { id: cSnake; SnakeMenu { theme: theme; settings: settings } }
    Component { id: cSettings; SettingsMenu { theme: theme; acc: accounts; settings: settings; themeSettings: themeAdapter } }
    Component { id: cVoice; VoiceMemoMenu { theme: theme; settings: settings; setup: voiceSetup } }
    Component { id: cNotif; NotificationHistory { theme: theme; notifs: notifs } }
    // the active-notification deck, reused for the pill morph and the floating stack
    Component { id: cStack; NotificationStack { theme: theme; notifs: notifs } }
    
    // ---- clock ----
    SystemClock { id: sysclock; precision: SystemClock.Minutes }
    readonly property string clockShort: Qt.formatDateTime(sysclock.date, "hh:mm")
    readonly property string clockDate:  Qt.formatDateTime(sysclock.date, "ddd, d MMM")

    // ==================== capture canvas (screenshot + record) ==============
    // The FULL-SCREEN part only — frozen grab + region select + annotations
    // (screenshot), transparent region + webcam (record). The CONTROLS live in the
    // pill (capture morph, below). Declared BEFORE the pill Variants so it maps
    // first and the pill stacks ON TOP of it (both Overlay) — the pill shows the
    // toolbar / record settings over this canvas. No REC timer here (the pill's
    // capture button stops recording). See CAPTURE.md.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: capWin
            required property var modelData
            screen: modelData

            // hidden while "grabbing" so the grabber captures the real desktop, not
            // our own overlay; hidden while "recording" the pill collapses but the
            // canvas stays for the webcam — mask makes all-but-webcam click-through.
            visible: capture.active && capture.mode !== "grabbing"
            color: "transparent"
            // Top (NOT Overlay): the pill is Overlay and is mapped permanently, so an
            // Overlay canvas mapped on-demand would stack ABOVE the pill and hide the
            // in-pill toolbar. Top sits above normal windows but BELOW the pill.
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "pill-capture"
            exclusionMode: ExclusionMode.Ignore
            // keyboard for screenshot editing + record config (Escape, Ctrl+C/S), but
            // NOT while recording (the user is working in real apps).
            WlrLayershell.keyboardFocus: (capture.active && capture.mode !== "recording")
                                         ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            anchors { top: true; bottom: true; left: true; right: true }

            // while recording the canvas only carries the (non-interactive) webcam,
            // so make the whole thing click-through; otherwise it's fully interactive.
            mask: capture.mode === "recording" ? capEmptyRegion : null
            Region { id: capEmptyRegion }        // no items -> click-through

            CaptureOverlay {
                id: capOv
                anchors.fill: parent
                visible: !capture.isRecord
                focus: !capture.isRecord
                state: capture
                theme: theme
            }
            RecordCanvas {
                id: capRecCv
                anchors.fill: parent
                visible: capture.isRecord
                focus: capture.isRecord && capture.mode === "recConfig"
                state: capture
                theme: theme
                rc: capRec
            }
        }
    }
}
