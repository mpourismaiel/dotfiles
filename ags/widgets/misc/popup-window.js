import { cn } from "../_utils/string.js";

const Gtk = imports.gi.Gtk;

const Revealer = ({ child, transition, name }) =>
  Widget.Revealer({
    transition,
    child,
    setup: (self) => {
      self.hook(
        App,
        (_, windowName, visible) => {
          if (windowName !== name) return;

          self.reveal_child = visible;
        },
        "window_toggled"
      );
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
    popup: true,
    visible: false,
    ...windowProps,
    child: Backdrop({
      name,
      child: Revealer({
        name,
        transition: animation,
        child: Widget.Box({
          className: cn("popup-window", title ? "with-title" : "without-title"),
          valign: valign ? valign : Gtk.Align.CENTER,
          halign: halign ? halign : Gtk.Align.CENTER,
          child: Widget.Box({
            vertical: true,
            children: [
              title
                ? Widget.Label({
                    className: "popup-title",
                    label: title,
                  })
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
