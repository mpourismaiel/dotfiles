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
    required property var brightness      // shared Brightness state (per-display)
    signal closeRequested()

    // re-read the displays each time the menu opens (values may have changed via
    // the shortcut / KDE OSD while it was closed).
    Component.onCompleted: if (root.brightness) root.brightness.refresh()

    readonly property var devs: {
        const a = UPower.devices ? UPower.devices.values : [];
        return a.filter(d => d.isPresent && d.type !== UPowerDeviceType.LinePower);
    }

    Column {
        anchors.fill: parent
        spacing: root.theme.gap

        MenuHeader {                            // back chevron + title
            theme: root.theme
            title: "Battery"
            onBack: root.closeRequested()
        }

    Flickable {
        width: parent.width
        height: parent.height - 26 - root.theme.gap
        contentHeight: col.height
        clip: true
        Column {
            id: col
            width: parent.width
            spacing: 14

            // ---- per-monitor screen brightness (KDE ScreenBrightness / DDC) ----
            Text {
                visible: root.brightness && root.brightness.available
                text: "Screen brightness"
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
                font.capitalization: Font.AllUppercase
            }
            Repeater {
                model: (root.brightness && root.brightness.available) ? root.brightness.displays : []
                delegate: Column {
                    id: brRow
                    required property var modelData
                    width: col.width
                    spacing: 4
                    Row {
                        width: parent.width
                        spacing: 6
                        MSym {
                            anchors.verticalCenter: parent.verticalCenter
                            size: 18
                            fill: 1
                            color: root.theme.textDim
                            icon: brRow.modelData.internal ? "laptop" : "monitor"
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 18 - 6 - 44
                            elide: Text.ElideRight
                            text: brRow.modelData.label
                            color: root.theme.text
                            font.family: root.theme.family
                            font.pixelSize: root.theme.fsNormal
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 44
                            horizontalAlignment: Text.AlignRight
                            text: Math.round(brRow.modelData.value * 100) + "%"
                            color: root.theme.faint
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall
                        }
                    }
                    PillSlider {
                        theme: root.theme
                        width: parent.width
                        value: brRow.modelData.value
                        onMoved: v => root.brightness.setRatio(brRow.modelData, v)
                    }
                }
            }
            Rectangle {                          // divider before the battery devices
                visible: root.brightness && root.brightness.available && root.devs.length > 0
                width: parent.width; height: 1; color: root.theme.divider
            }

            Repeater {
                model: root.devs
                delegate: Row {
                    id: devRow
                    required property var modelData
                    width: col.width
                    spacing: 14

                    MSym {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 24
                        fill: 1
                        color: root.theme.textDim
                        // map UPower state / percentage to a Material battery glyph
                        icon: {
                            const st = devRow.modelData.state;
                            if (st === UPowerDeviceState.Charging || st === UPowerDeviceState.PendingCharge)
                                return "battery_charging_full";
                            if (st === UPowerDeviceState.Unknown) return "battery_unknown";
                            const p = devRow.modelData.percentage;
                            if (p >= 0.95) return "battery_full";
                            if (p >= 0.80) return "battery_6_bar";
                            if (p >= 0.60) return "battery_5_bar";
                            if (p >= 0.45) return "battery_4_bar";
                            if (p >= 0.30) return "battery_3_bar";
                            if (p >= 0.15) return "battery_2_bar";
                            return "battery_1_bar";
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 24 - 14 - 60
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: (devRow.modelData.model && devRow.modelData.model.length)
                                  ? devRow.modelData.model
                                  : UPowerDeviceType.toString(devRow.modelData.type)
                            color: root.theme.text
                            font.family: root.theme.family
                            font.pixelSize: root.theme.fsNormal
                        }
                        Text {
                            text: UPowerDeviceState.toString(devRow.modelData.state)
                            color: root.theme.faint
                            font.family: root.theme.family
                            font.pixelSize: root.theme.fsSmall
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        // UPower percentage is a 0..1 ratio (see the glyph thresholds
                        // above), so scale to 0..100 — a full battery is 100%, not 1%.
                        text: Math.round(devRow.modelData.percentage * 100) + "%"
                        color: root.theme.text
                        font.family: root.theme.serif
                        font.pixelSize: root.theme.fsLarge + 3
                    }
                }
            }
            Text {
                visible: root.devs.length === 0
                text: "No battery devices"
                color: root.theme.textDim
                font.family: root.theme.family
                font.pixelSize: root.theme.fsNormal
            }
        }
    }
    }
}
