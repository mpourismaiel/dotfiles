import { IconMap } from "../../utils/icons.js";
import options from "../../lib/options.js";
import { createRowsOfLength } from "../../utils/array.js";
import PopupWindow from "../_components/popup-window.js";

const Applications = await Service.import("applications");
const Gtk = imports.gi.Gtk;

export const WINDOW_NAME = "AppLauncher";

const defaultAppMenuDetails = { isPinned: false, desktop: "" };
const appMenuDetails = Variable(defaultAppMenuDetails);

const toggleAppPin = (appMenuDetails) => {
  if (appMenuDetails.value.isPinned) {
    options.updateOption(
      "launcher_pinned_apps",
      options
        .getOption("launcher_pinned_apps")
        .filter((app) => app !== appMenuDetails.value.desktop)
    );
  } else {
    options.updateOption("launcher_pinned_apps", [
      ...options.getOption("launcher_pinned_apps"),
      appMenuDetails.value.desktop,
    ]);
  }
};

const AppMenu = Widget.Menu({
  children: [
    Widget.MenuItem({
      child: Widget.Label({
        label: appMenuDetails
          .bind()
          .as((v) => (v.isPinned ? "Remove from pinned" : "Add to pinned")),
      }),
      on_activate: () => {
        toggleAppPin(appMenuDetails);
        appMenuDetails.setValue(defaultAppMenuDetails);
      },
    }),
  ],
});

const AppItem = (app) =>
  Widget.Button({
    className: "launcher-app-item-container",
    hexpand: true,
    on_secondary_click: (_, e) => {
      const details = { desktop: app.desktop };
      details.isPinned = options
        .getOption("launcher_pinned_apps")
        .includes(app.desktop);
      appMenuDetails.setValue(details);
      AppMenu.popup_at_pointer(e);
    },
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

const PinnedAppItem = (app) =>
  Widget.Button({
    className: "launcher-pinned-app-item-container",
    on_secondary_click: (_, e) => {
      const details = { desktop: app.desktop };
      details.isPinned = options
        .getOption("launcher_pinned_apps")
        .includes(app.desktop);
      appMenuDetails.setValue(details);
      AppMenu.popup_at_pointer(e);
    },
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
      hpack: "center",
      className: "launcher-pinned-app-item",
      spacing: 8,
      vertical: true,
      children: [
        Widget.Icon({
          hpack: "center",
          icon: app.icon_name || "",
          size: 42,
        }),
        Widget.Label({
          className: "title",
          label: app.name,
          xalign: 0,
          justification: "center",
          hexpand: true,
          maxWidthChars: 12,
          ellipsize: 3,
          wrap: true,
          truncate: "end",
        }),
      ],
    }),
  });

const List = () => {
  const query = Variable("");
  const results = Variable();
  const showPinned = Utils.derive([query], (query) => !query);
  let applications = Applications.query("").map(AppItem);

  const Entry = Widget.Entry({
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
      query.value = text || "";
    },
  });

  const PinnedAppsRow = ({ children }) =>
    Widget.Box({
      className: "pinned-apps-row",
      homogeneous: true,
      spacing: 16,
      hpack: "start",
      vpack: "start",
      children,
    });

  const PinnedApps = Widget.Box({
    className: "pinned-apps",
    vpack: "start",
    spacing: 16,
    vertical: true,
    children: options
      .getOptionVariable("launcher_pinned_apps")
      .bind()
      .as((apps) =>
        createRowsOfLength(
          Applications.list
            .filter((app) => apps.includes(app.desktop))
            .map(PinnedAppItem),
          5
        ).map((children) => PinnedAppsRow({ children }))
      ),
  });

  const AppList = Widget.Box({
    vertical: true,
    className: "launcher-list",
    spacing: 16,
  });

  const Results = Widget.Box({
    vertical: true,
    className: "launcher-results",
    spacing: 16,
    children: [AppList],
  });

  function updateResults() {
    results.setValue(applications.filter((item) => item.visible));
  }

  function repopulate() {
    applications = Applications.query("").map(AppItem);

    console.log(Applications.list);
    AppList.children = applications;
    updateResults();
  }

  repopulate();

  query.connect("changed", ({ value }) => {
    applications.forEach((item) => {
      item.visible = item.attribute.app.match(value ?? "");
    });
    updateResults();
  });

  return Widget.Box({
    vertical: true,
    spacing: 16,
    className: "launcher",
    children: [
      Entry,
      Widget.Stack({
        transition: "slide_left_right",
        children: {
          list: Widget.Scrollable({
            className: "launcher-list",
            hscroll: "never",
            child: Results,
          }),
          pinned: PinnedApps,
        },
        shown: showPinned
          .bind()
          .as((showPinned) => (showPinned ? "pinned" : "list")),
      }),
    ],
    setup: (self) =>
      self.hook(App, (_, windowName, visible) => {
        if (windowName !== WINDOW_NAME || !visible) return;

        repopulate();
        Entry.text = "";
        Entry.grab_focus();
      }),
  });
};

export default () => {
  options.registerKey(
    "launcher_pinned_apps",
    ["org.gnome.font-viewer.desktop", "org.kde.drkonqi.coredump.gui.desktop"],
    (value) => Array.isArray(value) && value.every((v) => typeof v === "string")
  );

  return PopupWindow({
    name: WINDOW_NAME,
    className: "launcher-window",
    halign: Gtk.Align.START,
    valign: Gtk.Align.START,
    content: List(),
  });
};
