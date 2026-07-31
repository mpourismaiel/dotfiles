pragma ComponentBehavior: Bound
// IconButton.qml — a rounded hover button: an MSym glyph over a fill that fades in on
// hover, emitting clicked(). Caller sets width/height (and radius if not the default
// radiusBtn) plus the icon and colours, so one component serves the magit, close and
// dismiss buttons.
import QtQuick

Rectangle {
    id: root
    required property var theme
    property string icon: ""
    property int iconSize: 18
    property color hoverBg: root.theme.row
    property color restColor: root.theme.faint
    property color hoverColor: root.theme.text
    signal clicked()

    radius: root.theme.radiusBtn
    color: ma.containsMouse ? root.hoverBg : "transparent"
    Behavior on color { ColorAnimation { duration: root.theme.animFast } }

    MSym {
        anchors.centerIn: parent
        icon: root.icon
        size: root.iconSize
        color: ma.containsMouse ? root.hoverColor : root.restColor
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
