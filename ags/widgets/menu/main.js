import PanelButton from "../bar/panel-button.js";
import PopupWindow from "../misc/popup-window.js";
import Profile from "./profile.js";
import NetworkButton from "./network.js";
import { Row } from "../misc/layout.js";
import BluetoothButton from "./bluetooth.js";
import Volume from "./volume.js";
import SysTray from "./systray.js";

export const WINDOW_NAME = "ControlCenter";

const MenuToggleButton = () =>
  PanelButton({
    className: "menu-toggle-button",
    onPrimaryClick: () => App.toggleWindow(WINDOW_NAME),
    vpack: "center",
    hpack: "center",
    child: Widget.Box({
      className: "menu-toggle-button-icon",
      vpack: "center",
      hpack: "center",
    }),
  });

export const Menu = () =>
  PopupWindow({
    name: WINDOW_NAME,
    anchor: ["bottom", "left"],
    layout: "bottom left",
    margins: [0, 0, 16, 16],
    animation: "slide_left",
    className: "control-center",
    content: Widget.Box({
      className: "menu",
      spacing: 16,
      children: [
        Widget.Box({
          className: "menu-bar",
          vertical: true,
          spacing: 16,
          children: [
            Profile(),
            Widget.Box({
              className: "card",
              vpack: "start",
              vertical: true,
              spacing: 16,
              children: [
                Row({
                  spacing: 10,
                  children: [NetworkButton(), BluetoothButton()],
                }),
                Row({
                  child: Volume({ type: "speaker" }),
                }),
                Row({
                  child: Volume({ type: "microphone" }),
                }),
              ],
            }),
            SysTray(),
          ],
        }),
      ],
    }),
  });

export default MenuToggleButton;
