pragma ComponentBehavior: Bound
// MSym.qml — one Material Symbols Rounded glyph. `icon` is the symbol name
// (a ligature, e.g. "chevron_left"); fill/weight/grade map to the font's
// variable axes so `fill: 1` gives the solid variant. `size` sets both the
// pixel size and the optical-size axis. Chrome glyphs only — app/tray icons
// stay Qt-themed (IconImage). Validated to render (ligatures + FILL axis) on
// Qt 6.11 / Material Symbols Rounded variable font.
import QtQuick

Text {
    id: sym
    property string icon: ""
    property real fill: 0            // 0 outline, 1 solid
    property int weight: 400        // wght axis
    property real grade: 0          // GRAD axis
    property int size: 20           // pixel size == optical size

    text: sym.icon
    font.family: "Material Symbols Rounded"
    font.pixelSize: sym.size
    font.variableAxes: ({ "FILL": sym.fill, "wght": sym.weight, "GRAD": sym.grade, "opsz": sym.size })
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
    color: "#efe9dd"
    renderType: Text.QtRendering
}
