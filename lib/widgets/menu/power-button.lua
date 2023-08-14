local capi = {
  awesome = awesome
}
local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")
local wbutton = require("lib.widgets.button")
local wtext = require("lib.widgets.text")

local config_dir = gears.filesystem.get_configuration_dir()
local power_icon = config_dir .. "/images/power.svg"
local lock_icon = config_dir .. "/images/lock.svg"
local reboot_icon = config_dir .. "/images/restart.svg"
local sleep_icon = config_dir .. "/images/power-sleep.svg"
local logout_icon = config_dir .. "/images/logout.svg"

local suspend_command = function()
  capi.awesome.emit_signal("module::exit_screen:hide")
  capi.awesome.emit_signal("widget::drawer::hide")
  capi.awesome.emit_signal("module::lockscreen::show")
  awful.spawn.with_shell("systemctl suspend")
end

local logout_command = function()
  capi.awesome.quit()
end

local lock_command = function()
  capi.awesome.emit_signal("module::exit_screen:hide")
  capi.awesome.emit_signal("widget::drawer::hide")
  capi.awesome.emit_signal("module::lockscreen::show")
end

local power_command = function()
  capi.awesome.emit_signal("module::exit_screen:hide")
  capi.awesome.emit_signal("widget::drawer::hide")
  awful.spawn.with_shell("poweroff")
end

local reboot_command = function()
  awful.spawn.with_shell("reboot")
  capi.awesome.emit_signal("module::exit_screen:hide")
  capi.awesome.emit_signal("widget::drawer::hide")
end

local power_button = function(command)
  local icon = ""
  local label = ""
  local fn = nil
  if command == "power" then
    icon = power_icon
    label = "Power"
    fn = power_command
  elseif command == "lock" then
    icon = lock_icon
    label = "Lock"
    fn = lock_command
  elseif command == "reboot" then
    icon = reboot_icon
    label = "Reboot"
    fn = reboot_command
  elseif command == "sleep" then
    icon = sleep_icon
    label = "Sleep"
    fn = suspend_command
  elseif command == "logout" then
    icon = logout_icon
    label = "Logout"
    fn = logout_command
  end

  local w =
    wibox.widget {
    widget = wibox.container.constraint,
    width = config.dpi(120),
    height = config.dpi(36),
    strategy = "exact",
    {
      widget = wbutton,
      bg_normal = theme.bg_normal,
      paddings = 0,
      padding_left = config.dpi(16),
      callback = fn,
      halign = "left",
      shape = "rectangle",
      {
        layout = wibox.layout.fixed.horizontal,
        spacing = config.dpi(16),
        {
          widget = wibox.container.constraint,
          width = config.dpi(16),
          height = config.dpi(16),
          strategy = "exact",
          {
            widget = wibox.container.place,
            {
              widget = wibox.widget.imagebox,
              image = icon
            }
          }
        },
        {
          widget = wtext,
          text = label,
          halign = "left",
          valign = "center"
        }
      }
    }
  }

  return w
end

return power_button
