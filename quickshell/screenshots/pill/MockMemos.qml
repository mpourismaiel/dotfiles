pragma ComponentBehavior: Bound
// MockMemos.qml — stand-in for Memos.qml (screenshot harness). A couple of static
// voice memos so the clipboard menu's Memos tab renders; every action is a no-op.
import QtQuick

QtObject {
    id: root
    property var entries: [
        { id: "20260722-094100", created: "2026-07-22 09:41", type: "note", polished: true,
          text: "Remember to extract the shared MonthGrid component from the calendar and finance menus." },
        { id: "20260721-183000", created: "2026-07-21 18:30", type: "todo", polished: false,
          text: "book the dentist appointment for next week" }
    ]
    function refresh() {}
    function copyText(s) {}
    function copy(id) {}
    function remove(id) {}
    function repolish(id) {}
}
