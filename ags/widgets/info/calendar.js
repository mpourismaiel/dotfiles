import { range } from "../../utils/array.js";

const Day = (n) =>
  Widget.Button({
    className: "day",
    child: Widget.Label({ label: n + "" }),
  });

const createMonth = (month) => {
  const weeks = [[]];
  const days = range(31);
  const firstDayOfWeekInMonth = 3;

  for (let i = 0; i < firstDayOfWeekInMonth; i++) {
    weeks[0].push(EmptyDay("day-empty"));
  }

  for (let i = 0; i < days.length; i++) {
    if (weeks[weeks.length - 1].length === 7) {
      weeks.push([]);
    }

    weeks[weeks.length - 1].push(Day(days[i]));
  }

  if (weeks[weeks.length - 1].length < 7) {
    for (let i = weeks[weeks.length - 1].length; i < 7; i++) {
      weeks[weeks.length - 1].push(EmptyDay("day-empty"));
    }
  }

  return Widget.Box({
    vertical: true,
    className: "month",
    homogeneous: true,
    children: weeks.map((week) =>
      Widget.Box({
        className: "week",
        homogeneous: true,
        children: week,
      })
    ),
  });
};

const EmptyDay = (className) =>
  Widget.Box({ className: `day-empty ${className}` });

const Calendar = () => {
  return Widget.Box({
    className: "calendar",
    vertical: true,
    children: [Widget.Box({ className: "calendar-actions" }), createMonth()],
  });
};

export default Calendar;
