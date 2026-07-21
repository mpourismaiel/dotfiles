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
    function loadDay(key) {}
    function loadRange(a, b) {}
    function openAgenda(key) {}
    function toggleDone(file, pos) {}
    function hasItems(key) { return false; }
    function allDone(key) { return false; }
}
