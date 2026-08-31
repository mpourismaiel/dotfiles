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
    // With one overlay per monitor but a single frozen grab of ONLY the grabbed
    // monitor, exactly one overlay is "primary" (the grabbed screen — set by the
    // host). Non-primary overlays must never apply the full-screen region default nor
    // export: they'd clobber the shared region with their own size and race the crop
    // (grabToImage of a stretched wrong-monitor copy). Defaults true for the harness,
    // which drives a single overlay against a fixture.
    property bool primary: true

    property string saveDir: (Quickshell.env("HOME") || "") + "/Pictures/Screenshots"
    property string outPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-capture-out.png"
    property string fullPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-capture-full.png"

    focus: true
    // apply the full-screen default as soon as the grab is flagged AND we're sized.
    // The fullscreen window is mapped/sized AFTER the grab lands (and after the frozen
    // image loads), and the exact "now sized" signal is unreliable across compositors,
    // so instead of guessing which event arrives last a short timer retries while the
    // flag is up and stops itself the moment it commits (clearing pendingFull). The
    // instant paths below (flag-change + image-ready) usually win the race first.
    Connections {
        target: overlay.state
        function onPendingFullChanged() { overlay._applyFullDefault(); }
    }
    Timer {
        interval: 16; repeat: true
        running: overlay.state.pendingFull && overlay.primary
        onTriggered: overlay._applyFullDefault()
    }
    Keys.onEscapePressed: overlay.state.cancel()
    Keys.onPressed: (e) => {
        if (e.modifiers & Qt.ControlModifier) {
            if (e.key === Qt.Key_C) { overlay.state.requestCopy(); e.accepted = true; }
            else if (e.key === Qt.Key_S) { overlay.state.requestSave(); e.accepted = true; }
            // Ctrl+Z undo, Ctrl+Shift+Z / Ctrl+Y redo
            else if (e.key === Qt.Key_Z && (e.modifiers & Qt.ShiftModifier)) { overlay._redo(); e.accepted = true; }
            else if (e.key === Qt.Key_Z) { overlay._undo(); e.accepted = true; }
            else if (e.key === Qt.Key_Y) { overlay._redo(); e.accepted = true; }
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
    // true only during the grabToImage pass: hides the crop grips (which live inside
    // the exported `shot`) so they don't bake into the saved/copied PNG.
    property bool exporting: false

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
            onStatusChanged: if (status === Image.Ready) {
                if (overlay.state.frozenW === 0) {
                    overlay.state.frozenW = sourceSize.width;
                    overlay.state.frozenH = sourceSize.height;
                }
                overlay._applyFullDefault();
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
                    const t = overlay.state.tool, st = overlay.state;
                    if (t === "freehand") {
                        creator.draft = overlay._create({
                            state: st, theme: overlay.theme, annType: "freehand",
                            annColor: st.strokeColor, annWidth: st.strokeWidth,
                            x1: e.x, y1: e.y, x2: e.x, y2: e.y, points: [{ x: e.x, y: e.y }]
                        });
                        st.selected = creator.draft;
                        return;
                    }
                    // rect + rectFill both make an annType "rect"; rectFill just starts
                    // filled (a selected rect can toggle fill / recolour later).
                    const isRect = (t === "rect" || t === "rectFill");
                    creator.draft = overlay._create({
                        state: st, theme: overlay.theme,
                        annType: isRect ? "rect" : t,
                        annColor: st.strokeColor, annWidth: st.strokeWidth, fontPx: st.fontSize,
                        filled: t === "rectFill", fillColor: st.fillColor,
                        x1: e.x, y1: e.y,
                        x2: t === "text" ? e.x + 80 : e.x,
                        y2: t === "text" ? e.y + st.fontSize + 8 : e.y,
                        textValue: ""
                    });
                    st.selected = creator.draft;
                }
                onPositionChanged: (e) => {
                    if (!creator.draft || overlay.state.tool === "text") return;
                    if (overlay.state.tool === "freehand") { creator.draft.addPoint(e.x, e.y); return; }
                    creator.draft.x2 = e.x; creator.draft.y2 = e.y;
                }
                onReleased: () => {
                    const d = creator.draft; creator.draft = null;
                    if (!d) return;
                    const t = overlay.state.tool;
                    if (t === "text") { d.beginEditIfText(); overlay.state.tool = "select"; overlay._commit(); return; }
                    if (t === "freehand") {
                        if ((d.points || []).length < 2) { overlay._remove(d); overlay.state.selected = null; }
                        else overlay._commit();
                        return;
                    }
                    // a bare click (no drag) makes a zero-size shape — discard it
                    if (d.bw < 4 && d.bh < 4) { overlay._remove(d); overlay.state.selected = null; }
                    else overlay._commit();
                }
            }

            // ---- crop-region 8-point resize (annotating) --------------------
            // Border grips fine-tune the crop without a full re-select. It lives
            // INSIDE annLayer, declared before the annotations (which createObject
            // appends after it), so annotations always stack ON TOP — grabbing one
            // to drag/resize is preferred over the region grips. Resize-only (no
            // middle drag) keeps the interior free for annotating.
            ResizeHandles {
                theme: overlay.theme
                // only with the SELECT tool — a creation tool (rect/arrow/text) needs
                // the whole crop, borders included, free to draw on, so the grips get
                // out of the way (they'd otherwise eat presses near the crop edge).
                active: overlay.state.mode === "annotating" && overlay.showRegion
                        && overlay.state.tool === "select" && !overlay.exporting
                rect_: overlay.state.region
                boundW: overlay.width; boundH: overlay.height
                minW: 20; minH: 20
                moveEnabled: false
                onChanged: (r) => overlay.state.region = r
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

    // ---- rubber-band region select ----------------------------------------
    // Active in BOTH selecting and annotating so the crop is never one-shot:
    //   • selecting  — a click-DRAG draws a fresh crop, a plain CLICK reuses the
    //                  region already shown (quick same-area shot).
    //   • annotating — a drag that STARTS on the dimmed area OUTSIDE the crop draws a
    //                  fresh crop (redraw as often as you like); presses inside the
    //                  crop (plus a grip margin) fall through to annotating / the
    //                  resize grips. A plain click on the dim just deselects.
    // The persisted region is never wiped on press, so a click can still reuse it.
    property real _sx: 0
    property real _sy: 0
    property bool _dragging: false
    MouseArea {
        id: rubber
        anchors.fill: parent
        enabled: overlay.state.mode === "selecting" || overlay.state.mode === "annotating"
        // hoverEnabled stays false so this never claims the cursor on hover (annotations
        // keep their own); the crosshair only shows while actually dragging a crop.
        cursorShape: Qt.CrossCursor
        onPressed: (e) => {
            overlay._dragging = false;
            if (overlay.state.mode === "annotating") {
                // creation tools (rect/arrow/text) always draw an annotation — fall
                // through to the layer below.
                if (overlay.state.tool !== "select") { e.accepted = false; return; }
                // SELECT tool: pass through when the press lands on an existing
                // annotation (move / resize / select it) or on a crop-region grip
                // (fine-tune the crop); anywhere else on empty canvas a drag draws a
                // FRESH region — so a smaller crop is one drag away even from the
                // full-screen default (which leaves no dim to grab).
                if (overlay._annAt(e.x, e.y) || overlay._nearCropBorder(e.x, e.y)) {
                    e.accepted = false; return;
                }
            }
            overlay._sx = e.x; overlay._sy = e.y;
        }
        onPositionChanged: (e) => {
            if (!overlay._dragging && Math.abs(e.x - overlay._sx) + Math.abs(e.y - overlay._sy) < 6)
                return;                       // ignore sub-pixel jitter so a click stays a click
            overlay._dragging = true;
            overlay.state.region = Qt.rect(Math.min(overlay._sx, e.x), Math.min(overlay._sy, e.y),
                                           Math.abs(e.x - overlay._sx), Math.abs(e.y - overlay._sy));
        }
        onReleased: () => {
            if (overlay._dragging)
                overlay.state.commitRegion(overlay.state.region);            // new crop
            else if (overlay.state.mode === "selecting" && overlay.showRegion)
                overlay.state.commitRegion(overlay.state.region);            // click reuses
            else if (overlay.state.mode === "annotating")
                overlay.state.selected = null;                               // click on dim deselects
            overlay._dragging = false;
        }
    }

    Component { id: annProto; AnnItem { } }

    // ---- annotation bookkeeping + undo/redo ---------------------------------
    // Annotations are stable QML objects (see AnnItem); we hold explicit refs in
    // `_anns` rather than scanning annLayer.children so snapshot/hit-test never see
    // an object mid-destroy. Undo/redo is a linear history of scene snapshots (plain
    // JS, so colours/points serialise): `_history[_hi]` is the current scene; a
    // commit truncates any redo branch and pushes a fresh snapshot; undo/redo just
    // restore a neighbouring snapshot by rebuilding the objects.
    property var _anns: []
    property var _history: [ [] ]
    property int _hi: 0

    function _create(props) {
        const o = annProto.createObject(annLayer, props);
        if (o) overlay._anns.push(o);
        return o;
    }
    function _remove(o) {
        const i = overlay._anns.indexOf(o);
        if (i >= 0) overlay._anns.splice(i, 1);
        if (o) o.destroy();
    }
    function _clearAnns() {
        for (let i = overlay._anns.length - 1; i >= 0; i--)
            if (overlay._anns[i]) overlay._anns[i].destroy();
        overlay._anns = [];
        overlay.state.selected = null;
    }
    function _snapshot() {
        const out = [];
        for (let i = 0; i < overlay._anns.length; i++) {
            const k = overlay._anns[i];
            if (!k) continue;
            out.push({
                annType: k.annType, annColor: "" + k.annColor, annWidth: k.annWidth,
                fontPx: k.fontPx, filled: k.filled, fillColor: "" + k.fillColor,
                textValue: k.textValue, x1: k.x1, y1: k.y1, x2: k.x2, y2: k.y2,
                points: (k.points || []).map(p => ({ x: p.x, y: p.y })), z: k.z
            });
        }
        return out;
    }
    function _restore(list) {
        overlay._clearAnns();
        let maxZ = 0;
        for (let i = 0; i < list.length; i++) {
            const d = list[i];
            const o = overlay._create({
                state: overlay.state, theme: overlay.theme,
                annType: d.annType, annColor: d.annColor, annWidth: d.annWidth,
                fontPx: d.fontPx, filled: d.filled, fillColor: d.fillColor,
                textValue: d.textValue, x1: d.x1, y1: d.y1, x2: d.x2, y2: d.y2,
                points: d.points ? d.points.slice() : []
            });
            if (o && d.z !== undefined) { o.z = d.z; if (d.z > maxZ) maxZ = d.z; }
        }
        overlay.state.selected = null;
        if (overlay.state._annZ < maxZ) overlay.state._annZ = maxZ;
    }
    function _commit() {
        overlay._history = overlay._history.slice(0, overlay._hi + 1);
        overlay._history.push(overlay._snapshot());
        overlay._hi = overlay._history.length - 1;
        overlay._syncHistoryFlags();
    }
    function _undo() {
        if (overlay._hi <= 0) return;
        overlay._hi -= 1;
        overlay._restore(overlay._history[overlay._hi]);
        overlay._syncHistoryFlags();
    }
    function _redo() {
        if (overlay._hi >= overlay._history.length - 1) return;
        overlay._hi += 1;
        overlay._restore(overlay._history[overlay._hi]);
        overlay._syncHistoryFlags();
    }
    function _syncHistoryFlags() {
        overlay.state.canUndo = overlay._hi > 0;
        overlay.state.canRedo = overlay._hi < overlay._history.length - 1;
    }

    // test/programmatic helper: place an annotation directly (full-image coords).
    function addAnnotation(t, ax, ay, bx, by, c, tv) {
        return overlay._create({
            state: overlay.state, theme: overlay.theme, annType: t,
            annColor: c || overlay.state.strokeColor, annWidth: overlay.state.strokeWidth,
            fontPx: overlay.state.fontSize, x1: ax, y1: ay, x2: bx, y2: by, textValue: tv || ""
        });
    }
    // destroy every placed annotation + reset history (a new screenshot starts
    // clean); the state fires clearAnnotations() from reset()/beginScreenshot().
    function clearAnnotations() {
        overlay._clearAnns();
        overlay._history = [ [] ];
        overlay._hi = 0;
        overlay._syncHistoryFlags();
    }
    Connections {
        target: overlay.state
        function onClearAnnotations() { overlay.clearAnnotations(); }
        function onCommitHistory() { overlay._commit(); }
        function onUndoRequested() { overlay._undo(); }
        function onRedoRequested() { overlay._redo(); }
        function onDeleteSelectedRequested() {
            const s = overlay.state.selected;
            if (!s) return;
            overlay._remove(s);
            overlay.state.selected = null;
            overlay._commit();
        }
    }

    // a fresh grab asks for the full-screen default: once we know our size, pre-select
    // the whole screen and commit → annotating (toolbar up instantly). Region lives in
    // overlay coords (export grabs `shot` at this size), so full = the overlay box.
    function _applyFullDefault() {
        if (!overlay.primary) return;
        if (!overlay.state.pendingFull) return;
        if (overlay.width < 2 || overlay.height < 2) return;
        overlay.state.pendingFull = false;
        overlay.state.commitRegion(Qt.rect(0, 0, overlay.width, overlay.height));
    }

    // topmost annotation whose bounding box covers (px,py) — annLayer shares the
    // overlay's origin, so its children's x/y are directly comparable. Used to let a
    // press fall through to an annotation instead of starting a region draw.
    function _annAt(px, py) {
        for (let i = overlay._anns.length - 1; i >= 0; i--) {
            const k = overlay._anns[i];
            if (k && k.visible
                && px >= k.x && px <= k.x + k.width
                && py >= k.y && py <= k.y + k.height)
                return k;
        }
        return null;
    }
    // true when (px,py) sits in the grip band hugging the crop outline (within `m` of
    // an edge) — those presses go to the region ResizeHandles, not a fresh draw.
    function _nearCropBorder(px, py) {
        if (!overlay.showRegion) return false;
        const r = overlay.r, m = 16;
        const inOuter = px >= r.x - m && px <= r.x + r.width + m
                     && py >= r.y - m && py <= r.y + r.height + m;
        const inInner = px >= r.x + m && px <= r.x + r.width - m
                     && py >= r.y + m && py <= r.y + r.height - m;
        return inOuter && !inInner;
    }

    // ---- export: grab the full composite, crop to the region, copy / save ---
    // driven by state.exportRequested (from the pill toolbar / Ctrl+C/S).
    property string _shotPath: ""
    function _export(savePath) {
        if (!overlay.primary) return;         // only the grabbed monitor's overlay exports
        if (!overlay.showRegion) return;
        overlay.state.selected = null;        // drop handles before the grab
        overlay.exporting = true;             // hide the crop grips for the grab
        Qt.callLater(function() {
            shot.grabToImage(function(res) {
                overlay.exporting = false;    // grab rendered -> grips can come back
                if (!res) return;
                res.saveToFile(overlay.fullPath);
                const rx = Math.round(overlay.r.x), ry = Math.round(overlay.r.y);
                const rw = Math.round(overlay.r.width), rh = Math.round(overlay.r.height);
                // the crop always lands at outPath (+ copied); a save also cp's it to
                // the Screenshots dir. The in-pill "screenshot ready" card opens THIS
                // file, so prefer the persistent savePath when there is one.
                overlay._shotPath = savePath ? savePath : overlay.outPath;
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
    // when the crop/copy/save shell finishes, hand the final PNG to the host so it can
    // raise the in-pill "screenshot ready" notification (with a live thumbnail).
    Process {
        id: exporter
        onExited: (code) => { if (code === 0 && overlay._shotPath) overlay.state.shotReady(overlay._shotPath); }
    }
}
