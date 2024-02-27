import PanelButton from "./panel-button.js";
import { WINDOW_NAME as InfoWindowName } from "../info/main.js";

const Clock = () =>
  PanelButton({
    on_clicked: () => App.toggleWindow(InfoWindowName),
    child: Widget.Box({
      hexpand: true,
      class_name: "clock",
      vertical: true,
      children: [
        Widget.Label({
          class_name: "clock-hour",
          setup: (self) =>
            self.poll(1000, (self) =>
              Utils.execAsync(["date", "+%H"]).then(
                (date) => (self.label = date)
              )
            ),
        }),
        Widget.Label({
          class_name: "clock-minute",
          setup: (self) =>
            self.poll(1000, (self) =>
              Utils.execAsync(["date", "+%M"]).then(
                (date) => (self.label = date)
              )
            ),
        }),
      ],
    }),
  });

export default Clock;
