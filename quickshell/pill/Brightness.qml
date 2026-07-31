pragma ComponentBehavior: Bound
// Brightness.qml — per-display screen brightness over KDE's org.kde.ScreenBrightness
// DBus service (the same backend Plasma's brightness slider/keys use: it drives the
// internal panel's backlight and external monitors over DDC/CI). Owned once by
// init.qml and shared with the battery menu (per-display sliders) and the brightness
// shortcut (step the active monitor). Displays are enumerated on demand (menu open);
// writes are optimistic + throttled so a slider drag doesn't spawn a qdbus process
// per pixel or thrash a slow DDC bus.
import QtQuick
import Quickshell.Io

Item {
    id: root
    readonly property string svc: "org.kde.ScreenBrightness"
    // one stable QtObject per display: mutating its `value`/`raw` in place (rather
    // than replacing the `displays` array) keeps the battery menu's Repeater from
    // rebuilding the slider delegate mid-drag — which would drop the mouse grab and
    // break click-and-drag (the array is only reassigned on refresh, never on a
    // slider move). Same idea as the volume menu writing a live Pipewire node.
    component Display: QtObject {
        property string path
        property string name
        property string label
        property bool   internal
        property int    max: 1
        property int    raw
        property real   value       // 0..1
    }
    property var displays: []
    readonly property bool available: displays.length > 0
    Component { id: displayComp; Display {} }

    // ---- enumerate displays + read label/brightness/max/internal for each ----
    // qdbus is the terse way to read the per-display properties (gdbus needs a
    // verbose Properties.Get per field); one sh loop emits a tab-separated line
    // per display which the collector parses below.
    Process {
        id: enumProc
        command: ["sh", "-c",
            'svc=org.kde.ScreenBrightness; base=/org/kde/ScreenBrightness; ' +
            'for d in $(qdbus $svc $base org.kde.ScreenBrightness.DisplaysDBusNames); do ' +
              'b=$(qdbus $svc $base/$d org.kde.ScreenBrightness.Display.Brightness); ' +
              'm=$(qdbus $svc $base/$d org.kde.ScreenBrightness.Display.MaxBrightness); ' +
              'i=$(qdbus $svc $base/$d org.kde.ScreenBrightness.Display.IsInternal); ' +
              'l=$(qdbus $svc $base/$d org.kde.ScreenBrightness.Display.Label); ' +
              'printf "%s\\t%s\\t%s\\t%s\\t%s\\n" "$d" "$b" "$m" "$i" "$l"; ' +
            'done']
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                const lines = this.text.split("\n");
                for (let k = 0; k < lines.length; k++) {
                    const f = lines[k].split("\t");
                    if (f.length < 5) continue;
                    const max = parseInt(f[2]) || 1;
                    const raw = parseInt(f[1]) || 0;
                    out.push(displayComp.createObject(root, {
                        path: "/org/kde/ScreenBrightness/" + f[0],
                        name: f[0],
                        raw: raw,
                        max: max,
                        internal: f[3].trim() === "true",
                        label: f[4],
                        value: raw / max
                    }));
                }
                const old = root.displays;
                root.displays = out;
                for (let j = 0; j < old.length; j++)
                    if (old[j]) old[j].destroy();   // free the previous generation
            }
        }
    }
    function refresh() { enumProc.running = true; }
    Component.onCompleted: refresh()

    // ---- throttled optimistic writes (slider drag) ----
    // The UI updates instantly (optimistic `displays`); the DBus write is coalesced
    // to one every ~80 ms with a guaranteed trailing flush, so dragging is smooth
    // and a slow DDC monitor isn't hammered.
    Process { id: writeProc }
    property var _pending: ({})     // display path -> raw brightness to write
    property bool _cooling: false
    property bool _dirty: false
    Timer {
        id: coolTimer
        interval: 80; repeat: false
        onTriggered: {
            if (root._dirty) { root._dirty = false; root._flush(); coolTimer.restart(); }
            else root._cooling = false;
        }
    }
    function _flush() {
        const cmds = [];
        for (const p in root._pending)
            cmds.push("qdbus " + root.svc + " " + p +
                      " org.kde.ScreenBrightness.Display.SetBrightness " + root._pending[p] + " 1");
        root._pending = ({});
        if (!cmds.length) return;
        writeProc.command = ["sh", "-c", cmds.join("; ")];
        writeProc.startDetached();
    }
    // set a display (the Display object) to `ratio` in [0,1]: move the UI now (mutate
    // the object in place, so the array — and the slider delegate — is untouched),
    // queue the DBus write behind the throttle.
    function setRatio(disp, ratio) {
        if (!disp) return;
        ratio = Math.max(0, Math.min(1, ratio));
        disp.raw = Math.round(ratio * disp.max);
        disp.value = ratio;
        root._pending[disp.path] = disp.raw;
        if (root._cooling) { root._dirty = true; return; }
        root._flush();
        root._cooling = true;
        coolTimer.restart();
    }

    // ---- brightness shortcut: step the display on the active monitor ----
    Process { id: stepProc }
    Timer { id: stepRefresh; interval: 150; repeat: false; onTriggered: root.refresh() }
    // map a KWin output name (e.g. "eDP-1", "HDMI-A-1") to a display: internal
    // connectors (eDP/LVDS/DSI) -> the IsInternal display, otherwise the first
    // external one. An empty name (no focused window) falls back to internal.
    function displayForScreen(name) {
        if (!root.displays.length) return null;
        const internal = (name === "" || /^(eDP|LVDS|DSI)/i.test(name));
        for (let i = 0; i < root.displays.length; i++)
            if (root.displays[i].internal === internal) return root.displays[i];
        return root.displays[0];
    }
    // step the active monitor's brightness by ~5%. Reads the live value in-shell
    // (so it never drifts from KDE's OSD / another client) then clamps + writes.
    function stepActive(screen, sign) {
        const d = root.displayForScreen(screen);
        if (!d) return;
        const delta = Math.round(d.max * 0.05) * (sign < 0 ? -1 : 1);
        stepProc.command = ["sh", "-c",
            'p=' + d.path + '; svc=' + root.svc + '; ' +
            'c=$(qdbus $svc $p org.kde.ScreenBrightness.Display.Brightness); ' +
            'm=$(qdbus $svc $p org.kde.ScreenBrightness.Display.MaxBrightness); ' +
            'n=$((c + (' + delta + '))); ' +
            '[ $n -lt 0 ] && n=0; [ $n -gt $m ] && n=$m; ' +
            'qdbus $svc $p org.kde.ScreenBrightness.Display.SetBrightness $n 1'];
        stepProc.startDetached();
        stepRefresh.restart();   // pull the new value back if the menu is open
    }
}
