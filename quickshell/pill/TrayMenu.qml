pragma ComponentBehavior: Bound
// TrayMenu.qml — a system-tray item's DBus menu inside the pill (like
// AppContextMenu, not a native popup). MenuHeader shows the item title (chevron =
// closeRequested); below it a scrolling TrayMenuLevel walks trayItem.menu. The
// menu's implicitHeight sizes the ctx-mode pill. Any leaf trigger bubbles up to
// closeRequested() so acting closes the menu.
import QtQuick

Item {
    id: root
    required property var theme
    required property var trayItem      // SystemTrayItem
    signal closeRequested()

    readonly property string title: (root.trayItem && (root.trayItem.title || root.trayItem.id)) || "Menu"

    // header + content, independent of the height we're given, so the pill can bind
    // its ctx-mode height to this without a layout cycle (as AppContextMenu does).
    implicitHeight: header.implicitHeight + root.theme.gap + bodyCol.implicitHeight

    Column {
        anchors.fill: parent
        spacing: root.theme.gap

        MenuHeader {
            id: header
            theme: root.theme
            title: root.title
            onBack: root.closeRequested()
        }

        Flickable {
            id: bodyFlick
            width: parent.width
            height: parent.height - header.height - root.theme.gap
            contentHeight: bodyCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            // width MUST reference the Flickable id (its Column's parent is the
            // contentItem, width ~ contentWidth ~ 0) — see AppContextMenu's note.
            Column {
                id: bodyCol
                width: bodyFlick.width

                TrayMenuLevel {
                    width: parent.width
                    theme: root.theme
                    handle: root.trayItem ? root.trayItem.menu : null
                    onActivated: root.closeRequested()
                }
            }
        }
    }
}
