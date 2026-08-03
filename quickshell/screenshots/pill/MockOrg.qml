pragma ComponentBehavior: Bound
// MockOrg.qml — stand-in for OrgAgenda.qml (screenshot harness). Static agenda for
// the selected day; hasItems/allDone return false (no per-cell dots without keys).
import QtQuick

QtObject {
    id: root
    property var dayItems: [
        { text: "Ship pill + emaqs screenshots", todo: "TODO", done: false, dated: true,  type: "scheduled", priority: "A", file: "/home/mahdi/org/todo.org", pos: 120 },
        { text: "Refactor pill: extract shared components", todo: "TODO", done: false, dated: true, type: "deadline", priority: "B", file: "/home/mahdi/org/todo.org", pos: 240 },
        { text: "Review Quickshell 0.3 release notes", todo: "TODO", done: true, dated: false, type: "", priority: "", file: "/home/mahdi/org/todo.org", pos: 360 },
        { text: "Weekly review", todo: "", done: false, dated: false, type: "", priority: "C", file: "/home/mahdi/org/notes.org", pos: 12 }
    ]
    // ---- deadline watch (mirrors OrgAgenda's deadlines buckets) ----
    // delta = deadline-day − today: <0 overdue ("late"), 0 due today, >0 ahead.
    readonly property var deadlines: [
        { text: "Refactor pill: extract shared components", delta: -9, priority: "B", date: "2026-07-25", file: "/home/mahdi/org/todo.org",  pos: 240 },
        { text: "Review Quickshell 0.3 release notes",      delta: -4, priority: "",  date: "2026-07-30", file: "/home/mahdi/org/todo.org",  pos: 360 },
        { text: "Renew domain",                             delta: -1, priority: "A", date: "2026-08-02", file: "/home/mahdi/org/todo.org",  pos: 400 },
        { text: "Ship pill + emaqs screenshots",            delta:  0, priority: "A", date: "2026-08-03", file: "/home/mahdi/org/todo.org",  pos: 120 },
        { text: "Weekly review",                            delta:  0, priority: "C", date: "2026-08-03", file: "/home/mahdi/org/notes.org", pos:  12 },
        { text: "Invoice for July",                         delta:  1, priority: "B", date: "2026-08-04", file: "/home/mahdi/org/todo.org",  pos: 500 },
        { text: "Prepare board deck",                       delta:  5, priority: "A", date: "2026-08-08", file: "/home/mahdi/org/todo.org",  pos: 620 },
        { text: "Team offsite notes",                       delta:  5, priority: "",  date: "2026-08-08", file: "/home/mahdi/org/notes.org", pos:  80 },
        { text: "Pay rent",                                 delta:  9, priority: "A", date: "2026-08-12", file: "/home/mahdi/org/todo.org",  pos: 520 },
        { text: "Quarterly report",                         delta: 20, priority: "C", date: "2026-08-23", file: "/home/mahdi/org/todo.org",  pos: 560 }
    ]
    readonly property var lateItems:  deadlines.filter(function (d) { return d.delta < 0; })
    readonly property var todayItems: deadlines.filter(function (d) { return d.delta === 0; })
    readonly property var aheadItems: deadlines.filter(function (d) { return d.delta > 0; })
    readonly property int lateCount:  lateItems.length
    readonly property int todayCount: todayItems.length
    readonly property int aheadCount: aheadItems.length
    readonly property bool hasDue: (lateCount + todayCount) > 0

    function loadDay(key) {}
    function loadRange(a, b) {}
    function openAgenda(key) {}
    function toggleDone(file, pos) {}
    function gotoItem(file, pos) {}
    function loadDeadlines() {}
    function hasItems(key) { return false; }
    function allDone(key) { return false; }
}
