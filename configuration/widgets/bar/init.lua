local awful = require("awful")
local wibox = require("wibox")

local bar_widget_wrapper = require("configuration.widgets.bar.widget-wrapper")
local config = require("configuration.config")
local theme = require("configuration.config.theme")
local menu = require("configuration.widgets.menu")
local taglist = require("configuration.widgets.taglist")
local tasklist = require("configuration.widgets.tasklist")
local layoutbox = require("configuration.widgets.layoutbox")
local systray = require("configuration.widgets.systray")
local clock = require("configuration.widgets.clock")
local wbutton = require("configuration.widgets.button")

local bar = {mt = {}}

function bar.new(screen)
  return awful.wibar {
    position = "left",
    width = 48,
    screen = screen,
    bg = theme.bg_normal,
    widget = {
      layout = wibox.layout.stack,
      {
        widget = wibox.container.place,
        valign = "top",
        {
          widget = wibox.layout.fixed.vertical,
          menu.new(screen),
          {
            widget = wibox.container.margin,
            top = config.dpi(4),
            {
              widget = wbutton,
              margin = theme.bar_padding,
              bg_normal = theme.bg_normal,
              bg_hover = theme.bg_primary,
              paddings = 0,
              padding_top = 8,
              padding_bottom = 8,
              taglist.new(screen)
            }
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
            clock.new(),
            layoutbox.new(screen),
            systray.new()
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
