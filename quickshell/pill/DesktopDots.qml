pragma ComponentBehavior: Bound
// DesktopDots.qml — virtual-desktop dots with a sliding active dot. Used by the
// dashboard Row 1, under the date/time (interactive: dots switch desktop) and the desktop action burst
// (non-interactive: just the slide). activeIdx is the filled dot's slot (-1 hides
// it); switchRequested(id) fires when an interactive dot is clicked.
import QtQuick

Item {
    id: root
    required property var theme
    required property var desktops      // [{ id, name }]
    property int activeIdx: -1          // slot of the filled dot; -1 hides it
    property bool interactive: false    // clickable dots that switch desktop
    signal switchRequested(string id)

    implicitWidth: dotRow.width
    implicitHeight: 9

    Row {
        id: dotRow
        spacing: 4                       // 9px dot + 4 -> pitch 13
        Repeater {
            model: root.desktops
            delegate: Rectangle {
                required property var modelData
                width: 9; height: 9; radius: 4.5
                color: "transparent"
                border.color: root.theme.faint
                border.width: 1.5
                MouseArea {
                    anchors.fill: parent
                    enabled: root.interactive
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.switchRequested(modelData.id)
                }
            }
        }
    }
    Rectangle {                          // active indicator, slides on switch
        width: 9; height: 9; radius: 4.5
        y: 0
        color: root.theme.accent
        visible: root.activeIdx >= 0
        x: Math.max(0, root.activeIdx) * 13
        Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    }
}
