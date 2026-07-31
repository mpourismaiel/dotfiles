pragma ComponentBehavior: Bound
// Theme.qml — colours, metrics and timings for emaqs (Broadsheet palette, shared
// with the pill). Instantiated once in init.qml as `Theme { id: theme }`.
import QtQuick

QtObject {
    // ---- palette ----
    readonly property color bg:          "#1b1712"   // panel / bar base
    readonly property color bgElevated:  "#221d16"   // menu surface
    readonly property color row:         "#231e17"   // resting rows / hovered chrome
    readonly property color rowHi:       "#3a271c"   // selected / active tint
    readonly property color bgHover:     "#3a271c"   // hover square (= rowHi)
    readonly property color border:      Qt.rgba(0xec / 255.0, 0xe4 / 255.0, 0xd6 / 255.0, 0.12)
    readonly property color borderStrong: Qt.rgba(0xec / 255.0, 0xe4 / 255.0, 0xd6 / 255.0, 0.22)
    readonly property color divider:     Qt.rgba(0xec / 255.0, 0xe4 / 255.0, 0xd6 / 255.0, 0.12)
    readonly property color text:        "#efe9dd"   // primary cream
    readonly property color textDim:     "#a89e8c"   // secondary
    readonly property color faint:       "#7a7060"   // tertiary / idle glyphs
    readonly property color accent:      "#cf4636"   // vermillion
    readonly property color accentSoft:  Qt.rgba(0xcf / 255.0, 0x46 / 255.0, 0x36 / 255.0, 0.15)
    readonly property color accentDim:   "#3a271c"   // active-workspace tint (= rowHi)
    readonly property color danger:      "#d95435"   // destructive
    readonly property color track:       Qt.rgba(0xec / 255.0, 0xe4 / 255.0, 0xd6 / 255.0, 0.14)

    // resting (collapsed, un-hovered) tab: translucent + a soft gradient so the
    // floating tab blends with whatever is behind it (alpha only, not real blur).
    readonly property color bgTranslucent: Qt.rgba(0x1b / 255.0, 0x17 / 255.0, 0x12 / 255.0, 0.72)
    readonly property color bgGradTop:     Qt.rgba(0x2a / 255.0, 0x24 / 255.0, 0x1b / 255.0, 0.82)
    readonly property color bgGradBottom:  Qt.rgba(0x15 / 255.0, 0x11 / 255.0, 0x0c / 255.0, 0.66)
    readonly property real  idleOpacity:   0.86

    // ---- metrics ----
    readonly property int radiusPanel:   20
    readonly property int radiusRow:     14
    readonly property int radiusBtn:     10
    readonly property int pad:           14
    readonly property int gap:           10
    readonly property int rowHeight:     32

    // ---- fonts ----
    readonly property string family:     "IBM Plex Sans"
    readonly property string serif:      "DM Serif Display"
    readonly property string mono:       "IBM Plex Mono"
    readonly property string icon:       "Material Symbols Rounded"
    readonly property real   labelSpacing: 1.4

    // Icon theme for Qt-themed glyphs (unused by emaqs itself, kept so run-emaqs.sh
    // has the same knob as run-pill.sh). "" = follow KDE.
    readonly property string iconTheme:   ""

    readonly property int fsSmall:       11
    readonly property int fsNormal:      13
    readonly property int fsLarge:       15

    // ---- animation ----
    readonly property int anim:          210
    readonly property int animFast:      130
}
