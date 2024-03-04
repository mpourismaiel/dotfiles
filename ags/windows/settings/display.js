import { dependencies } from "../../utils/dots.js";
import { IconMap } from "../../utils/icons.js";

const DisplayItem = (variable) => (display) => {
  return Widget.Box({
    className: "display",
    children: [
      Widget.Icon({
        className: "icon",
        size: 16,
        icon: IconMap.brightness.screen,
      }),
      Widget.Box({
        vertical: true,
        className: "details",
        children: [
          Widget.Label({
            className: "title",
            label: display.name,
          }),
          Widget.Label({
            className: "description",
            label: display.description,
          }),
        ],
      }),
      Widget.Box({
        hexpand: true,
      }),
      Widget.Box({
        className: "actions",
        spacing: 8,
        children: [
          Widget.Button({
            className: "toggle-button is-active",
            on_clicked: () => {},
            child: Widget.Label({
              setup: (self) => {
                self.hook(
                  variable,
                  () =>
                    (self.label = variable.value.find(
                      (d) => d.name === display.name
                    ).enabled
                      ? "Deactivate"
                      : "Activate")
                );
              },
            }),
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
    poll: [5000, "wlr-randr --json"],
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
              self.children = JSON.parse(Displays.value).map(Item);
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
