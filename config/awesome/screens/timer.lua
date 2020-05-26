local wibox = require("wibox")
local awful = require("awful")
local beautiful = require("beautiful")
local markup = require("lain.util.markup")
local gears = require("gears")
local naughty = require("naughty")
local my_table = awful.util.table or gears.table

local icon_string = awful.util.theme_functions.icon_string

function widget_button(w, action)
  local bg_normal = awful.util.theme_functions.widget_bg .. "00"
  local bg_hover = awful.util.theme_functions.widget_bg .. "ff"

  w = wibox.container.background(wibox.container.margin(w, 10, 10), bg_normal)
  w:connect_signal(
    "mouse::enter",
    function()
      w.bg = bg_hover
    end
  )

  w:connect_signal(
    "mouse::leave",
    function()
      w.bg = bg_normal
    end
  )

  w:buttons(my_table.join(awful.button({}, 1, action)))

  return w
end

local s = awful.screen.focused()

local timer_screen =
  wibox(
  {
    screen = s,
    x = s.geometry.width / 2 - 200,
    y = s.geometry.height - 2,
    bg = awful.util.theme_functions.bg_panel,
    type = "dock",
    width = 400,
    height = 40,
    ontop = true,
    visible = false,
    opacity = 1
  }
)

timer_screen:connect_signal(
  "mouse::enter",
  function()
    timer_screen.y = s.geometry.height - 40
  end
)

timer_screen:connect_signal(
  "mouse::leave",
  function()
    timer_screen.y = s.geometry.height - 2
  end
)

local current_time = 2
local timer_running = false
local timer_stopped = true
local timer_time = wibox.widget.textbox(markup("#ffffff", "25:00"))
local timer_title = wibox.widget.textbox(markup("#ffffff", "Start a pomodoro!"))
local timer_button_label = wibox.widget.textbox(icon_string("", 10, true))

local timer =
  gears.timer {
  timeout = 1,
  callback = function()
    current_time = current_time - 1
    timer_time:set_markup(markup("#ffffff", math.floor(current_time / 60) .. ":" .. (current_time % 60)))

    if current_time <= 0 then
      timer_running = false
      timer_stopped = true
      timer_stop.visible = false
      current_time = 25 * 60
      timer:stop()
      naughty.notify {message = "Take a break!s"}
    end
  end
}

local timer_stop =
  widget_button(
  wibox.widget.textbox(icon_string("", 10, true)),
  function()
    timer:stop()
    timer_stop.visible = false

    timer_running = false
    timer_stopped = true
    current_time = 25 * 60
  end
)

local timer_button =
  widget_button(
  timer_button_label,
  function()
    if timer_running == false then
      timer:start()
      timer_running = true
      timer_stopped = false
      timer_stop.visible = true
      timer_button_label:set_markup("")
    else
      timer:stop()
      timer_running = false
      timer_button_label:set_markup("")
    end
  end
)

timer_stop.visible = false

timer_screen:setup(
  {
    layout = wibox.layout.flex.horizontal,
    {
      {
        timer_title,
        nil,
        {
          timer_time,
          wibox.container.margin(timer_button, 10),
          -- wibox.container.margin(timer_stop, 10),
          layout = wibox.layout.fixed.horizontal
        },
        layout = wibox.layout.align.horizontal
      },
      widget = wibox.container.margin,
      left = 10,
      right = 10,
      top = 5,
      bottom = 5
    }
  }
)
