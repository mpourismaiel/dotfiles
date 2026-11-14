pragma ComponentBehavior: Bound
// UpdateState.qml — system-update state for the pill (updatebridge.py), shared
// by the resting pill's lip line (UpdateLip), the dashboard status icon and the
// Updates page (UpdatesMenu, menu 20). Instantiated once in init.qml.
//
// One long-lived `updatebridge.py watch` process prints a JSON snapshot per line
// whenever anything changes (it also runs the twice-daily check itself and emits
// one-shot {"event":"notify"} lines, re-emitted here as `notify`). Everything the
// user does — check now, start, answer a pacman question, stop, hand over to a
// terminal — is a one-shot bridge command; the result comes back through the
// watcher, never through the command's own output. All state lives in plain files
// under `dir` (see updatebridge.py), so an update keeps running across a reload.
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property bool enabled: true            // settings.updatesEnabled
    property var sources: ["pacman", "flatpak"]   // settings.updateSources
    property string dir: ""                // settings.updatesDir ("" → ~/.local/state/pill/updates)

    // ---- last snapshot ------------------------------------------------------
    property bool ready: false
    property bool checking: false
    property double checkedAt: 0           // ms since epoch (0 = never)
    property double nextAt: 0
    property string error: ""
    property string level: "none"          // none · optional · recommended · required
    property var counts: ({ required: 0, recommended: 0, optional: 0, total: 0 })
    property var packages: []              // [{name, old, new, cls, restart, source, advisory?}]
    property var sourceRows: []            // [{key, label, desc, icon, count, enabled, available, togglable}]
    property var hold: []                  // unread Arch news since the last upgrade
    property string restart: ""            // what installing the pending set will need
    property double downloadBytes: 0
    property real daysBehind: 0
    property var pendingRestart: null      // {level, reasons} after a run, until it happens
    property var run: null                 // the live update run (null when idle)
    property var history: []               // checks + runs, newest first
    property string stateDir: ""
    property string aurHelper: ""

    signal notify(var e)                   // one-shot notification cue from the bridge

    // ---- derived ------------------------------------------------------------
    readonly property bool running: !!run && (run.status === "running" || run.status === "auth")
    readonly property bool asking: !!run && run.status === "asking"
    readonly property bool active: running || asking
    readonly property real progress: run ? Math.max(0, Math.min(1, (run.percent || 0) / 100)) : 0
    readonly property var lastRun: {
        for (var i = 0; i < history.length; i++)
            if (history[i].kind === "update") return history[i];
        return null;
    }
    // a failed run stays the headline state until it is looked at (the Updates
    // page marks it seen), a newer run replaces it, or a day passes.
    property string seenFailed: ""
    readonly property bool failed: !active && !!lastRun && lastRun.status === "failed"
        && lastRun.id !== seenFailed
        && (Date.now() / 1000 - lastRun.at) < 86400
    function markFailedSeen() { if (root.lastRun && root.lastRun.status === "failed") root.seenFailed = root.lastRun.id; }
    readonly property string restartLevel: pendingRestart ? (pendingRestart.level || "") : ""
    // the single state the lip line / status icon render:
    //   asking · running · failed · restart · hold · required · recommended · optional · none
    readonly property string mood: !enabled ? "none"
        : asking ? "asking" : running ? "running" : failed ? "failed"
        : restartLevel !== "" ? "restart"
        : (hold.length > 0 && counts.total > 0) ? "hold"
        : level
    readonly property int includedCount: counts.total || 0

    function restartPhrase(lv) {
        return lv === "reboot" ? "Reboot" : lv === "relogin" ? "Log out" : lv === "pill" ? "Pill restarts" : "";
    }
    function fmtBytes(b) {
        if (!b || b <= 0) return "";
        if (b >= 1073741824) return (b / 1073741824).toFixed(1) + " GB";
        if (b >= 1048576) return Math.round(b / 1048576) + " MB";
        return Math.max(1, Math.round(b / 1024)) + " KB";
    }
    function fmtDuration(s) {
        s = Math.max(0, Math.round(s || 0));
        if (s < 60) return s + " s";
        return Math.floor(s / 60) + " min " + (s % 60 < 10 ? "0" : "") + (s % 60) + " s";
    }

    // ---- bridge plumbing ----------------------------------------------------
    function _base() {
        var c = ["python", Quickshell.shellPath("updatebridge.py")];
        if (root.dir) c = c.concat(["--dir", root.dir]);
        return c.concat(["--sources", (root.sources || []).join(",")]);
    }
    property var _queue: []
    function _send(args) {
        var q = root._queue.slice(); q.push(root._base().concat(args)); root._queue = q;
        root._pump();
    }
    function _pump() {
        if (cmdProc.running || root._queue.length === 0) return;
        var q = root._queue.slice();
        cmdProc.command = q.shift();
        root._queue = q;
        cmdProc.running = true;
    }

    function checkNow()        { if (root.enabled) { root.checking = true; root._send(["check"]); } }
    function start()           { if (root.enabled && !root.active) root._send(["start"]); }
    function answer(value)     { if (root.run) root._send(["answer", root.run.id, "" + value]); }
    function stop()            { if (root.run) root._send(["stop", root.run.id]); }
    function terminal(what)    { root._send(["terminal", what || "repo"]); }
    function ackNews()         { root._send(["ack-news"]); }
    function ackRestart()      { root._send(["ack-restart"]); }
    function openLog(id)       { root._send(["open", id || "-", "log"]); }
    function showFolder(id)    { root._send(["open", id || "-", "folder"]); }

    function _apply(d) {
        root.ready = true;
        root.checking = !!d.checking;
        root.checkedAt = d.checkedAt || 0;
        root.nextAt = d.nextAt || 0;
        root.error = d.error || "";
        root.level = d.level || "none";
        root.counts = d.counts || ({ required: 0, recommended: 0, optional: 0, total: 0 });
        root.packages = d.packages || [];
        root.sourceRows = d.sources || [];
        root.hold = d.hold || [];
        root.restart = d.restart || "";
        root.downloadBytes = d.downloadBytes || 0;
        root.daysBehind = d.daysBehind || 0;
        root.pendingRestart = d.pendingRestart || null;
        root.run = d.run || null;
        root.history = d.history || [];
        root.stateDir = d.dir || "";
        root.aurHelper = d.aurHelper || "";
    }

    property Process watchProc: Process {
        running: root.enabled
        command: root._base().concat(["watch"])
        stdout: SplitParser {
            onRead: line => {
                var d = null;
                try { d = JSON.parse(line); } catch (e) { return; }
                if (!d) return;
                if (d.event === "notify") { root.notify(d); return; }
                if (d.event === "run") { root.run = d.run || null; return; }
                root._apply(d);
            }
        }
    }
    // a changed source set / directory must reach the watcher: restart it
    onSourcesChanged: root._rewatch()
    onDirChanged: root._rewatch()
    function _rewatch() {
        if (!root.enabled || !watchProc.running) return;
        watchProc.running = false;
        rewatchTimer.restart();
    }
    property Timer rewatchTimer: Timer {
        interval: 150
        onTriggered: if (root.enabled) root.watchProc.running = true
    }
    property Process cmdProc: Process {
        onExited: root._pump()
    }
}
