import { cn } from "../../../utils/string.js";

const ArrowButton = ({
  className,
  iconName,
  icon,
  labelText,
  label,
  children,
  ...rest
}) =>
  Widget.CenterBox({
    className: cn("arrow-button", className),
    spacing: 16,
    startWidget: Widget.Box({
      spacing: 16,
      children: children || [
        icon || Widget.Icon({ size: 24, icon: iconName }),
        label ||
          Widget.Label({
            className: "title",
            hpack: "start",
            label: labelText,
          }),
      ],
    }),
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
