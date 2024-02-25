import { range } from "../../utils/array.js";
import options from "../../lib/options.js";

import GLib from "gi://GLib?version=2.0";

const Progress = ({ height = 18, width = 180, vertical = false, visible }) => {
  const Value = Widget.Box({
    class_name: "value",
    hexpand: vertical,
    vexpand: !vertical,
    hpack: vertical ? "fill" : "start",
    vpack: vertical ? "end" : "fill",
  });

  const Trail = Widget.Box({
    class_name: "progress trail",
    child: Value,
    visible,
    css: `
            min-width: ${width}px;
            min-height: ${height}px;
        `,
  });

  let fill_size = 0;
  let animations = [];

  return Object.assign(Trail, {
    setValue(value) {
      if (value < 0) return;

      if (animations.length > 0) {
        for (const id of animations) GLib.source_remove(id);

        animations = [];
      }

      const axis = vertical ? "height" : "width";
      const axisv = vertical ? height : width;
      const min = vertical ? width : height;
      const preferred = (axisv - min) * value + min;

      if (!fill_size) {
        fill_size = preferred;
        Value.css = `min-${axis}: ${preferred}px;`;
        return;
      }

      const frames = options.getOption("transition") / 10;
      const goal = preferred - fill_size;
      const step = goal / frames;

      animations = range(frames, 0).map((i) =>
        Utils.timeout(5 * i, () => {
          fill_size += step;
          Value.css = `min-${axis}: ${fill_size}px`;
          animations.shift();
        })
      );
    },
  });
};

export default Progress;
