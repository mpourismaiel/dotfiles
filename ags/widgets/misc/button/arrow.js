import { cn } from "../../_utils/string.js";

const ArrowButton = ({ className, children, ...rest }) =>
  Widget.CenterBox({
    className: cn("arrow-button", className),
    spacing: 16,
    start_widget: Widget.Box({ spacing: 16, children }),
    end_widget: Widget.Icon({
      className: "arrow",
      icon: "arrow-down",
    }),
    ...rest,
  });

export default ArrowButton;
