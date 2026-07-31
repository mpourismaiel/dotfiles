pragma ComponentBehavior: Bound
// Memos.qml — permanent voice-memo state over voicebridge.py (~/Documents/memos).
// `entries` is the parsed list (newest first); refresh() reloads it, copy/remove/
// repolish act on a memo by id (its filename) then refresh.
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    required property var settings
    property var entries: []          // [{ id, created, type, polished, text }]

    // the transcription venv python (faster-whisper/anthropic live there); list &
    // delete are stdlib-only but run through it too for one consistent path.
    readonly property string py: Quickshell.env("HOME") + "/.local/share/pill-transcribe/venv/bin/python"

    function refresh() { if (!listProc.running) listProc.running = true; }
    function copyText(s) {                    // copy arbitrary text (polished or raw)
        if (!s || s.length === 0) return;
        copyProc.command = ["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", s];
        copyProc.running = true;
    }
    function copy(id) {
        const e = (root.entries || []).find(x => x.id === id);
        if (e) root.copyText(e.text);
    }
    function remove(id) { act(["delete", String(id)]); }
    function repolish(id) {
        act(["repolish", String(id),
             root.settings ? root.settings.claudeModel : "claude-opus-4-8",
             root.settings ? root.settings.localModel : "qwen2.5:3b"]);
    }
    function act(args) {
        actProc.command = [root.py, Quickshell.shellPath("voicebridge.py")].concat(args);
        actProc.running = true;
    }

    property Process listProc: Process {
        command: [root.py, Quickshell.shellPath("voicebridge.py"), "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.entries = JSON.parse(this.text) || []; }
                catch (e) { root.entries = []; }
            }
        }
    }
    property Process copyProc: Process { }
    // delete/repolish are user-paced; refresh after so the list reflects the change
    property Process actProc: Process { onExited: root.refresh() }
}
