import ArrowButton from "../_components/button/arrow.js";
import { WINDOW_NAME, openSettingsPage } from "../../windows/settings/main.js";

const Bluetooth = await Service.import("bluetooth");

const BluetoothButton = ({ onClose }) => {
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
    ArrowButton({
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
    onPrimaryClick: () => {
      onClose();
      App.toggleWindow(WINDOW_NAME);
      openSettingsPage("bluetooth");
    },
    child: BluetoothIndicator(),
  });
};

export default BluetoothButton;
