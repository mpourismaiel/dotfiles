import options from "../lib/options.js";
import { cn } from "../utils/string.js";

export const ShortcutsDisplay = Variable(null);

const Key = ({ key, size }) => {
  return Widget.Box({
    className: cn("key", size),
    children: [
      Widget.Label({
        justification: "center",
        hexpand: true,
        label: key,
      }),
    ],
  });
};

const Plus = () => {
  return Widget.Label({
    className: "plus",
    label: "+",
  });
};

const ComboKey = ({ combo }) => {
  return Widget.Box({
    className: "combo-key",
    children: combo
      .split("+")
      .map((key, index, arr) => {
        return index < arr.length - 1 ? [Key({ key }), Plus()] : Key({ key });
      })
      .flat(),
  });
};

const ShortcutKeyAndTitle = ({ title, combo }) => {
  return Widget.Box({
    className: "shortcut",
    vertical: true,
    children: [
      ComboKey({ combo }),
      Widget.Label({
        className: "description",
        label: title,
      }),
    ],
  });
};

const ShortcutHelper = () => {
  const Header = Widget.Label({
    className: "header",
    label: ShortcutsDisplay.bind().as((v) => (v ? v.title : "")),
  });

  const Shortcuts = Widget.Box({
    className: "shortcuts",
    spacing: 16,
    children: ShortcutsDisplay.bind().as((v) =>
      !v
        ? []
        : v.shortcuts
            .map(({ title, combo }, i, arr) =>
              i < arr.length - 1
                ? [ShortcutKeyAndTitle({ title, combo }), Widget.Separator()]
                : ShortcutKeyAndTitle({ title, combo })
            )
            .flat()
    ),
  });

  const Footer = Widget.Box({
    className: "footer",
    hpack: "end",
    spacing: 4,
    children: [
      Widget.Label({
        className: "footer-text",
        label: "Press",
      }),
      Key({ key: "Esc", size: "sm" }),
      Widget.Label({
        className: "footer-text",
        label: "to close",
      }),
    ],
  });

  return Widget.Window({
    name: "shortcut-helper",
    className: "shortcut-helper-window",
    anchor: ["bottom"],
    click_through: true,
    keymode: "none",
    layer: "overlay",
    visible: true,
    child: Widget.Box({
      child: Widget.Revealer({
        transition: "crossfade",
        transition_duration: options.getOption("transition"),
        child: Widget.Box({
          className: "shortcut-helper-container",
          vertical: true,
          children: [Header, Shortcuts, Footer],
        }),
        reveal_child: ShortcutsDisplay.bind().as((v) => v !== null),
      }),
    }),
  });
};

export default ShortcutHelper;
