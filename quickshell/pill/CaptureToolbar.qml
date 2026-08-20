pragma ComponentBehavior: Bound
// CaptureToolbar.qml — the screenshot tool row that the pill morphs into (and the
// harness renders standalone). Two rows under the header:
//   • tools + history + finish — select/text/arrow/line/rect/rectFill/draw, then
//     undo/redo, then fullscreen + copy/save.
//   • a CONTEXTUAL style row — only the controls the active target supports: colour
//     for everything, stroke width for shapes, font size for text, a fill toggle +
//     fill colour for a selected rectangle, and a delete button when one is picked.
// "Target" = the selected annotation if there is one, else the current draw tool's
// defaults (see CaptureState.attrType / cur*). Drives a CaptureState; the actual
// editing happens in the CaptureOverlay.
import QtQuick

Item {
    id: bar
    required property var state
    required property var theme

    implicitHeight: colWrap.implicitHeight + 2 * theme.pad
    implicitWidth: colWrap.implicitWidth + 2 * theme.pad

    readonly property var tools: [
        { id: "select",   icon: "arrow_selector_tool", gfill: 0 },
        { id: "text",     icon: "title",               gfill: 0 },
        { id: "arrow",    icon: "arrow_outward",       gfill: 0 },
        { id: "line",     icon: "horizontal_rule",     gfill: 0 },
        { id: "rect",     icon: "crop_square",         gfill: 0 },
        { id: "rectFill", icon: "square",              gfill: 1 },
        { id: "freehand", icon: "draw",                gfill: 0 }
    ]

    // one square icon button (shared look with the pill's dashboard tiles)
    component TBtn: Rectangle {
        id: b
        property string glyph: ""
        property bool on: false
        property bool disabled: false
        property real gfill: 0
        signal clicked()
        width: 30; height: 30; radius: bar.theme.radiusBtn
        opacity: disabled ? 0.35 : 1
        color: on ? bar.theme.accentSoft : (ma.containsMouse && !disabled ? bar.theme.bgHover : "transparent")
        border.color: on ? bar.theme.accent : "transparent"
        border.width: 1
        MSym {
            anchors.centerIn: parent
            icon: b.glyph
            size: 19
            fill: b.gfill
            color: b.on ? bar.theme.accent : (ma.containsMouse && !b.disabled ? bar.theme.text : bar.theme.textDim)
        }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true
                    cursorShape: b.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onClicked: { if (!b.disabled) b.clicked() } }
        Behavior on color { ColorAnimation { duration: bar.theme.animFast } }
    }

    // thin vertical divider between control groups
    component VDiv: Rectangle {
        width: 1; height: 24; color: bar.theme.divider
        anchors.verticalCenter: parent.verticalCenter
    }

    // a row of colour swatches with a live "current" highlight + a picked() signal.
    component Swatches: Row {
        id: sw
        property color current: "#000000"
        signal picked(color c)
        spacing: 5
        Repeater {
            model: bar.state.palette
            Rectangle {
                required property var modelData
                readonly property bool sel: sw.current == modelData
                width: 20; height: 20; radius: 10
                color: modelData
                border.color: sel ? bar.theme.text : bar.theme.border
                border.width: sel ? 2 : 1
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: sw.picked(modelData) }
            }
        }
    }

    // a small −  value  + stepper.
    component Stepper: Row {
        id: stp
        property int value: 0
        property int minv: 1
        property int maxv: 30
        property int step: 1
        signal changed(int v)
        spacing: 2
        TBtn { glyph: "remove"; onClicked: stp.changed(Math.max(stp.minv, stp.value - stp.step)) }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 26; horizontalAlignment: Text.AlignHCenter
            text: stp.value
            color: bar.theme.text; font.family: bar.theme.mono; font.pixelSize: bar.theme.fsNormal
        }
        TBtn { glyph: "add"; onClicked: stp.changed(Math.min(stp.maxv, stp.value + stp.step)) }
    }

    Column {
        id: colWrap
        anchors.centerIn: parent
        spacing: 8

        // header: back chevron + title (replaces the old close button)
        CaptureHeader { theme: bar.theme; title: "Screenshot"; onBack: bar.state.cancel() }

        // ---- row 1: tools + history + finish ----
        Row {
            id: toolRow
            spacing: 6

            Repeater {
                model: bar.tools
                TBtn {
                    required property var modelData
                    glyph: modelData.icon
                    gfill: modelData.gfill
                    on: bar.state.tool === modelData.id
                    onClicked: bar.state.tool = modelData.id
                }
            }

            VDiv {}

            // ---- undo / redo ----
            TBtn { glyph: "undo"; disabled: !bar.state.canUndo; onClicked: bar.state.undoRequested() }
            TBtn { glyph: "redo"; disabled: !bar.state.canRedo; onClicked: bar.state.redoRequested() }

            VDiv {}

            // ---- select the whole screen as the crop ----
            // (drawing a smaller crop is a drag on empty canvas with the select tool.)
            TBtn { glyph: "fullscreen"; onClicked: bar.state.selectFullScreen() }

            VDiv {}

            // ---- finish ----
            TBtn { glyph: "content_copy"; onClicked: bar.state.requestCopy() }
            TBtn { glyph: "download";     onClicked: bar.state.requestSave() }
        }

        // ---- row 2: contextual style controls (empty when nothing is editable) ----
        Row {
            id: styleRow
            spacing: 6
            visible: bar.state.attrType !== ""

            // stroke / line / text colour — applies to every target
            Swatches {
                anchors.verticalCenter: parent.verticalCenter
                current: bar.state.curColor
                onPicked: (c) => bar.state.pickColor(c)
            }

            // stroke width — shapes only (rect / arrow / line / draw), never text
            VDiv { visible: bar.state.attrHasStroke }
            Stepper {
                anchors.verticalCenter: parent.verticalCenter
                visible: bar.state.attrHasStroke
                minv: 1; maxv: 30; step: 1
                value: bar.state.curWidth
                onChanged: (v) => bar.state.pickWidth(v)
            }

            // font size — text only
            VDiv { visible: bar.state.attrHasFont }
            Stepper {
                anchors.verticalCenter: parent.verticalCenter
                visible: bar.state.attrHasFont
                minv: 8; maxv: 96; step: 2
                value: bar.state.curFont
                onChanged: (v) => bar.state.pickFont(v)
            }

            // fill toggle + fill colour — a selected rectangle only
            VDiv { visible: bar.state.attrIsRect && (bar.state.selected !== null) }
            TBtn {
                anchors.verticalCenter: parent.verticalCenter
                visible: bar.state.attrIsRect && (bar.state.selected !== null)
                glyph: "format_color_fill"
                gfill: bar.state.curFilled ? 1 : 0
                on: bar.state.curFilled
                onClicked: bar.state.toggleFill()
            }
            Swatches {
                anchors.verticalCenter: parent.verticalCenter
                visible: bar.state.attrIsRect && (bar.state.selected !== null) && bar.state.curFilled
                current: bar.state.curFill
                onPicked: (c) => bar.state.pickFill(c)
            }

            // delete the selected annotation
            VDiv { visible: bar.state.selected }
            TBtn {
                anchors.verticalCenter: parent.verticalCenter
                visible: bar.state.selected !== null
                glyph: "delete"
                onClicked: bar.state.deleteSelected()
            }
        }
    }
}
