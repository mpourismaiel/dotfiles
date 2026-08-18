pragma ComponentBehavior: Bound
// AppearanceSettings.qml — the Settings → Appearance page. Lets the user retheme
// the whole pill live: a grid of pre-configured themes at the top, then a wall of
// per-colour rows (swatch + text input). Only the title + footer are pinned;
// everything between scrolls in one Flickable. The colour picker opens as a shared
// dropdown (pickerLayer) over the rows — clicking a row's swatch anchors it there.
// The footer carries the colour-unit switch (HEX / RGB / HSL) and Import/Export.
//
// Everything persists to theme.json via the shared themeSettings JsonAdapter
// (bound in init.qml). Writes reassign `themeSettings.colors` whole so the adapter
// flushes and every Theme binding re-evaluates — recolouring the pill instantly.
// Import/Export move the theme through the system clipboard (wl-copy / wl-paste).
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    required property var theme
    required property var themeSettings     // JsonAdapter { var colors }  (from init.qml)

    property string unit: "hex"             // hex | rgb | hsl (colour-input format)
    property string status: ""              // transient footer toast

    // ---- colour-picker dropdown (rendered once by pickerLayer, over the rows) ----
    property string openKey: ""             // palette key whose picker is open ("" = none)
    property var openField: null            // the ColorField the dropdown anchors to
    function togglePicker(key, field) {
        if (root.openKey === key) { root.closePicker(); return; }
        root.openKey = key;
        root.openField = field;
        dropPicker.seedFrom(root.theme.parseColor(root.theme.colorString(key)));
    }
    function closePicker() { root.openKey = ""; root.openField = null; }

    // ---- persistence helpers (always reassign the whole map, never mutate) ----
    function _clone() {
        var src = root.themeSettings.colors || ({});
        var out = ({});
        for (var k in src) out[k] = src[k];
        return out;
    }
    function setColor(key, css) { var m = root._clone(); m[key] = css; root.themeSettings.colors = m; }
    function clearColor(key)    { var m = root._clone(); delete m[key]; root.themeSettings.colors = m; }
    function applyPreset(p) {
        var m = ({}); var src = p.colors || ({});
        for (var k in src) m[k] = src[k];
        root.themeSettings.colors = m;
    }
    function isOverridden(key) {
        var src = root.themeSettings.colors;
        return !!src && src[key] !== undefined && src[key] !== "";
    }
    function overrideCount() {
        var src = root.themeSettings.colors; if (!src) return 0;
        var n = 0; for (var k in src) if (src[k] !== undefined && src[k] !== "") n++;
        return n;
    }

    // effective colour for a preset key (preset override → shipped default)
    function presetColor(p, key) {
        var src = p.colors || ({});
        var v = (src[key] !== undefined && src[key] !== "") ? src[key] : root.theme.defaults[key];
        return root.theme.parseColor(v);
    }
    function presetActive(p) {
        // Default (empty map) is active whenever the user has no overrides.
        var keys = 0; var src = p.colors || ({}); for (var k in src) keys++;
        if (keys === 0) return root.overrideCount() === 0;
        // otherwise: every preset colour must currently be in effect
        for (var kk in src) if (root.theme.colorString(kk) !== src[kk]) return false;
        return root.overrideCount() === keys;
    }

    function flash(msg) { root.status = msg; statusTimer.restart(); }
    Timer { id: statusTimer; interval: 2200; onTriggered: root.status = ""; }

    // ---- clock / agenda design selection (persisted in theme.json) ----
    function clockStyleId() {
        return (root.themeSettings && root.themeSettings.clockStyle) ? root.themeSettings.clockStyle : "1a";
    }
    function clockStyleActive(id) { return root.clockStyleId() === id; }
    function setClockStyle(id) {
        if (root.theme.fontAvailable(root.theme.clockStyleDef(id).font) && root.themeSettings)
            root.themeSettings.clockStyle = id;
    }

    // ---- Export / Import via the clipboard ----
    // Export the FULL palette (every key resolved) so the theme is portable.
    function exportTheme() {
        var out = ({});
        for (var i = 0; i < root.theme.palette.length; i++) {
            var key = root.theme.palette[i].key;
            out[key] = root.theme.colorString(key);
        }
        copyProc.command = ["wl-copy", JSON.stringify(out, null, 2)];
        copyProc.running = true;
        root.flash("Theme copied to clipboard");
    }
    function importTheme() { pasteProc.running = true; }
    Process { id: copyProc }
    Process {
        id: pasteProc
        command: ["wl-paste", "--no-newline"]
        stdout: StdioCollector {
            onStreamFinished: {
                var m = ({});
                try { m = JSON.parse(this.text); }
                catch (e) { root.flash("Clipboard isn't a valid theme"); return; }
                if (!m || typeof m !== "object") { root.flash("Clipboard isn't a valid theme"); return; }
                // keep only known palette keys
                var out = ({}); var n = 0;
                for (var i = 0; i < root.theme.palette.length; i++) {
                    var key = root.theme.palette[i].key;
                    if (m[key] !== undefined && m[key] !== "") { out[key] = "" + m[key]; n++; }
                }
                root.themeSettings.colors = out;
                root.flash(n > 0 ? ("Imported theme (" + n + " colours)") : "No colours found");
            }
        }
    }

    // ======================= fixed title =======================
    Text {
        id: titleText
        anchors.top: parent.top
        anchors.left: parent.left
        text: "Appearance"
        color: root.theme.text
        font.family: root.theme.serif
        font.pixelSize: root.theme.fsLarge + 4
    }
    Rectangle {
        id: titleRule
        anchors.top: titleText.bottom
        anchors.topMargin: 8
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: root.theme.divider
    }

    // ======================= scrolling body (everything but title + footer) ==
    Flickable {
        id: scroll
        anchors.top: titleRule.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footer.top
        anchors.bottomMargin: 8
        contentHeight: body.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: body
            width: scroll.width
            spacing: 10

            Text {
                width: body.width
                wrapMode: Text.WordWrap
                text: "Recolour the pill. Pick a starting theme, then fine-tune any colour "
                    + "below — changes apply live and save to your pill's theme.json."
                color: root.theme.textDim
                font.family: root.theme.family
                font.pixelSize: root.theme.fsSmall
            }

            // ---- clock and agenda design ----
            // Re-skin the resting pill's clock + agenda (deadline / meeting) line.
            // Each option shows a live preview; a style whose font isn't installed
            // is greyed out with the font it needs, and can't be selected.
            Text {
                text: "CLOCK AND AGENDA"
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
                font.capitalization: Font.AllUppercase
            }
            Text {
                width: body.width
                wrapMode: Text.WordWrap
                text: "Choose how the collapsed pill tells the time and shows what's due."
                color: root.theme.textDim
                font.family: root.theme.family
                font.pixelSize: root.theme.fsSmall
            }
            Flow {
                width: body.width
                spacing: 10
                Repeater {
                    model: root.theme.clockStyles
                    delegate: Rectangle {
                        id: styleCard
                        required property var modelData
                        readonly property bool avail: root.theme.fontAvailable(styleCard.modelData.font)
                        readonly property bool active: root.clockStyleActive(styleCard.modelData.id)
                        // exactly two per row: fill the body width (minus the gap)
                        width: (body.width - 10) / 2
                        height: 150
                        radius: root.theme.radiusCard
                        color: styleCard.active ? root.theme.accentSoft
                             : (styleMa.containsMouse && styleCard.avail ? root.theme.rowHi : root.theme.row)
                        border.width: styleCard.active ? 1 : 0
                        border.color: root.theme.accent
                        opacity: styleCard.avail ? 1 : 0.6

                        Column {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            // live preview: a real resting pill (scaled to fit) on a
                            // desk-tone backdrop, so the translucent surface reads right.
                            Rectangle {
                                id: previewStrip
                                width: parent.width
                                height: 58
                                radius: root.theme.radiusBtn
                                color: root.theme.desk
                                border.width: 1
                                border.color: root.theme.border
                                clip: true
                                Item {
                                    id: previewHost
                                    anchors.centerIn: parent
                                    // the resting pill sized by init's own rule …
                                    width: Math.max(56, cp.implicitWidth + 23)
                                    height: Math.max(cp.hasUnderline ? 48 : 28, cp.implicitHeight + 7)
                                    // … then shrunk to fit if the agenda line runs wide
                                    scale: Math.min(1, (previewStrip.width - 26) / width)
                                    PillSurface {
                                        anchors.fill: parent
                                        theme: root.theme
                                        radius: Math.min(root.theme.radiusPanel, height / 2)
                                        wing: 12
                                        fillColor: root.theme.bgTranslucent
                                    }
                                    CollapsedPill {
                                        id: cp
                                        anchors.centerIn: parent
                                        theme: root.theme
                                        styleOverride: styleCard.modelData.id
                                        clock: "09:41"
                                        // a compact sample agenda: one due today + a soon meeting
                                        todayCount: 1
                                        meetingMins: 8
                                    }
                                }
                            }
                            // name + active tick
                            Row {
                                width: parent.width
                                spacing: 6
                                Text {
                                    width: parent.width - (styleCard.active ? 22 : 0)
                                    elide: Text.ElideRight
                                    text: styleCard.modelData.name
                                    color: styleCard.active ? root.theme.accent : root.theme.text
                                    font.family: root.theme.family
                                    font.pixelSize: root.theme.fsNormal
                                }
                                MSym {
                                    visible: styleCard.active
                                    anchors.verticalCenter: parent.verticalCenter
                                    icon: "check_circle"
                                    fill: 1
                                    size: 16
                                    color: root.theme.accent
                                }
                            }
                            // description, or the missing-font warning (icon + text)
                            Row {
                                width: parent.width
                                spacing: 5
                                MSym {
                                    visible: !styleCard.avail
                                    anchors.top: parent.top
                                    anchors.topMargin: 1
                                    icon: "warning"
                                    fill: 1
                                    size: 13
                                    color: root.theme.danger
                                }
                                Text {
                                    width: parent.width - (styleCard.avail ? 0 : 18)
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    text: styleCard.avail ? styleCard.modelData.desc
                                        : ("Requires the " + styleCard.modelData.font + " font — install it to enable.")
                                    color: styleCard.avail ? root.theme.faint : root.theme.danger
                                    font.family: root.theme.family
                                    font.pixelSize: root.theme.fsSmall
                                }
                            }
                        }
                        // top-most so the preview's own mouse areas never intercept
                        MouseArea {
                            id: styleMa
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: styleCard.avail
                            cursorShape: styleCard.avail ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.setClockStyle(styleCard.modelData.id)
                        }
                        Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                    }
                }
            }
            Rectangle { width: body.width; height: 1; color: root.theme.divider }

            // ---- theme presets grid ----
            Text {
                text: "THEMES"
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
                font.capitalization: Font.AllUppercase
            }
            Flow {
                width: body.width
                spacing: 8
                Repeater {
                    model: root.theme.presets
                    delegate: Rectangle {
                        id: presetCard
                        required property var modelData
                        readonly property bool active: root.presetActive(presetCard.modelData)
                        width: 150
                        height: 64
                        radius: root.theme.radiusBtn
                        color: presetMa.containsMouse ? root.theme.rowHi : root.theme.row
                        border.width: presetCard.active ? 1 : 0
                        border.color: root.theme.accent

                        // three-swatch preview (bg / accent / text), top-left
                        Row {
                            id: swatches
                            anchors.top: parent.top
                            anchors.topMargin: 12
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            spacing: -6
                            Repeater {
                                model: ["bg", "accent", "text"]
                                delegate: Rectangle {
                                    required property var modelData
                                    width: 18
                                    height: 18
                                    radius: 9
                                    border.width: 1
                                    border.color: root.theme.bg
                                    color: root.presetColor(presetCard.modelData, modelData)
                                }
                            }
                        }
                        // full-width name below, so long theme names don't elide
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 10
                            elide: Text.ElideRight
                            text: presetCard.modelData.name
                            color: presetCard.active ? root.theme.accent : root.theme.text
                            font.family: root.theme.family
                            font.pixelSize: root.theme.fsNormal
                        }
                        MouseArea {
                            id: presetMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.applyPreset(presetCard.modelData)
                        }
                        Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                    }
                }
            }

            // ---- colours ----
            Text {
                text: "COLORS"
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
                font.capitalization: Font.AllUppercase
            }
            Rectangle { width: body.width; height: 1; color: root.theme.divider }

            Column {
                id: wallCol
                width: body.width
                spacing: 2

                Repeater {
                    model: root.theme.palette
                    delegate: Column {
                        id: paletteRow
                        required property int index
                        required property var modelData
                        width: wallCol.width
                        spacing: 2

                        // group header (only when the group changes)
                        Item {
                            width: parent.width
                            height: 22
                            visible: paletteRow.index === 0
                                 || root.theme.palette[paletteRow.index - 1].group !== paletteRow.modelData.group
                            Text {
                                anchors.left: parent.left
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 3
                                text: paletteRow.modelData.group
                                color: root.theme.textDim
                                font.family: root.theme.mono
                                font.pixelSize: root.theme.fsSmall - 1
                                font.letterSpacing: root.theme.labelSpacing
                                font.capitalization: Font.AllUppercase
                            }
                        }

                        ColorField {
                            id: colorField
                            width: parent.width
                            theme: root.theme
                            label: paletteRow.modelData.label
                            unit: root.unit
                            valueStr: root.theme.colorString(paletteRow.modelData.key)
                            overridden: root.isOverridden(paletteRow.modelData.key)
                            active: root.openKey === paletteRow.modelData.key
                            onEdited: (value) => root.setColor(paletteRow.modelData.key, value)
                            onCleared: root.clearColor(paletteRow.modelData.key)
                            onSwatchClicked: root.togglePicker(paletteRow.modelData.key, colorField)
                        }
                    }
                }
            }
            // breathing room so the last picker clears the footer when expanded
            Item { width: 1; height: 6 }
        }
    }

    // ======================= sticky footer =======================
    Rectangle {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 40
        color: root.theme.bg

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: root.theme.divider
        }

        // ---- unit switch (segmented) ----
        Row {
            id: unitSwitch
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 2
            spacing: 4
            Repeater {
                model: [
                    { "u": "hex", "label": "HEX" },
                    { "u": "rgb", "label": "RGB" },
                    { "u": "hsl", "label": "HSL" }
                ]
                delegate: Rectangle {
                    id: seg
                    required property int index
                    required property var modelData
                    readonly property bool on: root.unit === seg.modelData.u
                    width: 44
                    height: 24
                    color: seg.on ? root.theme.accentSoft
                         : (segMa.containsMouse ? root.theme.rowHi : root.theme.bgElevated)
                    border.width: seg.on ? 1 : 0
                    border.color: root.theme.accent
                    radius: root.theme.radiusBtn
                    Text {
                        anchors.centerIn: parent
                        text: seg.modelData.label
                        color: seg.on ? root.theme.accent : root.theme.textDim
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                        font.letterSpacing: root.theme.labelSpacing
                    }
                    MouseArea {
                        id: segMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.unit = seg.modelData.u
                    }
                    Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                }
            }
        }

        // ---- transient status toast (centre) ----
        Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 2
            text: root.status
            visible: root.status !== ""
            color: root.theme.faint
            font.family: root.theme.family
            font.italic: true
            font.pixelSize: root.theme.fsSmall
            elide: Text.ElideRight
        }

        // ---- import / export ----
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 2
            spacing: 6
            Repeater {
                model: [
                    { "act": "import", "icon": "content_paste", "label": "Import" },
                    { "act": "export", "icon": "content_copy",  "label": "Export" }
                ]
                delegate: Rectangle {
                    id: ieBtn
                    required property var modelData
                    width: ieRow.width + 18
                    height: 26
                    radius: root.theme.radiusBtn
                    color: ieMa.containsMouse ? root.theme.rowHi : root.theme.bgElevated
                    border.width: 1
                    border.color: root.theme.border
                    Row {
                        id: ieRow
                        anchors.centerIn: parent
                        spacing: 5
                        MSym {
                            anchors.verticalCenter: parent.verticalCenter
                            icon: ieBtn.modelData.icon
                            size: 14
                            color: ieMa.containsMouse ? root.theme.text : root.theme.textDim
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: ieBtn.modelData.label
                            color: ieMa.containsMouse ? root.theme.text : root.theme.textDim
                            font.family: root.theme.family
                            font.pixelSize: root.theme.fsSmall
                        }
                    }
                    MouseArea {
                        id: ieMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (ieBtn.modelData.act === "export") root.exportTheme();
                            else root.importTheme();
                        }
                    }
                    Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                }
            }
        }
    }

    // scrolling dismisses the open picker (the dropdown is anchored to a fixed
    // scene point, so it would otherwise drift away from its row)
    Connections {
        target: scroll
        function onContentYChanged() { root.closePicker(); }
    }

    // ======================= shared colour-picker dropdown =======================
    // Last child → paints ABOVE every row (z only orders within a parent, so an
    // inline picker would sit behind the rows below it). Renders the open field's
    // ColorPicker at the field's swatch, dropping down (or up, near the footer).
    Item {
        id: pickerLayer
        anchors.fill: parent
        z: 1000
        visible: root.openKey !== ""

        // click-away closes
        MouseArea { anchors.fill: parent; onClicked: root.closePicker() }

        Rectangle {
            id: dropBox
            // swatch top-left, mapped into this layer's coordinates
            readonly property point ap: (root.openField && pickerLayer.visible)
                ? root.openField.anchorItem.mapToItem(pickerLayer, 0, 0) : Qt.point(0, 0)
            readonly property real swH: root.openField ? root.openField.anchorItem.height : 26
            readonly property real belowY: ap.y + swH + 6
            readonly property real aboveY: ap.y - dropBox.height - 6

            width: 312
            height: dropPicker.implicitHeight + 24
            radius: root.theme.radiusPanel
            color: root.theme.bgElevated
            border.width: 1
            border.color: root.theme.borderStrong
            x: Math.max(6, Math.min(dropBox.ap.x, pickerLayer.width - dropBox.width - 6))
            // drop down if it fits above the footer, else flip up above the swatch
            y: (dropBox.belowY + dropBox.height <= footer.y) ? dropBox.belowY
             : Math.max(6, dropBox.aboveY)

            // swallow clicks on the box so they don't reach the click-away layer
            MouseArea { anchors.fill: parent }

            ColorPicker {
                id: dropPicker
                anchors.fill: parent
                anchors.margins: 12
                theme: root.theme
                onPicked: (value) => {
                    if (root.openKey !== "")
                        root.setColor(root.openKey, root.theme.formatColor(value, root.unit));
                }
            }
        }
    }
}
