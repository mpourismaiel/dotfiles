import { IconMap } from "../../utils/icons.js";

const Bluetooth = await Service.import("bluetooth");

const DeviceItem = (device) =>
  Widget.Box({
    className: "device-item",
    children: [
      Widget.Icon({
        className: "icon",
        size: 16,
        icon: device.icon_name + "-symbolic",
      }),
      Widget.Label({ className: "label", label: device.name }),
      Widget.Label({
        className: "percentage",
        label: `${device.battery_percentage}%`,
        visible: device.bind("battery_percentage").as((p) => p > 0),
      }),
      Widget.Box({ hexpand: true }),
      Widget.Spinner({
        active: device.bind("connecting"),
        visible: device.bind("connecting"),
      }),
      Widget.Switch({
        active: device.bind("connected"),
        visible: device.bind("connecting").as((p) => !p),
        setup: (self) =>
          self.on("notify::active", () => {
            device.setConnection(self.active);
          }),
      }),
    ],
  });

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

export const BluetoothPageHeader = () => ({
  centerWidget: Widget.Label({ label: "Bluetooth" }),
  endWidget: Widget.Box({
    hpack: "end",
    child: Widget.Button({
      className: "toggle-button bluetooth-toggle-button",
      onPrimaryClick: () => (Bluetooth.enabled = !Bluetooth.enabled),
      child: Widget.Icon({
        size: 16,
        icon: Bluetooth.bind("enabled").as(
          (p) => IconMap.bluetooth[p ? "enabled" : "disabled"]
        ),
      }),
      setup: (self) =>
        self.hook(Bluetooth, () =>
          self.toggleClassName("active", Bluetooth.enabled)
        ),
    }),
  }),
});

const BluetoothPage = () => {
  return Widget.Box({
    vertical: true,
    spacing: 16,
    className: "bluetooth-settings",
    children: [BluetoothDevices()],
  });
};

export default BluetoothPage;
