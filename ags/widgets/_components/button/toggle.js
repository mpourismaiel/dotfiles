import { cn } from "../../../utils/string.js";

const ToggleButton = ({
  state = Variable(false),
  className,
  setup,
  ...rest
} = {}) => {
  return Widget.Button({
    className: cn("toggle-button", className),
    setup: (self) => {
      self.hook(state, (self) => {
        self.toggleClassName("active", state.value === "light");
      });
      if (setup) setup(self);
    },
    ...rest,
  });
};

export default ToggleButton;
