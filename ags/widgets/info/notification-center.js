import { IconMap } from "../../utils/icons.js";
import Notification from "../_components/notification.js";

const Notifications = await Service.import("notifications");

const EmptyMessage = () =>
  Widget.Box({
    className: "empty-message",
    child: Widget.Label({
      label: "No notifications",
      className: "empty-message-label",
    }),
  });

const Placeholder = () =>
  Widget.Box({
    className: "placeholder",
    vertical: true,
    vpack: "center",
    hpack: "center",
    vexpand: true,
    hexpand: true,
    visible: Notifications.bind("notifications").as((n) => n.length === 0),
    spacing: 10,
    children: [
      Widget.Icon({ size: 32, icon: IconMap.notifications.silent }),
      Widget.Label("Your inbox is empty"),
    ],
  });

const NotificationScroll = () =>
  Widget.Scrollable({
    className: "notifications-scroll",
    hscroll: "never",
    child: Widget.Box({
      vertical: true,
      children: [
        Widget.Box({
          vertical: true,
          visible: Notifications.bind("notifications").as((n) => n.length > 0),
          children: Notifications.bind("notifications").as((notifications) =>
            notifications.length === 0
              ? EmptyMessage()
              : notifications
                  .reverse()
                  .map((n) =>
                    Notification({ notification: n, notificationsWidth: 360 })
                  )
          ),
        }),
        Placeholder(),
      ],
    }),
  });

const NotificationCenter = () =>
  Widget.Box({
    vertical: true,
    className: "notification-center",
    children: [
      Widget.CenterBox({
        className: "notifications-header",
        startWidget: Widget.Label({
          hpack: "start",
          className: "notifications-label",
          label: "Notifications",
        }),
        endWidget: Widget.Box({
          hpack: "end",
          spacing: 8,
          children: [
            Widget.Button({
              className: "notifications-dnd-button",
              on_clicked: () => (Notifications.dnd = !Notifications.dnd),
              child: Widget.Icon({
                className: "notifications-dnd-icon",
                size: 24,
                icon: Notifications.bind("dnd").as((v) =>
                  v ? IconMap.notifications.silent : IconMap.notifications.noisy
                ),
              }),
            }),
            Widget.Button({
              className: "clear-all-icon-button",
              on_clicked: () => Notifications.clear(),
              child: Widget.Icon({
                className: "clear-all-icon",
                size: 24,
                icon: IconMap.ui.close,
              }),
            }),
          ],
        }),
      }),
      NotificationScroll(),
    ],
  });

export default NotificationCenter;
