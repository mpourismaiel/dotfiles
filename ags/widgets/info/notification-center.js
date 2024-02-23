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

const NotificationScroll = () =>
  Widget.Scrollable({
    className: "notifications-scroll",
    hscroll: "never",
    child: Widget.Box({
      vertical: true,
      children: Notifications.bind("notifications").as((notifications) =>
        notifications.length === 0
          ? EmptyMessage()
          : notifications.reverse().map(Notification)
      ),
    }),
  });

const NotificationCenter = () =>
  Widget.Box({
    vertical: true,
    className: "notification-center",
    children: [
      Widget.CenterBox({
        className: "notifications-header",
        centerWidget: Widget.Label({
          className: "notifications-label",
          label: "Notifications",
        }),
        endWidget: Widget.Box({
          hpack: "end",
          child: Widget.Button({
            className: "clear-all-icon-button",
            onPrimaryClick: () => Notifications.clear(),
            child: Widget.Icon({
              className: "clear-all-icon",
              size: 24,
              icon: "edit-clear-all",
            }),
          }),
        }),
      }),
      NotificationScroll(),
    ],
  });

export default NotificationCenter();
