import PopupWindow from "../misc/popup-window.js";

const { query } = await Service.import("applications");
export const WINDOW_NAME = "applauncher";

const AppItem = (app) =>
  Widget.Button({
    on_clicked: () => {
      App.closeWindow(WINDOW_NAME);
      app.launch();
    },
    attribute: { app },
    child: Widget.Box({
      hpack: "center",
      vertical: true,
      spacing: 8,
      children: [
        Widget.Icon({
          icon: app.icon_name || "",
          size: 42,
        }),
        Widget.Label({
          class_name: "title",
          label: app.name,
          xalign: 0,
          vpack: "center",
          truncate: "end",
        }),
      ],
    }),
  });

const AppList = (
  windowName,
  { width = 500, height = 500, spacing = 12 } = {}
) => {
  // list of application buttons
  let applications = query("").map(AppItem);

  // container holding the buttons
  const list = Widget.Box({
    vertical: true,
    children: applications,
    spacing,
  });

  // repopulate the box, so the most frequent apps are on top of the list
  function repopulate() {
    applications = query("").map(AppItem);
    list.children = applications;
  }

  // search entry
  const entry = Widget.Entry({
    hexpand: true,
    css: `margin-bottom: ${spacing}px;`,

    // to launch the first item on Enter
    on_accept: () => {
      if (applications[0]) {
        App.toggleWindow(windowName);
        applications[0].attribute.app.launch();
      }
    },

    // filter out the list
    on_change: ({ text }) =>
      applications.forEach((item) => {
        item.visible = item.attribute.app.match(text ?? "");
      }),
  });

  return Widget.Box({
    vertical: true,
    css: `margin: ${spacing * 2}px;`,
    children: [
      entry,

      // wrap the list in a scrollable
      Widget.Scrollable({
        hscroll: "never",
        css: `
                    min-width: ${width}px;
                    min-height: ${height}px;
                `,
        child: list,
      }),
    ],
    setup: (self) =>
      self.hook(App, (_, windowName, visible) => {
        if (windowName !== windowName) return;

        // when the applauncher shows up
        if (visible) {
          repopulate();
          entry.text = "";
          entry.grab_focus();
        }
      }),
  });
};

export default (monitor) =>
  PopupWindow({
    name: WINDOW_NAME,
    layout: "center",
    // expand: true,
    content: AppList(WINDOW_NAME),
  });
