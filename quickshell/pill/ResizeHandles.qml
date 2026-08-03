pragma ComponentBehavior: Bound
// ResizeHandles.qml — an 8-point resize frame (4 corner + 4 edge grips) with an
// optional middle-drag move, laid over a rectangular region. It works entirely in
// its PARENT's coordinate space: it reads `rect_` (x/y/w/h) and, on any grip drag
// or move, emits `changed(rect)` with the new geometry (clamped to `minW`/`minH`
// and, when >0, kept inside the `boundW`×`boundH` box). The owner keeps the backing
// store and feeds `rect_` straight back in — so the underlying bindings are never
// broken (same rule as the pill's sliders / the webcam drag).
//
// Used for the record region (RecordCanvas) and the webcam overlay. For the webcam
// the overlay owns its own middle-drag, so it passes `moveEnabled: false` and only
// the edge/corner grips are live (the disabled move area lets clicks fall through
// to the camera below).
import QtQuick

Item {
    id: h
    required property var theme
    property rect rect_: Qt.rect(0, 0, 0, 0)
    property real minW: 60
    property real minH: 45
    property real boundW: 0            // 0 = unbounded
    property real boundH: 0
    property bool moveEnabled: true
    property bool active: true

    signal changed(rect r)

    x: rect_.x; y: rect_.y
    width: rect_.width; height: rect_.height
    visible: active

    // grip roles: hx = -1 left / 0 mid / +1 right, vy = -1 top / 0 mid / +1 bottom
    readonly property var _grips: [
        { hx: -1, vy: -1 }, { hx: 0, vy: -1 }, { hx: 1, vy: -1 },
        { hx: -1, vy:  0 },                    { hx: 1, vy:  0 },
        { hx: -1, vy:  1 }, { hx: 0, vy:  1 }, { hx: 1, vy:  1 }
    ]

    // ---- middle drag (declared first → sits UNDER the grips) ----------------
    MouseArea {
        id: moveMa
        anchors.fill: parent
        enabled: h.moveEnabled && h.active
        hoverEnabled: h.moveEnabled && h.active
        cursorShape: Qt.OpenHandCursor
        property real _px: 0
        property real _py: 0
        onPressed: (e) => { moveMa._px = e.x; moveMa._py = e.y; }
        onPositionChanged: (e) => {
            if (!(e.buttons & Qt.LeftButton)) return;
            const p = h.mapToItem(h.parent, e.x, e.y);
            let nx = p.x - moveMa._px, ny = p.y - moveMa._py;
            if (h.boundW > 0) nx = Math.max(0, Math.min(nx, h.boundW - h.width));
            if (h.boundH > 0) ny = Math.max(0, Math.min(ny, h.boundH - h.height));
            h.changed(Qt.rect(nx, ny, h.width, h.height));
        }
    }

    // ---- 8 grips ------------------------------------------------------------
    Repeater {
        model: h._grips
        Rectangle {
            id: grip
            required property var modelData
            readonly property int hx: modelData.hx
            readonly property int vy: modelData.vy
            width: 14; height: 14; radius: 3
            color: gma.containsMouse ? h.theme.accent : h.theme.bg
            border.color: h.theme.accent; border.width: 2
            x: hx < 0 ? -width / 2 : hx > 0 ? h.width - width / 2 : (h.width - width) / 2
            y: vy < 0 ? -height / 2 : vy > 0 ? h.height - height / 2 : (h.height - height) / 2

            // edges captured on press so only the dragged side follows the pointer
            property real _l: 0
            property real _t: 0
            property real _r: 0
            property real _b: 0
            MouseArea {
                id: gma
                anchors.fill: parent
                anchors.margins: -6           // a comfortable hit target
                hoverEnabled: true
                cursorShape: grip.hx * grip.vy > 0 ? Qt.SizeFDiagCursor
                           : grip.hx * grip.vy < 0 ? Qt.SizeBDiagCursor
                           : grip.hx !== 0 ? Qt.SizeHorCursor : Qt.SizeVerCursor
                onPressed: {
                    grip._l = h.rect_.x; grip._t = h.rect_.y;
                    grip._r = h.rect_.x + h.rect_.width; grip._b = h.rect_.y + h.rect_.height;
                }
                onPositionChanged: (e) => {
                    if (!(e.buttons & Qt.LeftButton)) return;
                    const p = grip.mapToItem(h.parent, e.x, e.y);
                    let l = grip._l, t = grip._t, r = grip._r, b = grip._b;
                    if (grip.hx < 0) l = Math.min(p.x, r - h.minW);
                    else if (grip.hx > 0) r = Math.max(p.x, l + h.minW);
                    if (grip.vy < 0) t = Math.min(p.y, b - h.minH);
                    else if (grip.vy > 0) b = Math.max(p.y, t + h.minH);
                    if (h.boundW > 0) { l = Math.max(0, l); r = Math.min(h.boundW, r); }
                    if (h.boundH > 0) { t = Math.max(0, t); b = Math.min(h.boundH, b); }
                    h.changed(Qt.rect(l, t, r - l, b - t));
                }
            }
        }
    }
}
