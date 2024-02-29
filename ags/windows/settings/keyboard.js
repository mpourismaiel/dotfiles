import { IconMap } from "../../utils/icons.js";

const KeyboardLayoutSettings = () => {
  return Widget.Box({
    className: "content",
    child: Widget.Scrollable({
      hscroll: "never",
      className: "full-page-scroll",
      child: Widget.Box({
        vertical: true,
        children: Widget.Label("keyboard settings"),
      }),
    }),
  });
};

export const KeyboardPageHeader = ({ windowName }) => ({
  centerWidget: Widget.Label({ label: "Keyboard Settings" }),
});

const KeyboardPage = () => {
  return Widget.Box({
    vertical: true,
    spacing: 16,
    className: "keyboard-settings",
    children: [KeyboardLayoutSettings()],
  });
};

export default KeyboardPage;
