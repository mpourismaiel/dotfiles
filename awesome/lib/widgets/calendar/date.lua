local capi = {
  awesome = awesome
}
local wibox = require("wibox")
local gears = require("gears")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")
local wbutton = require("lib.widgets.button")
local wclock = require("lib.widgets.text.clock")

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
    padding_top = config.dpi(8),
    padding_bottom = config.dpi(8),
    padding_left = config.dpi(16),
    padding_right = config.dpi(16),
    valign = "center",
    halign = "left",
    callback = function()
      capi.awesome.emit_signal("module::calendar::today")
    end,
    {
      layout = wibox.layout.fixed.vertical,
      {
        widget = wclock,
        format = "%a %d %B %Y",
        font_size = 12,
        halign = "left",
        bold = false,
        foreground = theme.fg_primary
      },
      {
        widget = wibox.container.margin,
        top = config.dpi(8),
        {
          widget = wclock,
          format = "%H:%M",
          font_size = 16,
          halign = "left",
          bold = true,
          foreground = theme.fg_normal
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
