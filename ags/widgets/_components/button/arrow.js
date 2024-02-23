import { cn } from "../../../utils/string.js";

const ArrowButton = ({ className, children, ...rest }) =>
  Widget.CenterBox({
    className: cn("arrow-button", className),
    spacing: 16,
    startWidget: Widget.Box({ spacing: 16, children }),
    endWidget: Widget.Icon({
      className: "arrow",
      icon: "arrow-down",
    }),
    ...rest,
  });

export default ArrowButton;
