local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local naughty = require("naughty")
local config = require("lib.configuration")

local bar_widget_wrapper = require("lib.widgets.bar.widget-wrapper")

local config_dir = gears.filesystem.get_configuration_dir()

local widget_icon_dir = config_dir .. "/images/"

local return_button = function()
  if config.commands.bluetooth == nil then
    naughty.notify(
      {
        title = "Bluetooth",
        text = "Bluetooth command is not set in config.lua",
        preset = naughty.config.presets.critical
      }
    )
    return
  end

  awful.spawn.easy_async_with_shell(
    "command -v " .. config.commands.bluetooth,
    function(stdout)
      if stdout == "" then
        naughty.notify(
          {
            title = "Bluetooth",
            text = "Bluetooth command is not installed",
            preset = naughty.config.presets.critical
          }
        )
      end
    end
  )

  local widget =
    wibox.widget {
    {
      id = "icon",
      image = widget_icon_dir .. "bluetooth-off" .. ".svg",
      widget = wibox.widget.imagebox,
      resize = true,
      width = config.dpi(16),
      height = config.dpi(16)
    },
    layout = wibox.layout.align.horizontal
  }

  local widget_button = bar_widget_wrapper(widget)

  widget_button:buttons(
    gears.table.join(
      awful.button(
        {},
        1,
        nil,
        function()
          awful.spawn(config.commands.bluetooth, false)
        end
      )
    )
  )

  local bluetooth_tooltip =
    awful.tooltip {
    objects = {widget_button},
    mode = "outside",
    align = "right",
    margin_leftright = config.dpi(8),
    margin_topbottom = config.dpi(8),
    preferred_positions = {"right", "left", "top", "bottom"}
  }

  awful.widget.watch(
    "rfkill list bluetooth",
    5,
    function(_, stdout)
      local widget_icon_name = nil
      if stdout:match("Soft blocked: yes") then
        widget_icon_name = "bluetooth-off"
        bluetooth_tooltip.markup = "Bluetooth is off"
      else
        widget_icon_name = "bluetooth"
        bluetooth_tooltip.markup = "Bluetooth is on"
      end
      widget.icon:set_image(widget_icon_dir .. widget_icon_name .. ".svg")
      collectgarbage("collect")
    end,
    widget
  )

  return widget_button
end

return return_button
