pragma ComponentBehavior: Bound
// Clipboard.qml — clipboard-history state over clipbridge.py (cliphist backend).
// Instantiated once in init.qml as `Clipboard { id: clipboard }` and shared with
// the menu. `entries` is the parsed history (newest first); refresh() reloads it,
// copy/remove/wipe act on an entry (by id) then refresh.
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    // [{ id, kind:"image", w, h, path } | { id, kind:"text", text, images }]
    property var entries: []

    function refresh() { if (!listProc.running) listProc.running = true; }
    function copy(id)  { act(["copy", String(id)]); }
    function remove(id){ act(["delete", String(id)]); }
    function wipe()    { act(["wipe"]); }
    function act(args) {
        actProc.command = ["python", Quickshell.shellPath("clipbridge.py")].concat(args);
        actProc.running = true;
    }

    property Process listProc: Process {
        command: ["python", Quickshell.shellPath("clipbridge.py"), "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.entries = JSON.parse(this.text) || []; }
                catch (e) { root.entries = []; }
            }
        }
    }
    // one shared process for copy/delete/wipe (all user-paced); refresh after so
    // the list reflects the change (delete/wipe) or the re-store (copy).
    property Process actProc: Process { onExited: root.refresh() }
}
