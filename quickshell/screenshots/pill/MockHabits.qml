// MockHabits.qml — stand-in for HabitState (screenshot harness only): a
// deterministic 8-week habiq report pinned to 2026-09-12 so the jungle renders
// identically on every run — no habiq binary, no Process, no journal. Shapes
// mirror `habiq weeks --json` (see the habiq README + habiqbridge.py). The
// garden is tuned to show every visual state: a fully frozen vacation week
// (W34), a dead books tree (W32), a young "stretching" habit (current week
// only) and a mid-growth current week.
import QtQuick

QtObject {
    id: root
    property bool enabled: true
    property string habitsDir: "~/Documents/habits"
    property string error: ""
    readonly property bool loading: false
    readonly property bool writing: false
    signal writeDone(bool ok, string error)

    function reload() {}
    function loadGit() {}
    function gitSync() {}
    // stand-in git state: a repo with a couple of changes to sync, so the
    // header's sync strip renders its status text ("1↓ · 2↑ · 1 unsaved")
    property var gitInfo: ({ repo: true, branch: "main", dirty: 1, ahead: 2, behind: 1,
                            last: "a1b2c3d pill: habit entries 2026-09-12" })
    property bool gitBusy: false
    property string gitError: ""
    function initJournal() {}
    function logEntry() { writeDone(true, ""); }
    function missEntry() { writeDone(true, ""); }
    function editEntry() { writeDone(true, ""); }
    function deleteEntry() { writeDone(true, ""); }
    function addFreeze() { writeDone(true, ""); }
    function removeFreeze() { writeDone(true, ""); }
    function unfreeze() { writeDone(true, ""); }
    function addHabit() { writeDone(true, ""); }
    function editHabit() { writeDone(true, ""); }

    property string historyHabit: "reading"
    readonly property var _histBase: [
        { date: "2026-09-01", kind: "log", value: "24", reason: "" },
        { date: "2026-09-03", kind: "log", value: "31", reason: "" },
        { date: "2026-09-05", kind: "miss", value: "", reason: "travel" },
        { date: "2026-09-07", kind: "log", value: "18", reason: "" },
        { date: "2026-09-09", kind: "log", value: "42", reason: "long evening" },
        { date: "2026-09-11", kind: "log", value: "32", reason: "" }
    ]
    property var history: []
    function loadHistory(id) {
        // reshape the canned history to the habit's value type (bool → "done")
        var boolish = id === "workout" || id === "hledger" || id === "stretching";
        var out = [];
        for (var i = 0; i < _histBase.length; i++) {
            var e = _histBase[i];
            out.push({
                date: e.date, habit: id, kind: e.kind,
                value: e.kind === "log" ? (boolish ? "done" : e.value) : "",
                reason: e.reason, index: 1
            });
        }
        history = out;
        historyHabit = id;
    }
    Component.onCompleted: loadHistory("reading")

    property var habits: [
        { id: "hledger", name: "hledger update", schedule: "every day", scheduleSpec: "daily", type: "bool", typeRaw: "bool", reward: 1, penalty: 1 },
        { id: "coding", name: "coding / work", schedule: "Mon-Fri", scheduleSpec: "weekdays", type: "hours", typeRaw: "hours", target: "6:00", reward: 1, penalty: 1, offdayPenalty: 2 },
        { id: "workout", name: "workout", schedule: "Mon · Wed · Sat", scheduleSpec: "mon wed sat", type: "bool", typeRaw: "bool", reward: 4, penalty: 4 },
        { id: "reading", name: "reading", schedule: "freeform", scheduleSpec: "freeform", type: "pages", typeRaw: "count", unit: "pages", target: "20", reward: 3, penalty: 3, group: "books" },
        { id: "listening", name: "listening", schedule: "freeform", scheduleSpec: "freeform", type: "hh:mm:ss", typeRaw: "duration", target: "0:30:00", reward: 3, penalty: 3, group: "books" },
        { id: "stretching", name: "stretching", schedule: "every day", scheduleSpec: "daily", type: "bool", typeRaw: "bool", reward: 1, penalty: 1 }
    ]
    property var freezes: [
        { index: 1, start: "2026-08-17", end: "2026-08-23", habit: "", note: "vacation" }
    ]

    property var report: _buildReport()

    function _rng(seed) {
        var a = seed >>> 0;
        return function () {
            a |= 0; a = (a + 0x6D2B79F5) | 0;
            var t = Math.imul(a ^ (a >>> 15), 1 | a);
            t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
            return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
        };
    }

    function _buildReport() {
        // pinned clock: Saturday 2026-09-12, ISO week 37 (Mon 2026-09-07)
        var todayStr = "2026-09-12";
        var mondays = [];
        for (var wi = 7; wi >= 0; wi--) {
            var m = new Date("2026-09-07T12:00:00");
            m.setDate(m.getDate() - wi * 7);
            mondays.push({ d: m, wi: wi });
        }
        function isoStr(d) {
            var p = function (n) { return (n < 10 ? "0" : "") + n; };
            return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate());
        }
        function weekKey(m) {
            // fixed range: W30..W37 of 2026
            return "2026-W" + (37 - m.wi);
        }
        function season(m) {
            var mo = new Date(m.d.getTime() + 3 * 86400000).getMonth() + 1;
            return (mo >= 3 && mo <= 5) ? "spring" : (mo >= 6 && mo <= 8) ? "summer"
                 : (mo >= 9 && mo <= 11) ? "fall" : "winter";
        }
        var rowsSpec = [
            { id: "hledger", name: "hledger update", members: ["hledger"], sched: [0, 1, 2, 3, 4, 5, 6], scheduleLabel: "every day", typeLabel: "bool", freeform: false, reward: 1, q: 0.75 },
            { id: "coding", name: "coding / work", members: ["coding"], sched: [0, 1, 2, 3, 4], scheduleLabel: "Mon-Fri", typeLabel: "hours", freeform: false, reward: 1, q: 0.9 },
            { id: "workout", name: "workout", members: ["workout"], sched: [0, 2, 5], scheduleLabel: "Mon · Wed · Sat", typeLabel: "bool", freeform: false, reward: 4, q: 0.95 },
            { id: "books", name: "books", members: ["reading", "listening"], sched: [0, 1, 2, 3, 4, 5, 6], scheduleLabel: "freeform", typeLabel: "pages + hh:mm:ss", freeform: true, reward: 3, q: 0.55 },
            { id: "stretching", name: "stretching", members: ["stretching"], sched: [0, 1, 2, 3, 4, 5, 6], scheduleLabel: "every day", typeLabel: "bool", freeform: false, reward: 1, q: 0.85, newThisWeek: true }
        ];
        var rows = [], totals = [];
        for (var r = 0; r < rowsSpec.length; r++) {
            var spec = rowsSpec[r];
            var weeks = [];
            var streak = 0;
            for (var w = 0; w < mondays.length; w++) {
                var m = mondays[w];
                if (spec.newThisWeek && m.wi >= 1) continue;
                var rng = root._rng(1000 * r + m.wi * 7 + 5);
                var frozenWeek = m.wi === 4;                    // W33: vacation snow
                var q = (spec.id === "books" && m.wi === 5) ? 0 : spec.q;  // dead tree
                var days = [], net = 0, maxFull = 0, maxElapsed = 0, frozenDays = 0;
                for (var di = 0; di < 7; di++) {
                    var day = new Date(m.d.getTime() + di * 86400000);
                    var key = isoStr(day);
                    var st = "unscheduled", val = "", reason = "", score = 0;
                    if (frozenWeek) {
                        st = "frozen"; frozenDays++;
                    } else if (spec.sched.indexOf(di) >= 0) {
                        maxFull += spec.reward;
                        if (key > todayStr) {
                            st = "pending";
                        } else {
                            maxElapsed += spec.reward;
                            var roll = rng();
                            if (roll < q) {
                                st = "done"; score = spec.reward; net += score; streak++;
                                val = spec.id === "coding" ? "6:12" : spec.id === "books" ? "32" : "done";
                            } else if (roll < q + 0.12) {
                                st = "missed-reason"; reason = "sick";
                                score = spec.freeform ? 0 : -spec.reward; net += score;
                                streak = spec.freeform ? Math.max(0, streak - 1) : 0;
                            } else {
                                st = "missed";
                                score = spec.freeform ? 0 : -spec.reward; net += score;
                                streak = spec.freeform ? Math.max(0, streak - 2) : 0;
                            }
                        }
                    }
                    days.push({ date: key, state: st, value: val, reason: reason, score: score });
                }
                var size = maxFull > 0 ? Math.max(0, Math.min(1, net / maxFull)) : 0;
                var health = maxElapsed > 0 ? Math.max(0, Math.min(1, net / maxElapsed)) : (m.wi === 0 ? 1 : 0);
                var finished = m.wi > 0;
                var band = frozenWeek ? "frozen" : (finished && net <= 0) ? "dead"
                         : health <= 0.33 ? "low" : health <= 0.66 ? "mid" : "high";
                weeks.push({
                    week: weekKey(m), start: isoStr(m.d), end: isoStr(new Date(m.d.getTime() + 6 * 86400000)),
                    season: season(m), seed: (r * 977 + m.wi * 7919 + 13) >>> 0,
                    net: net, maxFull: maxFull, maxElapsed: maxElapsed,
                    sizeRatio: size, healthRatio: health,
                    stage: size < 0.25 ? 1 : size < 0.5 ? 2 : size < 0.75 ? 3 : 4,
                    band: band, frozenDays: frozenDays, streakEnd: streak,
                    finished: finished, days: days
                });
            }
            rows.push({
                id: spec.id, name: spec.name, members: spec.members,
                scheduleLabel: spec.scheduleLabel, typeLabel: spec.typeLabel,
                freeform: spec.freeform, streak: streak, longestStreak: streak + 5,
                noStreak: false, weeks: weeks
            });
        }
        for (var t = 0; t < mondays.length; t++) {
            var mm = mondays[t];
            var key2 = weekKey(mm);
            var net2 = 0, max2 = 0, streaks2 = 0;
            for (var rr = 0; rr < rows.length; rr++)
                for (var ww = 0; ww < rows[rr].weeks.length; ww++)
                    if (rows[rr].weeks[ww].week === key2) {
                        net2 += rows[rr].weeks[ww].net;
                        max2 += rows[rr].weeks[ww].maxFull;
                        streaks2 += rows[rr].weeks[ww].streakEnd;
                    }
            var veg = Math.max(0, Math.min(1, (max2 > 0 ? Math.max(0, net2) / max2 : 0) + Math.min(0.15, 0.005 * streaks2)));
            totals.push({ week: key2, start: isoStr(mm.d), season: season(mm), net: net2, max: max2, vegetation: veg });
        }
        return { today: todayStr, week: "2026-W37", seed: "0", rows: rows, weekTotals: totals };
    }
}
