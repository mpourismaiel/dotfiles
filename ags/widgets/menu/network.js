const Network = await Service.import("network");

const Container = ({ children }) => Widget.Box({ spacing: 16, children });

const NetworkButton = () => {
  const WifiIndicator = () =>
    Container({
      children: [
        Widget.Icon({
          icon: Network.wifi.bind("icon_name"),
        }),
        Widget.Label({
          className: "title",
          label: Network.wifi.bind("ssid").as((ssid) => ssid || "Unknown"),
        }),
      ],
    });

  const WiredIndicator = () =>
    Container({
      children: [
        Widget.Icon({
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
    child: NetworkIndicator(),
  });
};

export default NetworkButton;
