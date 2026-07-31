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
    property string dayKey: ""            // day currently loaded ("YYYY-MM-DD")
    property var dayItems: []             // [{ text, todo, type, priority, done, dated, file, pos }] for dayKey
    property var rangeDays: []            // [{ date, done }, …] within the loaded range that have dated entries
    property var rangeMap: ({})           // date -> allDone (every dated entry that day is done)

    function loadDay(key) {
        root.dayKey = key;
        dayProc.command = ["python", Quickshell.shellPath("orgbridge.py"), "day", key];
        if (!dayProc.running) dayProc.running = true;
    }
    function loadRange(a, b) {
        rangeProc.command = ["python", Quickshell.shellPath("orgbridge.py"), "range", a, b];
        if (!rangeProc.running) rangeProc.running = true;
    }
    function openAgenda(key) {
        openProc.command = ["python", Quickshell.shellPath("orgbridge.py"), "open", key];
        if (!openProc.running) openProc.running = true;
    }
    // flip a headline's TODO/DONE state (file+pos come from the loaded item),
    // then reload the current day so the list re-sorts (done drops to the end).
    function toggleDone(file, pos) {
        if (!file || toggleProc.running) return;
        toggleProc.command = ["python", Quickshell.shellPath("orgbridge.py"), "toggle", file, "" + pos];
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
    property Process toggleProc: Process {
        // reload once Emacs has flipped + saved, but give the row's tick / strike
        // animation a beat to finish before the model rebuilds and re-sorts.
        stdout: StdioCollector {
            onStreamFinished: reloadTimer.restart()
        }
    }
    property Timer reloadTimer: Timer {
        interval: 260
        onTriggered: root.loadDay(root.dayKey)
    }
}
