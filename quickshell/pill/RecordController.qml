pragma ComponentBehavior: Bound
// RecordController.qml — screen-recording backend (owned once by shell.qml; the
// record analogue of CaptureState's grab seam). Drives gpu-screen-recorder:
// captures the screen via the KWin ScreenCast PORTAL (so screen choice + its
// persisted restore token are the portal's job), optionally crops to the selected
// region, mixes mic + speaker, and hardware-encodes. Stops on SIGINT (gpsr
// finalizes the file cleanly), then copies the file URI so it's pasteable.
//
// ENCODER IS NEVER HARDCODED (the user swaps hardware): default -encoder gpu with
// -fallback-cpu-encoding yes lets gpsr auto-pick/fallback; codec + quality are
// user-selectable in the record panel.
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: rc
    required property var state          // the shared CaptureState (for the region + mode)

    // ---- options (bound to the record panel) --------------------------------
    property bool   micOn: false
    property string micDev: "default_input"
    property bool   spkOn: false
    property string spkDev: "default_output"
    property bool   useRegion: false     // record a sub-region vs the whole portal output
    property int    fps: 60
    property string codec: "h264"        // h264 | hevc | av1  (container/codec, not the encoder tier)
    property string quality: "very_high" // medium | high | very_high | ultra
    property bool   cursor: true

    // ---- webcam (an ON-SCREEN overlay, captured because the whole output is
    // recorded — gpsr does NOT composite it, so nothing here goes on the gpsr
    // command line; WebcamOverlay just renders it into the frame) --------------
    property bool   webcamOn: false
    property string webcamDev: ""        // camera id ("" = first available)
    property real   webcamX: 40
    property real   webcamY: 40
    property real   webcamW: 260
    property real   webcamH: 195
    // roundness is a MODE ("10" | "20" | "full" | "custom"); `webcamRound` is only the
    // custom px value. `webcamRoundEff` is what the overlay actually applies — "full"
    // tracks the size so it stays circular as W/H change.
    property string webcamRoundMode: "20"
    property real   webcamRound: 18            // custom px (used when mode === "custom")
    readonly property real webcamRoundEff: {
        if (webcamRoundMode === "full") return Math.round(Math.min(webcamW, webcamH) / 2);
        if (webcamRoundMode === "custom") return webcamRound;
        return parseInt(webcamRoundMode);      // "10" / "20"
    }
    property bool   webcamShadow: true
    property real   webcamOpacity: 1.0

    // enumerated audio devices: [{ token, label }]
    property var mics: []
    property var speakers: []

    property bool   recording: false
    property int    elapsed: 0           // seconds
    property string lastFile: ""

    readonly property string tokenFile: Quickshell.stateDir + "/capture-portal-token"
    property string outDir: (Quickshell.env("HOME") || "") + "/Videos"

    signal started()
    signal finished(string path)
    signal failed(string why)

    // last stderr from gpsr, surfaced when a run dies instead of recording
    property string lastError: ""

    // screen size (fed by the record canvas) for the webcam collision gate
    property real screenW: 0
    property real screenH: 0
    // at least half the webcam must be on-screen before recording
    function webcamVisibleOk() {
        if (!rc.webcamOn || rc.screenW < 1 || rc.screenH < 1) return true;
        const ix = Math.min(rc.webcamX + rc.webcamW, rc.screenW) - Math.max(rc.webcamX, 0);
        const iy = Math.min(rc.webcamY + rc.webcamH, rc.screenH) - Math.max(rc.webcamY, 0);
        const vis = Math.max(0, ix) * Math.max(0, iy);
        return vis >= 0.5 * rc.webcamW * rc.webcamH;
    }

    // ---- device enumeration -------------------------------------------------
    function refreshDevices() { lister.running = true; }
    property Process lister: Process {
        command: ["gpu-screen-recorder", "--list-audio-devices"]
        stdout: StdioCollector {
            onStreamFinished: {
                const mics = [], spks = [];
                for (const line of this.text.split("\n")) {
                    if (!line.trim()) continue;
                    const i = line.indexOf("|");
                    const token = i >= 0 ? line.slice(0, i) : line;
                    const label = i >= 0 ? line.slice(i + 1) : line;
                    // monitors / default_output = speakers to capture; the rest = mics
                    if (token === "default_output" || token.indexOf(".monitor") !== -1)
                        spks.push({ token: token, label: label });
                    else
                        mics.push({ token: token, label: label });
                }
                rc.mics = mics; rc.speakers = spks;
            }
        }
    }

    // ---- build the gpsr command --------------------------------------------
    function outPath() {
        const d = new Date();
        const p = (n) => (n < 10 ? "0" : "") + n;
        return rc.outDir + "/Recording_" + d.getFullYear() + p(d.getMonth()+1) + p(d.getDate())
             + "_" + p(d.getHours()) + p(d.getMinutes()) + p(d.getSeconds()) + ".mp4";
    }
    function buildArgs(out) {
        const r = rc.state.region;
        const useR = rc.useRegion && r.width > 1 && r.height > 1;
        const a = ["gpu-screen-recorder"];
        if (useR) {
            // sub-region = gpsr's KMS region capture. `-w` takes the geometry
            // (WxH+X+Y) DIRECTLY — the old `-region` flag is deprecated and, more to
            // the point, only valid with `-w region`, which is why pairing it with
            // `-w portal` errored ("-region can only be used when -w region is used").
            // Region capture goes through KMS, not the portal, so the portal/restore
            // args are intentionally omitted here.
            a.push("-w", Math.round(r.width) + "x" + Math.round(r.height)
                       + "+" + Math.round(r.x) + "+" + Math.round(r.y));
        } else {
            // whole screen via the ScreenCast portal (restore token remembers the pick)
            a.push("-w", "portal",
                   "-restore-portal-session", "yes",
                   "-portal-session-token-filepath", rc.tokenFile);
        }
        a.push("-f", String(rc.fps),
               "-k", rc.codec,
               "-q", rc.quality,
               "-encoder", "gpu",
               "-fallback-cpu-encoding", "yes",
               "-cursor", rc.cursor ? "yes" : "no");
        if (rc.micOn) a.push("-a", rc.micDev);
        if (rc.spkOn) a.push("-a", rc.spkDev);
        a.push("-o", out);
        return a;
    }

    // ---- lifecycle ----------------------------------------------------------
    function start() {
        if (rc.recording) return;
        mkdir.command = ["mkdir", "-p", rc.outDir]; mkdir.running = true;
        const out = rc.outPath();
        rc.lastFile = out;
        gpsr.command = rc.buildArgs(out);
        gpsr.running = true;
        rc.recording = true;
        rc.elapsed = 0;
        rc.state.mode = "recording";
        rc.started();
    }
    function stop() {
        if (!rc.recording) return;
        gpsr.signal(2);          // SIGINT -> gpsr writes the moov atom + exits
    }

    property Timer ticker: Timer {
        interval: 1000; repeat: true; running: rc.recording
        onTriggered: rc.elapsed += 1
    }

    property Process gpsr: Process {
        stderr: StdioCollector {
            onStreamFinished: {
                rc.lastError = this.text.trim();
                if (rc.lastError) console.warn("gpsr:", rc.lastError);
            }
        }
        // A clean stop is SIGINT -> gpsr finalizes and exits 0. A NON-zero exit means
        // gpsr never really recorded (portal denied, no encoder, bad restore token,
        // …) and would otherwise masquerade as an instant "saved" — so treat that as
        // a failure: surface the reason, don't copy/notify a phantom file.
        onExited: (code) => {
            rc.recording = false;
            if (code === 0 && rc.lastFile) {
                // copy the file URI so it pastes into chat apps as an attachment
                clip.command = ["sh", "-c",
                    "printf 'file://%s\\n' '" + rc.lastFile + "' | wl-copy --type text/uri-list"];
                clip.running = true;
                rc.finished(rc.lastFile);
            } else if (code !== 0) {
                rc.failed(rc.lastError || ("gpu-screen-recorder exited " + code));
            }
            rc.state.reset();
        }
    }

    property Process clip: Process { }
    property Process mkdir: Process { }

    Component.onCompleted: rc.refreshDevices()
}
