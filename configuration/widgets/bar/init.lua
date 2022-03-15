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
    position = "left",
    width = 48,
    screen = screen,
    bg = "#222222c0",
    widget = {
      layout = wibox.layout.stack,
      {
        widget = wibox.container.place,
        valign = "top",
        {
          widget = wibox.container.margin,
          top = config.dpi(9),
          {
            widget = taglist.new(screen)
          }
        }
      },
      {
        layout = wibox.layout.align.vertical,
        nil,
        wibox.container.place(tasklist.new(screen)),
        nil
      },
      {
        widget = wibox.container.place,
        valign = "bottom",
        {
          widget = wibox.container.margin,
          bottom = config.dpi(9),
          {
            layout = wibox.layout.fixed.vertical,
            bar_widget_wrapper(
              wibox.widget {
                base_size = config.dpi(16),
                horizontal = false,
                screen = screen,
                widget = wibox.widget.systray
              }
            ),
            bar_widget_wrapper(keyboardlayout.new()),
            bar_widget_wrapper(clock.new()),
            bar_widget_wrapper(layoutbox.new(screen))
          }
        }
      }
    }
  }
end

function bar.mt:__call(...)
  return bar.new(...)
end

return setmetatable(bar, bar.mt)
