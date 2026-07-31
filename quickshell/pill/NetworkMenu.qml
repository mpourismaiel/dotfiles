pragma ComponentBehavior: Bound
// NetworkMenu.qml — Wi-Fi list (signal + lock + active), connect/disconnect, and an
// inline password field that expands under a secured unknown network (an eye toggles
// reveal). Wi-Fi is Quickshell.Networking (NetworkManager); wired (LAN) + VPN are NOT
// in that binding, so they come from the shared NetState (nmcli). A header gear opens
// KDE's network KCM. In-flight connect/disconnect fills the row's ConnButton with a
// BusyStripe until the connection settles (a watchdog clears it if a connect silently
// fails, e.g. a wrong password).
import QtQuick
import Quickshell.Io
import Quickshell.Networking

Item {
    id: root
    required property var theme
    required property var netState
    signal closeRequested()

    // ---- search: one query filters every section (wired / wifi / vpn); a
    // section's label survives only while it still has matches ----
    function matches(s) { return search.text === "" || (s || "").toLowerCase().includes(search.text.toLowerCase()); }
    readonly property var fLans: root.netState.lans.filter(c => root.matches(c.name))
    readonly property var fNets: root.netState.nets.filter(n => root.matches(n.name))
    readonly property var fVpns: root.netState.vpns.filter(c => root.matches(c.name))

    // open KDE's network settings — try Plasma 6 then older variants
    Process { id: settingsProc }
    function openNetworkSettings() {
        settingsProc.command = ["sh", "-c",
            "kcmshell6 kcm_networkmanagement || systemsettings kcm_networkmanagement || kcmshell5 kcm_networkmanagement"];
        settingsProc.startDetached();
        root.closeRequested();
    }

    // scan (and poll LAN/VPN) only while the menu is visible
    Component.onCompleted: { if (root.netState.wifiDev) root.netState.wifiDev.scannerEnabled = true; root.netState.refresh(); }
    Component.onDestruction: if (root.netState.wifiDev) root.netState.wifiDev.scannerEnabled = false

    // a wired/VPN connection row (name + connect/disconnect), reused by both the LAN
    // and VPN sections (they share NetState's nmcli up/down plumbing; busyConn marks
    // the one in flight so its ConnButton shows a stripe).
    component ConnRow: Rectangle {
        id: connRow
        required property var conn
        readonly property bool busy: root.netState.busyConn === conn.name
        // keyboard nav: Enter = the row click (connect/disconnect); the opaque
        // row self-styles focus like the clipboard rows (rowHi)
        readonly property bool kbFocusable: !connRow.busy
        property bool kbFocused: false
        function keyClick() { root.netState.setConn(connRow.conn.name, !connRow.conn.active); }
        width: parent ? parent.width : 0
        height: root.theme.rowHeight
        radius: root.theme.radiusRow
        color: connRow.kbFocused ? root.theme.rowHi : conn.active ? root.theme.accentDim : root.theme.row
        Text {
            anchors.left: parent.left; anchors.leftMargin: 12
            anchors.right: connBtn.left; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: connRow.conn.name
            color: root.theme.text
            font.family: root.theme.family
            font.pixelSize: root.theme.fsNormal
        }
        ConnButton {
            id: connBtn
            anchors.right: parent.right; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            theme: root.theme
            active: connRow.conn.active
            busy: connRow.busy
            label: connRow.busy ? (connRow.conn.active ? "Disconnecting" : "Connecting")
                                : (connRow.conn.active ? "Disconnect" : "Connect")
        }
        MouseArea {
            anchors.fill: parent
            enabled: !connRow.busy
            cursorShape: Qt.PointingHandCursor
            onClicked: root.netState.setConn(connRow.conn.name, !connRow.conn.active)
        }
    }
    component NetLabel: Text {
        color: root.theme.faint
        font.family: root.theme.mono
        font.pixelSize: root.theme.fsSmall
        font.letterSpacing: root.theme.labelSpacing
        font.capitalization: Font.AllUppercase
    }

    Column {
        anchors.fill: parent
        spacing: root.theme.gap

        MenuHeader {                            // back chevron + title + settings gear + Wi-Fi toggle
            theme: root.theme
            title: "Network"
            onBack: root.closeRequested()
            MSym {                              // open KDE network settings
                readonly property bool kbFocusable: true
                property bool kbFocused: false
                function keyClick() { root.openNetworkSettings(); }
                anchors.verticalCenter: parent.verticalCenter
                icon: "settings"
                size: 19
                color: (gearMa.containsMouse || kbFocused) ? root.theme.text : root.theme.faint
                MouseArea {
                    id: gearMa
                    anchors.fill: parent; anchors.margins: -4
                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.openNetworkSettings()
                }
            }
            PillToggle {
                theme: root.theme
                anchors.verticalCenter: parent.verticalCenter
                checked: root.netState.wifiEnabled
                onToggled: v => Networking.wifiEnabled = v
            }
        }

        SearchField {
            id: search
            width: parent.width
            theme: root.theme
            placeholder: "Search networks"
        }

        Flickable {                             // network list
            width: parent.width
            height: parent.height - 36 - 34 - root.theme.gap
            contentHeight: netCol.height
            clip: true
            Column {
                id: netCol
                width: parent.width
                spacing: 4

                // ---- wired (LAN) — nmcli, shown first ----
                NetLabel { text: "Wired"; visible: root.fLans.length > 0 }
                Repeater {
                    model: root.fLans
                    delegate: ConnRow { required property var modelData; width: netCol.width; conn: modelData }
                }

                // ---- Wi-Fi ----
                NetLabel { text: "Wi-Fi"; visible: root.fNets.length > 0 }
                Repeater {
                    model: root.fNets
                    delegate: Rectangle {
                        id: netRow
                        required property var modelData
                        // in-flight connect/disconnect; busyTarget = the connected-state
                        // we're moving toward, so we know when we've arrived.
                        property bool busy: false
                        property bool busyTarget: false
                        property bool expanded: false      // password field revealed
                        property bool showPw: false        // eye toggle
                        // keyboard nav: Enter = the row click (connect / disconnect /
                        // reveal the password field for a secured unknown net); the
                        // opaque row self-styles focus like the clipboard rows
                        readonly property bool kbFocusable: !netRow.busy
                        property bool kbFocused: false
                        function keyClick() { netRow.act(); }
                        width: netCol.width
                        height: rowCol.height
                        radius: root.theme.radiusRow
                        color: netRow.kbFocused ? root.theme.rowHi : modelData.connected ? root.theme.accentDim : root.theme.row

                        function begin(target) { netRow.busy = true; netRow.busyTarget = target; wd.restart(); }
                        function act() {
                            const n = netRow.modelData;
                            if (n.connected) { netRow.begin(false); n.disconnect(); return; }
                            if (n.known || n.security === WifiSecurityType.Open) { netRow.begin(true); n.connect(); return; }
                            netRow.expanded = !netRow.expanded;   // secured + unknown -> ask for a password
                        }
                        function submitPsk() {
                            if (!pwInput.text) return;
                            netRow.begin(true);
                            netRow.modelData.connectWithPsk(pwInput.text);
                            netRow.expanded = false; netRow.showPw = false; pwInput.text = "";
                        }
                        // clear busy once the connection settles to the target state; the
                        // watchdog also clears it if a connect silently fails (bad psk).
                        Timer { id: wd; interval: 25000; onTriggered: netRow.busy = false }
                        Connections {
                            target: netRow.modelData
                            function onConnectedChanged() {
                                if (netRow.modelData.connected === netRow.busyTarget) { netRow.busy = false; wd.stop(); }
                            }
                        }

                        Column {
                            id: rowCol
                            width: parent.width

                            // ---- info strip: signal + name + lock + connect ----
                            Item {
                                width: parent.width
                                height: root.theme.rowHeight
                                Row {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 9
                                    MSym {
                                        anchors.verticalCenter: parent.verticalCenter
                                        size: 18
                                        fill: 1
                                        icon: {
                                            const s = netRow.modelData.signalStrength;
                                            return s > 0.75 ? "network_wifi" : s > 0.5 ? "network_wifi_3_bar"
                                                 : s > 0.25 ? "network_wifi_2_bar" : "network_wifi_1_bar";
                                        }
                                        color: netRow.modelData.connected ? root.theme.accent : root.theme.textDim
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.max(0, netRow.width - 185)
                                        elide: Text.ElideRight
                                        text: netRow.modelData.name
                                        color: root.theme.text
                                        font.family: root.theme.family
                                        font.pixelSize: root.theme.fsNormal
                                    }
                                    MSym {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: netRow.modelData.security !== WifiSecurityType.Open
                                        icon: "lock"
                                        size: 13
                                        color: root.theme.faint
                                    }
                                }
                                ConnButton {
                                    id: wifiBtn
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    theme: root.theme
                                    active: netRow.modelData.connected
                                    busy: netRow.busy
                                    label: netRow.busy ? (netRow.busyTarget ? "Connecting" : "Disconnecting")
                                         : netRow.expanded ? "Cancel"
                                         : (netRow.modelData.connected ? "Disconnect" : "Connect")
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: !netRow.busy
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: netRow.act()
                                }
                            }

                            // ---- password field (expands for a secured unknown net) ----
                            Item {
                                width: parent.width
                                height: netRow.expanded ? 46 : 0
                                visible: height > 0
                                clip: true
                                Behavior on height { NumberAnimation { duration: root.theme.anim; easing.type: Easing.OutCubic } }
                                Rectangle {
                                    id: pwField
                                    anchors.left: parent.left; anchors.leftMargin: 12
                                    anchors.right: pskBtn.left; anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 34
                                    radius: root.theme.radiusRow
                                    color: root.theme.row
                                    border.color: pwInput.activeFocus ? root.theme.accent : root.theme.border
                                    TextInput {
                                        id: pwInput
                                        objectName: "pillKbInput"
                                        anchors.left: parent.left; anchors.leftMargin: 10
                                        anchors.right: eye.left; anchors.rightMargin: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        verticalAlignment: TextInput.AlignVCenter
                                        echoMode: netRow.showPw ? TextInput.Normal : TextInput.Password
                                        color: root.theme.text
                                        font.family: root.theme.family
                                        font.pixelSize: root.theme.fsNormal
                                        clip: true
                                        focus: netRow.expanded
                                        onAccepted: netRow.submitPsk()
                                    }
                                    MSym {                       // eye — toggle text/password reveal
                                        id: eye
                                        anchors.right: parent.right; anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        icon: netRow.showPw ? "visibility_off" : "visibility"
                                        size: 18
                                        color: eyeMa.containsMouse ? root.theme.text : root.theme.faint
                                        MouseArea {
                                            id: eyeMa
                                            anchors.fill: parent; anchors.margins: -4
                                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: netRow.showPw = !netRow.showPw
                                        }
                                    }
                                }
                                ConnButton {
                                    id: pskBtn
                                    anchors.right: parent.right; anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    theme: root.theme
                                    interactive: true
                                    active: true
                                    label: "Connect"
                                    onClicked: netRow.submitPsk()
                                }
                            }
                        }
                    }
                }

                // ---- VPN — nmcli, shown last ----
                NetLabel { text: "VPN"; visible: root.fVpns.length > 0 }
                Repeater {
                    model: root.fVpns
                    delegate: ConnRow { required property var modelData; width: netCol.width; conn: modelData }
                }
            }
        }
    }
}
