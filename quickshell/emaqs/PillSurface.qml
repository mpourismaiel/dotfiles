pragma ComponentBehavior: Bound
// PillSurface.qml — bottom-attached panel background: convex rounded TOP corners,
// concave "wing" BOTTOM corners that flare into the screen edge (caelestia style),
// straight flush bottom. radius = top corner, wing = bottom flare; both animate.
import QtQuick
import QtQuick.Shapes

Item {
    id: root
    required property var theme
    property real radius: 14          // top convex corner radius
    property real wing: 12            // bottom concave flare radius
    property color fillColor: "transparent"
    property color strokeColor: "transparent"
    property real strokeWidth: 0

    Behavior on radius { NumberAnimation { duration: root.theme.anim; easing.type: Easing.OutCubic } }
    Behavior on wing   { NumberAnimation { duration: root.theme.anim; easing.type: Easing.OutCubic } }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            id: sp
            fillColor: root.fillColor
            strokeColor: root.strokeColor
            strokeWidth: root.strokeWidth
            joinStyle: ShapePath.RoundJoin

            // clamp so the corners never overrun a small tab
            readonly property real w: root.width
            readonly property real h: root.height
            readonly property real r: Math.max(0, Math.min(root.radius, root.height - root.wing, root.width / 2 - root.wing))
            readonly property real wr: Math.max(0, Math.min(root.wing, root.width / 2 - sp.r, root.height - sp.r))

            startX: sp.wr
            startY: sp.r
            // top-left convex corner
            PathArc { x: sp.wr + sp.r; y: 0; radiusX: sp.r; radiusY: sp.r; direction: PathArc.Clockwise }
            // top edge
            PathLine { x: sp.w - sp.wr - sp.r; y: 0 }
            // top-right convex corner
            PathArc { x: sp.w - sp.wr; y: sp.r; radiusX: sp.r; radiusY: sp.r; direction: PathArc.Clockwise }
            // right wall down
            PathLine { x: sp.w - sp.wr; y: sp.h - sp.wr }
            // bottom-right concave wing — flare out to the base
            PathArc { x: sp.w; y: sp.h; radiusX: sp.wr; radiusY: sp.wr; direction: PathArc.Counterclockwise }
            // straight flush bottom edge
            PathLine { x: 0; y: sp.h }
            // bottom-left concave wing
            PathArc { x: sp.wr; y: sp.h - sp.wr; radiusX: sp.wr; radiusY: sp.wr; direction: PathArc.Counterclockwise }
            // left wall up, close
            PathLine { x: sp.wr; y: sp.r }
        }
    }
}
