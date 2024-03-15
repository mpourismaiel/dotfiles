const QuickSettings = ({
  activeQuickSettings,
  children,
  key,
  onMoreSettingsClicked,
}) => {
  const on_clicked = () => {
    activeQuickSettings.setValue(null);
    onMoreSettingsClicked();
  };

  return Widget.Revealer({
    className: "quick-settings-revealer",
    child: Widget.Box({
      className: "content",
      vertical: true,
      spacing: 8,
      children: [
        ...children,
        Widget.Separator(),
        Widget.Button({
          className: "more-settings",
          on_clicked,
          child: Widget.Label({
            hpack: "start",
            label: "More settings",
          }),
        }),
      ],
    }),
    reveal_child: activeQuickSettings.bind().as((v) => v === key),
  });
};

export default QuickSettings;
