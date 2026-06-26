pragma ComponentBehavior: Bound
// PillToggle.qml — a small themed on/off switch. Reusable across menus.
import QtQuick

Item {
    id: root
    required property var theme
    property bool checked: false
    signal toggled(bool value)

    implicitWidth: 12
    implicitHeight: 20

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? root.theme.accent : root.theme.bgHover
        border.color: root.checked ? root.theme.accent : root.theme.border
        border.width: 1
        Behavior on color { ColorAnimation { duration: root.theme.animFast } }

        Rectangle {
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
