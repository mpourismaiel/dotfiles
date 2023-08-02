local awful = require("awful")
local wibox = require("wibox")

local theme = require("configuration.config.theme")
local menu = require("configuration.widgets.menu")
local taglist = require("configuration.widgets.taglist")
local tasklist = require("configuration.widgets.tasklist")
local clock = require("configuration.widgets.clock")
local wbutton = require("configuration.widgets.button")

local bar = {mt = {}}

function bar.new(screen)
  return awful.wibar {
    position = "left",
    width = theme.bar_width,
    screen = screen,
    bg = theme.bg_normal,
    widget = {
      layout = wibox.layout.stack,
      {
        widget = wibox.container.place,
        valign = "top",
        {
          widget = wbutton,
          margin = theme.bar_padding,
          bg_normal = theme.bg_normal,
          bg_hover = theme.bg_primary,
          paddings = 0,
          padding_top = 8,
          padding_bottom = 8,
          callback = function()
            awesome.emit_signal("module::launcher::show", screen)
          end,
          taglist.new(screen)
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
          layout = wibox.layout.fixed.vertical,
          clock.new(),
          menu()
        }
      }
    }
  }
end

function bar.mt:__call(...)
  return bar.new(...)
end

return setmetatable(bar, bar.mt)
