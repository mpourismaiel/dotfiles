pragma ComponentBehavior: Bound
// BluetoothMenu.qml — adapter power + scan toggles, then three sections:
// Connected, Paired (known, not connected), Available (discovered). Connect /
// disconnect / pair per row, battery % if reported. Uses Quickshell.Bluetooth.
import QtQuick

import Quickshell.Bluetooth

Item {
    id: root
    required property var theme
    signal closeRequested()
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: Bluetooth.devices ? Bluetooth.devices.values : []

    readonly property var connected: devices.filter(d => d.connected)
    readonly property var paired:    devices.filter(d => d.paired && !d.connected)
    readonly property var found:     devices.filter(d => !d.paired && !d.connected)

    // ---- search: one query filters every section (connected / paired /
    // available); a section's label and its dividers survive only while the
    // section still has matches ----
    function matches(d) {
        const s = d.name || d.deviceName || d.address || "";
        return search.text === "" || s.toLowerCase().includes(search.text.toLowerCase());
    }
    readonly property var fConnected: connected.filter(d => root.matches(d))
    readonly property var fPaired:    paired.filter(d => root.matches(d))
    readonly property var fFound:     found.filter(d => root.matches(d))

    // a single device row, reused by all three sections
    component DevRow: Rectangle {
        id: devRow
        required property var device
        property var theme: root.theme
        // in-flight connect/disconnect/pair; busyTarget = the connected-state we're
        // moving toward, so the stripe clears once we get there (a watchdog covers a
        // silent failure, e.g. pairing that never completes).
        property bool busy: false
        property bool busyTarget: false
        // keyboard nav: Enter = the row click (connect / disconnect / pair); the
        // opaque row self-styles focus like the clipboard rows (rowHi)
        readonly property bool kbFocusable: !devRow.busy
        property bool kbFocused: false
        function keyClick() { devRow.act(); }
        width: parent ? parent.width : 0
        height: root.theme.rowHeight
        radius: root.theme.radiusRow
        color: devRow.kbFocused ? root.theme.rowHi : device.connected ? root.theme.accentDim : root.theme.row

        function begin(target) { devRow.busy = true; devRow.busyTarget = target; wd.restart(); }
        function act() {
            const d = devRow.device;
            if (d.connected) { devRow.begin(false); d.disconnect(); }
            else if (d.paired) { devRow.begin(true); d.connect(); }
            else { devRow.begin(true); d.pair(); }
        }
        Timer { id: wd; interval: 25000; onTriggered: devRow.busy = false }
        Connections {
            target: devRow.device
            function onConnectedChanged() {
                if (devRow.device.connected === devRow.busyTarget) { devRow.busy = false; wd.stop(); }
            }
        }
        Row {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 9
            MSym {
                anchors.verticalCenter: parent.verticalCenter
                visible: device.connected
                icon: "bluetooth_connected"
                size: 17
                fill: 1
                color: root.theme.accent
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: device.name || device.deviceName || device.address
                color: root.theme.text
                font.family: root.theme.family
                font.pixelSize: root.theme.fsNormal
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: device.batteryAvailable
                // Bluetooth battery is a 0..1 ratio — scale to 0..100 (100%, not 1%).
                text: Math.round(device.battery * 100) + "%"
                color: root.theme.faint
                font.family: root.theme.family
                font.pixelSize: root.theme.fsSmall
            }
        }
        ConnButton {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            theme: root.theme
            active: devRow.device.connected
            busy: devRow.busy
            label: devRow.busy ? (devRow.busyTarget ? "Connecting" : "Disconnecting")
                 : (devRow.device.connected ? "Disconnect" : (devRow.device.paired ? "Connect" : "Pair"))
        }
        MouseArea {
            anchors.fill: parent
            enabled: !devRow.busy
            cursorShape: Qt.PointingHandCursor
            onClicked: devRow.act()
        }
    }

    component SectionLabel: Text {
        color: root.theme.faint
        font.family: root.theme.mono
        font.pixelSize: root.theme.fsSmall
        font.letterSpacing: root.theme.labelSpacing
        font.capitalization: Font.AllUppercase
    }

    Column {
        anchors.fill: parent
        spacing: root.theme.gap

        MenuHeader {                            // back chevron + title + scan/power toggles
            theme: root.theme
            title: "Bluetooth"
            onBack: root.closeRequested()
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Scan"
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
                font.capitalization: Font.AllUppercase
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

        SearchField {
            id: search
            width: parent.width
            theme: root.theme
            placeholder: "Search devices"
        }

        Flickable {
            width: parent.width
            height: parent.height - 36 - 34 - root.theme.gap
            contentHeight: col.height
            clip: true
            Column {
                id: col
                width: parent.width
                spacing: 4

                SectionLabel { text: "Connected"; visible: root.fConnected.length > 0 }
                Repeater { model: root.fConnected; delegate: DevRow { required property var modelData; device: modelData } }

                Rectangle { width: parent.width; height: 1; color: root.theme.divider
                    visible: root.fConnected.length > 0 && root.fPaired.length > 0 }

                SectionLabel { text: "Paired"; visible: root.fPaired.length > 0 }
                Repeater { model: root.fPaired; delegate: DevRow { required property var modelData; device: modelData } }

                Rectangle { width: parent.width; height: 1; color: root.theme.divider
                    visible: root.fFound.length > 0 && (root.fConnected.length + root.fPaired.length) > 0 }

                SectionLabel { text: "Available"; visible: root.fFound.length > 0 }
                Repeater { model: root.fFound; delegate: DevRow { required property var modelData; device: modelData } }
            }
        }
    }
}
