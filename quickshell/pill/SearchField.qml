pragma ComponentBehavior: Bound
// SearchField.qml — compact search row shared by the network/bluetooth/volume
// menus. No auto-focus: a click (or keyboard-nav Enter, via keyClick) focuses the
// input, which pulls the keyboard through the pillKbInput mechanism. Escape clears
// the query and hands the keyboard back. The menu reads `text` and filters its
// sections, keeping labels/dividers only where matches remain.
import QtQuick

Rectangle {
    id: root
    required property var theme
    property string placeholder: "Search"
    readonly property alias text: input.text

    // keyboard nav: Enter = click (focus the input and start typing). The row is
    // opaque, so it self-styles focus (kbFocused) with the same accent border it
    // shows while the input holds focus.
    readonly property bool kbFocusable: true
    property bool kbFocused: false
    function keyClick() { input.forceActiveFocus(); }

    implicitHeight: 34
    height: 34
    radius: root.theme.radiusRow
    color: root.theme.row
    border.width: 1
    border.color: (input.activeFocus || root.kbFocused) ? root.theme.accent : root.theme.border

    // clicking anywhere in the row (icon, padding) focuses the input; the input
    // sits on top of this, so text selection still works normally.
    MouseArea {
        anchors.fill: parent
        onClicked: input.forceActiveFocus()
    }

    MSym {
        id: searchIcon
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        icon: "search"
        size: 17
        color: input.activeFocus ? root.theme.accent : root.theme.faint
    }

    TextInput {
        id: input
        objectName: "pillKbInput"
        anchors.left: searchIcon.right
        anchors.leftMargin: 8
        anchors.right: clearBtn.visible ? clearBtn.left : parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        verticalAlignment: TextInput.AlignVCenter
        color: root.theme.text
        font.family: root.theme.family
        font.pixelSize: root.theme.fsNormal
        clip: true
        selectByMouse: true
        selectionColor: root.theme.accentDim
        // Escape: clear the query and drop focus (keyboard-nav reclaims the keys,
        // a mouse-opened menu releases the pill's keyboard grab)
        Keys.onEscapePressed: {
            input.text = "";
            input.focus = false;
        }
        Text {
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            visible: input.text.length === 0
            text: root.placeholder
            color: root.theme.faint
            font.family: root.theme.family
            font.pixelSize: root.theme.fsNormal
            elide: Text.ElideRight
        }
    }

    MSym {                       // ✕ — clear the query (shown while one is set)
        id: clearBtn
        visible: input.text.length > 0
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        icon: "close"
        size: 16
        color: clearMa.containsMouse ? root.theme.text : root.theme.faint
        MouseArea {
            id: clearMa
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: input.text = ""
        }
    }
}
