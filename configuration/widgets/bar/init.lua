local awful = require("awful")
local wibox = require("wibox")
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
    widget = {
      layout = wibox.layout.align.horizontal,
      taglist.new(screen),
      tasklist.new(screen),
      {
        -- Right widgets
        layout = wibox.layout.fixed.horizontal,
        wibox.widget.systray(),
        keyboardlayout.new(),
        clock.new(),
        layoutbox.new(screen)
      }
    }
  }
end

function bar.mt:__call(...)
  return bar.new(...)
end

return setmetatable(bar, bar.mt)
