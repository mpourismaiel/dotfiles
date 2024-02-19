import { dispatch } from "../../_utils/hyprland.js";
import { lookupIcon, substitudeClientClass } from "../../_utils/icons.js";

const Gtk = imports.gi.Gtk;

const Hyprland = await Service.import("hyprland");

const ClientButton = (client) => {
  return Widget.Box({
    className: "client-container",
    child: Widget.Button({
      className: "client",
      onPrimaryClick: () => dispatch(`focuswindow address:${client.address}`),
      child: Widget.Box({
        vpack: "center",
        children: [
          Widget.Box({
            vpack: "start",
            className: "client-indicator",
          }),
          Widget.Icon({
            size: 24,
            className: "client-icon",
            icon: lookupIcon(substitudeClientClass(client.class)),
            setup: (self) => {
              self.tooltip_text = client.title;
            },
          }),
        ],
      }),
      setup: (self) => {
        self.hook(Hyprland.active.client, () =>
          self.toggleClassName(
            "focused",
            Hyprland.active.client.address === client.address
          )
        );
      },
    }),
  });
};

const Clients = () =>
  Widget.Box({
    vertical: true,
    class_name: "clients",
    children: Hyprland.bind("clients").transform((cl) =>
      cl
        .sort(
          ({ workspace: { id: id1 } }, { workspace: { id: id2 } }) => id1 - id2
        )
        .map(ClientButton)
    ),
  });

export default Clients;
