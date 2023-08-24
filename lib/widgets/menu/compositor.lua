local wibox = require("wibox")
local gears = require("gears")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")
local picom_daemon = require("lib.daemons.system.picom")
local wbutton_state = require("lib.widgets.button.state")
local wtext = require("lib.widgets.text")
local console = require("lib.helpers.console")

local compositor = {mt = {}}
local instance = nil

local function new()
  local ret =
    wibox.widget {
    widget = wibox.container.constraint,
    strategy = "exact",
    width = config.dpi(60),
    height = config.dpi(60),
    {
      widget = wbutton_state,
      rounded = theme.rounded_rect_large,
      id = "state",
      paddings = 0,
      callback = function()
        picom_daemon:toggle()
      end,
      widget_on = {
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
              widget = wibox.widget.imagebox,
              image = theme.compositor_icon
            }
          }
        },
        {
          widget = wtext,
          text = "On"
        }
      },
      widget_off = {
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
              widget = wibox.widget.imagebox,
              image = theme.compositor_icon
            }
          }
        },
        {
          widget = wtext,
          text = "Off"
        }
      }
    }
  }
  gears.table.crush(ret, compositor)

  local wp = ret._private
  wp.state = ret:get_children_by_id("state")[1]

  if picom_daemon:get_state() then
    wp.state:turn_on()
  else
    wp.state:turn_off()
  end

  picom_daemon:connect_signal(
    "state",
    function(self, state)
      if state then
        wp.state:turn_on()
      else
        wp.state:turn_off()
      end
    end
  )
  return ret
end

if not instance then
  instance = new()
end
return instance
