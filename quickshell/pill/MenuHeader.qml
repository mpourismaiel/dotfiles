pragma ComponentBehavior: Bound
// MenuHeader.qml — shared header for every control-panel menu: a back chevron
// (‹) that collapses the panel, the menu title, and an optional trailing slot
// for menu-specific controls (toggles). Children declared inside a MenuHeader
// land in the right-aligned trailing Row, e.g.
//   MenuHeader { title: "Wi-Fi"; onBack: root.closeRequested(); PillToggle {} }
import QtQuick

Item {
    id: root
    required property var theme
    property string title: ""
    default property alias trailing: trailingRow.data
    property bool navArrows: false          // show ← → stepper right after the title
    signal back()
    signal prev()
    signal next()

    width: parent ? parent.width : 0
    implicitHeight: 26
    height: 26

    Item {                                  // back chevron + title (left) — clickable together
        id: backArea
        // keyboard nav (MenuKbNav): the back button is every menu's default
        // focus; focus brightens the chevron exactly like hover
        readonly property bool kbFocusable: true
        readonly property bool kbDefault: true
        property bool kbFocused: false
        function keyClick() { root.back(); }
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
                color: (backMa.containsMouse || backArea.kbFocused) ? root.theme.text : root.theme.faint
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

    Row {                                   // optional ← → stepper, right after the title
        id: navRow
        visible: root.navArrows
        anchors.left: backArea.right
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Rectangle {
            readonly property bool kbFocusable: root.navArrows
            property bool kbFocused: false
            function keyClick() { root.prev(); }
            width: 22
            height: 22
            radius: root.theme.radiusBtn
            color: (prevMa.containsMouse || kbFocused) ? root.theme.row : "transparent"
            MSym {
                anchors.centerIn: parent
                icon: "arrow_back"
                size: 18
                color: prevMa.containsMouse ? root.theme.text : root.theme.faint
            }
            MouseArea {
                id: prevMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.prev()
            }
            Behavior on color { ColorAnimation { duration: root.theme.animFast } }
        }
        Rectangle {
            readonly property bool kbFocusable: root.navArrows
            property bool kbFocused: false
            function keyClick() { root.next(); }
            width: 22
            height: 22
            radius: root.theme.radiusBtn
            color: (nextMa.containsMouse || kbFocused) ? root.theme.row : "transparent"
            MSym {
                anchors.centerIn: parent
                icon: "arrow_forward"
                size: 18
                color: nextMa.containsMouse ? root.theme.text : root.theme.faint
            }
            MouseArea {
                id: nextMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.next()
            }
            Behavior on color { ColorAnimation { duration: root.theme.animFast } }
        }
    }

    Row {                                   // trailing controls (right)
        id: trailingRow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.theme.gap
    }
}
