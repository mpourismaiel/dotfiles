pragma ComponentBehavior: Bound
// CaptureState.qml — the capture-tool controller (owned once, like NetState /
// Brightness in the pill; no singletons). Holds the mode machine, the selected
// region, the active annotation tool + its style, and the swappable grab seam.
//
// THE FILE SEAM (see ../capture/PLAN.md): everything here works on a *file*.
// `grab()` shells out to a swappable grabber (`grabCmd`) that must write a PNG
// to `grabPath` and print nothing but that path; when it lands we set
// `frozenSource` and the overlay freezes on it. The whole annotation editor
// downstream is testable headlessly against any PNG — the harness sets
// `frozenSource` directly and never calls a live grabber.
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    // ---- mode machine -------------------------------------------------------
    // screenshot: idle -> grabbing -> selecting (draw region on frozen img) -> annotating
    // record:     idle -> recConfig (transparent overlay: region + options) -> recording
    property string mode: "idle"          // idle | grabbing | selecting | annotating | recConfig | recording
    readonly property bool active: mode !== "idle"
    readonly property bool isRecord: mode === "recConfig" || mode === "recording"

    // ---- the frozen capture -------------------------------------------------
    property url frozenSource: ""          // file:// of the grabbed PNG (or a fixture)
    property real frozenW: 0               // natural pixel size of the grab
    property real frozenH: 0

    // ---- region (in frozen-image pixels) ------------------------------------
    property rect region: Qt.rect(0, 0, 0, 0)
    readonly property bool hasRegion: region.width > 1 && region.height > 1

    // ---- annotation tool + style -------------------------------------------
    // select = move/resize/delete existing; the rest create on press-drag.
    property string tool: "select"         // select | text | arrow | rect | rectFill
    property color strokeColor: "#e6402e"
    property int   strokeWidth: 4
    property int   fontSize: 22
    // the palette offered in the toolbar (first = default)
    readonly property var palette: [
        "#e6402e", "#f5a623", "#f8e71c", "#2ecc71",
        "#3aa0ff", "#b06bff", "#ffffff", "#1b1712"
    ]

    // monotonic z for annotations: bumped each time one is selected so the selected
    // annotation rises to the top of the stack (AnnItem.onIsSelectedChanged).
    property int _annZ: 0
    function nextAnnZ() { root._annZ += 1; return root._annZ; }

    // the currently selected annotation Item (a live object — NOT an index into a
    // rebuilt array; mutated in place so drags survive, per the pill's slider rule)
    property var selected: null

    // where the grab lands, and the SWAPPABLE grabber. `%o` is replaced with
    // grabPath; the grabber just has to WRITE a PNG there (stdout is ignored — we
    // load the file on a clean exit). Default = Spectacle non-interactive current
    // monitor, which is the only grabber verified working on this KWin:
    //   - the KWin ScreenShot2 DBus iface refuses unauthorized callers ("NoAuthorized")
    //   - the freedesktop Screenshot portal returns code 2 here (backend refuses
    //     non-interactive grabs)
    //   - grim needs wlr-screencopy, which KWin doesn't implement
    // Swap this ONE string to change grabbers (e.g. `screenshotbridge.py %o` for the
    // portal on a machine where it works, or a KWin ScreenShot2 helper). Spectacle
    // needs the Wayland env, which it inherits from the running qs instance.
    // `-m` = current monitor (the one under the cursor when the hotkey fires).
    property string grabPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-capture-grab.png"
    property string grabCmd: "spectacle -b -n -m -o %o"
    property int _grabSeq: 0

    // ---- signals for the host (pill) ---------------------------------------
    signal copied()                        // finished -> image on clipboard
    signal saved(string path)              // finished -> written to disk (+copied)
    signal shotReady(string path)          // cropped PNG written -> host shows the card
    signal cancelled()
    signal grabFailed(string why)
    signal clearAnnotations()              // overlay destroys all placed annotations
    // the toolbar now lives in the PILL, which can't reach the fullscreen canvas
    // item directly, so copy/save is a signal the canvas listens for (it owns the
    // grabToImage). "" = copy only; a path = save there + copy.
    signal exportRequested(string savePath)

    property string saveDir: (Quickshell.env("HOME") || "") + "/Pictures/Screenshots"
    function requestCopy() { root.exportRequested(""); }
    function requestSave() {
        const d = new Date();
        const p = (n) => (n < 10 ? "0" : "") + n;
        root.exportRequested(root.saveDir + "/Screenshot_" + d.getFullYear() + p(d.getMonth()+1)
            + p(d.getDate()) + "_" + p(d.getHours()) + p(d.getMinutes()) + p(d.getSeconds()) + ".png");
    }

    // ---- lifecycle ----------------------------------------------------------
    // Start a screenshot: fire the grabber, then freeze + let the user draw a
    // region. The pill hotkey / IPC verb calls this.
    function beginScreenshot() {
        root.reset();
        root.mode = "grabbing";
        root.grab();
    }

    // Start a screen recording: no grab, just a transparent overlay to pick a
    // region (optional) + configure sources, then the record button fires the
    // RecordController. The pill hotkey / IPC `record` calls this.
    function beginRecord() {
        root.reset();
        // region + all record options (sources / quality / webcam) are PRESERVED
        // across recordings: the region persists here (like screenshots), and the
        // rest live in RecordController, which is owned once. Reopening record thus
        // restores the last setup. (region is opt-in via the "Select area" chip.)
        root.mode = "recConfig";
    }

    // re-draw the crop region without losing annotations (toolbar "reselect")
    function reselectRegion() { root.mode = "selecting"; }

    // Feed a pre-grabbed image straight in (used by the headless harness and by
    // any alternate grabber that already has a file). Skips the live grab.
    function freezeOn(fileUrl, w, h) {
        root.frozenSource = fileUrl;
        root.frozenW = w;
        root.frozenH = h;
        root.mode = "selecting";
    }

    // NOTE: region is intentionally PRESERVED across screenshots (so the next grab
    // reuses the same crop for a quick same-area shot). Annotations are cleared.
    function reset() {
        root.selected = null;
        root.tool = "select";
        root.frozenSource = "";
        root.mode = "idle";
        root.clearAnnotations();
    }

    function cancel() {
        root.reset();
        root.cancelled();
    }

    // region committed by the rubber-band -> move to annotating
    function commitRegion(r) {
        root.region = r;
        if (root.hasRegion) root.mode = "annotating";
    }

    function pickColor(c) {
        root.strokeColor = c;
        if (root.selected && root.selected.setColor) root.selected.setColor(c);
    }
    function pickWidth(w) {
        root.strokeWidth = w;
        if (root.selected && root.selected.setWidth) root.selected.setWidth(w);
    }
    function deleteSelected() {
        if (root.selected) { root.selected.destroy(); root.selected = null; }
    }

    // ---- the swappable grabber ---------------------------------------------
    function grab() {
        root._grabSeq += 1;
        grabber.command = ["sh", "-c",
            root.grabCmd.replace("%o", "'" + root.grabPath + "'")];
        grabber.running = true;
    }
    property Process grabber: Process {
        stderr: StdioCollector {
            onStreamFinished: if (this.text.trim()) console.warn("capture grab:", this.text.trim())
        }
        // load the file on a clean exit (grabber-agnostic — spectacle writes a file
        // and prints nothing). The `#seq` fragment forces the Image to reload even
        // though grabPath is constant; QUrl drops the fragment when opening the file.
        onExited: (code) => {
            if (code === 0) {
                root.frozenW = 0; root.frozenH = 0;
                root.frozenSource = "";
                root.frozenSource = "file://" + root.grabPath + "#" + root._grabSeq;
                // always enter region-select. A persisted region (quick same-area
                // shot) is shown as the starting crop: a plain CLICK reuses it (→
                // annotating), a click-DRAG replaces it with a fresh one. So the crop
                // is never "stuck" — you can always redraw it.
                root.mode = "selecting";
            } else if (root.mode === "grabbing") {
                root.grabFailed("grabber exit " + code);
                root.reset();
            }
        }
    }
}
