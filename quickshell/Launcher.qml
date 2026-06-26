pragma ComponentBehavior: Bound
// Launcher.qml — KDE-style application launcher.
//
// The app list is supplied by the parent (built once from DesktopEntries and
// kept alive across opens), so opening is instant after the first build. A
// ListView virtualises the rows, so only the visible icons exist; icons load
// asynchronously, so the UI never blocks on icon decoding. Click a row to
// launch the app detached from this process (DesktopEntry.execute()).
//
// First step: just the list + launch. Search/favourites/keyboard nav are TODO.
import QtQuick
import Quickshell
import Quickshell.Widgets

Item {
    id: root
    required property var theme
    required property var apps   // [DesktopEntry], pre-sorted by the parent
    signal launched()

    ListView {
        id: list
        anchors.fill: parent
        model: root.apps
        clip: true
        spacing: 2
        cacheBuffer: 600           // pre-render a little above/below the viewport
        boundsBehavior: Flickable.StopAtBounds
        visible: count > 0

        delegate: Rectangle {
            id: appRow
            required property var modelData
            width: list.width
            height: root.theme.rowHeight
            radius: root.theme.radiusSmall
            color: ma.containsMouse ? root.theme.bgHover : "transparent"

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                IconImage {
                    anchors.verticalCenter: parent.verticalCenter
                    implicitSize: 24
                    asynchronous: true          // decode off the GUI thread
                    source: Quickshell.iconPath(appRow.modelData.icon, "application-x-executable")
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 24 - 10
                    elide: Text.ElideRight
                    text: appRow.modelData.name
                    color: root.theme.text
                    font.pixelSize: root.theme.fsNormal
                }
            }
            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { appRow.modelData.execute(); root.launched(); }
            }
        }
    }

    // loading state — shown only until the app list is populated
    Text {
        anchors.centerIn: parent
        visible: list.count === 0
        text: "Loading applications…"
        color: root.theme.textDim
        font.pixelSize: root.theme.fsNormal
        SequentialAnimation on opacity {
            running: parent.visible
            loops: Animation.Infinite
            NumberAnimation { from: 0.4; to: 1.0; duration: 600; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.0; to: 0.4; duration: 600; easing.type: Easing.InOutSine }
        }
    }
}
