pragma ComponentBehavior: Bound
// Theme.qml — one place for all colours, metrics and timings. Change here to
// restyle the whole pill. Instantiated once in init.qml as `Theme { id: theme }`
// and passed into every menu component as `theme`.
//
// Colours are now user-customisable at runtime (Settings → Appearance). Each
// colour reads from the `overrides` map (a { key: "<css colour>" } object, bound
// in init.qml to the persisted theme.json JsonAdapter); a missing/blank entry
// falls back to the built-in default in `defaults`. So the shipped palette lives
// in `defaults`, the user's edits live in theme.json, and every widget just reads
// `theme.<key>` as before. `palette` describes the editable list (order + labels
// + groups) that the Appearance page renders, and `presets` are the one-click
// starting points.
import QtQuick

QtObject {
    id: theme

    // ---- user overrides (bound to theme.json in init.qml) ----
    // { "<key>": "<css colour string>" }. Blank/absent → use defaults[key].
    property var overrides: ({})

    // ---- shipped palette (Terminal 79 — warm amber-phosphor analog deck) ----
    // Single source of truth for the built-in colours. Stored as CSS strings so
    // they round-trip through the same parseColor() the user's overrides use.
    readonly property var defaults: ({
        "desk":          "#151310",
        "bg":            "#1b1712",
        "bgElevated":    "#221d16",
        "card":          "#221d16",
        "row":           "#231e17",
        "rowHi":         "#3a271c",
        "bgHover":       "#3a271c",
        "border":        "rgba(236, 228, 214, 0.12)",
        "borderStrong":  "rgba(236, 228, 214, 0.22)",
        "divider":       "rgba(236, 228, 214, 0.12)",
        "track":         "rgba(236, 228, 214, 0.14)",
        "text":          "#efe9dd",
        "textDim":       "#a89e8c",
        "faint":         "#7a7060",
        "accent":        "#cf4636",
        "accentSoft":    "rgba(207, 70, 54, 0.15)",
        "accentDim":     "#3a271c",
        "danger":        "#d95435",
        "good":          "#3ecf8e",
        "success":       "#a8d5a4",
        "money":         "#d9a441",
        "event":         "#6ea8d8",
        "bgTranslucent": "rgba(27, 23, 18, 0.72)",
        "bgGradTop":     "rgba(42, 36, 27, 0.82)",
        "bgGradBottom":  "rgba(21, 17, 12, 0.66)"
    })

    // resolve one palette key to a live colour: user override if set, else default.
    function _col(key) {
        var o = overrides ? overrides[key] : undefined;
        return parseColor((o !== undefined && o !== null && o !== "") ? o : defaults[key]);
    }
    // the raw css string currently in effect for a key (override or default) — used
    // by the Appearance page to seed its inputs and to export the whole theme.
    function colorString(key) {
        var o = overrides ? overrides[key] : undefined;
        return (o !== undefined && o !== null && o !== "") ? o : defaults[key];
    }

    // ---- palette (all values below resolve through overrides → defaults) ----
    readonly property color desk:         _col("desk")          // deepest desktop wash
    readonly property color bg:           _col("bg")            // panel / pill base
    readonly property color bgElevated:   _col("bgElevated")    // cards / popups / menus
    readonly property color card:         _col("card")          // notification cards (was alias of bgElevated)
    readonly property color row:          _col("row")           // resting list rows / tiles
    readonly property color rowHi:        _col("rowHi")         // selected / active / hover-highlight rows
    readonly property color bgHover:      _col("bgHover")       // shared hover square + hovered surfaces
    readonly property color border:       _col("border")       // hairline (--line)
    readonly property color borderStrong: _col("borderStrong") // (--line-2)
    readonly property color divider:      _col("divider")      // (--line)
    readonly property color text:         _col("text")         // primary cream
    readonly property color textDim:      _col("textDim")      // secondary (--dim)
    readonly property color faint:        _col("faint")        // tertiary / idle glyphs (--faint)
    readonly property color accent:       _col("accent")       // vermillion
    readonly property color accentSoft:   _col("accentSoft")   // accent tint bg
    readonly property color accentDim:    _col("accentDim")    // selected / active background tint
    readonly property color danger:       _col("danger")       // destructive
    readonly property color good:         _col("good")         // green (privacy/live cue)
    readonly property color success:      _col("success")      // pastel green (all-done / completed cue)
    readonly property color money:        _col("money")        // gold (finance dots / figures)
    readonly property color event:        _col("event")        // soft blue (Google-calendar event dot / times)
    readonly property color track:        _col("track")        // toggle / slider track

    // resting (collapsed, un-hovered) pill: translucent + dimmed (see init.qml).
    // NOTE: this is alpha translucency only — true backdrop blur needs the KWin
    // blur protocol, which Quickshell does not expose.
    readonly property color bgTranslucent: _col("bgTranslucent")
    // resting-pill gradient (translucent, no border): warmer/lighter top fading to
    // a darker bottom, so the floating pill blends with whatever is behind it.
    readonly property color bgGradTop:     _col("bgGradTop")
    readonly property color bgGradBottom:  _col("bgGradBottom")
    readonly property real idleOpacity:    0.86

    // ---- Appearance page metadata --------------------------------------------
    // Ordered, grouped list of the editable colours above. The Appearance page
    // renders one ColorField per entry (a group header starts a new section).
    readonly property var palette: [
        // Ordered as you'd build a theme top-down: the backgrounds first, then the
        // text on them, then the accent, then the hairline details, the semantic
        // status colours, and finally the niche resting-pill (collapsed) colours.
        { "group": "Surfaces",     "key": "bg",            "label": "Pill / panel base" },
        { "group": "Surfaces",     "key": "bgElevated",    "label": "Menus / popups" },
        { "group": "Surfaces",     "key": "card",          "label": "Notification cards" },
        { "group": "Surfaces",     "key": "row",           "label": "List rows / tiles" },
        { "group": "Surfaces",     "key": "rowHi",         "label": "Active / hover row" },
        { "group": "Surfaces",     "key": "bgHover",       "label": "Hover square" },
        { "group": "Surfaces",     "key": "desk",          "label": "Desktop wash" },
        { "group": "Text",         "key": "text",          "label": "Primary text" },
        { "group": "Text",         "key": "textDim",       "label": "Secondary text" },
        { "group": "Text",         "key": "faint",         "label": "Faint / idle glyphs" },
        { "group": "Accent",       "key": "accent",        "label": "Accent" },
        { "group": "Accent",       "key": "accentSoft",    "label": "Accent tint" },
        { "group": "Accent",       "key": "accentDim",     "label": "Accent selected bg" },
        { "group": "Lines",        "key": "border",        "label": "Hairline border" },
        { "group": "Lines",        "key": "borderStrong",  "label": "Strong border" },
        { "group": "Lines",        "key": "divider",       "label": "Divider" },
        { "group": "Lines",        "key": "track",         "label": "Toggle / slider track" },
        { "group": "Status",       "key": "good",          "label": "Good / live cue" },
        { "group": "Status",       "key": "success",       "label": "Success / completed" },
        { "group": "Status",       "key": "danger",        "label": "Danger / destructive" },
        { "group": "Status",       "key": "money",         "label": "Money / finance" },
        { "group": "Status",       "key": "event",         "label": "Calendar event" },
        { "group": "Resting pill", "key": "bgTranslucent", "label": "Resting fill" },
        { "group": "Resting pill", "key": "bgGradTop",     "label": "Resting gradient top" },
        { "group": "Resting pill", "key": "bgGradBottom",  "label": "Resting gradient bottom" }
    ]

    // ---- pre-configured themes (Appearance page grid) ----
    // `colors` is an overrides map; the empty map means "everything at defaults",
    // so applying "Default" simply clears the user's edits.
    readonly property var presets: [
        { "name": "Default", "colors": ({}) },
        { "name": "Catppuccin Mocha", "colors": ({
            "desk": "#11111b", "bg": "#1e1e2e", "bgElevated": "#252539", "card": "#252539",
            "row": "#313244", "rowHi": "#3d3355", "bgHover": "#3d3355",
            "border": "rgba(205, 214, 244, 0.12)", "borderStrong": "rgba(205, 214, 244, 0.22)",
            "divider": "rgba(205, 214, 244, 0.12)", "track": "rgba(205, 214, 244, 0.14)",
            "text": "#cdd6f4", "textDim": "#a6adc8", "faint": "#7f849c",
            "accent": "#cba6f7", "accentSoft": "rgba(203, 166, 247, 0.15)", "accentDim": "#3d3355",
            "danger": "#f38ba8", "good": "#a6e3a1", "success": "#94e2d5", "money": "#f9e2af", "event": "#89b4fa",
            "bgTranslucent": "rgba(30, 30, 46, 0.72)", "bgGradTop": "rgba(45, 45, 61, 0.82)", "bgGradBottom": "rgba(11, 11, 21, 0.66)"
        }) },
        { "name": "Catppuccin Latte", "colors": ({
            "desk": "#dce0e8", "bg": "#eff1f5", "bgElevated": "#e6e9ef", "card": "#e6e9ef",
            "row": "#dce0e8", "rowHi": "#e5dcf7", "bgHover": "#e5dcf7",
            "border": "rgba(76, 79, 105, 0.12)", "borderStrong": "rgba(76, 79, 105, 0.22)",
            "divider": "rgba(76, 79, 105, 0.12)", "track": "rgba(76, 79, 105, 0.14)",
            "text": "#4c4f69", "textDim": "#6c6f85", "faint": "#8c8fa1",
            "accent": "#8839ef", "accentSoft": "rgba(136, 57, 239, 0.15)", "accentDim": "#e5dcf7",
            "danger": "#d20f39", "good": "#179299", "success": "#40a02b", "money": "#df8e1d", "event": "#1e66f5",
            "bgTranslucent": "rgba(239, 241, 245, 0.72)", "bgGradTop": "rgba(249, 251, 255, 0.82)", "bgGradBottom": "rgba(214, 218, 226, 0.66)"
        }) },
        { "name": "Nord", "colors": ({
            "desk": "#242933", "bg": "#2e3440", "bgElevated": "#3b4252", "card": "#3b4252",
            "row": "#434c5e", "rowHi": "#4c566a", "bgHover": "#4c566a",
            "border": "rgba(236, 239, 244, 0.12)", "borderStrong": "rgba(236, 239, 244, 0.22)",
            "divider": "rgba(236, 239, 244, 0.12)", "track": "rgba(236, 239, 244, 0.14)",
            "text": "#eceff4", "textDim": "#c4ccd9", "faint": "#7b8494",
            "accent": "#88c0d0", "accentSoft": "rgba(136, 192, 208, 0.15)", "accentDim": "#4c566a",
            "danger": "#bf616a", "good": "#8fbcbb", "success": "#a3be8c", "money": "#ebcb8b", "event": "#81a1c1",
            "bgTranslucent": "rgba(46, 52, 64, 0.72)", "bgGradTop": "rgba(61, 67, 79, 0.82)", "bgGradBottom": "rgba(30, 35, 45, 0.66)"
        }) },
        { "name": "Dracula", "colors": ({
            "desk": "#191a21", "bg": "#21222c", "bgElevated": "#282a36", "card": "#282a36",
            "row": "#343746", "rowHi": "#44475a", "bgHover": "#44475a",
            "border": "rgba(248, 248, 242, 0.12)", "borderStrong": "rgba(248, 248, 242, 0.22)",
            "divider": "rgba(248, 248, 242, 0.12)", "track": "rgba(248, 248, 242, 0.14)",
            "text": "#f8f8f2", "textDim": "#c0c2d1", "faint": "#6272a4",
            "accent": "#bd93f9", "accentSoft": "rgba(189, 147, 249, 0.15)", "accentDim": "#44475a",
            "danger": "#ff5555", "good": "#50fa7b", "success": "#69ff94", "money": "#f1fa8c", "event": "#8be9fd",
            "bgTranslucent": "rgba(33, 34, 44, 0.72)", "bgGradTop": "rgba(48, 49, 59, 0.82)", "bgGradBottom": "rgba(19, 20, 27, 0.66)"
        }) },
        { "name": "Everforest Dark", "colors": ({
            "desk": "#1e2326", "bg": "#272e33", "bgElevated": "#2e383c", "card": "#2e383c",
            "row": "#374145", "rowHi": "#4c3743", "bgHover": "#4c3743",
            "border": "rgba(211, 198, 170, 0.12)", "borderStrong": "rgba(211, 198, 170, 0.22)",
            "divider": "rgba(211, 198, 170, 0.12)", "track": "rgba(211, 198, 170, 0.14)",
            "text": "#d3c6aa", "textDim": "#9da9a0", "faint": "#7a8478",
            "accent": "#a7c080", "accentSoft": "rgba(167, 192, 128, 0.15)", "accentDim": "#4c3743",
            "danger": "#e67e80", "good": "#83c092", "success": "#a7c080", "money": "#dbbc7f", "event": "#7fbbb3",
            "bgTranslucent": "rgba(39, 46, 51, 0.72)", "bgGradTop": "rgba(54, 61, 66, 0.82)", "bgGradBottom": "rgba(24, 29, 32, 0.66)"
        }) },
        { "name": "Kanagawa Wave", "colors": ({
            "desk": "#16161d", "bg": "#1f1f28", "bgElevated": "#2a2a37", "card": "#2a2a37",
            "row": "#363646", "rowHi": "#43242b", "bgHover": "#43242b",
            "border": "rgba(220, 215, 186, 0.12)", "borderStrong": "rgba(220, 215, 186, 0.22)",
            "divider": "rgba(220, 215, 186, 0.12)", "track": "rgba(220, 215, 186, 0.14)",
            "text": "#dcd7ba", "textDim": "#c8c093", "faint": "#727169",
            "accent": "#7e9cd8", "accentSoft": "rgba(126, 156, 216, 0.15)", "accentDim": "#43242b",
            "danger": "#e46876", "good": "#98bb6c", "success": "#87a987", "money": "#e6c384", "event": "#7fb4ca",
            "bgTranslucent": "rgba(31, 31, 40, 0.72)", "bgGradTop": "rgba(46, 46, 55, 0.82)", "bgGradBottom": "rgba(16, 16, 23, 0.66)"
        }) }
    ]

    // ---- colour helpers -------------------------------------------------------
    // parseColor(): turn any CSS colour string into a Qt colour. Supports #rgb,
    // #rgba, #rrggbb, #rrggbbaa, rgb()/rgba(), hsl()/hsla() (comma-, space- or
    // slash-separated, with optional % units) and falls back to letting Qt coerce
    // named colours ("red") / anything else it understands.
    function parseColor(str) {
        if (str === undefined || str === null)
            return Qt.rgba(0, 0, 0, 0);
        if (typeof str !== "string")
            return str;
        var s = str.trim();
        if (s === "")
            return Qt.rgba(0, 0, 0, 0);
        var m;
        if (s.charAt(0) === "#") {
            var h = s.substring(1);
            var r, g, b, a = 1;
            if (h.length === 3 || h.length === 4) {
                r = parseInt(h.charAt(0) + h.charAt(0), 16);
                g = parseInt(h.charAt(1) + h.charAt(1), 16);
                b = parseInt(h.charAt(2) + h.charAt(2), 16);
                if (h.length === 4)
                    a = parseInt(h.charAt(3) + h.charAt(3), 16) / 255;
            } else if (h.length === 6 || h.length === 8) {
                r = parseInt(h.substring(0, 2), 16);
                g = parseInt(h.substring(2, 4), 16);
                b = parseInt(h.substring(4, 6), 16);
                if (h.length === 8)
                    a = parseInt(h.substring(6, 8), 16) / 255;
            } else {
                return Qt.rgba(0, 0, 0, 0);
            }
            if (isNaN(r) || isNaN(g) || isNaN(b))
                return Qt.rgba(0, 0, 0, 0);
            return Qt.rgba(r / 255, g / 255, b / 255, a);
        }
        m = s.match(/^rgba?\((.+)\)$/i);
        if (m) {
            var pr = theme._parts(m[1]);
            return Qt.rgba(theme._chan(pr[0]), theme._chan(pr[1]), theme._chan(pr[2]),
                           pr.length > 3 ? theme._alpha(pr[3]) : 1);
        }
        m = s.match(/^hsla?\((.+)\)$/i);
        if (m) {
            var ph = theme._parts(m[1]);
            var hue = parseFloat(ph[0]) / 360;
            return Qt.hsla(hue < 0 ? 0 : (hue > 1 ? hue % 1 : hue),
                           theme._pct(ph[1]), theme._pct(ph[2]),
                           ph.length > 3 ? theme._alpha(ph[3]) : 1);
        }
        // named colour / anything Qt can coerce
        return s;
    }
    // split "255, 0, 0 / .5" or "255 0 0" into tokens
    function _parts(body) {
        return body.replace(/\//g, " ").split(/[\s,]+/).filter(function (x) { return x !== ""; });
    }
    // one rgb channel token → 0..1 ("255" or "50%")
    function _chan(t) {
        if (t === undefined) return 0;
        var v = t.indexOf("%") >= 0 ? parseFloat(t) / 100 : parseFloat(t) / 255;
        return isNaN(v) ? 0 : Math.max(0, Math.min(1, v));
    }
    // an alpha token → 0..1 ("0.5" or "50%")
    function _alpha(t) {
        if (t === undefined) return 1;
        var v = t.indexOf("%") >= 0 ? parseFloat(t) / 100 : parseFloat(t);
        return isNaN(v) ? 1 : Math.max(0, Math.min(1, v));
    }
    // a saturation/lightness token → 0..1 ("50%" or "0.5")
    function _pct(t) {
        if (t === undefined) return 0;
        var v = t.indexOf("%") >= 0 ? parseFloat(t) / 100 : parseFloat(t);
        return isNaN(v) ? 0 : Math.max(0, Math.min(1, v));
    }

    // formatColor(): a Qt colour → a CSS string in the requested unit
    // ("hex" | "rgb" | "hsl"); alpha is only emitted when < 1.
    function formatColor(col, unit) {
        var c = Qt.color(col);
        var a = c.a;
        var withA = a < 0.999;
        if (unit === "rgb") {
            var r = Math.round(c.r * 255), g = Math.round(c.g * 255), b = Math.round(c.b * 255);
            return withA ? "rgba(" + r + ", " + g + ", " + b + ", " + theme._ad(a) + ")"
                         : "rgb(" + r + ", " + g + ", " + b + ")";
        }
        if (unit === "hsl") {
            var hh = c.hslHue < 0 ? 0 : Math.round(c.hslHue * 360);
            var ss = Math.round(c.hslSaturation * 100);
            var ll = Math.round(c.hslLightness * 100);
            return withA ? "hsla(" + hh + ", " + ss + "%, " + ll + "%, " + theme._ad(a) + ")"
                         : "hsl(" + hh + ", " + ss + "%, " + ll + "%)";
        }
        // hex (default)
        var hx = "#" + theme._hx(c.r * 255) + theme._hx(c.g * 255) + theme._hx(c.b * 255);
        if (withA)
            hx += theme._hx(a * 255);
        return hx;
    }
    function _hx(n) {
        var v = Math.max(0, Math.min(255, Math.round(n))).toString(16);
        return v.length < 2 ? "0" + v : v;
    }
    function _ad(a) { return Math.round(a * 100) / 100; }

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
