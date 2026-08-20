pragma ComponentBehavior: Bound
// AnnItem.qml — one annotation on the frozen capture: rectangle (stroke, with an
// optional fill), arrow, plain line, freehand scribble, or text. Created
// imperatively by AnnotationLayer (createObject) so it is a STABLE object whose
// geometry is mutated in place — a Repeater over a JS array would recreate the
// delegate mid-drag and drop the grab (the same slider-drag gotcha documented for
// the pill). Move (body drag) + resize (corner / endpoint handles) + delete
// (state.deleteSelected). Selection is tracked by identity (state.selected ===
// this), not an index. Attribute edits (colour / width / fill / font) come in via
// setters the toolbar/state calls on the selected item; each commits an undo step.
import QtQuick
import QtQuick.Shapes

Item {
    id: ann
    required property var state
    required property var theme

    readonly property bool isAnnotation: true   // marker so the layer can find + destroy these
    property string annType: "rect"     // rect | arrow | line | freehand | text
    property color annColor: "#e6402e"  // stroke / line / text colour
    property int   annWidth: 4
    property int   fontPx: 22
    property bool  filled: false        // rect only: paint the interior with fillColor
    property color fillColor: "#e6402e" // rect only
    property string textValue: ""
    // freehand only: the recorded path, in layer (frozen-image) coords.
    property var points: []

    // two defining points in layer (frozen-image) coords. rect/text: opposite
    // corners; arrow/line: tail -> head; freehand: bounding-box min -> max.
    property real x1: 0
    property real y1: 0
    property real x2: 0
    property real y2: 0

    readonly property bool isSelected: state.selected === ann
    // raise to the top of the annotation stack whenever selected (so it's the one
    // you grab/edit, and it stays in front afterwards) — a monotonic counter, not a
    // reparent, so the stable-object drag grab is never dropped.
    onIsSelectedChanged: if (ann.isSelected && ann.state.nextAnnZ) ann.z = ann.state.nextAnnZ()
    readonly property bool isArrow: annType === "arrow"
    readonly property bool isLine: annType === "line"
    readonly property bool isText: annType === "text"
    readonly property bool isFreehand: annType === "freehand"
    // arrow + line resize by their two endpoints; everything else by a bounding box.
    readonly property bool isLinear: isArrow || isLine
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
    // freehand path in local coords (recomputed as the item moves / the path grows)
    readonly property var localPoints: {
        const out = [];
        const ps = ann.points || [];
        for (let i = 0; i < ps.length; i++) out.push(Qt.point(ps[i].x - ann.x, ps[i].y - ann.y));
        return out;
    }

    function setColor(c) { ann.annColor = c }
    function setWidth(w) { ann.annWidth = w }
    function setFont(s)  { ann.fontPx = s }
    function setFill(c)  { ann.fillColor = c; ann.filled = true }
    function toggleFilled() { ann.filled = !ann.filled }
    function select() { ann.state.selected = ann }
    function beginEditIfText() { if (ann.isText) { ann.state.selected = ann; txtInput.forceActiveFocus(); } }
    // freehand: append a point and grow the tracked bounding box.
    function addPoint(px, py) {
        const ps = (ann.points || []).slice();
        ps.push({ x: px, y: py });
        ann.points = ps;
        ann.x1 = Math.min(ann.x1, px); ann.y1 = Math.min(ann.y1, py);
        ann.x2 = Math.max(ann.x2, px); ann.y2 = Math.max(ann.y2, py);
    }

    // ---- rectangle (stroke + optional fill) --------------------------------
    Rectangle {
        visible: ann.annType === "rect"
        x: ann.m; y: ann.m
        width: ann.bw; height: ann.bh
        color: ann.filled ? ann.fillColor : "transparent"
        border.color: ann.annColor
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
        // arrowhead — a V chevron (barb → tip → barb). Coordinates reference the
        // ShapePath by id (`head`): a PathLine is a non-Item Path element with no
        // visual `parent`, so `parent.len`/`parent.a` were undefined and the second
        // barb never drew (leaving just one diagonal line at the tip).
        ShapePath {
            id: head
            readonly property real a: Math.atan2(ann.ly2 - ann.ly1, ann.lx2 - ann.lx1)
            readonly property real len: Math.max(12, ann.annWidth * 3.4)
            readonly property real spread: 0.5
            strokeColor: ann.annColor
            strokeWidth: ann.annWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            startX: ann.lx2 - head.len * Math.cos(head.a - head.spread)
            startY: ann.ly2 - head.len * Math.sin(head.a - head.spread)
            PathLine { x: ann.lx2; y: ann.ly2 }
            PathLine {
                x: ann.lx2 - head.len * Math.cos(head.a + head.spread)
                y: ann.ly2 - head.len * Math.sin(head.a + head.spread)
            }
        }
    }

    // ---- plain line (arrow without the head) --------------------------------
    Shape {
        visible: ann.isLine
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
    }

    // ---- freehand scribble --------------------------------------------------
    Shape {
        visible: ann.isFreehand
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: ann.annColor
            strokeWidth: ann.annWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: ann.localPoints }
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
        onEditingFinished: { focus = false; ann.state.commitHistory(); }
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
    property bool _moved: false
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
            ann._px = p.x; ann._py = p.y; ann._moved = false;
            ann._base = { x1: ann.x1, y1: ann.y1, x2: ann.x2, y2: ann.y2,
                          points: (ann.points || []).map(q => ({ x: q.x, y: q.y })) };
        }
        onPositionChanged: (e) => {
            if (!(e.buttons & Qt.LeftButton) || !ann._base) return;
            const p = mapToItem(ann.parent, e.x, e.y);
            const dx = p.x - ann._px, dy = p.y - ann._py;
            if (Math.abs(dx) + Math.abs(dy) > 0) ann._moved = true;
            ann.x1 = ann._base.x1 + dx; ann.y1 = ann._base.y1 + dy;
            ann.x2 = ann._base.x2 + dx; ann.y2 = ann._base.y2 + dy;
            if (ann.isFreehand)
                ann.points = ann._base.points.map(q => ({ x: q.x + dx, y: q.y + dy }));
        }
        onReleased: { ann._base = null; if (ann._moved) ann.state.commitHistory(); ann._moved = false; }
        onDoubleClicked: ann.beginEditIfText()
    }

    // ---- resize / endpoint handles -----------------------------------------
    // rect/text: corner handles that move the matching defining corner.
    // arrow/line: 2 handles at tail/head. Freehand has no resize (move only).
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
                if (ann.isLinear) {
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
            onReleased: ann.state.commitHistory()
        }
    }
    // arrow/line endpoints
    Handle { corner: 0; hx: ann.lx1; hy: ann.ly1; visible: ann.isSelected && ann.isLinear && ann.state.tool === "select" }
    Handle { corner: 1; hx: ann.lx2; hy: ann.ly2; visible: ann.isSelected && ann.isLinear && ann.state.tool === "select" }
    // rect/text corners
    Handle { corner: 0; hx: ann.m;          hy: ann.m;          visible: ann.isSelected && !ann.isLinear && !ann.isFreehand && ann.state.tool === "select" }
    Handle { corner: 1; hx: ann.m + ann.bw; hy: ann.m + ann.bh; visible: ann.isSelected && !ann.isLinear && !ann.isFreehand && ann.state.tool === "select" }
    Handle { corner: 2; hx: ann.m + ann.bw; hy: ann.m;          visible: ann.isSelected && !ann.isLinear && !ann.isFreehand && !ann.isText && ann.state.tool === "select" }
    Handle { corner: 3; hx: ann.m;          hy: ann.m + ann.bh; visible: ann.isSelected && !ann.isLinear && !ann.isFreehand && !ann.isText && ann.state.tool === "select" }

    // selection outline for rect / text / freehand (bounding-box types)
    Rectangle {
        visible: ann.isSelected && !ann.isLinear && ann.state.tool === "select"
        x: ann.m - 3; y: ann.m - 3
        width: (ann.isText ? txt.implicitWidth : ann.bw) + 6
        height: (ann.isText ? txt.implicitHeight : ann.bh) + 6
        color: "transparent"
        border.color: ann.theme.accent
        border.width: 1
        opacity: 0.7
    }
}
