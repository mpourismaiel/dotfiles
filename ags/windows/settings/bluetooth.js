import { IconMap } from "../../utils/icons.js";
import SettingsHeaderButton from "../../widgets/_components/button/settings-header.js";

const Bluetooth = await Service.import("bluetooth");

const Gio = imports.gi.Gio;
const GLib = imports.gi.GLib;

// Replace "/org/bluez/hci0" with the correct path to your Bluetooth adapter
const adapterPath = "/org/bluez/hci0";

const proxy = new Gio.DBusProxy({
  g_connection: Gio.bus_get_sync(Gio.BusType.SYSTEM, null),
  g_interface_name: "org.bluez.Adapter1",
  g_object_path: adapterPath,
  g_name: "org.bluez",
});

const DeviceItem = (device) => {
  return Widget.Box({
    className: "device-item",
    children: [
      Widget.Icon({
        className: "icon",
        vpack: "start",
        size: 16,
        icon: device.icon_name + "-symbolic",
      }),
      Widget.Box({
        vertical: true,
        children: [
          Widget.Label({
            hpack: "start",
            className: "label",
            label: device.name,
          }),
          Widget.Box({
            spacing: 16,
            vpack: "start",
            children: [
              Widget.Label({
                className: "paired",
                label: device
                  .bind("paired")
                  .as((v) => `${v ? "Paired" : "Not Paired"}`),
              }),
              Widget.Label({
                className: "trusted",
                label: device
                  .bind("trusted")
                  .as((v) => `${v ? "Trusted" : "Not Trusted"}`),
              }),
              Widget.Label({
                className: "percentage",
                label: `${device.battery_percentage}%`,
                visible: device.bind("battery_percentage").as((p) => p > 0),
              }),
            ],
          }),
        ],
      }),
      Widget.Box({ hexpand: true }),
      Widget.Box({
        spacing: 8,
        children: [
          Widget.Button({
            className: "toggle-button",
            on_clicked: () => {
              device.setConnection(!device.connected);
            },
            child: Widget.Stack({
              children: {
                connecting: Widget.Icon({
                  className: "spinner",
                  icon: IconMap.ui.refresh,
                  size: 16,
                }),
                normal: Widget.Stack({
                  children: {
                    connected: Widget.Icon({
                      icon: IconMap.bluetooth.enabled,
                      size: 16,
                    }),
                    disconnected: Widget.Icon({
                      icon: IconMap.bluetooth.disabled,
                      size: 16,
                    }),
                  },
                  shown: device
                    .bind("connected")
                    .as((v) => (v ? "connected" : "disconnected")),
                }),
              },
              shown: device
                .bind("connecting")
                .as((v) => (v ? "connecting" : "normal")),
            }),
          }),
        ],
      }),
    ],
  });
};

const BluetoothDevices = () => {
  return Widget.Box({
    className: "content",
    child: Widget.Scrollable({
      hscroll: "never",
      className: "full-page-scroll",
      child: Widget.Box({
        vertical: true,
        children: Bluetooth.bind("devices").as((ds) =>
          ds
            .filter((d) => d.name)
            .map((device, i, arr) => {
              const items = [];
              items.push(DeviceItem(device));

              if (i < arr.length - 1) {
                items.push(Widget.Separator());
              }

              return items;
            })
            .flat()
        ),
      }),
    }),
  });
};

export const BluetoothPageHeader = () => {
  const scanning = Variable(false);
  return {
    centerWidget: Widget.Label({ label: "Bluetooth" }),
    endWidget: [
      SettingsHeaderButton({
        className: "bluetooth-rescan-button",
        on_clicked: async () => {
          if (scanning.value) {
            return;
          }
          scanning.value = true;
          await Utils.execAsync("bluetoothctl scan on");
          scanning.value = false;
        },
        icon: IconMap.ui.refresh,
        loading: scanning,
      }),
      SettingsHeaderButton({
        className: "toggle-button bluetooth-toggle-button",
        on_clicked: () => (Bluetooth.enabled = !Bluetooth.enabled),
        icon: Bluetooth.bind("enabled").as(
          (p) => IconMap.bluetooth[p ? "enabled" : "disabled"]
        ),
        setup: (self) =>
          self.hook(Bluetooth, () =>
            self.toggleClassName("active", Bluetooth.enabled)
          ),
      }),
    ],
  };
};

const BluetoothPage = () => {
  return Widget.Box({
    vertical: true,
    spacing: 16,
    className: "bluetooth-settings",
    children: [BluetoothDevices()],
  });
};

export default BluetoothPage;
