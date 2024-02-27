import PanelButton from "../bar/panel-button.js";
import PopupWindow from "../_components/popup-window.js";
import Profile from "./profile.js";
import NetworkButton from "./network.js";
import { Row } from "../_components/layout.js";
import BluetoothButton from "./bluetooth.js";
import Volume from "./volume.js";
import SysTray from "./systray.js";
import BatteryButton from "./battery.js";
import ThemeToggleButton from "./theme-toggle.js";

const Gtk = imports.gi.Gtk;

export const WINDOW_NAME = "ControlCenter";

const MenuToggleButton = () =>
  PanelButton({
    className: "menu-toggle-button",
    on_clicked: () => App.toggleWindow(WINDOW_NAME),
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
            Profile({
              onClose: () => App.closeWindow(WINDOW_NAME),
            }),
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
                  spacing: 10,
                  children: [
                    BatteryButton({
                      onClose: () => App.closeWindow(WINDOW_NAME),
                    }),
                    ThemeToggleButton(),
                  ],
                }),
                Row({
                  child: Volume({
                    type: "speaker",
                    onClose: () => App.closeWindow(WINDOW_NAME),
                  }),
                }),
                Row({
                  child: Volume({
                    type: "microphone",
                    onClose: () => App.closeWindow(WINDOW_NAME),
                  }),
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
