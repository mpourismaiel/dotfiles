import Workspaces from "../workspaces/vertical/main.js";
import Clients from "../clients/vertical/main.js";
import MenuToggleButton from "../menu/main.js";
import Clock from "./date.js";

const Top = () =>
  Widget.Box({
    spacing: 8,
    children: [Workspaces()],
  });

const Center = (monitor) =>
  Widget.Box({
    spacing: 8,
    children: [Clients(monitor)],
  });

const Bottom = (monitor) =>
  Widget.Box({
    vertical: true,
    vpack: "end",
    children: [Clock(), MenuToggleButton(monitor)],
  });

const Bar = (monitor = 0) =>
  Widget.Window({
    name: `bar-${monitor}`, // name has to be unique
    class_name: "bar",
    monitor,
    anchor: ["top", "left", "bottom"],
    exclusivity: "exclusive",
    child: Widget.CenterBox({
      vertical: true,
      startWidget: Top(),
      centerWidget: Center(monitor),
      endWidget: Bottom(monitor),
    }),
  });

export default Bar;
