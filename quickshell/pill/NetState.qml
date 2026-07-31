pragma ComponentBehavior: Bound
// NetState.qml — shared network state (owned in init.qml, passed to StatusIcons +
// NetworkMenu; no singletons). Wi-Fi comes from Quickshell.Networking; wired (LAN)
// and VPN are NOT in that binding, so they're polled via `nmcli`. Exposes the
// aggregate the dashboard glyph needs + drives LAN/VPN up/down (busyConn tracks the
// one in-flight connection so its row can show a connecting stripe). nmcli up/down
// blocks until the operation settles, so the toggle process exiting is our "done".
import QtQuick
import Quickshell.Io
import Quickshell.Networking

QtObject {
    id: root

    // ---- Wi-Fi (native) ----
    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property var wifiDev: {
        const ds = Networking.devices ? Networking.devices.values : [];
        for (let i = 0; i < ds.length; i++)
            if (ds[i].type === DeviceType.Wifi) return ds[i];
        return null;
    }
    // scanned networks, active-first then by signal (shared with the menu list)
    readonly property var nets: {
        if (!root.wifiDev || !root.wifiDev.networks) return [];
        const a = root.wifiDev.networks.values.slice();
        a.sort((x, y) => (y.connected - x.connected) || (y.signalStrength - x.signalStrength));
        return a;
    }
    readonly property var activeWifi: {
        const a = root.nets;
        for (let i = 0; i < a.length; i++) if (a[i].connected) return a[i];
        return null;
    }
    readonly property bool wifiActive: root.activeWifi !== null
    readonly property real wifiSignal: root.activeWifi ? root.activeWifi.signalStrength : 0

    // ---- wired (LAN) + VPN via nmcli (neither is in the native binding) ----
    property var lans: []
    property var vpns: []
    readonly property bool lanActive: root.lans.some(l => l.active)
    readonly property bool vpnActive: root.vpns.some(v => v.active)

    // the single LAN/VPN connection with an nmcli up/down in flight (its row shows a
    // connecting stripe); cleared when the toggle process exits.
    property string busyConn: ""

    function refresh() { if (!nmcliList.running) nmcliList.running = true; }
    function setConn(name, up) {
        root.busyConn = name;
        nmcliToggle.command = ["nmcli", "connection", up ? "up" : "down", "id", name];
        nmcliToggle.running = true;
    }

    property Process nmcliList: Process {
        command: ["nmcli", "-t", "-f", "NAME,TYPE,STATE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const vpn = [], lan = [];
                for (const line of this.text.split("\n")) {
                    if (!line) continue;
                    // `-t` is colon-separated; TYPE/STATE never contain ':', so the
                    // name is everything before the last two fields (handles ':' in names)
                    const p = line.split(":");
                    if (p.length < 3) continue;
                    const state = p[p.length - 1], type = p[p.length - 2];
                    const name = p.slice(0, p.length - 2).join(":");
                    if (type.indexOf("vpn") !== -1 || type.indexOf("wireguard") !== -1)
                        vpn.push({ name: name, active: state === "activated" });
                    else if (type.indexOf("ethernet") !== -1)
                        lan.push({ name: name, active: state === "activated" });
                }
                root.vpns = vpn;
                root.lans = lan;
            }
        }
    }
    property Process nmcliToggle: Process {
        onExited: { root.busyConn = ""; root.refresh(); }
    }
    property Timer poll: Timer {
        interval: 4000; running: true; repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()
}
