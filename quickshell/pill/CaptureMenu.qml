pragma ComponentBehavior: Bound
// CaptureMenu.qml — the small chooser the pill morphs into when the capture button
// is clicked: "Take screenshot" / "Record screen" (or "Stop & save" while a
// recording is live). Hosted in the pill by captureLoader; implicitWidth/Height
// size the pill. Selecting a row fires the matching signal and closes the menu.
import QtQuick

Item {
    id: menu
    required property var theme
    property bool recording: false
    signal screenshot()
    signal record()
    signal stop()
    signal dismiss()

    implicitWidth: col.implicitWidth
    implicitHeight: col.implicitHeight

    component Row_: Rectangle {
        id: r
        property string glyph: ""
        property string label: ""
        property color tint: menu.theme.text
        signal clicked()
        width: 240; height: 40; radius: menu.theme.radiusRow
        color: rma.containsMouse ? menu.theme.bgHover : menu.theme.row
        Row {
            anchors.left: parent.left; anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter; spacing: 12
            MSym { anchors.verticalCenter: parent.verticalCenter; icon: r.glyph; size: 22; color: r.tint }
            Text { anchors.verticalCenter: parent.verticalCenter; text: r.label; color: menu.theme.text
                   font.family: menu.theme.family; font.pixelSize: menu.theme.fsNormal }
        }
        MouseArea { id: rma; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor; onClicked: r.clicked() }
        Behavior on color { ColorAnimation { duration: menu.theme.animFast } }
    }

    Column {
        id: col
        spacing: 6

        CaptureHeader { theme: menu.theme; title: "Capture"; onBack: menu.dismiss() }

        Row_ {
            visible: menu.recording
            glyph: "stop_circle"; label: "Stop & save recording"; tint: menu.theme.accent
            onClicked: menu.stop()
        }
        Row_ {
            visible: !menu.recording
            glyph: "screenshot_monitor"; label: "Take screenshot"
            onClicked: menu.screenshot()
        }
        Row_ {
            visible: !menu.recording
            glyph: "videocam"; label: "Record screen"
            onClicked: menu.record()
        }
    }
}
