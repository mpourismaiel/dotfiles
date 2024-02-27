const PanelButton = ({
  className = "",
  label = "",
  onScrollUp = () => null,
  onScrollDown = () => null,
  on_clicked = () => null,
  onMiddleClickRelease = () => null,
  onSecondaryClickRelease = () => null,
  child = null,
  ...rest
}) =>
  Widget.Button({
    className: "panel-button-container",
    onScrollUp,
    onScrollDown,
    on_clicked,
    onMiddleClickRelease,
    onSecondaryClickRelease,
    ...rest,
    child: Widget.Box({
      className: "panel-button",
      child: Widget.Box({
        className,
        child: child || Widget.Label({ label }),
      }),
    }),
  });

export default PanelButton;
