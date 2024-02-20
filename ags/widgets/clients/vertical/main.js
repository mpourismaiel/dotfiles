import { dispatch } from "../../_utils/hyprland.js";
import { lookupIcon, substitudeClientClass } from "../../_utils/icons.js";

const Gtk = imports.gi.Gtk;

const Hyprland = await Service.import("hyprland");

const ClientButton = (clients) => {
  const client = clients[0];
  const addresses = clients.map((client) => client.address);

  return Widget.Box({
    className: "client-container",
    child: Widget.Button({
      className: "client",
      onPrimaryClick: () => dispatch(`focuswindow address:${client.address}`),
      child: Widget.Box({
        children: [
          Widget.Box({
            vertical: true,
            className: "client-indicators",
            valign: Gtk.Align.CENTER,
            children: clients.map((client) =>
              Widget.Box({
                className: "client-indicator",
                setup: (self) => {
                  self.hook(Hyprland.active.client, (self) =>
                    self.toggleClassName(
                      "focused",
                      Hyprland.active.client.address === client.address
                    )
                  );
                },
              })
            ),
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
        self.hook(Hyprland.active.client, (self) =>
          self.toggleClassName(
            "focused",
            addresses.includes(Hyprland.active.client.address)
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
    children: Hyprland.bind("clients").transform((cl) => {
      const source = cl
        .sort(
          ({ workspace: { id: id1 } }, { workspace: { id: id2 } }) => id1 - id2
        )
        .filter((client) => client.pid >= 0)
        .reduce((acc, client) => {
          const workspaceId = client.workspace.id;
          const cls = client.class;
          if (!acc[workspaceId]) {
            acc[workspaceId] = {};
          }

          if (!acc[workspaceId][cls]) {
            acc[workspaceId][cls] = [];
          }

          acc[workspaceId][cls].push(client);
          return acc;
        }, {});

      const classesSortedByWorkspace = Object.keys(source)
        .sort((a, b) => a - b)
        .map((workspaceId) => {
          const clients = source[workspaceId];
          return Object.keys(clients)
            .sort((a, b) => a.localeCompare(b))
            .map((cls) =>
              clients[cls].sort(({ pid: apid }, { pid: bpid }) => apid - bpid)
            );
        })
        .flat();

      return classesSortedByWorkspace.map(ClientButton);
    }),
  });

export default Clients;
