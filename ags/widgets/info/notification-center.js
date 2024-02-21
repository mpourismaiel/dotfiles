import Notification from "../misc/notification.js";

const Notifications = await Service.import("notifications");

const NotificationScroll = Widget.Scrollable({
  className: "notifications-scroll",
  hscroll: "never",
  child: Widget.Box({
    vertical: true,
    children: Notifications.bind("notifications").as((notifications) =>
      notifications.reverse().map(Notification)
    ),
  }),
});

const NotificationCenter = Widget.Box({
  vertical: true,
  className: "notification-center",
  children: [
    Widget.CenterBox({
      className: "notifications-header",
      startWidget: Widget.Label({
        className: "notifications-label",
        label: "Notifications",
      }),
      endWidget: Widget.Button({
        className: "clear-all-icon-button",
        onPrimaryClick: () => Notifications.clear(),
        child: Widget.Icon({
          className: "clear-all-icon",
          size: 24,
          icon: "edit-clear-all",
        }),
      }),
    }),
    NotificationScroll,
  ],
});

export default NotificationCenter;
