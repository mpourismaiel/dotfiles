local wibox = require("wibox")
local gears = require("gears")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")
local console = require("lib.helpers.console")
local wbutton = require("lib.widgets.button")
local power_button = require("lib.widgets.menu.power-button")

local power = {mt = {}}

function power:set_callback(callback)
  local wp = self._private
  wp.callback = callback
end

function power:get_callback()
  local wp = self._private
  return wp.callback
end

local function new(args)
  local ret = {_private = {}}
  gears.table.crush(ret, power, true)

  local wp = ret._private
  wp.callback = args.callback or nil

  local toggle =
    wibox.widget {
    widget = wbutton,
    bg_normal = theme.bg_secondary,
    rounded = theme.rounded_rect_large,
    callback = function()
      if not wp.callback then
        return
      end
      wp.callback(wp.menu)
    end,
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

  local menu =
    wibox {
    ontop = true,
    visible = false,
    type = "utility",
    width = config.dpi(120),
    height = config.dpi(36) * 5,
    bg = theme.bg_normal,
    shape = gears.shape.rounded_rect,
    widget = {
      layout = wibox.layout.fixed.vertical,
      power_button("lock"),
      power_button("sleep"),
      power_button("logout"),
      power_button("reboot"),
      power_button("power")
    }
  }

  ret.toggle = toggle
  wp.menu = menu

  return ret
end

function power.mt:__call(...)
  return new(...)
end

return setmetatable(power, power.mt)
