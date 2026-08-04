pragma ComponentBehavior: Bound
// OrgAgenda.qml — Org-agenda state over orgbridge.py (Emacs daemon via emacsclient).
// Instantiated once in init.qml as `OrgAgenda { id: orgAgenda }` and shared with the
// calendar menu. loadDay(key) fills dayItems for a day; loadRange(a,b) fills rangeDays
// with the dates in [a,b] that have entries (calendar dots); openAgenda(key) opens the
// agenda in Emacs. Best-effort — empty if Emacs is unreachable.
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    // ---- feature gate (launcher Settings → Org Agenda) ----
    // enabled=false → no orgbridge calls at all, and the model stays empty so the
    // calendar dots, agenda list and deadline under-line all go dark. agendaDir, when
    // set, is passed to orgbridge as `--dir` and overrides Emacs's org-agenda-files,
    // so the pill isn't tied to one machine's org config.
    property bool enabled: false
    property string agendaDir: ""
    // orgbridge invocation with the optional dir override prepended.
    function _cmd(args) {
        var base = ["python", Quickshell.shellPath("orgbridge.py")];
        if (root.agendaDir) base = base.concat(["--dir", root.agendaDir]);
        return base.concat(args);
    }
    // reloading whatever's live, or dropping everything when the feature is turned off.
    onEnabledChanged: {
        if (root.enabled) { root.loadDeadlines(); root.refresh(); }
        else { root.dayItems = []; root.rangeDays = []; root.rangeMap = ({}); root.deadlines = []; }
    }
    onAgendaDirChanged: if (root.enabled) { root.loadDeadlines(); root.refresh(); }

    property string dayKey: ""            // day currently loaded ("YYYY-MM-DD")
    property var dayItems: []             // [{ text, todo, type, priority, done, dated, file, pos }] for dayKey
    property var rangeDays: []            // [{ date, done }, …] within the loaded range that have dated entries
    property var rangeMap: ({})           // date -> allDone (every dated entry that day is done)
    property string rangeA: ""            // last loaded range bounds, so the poll can refresh it
    property string rangeB: ""

    // ---- deadline watch (the collapsed pill's under-line + the deadlines popup) ----
    // Every undone DEADLINE todo due within `aheadDays`, sorted most-overdue-first.
    // Each item is a dayItem shape plus `delta` (deadline-day − today: <0 overdue,
    // 0 due today, >0 ahead) and `date` (the deadline's ISO date). Loaded from
    // orgbridge `deadlines`, polled on a timer, and reloaded after a toggle.
    property int  aheadDays: 30
    property var  deadlines: []
    // three buckets by delta, in the popup's display order (late → today → ahead).
    readonly property var lateItems:  deadlines.filter(function (d) { return d.delta < 0; })
    readonly property var todayItems: deadlines.filter(function (d) { return d.delta === 0; })
    readonly property var aheadItems: deadlines.filter(function (d) { return d.delta > 0; })
    readonly property int lateCount:  lateItems.length
    readonly property int todayCount: todayItems.length
    readonly property int aheadCount: aheadItems.length
    // the under-line only appears for things that are actually due/overdue.
    readonly property bool hasDue: (lateCount + todayCount) > 0

    function loadDay(key) {
        root.dayKey = key;
        if (!root.enabled) { root.dayItems = []; return; }
        dayProc.command = root._cmd(["day", key]);
        if (!dayProc.running) dayProc.running = true;
    }
    function loadRange(a, b) {
        root.rangeA = a; root.rangeB = b;
        if (!root.enabled) { root.rangeDays = []; root.rangeMap = ({}); return; }
        rangeProc.command = root._cmd(["range", a, b]);
        if (!rangeProc.running) rangeProc.running = true;
    }
    // re-pull whatever's currently shown (day list + month dots) without any UI
    // action, so entries added in Emacs surface on their own. No-op for the parts
    // that were never loaded yet.
    function refresh() {
        if (root.dayKey) root.loadDay(root.dayKey);
        if (root.rangeA && root.rangeB) root.loadRange(root.rangeA, root.rangeB);
    }
    function openAgenda(key) {
        if (!root.enabled) return;
        openProc.command = root._cmd(["open", key]);
        if (!openProc.running) openProc.running = true;
    }
    // (re)load the deadline watch list; called on a timer, on popup open, and after
    // a toggle. Skips if a fetch is already in flight so the timer can't stack them.
    function loadDeadlines() {
        if (!root.enabled) { root.deadlines = []; return; }
        if (deadlinesProc.running) return;
        deadlinesProc.command = root._cmd(["deadlines", "" + root.aheadDays]);
        deadlinesProc.running = true;
    }
    // open FILE at headline POS in a visible Emacs frame (the popup's "open" action).
    function gotoItem(file, pos) {
        if (!root.enabled || !file || gotoProc.running) return;
        gotoProc.command = root._cmd(["goto", file, "" + pos]);
        gotoProc.running = true;
    }
    // flip a headline's TODO/DONE state (file+pos come from the loaded item),
    // then reload the current day so the list re-sorts (done drops to the end).
    function toggleDone(file, pos) {
        if (!root.enabled || !file || toggleProc.running) return;
        toggleProc.command = root._cmd(["toggle", file, "" + pos]);
        toggleProc.running = true;
    }
    function hasItems(key) { return root.rangeMap.hasOwnProperty(key); }
    // true only when the day has dated entries and they are all done
    function allDone(key) { return root.rangeMap[key] === true; }

    property Process dayProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.dayItems = JSON.parse(this.text) || []; }
                catch (e) { root.dayItems = []; }
            }
        }
    }
    property Process rangeProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                var arr = [];
                try { arr = JSON.parse(this.text) || []; }
                catch (e) { arr = []; }
                var m = {};
                for (var i = 0; i < arr.length; i++)
                    m[arr[i].date] = (arr[i].done === true);
                root.rangeMap = m;
                root.rangeDays = arr;
            }
        }
    }
    property Process openProc: Process {}
    property Process gotoProc: Process {}
    property Process deadlinesProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.deadlines = JSON.parse(this.text) || []; }
                catch (e) { root.deadlines = []; }
            }
        }
    }
    property Process toggleProc: Process {
        // reload once Emacs has flipped + saved, but give the row's tick / strike
        // animation a beat to finish before the model rebuilds and re-sorts.
        stdout: StdioCollector {
            onStreamFinished: reloadTimer.restart()
        }
    }
    property Timer reloadTimer: Timer {
        interval: 260
        onTriggered: { root.loadDay(root.dayKey); root.loadDeadlines(); }
    }
    // keep the deadline watch warm: fetch on startup and re-poll every 5 minutes
    // (dates roll over, deadlines pass) so the under-line stays current on its own.
    property Timer deadlinesPoll: Timer {
        interval: 300000
        running: root.enabled
        repeat: true
        triggeredOnStart: true
        onTriggered: root.loadDeadlines()
    }
    // keep the agenda day list + month dots current too: re-pull the loaded day and
    // range every 10 minutes so entries added in Emacs appear without reopening the
    // calendar. Bindings on dayItems/rangeDays update the open menu reactively.
    property Timer agendaPoll: Timer {
        interval: 600000
        running: root.enabled
        repeat: true
        onTriggered: root.refresh()
    }
}
