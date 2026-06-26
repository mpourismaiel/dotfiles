pragma ComponentBehavior: Bound
// Theme.qml — one place for all colours, metrics and timings. Change here to
// restyle the whole pill. Instantiated once in pill.qml as `Theme { id: theme }`
// and passed into every menu component as `theme`.
import QtQuick

QtObject {
    // ---- palette (dark, Tokyo-night-ish accent over near-black) ----
    readonly property color bg:         "#0d0f14"
    readonly property color bgElevated:  "#161a22"
    readonly property color bgHover:     "#1f2530"
    readonly property color border:      "#2a2f3a"
    readonly property color divider:     "#242a35"
    readonly property color text:        "#e6e6e6"
    readonly property color textDim:     "#9aa3b2"
    readonly property color accent:      "#7aa2f7"
    readonly property color accentDim:   "#2b3654"
    readonly property color danger:      "#f7768e"
    readonly property color good:        "#9ece6a"

    // ---- metrics ----
    readonly property int radius:        18
    readonly property int radiusSmall:   10
    readonly property int pad:           14
    readonly property int gap:           10
    readonly property int railWidth:     44
    readonly property int rowHeight:     38

    // ---- fonts ----
    readonly property string mono:       "monospace"
    readonly property int fsSmall:       11
    readonly property int fsNormal:      13
    readonly property int fsLarge:       15

    // ---- animation ----
    readonly property int anim:          210
    readonly property int animFast:      130
}
