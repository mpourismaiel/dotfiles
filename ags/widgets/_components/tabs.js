const Tabs = ({ tabs, children, shown }) => {
  const Buttons = tabs.map(({ label, icon, id }) => {
    const Icon = icon
      ? Widget.Icon({
          className: "icon",
          size: 16,
          icon,
        })
      : null;

    const Label = label
      ? Widget.Label({
          className: "label",
          label,
        })
      : null;

    return Widget.Button({
      className: "tab toggle-button",
      child: Widget.Box({
        spacing: 8,
        children: [Icon, Label].filter(Boolean),
      }),
      on_clicked: () => (shown.value = id),
      setup: (self) => {
        self.hook(shown, () => {
          self.toggleClassName("active", shown.value === id);
        });
      },
    });
  });

  return Widget.Box({
    className: "tabs",
    vertical: true,
    spacing: 16,
    children: [
      Widget.Box({
        className: "tabs",
        spacing: 8,
        children: Buttons,
      }),
      Widget.Stack({
        transition: "slide_left_right",
        children,
        shown: shown.bind(),
      }),
    ],
  });
};

export default Tabs;
