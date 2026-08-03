pragma ComponentBehavior: Bound
// AnnItem.qml — one annotation on the frozen capture: rectangle (stroke or
// filled), arrow, or text. Created imperatively by AnnotationLayer (createObject)
// so it is a STABLE object whose geometry is mutated in place — a Repeater over a
// JS array would recreate the delegate mid-drag and drop the grab (the same
// slider-drag gotcha documented for the pill). Move (body drag) + resize (corner
// / endpoint handles) + delete (state.deleteSelected). Selection is tracked by
// identity (state.selected === this), not an index.
import QtQuick
import QtQuick.Shapes

Item {
    id: ann
    required property var state
    required property var theme

    readonly property bool isAnnotation: true   // marker so the layer can find + destroy these
    property string annType: "rect"     // rect | rectFill | arrow | text
    property color annColor: "#e6402e"
    property int   annWidth: 4
    property int   fontPx: 22
    property string textValue: ""

    // two defining points in layer (frozen-image) coords. rect/text: opposite
    // corners; arrow: tail -> head.
    property real x1: 0
    property real y1: 0
    property real x2: 0
    property real y2: 0

    readonly property bool isSelected: state.selected === ann
    readonly property bool isArrow: annType === "arrow"
    readonly property bool isText: annType === "text"
    readonly property real minx: Math.min(x1, x2)
    readonly property real miny: Math.min(y1, y2)
    readonly property real bw: Math.abs(x2 - x1)
    readonly property real bh: Math.abs(y2 - y1)
    readonly property int  m: 16        // overflow margin for handles / arrowhead

    x: minx - m
    y: miny - m
    width: (isText ? txt.implicitWidth : bw) + 2 * m
    height: (isText ? txt.implicitHeight : bh) + 2 * m

    // local coords of the two points
    readonly property real lx1: x1 - x
    readonly property real ly1: y1 - y
    readonly property real lx2: x2 - x
    readonly property real ly2: y2 - y

    function setColor(c) { ann.annColor = c }
    function setWidth(w) { ann.annWidth = w }
    function select() { ann.state.selected = ann }
    function beginEditIfText() { if (ann.isText) { ann.state.selected = ann; txtInput.forceActiveFocus(); } }

    // ---- rectangle (stroke or filled) --------------------------------------
    Rectangle {
        visible: ann.annType === "rect" || ann.annType === "rectFill"
        x: ann.m; y: ann.m
        width: ann.bw; height: ann.bh
        color: ann.annType === "rectFill" ? ann.annColor : "transparent"
        border.color: ann.annType === "rectFill" ? "transparent" : ann.annColor
        border.width: ann.annWidth
        radius: 2
    }

    // ---- arrow --------------------------------------------------------------
    Shape {
        visible: ann.isArrow
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: ann.annColor
            strokeWidth: ann.annWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            startX: ann.lx1; startY: ann.ly1
            PathLine { x: ann.lx2; y: ann.ly2 }
        }
        // arrowhead (two barbs at the head)
        ShapePath {
            readonly property real a: Math.atan2(ann.ly2 - ann.ly1, ann.lx2 - ann.lx1)
            readonly property real len: Math.max(10, ann.annWidth * 3.2)
            readonly property real spread: 0.5
            strokeColor: ann.annColor
            strokeWidth: ann.annWidth
            fillColor: ann.annColor
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            startX: ann.lx2 - len * Math.cos(a - spread)
            startY: ann.ly2 - len * Math.sin(a - spread)
            PathLine { x: ann.lx2; y: ann.ly2 }
            PathLine {
                x: ann.lx2 - parent.len * Math.cos(parent.a + parent.spread)
                y: ann.ly2 - parent.len * Math.sin(parent.a + parent.spread)
            }
        }
    }

    // ---- text ---------------------------------------------------------------
    // Text renders normally; when selected + focused, an overlaid TextInput edits
    // it (kept in sync). Editing needs the overlay window to hold the keyboard.
    Text {
        id: txt
        visible: ann.isText && !txtInput.activeFocus
        x: ann.m; y: ann.m
        text: ann.textValue.length ? ann.textValue : "Text"
        color: ann.annColor
        font.family: ann.theme.family
        font.pixelSize: ann.fontPx
        font.bold: true
        style: Text.Outline
        styleColor: Qt.rgba(0, 0, 0, 0.55)
    }
    TextInput {
        id: txtInput
        visible: ann.isText && activeFocus
        x: ann.m; y: ann.m
        text: ann.textValue
        color: ann.annColor
        font: txt.font
        selectByMouse: true
        onTextChanged: ann.textValue = text
        onEditingFinished: focus = false
        Rectangle {                 // caret box while editing
            anchors.fill: parent; anchors.margins: -3
            color: "transparent"; border.color: ann.theme.accent; border.width: 1
            visible: parent.activeFocus
        }
    }

    // ---- move (body drag) ---------------------------------------------------
    property real _px: 0
    property real _py: 0
    property var _base: null
    MouseArea {
        id: body
        anchors.fill: parent
        enabled: ann.state.tool === "select"
        hoverEnabled: true
        cursorShape: ann.isSelected ? Qt.SizeAllCursor : Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onPressed: (e) => {
            ann.select();
            const p = mapToItem(ann.parent, e.x, e.y);
            ann._px = p.x; ann._py = p.y;
            ann._base = { x1: ann.x1, y1: ann.y1, x2: ann.x2, y2: ann.y2 };
        }
        onPositionChanged: (e) => {
            if (!(e.buttons & Qt.LeftButton) || !ann._base) return;
            const p = mapToItem(ann.parent, e.x, e.y);
            const dx = p.x - ann._px, dy = p.y - ann._py;
            ann.x1 = ann._base.x1 + dx; ann.y1 = ann._base.y1 + dy;
            ann.x2 = ann._base.x2 + dx; ann.y2 = ann._base.y2 + dy;
        }
        onReleased: ann._base = null
        onDoubleClicked: ann.beginEditIfText()
    }

    // ---- resize / endpoint handles -----------------------------------------
    // rect/text: 4 corner handles that move the matching defining corner.
    // arrow: 2 handles at tail/head.
    component Handle: Rectangle {
        id: h
        required property int corner    // 0 tail/tl, 1 head/br, 2 tr, 3 bl
        property real hx: 0
        property real hy: 0
        visible: ann.isSelected && ann.state.tool === "select"
        width: 12; height: 12; radius: 6
        color: ann.theme.bg
        border.color: ann.theme.accent
        border.width: 2
        x: hx - width / 2
        y: hy - height / 2
        MouseArea {
            anchors.fill: parent; anchors.margins: -6
            cursorShape: Qt.SizeFDiagCursor
            onPositionChanged: (e) => {
                if (!(e.buttons & Qt.LeftButton)) return;
                const p = mapToItem(ann.parent, e.x, e.y);
                if (ann.isArrow) {
                    if (h.corner === 0) { ann.x1 = p.x; ann.y1 = p.y; }
                    else { ann.x2 = p.x; ann.y2 = p.y; }
                } else {
                    // corners: 0 tl,1 br,2 tr,3 bl — move the owning edges
                    if (h.corner === 0 || h.corner === 3) ann.x1 = p.x;
                    if (h.corner === 1 || h.corner === 2) ann.x2 = p.x;
                    if (h.corner === 0 || h.corner === 2) ann.y1 = p.y;
                    if (h.corner === 1 || h.corner === 3) ann.y2 = p.y;
                }
            }
        }
    }
    // arrow endpoints
    Handle { corner: 0; hx: ann.lx1; hy: ann.ly1; visible: ann.isSelected && ann.isArrow && ann.state.tool === "select" }
    Handle { corner: 1; hx: ann.lx2; hy: ann.ly2; visible: ann.isSelected && ann.isArrow && ann.state.tool === "select" }
    // rect/text corners
    Handle { corner: 0; hx: ann.m;          hy: ann.m;          visible: ann.isSelected && !ann.isArrow && ann.state.tool === "select" }
    Handle { corner: 1; hx: ann.m + ann.bw; hy: ann.m + ann.bh; visible: ann.isSelected && !ann.isArrow && ann.state.tool === "select" }
    Handle { corner: 2; hx: ann.m + ann.bw; hy: ann.m;          visible: ann.isSelected && !ann.isArrow && !ann.isText && ann.state.tool === "select" }
    Handle { corner: 3; hx: ann.m;          hy: ann.m + ann.bh; visible: ann.isSelected && !ann.isArrow && !ann.isText && ann.state.tool === "select" }

    // selection outline for rect/text
    Rectangle {
        visible: ann.isSelected && !ann.isArrow && ann.state.tool === "select"
        x: ann.m - 3; y: ann.m - 3
        width: (ann.isText ? txt.implicitWidth : ann.bw) + 6
        height: (ann.isText ? txt.implicitHeight : ann.bh) + 6
        color: "transparent"
        border.color: ann.theme.accent
        border.width: 1
        opacity: 0.7
    }
}
