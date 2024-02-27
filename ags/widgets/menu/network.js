import ArrowButton from "../_components/button/arrow.js";
import { WINDOW_NAME, openSettingsPage } from "../../windows/settings/main.js";

const Network = await Service.import("network");

const NetworkButton = ({ onClose }) => {
  const WifiIndicator = () =>
    ArrowButton({
      children: [
        Widget.Icon({
          size: 24,
          icon: Network.wifi.bind("icon_name"),
        }),
        Widget.Label({
          className: "title",
          label: Network.wifi.bind("ssid").as((ssid) => ssid || "Unknown"),
        }),
      ],
    });

  const WiredIndicator = () =>
    ArrowButton({
      children: [
        Widget.Icon({
          size: 24,
          icon: Network.wired.bind("icon_name"),
        }),
        Widget.Label({
          className: "title",
          label: Network.wifi.bind("ssid").as((ssid) => ssid || "Unknown"),
        }),
      ],
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
      onClose();
      App.toggleWindow(WINDOW_NAME);
      openSettingsPage("network");
    },
    child: NetworkIndicator(),
  });
};

export default NetworkButton;
