import { getAudioTypeIcon } from "../_utils/icons.js";
import { Row } from "../misc/layout.js";

const Audio = await Service.import("audio");

const VolumeMuteButton = ({ type }) =>
  Widget.Button({
    className: "bar-volume-indicator",
    onPrimaryClick: () => (Audio[type].is_muted = !Audio[type].is_muted),
    child: Widget.Icon({
      size: 24,
      setup: (self) => {
        self.hook(
          Audio,
          (icon) => {
            if (!Audio[type]) return;

            icon.icon =
              type === "speaker"
                ? getAudioTypeIcon(Audio[type].icon_name || "")
                : "microphone-sensitivity-high-symbolic";

            icon.tooltip_text = `Volume ${Math.floor(
              Audio[type].volume * 100
            )}%`;
          },
          `${type}-changed`
        );
      },
    }),
  });

const VolumeSlider = ({ type }) =>
  Widget.Slider({
    class_name: "bar-volume-slider",
    hexpand: true,
    draw_value: false,
    on_change: ({ value }) => (Audio[type].volume = value),
    setup: (self) => {
      self.hook(
        Audio,
        (slider) => {
          slider.value = Audio[type]?.volume;
        },
        `${type}-changed`
      );
    },
  });

const Volume = ({ type }) =>
  Widget.Box({
    spacing: 10,
    children: [VolumeMuteButton({ type }), VolumeSlider({ type })],
  });

export default Volume;
