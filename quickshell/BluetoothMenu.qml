pragma ComponentBehavior: Bound
// BluetoothMenu.qml — adapter power + scan toggles, then three sections:
// Connected, Paired (known, not connected), Available (discovered). Connect /
// disconnect / pair per row, battery % if reported. Uses Quickshell.Bluetooth.
import QtQuick

import Quickshell.Bluetooth

Item {
    id: root
    required property var theme
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: Bluetooth.devices ? Bluetooth.devices.values : []

    readonly property var connected: devices.filter(d => d.connected)
    readonly property var paired:    devices.filter(d => d.paired && !d.connected)
    readonly property var found:     devices.filter(d => !d.paired && !d.connected)

    // a single device row, reused by all three sections
    component DevRow: Rectangle {
        required property var device
        property var theme: root.theme
        width: parent ? parent.width : 0
        height: root.theme.rowHeight
        radius: root.theme.radiusSmall
        color: device.connected ? root.theme.accentDim : root.theme.bgHover
        Row {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: device.name || device.deviceName || device.address
                color: root.theme.text
                font.pixelSize: root.theme.fsNormal
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: device.batteryAvailable
                text: Math.round(device.battery) + "%"
                color: root.theme.textDim
                font.pixelSize: root.theme.fsSmall
            }
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: device.connected ? "Disconnect" : (device.paired ? "Connect" : "Pair")
            color: root.theme.textDim
            font.pixelSize: root.theme.fsSmall
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (device.connected) device.disconnect();
                else if (device.paired) device.connect();
                else device.pair();
            }
        }
    }

    component SectionLabel: Text {
        color: root.theme.textDim
        font.pixelSize: root.theme.fsSmall
        font.bold: true
    }

    Column {
        anchors.fill: parent
        spacing: root.theme.gap

        Row {                                   // header: power + scan
            width: parent.width
            spacing: root.theme.gap
            Text {
                text: "Bluetooth"
                color: root.theme.text
                font.pixelSize: root.theme.fsNormal
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
            Item { width: parent.width - 160; height: 1 }
            Text {
                text: "Scan"
                color: root.theme.textDim
                font.pixelSize: root.theme.fsSmall
                anchors.verticalCenter: parent.verticalCenter
            }
            PillToggle {
                theme: root.theme
                anchors.verticalCenter: parent.verticalCenter
                checked: root.adapter ? root.adapter.discovering : false
                onToggled: v => { if (root.adapter) root.adapter.discovering = v; }
            }
            PillToggle {
                theme: root.theme
                anchors.verticalCenter: parent.verticalCenter
                checked: root.adapter ? root.adapter.enabled : false
                onToggled: v => { if (root.adapter) root.adapter.enabled = v; }
            }
        }

        Flickable {
            width: parent.width
            height: parent.height - 36
            contentHeight: col.height
            clip: true
            Column {
                id: col
                width: parent.width
                spacing: 4

                SectionLabel { text: "Connected"; visible: root.connected.length > 0 }
                Repeater { model: root.connected; delegate: DevRow { required property var modelData; device: modelData } }

                Rectangle { width: parent.width; height: 1; color: root.theme.divider
                    visible: root.connected.length > 0 && root.paired.length > 0 }

                SectionLabel { text: "Paired"; visible: root.paired.length > 0 }
                Repeater { model: root.paired; delegate: DevRow { required property var modelData; device: modelData } }

                Rectangle { width: parent.width; height: 1; color: root.theme.divider
                    visible: root.found.length > 0 && (root.connected.length + root.paired.length) > 0 }

                SectionLabel { text: "Available"; visible: root.found.length > 0 }
                Repeater { model: root.found; delegate: DevRow { required property var modelData; device: modelData } }
            }
        }
    }
}
