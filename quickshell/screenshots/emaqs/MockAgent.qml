pragma ComponentBehavior: Bound
// MockAgent.qml — a stand-in for AgentBridge.qml used by the screenshot harness.
// All fields are writable so the harness grabber can flip the collapsed-tab
// state (permission card / finished line / working dots / idle) between grabs.
import QtQuick

QtObject {
    property bool dnd: false
    property int workingCount: 0
    property var workingList: []              // [{ workspace }]
    property var permissionNotif: null        // { id, title, body, actions:[[key,label]] }
    property var finishedNotif: null          // { id, title }
    function action(id, key) {}
    function dismiss(id) {}
    function setSession(id, buffer, kind, value) {}
}
