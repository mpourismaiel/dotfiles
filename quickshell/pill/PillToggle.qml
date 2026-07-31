pragma ComponentBehavior: Bound
// PillToggle.qml — a small themed on/off switch. Reusable across menus.
import QtQuick

Item {
    id: root
    required property var theme
    property bool checked: false
    signal toggled(bool value)

    // keyboard nav (MenuKbNav): Enter flips the switch like a click. The track
    // is translucent, so the floating square behind would drown it — the toggle
    // self-styles focus with a bright track border instead (kbFocused).
    readonly property bool kbFocusable: true
    property bool kbFocused: false
    function keyClick() {
        root.checked = !root.checked;
        root.toggled(root.checked);
    }

    implicitWidth: 34
    implicitHeight: 18

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? root.theme.accent : root.theme.track
        border.color: root.kbFocused ? root.theme.text : root.checked ? root.theme.accent : root.theme.border
        border.width: 1
        Behavior on color { ColorAnimation { duration: root.theme.animFast } }

        Rectangle {                       // knob — fits inside the track
            width: parent.height - 4
            height: parent.height - 4
            radius: height / 2
            y: 2
            x: root.checked ? parent.width - width - 2 : 2
            color: "white"
            Behavior on x { NumberAnimation { duration: root.theme.animFast; easing.type: Easing.OutCubic } }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.checked = !root.checked;
            root.toggled(root.checked);
        }
    }
}
