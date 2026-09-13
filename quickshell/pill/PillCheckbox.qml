// PillCheckbox.qml — the pill's small tick box, extracted from the org-agenda
// checkbox pattern (CalendarMenu agenda rows / AgendaMenu deadline rows):
// 14×14 rounded well, accent fill + popping check glyph when on, accent border
// on hover. Optional trailing label; the whole row is clickable. Used by the
// habit tracker's dialogs (bool done / missed).
import QtQuick

Item {
    id: root
    required property var theme
    property bool checked: false
    property string label: ""
    signal toggled(bool on)

    implicitWidth: box.width + (label !== "" ? lab.implicitWidth + 7 : 0)
    implicitHeight: 20
    width: implicitWidth
    height: implicitHeight

    Rectangle {
        id: box
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 14
        height: 14
        radius: 4
        color: root.checked ? root.theme.accent : "transparent"
        border.width: 1
        border.color: (root.checked || ma.containsMouse) ? root.theme.accent : root.theme.faint
        Behavior on color { ColorAnimation { duration: root.theme.anim } }
        Behavior on border.color { ColorAnimation { duration: root.theme.anim } }
        MSym {
            anchors.centerIn: parent
            icon: "check"
            fill: 1
            size: 11
            color: root.theme.bg
            // pops in when ticked, shrinks away when un-ticked
            opacity: root.checked ? 1 : 0
            scale: root.checked ? 1 : 0.4
            Behavior on opacity { NumberAnimation { duration: root.theme.animFast } }
            Behavior on scale { NumberAnimation { duration: root.theme.anim; easing.type: Easing.OutBack } }
        }
    }
    Text {
        id: lab
        visible: root.label !== ""
        anchors.left: box.right
        anchors.leftMargin: 7
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: root.theme.textDim
        font.family: root.theme.mono
        font.pixelSize: root.theme.fsSmall
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        anchors.margins: -3
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }
}
