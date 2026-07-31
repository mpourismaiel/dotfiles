pragma ComponentBehavior: Bound
// AgentCountBadge.qml — accent-soft circle holding the active-agent count in accent
// mono; hidden (and zero-width) unless more than one agent is working. `diameter`
// sizes the circle (18 in the collapsed cards, 22 in the expanded bar).
import QtQuick

Rectangle {
    id: root
    required property var theme
    property int count: 0
    property int diameter: 18
    visible: count > 1
    width: visible ? diameter : 0
    height: diameter
    radius: diameter / 2
    color: root.theme.accentSoft
    Text {
        anchors.centerIn: parent
        text: root.count
        color: root.theme.accent
        font.family: root.theme.mono
        font.pixelSize: root.theme.fsSmall
        font.bold: true
    }
}
