import PopupWindow from "../_components/popup-window.js";
import NotificationCenter from "./notification-center.js";

const Gtk = imports.gi.Gtk;

export const WINDOW_NAME = "InfoPanel";

export const InfoPanel = () =>
  PopupWindow({
    name: WINDOW_NAME,
    valign: Gtk.Align.END,
    halign: Gtk.Align.START,
    animation: "slide_left",
    className: "info-panel-window",
    content: Widget.Box({
      className: "info-panel-container",
      spacing: 16,
      children: [
        Widget.Box({
          className: "info-notifications",
          vertical: true,
          child: NotificationCenter,
        }),
      ],
    }),
  });

export default InfoPanel;
