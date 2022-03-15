local awful = require("awful")
local wibox = require("wibox")

local bar_widget_wrapper = require("configuration.widgets.bar.widget-wrapper")
local config = require("configuration.config")
local taglist = require("configuration.widgets.taglist")
local tasklist = require("configuration.widgets.tasklist")
local layoutbox = require("configuration.widgets.layoutbox")
local keyboardlayout = require("configuration.widgets.keyboardlayout")
local clock = require("configuration.widgets.clock")

local bar = {mt = {}}

function bar.new(screen)
  return awful.wibar {
    position = "bottom",
    height = 48,
    screen = screen,
    bg = "#222222e0",
    widget = {
      layout = wibox.layout.stack,
      {
        widget = wibox.container.place,
        halign = "left",
        {
          widget = wibox.container.margin,
          left = config.dpi(6),
          {
            widget = taglist.new(screen)
          }
        }
      },
      {
        layout = wibox.layout.align.horizontal,
        nil,
        wibox.container.place(tasklist.new(screen)),
        nil
      },
      {
        widget = wibox.container.place,
        halign = "right",
        {
          layout = wibox.layout.fixed.horizontal,
          bar_widget_wrapper(wibox.widget.systray()),
          bar_widget_wrapper(keyboardlayout.new()),
          bar_widget_wrapper(clock.new()),
          bar_widget_wrapper(layoutbox.new(screen))
        }
      }
    }
  }
end

function bar.mt:__call(...)
  return bar.new(...)
end

return setmetatable(bar, bar.mt)
