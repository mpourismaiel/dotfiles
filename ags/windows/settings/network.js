import { dependencies } from "../../utils/dots.js";
import { IconMap } from "../../utils/icons.js";
import SettingsHeaderButton from "../../widgets/_components/button/settings-header.js";

const Network = await Service.import("network");

const NetworkDetails = Variable({
  wifi: null,
  enterPassword: false,
  password: "",
});

const connectWifiCommand = (bssid, password) =>
  `nmcli device wifi connect "${bssid}" ${
    password ? `password "${password}"` : ""
  }`;

const WifiItem = (wifi) => {
  const isConnecting = Variable(false);

  const tryConnect = () => {
    if (!dependencies("nmcli")) return;

    isConnecting = true;
    Utils.execAsync(connectWifiCommand(wifi.bssid))
      .catch((err) => {
        print(`Error: ${err}`);
        NetworkDetails.setValue({ wifi: wifi, enterPassword: true });
      })
      .finally(() => {
        isConnecting = false;
      });
  };

  return Widget.Box({
    className: "wifi-item",
    children: [
      Widget.Icon({ size: 16, className: "icon", icon: wifi.iconName }),
      Widget.Label({ className: "label", label: wifi.ssid || "" }),
      Widget.Box({ hexpand: true }),
      Widget.Stack({
        hpack: "end",
        children: {
          connect: Widget.Button({
            className: "connect-button",
            on_clicked: tryConnect,
            child: Widget.Label({
              label: isConnecting
                .bind()
                .as((v) => (v ? "Connecting..." : "Connect")),
              hexpand: true,
              hpack: "end",
            }),
          }),
          connected: Widget.Label({
            className: "connected",
            label: "Connected",
            hexpand: true,
            hpack: "end",
          }),
        },
        shown: Network.wifi
          .bind("ssid")
          .as((ssid) => ((ssid || "") === wifi.ssid ? "connected" : "connect")),
      }),
    ],
  });
};

const NetworkWifiSelector = () => {
  return Widget.Stack({
    className: "content",
    children: {
      list: Widget.Scrollable({
        hscroll: "never",
        className: "full-page-scroll",
        child: Widget.Box({
          vertical: true,
          setup: (self) => {
            self.hook(Network, (self) => {
              self.children = Network.wifi?.access_points
                .sort(({ active: aActive }, { active: bActive }) => {
                  if (aActive === bActive) return 0;
                  if (aActive) return -1;
                  return 1;
                })
                .map((device, i, arr) => {
                  const items = [];
                  items.push(WifiItem(device));

                  if (i < arr.length - 1) {
                    items.push(Widget.Separator());
                  }

                  return items;
                })
                .flat();
            });
          },
        }),
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
    setup: (self) =>
      self.hook(
        NetworkDetails,
        (v) => (self.shown = v.enterPassword ? "password" : "list")
      ),
  });
};

const RescanWifiButton = () =>
  SettingsHeaderButton({
    className: "network-scan-button",
    on_clicked: () => Network.wifi?.scan(),
    icon: "view-refresh-symbolic",
  });

const ConnectionEditorButton = ({ windowName }) =>
  SettingsHeaderButton({
    className: "network-scan-button",
    on_clicked: () => {
      if (!dependencies("nm-connection-editor")) return;

      Utils.execAsync("nm-connection-editor");
      App.closeWindow(windowName);
    },
    icon: IconMap.ui.settings,
  });

export const NetworkPageHeader = ({ windowName }) => ({
  centerWidget: Widget.Label({ label: "Network" }),
  endWidget: [ConnectionEditorButton({ windowName }), RescanWifiButton()],
});

const NetworkPage = () => {
  Network.wifi?.scan();
  NetworkDetails.setValue({
    wifi: null,
    enterPassword: false,
    password: "",
  });

  return Widget.Box({
    vertical: true,
    spacing: 16,
    className: "network-settings",
    children: [NetworkWifiSelector()],
  });
};

export default NetworkPage;
