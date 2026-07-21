pragma ComponentBehavior: Bound
// MockEmacs.qml — a stand-in for EmaqsBridge.qml used by the screenshot harness.
// Exposes exactly the surface init.qml reads (names / currentIdx / bufferGroups)
// plus no-op methods, so the real pill body renders against deterministic data
// without an Emacs daemon or any DBus/process activity.
import QtQuick

QtObject {
    property var names: ["MAIN", "AWESOME", "DOOM", "EMAQS", "SCRATCH"]
    property int currentIdx: 1
    property var bufferGroups: [
        { group: "Files", items: ["init.qml", "qs-emaqs-docs.org", "Theme.qml"] },
        { group: "Ghostel", items: ["*ghostel:build*", "*ghostel:run*"] },
        { group: "Agent Shell", items: ["*claude: refactor pill*", "*claude: write tests*"] }
    ]
    function loadWorkspaces() {}
    function loadBuffers(ws) {}
    function switchTo(ws) {}
    function openBuffer(name, ws) {}
    function magit(ws) {}
    function closeWorkspace(ws) {}
}
