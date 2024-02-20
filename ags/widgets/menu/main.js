import PanelButton from "../bar/panel-button.js";
import PopupWindow from "../misc/popup-window.js";
import Profile from "./profile.js";
import NetworkButton from "./network.js";
import { Row } from "../misc/layout.js";
import BluetoothButton from "./bluetooth.js";
import Volume from "./volume.js";
import SysTray from "./systray.js";

const Gtk = imports.gi.Gtk;

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
    valign: Gtk.Align.END,
    halign: Gtk.Align.START,
    animation: "slide_up",
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
                  children: [
                    NetworkButton({
                      onClose: () => App.closeWindow(WINDOW_NAME),
                    }),
                    BluetoothButton({
                      onClose: () => App.closeWindow(WINDOW_NAME),
                    }),
                  ],
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
