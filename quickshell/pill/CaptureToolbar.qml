pragma ComponentBehavior: Bound
// CaptureToolbar.qml — the screenshot tool row that the pill morphs into (and the
// harness renders standalone): tool picker (select/text/arrow/rect/rectFill),
// colour swatches, a stroke-width stepper, then copy / save / cancel. Drives a
// CaptureState; the actual editing happens in the CaptureOverlay. Kept as its own
// component so init.qml just hosts it inside the expanded pill.
import QtQuick

Item {
    id: bar
    required property var state
    required property var theme

    implicitHeight: colWrap.implicitHeight + 2 * theme.pad
    implicitWidth: colWrap.implicitWidth + 2 * theme.pad

    readonly property var tools: [
        { id: "select",   icon: "arrow_selector_tool" },
        { id: "text",     icon: "title" },
        { id: "arrow",    icon: "arrow_outward" },
        { id: "rect",     icon: "crop_square" },
        { id: "rectFill", icon: "square" }
    ]

    // one square icon button (shared look with the pill's dashboard tiles)
    component TBtn: Rectangle {
        id: b
        property string glyph: ""
        property bool on: false
        property real gfill: 0
        signal clicked()
        width: 30; height: 30; radius: bar.theme.radiusBtn
        color: on ? bar.theme.accentSoft : (ma.containsMouse ? bar.theme.bgHover : "transparent")
        border.color: on ? bar.theme.accent : "transparent"
        border.width: 1
        MSym {
            anchors.centerIn: parent
            icon: b.glyph
            size: 19
            fill: b.gfill
            color: b.on ? bar.theme.accent : (ma.containsMouse ? bar.theme.text : bar.theme.textDim)
        }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
        Behavior on color { ColorAnimation { duration: bar.theme.animFast } }
    }

    Column {
        id: colWrap
        anchors.centerIn: parent
        spacing: 8

        // header: back chevron + title (replaces the old close button)
        CaptureHeader { theme: bar.theme; title: "Screenshot"; onBack: bar.state.cancel() }

    Row {
        id: row
        spacing: 6

        // ---- tools ----
        Repeater {
            model: bar.tools
            TBtn {
                required property var modelData
                glyph: modelData.icon
                gfill: modelData.id === "rectFill" ? 1 : 0
                on: bar.state.tool === modelData.id
                onClicked: bar.state.tool = modelData.id
            }
        }

        Rectangle { width: 1; height: 24; color: bar.theme.divider; anchors.verticalCenter: parent.verticalCenter }

        // ---- colour swatches ----
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5
            Repeater {
                model: bar.state.palette
                Rectangle {
                    required property var modelData
                    readonly property bool sel: bar.state.strokeColor == modelData
                    width: 20; height: 20; radius: 10
                    color: modelData
                    border.color: sel ? bar.theme.text : bar.theme.border
                    border.width: sel ? 2 : 1
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: bar.state.pickColor(parent.modelData) }
                }
            }
        }

        Rectangle { width: 1; height: 24; color: bar.theme.divider; anchors.verticalCenter: parent.verticalCenter }

        // ---- stroke width stepper ----
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            TBtn { glyph: "remove"; onClicked: bar.state.pickWidth(Math.max(1, bar.state.strokeWidth - 1)) }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 22; horizontalAlignment: Text.AlignHCenter
                text: bar.state.strokeWidth
                color: bar.theme.text; font.family: bar.theme.mono; font.pixelSize: bar.theme.fsNormal
            }
            TBtn { glyph: "add"; onClicked: bar.state.pickWidth(Math.min(30, bar.state.strokeWidth + 1)) }
        }

        Rectangle { width: 1; height: 24; color: bar.theme.divider; anchors.verticalCenter: parent.verticalCenter }

        // ---- select the whole screen as the crop ----
        // (drawing a smaller crop is a drag on empty canvas with the select tool.)
        TBtn { glyph: "fullscreen"; onClicked: bar.state.selectFullScreen() }

        Rectangle { width: 1; height: 24; color: bar.theme.divider; anchors.verticalCenter: parent.verticalCenter }

        // ---- finish ----
        TBtn { glyph: "content_copy"; onClicked: bar.state.requestCopy() }
        TBtn { glyph: "download";     onClicked: bar.state.requestSave() }
    }
    }
}
