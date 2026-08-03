pragma ComponentBehavior: Bound
// CaptureHeader.qml — the shared top-left header for the capture morphs (chooser,
// screenshot toolbar, record settings): a back chevron + serif title, matching the
// control-panel menus (see MenuHeader). Emits back() — used to close/cancel the
// capture. It HUGS its content on the left (implicitWidth = the chevron+title),
// so the wider control rows below are what drive the pill width; the header never
// forces a full-width binding (which would cycle inside an auto-sized Column).
import QtQuick

Item {
    id: root
    required property var theme
    property string title: ""
    signal back()

    implicitWidth: hrow.implicitWidth
    implicitHeight: 26

    Row {
        id: hrow
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        Rectangle {
            width: 26; height: 26; radius: root.theme.radiusBtn
            anchors.verticalCenter: parent.verticalCenter
            color: bma.containsMouse ? root.theme.bgHover : "transparent"
            MSym {
                anchors.centerIn: parent
                icon: "chevron_left"; size: 18
                color: bma.containsMouse ? root.theme.text : root.theme.textDim
            }
            MouseArea {
                id: bma
                anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.back()
            }
            Behavior on color { ColorAnimation { duration: root.theme.animFast } }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.title; color: root.theme.text
            font.family: root.theme.serif; font.pixelSize: root.theme.fsLarge + 2
        }
    }
}
