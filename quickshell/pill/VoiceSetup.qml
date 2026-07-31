pragma ComponentBehavior: Bound
// VoiceSetup.qml — Transcribe-tab setup state over voicebridge.py: cloud-key
// presence + storage (keyring), and local-model download with progress.
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    required property var settings
    readonly property string py: Quickshell.env("HOME") + "/.local/share/pill-transcribe/venv/bin/python"

    property bool anthropicKeySet: false
    property bool googleKeySet: false
    property bool openaiKeySet: false
    property bool localPresent: false        // is settings.localModel pulled?
    property bool pulling: false
    property real pullProgress: 0            // 0..1 (only meaningful while pulling)
    property string pullStatus: ""

    function keySet(provider) {
        if (provider === "google") return root.googleKeySet;
        if (provider === "openai") return root.openaiKeySet;
        return root.anthropicKeySet;
    }

    function refresh() {
        statusProc.command = [root.py, Quickshell.shellPath("voicebridge.py"),
                              "status", root.settings ? root.settings.localModel : ""];
        statusProc.running = true;
    }
    function setKey(provider, value) {
        if (!value || value.length === 0) return;
        setkeyProc.command = [root.py, Quickshell.shellPath("voicebridge.py"),
                              "setkey", provider, value];
        setkeyProc.running = true;
    }
    function pull(model) {
        if (root.pulling) return;
        root.pulling = true; root.pullProgress = 0; root.pullStatus = "starting…";
        pullProc.command = [root.py, Quickshell.shellPath("voicebridge.py"), "pull", model];
        pullProc.running = true;
    }

    property Process statusProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text) || {};
                    root.anthropicKeySet = !!d.anthropic;
                    root.googleKeySet = !!d.google;
                    root.openaiKeySet = !!d.openai;
                    root.localPresent = !!d.local;
                } catch (e) {}
            }
        }
    }
    property Process setkeyProc: Process { onExited: root.refresh() }
    property Process pullProc: Process {
        // ollama progress arrives as one JSON object per line
        stdout: SplitParser {
            onRead: line => {
                let d = null;
                try { d = JSON.parse(line); } catch (e) { return; }
                if (d.error) root.pullStatus = d.error;
                else if (d.done) root.pullStatus = "done";
                else {
                    root.pullStatus = d.status || "";
                    if (d.total > 0) root.pullProgress = Math.max(0, Math.min(1, (d.completed || 0) / d.total));
                }
            }
        }
        onExited: { root.pulling = false; root.pullProgress = 0; root.refresh(); }
    }
}
