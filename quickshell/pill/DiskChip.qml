pragma ComponentBehavior: Bound
// DiskChip.qml — a small outlined label in the Disk window. `tone` picks the
// colour: safe (green) · warn (gold) · stop (accent, tinted) · plain (dim).
// `tier` is a shortcut: free→safe, cost→warn, state/data→stop.
import QtQuick

Rectangle {
    id: root
    required property var theme
    property string text: ""
    property string tone: "plain"
    property string tier: ""
    readonly property string _tone: tier === "free" ? "safe" : tier === "cost" ? "warn" : tier !== "" ? "stop" : tone
    readonly property color ink: _tone === "safe" ? theme.success : _tone === "warn" ? theme.money : _tone === "stop" ? theme.accent : theme.textDim

    implicitWidth: lab.implicitWidth + 14
    implicitHeight: 18
    radius: 7
    color: _tone === "stop" ? theme.accentSoft : "transparent"
    border.width: 1
    border.color: Qt.rgba(ink.r, ink.g, ink.b, 0.45)

    Text {
        id: lab
        anchors.centerIn: parent
        text: root.text.toUpperCase()
        color: root.ink
        font.family: root.theme.mono
        font.pixelSize: 9
        font.weight: Font.Medium
        font.letterSpacing: 0.8
    }
}
