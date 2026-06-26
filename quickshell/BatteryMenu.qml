pragma ComponentBehavior: Bound
// BatteryMenu.qml — every present power device (laptop battery, mouse, keyboard,
// headphones, …) with themed icon, name, state and percentage. Uses
// Quickshell.Services.UPower + Quickshell.iconPath for icons.
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.UPower

Item {
    id: root
    required property var theme

    readonly property var devs: {
        const a = UPower.devices ? UPower.devices.values : [];
        return a.filter(d => d.isPresent && d.type !== UPowerDeviceType.LinePower);
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.height
        clip: true
        Column {
            id: col
            width: parent.width
            spacing: 12

            Repeater {
                model: root.devs
                delegate: Row {
                    id: devRow
                    required property var modelData
                    width: col.width
                    spacing: 10

                    IconImage {
                        anchors.verticalCenter: parent.verticalCenter
                        implicitSize: 28
                        source: Quickshell.iconPath(devRow.modelData.iconName, "battery")
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 28 - 10 - 60
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: (devRow.modelData.model && devRow.modelData.model.length)
                                  ? devRow.modelData.model
                                  : UPowerDeviceType.toString(devRow.modelData.type)
                            color: root.theme.text
                            font.pixelSize: root.theme.fsNormal
                        }
                        Text {
                            text: UPowerDeviceState.toString(devRow.modelData.state)
                            color: root.theme.textDim
                            font.pixelSize: root.theme.fsSmall
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.round(devRow.modelData.percentage) + "%"
                        color: root.theme.text
                        font.pixelSize: root.theme.fsLarge
                        font.bold: true
                    }
                }
            }
            Text {
                visible: root.devs.length === 0
                text: "No battery devices"
                color: root.theme.textDim
                font.pixelSize: root.theme.fsNormal
            }
        }
    }
}
