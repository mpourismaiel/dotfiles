local wibox = require("wibox")
local lain = require("lain")
local clickable_container = require("widgets.clickable-container")
local markup = lain.util.markup

return function(theme)
  local clock = wibox.widget.textclock(markup(theme.fg_normal, markup.font("FiraCode Bold 14", "%H:%M")))
  local date = wibox.widget.textclock(markup(theme.fg_normal_secondary, markup.font("FiraCode Bold 10", "%Y/%m/%d")))

  local widget =
    wibox.widget {
    wibox.container.place(wibox.container.margin(clock, 0, 0, 5)),
    wibox.container.place(date),
    layout = wibox.layout.fixed.vertical
  }

  local container = clickable_container(wibox.container.constraint(wibox.container.place(widget), "exact", 100), {change_cursor = false})
  local calendar = require("widgets.damn.calendar-widget.calendar")(theme)
  container:connect_signal(
    "button::press",
    function(_, _, _, button)
      if button == 1 then
        calendar.toggle()
      end
    end
  )

  return container
end
