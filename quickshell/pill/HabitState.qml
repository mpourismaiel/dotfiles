pragma ComponentBehavior: Bound
// HabitState.qml — habiq habit-tracker state over habiqbridge.py. Instantiated
// once in init.qml as `HabitState { id: habitState; enabled: settings.habitsEnabled;
// habitsDir: settings.habitsDir }` and shared with the habit menu + the
// calendar/finance header buttons. All logic (streaks, scores, freezes, tree
// seeds) lives in the habiq CLI; this object only fetches its JSON and fires
// write commands. Best-effort: empty data + `error` when habiq is unreachable.
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    // ---- feature gate (launcher Settings → Habit Tracker) ----
    property bool enabled: false
    property string habitsDir: ""         // journal directory ("" → habiq's default)

    // ---- data (shapes documented in habiqbridge.py / habiq README) ----
    property var report: null             // `weeks` — rows[].weeks[] + weekTotals[]
    property var habits: []               // `habit list` — definitions
    property var freezes: []              // `freeze list` — freeze dialog rows
    property var history: []              // last `history HABIT` result
    property string historyHabit: ""      // which habit `history` belongs to
    property string error: ""             // last read error ("" = fine)
    readonly property bool loading: weeksProc.running
    readonly property bool writing: writeProc.running

    signal writeDone(bool ok, string error)   // any write command finished

    function bridge(args) {
        var base = ["python", Quickshell.shellPath("habiqbridge.py")];
        if (root.habitsDir) base = base.concat(["--dir", root.habitsDir]);
        return base.concat(args);
    }

    // ---- reads ----
    function reload() {
        if (!root.enabled) { root.report = null; return; }
        weeksProc.command = root.bridge(["weeks", "26"]);
        if (!weeksProc.running) weeksProc.running = true;
        habitsProc.command = root.bridge(["habits"]);
        if (!habitsProc.running) habitsProc.running = true;
        freezesProc.command = root.bridge(["freezes"]);
        if (!freezesProc.running) freezesProc.running = true;
    }
    function loadHistory(habitId) {
        root.historyHabit = habitId;
        historyProc.command = root.bridge(["history", habitId]);
        historyProc.running = false;
        historyProc.running = true;
    }

    // ---- writes (each refreshes the report + open history on success) ----
    function logEntry(habit, date, value, reason) {
        _write(["log", habit, date, value || "", reason || ""]);
    }
    function missEntry(habit, date, reason) {
        _write(["miss", habit, date, reason || ""]);
    }
    function editEntry(habit, date, index, value, reason) {
        _write(["edit", habit, date, String(index), value, reason || ""]);
    }
    function deleteEntry(habit, date, index) {
        _write(["delete", habit, date, String(index)]);
    }
    function addFreeze(start, end, habit, note) {
        _write(["freeze-add", start, end, habit || "", note || ""]);
    }
    function removeFreeze(index) {
        _write(["freeze-remove", String(index)]);
    }
    function unfreeze() {
        _write(["unfreeze"]);
    }
    function addHabit(spec) {
        _write(["habit-add", JSON.stringify(spec)]);
    }
    function initJournal() {
        _write(["init"]);
    }
    function _write(args) {
        writeProc.command = root.bridge(args);
        writeProc.running = false;
        writeProc.running = true;
    }

    onEnabledChanged: reload()
    onHabitsDirChanged: if (enabled) reload()

    property Process weeksProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(text);
                    root.report = d;
                    root.error = d && d.error ? d.error : "";
                } catch (e) {
                    root.report = null;
                    root.error = "bad bridge output";
                }
            }
        }
    }
    property Process habitsProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.habits = JSON.parse(text) || []; } catch (e) { root.habits = []; }
            }
        }
    }
    property Process freezesProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.freezes = JSON.parse(text) || []; } catch (e) { root.freezes = []; }
            }
        }
    }
    property Process historyProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.history = JSON.parse(text) || []; } catch (e) { root.history = []; }
            }
        }
    }
    property Process writeProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                var ok = false, err = "";
                try {
                    var d = JSON.parse(text);
                    ok = !!(d && d.ok);
                    err = (d && d.error) || "";
                } catch (e) {
                    err = "bad bridge output";
                }
                if (ok) {
                    root.reload();
                    if (root.historyHabit) root.loadHistory(root.historyHabit);
                }
                root.writeDone(ok, err);
            }
        }
    }
}
