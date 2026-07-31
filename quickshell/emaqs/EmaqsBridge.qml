pragma ComponentBehavior: Bound
// EmaqsBridge.qml — Doom-workspace + buffer state over emaqsbridge.py (Emacs daemon
// via emacsclient). Best-effort: empty if Emacs is unreachable.
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property var names: []                 // ["awesome", "elvou-app", …]
    property string current: ""            // current workspace name
    readonly property int currentIdx: names.indexOf(current)
    property var bufferGroups: []          // [{ group, items:[name,…] }, …]

    function loadWorkspaces() {
        if (wsProc.running) return;
        wsProc.command = ["python", Quickshell.shellPath("emaqsbridge.py"), "workspaces"];
        wsProc.running = true;
    }
    function loadBuffers(ws) {
        root.bufferGroups = [];
        bufProc.command = ["python", Quickshell.shellPath("emaqsbridge.py"), "buffers", ws || ""];
        if (!bufProc.running) bufProc.running = true;
    }
    function switchTo(ws) {
        root.current = ws;                 // optimistic — focus highlight moves now
        act(["switch", ws]);               // switching collapses emaqs, so no re-sync
    }
    function openBuffer(name, ws) { act(["openbuf", name, ws || ""]); }
    function magit(ws) { act(["magit", ws || ""]); }
    function closeWorkspace(ws) { act(["close", ws || ""]); reloadTimer.restart(); }

    function act(args) {
        if (actProc.running) return;       // drop overlapping user actions
        actProc.command = ["python", Quickshell.shellPath("emaqsbridge.py")].concat(args);
        actProc.running = true;
    }

    property Process wsProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var o = JSON.parse(this.text) || {};
                    root.names = o.names || [];
                    root.current = o.current || "";
                } catch (e) {}
            }
        }
    }
    property Process bufProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.bufferGroups = JSON.parse(this.text) || []; }
                catch (e) { root.bufferGroups = []; }
            }
        }
    }
    property Process actProc: Process {}
    // re-sync workspaces shortly after a close so the closed one drops off the bar.
    property Timer reloadTimer: Timer {
        interval: 320
        onTriggered: root.loadWorkspaces()
    }
}
