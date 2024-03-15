import { IconMap } from "../../utils/icons.js";
import RegularWindow from "../../widgets/_components/regular-window.js";
import AudioPage, { AudioPageHeader } from "./audio.js";
import BluetoothPage, { BluetoothPageHeader } from "./bluetooth.js";
import DisplayPage, { DisplayPageHeader } from "./display.js";
import NetworkPage, { NetworkPageHeader } from "./network.js";

export const WINDOW_NAME = "settings";

const sections = [
  { type: "category", title: "General" },
  {
    type: "page",
    key: "network",
    title: "Network",
    icon: "network-wireless-connected-symbolic",
    header: NetworkPageHeader,
    page: NetworkPage,
  },
  {
    type: "page",
    key: "bluetooth",
    title: "Bluetooth",
    icon: "bluetooth-active-symbolic",
    header: BluetoothPageHeader,
    page: BluetoothPage,
  },
  {
    type: "page",
    key: "audio",
    title: "Audio",
    icon: "audio-headphones-symbolic",
    header: AudioPageHeader,
    page: AudioPage,
  },
  { type: "category", title: "Graphics" },
  {
    type: "page",
    key: "display",
    title: "Display",
    icon: IconMap.brightness.screen,
    header: DisplayPageHeader,
    page: DisplayPage,
  },
];

const activePage = Variable(null);
const initialTab = Variable(null);

export const openSettingsPage = (sectionKey, tabKey) => {
  initialTab.setValue(tabKey);
  activePage.setValue(sectionKey);
};

const Section = (section) => {
  if (section.type === "page") {
    return Widget.Button({
      on_clicked: () => activePage.setValue(section.key),
      className: "toggle-button section",
      setup: (self) => {
        self.hook(activePage, () => {
          self.toggleClassName("active", activePage.value === section.key);
        });
      },
      child: Widget.Box({
        hpack: "start",
        spacing: 16,
        children: [
          Widget.Icon({
            icon: section.icon,
            hexpand: true,
            hpack: "end",
          }),
          Widget.Label({
            label: section.title,
          }),
        ],
      }),
    });
  }

  if (section.type === "category") {
    return Widget.Label({
      className: "category",
      hpack: "start",
      label: section.title,
    });
  }

  return null;
};

const Sections = () => {
  return Widget.Box({
    vertical: true,
    className: "sections",
    spacing: 10,
    children: sections.map(Section),
  });
};

let activePageInstance = null;
let activeHeaderInstance = null;

const ActivePage = () => {
  return Widget.Box({
    className: "active-page",
    vertical: true,
    spacing: 10,
    hexpand: true,
    setup: (self) =>
      self.hook(activePage, () => {
        if (activeHeaderInstance) {
          self.remove(activeHeaderInstance);
          activeHeaderInstance.destroy();
        }

        if (activePageInstance) {
          self.remove(activePageInstance);
          activePageInstance.destroy();
        }

        activeHeaderInstance = null;
        activePageInstance = null;

        const { header, page } =
          sections.find((section) => section.key === activePage.value) || {};

        if (header) {
          const transformedHeader = header({ windowName: WINDOW_NAME });
          transformedHeader.endWidget = Widget.Box({
            spacing: 8,
            hpack: "end",
            children: transformedHeader.endWidget,
          });

          activeHeaderInstance = Widget.CenterBox({
            className: "settings-page-header",
            startWidget: Widget.Box({
              hpack: "start",
              child: Widget.Button({
                className: "back-button",
                on_clicked: () => activePage.setValue(null),
                child: Widget.Icon({ icon: IconMap.ui.arrow.left }),
              }),
            }),
            ...transformedHeader,
          });
          self.add(activeHeaderInstance);
        }

        if (page) {
          activePageInstance = page(initialTab.value);
        } else {
          activePageInstance = Widget.Label({
            label: "page",
          });
        }

        self.add(activePageInstance);
        self.show_all();
      }),
  });
};

const TitleBar = () => {
  return Widget.Box({
    className: "titlebar",
    hexpand: true,
    children: [
      Widget.Icon({ icon: IconMap.ui.settings, size: 16 }),
      Widget.Label({
        label: "Settings",
        className: "title",
      }),
      Widget.Box({ hexpand: true }),
      Widget.Box({
        hpack: "end",
        children: [
          Widget.Button({
            className: "close-button",
            on_clicked: () => App.closeWindow(WINDOW_NAME),
            child: Widget.Icon({ icon: IconMap.ui.close }),
          }),
        ],
      }),
    ],
  });
};

const SettingsWindow = () => {
  return RegularWindow({
    name: WINDOW_NAME,
    title: "AGS Settings",
    className: "settings-window",
    setup(win) {
      win.on("delete-event", () => {
        win.hide();
        return true;
      });
      win.set_default_size(800, 600);
    },
    child: Widget.Box({
      vertical: true,
      children: [
        TitleBar(),
        Widget.Box({
          vexpand: true,
          hexpand: true,
          children: [Sections(), Widget.Separator(), ActivePage()],
        }),
      ],
    }),
  });
};

export default SettingsWindow;
