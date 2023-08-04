local wibox = require("wibox")
local gears = require("gears")
local config = require("lib.config")
local theme = require("lib.config.theme")
local wbutton = require("lib.widgets.button")

local power = {mt = {}}

local function new()
  local ret =
    wibox.widget {
    widget = wbutton,
    bg_normal = theme.bg_secondary,
    rounded = theme.rounded_rect_large,
    paddings = 0,
    {
      widget = wibox.container.place,
      {
        widget = wibox.container.constraint,
        strategy = "exact",
        width = config.dpi(24),
        height = config.dpi(24),
        {
          widget = wibox.widget.imagebox,
          image = theme.shutdown_icon
        }
      }
    }
  }

  gears.table.crush(ret, power, true)

  return ret
end

function power.mt:__call(...)
  return new(...)
end

return setmetatable(power, power.mt)
