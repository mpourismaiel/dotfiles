import { dependencies } from "../../utils/dots.js";
import { IconMap } from "../../utils/icons.js";

import Gtk from "gi://Gtk?version=3.0";

const DisplayItem = (variable) => (display) => {
  const resolutions = new Gtk.ComboBoxText();
  display.modes.forEach((mode) => {
    resolutions.append_text(
      `${mode.width}x${mode.height}@${parseInt(mode.refresh)}Hz`
    );
  });
  resolutions.set_active(display.modes.findIndex((m) => m.current));

  return Widget.Box({
    className: "display",
    vertical: true,
    children: [
      Widget.Box({
        children: [
          Widget.Icon({
            className: "icon",
            size: 16,
            icon: IconMap.brightness.screen,
          }),
          Widget.Label({
            className: "title",
            hpack: "start",
            label: display.description,
          }),
          Widget.Box({
            hexpand: true,
          }),
          Widget.Box({
            className: "actions",
            spacing: 8,
            children: [
              Widget.Switch({
                vpack: "is-enabled",
                setup: (self) => {
                  self.on("notify::active", () => {
                    // device.setConnection(self.active);
                  });
                  self.hook(variable, () => {
                    self.active = variable.value?.find(
                      (d) => d.name === display.name
                    )?.enabled;
                  });
                },
              }),
            ],
          }),
        ],
      }),
      Widget.Box({
        vertical: true,
        hexpand: true,
        spacing: 16,
        className: "more-actions",
        children: [
          Widget.Box({
            className: "resolutions",
            hexpand: true,
            children: [
              Widget.Label({
                className: "label",
                label: "Resolutions",
              }),
              Widget.Box({ hexpand: true }),
              Widget.Box({
                hpack: "end",
                child: resolutions,
              }),
            ],
          }),
          Widget.Box({
            className: "scale",
            hexpand: true,
            children: [
              Widget.Label({
                className: "label",
                label: "Scale",
              }),
              Widget.Box({ hexpand: true }),
              Widget.Box({
                hpack: "end",
                child: Widget.Entry({
                  className: "scale",
                  on_accept: () => {},
                  on_change: ({ text }) => {},
                  setup: (self) => {
                    self.hook(variable, () => {
                      self.text =
                        variable.value?.find((d) => d.name === display.name)
                          ?.scale + "" || "1.0";
                    });
                  },
                }),
              }),
            ],
          }),
        ],
      }),
    ],
  });
};

const DisplaySettings = () => {
  if (!dependencies("wlr-randr")) {
    return Widget.Box({
      className: "content",
      child: Widget.Box({
        className: "alert error",
        children: [
          Widget.Label({
            label: "Please install wlr-randr!",
          }),
        ],
      }),
    });
  }

  const Displays = Variable([], {
    poll: [5000, "wlr-randr --json", (out) => JSON.parse(out)],
  });

  const Item = DisplayItem(Displays);

  return Widget.Box({
    className: "content",
    child: Widget.Scrollable({
      hscroll: "never",
      className: "full-page-scroll",
      child: Widget.Box({
        vertical: true,
        setup: (self) => {
          self.hook(Displays, () => {
            try {
              self.children = Displays.value.map(Item);
            } catch (err) {
              console.error(err);
              self.children = Widget.Box({
                className: "alert error",
                vertical: true,
                children: [
                  Widget.Label({ label: "Something went wrong!" }),
                  Widget.Label({
                    hexpand: true,
                    use_markup: true,
                    xalign: 0,
                    justification: "left",
                    label: err,
                    max_width_chars: 40,
                    wrap: true,
                  }),
                ],
              });
            }
          });
        },
      }),
    }),
  });
};

export const DisplayPageHeader = ({ windowName }) => ({
  centerWidget: Widget.Label({ label: "Display" }),
});

const DisplayPage = () => {
  return Widget.Box({
    vertical: true,
    spacing: 16,
    className: "display-settings",
    children: [DisplaySettings()],
  });
};

export default DisplayPage;
