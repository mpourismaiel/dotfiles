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
    function editHabit(spec) {
        _write(["habit-edit", JSON.stringify(spec)]);
    }
    function initJournal() {
        _write(["init"]);
    }
    function _write(args) {
        writeProc.command = root.bridge(args);
        writeProc.running = false;
        writeProc.running = true;
    }

    // ---- git sync: the journal directory may be a git repo. The pill offers a
    // status snapshot (dirty / ahead↑ / behind↓) + ONE sync button that pulls
    // (fast-forward only) then pushes. Diverged branches / conflicts are left
    // for a terminal — the strip only reports them. gitInfo.repo === false
    // (the default, and whenever the dir isn't a repo) hides the whole strip. --
    property var gitInfo: ({ repo: false })
    property bool gitBusy: false
    property string gitError: ""
    function loadGit() {
        if (!root.enabled) { root.gitInfo = ({ repo: false }); return; }
        gitStatusProc.command = root.bridge(["git-status"]);
        gitStatusProc.running = false;
        gitStatusProc.running = true;
    }
    function gitSync() {
        if (root.gitBusy || !root.enabled) return;
        root.gitBusy = true;
        root.gitError = "";
        gitSyncProc.command = root.bridge(["git-sync"]);
        gitSyncProc.running = false;
        gitSyncProc.running = true;
    }
    property Process gitStatusProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.gitInfo = JSON.parse(this.text) || { repo: false }; }
                catch (e) { root.gitInfo = { repo: false }; }
            }
        }
    }
    property Process gitSyncProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                root.gitBusy = false;
                var r = null;
                try { r = JSON.parse(this.text); } catch (e) { r = null; }
                if (r && r.ok) {
                    if (r.pulled) root.reload();   // remote brought new entries → re-render
                } else {
                    root.gitError = (r && r.error) ? r.error : "sync failed";
                }
                root.loadGit();
            }
        }
    }

    onEnabledChanged: { reload(); loadGit(); }
    onHabitsDirChanged: if (enabled) { reload(); loadGit(); }

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
                    root.loadGit();   // logging left the repo dirty / ahead
                    if (root.historyHabit) root.loadHistory(root.historyHabit);
                }
                root.writeDone(ok, err);
            }
        }
    }
}
