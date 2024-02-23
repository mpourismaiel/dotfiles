import RegularWindow from "../../widgets/_components/regular-window.js";

const Network = await Service.import("network");

export const WINDOW_NAME = "NetworkSettings";

const connectWifiCommand = (bssid, password) =>
  `nmcli device wifi connect "${bssid}" ${
    password ? `password "${password}"` : ""
  }`;

const renderAccessPoints = (self) => {
  self.children = Network.wifi?.access_points
    .sort(({ active: aActive }, { active: bActive }) => {
      if (aActive === bActive) return 0;
      if (aActive) return -1;
      return 1;
    })
    .map((ap) =>
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
          startWidget: Widget.Box({
            spacing: 16,
            children: [Widget.Icon(ap.iconName), Widget.Label(ap.ssid || "")],
          }),
          endWidget: ap.active
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

const NetworkDetails = Variable({
  wifi: null,
  enterPassword: false,
  password: "",
});

const NetworkWifiSelector = () => {
  return Widget.Stack({
    className: "content",
    children: {
      list: Widget.Box({
        vertical: true,
        spacing: 16,
        setup: (self) => {
          self.hook(
            App,
            (_, windowName, visible) => {
              if (windowName !== WINDOW_NAME) return;
              Network.wifi?.scan();
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
};

const RescanWifiButton = () =>
  Widget.Box({
    child: Widget.Button({
      onPrimaryClick: () => Network.wifi?.scan(),
      child: Widget.Icon({ size: 16, icon: "view-refresh-symbolic" }),
    }),
  });

export const NetworkWindow = () =>
  RegularWindow({
    name: WINDOW_NAME,
    title: "Network Settings",
    className: "network-settings-window",
    setup(win) {
      win.on("delete-event", () => {
        win.hide();
        return true;
      });
      win.set_default_size(500, 600);
    },
    child: Widget.Box({
      vertical: true,
      spacing: 16,
      children: [
        Widget.CenterBox({
          className: "popup-title",
          css: "padding-left:10px;padding-right:10px",
          startWidget: RescanWifiButton(),
          centerWidget: Widget.Label({ label: "Network" }),
        }),
        NetworkWifiSelector(),
      ],
    }),
  });
