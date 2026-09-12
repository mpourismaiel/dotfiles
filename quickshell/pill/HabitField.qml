// HabitField.qml — labeled single-line text field used by the habit tracker's
// dialogs (log/edit form, freeze ranges, add-habit). Styled like the pill's
// other input wells; typing works because init.qml's kbInputFocused watches
// the active-focus item globally.
import QtQuick

Column {
    id: root
    required property var theme
    property string label: ""
    property alias text: input.text
    property alias placeholder: ph.text
    property alias input: input
    property int fieldWidth: 130
    spacing: 4

    Text {
        text: root.label
        visible: root.label !== ""
        color: root.theme.faint
        font.family: root.theme.mono
        font.pixelSize: root.theme.fsSmall
        font.capitalization: Font.AllUppercase
        font.letterSpacing: root.theme.labelSpacing
    }
    Rectangle {
        width: root.fieldWidth
        height: 28
        radius: root.theme.radiusBtn
        color: root.theme.row
        border.width: 1
        border.color: input.activeFocus ? root.theme.accent : root.theme.border
        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 9
            anchors.rightMargin: 9
            verticalAlignment: TextInput.AlignVCenter
            color: root.theme.text
            font.family: root.theme.mono
            font.pixelSize: root.theme.fsNormal
            clip: true
            selectByMouse: true
            Text {
                id: ph
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text === "" && !input.activeFocus
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsNormal
            }
        }
        Behavior on border.color { ColorAnimation { duration: root.theme.animFast } }
    }
}
