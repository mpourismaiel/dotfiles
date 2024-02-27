import options from "../../lib/options.js";
import ToggleButton from "../_components/button/toggle.js";

const ThemeToggleButton = () => {
  return ToggleButton({
    state: options.getOptionVariable("theme-mode"),
    className: "theme-mode-toggle",
    on_clicked: () => {
      options.updateOption(
        "theme-mode",
        options.getOption("theme-mode") === "dark" ? "light" : "dark"
      );
    },
    child: Widget.Box({
      spacing: 16,
      children: [
        Widget.Icon({
          size: 24,
          icon: "applications-graphics-symbolic",
        }),
        Widget.Label({
          className: "title",
          label: options
            .getOptionVariable("theme-mode")
            .bind()
            .as((value) => (value === "dark" ? "Dark" : "Light")),
        }),
      ],
    }),
  });
};

export default ThemeToggleButton;
