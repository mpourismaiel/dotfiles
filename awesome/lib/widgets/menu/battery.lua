local wibox = require("wibox")
local gears = require("gears")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")
local upower_daemon = require("lib.daemons.hardware.upower")
local wbutton = require("lib.widgets.button")
local wtext = require("lib.widgets.text")
local console = require("lib.helpers.console")

local battery = {mt = {}}

function battery:update(data)
  local wp = self._private
  if data.State then
    if data.State == upower_daemon.UPower_States.Charging or data.State == upower_daemon.UPower_States.Fully_charged then
      wp.image_container:insert(2, wp.charging_icon)
    else
      wp.image_container:remove(2)
    end
  end

  if data.Percentage <= 10 then
    wp.image_role:set_image(theme.battery_10_icon)
  elseif data.Percentage <= 25 then
    wp.image_role:set_image(theme.battery_25_icon)
  elseif data.Percentage <= 50 then
    wp.image_role:set_image(theme.battery_50_icon)
  elseif data.Percentage <= 75 then
    wp.image_role:set_image(theme.battery_75_icon)
  else
    wp.image_role:set_image(theme.battery_100_icon)
  end

  wp.text_role:set_text(data.Percentage .. "%")
end

local function new()
  local ret = {_private = {}}
  gears.table.crush(ret, battery, true)

  local wp = ret._private

  local widget =
    wibox.widget {
    widget = wbutton,
    strategy = "exact",
    width = config.dpi(60),
    height = config.dpi(60),
    bg_normal = theme.bg_secondary,
    rounded = theme.rounded_rect_large,
    paddings = 0,
    {
      layout = wibox.layout.fixed.vertical,
      spacing = config.dpi(8),
      {
        widget = wibox.container.constraint,
        strategy = "exact",
        width = config.dpi(16),
        height = config.dpi(16),
        {
          widget = wibox.container.place,
          {
            layout = wibox.layout.stack,
            id = "image_container",
            {
              widget = wibox.widget.imagebox,
              image = theme.battery_50_icon,
              id = "image_role"
            }
          }
        }
      },
      {
        widget = wibox.container.place,
        {
          widget = wtext,
          text = "50%",
          id = "text_role"
        }
      }
    }
  }

  local charging_icon =
    wibox.widget {
    widget = wibox.widget.imagebox,
    image = theme.battery_charging_icon
  }

  ret.widget = widget
  wp.charging_icon = charging_icon
  wp.image_container = widget:get_children_by_id("image_container")[1]
  wp.image_role = widget:get_children_by_id("image_role")[1]
  wp.text_role = widget:get_children_by_id("text_role")[1]

  upower_daemon:connect_signal(
    "battery::init",
    function(self, device)
      ret:update(device)
    end
  )

  upower_daemon:connect_signal(
    "battery::update",
    function(self, device, data)
      ret:update(device)
    end
  )

  return ret
end

function battery.mt:__call(...)
  return new(...)
end

return setmetatable(battery, battery.mt)
