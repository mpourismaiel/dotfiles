pragma ComponentBehavior: Bound
// MSym.qml — one Material Symbols Rounded glyph (see pill's MSym.qml).
import QtQuick

Text {
    id: sym
    property string icon: ""
    property real fill: 0
    property int weight: 400
    property real grade: 0
    property int size: 20

    text: sym.icon
    font.family: "Material Symbols Rounded"
    font.pixelSize: sym.size
    font.variableAxes: ({ "FILL": sym.fill, "wght": sym.weight, "GRAD": sym.grade, "opsz": sym.size })
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
    color: "#efe9dd"
    renderType: Text.QtRendering
}
