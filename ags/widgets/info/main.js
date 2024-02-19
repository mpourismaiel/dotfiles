import PopupWindow from "../misc/popup-window.js";

export const WINDOW_NAME = "InfoPanel";

export const InfoPanel = () =>
  PopupWindow({
    name: WINDOW_NAME,
    anchor: ["bottom", "left"],
    layout: "bottom left",
    margins: [0, 0, 16, 16],
    animation: "slide_left",
    className: "info-panel-window",
    content: Widget.Box({
      className: "info-panel-container",
      spacing: 16,
      children: [
        Widget.Box({
          className: "info-notifications",
          vertical: true,
          child: Widget.Label({ label: "Hello World!" }),
        }),
        Widget.Box({
          className: "info-calendar",
          vertical: true,
          child: Widget.Label({ label: "Hello World!" }),
        }),
      ],
    }),
  });

export default InfoPanel;
