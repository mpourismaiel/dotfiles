import { cn } from "../_utils/string.js";

const Notifications = await Service.import("notifications");

const NotificationIcon = ({ app_entry, app_icon, image }) => {
  if (image) {
    return Widget.Box({
      css: `
        min-width: 36px;
        min-height: 36px;
        background-image: url("${image}");
        background-size: contain;
        background-repeat: no-repeat;
        background-position: center;
      `,
    });
  }

  let icon = "dialog-information-symbolic";
  if (Utils.lookUpIcon(app_icon)) icon = app_icon;

  if (app_entry && Utils.lookUpIcon(app_entry)) icon = app_entry;

  return Widget.Icon({ icon, size: 36 });
};

export const Notification = (n) => {
  const icon = Widget.Box({
    vpack: "start",
    className: "notification-icon",
    child: NotificationIcon(n),
  });

  const title = Widget.Label({
    className: "notification-title",
    xalign: 0,
    justification: "left",
    hexpand: true,
    maxWidthChars: 24,
    ellipsize: 3,
    wrap: true,
    truncate: "end",
    label: n.summary,
    useMarkup: n.summary.startsWith("<"),
  });

  const body = Widget.Label({
    className: cn(
      "notification-body",
      n.summary ? "" : "header",
      n.actions.length ? "" : "footer"
    ),
    xalign: 0,
    justification: "left",
    hexpand: true,
    maxWidthChars: 32,
    ellipsize: 3,
    wrap: true,
    truncate: "end",
    label: n.body,
    useMarkup: n.body.startsWith("<"),
  });

  const actions = Widget.Box({
    className: "notification-actions",
    children: n.actions.map(({ id, label }) =>
      Widget.Button({
        className: "action-button",
        onPrimaryClick: () => n.invoke(id),
        hexpand: true,
        child: Widget.Label(label),
      })
    ),
  });

  const image = Widget.Box({
    className: "notification-image",
    css: `
      background-image: url("${n.image}");
      background-size: contain;
      background-repeat: no-repeat;
      background-position: center;
    `,
  });

  return Widget.Revealer({
    transition: "slide_left",
    setup: (self) => {
      Utils.timeout(10, () => (self.reveal_child = true));
    },
    child: Widget.EventBox({
      on_primary_click: () => n.dismiss(),
      child: Widget.Box({
        class_name: `notification ${n.urgency}`,
        vertical: true,
        children: [
          n.summary
            ? Widget.Box({
                className: "notification-header header",
                children: [icon, title],
              })
            : null,
          n.image ? image : null,
          body,
          n.actions.length ? actions : null,
        ],
      }),
    }),
  });
};

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
