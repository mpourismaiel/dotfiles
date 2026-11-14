pragma ComponentBehavior: Bound
// DiskBtn.qml — the Disk window's text button: uppercase mono label, optional
// leading glyph, hairline outline (or solid accent when `primary`). `on: false`
// greys it out and stops clicks.
import QtQuick

Rectangle {
    id: root
    required property var theme
    property string text: ""
    property string icon: ""
    property bool primary: false
    property bool on: true
    signal clicked()

    implicitWidth: row.implicitWidth + 22
    implicitHeight: 28
    radius: theme.radiusBtn
    color: primary ? (on ? (ma.containsMouse ? Qt.lighter(theme.accent, 1.12) : theme.accent) : theme.track)
                   : (ma.containsMouse && on ? theme.bgHover : "transparent")
    border.width: primary ? 0 : 1
    border.color: theme.borderStrong
    opacity: on ? 1 : 0.45
    Behavior on color { ColorAnimation { duration: root.theme.animFast } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        MSym {
            visible: root.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            icon: root.icon
            size: 14
            color: root.theme.text
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.text.toUpperCase()
            color: root.theme.text
            font.family: root.theme.mono
            font.pixelSize: 10
            font.weight: Font.Medium
            font.letterSpacing: 1
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.on
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
