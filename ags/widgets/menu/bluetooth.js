import ArrowButton from "../_components/button/arrow.js";
import { WINDOW_NAME, openSettingsPage } from "../../windows/settings/main.js";
import QuickSettings from "./quick-settings.js";

const Bluetooth = await Service.import("bluetooth");

export const BluetoothQuickSettings = ({
  activeQuickSettings,
  key,
  onClose,
}) => {
  return QuickSettings({
    activeQuickSettings,
    key,
    onMoreSettingsClicked: () => {
      onClose();
      App.toggleWindow(WINDOW_NAME);
      openSettingsPage("bluetooth");
    },
    children: [Widget.Label({ label: "Bluetooth" })],
  });
};

const BluetoothButton = ({ onQuickSettings }) => {
  const Icon = () =>
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
      icon: Icon(),
      labelText: "Bluetooth",
    });

  return Widget.Button({
    className: "bar-bluetooth panel-button",
    on_clicked: () => {
      onQuickSettings("bluetooth");
    },
    child: BluetoothIndicator(),
  });
};

export default BluetoothButton;
