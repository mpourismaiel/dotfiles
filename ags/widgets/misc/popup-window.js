const Padding = (windowName) =>
  Widget.EventBox({
    class_name: "padding",
    hexpand: true,
    vexpand: true,
    onPrimaryClick: () => App.toggleWindow(windowName),
  });

const PopupRevealer = (windowName, transition, child) =>
  Widget.Box({
    css: "padding: 1px;",
    child: Widget.Revealer({
      transition,
      child,
      setup: (self) => {
        self.hook(
          App,
          (revealer, name, visible) => {
            if (name === windowName) revealer.reveal_child = visible;
          },
          "window-toggled"
        );
      },
    }),
  });

const layouts = {
  center: (windowName, child, animation, expand) =>
    Widget.CenterBox({
      class_name: "popup-window-center",
      // css: expand ? "min-width: 5000px; min-height: 3000px;" : "",
      start_widget: Padding(windowName),
      center_widget: Widget.CenterBox({
        vertical: true,
        start_widget: Padding(windowName),
        center_widget: child,
        end_widget: Padding(windowName),
      }),
      end_widget: Padding(windowName),
    }),
  none: (windowName, child, animation) =>
    Widget.CenterBox({
      start_widget: Padding(windowName),
      center_widget: Widget.Box({
        vertical: true,
        children: [
          PopupRevealer(windowName, animation || "none", child),
          Padding(windowName),
        ],
      }),
      end_widget: Padding(windowName),
    }),
  top: (windowName, child, animation) =>
    Widget.CenterBox({
      start_widget: Padding(windowName),
      center_widget: Widget.Box({
        vertical: true,
        children: [
          PopupRevealer(windowName, animation || "slide_down", child),
          Padding(windowName),
        ],
      }),
      end_widget: Padding(windowName),
    }),
  "top right": (windowName, child, animation) =>
    Widget.Box({
      children: [
        Padding(windowName),
        Widget.Box({
          hexpand: false,
          vertical: true,
          children: [
            PopupRevealer(windowName, animation || "slide_down", child),
            Padding(windowName),
          ],
        }),
      ],
    }),
  "top left": (windowName, child, animation) =>
    Widget.Box({
      children: [
        Padding(windowName),
        Widget.Box({
          hexpand: false,
          vertical: true,
          children: [
            PopupRevealer(windowName, animation || "slide_down", child),
            Padding(windowName),
          ],
        }),
      ],
    }),
  "bottom right": (windowName, child, animation) =>
    Widget.Box({
      children: [
        Padding(windowName),
        Widget.Box({
          hexpand: false,
          vertical: true,
          children: [
            Padding(windowName),
            PopupRevealer(windowName, animation || "slide_right", child),
          ],
        }),
      ],
    }),
  "bottom left": (windowName, child, animation) =>
    Widget.Box({
      children: [
        Padding(windowName),
        Widget.Box({
          hexpand: false,
          vertical: true,
          children: [
            PopupRevealer(windowName, animation || "slide_left", child),
            Padding(windowName),
          ],
        }),
      ],
    }),
};

const PopupWindow = ({
  layout = "center",
  expand = true,
  name,
  animation,
  content,
  ...rest
}) =>
  Widget.Window({
    name,
    child: layouts[layout](name, content, animation, expand),
    popup: true,
    layer: "overlay",
    visible: false,
    keymode: "on-demand",
    ...rest,
  });

export default PopupWindow;
