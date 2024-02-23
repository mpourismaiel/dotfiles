import { cn } from "../../utils/string.js";

export const Row = ({ className, ...rest }) =>
  Widget.Box({
    className: cn("row", className),
    ...rest,
  });
