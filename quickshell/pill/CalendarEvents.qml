pragma ComponentBehavior: Bound
// CalendarEvents.qml — Google Calendar state over gcalbridge.py (KDE Online Accounts
// + signond). Instantiated once in init.qml as `CalendarEvents { id: calEvents }` and
// shared with the calendar menu (mirrors OrgAgenda / FinanceState). read() loads the
// cache with no network I/O; fetch()/fetch(a,b) refresh it from Google (hourly Timer +
// refetch button). dayEvents(key) / hasEvents(key) filter the cached window client-side.
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property var events: []            // normalized events across all accounts
    property var dayMap: ({})          // "YYYY-MM-DD" -> true (any event that day)
    property bool loading: false
    property string lastError: ""      // first error from the last fetch, if any
    property string fetched: ""        // "YYYY-MM-DD HH:MM" of the last fetch
    property var accounts: []          // account display names seen last fetch
    property string winStart: ""       // cached window bounds (drive ensureCovers)
    property string winEnd: ""

    function _ingest(text) {
        var env = null;
        try { env = JSON.parse(text); } catch (e) { env = null; }
        if (!env) return;
        root.events = env.events || [];
        var m = {};
        for (var i = 0; i < root.events.length; i++) {
            var ds = root.events[i].days || [];
            for (var j = 0; j < ds.length; j++) m[ds[j]] = true;
        }
        root.dayMap = m;
        root.accounts = env.accounts || [];
        if (env.window) { root.winStart = env.window[0]; root.winEnd = env.window[1]; }
        if (env.fetched) root.fetched = env.fetched;
        root.lastError = (env.errors && env.errors.length) ? ("" + env.errors[0]) : "";
    }

    // load the cache without touching the network (menu open / startup)
    function read() {
        readProc.command = ["python", Quickshell.shellPath("gcalbridge.py"), "read"];
        if (!readProc.running) readProc.running = true;
    }
    // refresh from Google. Optional A/B extend the fetched window.
    function fetch(a, b) {
        if (fetchProc.running) return;
        var cmd = ["python", Quickshell.shellPath("gcalbridge.py"), "fetch"];
        if (a && b) { cmd.push(a); cmd.push(b); }
        fetchProc.command = cmd;
        root.loading = true;
        fetchProc.running = true;
    }
    // trigger a fetch only when the shown grid falls outside the cached window,
    // growing the window to cover both the old span and the newly-requested one.
    function ensureCovers(a, b) {
        if (fetchProc.running) return;
        var haveWin = root.winStart !== "" && root.winEnd !== "";
        if (!haveWin || a < root.winStart || b > root.winEnd) {
            var na = (haveWin && root.winStart < a) ? root.winStart : a;
            var nb = (haveWin && root.winEnd > b) ? root.winEnd : b;
            root.fetch(na, nb);
        }
    }

    function hasEvents(key) { return root.dayMap.hasOwnProperty(key); }
    // the selected day's events (client-side filter of the cached window)
    function dayEvents(key) {
        var out = [];
        for (var i = 0; i < root.events.length; i++) {
            var ds = root.events[i].days || [];
            if (ds.indexOf(key) !== -1) out.push(root.events[i]);
        }
        return out;
    }

    property Process readProc: Process {
        stdout: StdioCollector { onStreamFinished: root._ingest(this.text) }
    }
    property Process fetchProc: Process {
        stdout: StdioCollector { onStreamFinished: root._ingest(this.text) }
        onRunningChanged: if (!running) root.loading = false
    }
    // hourly background refresh (default window)
    property Timer hourly: Timer {
        interval: 3600 * 1000
        repeat: true
        running: true
        onTriggered: root.fetch()
    }
    // one fetch shortly after start-up, so sign-in doesn't race the shell coming up
    property Timer startup: Timer {
        interval: 4000
        running: true
        onTriggered: root.fetch()
    }
    Component.onCompleted: root.read()
}
