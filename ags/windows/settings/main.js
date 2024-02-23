import RegularWindow from "../../widgets/_components/regular-window.js";
import AudioPage, { AudioPageHeader } from "./audio.js";
import BluetoothPage, { BluetoothPageHeader } from "./bluetooth.js";
import NetworkPage, { NetworkPageHeader } from "./network.js";

export const WINDOW_NAME = "NetworkSettings";

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
];

const activePage = Variable(null);

export const openSettingsPage = (sectionKey) => {
  activePage.setValue(sectionKey);
};

const Section = (section) => {
  if (section.type === "page") {
    return Widget.Button({
      onPrimaryClick: () => activePage.setValue(section.key),
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
          activeHeaderInstance = Widget.CenterBox({
            className: "settings-page-header",
            ...header(),
          });
          self.add(activeHeaderInstance);
        }

        if (page) {
          activePageInstance = page();
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
      children: [Sections(), Widget.Separator(), ActivePage()],
    }),
  });
};

export default SettingsWindow;
