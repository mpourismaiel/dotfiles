pragma ComponentBehavior: Bound
// Theme.qml — one place for all colours, metrics and timings. Change here to
// restyle the whole pill. Instantiated once in init.qml as `Theme { id: theme }`
// and passed into every menu component as `theme`.
import QtQuick

QtObject {
    // ---- palette (Broadsheet: warm cocoa-black under a vermillion accent, set
    //      in serif; see __ignore__/Broadsheet.html for the reference sheet) ----
    readonly property color desk:        "#151310"   // deepest desktop wash
    readonly property color bg:          "#1b1712"   // panel / pill base
    readonly property color bgElevated:  "#221d16"   // cards / popups / menus
    readonly property color card:        "#221d16"   // alias of bgElevated (notification cards)
    readonly property color row:         "#231e17"   // resting list rows / tiles
    readonly property color rowHi:       "#3a271c"   // selected / active / hover-highlight rows
    readonly property color bgHover:     "#3a271c"   // shared hover square + hovered surfaces (= rowHi)
    readonly property color border:      Qt.rgba(0xec / 255.0, 0xe4 / 255.0, 0xd6 / 255.0, 0.12)  // hairline (--line)
    readonly property color borderStrong: Qt.rgba(0xec / 255.0, 0xe4 / 255.0, 0xd6 / 255.0, 0.22) // (--line-2)
    readonly property color divider:     Qt.rgba(0xec / 255.0, 0xe4 / 255.0, 0xd6 / 255.0, 0.12)  // (--line)
    readonly property color text:        "#efe9dd"   // primary cream
    readonly property color textDim:     "#a89e8c"   // secondary (--dim)
    readonly property color faint:       "#7a7060"   // tertiary / idle glyphs (--faint)
    readonly property color accent:      "#cf4636"   // vermillion
    readonly property color accentSoft:  Qt.rgba(0xcf / 255.0, 0x46 / 255.0, 0x36 / 255.0, 0.15)  // accent tint bg
    readonly property color accentDim:   "#3a271c"   // selected / active background tint (= rowHi)
    readonly property color danger:      "#d95435"   // vermillion-light (destructive)
    readonly property color good:        "#3ecf8e"   // green (privacy/live cue)
    readonly property color success:     "#a8d5a4"   // pastel green (all-done calendar dot / completed cue)
    readonly property color money:       "#d9a441"   // gold (finance dots / figures — distinct from the vermillion agenda dot)
    readonly property color event:       "#6ea8d8"   // soft blue (Google-calendar event dot / times — distinct from agenda & finance)
    readonly property color track:       Qt.rgba(0xec / 255.0, 0xe4 / 255.0, 0xd6 / 255.0, 0.14)  // toggle / slider track

    // resting (collapsed, un-hovered) pill: translucent + dimmed (see init.qml).
    // NOTE: this is alpha translucency only — true backdrop blur needs the KWin
    // blur protocol, which Quickshell does not expose.
    readonly property color bgTranslucent: Qt.rgba(0x1b / 255.0, 0x17 / 255.0, 0x12 / 255.0, 0.72)
    // resting-pill gradient (translucent, no border): warmer/lighter top fading to
    // a darker bottom, so the floating pill blends with whatever is behind it.
    readonly property color bgGradTop:     Qt.rgba(0x2a / 255.0, 0x24 / 255.0, 0x1b / 255.0, 0.82)
    readonly property color bgGradBottom:  Qt.rgba(0x15 / 255.0, 0x11 / 255.0, 0x0c / 255.0, 0.66)
    readonly property real idleOpacity:    0.86

    // ---- metrics (Broadsheet radius scale) ----
    readonly property int radius:        20         // open pill / panel (--r-panel)
    readonly property int radiusPanel:   20         // menus / launcher panel (--r-panel)
    readonly property int radiusCard:    18         // notification cards (--r-card)
    readonly property int radiusTile:    16         // launcher grid tiles (--r-tile)
    readonly property int radiusRow:     14         // list rows / search field (--r-row)
    readonly property int radiusBtn:     10         // buttons (--r-btn)
    readonly property int radiusSmall:   10         // generic small radius
    readonly property int pad:           14
    readonly property int gap:           10
    readonly property int railWidth:     44
    readonly property int rowHeight:     40
    // dashboard icon buttons (app-list tiles, launcher, status icons, tray) are
    // all this square size, laid out with this spacing, so the shared hover
    // indicator is one uniform square that jumps between them.
    readonly property int iconCell:      26
    readonly property int iconSpacing:    6
    // hovered-dashboard app tiles (taskbar) run larger than the menu/tray glyphs
    readonly property int appCell:       36
    readonly property int appIcon:       28

    // ---- fonts ----
    //   family = body (IBM Plex Sans) · serif = titles/clock/figures (DM Serif
    //   Display) · mono = uppercase spaced labels (IBM Plex Mono) · icon =
    //   Material Symbols Rounded (chrome glyphs; app/tray icons stay Qt-themed).
    readonly property string family:     "IBM Plex Sans"
    readonly property string serif:      "DM Serif Display"
    readonly property string mono:       "IBM Plex Mono"
    readonly property string icon:       "Material Symbols Rounded"
    // letter-spacing (px) for the uppercase mono labels
    readonly property real   labelSpacing: 1.4

    // ---- icons ----
    // Icons resolve through Qt's icon theme. run-pill.sh makes that follow KDE's
    // configured theme by default (QT_QPA_PLATFORMTHEME=kde). Set a name here to
    // force a specific theme instead (e.g. "Papirus", "breeze") — run-pill.sh
    // reads this value and applies it. "" = follow KDE.
    readonly property string iconTheme:   ""
    readonly property int fsSmall:       11
    readonly property int fsNormal:      13
    readonly property int fsLarge:       15

    // ---- animation ----
    readonly property int anim:          210
    readonly property int animFast:      130

    // ---- power confirmation design ----
    // Which full-screen shutdown/reboot/logout confirmation to show (see the
    // powerConfirm block in init.qml). One of the four Claude-designed variants,
    // or "random" to pick a fresh one on every open:
    //   "1a" Hush   — restrained italic serif on a dark wash
    //   "1b" Blaze  — full vermillion flood, brutalist
    //   "1c" Ledger — editorial, keyline frame
    //   "1d" Split  — decisive left (yes) / right (no) halves
    //   "random"    — one of the above, chosen per open
    // Needs the fonts: IBM Plex Mono, Newsreader, DM Serif Display, Instrument Serif.
    readonly property string confirmation: "1a"
}
