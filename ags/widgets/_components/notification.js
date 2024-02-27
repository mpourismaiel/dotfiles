import options from "../../lib/options.js";
import { IconMap } from "../../utils/icons.js";

import GLib from "gi://GLib";

const time = (time, format = "%H:%M") =>
  GLib.DateTime.new_from_unix_local(time).format(format);

const NotificationIcon = ({ app_entry, app_icon, image }) => {
  if (image) {
    return Widget.Box({
      vpack: "start",
      hexpand: false,
      className: "icon",
      child: Widget.Box({
        className: "img",
        css: `
        background-image: url("${image}");
        background-size: cover;
        background-repeat: no-repeat;
        background-position: center;
      `,
      }),
    });
  }

  let icon = IconMap.fallback.notification;
  if (Utils.lookUpIcon(app_icon)) icon = app_icon;

  if (Utils.lookUpIcon(app_entry || "")) icon = app_entry || "";

  return Widget.Box({
    vpack: "start",
    hexpand: false,
    className: "icon",
    child: Widget.Icon({
      icon,
      size: 32,
      hpack: "center",
      hexpand: true,
      vpack: "center",
      vexpand: true,
    }),
  });
};

export default ({ notification, notificationsWidth }) => {
  const Content = Widget.Box({
    className: "content",
    css: `min-width: ${notificationsWidth}px; max-width: ${notificationsWidth}px;`,
    children: [
      NotificationIcon(notification),
      Widget.Box({
        hexpand: true,
        vertical: true,
        spacing: 10,
        children: [
          Widget.Box({
            children: [
              Widget.Label({
                className: "title",
                xalign: 0,
                justification: "left",
                hexpand: true,
                max_width_chars: 24,
                truncate: "end",
                wrap: true,
                label: notification.summary.trim(),
                use_markup: true,
              }),
              Widget.Box({ hexpand: true }),
              Widget.Label({
                className: "time",
                hpack: "end",
                vpack: "center",
                label: time(notification.time),
              }),
              Widget.Button({
                className: "close-button",
                hpack: "end",
                vpack: "start",
                child: Widget.Icon("window-close-symbolic"),
                on_clicked: notification.close,
              }),
            ],
          }),
          Widget.Label({
            className: "description",
            hexpand: true,
            use_markup: true,
            xalign: 0,
            justification: "left",
            label: notification.body.trim(),
            max_width_chars: 40,
            wrap: true,
          }),
        ],
      }),
    ],
  });

  const ActionsBox =
    notification.actions.length > 0
      ? Widget.Revealer({
          transition: "slide_down",
          child: Widget.EventBox({
            child: Widget.Box({
              className: "actions horizontal",
              spacing: 10,
              children: notification.actions.map((action) =>
                Widget.Button({
                  className: "action-button",
                  on_clicked: () => notification.invoke(action.id),
                  hexpand: true,
                  child: Widget.Label(action.label),
                })
              ),
            }),
          }),
        })
      : null;

  const eventbox = Widget.EventBox({
    vexpand: false,
    on_primary_click: notification.dismiss,
    on_hover() {
      if (ActionsBox) ActionsBox.reveal_child = true;
    },
    on_hover_lost() {
      if (ActionsBox) ActionsBox.reveal_child = true;

      notification.dismiss();
    },
    child: Widget.Box({
      vertical: true,
      spacing: 20,
      children: ActionsBox ? [Content, ActionsBox] : [Content],
    }),
  });

  return Widget.Box({
    className: `notification ${notification.urgency}`,
    child: eventbox,
  });
};
