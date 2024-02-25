import options from "../lib/options.js";
import { IconMap } from "../utils/icons.js";
import PopupWindow from "../widgets/_components/popup-window.js";
import Progress from "../widgets/_components/progress.js";

import GLib from "gi://GLib";
const Audio = await Service.import("audio");
const Hyprland = await Service.import("hyprland");

const VolumeMap = [
  [30, IconMap.audio.volume.low],
  [70, IconMap.audio.volume.medium],
  [100, IconMap.audio.volume.high],
];

const icon = Variable("volume");
const valueType = Variable("progress");
const value = Variable(1);

const OSD = (monitor) => {
  options.registerKey("osd-timeout", 2000);
  const progress = Progress({
    width: 120,
    height: 8,
    vertical: false,
    visible: valueType.bind().as((v) => v === "progress"),
  });

  const revealer = Widget.Revealer({
    transition: "slide_up",
    transition_duration: options.getOption("transition"),
    child: Widget.Box({
      vertical: true,
      spacing: 30,
      className: "content",
      children: [
        Widget.Icon({
          className: "icon",
          size: 48,
          icon: icon.bind(),
        }),
        Widget.Label({
          className: "value-string",
          label: value.bind().as((v) => v + ""),
          visible: valueType.bind().as((v) => v !== "progress"),
        }),
        progress,
      ],
    }),
  });

  let timerId = null;
  const show = (t, vt, v) => {
    if (timerId !== null) {
      GLib.source_remove(timerId);
    }

    icon.setValue(t);
    value.setValue(v);
    valueType.setValue(vt);
    if (vt === "progress") {
      progress.setValue(v);
    }

    revealer.reveal_child = true;

    timerId = Utils.timeout(options.getOption("osd-timeout"), () => {
      timerId = null;
      revealer.reveal_child = false;
    });
  };

  revealer
    .hook(
      Audio.speaker,
      () => {
        show(
          Audio.speaker.volume > 0
            ? VolumeMap.find(([v]) => Audio.speaker.volume * 100 <= v)?.[1] ||
                IconMap.audio.volume.overamplified
            : IconMap.audio.volume.muted,
          "progress",
          Audio.speaker.volume
        );
      },
      "notify::volume"
    )
    .hook(
      Hyprland,
      (_, keyboardName, language) => {
        if (!keyboardName && !language) return;
        show(IconMap.brightness.keyboard, "text", language);
      },
      "keyboard-layout"
    );

  return Widget.Window({
    name: `osd-${monitor}`,
    className: "osd",
    anchor: ["bottom"],
    click_through: true,
    keymode: "none",
    layer: "overlay",
    setup: (self) => {
      self.keybind("Escape", () => App.closeWindow(name));
    },
    child: Widget.Box({
      className: "osd-box",
      child: revealer,
    }),
  });
};

export default OSD;
