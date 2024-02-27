import { IconMap, icon } from "../../utils/icons.js";
import ToggleButton from "../../widgets/_components/button/toggle.js";

const Audio = await Service.import("audio");

const SinkDevice = (speaker) => {
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
                  icon: icon(speaker.icon_name || "", IconMap.fallback.audio),
                  tooltip_text: speaker.icon_name || "",
                  size: 16,
                }),
                Widget.Label({
                  hpack: "start",
                  className: "title",
                  label: speaker.description,
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
              label: speaker.name,
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
                className: Audio.speaker
                  .bind("stream")
                  .as(
                    (s) =>
                      `default-button toggle-button ${
                        s === speaker.stream ? "active" : ""
                      }`
                  ),
                on_clicked: () => {
                  Audio.speaker = speaker;
                },
                child: Widget.Icon({
                  size: 16,
                  icon: Audio.speaker
                    .bind("stream")
                    .as((s) =>
                      s === speaker.stream ? IconMap.ui.tick : IconMap.ui.close
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
        on_change: ({ value }) => (speaker.volume = value),
        setup: (self) => {
          self.hook(
            Audio,
            (self) => {
              self.value = Audio.speakers.find((s) => s === speaker)?.volume;
            },
            `speaker-changed`
          );
        },
      }),
    ],
  });
};

const AudioSinks = () => {
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
            result.push(SinkDevice(speaker));
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

export const AudioPageHeader = () => ({
  centerWidget: Widget.Label({ label: "Audio" }),
});

const AudioPage = () => {
  return Widget.Box({
    vertical: true,
    spacing: 16,
    className: "audio-settings",
    child: Widget.Box({
      className: "content",
      children: [AudioSinks()],
    }),
  });
};

export default AudioPage;
