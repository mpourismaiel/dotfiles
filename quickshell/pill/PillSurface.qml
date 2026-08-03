pragma ComponentBehavior: Bound
// PillSurface.qml — top-attached panel background: convex rounded BOTTOM (free)
// corners, concave "wing" TOP corners that flare into the screen edge (caelestia
// style), straight flush top. radius = free corner, wing = edge flare; both animate.
import QtQuick
import QtQuick.Shapes

Item {
    id: root
    required property var theme
    property real radius: 16          // convex free-edge (bottom) corner radius
    property real wing: 12            // concave top-edge flare radius
    property color fillColor: "transparent"
    property color strokeColor: "transparent"
    property real strokeWidth: 0
    // detached/floating: draw a uniformly-rounded rectangle (all four corners = radius)
    // instead of the top-attached winged shape, so the top corners match the bottom.
    property bool rounded: false

    Behavior on radius { NumberAnimation { duration: root.theme.anim; easing.type: Easing.OutCubic } }
    Behavior on wing   { NumberAnimation { duration: root.theme.anim; easing.type: Easing.OutCubic } }

    // floating pill: a plain rounded rect (equal top/bottom radius)
    Rectangle {
        anchors.fill: parent
        visible: root.rounded
        radius: Math.min(root.radius, Math.min(width, height) / 2)
        color: root.fillColor
        border.color: root.strokeColor
        border.width: root.strokeWidth
    }

    Shape {
        anchors.fill: parent
        visible: !root.rounded
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            id: sp
            fillColor: root.fillColor
            strokeColor: root.strokeColor
            strokeWidth: root.strokeWidth
            joinStyle: ShapePath.RoundJoin

            readonly property real w: root.width
            readonly property real h: root.height
            readonly property real r: Math.max(0, Math.min(root.radius, root.height - root.wing, root.width / 2 - root.wing))
            readonly property real wr: Math.max(0, Math.min(root.wing, root.width / 2 - sp.r, root.height - sp.r))

            startX: sp.wr
            startY: sp.h - sp.r
            // bottom-left convex corner (free edge)
            PathArc { x: sp.wr + sp.r; y: sp.h; radiusX: sp.r; radiusY: sp.r; direction: PathArc.Counterclockwise }
            // bottom edge
            PathLine { x: sp.w - sp.wr - sp.r; y: sp.h }
            // bottom-right convex corner
            PathArc { x: sp.w - sp.wr; y: sp.h - sp.r; radiusX: sp.r; radiusY: sp.r; direction: PathArc.Counterclockwise }
            // right wall up
            PathLine { x: sp.w - sp.wr; y: sp.wr }
            // top-right concave wing — flare out to the top edge
            PathArc { x: sp.w; y: 0; radiusX: sp.wr; radiusY: sp.wr; direction: PathArc.Clockwise }
            // straight flush top edge
            PathLine { x: 0; y: 0 }
            // top-left concave wing
            PathArc { x: sp.wr; y: sp.wr; radiusX: sp.wr; radiusY: sp.wr; direction: PathArc.Clockwise }
            // left wall down, close
            PathLine { x: sp.wr; y: sp.h - sp.r }
        }
    }
}
