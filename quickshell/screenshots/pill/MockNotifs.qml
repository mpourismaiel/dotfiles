pragma ComponentBehavior: Bound
// MockNotifs.qml — stand-in for Notifications.qml (screenshot harness). Builds a few
// notification QtObjects (all fields the views read) and exposes grouped/active +
// the aggregate/no-op methods. No NotificationServer is instantiated, so the harness
// can never contend for org.freedesktop.Notifications.
import QtQuick

Item {
    id: root
    property var grouped: []
    property var active: []
    property bool held: false
    property bool dnd: false
    property int unreadCount: 3
    readonly property var current: active.length ? active[0] : null
    readonly property bool anyReply: active.some(n => n && n.hasInlineReply)

    function rebuild() {}
    function clearAll() {}
    function clearGroup(g) {}
    function hold(v) {}
    function dismissAll() {}
    function dismiss(n) {}
    function forget(n) {}
    function drop(n) {}
    function timeoutFor(n) { return 5000; }
    function progressFor(n) { return 0.62; }
    function relTime(id) { return id === "1" ? "just now" : id === "2" ? "4m ago" : "1h ago"; }

    component Notif: QtObject {
        property string id: ""
        property string summary: ""
        property string appName: ""
        property string appIcon: ""
        property string body: ""
        property string image: ""
        property var hints: ({})
        property int urgency: 1
        property var actions: []
        property bool hasInlineReply: false
        property string inlineReplyPlaceholder: ""
        function sendInlineReply(t) {}
    }
    Component { id: nc; Notif {} }
    Component.onCompleted: {
        const n1 = nc.createObject(root, { id: "1", summary: "Build passed", appName: "CI",
            appIcon: "emblem-default", body: "awesome-pill #482 passed in 3m 12s", urgency: 1 });
        const n2 = nc.createObject(root, { id: "2", summary: "New message from Sara", appName: "Signal",
            appIcon: "signal-desktop", body: "Are we still on for the design review at 3?", urgency: 1,
            hasInlineReply: true, inlineReplyPlaceholder: "Reply to Sara…",
            actions: [{ identifier: "reply", text: "Reply", invoke: function () {} }] });
        const n3 = nc.createObject(root, { id: "3", summary: "Battery low", appName: "Power",
            appIcon: "battery-caution", body: "15% remaining — plug in soon.", urgency: 2,
            actions: [{ identifier: "default", text: "", invoke: function () {} },
                      { identifier: "settings", text: "Settings", invoke: function () {} }] });
        root.active = [n3, n2, n1];
        root.grouped = [
            { app: "Signal", items: [n2] },
            { app: "CI",     items: [n1] },
            { app: "Power",  items: [n3] }
        ];
    }
}
