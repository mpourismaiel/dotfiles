pragma ComponentBehavior: Bound
// DiskWindow.qml — the Disk manager as a real window: an ordinary decorated
// toplevel (title bar, resize, minimise, behind / in front of other windows, on
// the taskbar), NOT a layer-shell panel. It opens from the disk button next to
// the games / settings buttons in the dashboard (or `qs ipc call pill disk`) and
// stays open until you close it yourself — closing the pill, switching windows
// or losing focus does nothing to it.
//
// The window only exists while `disk.shown` is true (LazyLoader), so it costs
// nothing when closed. Content: DiskView.
import QtQuick
import Quickshell

LazyLoader {
    id: root
    required property var theme
    required property var disk

    active: root.disk.shown

    FloatingWindow {
        id: win
        title: "Disk"
        implicitWidth: 1220
        implicitHeight: 780
        minimumSize: Qt.size(980, 600)
        color: root.theme.bg
        // the title-bar ✕ (or the compositor) closed it → forget the window
        onClosed: root.disk.shown = false
        onVisibleChanged: if (!visible) root.disk.shown = false

        DiskView {
            anchors.fill: parent
            theme: root.theme
            disk: root.disk
        }
    }
}
