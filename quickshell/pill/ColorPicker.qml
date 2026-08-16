pragma ComponentBehavior: Bound
// ColorPicker.qml — a compact inline HSV colour picker: a saturation/value square,
// a hue slider and an alpha slider. Used inside ColorField (Settings → Appearance).
//
// It keeps its own H/S/V/A state so dragging is smooth; call seedFrom(color) to
// load a starting colour (done when the host field expands / commits a typed
// value — NOT bound live, so the picker never fights the field's own edits).
// `picked(color)` fires continuously as the user drags.
import QtQuick

Item {
    id: root
    required property var theme
    property bool showAlpha: true
    signal picked(color value)

    // internal HSVA state (all 0..1)
    property real hh: 0
    property real ss: 0
    property real vv: 1
    property real aa: 1
    property bool _seeding: false

    implicitHeight: svSquare.height + 12 + hueSlider.height + (root.showAlpha ? 8 + alphaSlider.height : 0)

    function seedFrom(col) {
        var c = Qt.color(col);
        root._seeding = true;
        if (c.hsvHue >= 0)            // keep prior hue for achromatic (gray) inputs
            root.hh = c.hsvHue;
        root.ss = c.hsvSaturation;
        root.vv = c.hsvValue;
        root.aa = c.a;
        root._seeding = false;
    }

    readonly property color current: Qt.hsva(root.hh, root.ss, root.vv, root.aa)
    // Only ever emit from a real user drag (the slider/square apply() handlers).
    // NOT from `current` changing, so seeding + the initial white state never
    // clobber the stored colour when the picker is first instantiated.
    function _emit() { if (!root._seeding) root.picked(root.current); }

    // keep the picker a sensible width instead of stretching the SV square across
    // the whole (wide) settings pane
    readonly property int contentW: Math.min(width, 320)

    // ---- saturation / value square ----
    Rectangle {
        id: svSquare
        anchors.top: parent.top
        anchors.left: parent.left
        width: root.contentW
        height: 150
        radius: root.theme.radiusSmall
        color: Qt.hsva(root.hh, 1, 1, 1)     // pure hue base
        clip: true

        // white → transparent (left→right = saturation)
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#ffffffff" }
                GradientStop { position: 1.0; color: "#00ffffff" }
            }
        }
        // transparent → black (top→bottom = value)
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: "#00000000" }
                GradientStop { position: 1.0; color: "#ff000000" }
            }
        }

        // thumb
        Rectangle {
            width: 14
            height: 14
            radius: 7
            border.width: 2
            border.color: "#ffffff"
            color: "transparent"
            x: root.ss * svSquare.width - width / 2
            y: (1 - root.vv) * svSquare.height - height / 2
            Rectangle {
                anchors.centerIn: parent
                width: 12
                height: 12
                radius: 6
                border.width: 1
                border.color: "#40000000"
                color: "transparent"
            }
        }

        MouseArea {
            anchors.fill: parent
            preventStealing: true
            function apply(mx, my) {
                root.ss = Math.max(0, Math.min(1, mx / svSquare.width));
                root.vv = Math.max(0, Math.min(1, 1 - my / svSquare.height));
                root._emit();
            }
            onPressed: (m) => apply(m.x, m.y)
            onPositionChanged: (m) => apply(m.x, m.y)
        }
    }

    // ---- hue slider ----
    Rectangle {
        id: hueSlider
        anchors.top: svSquare.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        width: root.contentW
        height: 16
        radius: height / 2
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.000; color: "#ff0000" }
            GradientStop { position: 0.167; color: "#ffff00" }
            GradientStop { position: 0.333; color: "#00ff00" }
            GradientStop { position: 0.500; color: "#00ffff" }
            GradientStop { position: 0.667; color: "#0000ff" }
            GradientStop { position: 0.833; color: "#ff00ff" }
            GradientStop { position: 1.000; color: "#ff0000" }
        }
        Rectangle {
            width: 18
            height: 18
            radius: 9
            border.width: 3
            border.color: "#ffffff"
            color: Qt.hsva(root.hh, 1, 1, 1)
            y: (parent.height - height) / 2
            x: Math.max(0, Math.min(parent.width - width, root.hh * parent.width - width / 2))
        }
        MouseArea {
            anchors.fill: parent
            preventStealing: true
            function apply(mx) { root.hh = Math.max(0, Math.min(1, mx / hueSlider.width)); root._emit(); }
            onPressed: (m) => apply(m.x)
            onPositionChanged: (m) => apply(m.x)
        }
    }

    // ---- alpha slider ----
    Rectangle {
        id: alphaSlider
        visible: root.showAlpha
        anchors.top: hueSlider.bottom
        anchors.topMargin: 8
        anchors.left: parent.left
        width: root.contentW
        height: 16
        radius: height / 2
        clip: true
        color: "transparent"

        // checkerboard so partial alpha reads as transparent
        Row {
            anchors.fill: parent
            Repeater {
                model: Math.ceil(alphaSlider.width / 8) + 1
                delegate: Column {
                    id: checkCol
                    required property int index
                    Repeater {
                        model: 2
                        delegate: Rectangle {
                            required property int index
                            width: 8
                            height: 8
                            color: ((checkCol.index + index) % 2 === 0) ? "#3a3a3a" : "#5a5a5a"
                        }
                    }
                }
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.hsva(root.hh, root.ss, root.vv, 0) }
                GradientStop { position: 1.0; color: Qt.hsva(root.hh, root.ss, root.vv, 1) }
            }
        }
        Rectangle {
            width: 18
            height: 18
            radius: 9
            border.width: 3
            border.color: "#ffffff"
            color: "transparent"
            y: (parent.height - height) / 2
            x: Math.max(0, Math.min(parent.width - width, root.aa * parent.width - width / 2))
        }
        MouseArea {
            anchors.fill: parent
            preventStealing: true
            function apply(mx) { root.aa = Math.max(0, Math.min(1, mx / alphaSlider.width)); root._emit(); }
            onPressed: (m) => apply(m.x)
            onPositionChanged: (m) => apply(m.x)
        }
    }
}
