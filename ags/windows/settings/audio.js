import { dependencies } from "../../utils/dots.js";
import { IconMap, icon } from "../../utils/icons.js";
import SettingsHeaderButton from "../../widgets/_components/button/settings-header.js";
import Tabs from "../../widgets/_components/tabs.js";

const Audio = await Service.import("audio");

const activeTab = Variable("speaker");
export const setActiveTab = (tab) => {
  switch (tab) {
    case "microphone":
      activeTab.setValue("microphone");
      break;

    case "speaker":
    default:
      activeTab.setValue("speaker");
      break;
  }
};

const SinkDevice = (device, streams, mainStream, setDefault) => {
  return Widget.Box({
    className: "speaker audio-device",
    vertical: true,
    spacing: 16,
    children: [
      Widget.CenterBox({
        spacing: 16,
        startWidget: Widget.Box({
          hpack: "start",
          className: "details",
          vertical: true,
          hexpand: true,
          spacing: 8,
          children: [
            Widget.Box({
              hpack: "start",
              children: [
                Widget.Icon({
                  className: "icon",
                  icon: icon(device.icon_name || "", IconMap.fallback.audio),
                  tooltip_text: device.icon_name || "",
                  size: 16,
                }),
                Widget.Label({
                  hpack: "start",
                  className: "title",
                  label: device.description,
                  xalign: 0,
                  justification: "left",
                  hexpand: true,
                  maxWidthChars: 26,
                  ellipsize: 3,
                  wrap: true,
                  truncate: "end",
                }),
              ],
            }),
            Widget.Label({
              hpack: "start",
              className: "descriptor",
              label: device.name,
              xalign: 0,
              justification: "left",
              hexpand: true,
              maxWidthChars: 50,
              ellipsize: 3,
              wrap: true,
              truncate: "end",
            }),
          ],
        }),
        endWidget: Widget.Box({
          vpack: "start",
          hpack: "end",
          spacing: 16,
          children: [
            Widget.Box({
              child: Widget.Button({
                className: mainStream
                  .bind("stream")
                  .as(
                    (s) =>
                      `default-button toggle-button ${
                        s === device.stream ? "active" : ""
                      }`
                  ),
                on_clicked: () => setDefault(device),
                child: Widget.Icon({
                  size: 16,
                  icon: mainStream
                    .bind("stream")
                    .as((s) =>
                      s === device.stream ? IconMap.ui.tick : IconMap.ui.close
                    ),
                }),
              }),
            }),
          ],
        }),
      }),
      Widget.Slider({
        class_name: "volume-slider",
        hexpand: true,
        draw_value: false,
        on_change: ({ value }) => (device.volume = value),
        setup: (self) => {
          self.hook(
            Audio,
            (self) => {
              self.value = streams.find((s) => s === device)?.volume;
            },
            `speaker-changed`
          );
        },
      }),
    ],
  });
};

const MixerItem = (stream) => {
  return Widget.Box({
    className: "speaker audio-device",
    vertical: true,
    spacing: 16,
    children: [
      Widget.CenterBox({
        spacing: 16,
        startWidget: Widget.Box({
          hpack: "start",
          className: "details",
          vertical: true,
          hexpand: true,
          spacing: 8,
          children: [
            Widget.Box({
              hpack: "start",
              children: [
                Widget.Icon({
                  className: "icon",
                  icon: icon(stream.name || "", IconMap.fallback.audio),
                  tooltip_text: stream.name || "",
                  size: 16,
                }),
                Widget.Label({
                  hpack: "start",
                  className: "title",
                  label: stream.name,
                  xalign: 0,
                  justification: "left",
                  hexpand: true,
                  maxWidthChars: 26,
                  ellipsize: 3,
                  wrap: true,
                  truncate: "end",
                }),
              ],
            }),
            Widget.Label({
              hpack: "start",
              className: "descriptor",
              label: stream.description,
              xalign: 0,
              justification: "left",
              hexpand: true,
              maxWidthChars: 50,
              ellipsize: 3,
              wrap: true,
              truncate: "end",
            }),
          ],
        }),
      }),
      Widget.Slider({
        class_name: "volume-slider",
        hexpand: true,
        draw_value: false,
        on_change: ({ value }) => (stream.volume = value),
        volume: stream.bind("volume"),
      }),
    ],
  });
};

const SpeakerSinks = () => {
  return Widget.Scrollable({
    hscroll: "never",
    className: "full-page-scroll",
    child: Widget.Box({
      vertical: true,
      spacing: 16,
      children: Audio.bind("speakers").as((speakers) =>
        speakers
          .map((speaker, i, arr) => {
            const result = [];
            result.push(
              SinkDevice(
                speaker,
                Audio.speakers,
                Audio.speaker,
                (s) => (Audio.speaker = s)
              )
            );
            if (i !== arr.length - 1) {
              result.push(Widget.Separator());
            }
            return result;
          })
          .flat()
      ),
    }),
  });
};

const MicrophoneSinks = () => {
  return Widget.Scrollable({
    hscroll: "never",
    className: "full-page-scroll",
    child: Widget.Box({
      vertical: true,
      spacing: 16,
      children: Audio.bind("microphones").as((microphones) =>
        microphones
          .map((microphone, i, arr) => {
            const result = [];
            result.push(
              SinkDevice(
                microphone,
                Audio.microphones,
                Audio.microphone,
                (s) => (Audio.microphone = s)
              )
            );
            if (i !== arr.length - 1) {
              result.push(Widget.Separator());
            }
            return result;
          })
          .flat()
      ),
    }),
  });
};

const AppMixer = () => {
  return Widget.Scrollable({
    hscroll: "never",
    className: "full-page-scroll",
    child: Widget.Box({
      vertical: true,
      spacing: 16,
      children: Audio.bind("apps").as((apps) => apps.map(MixerItem)),
    }),
  });
};

export const AudioPageHeader = ({ windowName }) => ({
  centerWidget: Widget.Label({ label: "Audio" }),
  endWidget: [
    SettingsHeaderButton({
      className: "audio-external-settings-button",
      on_clicked: () => {
        if (!dependencies("pavucontrol-qt")) return;

        Utils.execAsync("pavucontrol-qt");
        App.closeWindow(windowName);
      },
      icon: IconMap.ui.settings,
    }),
  ],
});

const AudioPage = (initialTab) => {
  setActiveTab(initialTab);
  return Widget.Box({
    vertical: true,
    spacing: 16,
    className: "audio-settings",
    child: Widget.Box({
      className: "content",
      child: Tabs({
        tabs: [
          { label: "Speakers", id: "speaker" },
          { label: "Microphones", id: "microphone" },
          { label: "Applications", id: "apps" },
        ],
        children: {
          speaker: SpeakerSinks(),
          microphone: MicrophoneSinks(),
          apps: AppMixer(),
        },
        shown: activeTab,
      }),
    }),
  });
};

export default AudioPage;
