pragma ComponentBehavior: Bound
// RecordControls.qml — the screen-record settings, hosted INSIDE the pill (the pill
// morphs to this while mode === "recConfig"). Whole-screen / select-area, mic +
// speaker (device dropdowns), webcam + its config row, fps / codec / quality /
// cursor, and the Record button (gated by the webcam ≥50%-visible check). The
// fullscreen region drawing + webcam preview happen on RecordCanvas; screen choice
// is the KWin portal's job at record start. implicitWidth/Height drive the pill size.
import QtQuick
import QtMultimedia

Item {
    id: ctl
    required property var state
    required property var theme
    required property var rc
    property bool warn: false

    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight

    // the Select whose list is open (rendered by dropLayer, above all controls)
    property var openSel: null

    // roundness dropdown selection == the controller's mode
    readonly property string roundTok: ctl.rc.webcamRoundMode
    function pickRound(t) {
        // switching to custom seeds the px field from the current effective radius
        if (t === "custom") ctl.rc.webcamRound = Math.round(ctl.rc.webcamRoundEff);
        ctl.rc.webcamRoundMode = t;
    }

    MediaDevices { id: media }
    readonly property var cameras: {
        const out = [], vs = media.videoInputs || [];
        for (let i = 0; i < vs.length; i++) out.push({ token: vs[i].id, label: vs[i].description });
        return out;
    }
    function tryStart() { if (ctl.rc.webcamVisibleOk()) ctl.rc.start(); else ctl.warn = true; }

    // ============================ shared bits ===============================
    component Chip: Rectangle {
        id: c
        property string label: ""
        property bool on: false
        property string glyph: ""
        signal clicked()
        implicitWidth: crow.implicitWidth + (c.label ? 20 : 14); height: 30; radius: ctl.theme.radiusBtn
        color: on ? ctl.theme.accentSoft : (cma.containsMouse ? ctl.theme.bgHover : ctl.theme.row)
        border.color: on ? ctl.theme.accent : ctl.theme.border; border.width: 1
        Row { id: crow; anchors.centerIn: parent; spacing: 6
            MSym { visible: c.glyph !== ""; anchors.verticalCenter: parent.verticalCenter
                   icon: c.glyph; size: 17; color: c.on ? ctl.theme.accent : ctl.theme.textDim }
            Text { visible: c.label !== ""; anchors.verticalCenter: parent.verticalCenter; text: c.label
                   color: c.on ? ctl.theme.text : ctl.theme.textDim
                   font.family: ctl.theme.family; font.pixelSize: ctl.theme.fsNormal }
        }
        MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor; onClicked: c.clicked() }
        Behavior on color { ColorAnimation { duration: ctl.theme.animFast } }
    }
    component Seg: Row {
        id: seg
        property var options: []
        property var current: ""
        signal picked(var value)
        spacing: 0
        Repeater {
            model: seg.options
            Rectangle {
                required property var modelData
                readonly property bool sel: seg.current === modelData.value
                width: segt.implicitWidth + 16; height: 30
                color: sel ? ctl.theme.accentSoft : (sma.containsMouse ? ctl.theme.bgHover : ctl.theme.row)
                border.color: sel ? ctl.theme.accent : ctl.theme.border; border.width: 1
                Text { id: segt; anchors.centerIn: parent; text: parent.modelData.label
                       color: parent.sel ? ctl.theme.text : ctl.theme.textDim
                       font.family: ctl.theme.family; font.pixelSize: ctl.theme.fsNormal }
                MouseArea { id: sma; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor; onClicked: seg.picked(parent.modelData.value) }
            }
        }
    }
    // dropdown over [{token,label}]. The LIST is not drawn here — a nested popup
    // can't paint above later sibling rows (z only orders within a parent), so it
    // would appear behind the controls below it. Instead the open Select registers
    // itself as `ctl.openSel` and the shared `dropLayer` overlay (last child of the
    // root, top of everything) renders its list at the mapped position.
    component Select: Item {
        id: sel
        property var options: []
        property string currentToken: ""
        property string placeholder: "—"
        signal picked(string token)
        readonly property bool openList: ctl.openSel === sel
        readonly property string curLabel: {
            for (const o of options) if (o.token === currentToken) return o.label;
            return placeholder;
        }
        function pick(t) { sel.picked(t); ctl.openSel = null; }
        implicitWidth: 190; height: 30
        Rectangle {
            anchors.fill: parent; radius: ctl.theme.radiusBtn
            color: (sel.openList || dma.containsMouse) ? ctl.theme.bgHover : ctl.theme.row
            border.color: sel.openList ? ctl.theme.accent : ctl.theme.border; border.width: 1
            Text { anchors.left: parent.left; anchors.leftMargin: 10; anchors.right: chev.left
                   anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                   text: sel.curLabel; color: ctl.theme.text
                   font.family: ctl.theme.family; font.pixelSize: ctl.theme.fsSmall }
            MSym { id: chev; anchors.right: parent.right; anchors.rightMargin: 6
                   anchors.verticalCenter: parent.verticalCenter
                   icon: sel.openList ? "expand_less" : "expand_more"; size: 18; color: ctl.theme.textDim }
            MouseArea { id: dma; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ctl.openSel = (ctl.openSel === sel ? null : sel) }
        }
    }

    // a small ± stepper button (shared look with the record chips)
    component SBtn: Rectangle {
        id: sb
        property string glyph: ""
        signal clicked()
        width: 26; height: 26; radius: ctl.theme.radiusBtn
        color: sbma.containsMouse ? ctl.theme.bgHover : ctl.theme.row
        border.color: ctl.theme.border; border.width: 1
        MSym { anchors.centerIn: parent; icon: sb.glyph; size: 16; color: ctl.theme.textDim }
        MouseArea { id: sbma; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor; onClicked: sb.clicked() }
        Behavior on color { ColorAnimation { duration: ctl.theme.animFast } }
    }
    // a labelled fine stepper: LABEL − value + . `changed(v)` fires the new value.
    component Stepper: Row {
        id: st
        property string label: ""
        property int value: 0
        property int min: 0
        property int max: 9999
        property int step: 10
        property string suffix: ""
        signal changed(int v)
        spacing: 4
        Text { anchors.verticalCenter: parent.verticalCenter; text: st.label; color: ctl.theme.textDim
               font.family: ctl.theme.mono; font.pixelSize: ctl.theme.fsSmall }
        SBtn { glyph: "remove"; onClicked: st.changed(Math.max(st.min, st.value - st.step)) }
        Text { anchors.verticalCenter: parent.verticalCenter; width: 40; horizontalAlignment: Text.AlignHCenter
               text: st.value + st.suffix; color: ctl.theme.text
               font.family: ctl.theme.mono; font.pixelSize: ctl.theme.fsNormal }
        SBtn { glyph: "add"; onClicked: st.changed(Math.min(st.max, st.value + st.step)) }
    }

    // ============================ content ==================================
    Column {
        id: content
        spacing: 12

        // header: back chevron + title (replaces the old close button)
        CaptureHeader { theme: ctl.theme; title: "Record screen"; onBack: ctl.state.cancel() }

        // row 1: area + sources
        Row {
            spacing: 8
            Chip { glyph: "fullscreen"; label: "Whole screen"; on: !ctl.rc.useRegion
                   onClicked: { ctl.rc.useRegion = false; ctl.state.region = Qt.rect(0,0,0,0); } }
            Chip { glyph: "crop"; label: "Select area"; on: ctl.rc.useRegion
                   onClicked: ctl.rc.useRegion = true }
            Rectangle { width: 1; height: 30; color: ctl.theme.divider }
            Chip { glyph: "mic"; label: "Mic"; on: ctl.rc.micOn; onClicked: ctl.rc.micOn = !ctl.rc.micOn }
            Select { visible: ctl.rc.micOn; options: ctl.rc.mics; currentToken: ctl.rc.micDev
                     placeholder: "default mic"; onPicked: (t) => ctl.rc.micDev = t }
            Chip { glyph: "volume_up"; label: "Speaker"; on: ctl.rc.spkOn; onClicked: ctl.rc.spkOn = !ctl.rc.spkOn }
            Select { visible: ctl.rc.spkOn; options: ctl.rc.speakers; currentToken: ctl.rc.spkDev
                     placeholder: "default output"; onPicked: (t) => ctl.rc.spkDev = t }
            Rectangle { width: 1; height: 30; color: ctl.theme.divider }
            Chip { glyph: "videocam"; label: "Webcam"; on: ctl.rc.webcamOn; onClicked: ctl.rc.webcamOn = !ctl.rc.webcamOn }
        }

        // row 1.5: webcam config (only when the webcam is on)
        Row {
            visible: ctl.rc.webcamOn
            spacing: 8
            Select { width: 170; options: ctl.cameras; currentToken: ctl.rc.webcamDev
                     placeholder: "default camera"; onPicked: (t) => ctl.rc.webcamDev = t }
            Rectangle { width: 1; height: 30; color: ctl.theme.divider }
            // fine size/roundness — applied live (WebcamOverlay binds rc.* directly)
            Stepper { anchors.verticalCenter: parent.verticalCenter; label: "W"; value: ctl.rc.webcamW
                      min: 120; max: 960; step: 20; onChanged: (v) => ctl.rc.webcamW = v }
            Stepper { anchors.verticalCenter: parent.verticalCenter; label: "H"; value: ctl.rc.webcamH
                      min: 90; max: 720; step: 20; onChanged: (v) => ctl.rc.webcamH = v }
            // roundness: a dropdown of presets + a custom px input
            Text { anchors.verticalCenter: parent.verticalCenter; text: "ROUND"; color: ctl.theme.textDim
                   font.family: ctl.theme.mono; font.pixelSize: ctl.theme.fsSmall }
            Select { anchors.verticalCenter: parent.verticalCenter; implicitWidth: 130
                     options: [{token:"10",label:"10 px"},{token:"20",label:"20 px"},
                               {token:"full",label:"Full round"},{token:"custom",label:"Custom…"}]
                     currentToken: ctl.roundTok; onPicked: (t) => ctl.pickRound(t) }
            Stepper { visible: ctl.rc.webcamRoundMode === "custom"; anchors.verticalCenter: parent.verticalCenter
                      label: "PX"; value: ctl.rc.webcamRound; min: 0
                      max: Math.round(Math.min(ctl.rc.webcamW, ctl.rc.webcamH) / 2)
                      step: 2; onChanged: (v) => ctl.rc.webcamRound = v }
            Rectangle { width: 1; height: 30; color: ctl.theme.divider }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "OPACITY"; color: ctl.theme.textDim
                   font.family: ctl.theme.mono; font.pixelSize: ctl.theme.fsSmall }
            Seg { current: ctl.rc.webcamOpacity
                  options: [{value:1.0,label:"100"},{value:0.8,label:"80"},{value:0.6,label:"60"}]
                  onPicked: (v) => ctl.rc.webcamOpacity = v }
            Chip { glyph: "flare"; label: "Shadow"; on: ctl.rc.webcamShadow; onClicked: ctl.rc.webcamShadow = !ctl.rc.webcamShadow }
            Rectangle { width: 1; height: 30; color: ctl.theme.divider }
            Chip { glyph: "north_west"; onClicked: { ctl.rc.webcamX = 40; ctl.rc.webcamY = 40; } }
            Chip { glyph: "north_east"; onClicked: { ctl.rc.webcamX = ctl.rc.screenW - ctl.rc.webcamW - 40; ctl.rc.webcamY = 40; } }
            Chip { glyph: "south_west"; onClicked: { ctl.rc.webcamX = 40; ctl.rc.webcamY = ctl.rc.screenH - ctl.rc.webcamH - 40; } }
            Chip { glyph: "south_east"; onClicked: { ctl.rc.webcamX = ctl.rc.screenW - ctl.rc.webcamW - 40; ctl.rc.webcamY = ctl.rc.screenH - ctl.rc.webcamH - 40; } }
        }

        // row 2: fps / codec / quality / cursor
        Row {
            spacing: 8
            Text { anchors.verticalCenter: parent.verticalCenter; text: "FPS"; color: ctl.theme.textDim
                   font.family: ctl.theme.mono; font.pixelSize: ctl.theme.fsSmall }
            Seg { current: ctl.rc.fps
                  options: [{value:30,label:"30"},{value:60,label:"60"},{value:120,label:"120"}]
                  onPicked: (v) => ctl.rc.fps = v }
            Rectangle { width: 1; height: 30; color: ctl.theme.divider }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "CODEC"; color: ctl.theme.textDim
                   font.family: ctl.theme.mono; font.pixelSize: ctl.theme.fsSmall }
            Seg { current: ctl.rc.codec
                  options: [{value:"h264",label:"H.264"},{value:"hevc",label:"HEVC"},{value:"av1",label:"AV1"}]
                  onPicked: (v) => ctl.rc.codec = v }
            Rectangle { width: 1; height: 30; color: ctl.theme.divider }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "QUALITY"; color: ctl.theme.textDim
                   font.family: ctl.theme.mono; font.pixelSize: ctl.theme.fsSmall }
            Seg { current: ctl.rc.quality
                  options: [{value:"medium",label:"Med"},{value:"high",label:"High"},{value:"very_high",label:"V.High"},{value:"ultra",label:"Ultra"}]
                  onPicked: (v) => ctl.rc.quality = v }
            Rectangle { width: 1; height: 30; color: ctl.theme.divider }
            Chip { glyph: "mouse"; label: "Cursor"; on: ctl.rc.cursor; onClicked: ctl.rc.cursor = !ctl.rc.cursor }
        }

        // record + cancel
        Row {
            spacing: 12
            Rectangle {
                width: 150; height: 38; radius: ctl.theme.radiusBtn
                color: rbma.containsMouse ? Qt.lighter(ctl.theme.accent, 1.1) : ctl.theme.accent
                Row { anchors.centerIn: parent; spacing: 8
                    Rectangle { width: 12; height: 12; radius: 6; color: "white"; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "Record"; color: "white"; font.family: ctl.theme.family
                           font.pixelSize: ctl.theme.fsNormal; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea { id: rbma; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor; onClicked: ctl.tryStart() }
            }
            Text { anchors.verticalCenter: parent.verticalCenter; width: 240; wrapMode: Text.WordWrap
                   text: "Screen is chosen by the KWin portal on start (remembered after the first time)."
                   color: ctl.theme.faint; font.family: ctl.theme.family; font.pixelSize: ctl.theme.fsSmall }
        }
    }

    // webcam-offscreen alert (covers the controls)
    Rectangle {
        visible: ctl.warn
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55); radius: ctl.theme.radiusPanel
        MouseArea { anchors.fill: parent }
        Column {
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 360)
            spacing: 10
            Text { width: parent.width; wrapMode: Text.WordWrap
                   text: "The webcam is mostly off-screen"; color: ctl.theme.text
                   font.family: ctl.theme.family; font.pixelSize: ctl.theme.fsLarge; font.bold: true }
            Text { width: parent.width; wrapMode: Text.WordWrap
                   text: "Reposition it (drag or corner-snap), or record anyway."
                   color: ctl.theme.textDim; font.family: ctl.theme.family; font.pixelSize: ctl.theme.fsNormal }
            Row {
                anchors.right: parent.right; spacing: 8
                Chip { label: "Reposition"; glyph: "open_with"; onClicked: ctl.warn = false }
                Rectangle {
                    width: 130; height: 30; radius: ctl.theme.radiusBtn; color: ctl.theme.accent
                    Text { anchors.centerIn: parent; text: "Record anyway"; color: "white"
                           font.family: ctl.theme.family; font.pixelSize: ctl.theme.fsNormal; font.bold: true }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: { ctl.warn = false; ctl.rc.start(); } }
                }
            }
        }
    }

    // ---- shared dropdown overlay (last child → paints ABOVE every control) ----
    // Renders the open Select's list at its mapped position so the popup's
    // background + rows sit on top of everything, instead of behind the rows below.
    Item {
        id: dropLayer
        anchors.fill: parent
        z: 1000
        visible: ctl.openSel !== null
        // click-away: anywhere outside the list closes the dropdown
        MouseArea { anchors.fill: parent; onClicked: ctl.openSel = null }
        Rectangle {
            id: dropBox
            readonly property var sel: ctl.openSel
            readonly property point p: sel ? sel.mapToItem(dropLayer, 0, sel.height) : Qt.point(0, 0)
            visible: sel !== null
            x: p.x; y: p.y + 4
            width: sel ? sel.width : 0
            height: Math.min(dropCol.implicitHeight + 8, 220)
            radius: ctl.theme.radiusBtn
            color: ctl.theme.bgElevated; border.color: ctl.theme.border; border.width: 1
            clip: true
            Column {
                id: dropCol
                width: parent.width; y: 4
                Repeater {
                    model: dropBox.sel ? dropBox.sel.options : []
                    Rectangle {
                        required property var modelData
                        width: parent.width; height: 28
                        readonly property bool cur: dropBox.sel && dropBox.sel.currentToken === modelData.token
                        color: oma.containsMouse ? ctl.theme.bgHover : (cur ? ctl.theme.accentSoft : "transparent")
                        Text { anchors.left: parent.left; anchors.leftMargin: 10; anchors.right: parent.right
                               anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                               elide: Text.ElideRight; text: modelData.label
                               color: parent.cur ? ctl.theme.accent : ctl.theme.text
                               font.family: ctl.theme.family; font.pixelSize: ctl.theme.fsSmall }
                        MouseArea { id: oma; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: dropBox.sel.pick(modelData.token) }
                    }
                }
            }
        }
    }
}
