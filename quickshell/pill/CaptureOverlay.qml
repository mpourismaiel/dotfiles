pragma ComponentBehavior: Bound
// CaptureOverlay.qml — the fullscreen screenshot surface (a plain Item; the host
// wraps it in a layer-shell window / the harness in a FloatingWindow). Shows the
// frozen grab, a Flameshot-style rubber-band region select, a dim mask outside the
// region, then the annotation editor.
//
// Annotations are drawn over the WHOLE frozen image (they are NOT clipped to the
// region — the region only CROPS the final composite). So the exportable content
// is `shot` (frozen image + annotations, no dim/border); export grabs it and crops
// to the region with ImageMagick, then copies / saves. Everything runs against any
// PNG in `state.frozenSource`, so the harness drives it with a fixture.
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: overlay
    required property var state
    required property var theme

    property string saveDir: (Quickshell.env("HOME") || "") + "/Pictures/Screenshots"
    property string outPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-capture-out.png"
    property string fullPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-capture-full.png"

    focus: true
    Keys.onEscapePressed: overlay.state.cancel()
    Keys.onPressed: (e) => {
        if (e.modifiers & Qt.ControlModifier) {
            if (e.key === Qt.Key_C) { overlay.state.requestCopy(); e.accepted = true; }
            else if (e.key === Qt.Key_S) { overlay.state.requestSave(); e.accepted = true; }
        } else if ((e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace)
                   && overlay.state.selected && overlay.state.tool === "select") {
            overlay.state.deleteSelected(); e.accepted = true;
        }
    }
    // the pill toolbar / Ctrl+C/S ask the state to export; the canvas (which owns
    // grabToImage) does the work here.
    Connections {
        target: overlay.state
        function onExportRequested(savePath) { overlay._export(savePath); }
    }

    readonly property rect r: overlay.state.region
    readonly property bool showRegion: overlay.state.hasRegion

    Rectangle { anchors.fill: parent; color: "black" }   // letterbox under the grab

    // ---- exportable composite: frozen grab + annotations (NOT clipped) ------
    Item {
        id: shot
        anchors.fill: parent

        Image {
            id: frozen
            anchors.fill: parent
            source: overlay.state.frozenSource
            fillMode: Image.Stretch
            asynchronous: false
            cache: false
            onStatusChanged: if (status === Image.Ready && overlay.state.frozenW === 0) {
                overlay.state.frozenW = sourceSize.width;
                overlay.state.frozenH = sourceSize.height;
            }
        }

        // annotations live in FULL-IMAGE coords, drawable anywhere
        Item {
            id: annLayer
            anchors.fill: parent

            MouseArea {                       // empty-click deselect (select tool only)
                anchors.fill: parent
                enabled: overlay.state.tool === "select" && overlay.state.mode === "annotating"
                onPressed: (e) => { overlay.state.selected = null; e.accepted = false; }
            }
            MouseArea {                       // create a new annotation (creation tools)
                id: creator
                anchors.fill: parent
                enabled: overlay.state.tool !== "select" && overlay.state.mode === "annotating"
                cursorShape: Qt.CrossCursor
                property var draft: null
                onPressed: (e) => {
                    const t = overlay.state.tool;
                    creator.draft = annProto.createObject(annLayer, {
                        state: overlay.state, theme: overlay.theme,
                        annType: t, annColor: overlay.state.strokeColor,
                        annWidth: overlay.state.strokeWidth, fontPx: overlay.state.fontSize,
                        x1: e.x, y1: e.y,
                        x2: t === "text" ? e.x + 80 : e.x,
                        y2: t === "text" ? e.y + overlay.state.fontSize + 8 : e.y,
                        textValue: ""
                    });
                    overlay.state.selected = creator.draft;
                }
                onPositionChanged: (e) => {
                    if (!creator.draft || overlay.state.tool === "text") return;
                    creator.draft.x2 = e.x; creator.draft.y2 = e.y;
                }
                onReleased: () => {
                    const d = creator.draft; creator.draft = null;
                    if (!d) return;
                    if (overlay.state.tool === "text") { d.beginEditIfText(); overlay.state.tool = "select"; return; }
                    if (d.bw < 4 && d.bh < 4) { d.destroy(); overlay.state.selected = null; }
                }
            }
        }
    }

    // ---- dim outside the region + border (VISUAL only — not exported) -------
    Item {
        anchors.fill: parent
        visible: overlay.state.frozenSource != ""
        Rectangle { color: Qt.rgba(0,0,0,0.45); x: 0; y: 0; width: parent.width
                    height: overlay.showRegion ? overlay.r.y : parent.height }
        Rectangle { color: Qt.rgba(0,0,0,0.45); visible: overlay.showRegion
                    x: 0; y: overlay.r.y + overlay.r.height; width: parent.width
                    height: parent.height - (overlay.r.y + overlay.r.height) }
        Rectangle { color: Qt.rgba(0,0,0,0.45); visible: overlay.showRegion
                    x: 0; y: overlay.r.y; width: overlay.r.x; height: overlay.r.height }
        Rectangle { color: Qt.rgba(0,0,0,0.45); visible: overlay.showRegion
                    x: overlay.r.x + overlay.r.width; y: overlay.r.y
                    width: parent.width - (overlay.r.x + overlay.r.width); height: overlay.r.height }
    }
    Rectangle {
        visible: overlay.showRegion
        x: overlay.r.x; y: overlay.r.y; width: overlay.r.width; height: overlay.r.height
        color: "transparent"; border.color: overlay.theme.accent; border.width: 1
    }

    // ---- rubber-band region select (mode: selecting) -----------------------
    property real _sx: 0
    property real _sy: 0
    MouseArea {
        id: rubber
        anchors.fill: parent
        enabled: overlay.state.mode === "selecting"
        cursorShape: Qt.CrossCursor
        onPressed: (e) => { overlay._sx = e.x; overlay._sy = e.y;
                            overlay.state.region = Qt.rect(e.x, e.y, 0, 0); }
        onPositionChanged: (e) => {
            overlay.state.region = Qt.rect(Math.min(overlay._sx, e.x), Math.min(overlay._sy, e.y),
                                           Math.abs(e.x - overlay._sx), Math.abs(e.y - overlay._sy));
        }
        onReleased: overlay.state.commitRegion(overlay.state.region)
    }

    // ---- crop-region 8-point resize (annotating) ---------------------------
    // Border grips let you fine-tune the crop without a full re-select; the
    // interior stays free for annotating, so this is resize-only (no middle drag).
    ResizeHandles {
        theme: overlay.theme
        active: overlay.state.mode === "annotating" && overlay.showRegion
        rect_: overlay.state.region
        boundW: overlay.width; boundH: overlay.height
        minW: 20; minH: 20
        moveEnabled: false
        onChanged: (r) => overlay.state.region = r
    }

    Component { id: annProto; AnnItem { } }

    // test/programmatic helper: place an annotation directly (full-image coords).
    function addAnnotation(t, ax, ay, bx, by, c, tv) {
        return annProto.createObject(annLayer, {
            state: overlay.state, theme: overlay.theme, annType: t,
            annColor: c || overlay.state.strokeColor, annWidth: overlay.state.strokeWidth,
            fontPx: overlay.state.fontSize, x1: ax, y1: ay, x2: bx, y2: by, textValue: tv || ""
        });
    }
    // destroy every placed annotation (a new screenshot starts clean); the state
    // fires clearAnnotations() from reset()/beginScreenshot().
    function clearAnnotations() {
        const kids = annLayer.children;
        for (let i = kids.length - 1; i >= 0; i--)
            if (kids[i] && kids[i].isAnnotation) kids[i].destroy();
        overlay.state.selected = null;
    }
    Connections {
        target: overlay.state
        function onClearAnnotations() { overlay.clearAnnotations(); }
    }

    // ---- export: grab the full composite, crop to the region, copy / save ---
    // driven by state.exportRequested (from the pill toolbar / Ctrl+C/S).
    function _export(savePath) {
        if (!overlay.showRegion) return;
        overlay.state.selected = null;        // drop handles before the grab
        Qt.callLater(function() {
            shot.grabToImage(function(res) {
                if (!res) return;
                res.saveToFile(overlay.fullPath);
                const rx = Math.round(overlay.r.x), ry = Math.round(overlay.r.y);
                const rw = Math.round(overlay.r.width), rh = Math.round(overlay.r.height);
                let cmd = "magick '" + overlay.fullPath + "' -crop " + rw + "x" + rh + "+" + rx + "+" + ry
                        + " +repage '" + overlay.outPath + "' && wl-copy --type image/png < '" + overlay.outPath + "'";
                if (savePath)
                    cmd += " && mkdir -p '" + overlay.saveDir + "' && cp '" + overlay.outPath + "' '" + savePath + "'";
                exporter.command = ["sh", "-c", cmd];
                exporter.running = true;
                if (savePath) overlay.state.saved(savePath); else overlay.state.copied();
            });
        });
    }
    Process { id: exporter }
}
