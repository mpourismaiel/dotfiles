pragma ComponentBehavior: Bound
// EmaqsBridge.qml — Doom-workspace + buffer state over emaqsbridge.py (Emacs daemon
// via emacsclient). Best-effort: empty if Emacs is unreachable.
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property var names: []                 // raw perspective names — used for actions
    property var labels: []                 // display labels, parallel to names
    property string current: ""            // current workspace name
    readonly property int currentIdx: names.indexOf(current)
    property var bufferGroups: []          // [{ group, items:[name,…] }, …]

    // human label for a raw perspective NAME ("main" -> "1 awesome"); the bar
    // switches by name but shows this, matching the dashboard / super-menu.
    function labelFor(name) {
        var i = names.indexOf(name);
        return (i >= 0 && i < labels.length && labels[i]) ? labels[i] : name;
    }

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

    // change an agent-shell BUFFER's model or session mode from the workspace menu.
    // KIND is "model" or "mode" (also the session key it updates). Optimistically
    // reflect the pick in bufferGroups, then dispatch to Emacs on its own process so
    // it never collides with a navigation action in flight.
    function setAgentSession(buffer, kind, value) {
        updateSession(buffer, kind, value);
        sessProc.command = ["python", Quickshell.shellPath("emaqsbridge.py"),
                            "agent-session", buffer, kind, value];
        if (!sessProc.running) sessProc.running = true;
    }
    function updateSession(buffer, kind, value) {
        var groups = [];
        for (var i = 0; i < bufferGroups.length; i++) {
            var g = bufferGroups[i];
            if (g.sessions && g.sessions[buffer]) {
                var ns = {};
                for (var k in g.sessions) ns[k] = g.sessions[k];
                var s = {};
                for (var sk in ns[buffer]) s[sk] = ns[buffer][sk];
                s[kind] = value;
                ns[buffer] = s;
                var ng = {};
                for (var gk in g) ng[gk] = g[gk];
                ng.sessions = ns;
                groups.push(ng);
            } else groups.push(g);
        }
        bufferGroups = groups;
    }

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
                    root.labels = o.labels || [];
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
    property Process sessProc: Process {}
    // re-sync workspaces shortly after a close so the closed one drops off the bar.
    property Timer reloadTimer: Timer {
        interval: 320
        onTriggered: root.loadWorkspaces()
    }
}
