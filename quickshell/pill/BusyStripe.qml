pragma ComponentBehavior: Bound
// BusyStripe.qml — a diagonal barber-pole that slides sideways behind a button to
// signal an in-flight action (connecting/disconnecting/pairing). Clipped + faded,
// so it reads as a moving texture, not a fill. Shown while `active`. The band holds
// one extra period of stripes and loops a single period, so the motion is seamless.
import QtQuick

Item {
    id: root
    required property var theme
    property bool active: false
    property color stripe: root.theme.accent

    clip: true
    visible: opacity > 0
    opacity: root.active ? 0.22 : 0
    Behavior on opacity { NumberAnimation { duration: root.theme.animFast } }

    readonly property int period: 24        // px between stripe starts

    Row {
        id: band
        height: root.height
        Repeater {
            model: Math.ceil((root.width + root.height) / root.period) + 2
            delegate: Item {
                width: root.period
                height: band.height
                Rectangle {                 // one diagonal bar per cell
                    width: root.period * 0.42
                    height: parent.height * 2.2
                    y: -parent.height * 0.6
                    color: root.stripe
                    rotation: 32
                    transformOrigin: Item.Center
                    antialiasing: true
                }
            }
        }
        // slide exactly one period, forever -> continuous motion
        NumberAnimation on x {
            from: -root.period
            to: 0
            duration: 640
            loops: Animation.Infinite
            running: root.active
        }
    }
}
