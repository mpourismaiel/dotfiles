import ArrowButton from "../misc/button/arrow.js";
import PopupWindow from "../misc/popup-window.js";

const Network = await Service.import("network");

export const WINDOW_NAME = "NetworkSettings";

const connectWifiCommand = (bssid, password) =>
  `nmcli device wifi connect ${bssid} ${
    password ? `password "${password}"` : ""
  }`;

const NetworkButton = ({ onClose }) => {
  const WifiIndicator = () =>
    ArrowButton({
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
    ArrowButton({
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
    onPrimaryClick: () => {
      onClose();
      App.toggleWindow(WINDOW_NAME);
    },
    child: NetworkIndicator(),
  });
};

const NetworkDetails = Variable({
  wifi: null,
  enterPassword: false,
  password: "",
});

const renderAccessPoints = (self) => {
  self.children = Network.wifi?.access_points.map((ap) =>
    Widget.Button({
      onPrimaryClick: () => {
        // check for errors, if there are any ask for password
        Utils.execAsync(connectWifiCommand(ap.bssid))
          .then((out) => print(out))
          .catch((err) => {
            print(`Error: ${err}`);
            NetworkDetails.setValue({ wifi: ap, enterPassword: true });
          });
      },
      child: Widget.CenterBox({
        start_widget: Widget.Box({
          spacing: 16,
          children: [Widget.Icon(ap.iconName), Widget.Label(ap.ssid || "")],
        }),
        end_widget: ap.active
          ? Widget.Icon({
              icon: "network",
              hexpand: true,
              hpack: "end",
            })
          : null,
      }),
    })
  );
};

const NetworkWifiSelector = Widget.Stack({
  children: {
    list: Widget.Box({
      vertical: true,
      spacing: 16,
      setup: (self) => {
        self.hook(
          App,
          (_, windowName, visible) => {
            if (windowName !== WINDOW_NAME) return;
            Network.wifi.scan();
          },
          "window_toggled"
        );

        self.hook(Network, renderAccessPoints);
      },
    }),
    password: Widget.Box({
      vertical: true,
      className: "wifi-password-window",
      spacing: 16,
      children: [
        Widget.Label({
          className: "wifi-password-label",
          label: `Enter password for "${NetworkDetails.value.wifi?.bssid}"`,
        }),
        Widget.Entry({
          hexpand: true,
          on_accept: () =>
            Utils.execAsync(
              connectWifiCommand(
                NetworkDetails.value.wifi.bssid,
                NetworkDetails.value.password
              )
            )
              .then((out) => print(out))
              .catch((err) => {
                print(`Error: ${err}`);
                NetworkDetails.setValue({ wifi: ap, enterPassword: true });
              }),
          on_change: ({ text }) => (NetworkDetails.value.password = text),
        }),
      ],
    }),
  },
  shown: NetworkDetails.bind().as((v) =>
    v.enterPassword ? "password" : "list"
  ),
  setup: (self) => {
    self.hook(App, (_, windowName, visible) => {
      if (windowName !== WINDOW_NAME || !visible) return;
      NetworkDetails.setValue({
        wifi: null,
        enterPassword: false,
        password: "",
      });
    });
  },
});

export const NetworkWindow = () =>
  PopupWindow({
    name: WINDOW_NAME,
    title: "Network",
    animation: "slide_up",
    content: NetworkWifiSelector,
  });

export default NetworkButton;
