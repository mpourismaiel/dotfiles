import { cn } from "../../utils/string.js";
import options from "../../lib/options.js";

const Gtk = imports.gi.Gtk;

const Revealer = ({ child, transition, name }) =>
  Widget.Revealer({
    transition,
    transition_duration: options.getOptionVariable("transition").bind(),
    child,
    setup: (self) => {
      self.hook(App, (_, windowName, visible) => {
        if (windowName !== name) return;
        self.reveal_child = visible;
      });
    },
  });

const Backdrop = ({ name, child }) =>
  Widget.EventBox({
    className: "popup-background",
    valign: Gtk.Align.FILL,
    halign: Gtk.Align.FILL,
    onPrimaryClick: () => {
      App.toggleWindow(name);
    },
    child,
  });

const PopupWindow = ({
  layout = "center",
  name,
  title,
  className,
  content,
  anchor,
  animation = "slide_up",
  valign,
  halign,
  windowProps = {},
  ...rest
}) =>
  Widget.Window({
    name,
    anchor: ["right", "bottom", "left", "top"],
    className: cn("popup", className),
    layer: "overlay",
    keymode: "exclusive",
    exclusivity: "ignore",
    visible: false,
    setup: (self) => {
      self.keybind("Escape", () => App.closeWindow(name));
    },
    ...windowProps,
    child: Backdrop({
      name,
      child: Revealer({
        name,
        transition: "slide_up",
        child: Widget.Box({
          className: cn("popup-window", title ? "with-title" : "without-title"),
          valign: valign ? valign : Gtk.Align.CENTER,
          halign: halign ? halign : Gtk.Align.CENTER,
          child: Widget.Box({
            vertical: true,
            children: [
              title
                ? typeof title === "string"
                  ? Widget.Label({
                      className: "popup-title",
                      label: title,
                    })
                  : title
                : null,
              Widget.Box({
                className: "popup-content",
                children: Array.isArray(content) ? content : [content],
                ...rest,
              }),
            ],
          }),
        }),
      }),
    }),
  });

export default PopupWindow;
