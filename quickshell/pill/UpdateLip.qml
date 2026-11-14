pragma ComponentBehavior: Bound
// UpdateLip.qml — the system-update hairline on the resting pill's bottom lip.
// It traces the pill's free edge from wall to wall (both bottom corners + the
// flat run between them — the same geometry as PillSurface, so it must be given
// the same radius / wing and anchored over it) and is the ONLY update signal on
// the resting pill:
//
//   none         nothing drawn
//   optional     almost transparent, no glow   ("not worth it yet")
//   recommended  faint accent, no glow, still
//   required     full accent + halo, slow breathing
//   hold/restart money (gold); "asking" adds the halo + breathing
//   running      accent, filled left→right to `progress` over a faint track
//   failed       danger, stopped at `progress` over the track
//
// Colours/alphas come from Theme (lip*). No blur is available on this
// compositor, so the "glow" is a wider low-alpha stroke under the line.
import QtQuick
import QtQuick.Shapes

Item {
    id: root
    required property var theme
    property string mood: "none"
    property real progress: 0          // 0…1, used by running / failed
    property real radius: 16
    property real wing: 12

    readonly property bool partial: mood === "running" || mood === "failed"
    readonly property bool glowing: mood === "required" || mood === "asking"
    readonly property color lineColor: {
        var t = root.theme;
        if (mood === "optional") return Qt.rgba(t.text.r, t.text.g, t.text.b, t.lipQuietAlpha);
        if (mood === "recommended") return Qt.rgba(t.accent.r, t.accent.g, t.accent.b, t.lipSoftAlpha);
        if (mood === "required" || mood === "running") return t.accent;
        if (mood === "hold" || mood === "restart" || mood === "asking") return t.money;
        if (mood === "failed") return t.danger;
        return "transparent";
    }
    visible: mood !== "none" && mood !== ""

    // one stroked copy of the lip contour
    component Lip: Shape {
        id: lip
        property color stroke: "transparent"
        property real thick: 2
        width: root.width
        height: root.height
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            id: sp
            fillColor: "transparent"
            strokeColor: lip.stroke
            strokeWidth: lip.thick
            capStyle: ShapePath.RoundCap
            // inset by half the stroke so the line sits ON the pill's edge, inside it
            readonly property real w: root.width
            readonly property real h: root.height - root.theme.lipWidth / 2
            readonly property real r: Math.max(0, Math.min(root.radius, root.height - root.wing, root.width / 2 - root.wing))
            readonly property real wr: Math.max(0, Math.min(root.wing, root.width / 2 - sp.r, root.height - sp.r))
            readonly property real inx: sp.wr + root.theme.lipWidth / 2
            startX: sp.inx
            startY: sp.h - sp.r
            PathArc { x: sp.inx + sp.r; y: sp.h; radiusX: sp.r; radiusY: sp.r; direction: PathArc.Counterclockwise }
            PathLine { x: sp.w - sp.inx - sp.r; y: sp.h }
            PathArc { x: sp.w - sp.inx; y: sp.h - sp.r; radiusX: sp.r; radiusY: sp.r; direction: PathArc.Counterclockwise }
        }
    }

    // faint full-width track under a partial (progress) line
    Lip {
        visible: root.partial
        stroke: root.theme.track
        thick: root.theme.lipWidth
    }

    Item {
        id: fill
        height: root.height
        width: root.partial ? root.width * Math.max(0, Math.min(1, root.progress)) : root.width
        clip: root.partial
        Behavior on width { enabled: root.partial; NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

        Lip {   // halo
            visible: root.glowing
            stroke: Qt.rgba(root.lineColor.r, root.lineColor.g, root.lineColor.b, root.theme.lipGlowAlpha)
            thick: root.theme.lipWidth * 3.5
        }
        Lip {
            stroke: root.lineColor
            thick: root.theme.lipWidth
        }

        SequentialAnimation on opacity {
            running: root.glowing && root.visible
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation { to: 0.4; duration: 1200; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 1200; easing.type: Easing.InOutSine }
        }
    }
    Behavior on opacity { NumberAnimation { duration: root.theme.anim } }
}
