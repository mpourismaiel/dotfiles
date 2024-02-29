import options from "../../lib/options.js";
import Notification from "../_components/notification.js";

const Notifications = await Service.import("notifications");

function Animated(id) {
  const n = Notifications.getNotification(id);
  if (!n) return;

  const transition = options.getOption("transition");
  const widget = Notification({
    notification: n,
    notificationsWidth: options.getOption("notifications_width"),
  });

  const inner = Widget.Revealer({
    transition: "slide_down",
    transition_duration: transition,
    child: widget,
  });

  const outer = Widget.Revealer({
    transition: "slide_down",
    transition_duration: transition,
    child: inner,
  });

  const box = Widget.Box({
    hpack: "end",
    child: outer,
  });

  Utils.idle(() => {
    outer.reveal_child = true;
    Utils.timeout(transition, () => {
      inner.reveal_child = true;
    });
  });

  return Object.assign(box, {
    dismiss() {
      inner.reveal_child = false;
      Utils.timeout(transition, () => {
        outer.reveal_child = false;
        Utils.timeout(transition, () => {
          if (!box) return;
          box.destroy();
        });
      });
    },
  });
}

function PopupList() {
  const map = new Map();
  const box = Widget.Box({
    hpack: "end",
    vertical: true,
    css: `min-width: ${options.getOption("notifications_width")}px`,
  });

  function remove(_, id) {
    map.get(id)?.dismiss();
    map.delete(id);
  }

  return box
    .hook(
      Notifications,
      (_, id) => {
        if (id !== undefined) {
          if (map.has(id)) remove(null, id);

          if (Notifications.dnd) return;

          const w = Animated(id);
          map.set(id, w);
          box.children = [w, ...box.children];
        }
      },
      "notified"
    )
    .hook(Notifications, remove, "dismissed")
    .hook(Notifications, remove, "closed");
}

export default (monitor) => {
  options.registerKey(
    "notifications_width",
    450,
    (value) => typeof value === "number" && value > 0
  );
  options.registerKey(
    "notifications_position",
    ["bottom", "right"],
    (value) =>
      value.length <= 2 &&
      value.every((v) => ["top", "bottom", "left", "right"].includes(v))
  );

  return Widget.Window({
    monitor,
    name: `notifications${monitor}`,
    anchor: options.getOptionVariable("notifications_position").bind(),
    class_name: "notifications",
    layer: "overlay",
    child: Widget.Box({
      css: "padding: 2px;",
      child: PopupList(),
    }),
  });
};
