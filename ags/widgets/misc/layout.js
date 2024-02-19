import { cn } from "../_utils/string.js";

export const Row = ({ className, ...rest }) =>
  Widget.Box({
    className: cn("row", className),
    ...rest,
  });
