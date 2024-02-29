import { range } from "../../utils/array.js";
import { IconMap } from "../../utils/icons.js";
import { cn } from "../../utils/string.js";

const date = Variable(new Date());
const selectedDate = Variable(
  new Date(
    date.value.getFullYear(),
    date.value.getMonth(),
    date.value.getDate()
  )
);

const Day = (n, className, callback = () => {}) => {
  const d = new Date(date.value.getFullYear(), date.value.getMonth(), n);

  return Widget.Button({
    className: cn("day", className),
    on_clicked: callback,
    child: Widget.Label({
      className: "label",
      label: d.getDate() + "",
    }),
    setup: (self) => {
      self.hook(selectedDate, () => {
        self.toggleClassName(
          "selected",
          selectedDate.value && selectedDate.value.getTime() === d.getTime()
        );
      });
    },
  });
};

const createMonth = () => {
  const weeks = [[]];
  const firstDayOfMonth = new Date(
    date.value.getFullYear(),
    date.value.getMonth() + 1,
    1
  );
  const lastDayOfMonth = new Date(
    date.value.getFullYear(),
    date.value.getMonth() + 1,
    0
  );
  const firstDayOfWeekInMonth = firstDayOfMonth.getDay();
  const lastDayOfPreviousMonth = new Date(
    date.value.getFullYear(),
    date.value.getMonth(),
    0
  ).getDate();
  const days = range(lastDayOfMonth.getDate());

  for (let i = 0; i < firstDayOfWeekInMonth; i++) {
    weeks[0].push(
      Day(
        firstDayOfMonth.getDate() - firstDayOfWeekInMonth + i,
        "empty",
        () => {
          date.value = new Date(
            date.value.getFullYear(),
            date.value.getMonth() - 1,
            1
          );
        }
      )
    );
  }

  for (let i = 0; i < days.length; i++) {
    if (weeks[weeks.length - 1].length === 7) {
      weeks.push([]);
    }

    weeks[weeks.length - 1].push(
      Day(days[i], "", () => {
        selectedDate.value = new Date(
          date.value.getFullYear(),
          date.value.getMonth(),
          days[i]
        );
      })
    );
  }

  const lastWeekLength = weeks[weeks.length - 1].length;
  if (weeks[weeks.length - 1].length < 7) {
    for (let i = lastWeekLength; i < 7; i++) {
      weeks[weeks.length - 1].push(
        Day(i - lastWeekLength + 1, "empty", () => {
          date.value = new Date(
            date.value.getFullYear(),
            date.value.getMonth() + 1,
            1
          );
        })
      );
    }
  }

  if (weeks.length < 6) {
    weeks.push([]);
    for (let i = 0; i < 7; i++) {
      weeks[weeks.length - 1].push(
        Day(7 - lastWeekLength + i + 1, "empty", () => {
          date.value = new Date(
            date.value.getFullYear(),
            date.value.getMonth() + 1,
            1
          );
        })
      );
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

const MonthHeader = () => {
  return Widget.Button({
    className: "month-title",
    on_clicked: () => {
      date.value = new Date();
    },
    child: Widget.Label({
      hpack: "start",
      label: date
        .bind()
        .as(
          (d) =>
            d.toLocaleString("default", { month: "long" }) +
            " " +
            d.getFullYear()
        ),
    }),
  });
};

const SwitchMonthActions = () => {
  return Widget.Box({
    hpack: "end",
    spacing: 8,
    children: [
      Widget.Button({
        className: "switch-month prev",
        on_clicked: () => {
          date.value = new Date(
            date.value.getFullYear(),
            date.value.getMonth() - 1,
            1
          );
        },
        child: Widget.Icon({
          className: "arrow left",
          icon: IconMap.ui.arrow.left,
        }),
      }),
      Widget.Button({
        className: "switch-month next",
        on_clicked: () => {
          date.value = new Date(
            date.value.getFullYear(),
            date.value.getMonth() + 1,
            1
          );
        },
        child: Widget.Icon({
          className: "arrow right",
          icon: IconMap.ui.arrow.right,
        }),
      }),
    ],
  });
};

const TodoList = () => {
  return Widget.Box({
    className: "todolist",
    vertical: true,
    spacing: 16,
    children: [
      Widget.Label({
        className: "title",
        hpack: "start",
        label: "Todo List",
      }),
      Widget.Scrollable({
        hscroll: "never",
        className: "todolist-items-container",
        vexpand: true,
        child: Widget.Box({
          vertical: true,
          children: range(5)
            .map((txt, i, arr) => {
              const result = [];
              const box = Widget.Box({
                className: "todo",
                children: [
                  Widget.Label({
                    hpack: "start",
                    justify: "start",
                    label: "Lorem ipsum dolor sit emet " + (i + 1),
                  }),
                  Widget.Box({ hexpand: true }),
                  Widget.Button({
                    hpack: "end",
                    child: Widget.Icon({ icon: IconMap.ui.close }),
                    on_clicked: () => {
                      console.log("close");
                    },
                  }),
                ],
              });

              result.push(box);
              if (i !== arr.length - 1) {
                result.push(Widget.Separator());
              }

              return result;
            })
            .flat(),
        }),
      }),
    ],
  });
};

const Calendar = () => {
  return Widget.Box({
    className: "calendar",
    vertical: true,
    spacing: 16,
    children: [
      Widget.CenterBox({
        className: "calendar-header",
        startWidget: MonthHeader(),
        endWidget: SwitchMonthActions(),
      }),
      Widget.Box({
        child: createMonth(),
        setup: (self) => {
          self.hook(date, () => {
            self.child = createMonth();
          });
        },
      }),
      Widget.Separator(),
      TodoList(),
    ],
  });
};

export default Calendar;
