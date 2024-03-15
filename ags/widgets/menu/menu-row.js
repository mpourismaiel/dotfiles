import { Row } from "../_components/layout.js";

const MenuRow = ({ children, settings }) => {
  return Widget.Box({
    vertical: true,
    children: [
      Row({
        spacing: 10,
        children: children,
      }),
      ...settings,
    ],
  });
};

export default MenuRow;
