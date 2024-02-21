const Hyprland = await Service.import("hyprland");

import PanelButton from "../../bar/panel-button.js";
import { WINDOW_NAME as LauncherWindowName } from "../../launcher/main.js";
import { range } from "../../_utils/array.js";
import { dispatch } from "../../_utils/hyprland.js";

const WorkspaceButton = ({ id }) =>
  Widget.Box({
    class_name: "workspace-indicator",
    vpack: "center",
    hpack: "center",
    class_name: Hyprland.active.workspace
      .bind("id")
      .transform((i) => `${i === id ? "focused workspace" : "workspace"}`),
    setup: (self) => (self.id = `workspace-${id}`),
  });

const Container = () =>
  Widget.Box({
    vertical: true,
    class_name: "workspaces",
    hexpand: true,
    children: range(6, 0).map((id) => WorkspaceButton({ id: id + 1 })),
  }).hook(
    Hyprland,
    (box) => {
      box.children.forEach((button, i) => {
        const ws_before = i > 0 ? Hyprland.getWorkspace(i) : null;
        button.toggleClassName("occupied-left", ws_before?.windows > 0);
        const ws = Hyprland.getWorkspace(i + 1);
        button.toggleClassName("occupied", ws?.windows > 0);
        const ws_after = i < 6 ? Hyprland.getWorkspace(i + 2) : null;
        button.toggleClassName("occupied-right", ws_after?.windows > 0);
      });
    },
    "notify::workspaces"
  );

const Workspaces = () =>
  Widget.EventBox({
    onScrollUp: () => dispatch("workspace -1"),
    onScrollDown: () => dispatch("workspace +1"),
    child: Widget.Box({
      vertical: true,
      className: "workspaces-container",
      children: [
        PanelButton({
          vpack: "start",
          onPrimaryClick: () => App.toggleWindow(LauncherWindowName),
          child: Container(),
        }),
        Widget.Box({
          class_name: "padding",
          hexpand: true,
          vexpand: true,
        }),
      ],
    }),
  });

export default () => Workspaces();
