import PopupWindow from "../_components/popup-window.js";

const { query } = await Service.import("applications");
const Gtk = imports.gi.Gtk;

export const WINDOW_NAME = "AppLauncher";

const AppItem = (app) =>
  Widget.Button({
    className: "launcher-app-item-container",
    hexpand: true,
    on_clicked: (self) => {
      self.attribute.run();
    },
    setup: (self) => {
      self.keybind("Enter", () => {
        App.closeWindow(WINDOW_NAME);
        app.launch();
      });
    },
    attribute: {
      app,
      run: () => {
        App.closeWindow(WINDOW_NAME);
        app.launch();
      },
    },
    child: Widget.Box({
      hpack: "start",
      className: "launcher-app-item",
      spacing: 8,
      children: [
        Widget.Icon({
          icon: app.icon_name || "",
          size: 42,
        }),
        Widget.Label({
          className: "title",
          label: app.name,
          xalign: 0,
          justification: "left",
          hexpand: true,
          maxWidthChars: 32,
          ellipsize: 3,
          wrap: true,
          truncate: "end",
        }),
      ],
    }),
  });

const List = () => {
  let applications = query("").map(AppItem);

  const AppList = Widget.Box({
    vertical: true,
    className: "launcher-list",
    spacing: 16,
  });

  const results = Variable();
  repopulate();

  function updateResults() {
    results.setValue(applications.filter((item) => item.visible));
  }

  function repopulate() {
    applications = query("").map(AppItem);
    AppList.children = applications;
    updateResults();
  }

  const entry = Widget.Entry({
    hexpand: true,
    className: "launcher-search",
    placeholder_text: "Search...",

    on_accept: () => {
      if (results.value[0]) {
        results.value[0].attribute.run();
        App.closeWindow(WINDOW_NAME);
      }
    },

    on_change: ({ text }) => {
      applications.forEach((item) => {
        item.visible = item.attribute.app.match(text ?? "");
      });
      updateResults();
    },
  });

  const Results = Widget.Box({
    vertical: true,
    className: "launcher-results",
    spacing: 16,
    children: [AppList],
  });

  return Widget.Box({
    vertical: true,
    spacing: 16,
    className: "launcher",
    children: [
      entry,
      Widget.Scrollable({
        className: "launcher-list",
        hscroll: "never",
        child: Results,
      }),
    ],
    setup: (self) =>
      self.hook(App, (_, windowName, visible) => {
        if (windowName !== WINDOW_NAME) return;

        // when the applauncher shows up
        if (visible) {
          repopulate();
          entry.text = "";
          entry.grab_focus();
        }
      }),
  });
};

export default () =>
  PopupWindow({
    name: WINDOW_NAME,
    className: "launcher-window",
    halign: Gtk.Align.START,
    valign: Gtk.Align.START,
    content: List(),
  });
