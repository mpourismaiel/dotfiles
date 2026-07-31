pragma ComponentBehavior: Bound
// MenuHeader.qml — back chevron + title + trailing controls slot (see pill).
import QtQuick

Item {
    id: root
    required property var theme
    property string title: ""
    default property alias trailing: trailingRow.data
    signal back()

    width: parent ? parent.width : 0
    implicitHeight: 26
    height: 26

    Item {                                  // back chevron + title, clickable together
        id: backArea
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        width: backRow.width
        Row {
            id: backRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7
            MSym {
                anchors.verticalCenter: parent.verticalCenter
                icon: "chevron_left"
                size: 20
                color: backMa.containsMouse ? root.theme.text : root.theme.faint
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.title
                color: root.theme.text
                font.family: root.theme.serif
                font.pixelSize: root.theme.fsLarge + 4
            }
        }
        MouseArea {
            id: backMa
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.back()
        }
    }

    Row {                                   // trailing controls (right)
        id: trailingRow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.theme.gap
    }
}
