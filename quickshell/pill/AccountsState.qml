pragma ComponentBehavior: Bound
// AccountsState.qml — calendar account manager over gcalbridge.py. Lists KDE + pill
// accounts and adds Google (loopback OAuth) / Proton (ICS URL) / removes pill ones.
// Mirrors CalendarEvents; the launcher settings page (AccountsMenu) drives it, and any
// change reloads the list and refetches CalendarEvents (`cal`).
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property var cal: null              // CalendarEvents — refetched after any change
    property var accounts: []           // [{id, provider, label, source, removable}]
    property string lastError: ""
    property bool busy: false           // an add/remove is in flight
    property string busyKind: ""        // "google" | "proton" | "remove" | ""

    function load() {
        listProc.command = ["python", Quickshell.shellPath("gcalbridge.py"), "accounts"];
        if (!listProc.running) listProc.running = true;
    }
    function addGoogle() {
        if (root.busy) return;
        root.busy = true; root.busyKind = "google"; root.lastError = "";
        opProc.command = ["python", Quickshell.shellPath("gcalbridge.py"), "add-google"];
        opProc.running = true;
    }
    function addProton(url, label) {
        if (root.busy || !url) return;
        root.busy = true; root.busyKind = "proton"; root.lastError = "";
        opProc.command = ["python", Quickshell.shellPath("gcalbridge.py"),
                          "add-proton", "" + url, "" + (label || "")];
        opProc.running = true;
    }
    function remove(id) {
        if (root.busy) return;
        root.busy = true; root.busyKind = "remove"; root.lastError = "";
        opProc.command = ["python", Quickshell.shellPath("gcalbridge.py"), "remove", "" + id];
        opProc.running = true;
    }

    property Process listProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                var env = null;
                try { env = JSON.parse(this.text); } catch (e) { env = null; }
                if (env) {
                    root.accounts = env.accounts || [];
                    if (env.errors && env.errors.length)
                        root.lastError = "" + env.errors[0];
                }
            }
        }
    }
    property Process opProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                var r = null;
                try { r = JSON.parse(this.text); } catch (e) { r = null; }
                root.lastError = (r && r.ok === false) ? ("" + (r.error || "failed")) : "";
                root.busy = false; root.busyKind = "";
                root.load();
                if (root.cal) root.cal.fetch();
            }
        }
        onRunningChanged: if (!running) { root.busy = false; root.busyKind = ""; }
    }
    Component.onCompleted: root.load()
}
