import PopupWindow from "../widgets/_components/popup-window.js";
import powermenu from "../service/powermenu.js";
import { IconMap } from "../utils/icons.js";

const SysButton = (action, label) =>
  Widget.Button({
    onPrimaryClick: () => powermenu.action(action),
    child: Widget.Box({
      vertical: true,
      class_name: "system-button",
      spacing: 10,
      children: [
        Widget.Icon({ size: 32, icon: IconMap.powermenu[action] }),
        Widget.Label({
          label,
        }),
      ],
    }),
  });

export const Verification = () =>
  PopupWindow({
    name: "verification",
    className: "verification",
    title: "Are you sure?",
    content: Widget.Box({
      vertical: true,
      spacing: 20,
      children: [
        Widget.Box({
          hexpand: true,
          children: [
            Widget.Label({
              label: "Are you sure you want to perform this action?",
            }),
          ],
        }),
        Widget.Box({
          homogeneous: true,
          hexpand: true,
          spacing: 10,
          children: [
            Widget.Button({
              child: Widget.Label("No"),
              on_clicked: () => App.toggleWindow("verification"),
              setup: (self) =>
                self.hook(App, (_, name, visible) => {
                  if (name === "verification" && visible) self.grab_focus();
                }),
            }),
            Widget.Button({
              child: Widget.Label("Yes"),
              on_clicked: () => Utils.exec(powermenu.cmd),
            }),
          ],
        }),
      ],
    }),
  });

export const PowerMenu = () =>
  PopupWindow({
    name: "powermenu",
    className: "power-menu",
    content: Widget.Box({
      homogeneous: true,
      spacing: 16,
      children: [
        SysButton("shutdown", "Shutdown"),
        SysButton("logout", "Log Out"),
        SysButton("reboot", "Reboot"),
        SysButton("sleep", "Sleep"),
      ],
    }),
  });
