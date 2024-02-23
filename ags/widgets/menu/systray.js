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
      className: "systray",
      spacing: 4,
      attribute: {
        items: new Map(),
        onAdded: (self, id) => {
          const item = SystemTray.getItem(id);
          if (!item) return;

          item.menu.className = "menu";
          if (self.attribute.items.has(id) || !item) return;

          const widget = SysTrayItem(item);
          self.attribute.items.set(id, widget);
          self.add(widget);
          self.show_all();
        },
        onRemoved: (self, id) => {
          if (!self.attribute.items.has(id)) return;

          self.attribute.items.get(id).destroy();
          self.attribute.items.delete(id);
        },
      },
      setup: (self) =>
        self
          .hook(
            SystemTray,
            (self, id) => self.attribute.onAdded(self, id),
            "added"
          )
          .hook(
            SystemTray,
            (self, id) => self.attribute.onRemoved(self, id),
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
