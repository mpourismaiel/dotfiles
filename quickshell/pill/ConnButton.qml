pragma ComponentBehavior: Bound
// ConnButton.qml — the compact uppercase Connect/Disconnect/Pair control shared by
// the network + Bluetooth rows. Presentational by default (the row is the click
// target); `interactive` makes the chip itself clickable (Wi-Fi password field).
// While `busy` it fills with a BusyStripe barber-pole and ignores clicks. A disabled
// MouseArea is transparent to events, so non-interactive clicks fall through to the
// row behind.
import QtQuick

Item {
    id: root
    required property var theme
    property string label: "Connect"
    property bool active: false        // currently-connected styling (accent)
    property bool busy: false
    property bool interactive: false
    signal clicked()

    // keyboard nav (MenuKbNav): only an interactive chip is its own focus stop —
    // a presentational one is covered by its row's focus. Self-styles focus as a
    // rowHi fill (chip-style), keeping the label fully legible.
    readonly property bool kbFocusable: root.interactive && !root.busy
    property bool kbFocused: false
    function keyClick() { root.clicked(); }

    implicitWidth: Math.max(txt.implicitWidth + 22, 76)
    implicitHeight: 26

    Rectangle {
        anchors.fill: parent
        radius: root.theme.radiusBtn
        clip: true
        color: root.busy ? root.theme.row : root.kbFocused ? root.theme.rowHi : "transparent"
        Behavior on color { ColorAnimation { duration: root.theme.animFast } }
        BusyStripe { anchors.fill: parent; theme: root.theme; active: root.busy }
    }
    Text {
        id: txt
        anchors.centerIn: parent
        text: root.label
        color: root.active ? root.theme.accent : root.theme.textDim
        font.family: root.theme.mono
        font.pixelSize: root.theme.fsSmall
        font.letterSpacing: root.theme.labelSpacing
        font.capitalization: Font.AllUppercase
    }
    MouseArea {
        anchors.fill: parent
        enabled: root.interactive && !root.busy
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
