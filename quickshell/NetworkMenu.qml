pragma ComponentBehavior: Bound
// NetworkMenu.qml — Wi-Fi list (signal + lock + active), connect/disconnect,
// password prompt for secured networks, Wi-Fi on/off. Uses Quickshell.Networking
// (NetworkManager). VPN is NOT in the native binding — would need nmcli (TODO).
import QtQuick
import Quickshell.Networking

Item {
    id: root
    required property var theme

    readonly property var wifiDev: {
        const ds = Networking.devices ? Networking.devices.values : [];
        for (let i = 0; i < ds.length; i++)
            if (ds[i].type === DeviceType.Wifi) return ds[i];
        return null;
    }
    readonly property var nets: {
        if (!wifiDev || !wifiDev.networks) return [];
        const a = wifiDev.networks.values.slice();
        a.sort((x, y) => (y.connected - x.connected) || (y.signalStrength - x.signalStrength));
        return a;
    }
    property var pskTarget: null

    Component.onCompleted: if (wifiDev) wifiDev.scannerEnabled = true
    Component.onDestruction: if (wifiDev) wifiDev.scannerEnabled = false

    Column {
        anchors.fill: parent
        spacing: root.theme.gap

        Row {                                   // header + toggle
            width: parent.width
            Text {
                text: "Wi-Fi"
                color: root.theme.text
                font.pixelSize: root.theme.fsNormal
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
            Item { width: parent.width - 38 - 36; height: 1 }
            PillToggle {
                theme: root.theme
                anchors.verticalCenter: parent.verticalCenter
                checked: Networking.wifiEnabled
                onToggled: v => Networking.wifiEnabled = v
            }
        }

        Flickable {                             // network list
            width: parent.width
            height: parent.height - 36
            contentHeight: netCol.height
            clip: true
            Column {
                id: netCol
                width: parent.width
                spacing: 4
                Repeater {
                    model: root.nets
                    delegate: Rectangle {
                        id: netRow
                        required property var modelData
                        width: netCol.width
                        height: root.theme.rowHeight
                        radius: root.theme.radiusSmall
                        color: modelData.connected ? root.theme.accentDim : root.theme.bgHover

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: {
                                    const s = netRow.modelData.signalStrength;
                                    return s > 0.75 ? "▰▰▰▰" : s > 0.5 ? "▰▰▰▱" : s > 0.25 ? "▰▰▱▱" : "▰▱▱▱";
                                }
                                color: root.theme.accent
                                font.pixelSize: root.theme.fsSmall
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: netRow.width - 190
                                elide: Text.ElideRight
                                text: netRow.modelData.name
                                color: root.theme.text
                                font.pixelSize: root.theme.fsNormal
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: netRow.modelData.security !== WifiSecurityType.Open
                                text: "🔒"
                                font.pixelSize: root.theme.fsSmall
                            }
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: netRow.modelData.connected ? "Disconnect" : "Connect"
                            color: root.theme.textDim
                            font.pixelSize: root.theme.fsSmall
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const n = netRow.modelData;
                                if (n.connected) { n.disconnect(); return; }
                                if (n.known || n.security === WifiSecurityType.Open) n.connect();
                                else root.pskTarget = n;
                            }
                        }
                    }
                }
            }
        }
    }

    // password prompt overlay (secured + unknown networks)
    Rectangle {
        anchors.fill: parent
        visible: root.pskTarget !== null
        color: root.theme.bg
        radius: root.theme.radiusSmall
        Column {
            anchors.centerIn: parent
            width: parent.width - 24
            spacing: root.theme.gap
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: root.pskTarget ? ("Password for " + root.pskTarget.name) : ""
                color: root.theme.text
                font.pixelSize: root.theme.fsNormal
            }
            Rectangle {
                width: parent.width
                height: 34
                radius: root.theme.radiusSmall
                color: root.theme.bgHover
                border.color: root.theme.border
                TextInput {
                    id: pskInput
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    color: root.theme.text
                    font.pixelSize: root.theme.fsNormal
                    clip: true
                    focus: root.pskTarget !== null
                    onAccepted: {
                        if (root.pskTarget) root.pskTarget.connectWithPsk(text);
                        root.pskTarget = null; text = "";
                    }
                }
            }
            Row {
                anchors.right: parent.right
                spacing: root.theme.gap
                Text {
                    text: "Cancel"
                    color: root.theme.textDim
                    font.pixelSize: root.theme.fsNormal
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: { root.pskTarget = null; pskInput.text = ""; } }
                }
                Text {
                    text: "Connect"
                    color: root.theme.accent
                    font.pixelSize: root.theme.fsNormal
                    font.bold: true
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.pskTarget) root.pskTarget.connectWithPsk(pskInput.text);
                            root.pskTarget = null; pskInput.text = "";
                        } }
                }
            }
        }
    }
}
