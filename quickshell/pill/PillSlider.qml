pragma ComponentBehavior: Bound
// PillSlider.qml — a themed horizontal slider over [0,1]. Reused for volume.
import QtQuick

Item {
    id: root
    required property var theme
    property real value: 0            // 0..1
    signal moved(real value)

    implicitHeight: 16
    implicitWidth: 120

    readonly property real clamped: Math.max(0, Math.min(1, value))

    Rectangle {                       // track
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 6
        radius: 3
        color: root.theme.track

        Rectangle {                   // fill
            width: root.clamped * parent.width
            height: parent.height
            radius: parent.radius
            color: root.theme.accent
        }
    }

    Rectangle {                       // handle
        width: 14
        height: 14
        radius: 7
        color: "white"
        anchors.verticalCenter: parent.verticalCenter
        x: root.clamped * (root.width - width)
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        function apply(mx) {
            const v = Math.max(0, Math.min(1, mx / width));
            root.value = v;
            root.moved(v);
        }
        onPressed: mouse => apply(mouse.x)
        onPositionChanged: mouse => { if (pressed) apply(mouse.x); }
    }
}
