import ArrowButton from "../_components/button/arrow.js";

const Battery = await Service.import("battery");

const BatteryButton = () => {
  const icons = (charging) =>
    [
      ...Array.from({ length: 10 }, (_, i) => i * 10).map((i) => [
        `${i}`,
        Widget.Icon({
          class_name: `${i} ${charging ? "charging" : "discharging"}`,
          icon: `battery-level-${i}${charging ? "-charging" : ""}-symbolic`,
          size: 24,
        }),
      ]),
      [
        "100",
        Widget.Icon({
          class_name: `100 ${charging ? "charging" : "discharging"}`,
          icon: `battery-level-100${charging ? "-charged" : ""}-symbolic`,
          size: 24,
        }),
      ],
    ].reduce((acc, [key, widget]) => {
      acc[key] = widget;
      return acc;
    }, {});

  const Indicators = (charging) =>
    Widget.Stack({
      children: icons(charging),
      setup: (self) =>
        self.hook(Battery, (stack) => {
          stack.shown = `${Math.floor(Battery.percent / 10) * 10}`;
        }),
    });

  const BatteryIcon = () =>
    Widget.Stack({
      class_name: "battery__indicator",
      children: {
        true: Indicators(true),
        false: Indicators(false),
      },
      setup: (self) =>
        self.hook(Battery, (stack) => {
          const { charging, charged } = Battery;
          stack.shown = `${charging || charged}`;
          stack.toggleClassName("charging", Battery.charging);
          stack.toggleClassName("charged", Battery.charged);
          stack.toggleClassName("low", Battery.percent < 30);
        }),
    });

  const BatteryIndicator = () =>
    ArrowButton({
      children: [
        BatteryIcon(),
        Widget.Label({
          class_name: "title",
          hpack: "start",
          setup: (self) => {
            self.hook(Battery, (self) => {
              self.label = Battery.percent ? `${Battery.percent}%` : "Unknown";
            });
          },
        }),
      ],
    });

  return Widget.Button({
    className: "bar-battery panel-button",
    child: BatteryIndicator(),
  });
};

export default BatteryButton;
