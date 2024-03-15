import { cn } from "../../../utils/string.js";

const SettingsHeaderButton = ({
  className,
  icon,
  on_clicked,
  loading = Variable(),
  setup = () => {},
}) => {
  return Widget.Button({
    className: cn("header-button", className),
    on_clicked,
    setup,
    child: Widget.Icon({
      size: 16,
      className: loading.bind().as((v) => cn(v ? "spinner" : "")),
      icon,
    }),
  });
};

export default SettingsHeaderButton;
