local capi = {
  awesome = awesome
}
local wibox = require("wibox")
local gears = require("gears")
local config = require("configuration.config")
local theme = require("configuration.config.theme")
local wbutton = require("configuration.widgets.button")
local wclock = require("configuration.widgets.text.clock")

local date = {mt = {}}

local function new()
  local ret = {_private = {}}
  gears.table.crush(ret, date)

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
      capi.awesome.emit_signal("module::calendar::today")
    end,
    {
      layout = wibox.layout.fixed.vertical,
      {
        widget = wibox.container.place,
        {
          widget = wclock,
          format = "%a %d %B %Y",
          font_size = config.dpi(12),
          bold = false,
          foreground = theme.fg_primary
        }
      },
      {
        widget = wibox.container.margin,
        top = config.dpi(8),
        {
          widget = wibox.container.place,
          {
            widget = wclock,
            format = "%H:%M",
            font_size = config.dpi(16),
            bold = true,
            foreground = theme.fg_normal
          }
        }
      }
    }
  }

  wp.toggle = toggle

  return wp.toggle
end

function date.mt:__call(...)
  return new(...)
end

return setmetatable(date, date.mt)
