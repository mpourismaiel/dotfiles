local capi = {
  awesome = awesome
}
local wibox = require("wibox")
local gears = require("gears")
local awful = require("awful")
local theme = require("lib.config.theme")
local wbutton = require("lib.widgets.button")
local wclock = require("lib.widgets.text.clock")

local datetime = {mt = {}}

local function new()
  local ret = {_private = {}}
  gears.table.crush(ret, datetime)

  local wp = ret._private
  local toggle =
    wibox.widget {
    widget = wbutton,
    margin = theme.bar_padding,
    bg_normal = theme.bg_normal,
    bg_hover = theme.bg_primary,
    paddings = 0,
    padding_top = 8,
    padding_bottom = 8,
    valign = "center",
    callback = function()
      capi.awesome.emit_signal("module::calendar::toggle", awful.screen.focused())
    end,
    {
      layout = wibox.layout.fixed.vertical,
      {
        widget = wibox.container.place,
        {
          widget = wclock,
          format = "%H",
          font_size = theme.bar_clock_hour_font_size,
          bold = theme.bar_clock_hour_bold,
          foreground = theme.fg_primary
        }
      },
      {
        widget = wibox.container.place,
        {
          widget = wclock,
          format = "%M",
          font_size = theme.bar_clock_minute_font_size,
          bold = theme.bar_clock_minute_bold,
          foreground = theme.fg_normal
        }
      }
    }
  }

  wp.toggle = toggle

  return wp.toggle
end

function datetime.mt:__call(...)
  return new(...)
end

return setmetatable(datetime, datetime.mt)
