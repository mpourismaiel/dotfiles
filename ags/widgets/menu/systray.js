const SystemTray = await Service.import("systemtray");
const { Gravity } = imports.gi.Gdk;

const revealerDuration = 200;

const SysTrayItem = (item) =>
  Widget.Button({
    className: "bar-systray-item",
    child: Widget.Icon({
      hpack: "center",
      icon: item.icon,
      setup: (self) => self.hook(item, (self) => (self.icon = item.icon)),
    }),
    setup: (self) =>
      self.hook(item, (self) => (self.tooltipMarkup = item["tooltip-markup"])),
    onClicked: (btn) =>
      item.menu.popup_at_widget(btn, Gravity.SOUTH, Gravity.NORTH, null),
    onSecondaryClick: (btn) =>
      item.menu.popup_at_widget(btn, Gravity.SOUTH, Gravity.NORTH, null),
  });

const SysTray = (props = {}) => {
  return Widget.Box({
    className: "card",
    child: Widget.Box({
      vertical: false,
      className: "systray",
      spacing: 4,
      attribute: {
        items: new Map(),
        onAdded: (box, id) => {
          const item = SystemTray.getItem(id);
          if (!item) return;

          item.menu.className = "menu";
          if (box.attribute.items.has(id) || !item) return;

          const widget = SysTrayItem(item);
          box.attribute.items.set(id, widget);
          box.add(widget);
          box.show_all();
        },
        onRemoved: (box, id) => {
          if (!box.attribute.items.has(id)) return;

          box.attribute.items.get(id).destroy();
          box.attribute.items.delete(id);
        },
      },
      setup: (self) =>
        self
          .hook(
            SystemTray,
            (box, id) => box.attribute.onAdded(box, id),
            "added"
          )
          .hook(
            SystemTray,
            (box, id) => box.attribute.onRemoved(box, id),
            "removed"
          ),
    }),
    setup: (self) => {
      self.hook(SystemTray, (self) => {
        self.visible = SystemTray.items.length > 0;
      });
    },
  });
};

export default SysTray;
