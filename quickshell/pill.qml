pragma ComponentBehavior: Bound
// ----------------------------------------------------------------------------
// pill.qml — morphing "pill" overlay for KDE Plasma 6 / KWin / Wayland.
//
// Stages: collapsed (hh:mm) -> hovered (dashboard, two balanced rows) -> clicked
// (control panel). See qs-pill-docs.org "How the pill works" for the full notes.
//
// Run with:  qs -p quickshell/pill.qml
// ----------------------------------------------------------------------------
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

ShellRoot {
    id: root
    property var desktops: []
    property string currentDesktop: ""
    property var windows: []          // [{id, uuid, title, icon}]
    property string activeWindow: ""  // active window uuid "{...}"

    Theme { id: theme }
    // keep the default sink bound so the dashboard volume icon reflects mute live
    PwObjectTracker { objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : [] }

    // ---- KWin virtual desktops over DBus (org.kde.KWin /VirtualDesktopManager) ----
    Process {
        id: fetchDesktops
        running: true
        command: ["gdbus", "call", "--session", "--dest", "org.kde.KWin",
            "--object-path", "/VirtualDesktopManager", "--method",
            "org.freedesktop.DBus.Properties.Get",
            "org.kde.KWin.VirtualDesktopManager", "desktops"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                const re = /\(\s*(?:uint32\s+)?\d+\s*,\s*'([^']*)'\s*,\s*'([^']*)'\s*\)/g;
                let m;
                while ((m = re.exec(this.text)) !== null)
                    out.push({ id: m[1], name: m[2] });
                root.desktops = out;
            }
        }
    }
    Process {
        running: true
        command: ["gdbus", "call", "--session", "--dest", "org.kde.KWin",
            "--object-path", "/VirtualDesktopManager", "--method",
            "org.freedesktop.DBus.Properties.Get",
            "org.kde.KWin.VirtualDesktopManager", "current"]
        stdout: StdioCollector {
            onStreamFinished: { const m = this.text.match(/'([^']*)'/); if (m) root.currentDesktop = m[1]; }
        }
    }
    Process {
        running: true
        command: ["gdbus", "monitor", "--session", "--dest", "org.kde.KWin",
            "--object-path", "/VirtualDesktopManager"]
        stdout: SplitParser {
            onRead: line => {
                if (line.indexOf("currentChanged") !== -1) {
                    const m = line.match(/'([^']*)'/); if (m) root.currentDesktop = m[1];
                } else if (line.indexOf("desktopCreated") !== -1 || line.indexOf("desktopRemoved") !== -1) {
                    fetchDesktops.running = true;
                }
            }
        }
    }
    function switchDesktop(id) {
        switchProc.command = ["gdbus", "call", "--session", "--dest", "org.kde.KWin",
            "--object-path", "/VirtualDesktopManager", "--method",
            "org.freedesktop.DBus.Properties.Set",
            "org.kde.KWin.VirtualDesktopManager", "current", "<'" + id + "'>"];
        switchProc.running = true;
    }
    Process { id: switchProc }

    // ---- open windows (taskbar) + active window via winbridge.py ----
    // (KRunner windows runner for the list + a tiny KWin script for the active
    //  window — see winbridge.py. Emits one JSON line per update.)
    Process {
        running: true
        command: ["python", Quickshell.shellPath("winbridge.py")]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const d = JSON.parse(line);
                    root.windows = d.windows;
                    root.activeWindow = d.active;
                } catch (e) {}
            }
        }
    }
    function activateWindow(id) {
        runProc.command = ["gdbus", "call", "--session", "--dest", "org.kde.KWin",
            "--object-path", "/WindowsRunner", "--method", "org.kde.krunner1.Run", id, ""];
        runProc.running = true;
    }
    Process { id: runProc }
    Process { id: launchProc }
    function launch(execString) { launchProc.command = ["sh", "-c", execString]; launchProc.startDetached(); }

    // group windows by app (icon name); preserve first-seen order
    readonly property var appGroups: {
        const g = {}, order = [];
        for (const w of windows) {
            if (!g[w.icon]) { g[w.icon] = { icon: w.icon, wins: [] }; order.push(w.icon); }
            g[w.icon].wins.push(w);
        }
        return order.map(k => g[k]);
    }
    function groupActive(grp) { return grp.wins.some(w => w.uuid === root.activeWindow); }
    function cycleGroup(grp) {
        const i = grp.wins.findIndex(w => w.uuid === root.activeWindow);
        root.activateWindow(grp.wins[i >= 0 ? (i + 1) % grp.wins.length : 0].id);
    }

    // ---- launcher app list ----
    // Built once here (the long-lived root) and shared with every monitor's
    // Launcher, so it survives open/close and is computed in the background at
    // startup rather than on first open. Reactive to DesktopEntries, so it
    // auto-updates when apps are installed or removed.
    readonly property var appList: {
        const src = DesktopEntries.applications ? DesktopEntries.applications.values : [];
        const a = src.filter(e => e && !e.noDisplay);
        a.sort((x, y) => x.name.localeCompare(y.name));
        return a;
    }

    // ---- one full-screen overlay window per monitor ----
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            anchors { top: true; bottom: true; left: true; right: true }
            mask: (win.open || win.launcher || win.ctxGroup !== null) ? fullRegion : pillRegion

            property bool open: false
            property bool launcher: false // app launcher (wider open state)
            property var ctxGroup: null   // app group whose right-click menu is shown
            property bool dash: open || launcher || hover.hovered || ctxGroup !== null
            property int menu: 0          // 0 net, 1 vol, 2 bt, 3 batt, 4 notif

            Region { id: pillRegion; item: pill }
            Region { id: fullRegion; item: backdrop }

            MouseArea {
                id: backdrop
                anchors.fill: parent
                enabled: win.open || win.launcher || win.ctxGroup !== null
                onClicked: { win.open = false; win.launcher = false; win.ctxGroup = null; }
            }

            Item {
                id: pill
                anchors.horizontalCenter: parent.horizontalCenter
                y: 6
                width: win.launcher ? 520 : (win.dash ? 384 : 96)
                height: (win.open || win.launcher) ? 470 : (win.dash ? 104 : 28)
                Behavior on width  { NumberAnimation { duration: theme.anim; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: theme.anim; easing.type: Easing.OutCubic } }

                HoverHandler { id: hover }

                Rectangle {
                    anchors.fill: parent
                    radius: Math.min(theme.radius, height / 2)
                    color: theme.bg
                    border.color: theme.border
                    border.width: 1
                    Behavior on radius { NumberAnimation { duration: theme.anim } }
                }

                MouseArea { anchors.fill: parent; enabled: win.dash && !win.open && !win.launcher; onClicked: win.open = true }
                MouseArea { anchors.fill: parent; enabled: win.open || win.launcher; onClicked: {} }

                // ---- collapsed: clock (hh:mm) ----
                Text {
                    anchors.centerIn: parent
                    visible: !win.dash
                    text: root.clockShort
                    color: theme.text
                    font.family: theme.mono
                    font.pixelSize: theme.fsNormal
                }

                // ================= Row 1: desktops (left) | apps (right) =================
                Item {
                    x: theme.pad; y: 12
                    width: pill.width - theme.pad * 2
                    height: 26
                    opacity: win.dash ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: theme.animFast } }

                    Row {                                   // virtual desktops
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        Repeater {
                            model: root.desktops
                            delegate: Rectangle {
                                required property var modelData
                                width: 13; height: 13; radius: 7
                                color: modelData.id === root.currentDesktop ? theme.accent : "transparent"
                                border.color: theme.accent; border.width: 2
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.switchDesktop(modelData.id) }
                            }
                        }
                    }

                    Row {                                   // grouped app icons (taskbar)
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Repeater {
                            model: root.appGroups
                            delegate: Item {
                                id: appItem
                                required property var modelData
                                width: 26; height: 26
                                IconImage {
                                    anchors.top: parent.top
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    implicitSize: 22
                                    source: Quickshell.iconPath(appItem.modelData.icon, "application-x-executable")
                                }
                                Text {                       // window-count badge (2+ windows)
                                    visible: appItem.modelData.wins.length > 1
                                    anchors.top: parent.top; anchors.right: parent.right
                                    text: appItem.modelData.wins.length
                                    color: theme.text; font.pixelSize: 9; font.bold: true
                                }
                                Rectangle {                  // active / running indicator
                                    anchors.bottom: parent.bottom
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    height: 2; radius: 1
                                    width: root.groupActive(appItem.modelData) ? 16 : 6
                                    color: root.groupActive(appItem.modelData) ? theme.accent : theme.textDim
                                    Behavior on width { NumberAnimation { duration: theme.animFast } }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: mouse => {
                                        if (mouse.button === Qt.LeftButton) root.cycleGroup(appItem.modelData);
                                        else win.ctxGroup = appItem.modelData;
                                    }
                                }
                            }
                        }
                    }
                }

                // ============ Row 2: date/time (left) | status + tray (right) ============
                Item {
                    x: theme.pad; y: 62
                    width: pill.width - theme.pad * 2
                    height: 24
                    opacity: (win.dash && !win.open && !win.launcher) ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: theme.animFast } }

                    Row {                                    // launcher button + date/time (left)
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        IconImage {                          // open the app launcher
                            anchors.verticalCenter: parent.verticalCenter
                            implicitSize: 18
                            source: Quickshell.iconPath("view-app-grid", "application-x-executable")
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: win.launcher = true }
                        }
                        Text {                               // date/time
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.clockText
                            color: theme.textDim; font.family: theme.mono; font.pixelSize: theme.fsSmall
                        }
                    }

                    Row {                                    // status icons + system tray (right)
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12

                        Repeater {                           // status icons -> open panel to that menu
                            model: [
                                { ic: "network-wireless", menu: 0 },
                                { ic: (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio && Pipewire.defaultAudioSink.audio.muted)
                                       ? "audio-volume-muted" : "audio-volume-high", menu: 1 },
                                { ic: "bluetooth", menu: 2 },
                                { ic: (UPower.displayDevice && UPower.displayDevice.iconName) ? UPower.displayDevice.iconName : "battery", menu: 3 }
                            ]
                            delegate: IconImage {
                                required property var modelData
                                implicitSize: 18
                                source: Quickshell.iconPath(modelData.ic, "application-x-executable")
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: { win.menu = modelData.menu; win.open = true; } }
                            }
                        }
                        Repeater {                           // system tray
                            model: SystemTray.items
                            delegate: Item {
                                required property SystemTrayItem modelData
                                width: 18; height: 18
                                Image { anchors.fill: parent; source: modelData.icon; fillMode: Image.PreserveAspectFit }
                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: mouse => {
                                        if (mouse.button === Qt.LeftButton) modelData.activate();
                                        else modelData.display(win, width / 2, height);
                                    }
                                }
                            }
                        }
                    }
                }

                // ===================== control panel (open) =====================
                Item {
                    x: theme.pad; y: 46
                    width: pill.width - theme.pad * 2
                    height: pill.height - 46 - theme.pad
                    opacity: win.open ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: theme.anim } }

                    Rectangle { width: parent.width; height: 1; color: theme.divider }

                    Column {                          // left icon rail
                        id: rail
                        y: 12
                        spacing: 8
                        Repeater {
                            model: [
                                { ic: "network-wireless",                 i: 0 },
                                { ic: "audio-volume-high",                i: 1 },
                                { ic: "bluetooth",                        i: 2 },
                                { ic: "battery",                          i: 3 },
                                { ic: "preferences-desktop-notification", i: 4 }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                width: theme.railWidth - 8; height: theme.railWidth - 8
                                radius: theme.radiusSmall
                                color: win.menu === modelData.i ? theme.accentDim : "transparent"
                                IconImage {
                                    anchors.centerIn: parent; implicitSize: 22
                                    source: Quickshell.iconPath(modelData.ic, "application-x-executable")
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: win.menu = modelData.i }
                            }
                        }
                    }

                    Item {                            // menu pane
                        x: theme.railWidth + 12; y: 14
                        width: parent.width - theme.railWidth - 12
                        height: parent.height - 26
                        Loader {
                            anchors.fill: parent
                            active: win.open
                            sourceComponent: win.menu === 0 ? cNet
                                           : win.menu === 1 ? cVol
                                           : win.menu === 2 ? cBt
                                           : win.menu === 3 ? cBatt : cNotif
                        }
                    }
                }

                // ===================== launcher (wider open state) =====================
                Item {
                    x: theme.pad; y: 46
                    width: pill.width - theme.pad * 2
                    height: pill.height - 46 - theme.pad
                    clip: true
                    opacity: win.launcher ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: theme.anim } }

                    Rectangle { width: parent.width; height: 1; color: theme.divider }

                    // Kept instantiated (not gated on win.launcher) so the list
                    // virtualises and pre-warms its icons in the background at
                    // startup; subsequent opens are instant. Sized to the open
                    // dimensions regardless of the pill's current animation so
                    // the ListView always has room to lay out; the panel clips.
                    Launcher {
                        y: 14
                        width: 520 - theme.pad * 2
                        height: 470 - 46 - theme.pad - 14
                        theme: theme
                        apps: root.appList
                        onLaunched: win.launcher = false
                    }
                }
            }

            // ===================== app right-click menu =====================
            Loader {
                active: win.ctxGroup !== null
                anchors.horizontalCenter: parent.horizontalCenter
                y: pill.y + pill.height + 6
                sourceComponent: Rectangle {
                    id: ctxCard
                    width: 240
                    height: ctxCol.height + 16
                    radius: theme.radiusSmall
                    color: theme.bgElevated
                    border.color: theme.border; border.width: 1
                    readonly property var entry: win.ctxGroup ? DesktopEntries.heuristicLookup(win.ctxGroup.icon) : null

                    Column {
                        id: ctxCol
                        x: 8; y: 8
                        width: parent.width - 16
                        spacing: 2

                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: ctxCard.entry ? ctxCard.entry.name : (win.ctxGroup ? win.ctxGroup.icon : "")
                            color: theme.textDim; font.pixelSize: theme.fsSmall; font.bold: true
                            bottomPadding: 4
                        }
                        Repeater {                        // launcher actions (New Window, …)
                            model: ctxCard.entry ? ctxCard.entry.actions : []
                            delegate: Rectangle {
                                required property var modelData
                                width: ctxCol.width; height: 28; radius: theme.radiusSmall
                                color: ma.containsMouse ? theme.bgHover : "transparent"
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter; x: 8
                                    text: modelData.name; color: theme.text; font.pixelSize: theme.fsNormal
                                }
                                MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.launch(modelData.execString); win.ctxGroup = null; } }
                            }
                        }
                        Rectangle { width: parent.width; height: 1; color: theme.divider
                            visible: win.ctxGroup !== null && win.ctxGroup.wins.length > 0 }
                        Repeater {                        // this app's windows (click to focus)
                            model: win.ctxGroup ? win.ctxGroup.wins : []
                            delegate: Rectangle {
                                required property var modelData
                                width: ctxCol.width; height: 28; radius: theme.radiusSmall
                                color: wma.containsMouse ? theme.bgHover : "transparent"
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter; x: 8
                                    width: parent.width - 16; elide: Text.ElideRight
                                    text: modelData.title; color: theme.text; font.pixelSize: theme.fsSmall
                                }
                                MouseArea { id: wma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.activateWindow(modelData.id); win.ctxGroup = null; } }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- menu components ----
    Component { id: cNet;  NetworkMenu   { theme: theme } }
    Component { id: cVol;  VolumeMenu    { theme: theme } }
    Component { id: cBt;   BluetoothMenu { theme: theme } }
    Component { id: cBatt; BatteryMenu   { theme: theme } }
    Component { id: cNotif; Item {
        Text {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: "Notification history\n(coming soon)"
            color: theme.textDim; font.pixelSize: theme.fsNormal
        }
    } }

    // ---- clock ----
    SystemClock { id: sysclock; precision: SystemClock.Seconds }
    readonly property string clockText: Qt.formatDateTime(sysclock.date, "ddd  hh:mm:ss")
    readonly property string clockShort: Qt.formatDateTime(sysclock.date, "hh:mm")
}
