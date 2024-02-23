import Notification from "../_components/notification.js";

const Notifications = await Service.import("notifications");

export const NotificationPopup = () => {
  const map = new Map();

  const onNotified = (self, id) => {
    if (!id || Notifications.dnd) return;
    map.delete(id);
    map.set(id, true);

    map.set(id, Notification(Notifications.getNotification(id)));
    self.children = Array.from(map.values()).reverse();
  };

  const onDismissed = (force) => (self, id) => {
    if (!id || !map.has(id)) return;

    map.get(id).reveal_child = false;
    Utils.timeout(250, () => {
      map.get(id)?.destroy();
      map.delete(id);
    });
  };

  return Widget.Window({
    name: "notifications",
    anchor: ["bottom", "right"],
    child: Widget.Box({
      class_name: "notifications",
      vertical: true,
      setup: (self) => {
        self.hook(Notifications, onNotified, "notified");
        self.hook(Notifications, onDismissed(), "dismissed");
        self.hook(Notifications, onDismissed(true), "closed");
      },
    }),
  });
};
