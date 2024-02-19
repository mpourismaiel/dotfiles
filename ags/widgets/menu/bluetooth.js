const Bluetooth = await Service.import("bluetooth");

const Container = ({ children }) => Widget.Box({ spacing: 16, children });

const BluetoothButton = () => {
  const BluetoothButton = () =>
    Widget.Icon({
      size: 24,
      setup: (self) =>
        self.hook(Bluetooth, (self) => {
          self.icon = Bluetooth.enabled
            ? "bluetooth-active-symbolic"
            : "bluetooth-disabled-symbolic";
        }),
    });

  const BluetoothIndicator = () =>
    Container({
      children: [
        BluetoothButton(),
        Widget.Label({
          class_name: "title",
          hpack: "start",
          label: "Bluetooth",
        }),
      ],
    });

  return Widget.Button({
    className: "bar-bluetooth panel-button",
    child: BluetoothIndicator(),
  });
};

export default BluetoothButton;
