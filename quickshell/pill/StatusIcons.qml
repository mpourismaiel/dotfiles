pragma ComponentBehavior: Bound
// StatusIcons.qml — the dashboard status switcher (Row 2). Network / volume /
// bluetooth / battery / notifications; the glyphs track live state — the volume
// icon follows Pipewire mute AND level (off/mute/down/up), the battery follows
// UPower charge/state (6-bar granularity + a red alert glyph when critically low),
// and the notifications icon carries a count badge for un-cleared history.
// menuRequested(menu) fires on click; when `open`, the icon for the current `menu`
// is highlighted. Menu ids: 0 net, 1 vol, 2 bt, 3 batt, 5 clipboard, 4 notif. Row
// order is net · bt · batt · vol · clipboard · notif (volume beside clipboard, away
// from the similar-looking network glyph). The hover highlight
// is NOT drawn here (only the open-menu selection): each icon reports itself via
// itemEntered (on enter only) so the shared hover square jumps to it.
import QtQuick
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

Row {
    id: root
    required property var theme
    property var notifs                  // notification state (drives the badge count)
    property var netState                // shared network state (drives the net glyph)
    property var fin                     // FinanceState (drives the evening nag glyph)
    property bool open: false
    property int menu: -1
    signal menuRequested(int menu)
    signal itemEntered(var item)         // icon hovered -> move the shared indicator

    // keep the default sink live so `volume`/`muted` fire property updates here.
    PwObjectTracker { objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : [] }

    // live glyphs: volume follows Pipewire mute + level; battery follows UPower.
    readonly property var sinkAudio: (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio) ? Pipewire.defaultAudioSink.audio : null
    readonly property bool muted: root.sinkAudio ? root.sinkAudio.muted : false
    readonly property real volume: root.sinkAudio ? root.sinkAudio.volume : 0
    function volumeIcon() {
        if (root.muted) return "volume_off";
        if (root.volume <= 0.001) return "volume_mute";  // speaker, no waves
        if (root.volume < 0.5) return "volume_down";      // one wave
        return "volume_up";                               // two waves
    }

    readonly property var battery: (UPower.displayDevice && UPower.displayDevice.isPresent) ? UPower.displayDevice : null
    readonly property bool charging: root.battery
        && (root.battery.state === UPowerDeviceState.Charging || root.battery.state === UPowerDeviceState.PendingCharge)
    // critically low and not on charge -> flag it (glyph turns red).
    readonly property bool batteryLow: root.battery && !root.charging && root.battery.percentage <= 0.15
    function batteryIcon() {
        if (!root.battery) return "power";
        if (root.charging) return "battery_charging_full";
        if (root.battery.state === UPowerDeviceState.Unknown) return "battery_unknown";
        const p = root.battery.percentage;
        if (p >= 0.95) return "battery_full";
        if (p >= 0.80) return "battery_6_bar";
        if (p >= 0.60) return "battery_5_bar";
        if (p >= 0.45) return "battery_4_bar";
        if (p >= 0.30) return "battery_3_bar";
        if (p >= 0.15) return "battery_2_bar";
        if (p >= 0.05) return "battery_1_bar";
        return "battery_alert";
    }

    // network glyph tracks the live state: wired first (LAN beats Wi-Fi), then the
    // connected Wi-Fi at its signal strength, then disconnected (radio on vs off).
    // An active VPN adds a small lock badge (drawn in the delegate).
    function netIcon() {
        const ns = root.netState;
        if (!ns) return "wifi_off";
        if (ns.lanActive) return "lan";
        if (ns.wifiActive) {
            const s = ns.wifiSignal;
            return s > 0.75 ? "network_wifi" : s > 0.5 ? "network_wifi_3_bar"
                 : s > 0.25 ? "network_wifi_2_bar" : "network_wifi_1_bar";
        }
        return ns.wifiEnabled ? "signal_wifi_off" : "wifi_off";
    }
    function netFill() {
        const ns = root.netState;
        return (ns && (ns.lanActive || ns.wifiActive)) ? 1 : 0;
    }

    readonly property int unread: root.notifs ? root.notifs.unreadCount : 0

    // keyboard nav (init.qml's dashboard handler): the icons as an ordered strip
    readonly property int iconCount: statusRep.count
    function iconAt(i) { return statusRep.itemAt(i); }

    spacing: root.theme.iconSpacing + 4
    Repeater {
        id: statusRep
        model: {
            var m = [
                { ic: root.netIcon(), fill: root.netFill(), menu: 0, warn: false, badge: 0, vpn: !!(root.netState && root.netState.vpnActive) },
                { ic: "bluetooth",     fill: 0, menu: 2, warn: false, badge: 0 },
                { ic: root.batteryIcon(), fill: 1, menu: 3, warn: root.batteryLow, badge: 0 },
                // volume sits right next to clipboard (the volume/network glyphs read
                // alike at a glance, so keep volume away from network)
                { ic: root.volumeIcon(), fill: root.muted ? 0 : 1, menu: 1, warn: false, badge: 0 },
                { ic: "content_paste", fill: 0, menu: 5, warn: false, badge: 0 },
                { ic: "notifications", fill: root.unread > 0 ? 1 : 0, menu: 4, warn: false, badge: root.unread }
            ];
            // evening finance nag: a red piggy bank, leftmost, only while the nag
            // is live (≥ 20:00, nothing logged today, not dismissed, privacy off);
            // clicking it opens the finance menu. See FinanceState.
            if (root.fin && root.fin.nagIcon)
                m.unshift({ ic: "savings", fill: 1, menu: 8, warn: true, badge: 0 });
            return m;
        }
        delegate: Rectangle {
            id: statusItem
            required property var modelData
            readonly property bool selected: root.open && root.menu === modelData.menu
            // keyboard nav: Enter = click (open this icon's menu)
            function keyClick() { root.menuRequested(statusItem.modelData.menu); }
            width: root.theme.iconCell + 4; height: root.theme.iconCell + 4; radius: root.theme.radiusBtn
            // only the open-menu selection is drawn here; hover is the shared square
            color: selected ? root.theme.accentDim : "transparent"
            Behavior on color { ColorAnimation { duration: root.theme.animFast } }
            MSym {
                anchors.centerIn: parent
                icon: modelData.ic
                size: 21
                fill: modelData.fill
                color: statusItem.selected ? root.theme.accent
                     : modelData.warn ? root.theme.danger
                     : root.theme.textDim
            }
            // active VPN/WireGuard -> a quarter-size lock badge tucked into the
            // network glyph's bottom-right, on a knockout disc so it stays legible
            // over the base icon (green = a protected tunnel is up).
            Item {
                visible: statusItem.modelData.vpn === true
                width: 13; height: 13
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: 1
                anchors.bottomMargin: 1
                Rectangle { anchors.fill: parent; radius: width / 2; color: root.theme.bg }
                MSym {
                    anchors.centerIn: parent
                    icon: "lock"; size: 11; fill: 1
                    color: statusItem.selected ? root.theme.accent : root.theme.good
                }
            }
            // un-cleared notifications count badge (top-right of the bell); "9+"
            // once past nine so it never outgrows the pill.
            Rectangle {
                visible: modelData.badge > 0
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 1
                anchors.rightMargin: 1
                width: Math.max(14, badgeText.implicitWidth + 6); height: 14; radius: 7
                color: root.theme.accent
                Text {
                    id: badgeText
                    anchors.centerIn: parent
                    text: modelData.badge > 9 ? "9+" : modelData.badge
                    font.family: root.theme.family
                    color: "#ffffff"; font.pixelSize: 9; font.bold: true
                }
            }
            MouseArea {
                id: statusMa
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (statusMa.containsMouse) root.itemEntered(statusItem);
                onClicked: root.menuRequested(modelData.menu)
            }
        }
    }
}
