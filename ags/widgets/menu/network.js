import ArrowButton from "../_components/button/arrow.js";
import { WINDOW_NAME, openSettingsPage } from "../../windows/settings/main.js";
import QuickSettings from "./quick-settings.js";

const Network = await Service.import("network");

export const NetworkQuickSettings = ({ activeQuickSettings, key, onClose }) => {
  return QuickSettings({
    activeQuickSettings,
    key,
    onMoreSettingsClicked: () => {
      onClose();
      App.toggleWindow(WINDOW_NAME);
      openSettingsPage("network");
    },
    children: [Widget.Label({ label: "Network" })],
  });
};

const NetworkButton = ({ onQuickSettings }) => {
  const WifiIndicator = () =>
    ArrowButton({
      iconName: Network.wifi.bind("icon_name"),
      labelText: Network.wifi.bind("ssid").as((ssid) => ssid || "Unknown"),
    });

  const WiredIndicator = () =>
    ArrowButton({
      iconName: Network.wired.bind("icon_name"),
      labelText: Network.wifi.bind("ssid").as((ssid) => ssid || "Unknown"),
    });

  const NetworkIndicator = () =>
    Widget.Stack({
      children: {
        wifi: WifiIndicator(),
        wired: WiredIndicator(),
      },
      shown: Network.bind("primary").as((p) => p || "wifi"),
    });

  return Widget.Button({
    className: "bar-network panel-button",
    on_clicked: () => {
      onQuickSettings("network");
    },
    child: NetworkIndicator(),
  });
};

export default NetworkButton;
