import { cn } from "../../../utils/string.js";

const ArrowButton = ({ className, children, ...rest }) =>
  Widget.CenterBox({
    className: cn("arrow-button", className),
    spacing: 16,
    startWidget: Widget.Box({ spacing: 16, children }),
    endWidget: Widget.Box({
      hpack: "end",
      child: Widget.Icon({
        size: 16,
        className: "arrow",
        icon: "arrow-right",
      }),
    }),
    ...rest,
  });

export default ArrowButton;
