local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local config = require("configuration.config")
local theme = require("configuration.config.theme")
local wbutton = require("configuration.widgets.button")

local config_dir = gears.filesystem.get_configuration_dir()
local power_icon = config_dir .. "/images/power.svg"
local lock_icon = config_dir .. "/images/lock.svg"
local reboot_icon = config_dir .. "/images/restart.svg"
local sleep_icon = config_dir .. "/images/power-sleep.svg"
local logout_icon = config_dir .. "/images/logout.svg"

local suspend_command = function()
  awesome.emit_signal("module::exit_screen:hide")
  awesome.emit_signal("widget::drawer:hide")
  awesome.emit_signal("module::lockscreen:show")
  awful.spawn.with_shell("systemctl suspend")
end

local logout_command = function()
  awesome.quit()
end

local lock_command = function()
  awesome.emit_signal("module::exit_screen:hide")
  awesome.emit_signal("widget::drawer:hide")
  awesome.emit_signal("module::lockscreen:show")
end

local power_command = function()
  awesome.emit_signal("module::exit_screen:hide")
  awesome.emit_signal("widget::drawer:hide")
  awful.spawn.with_shell("poweroff")
end

local reboot_command = function()
  awful.spawn.with_shell("reboot")
  awesome.emit_signal("module::exit_screen:hide")
  awesome.emit_signal("widget::drawer:hide")
end

local power_button = function(command)
  local icon = ""
  local fn = nil
  if command == "power" then
    icon = power_icon
    fn = power_command
  elseif command == "lock" then
    icon = lock_icon
    fn = lock_command
  elseif command == "reboot" then
    icon = reboot_icon
    fn = reboot_command
  elseif command == "sleep" then
    icon = sleep_icon
    fn = suspend_command
  elseif command == "logout" then
    icon = logout_icon
    fn = logout_command
  end

  local w =
    wibox.widget {
    widget = wbutton,
    bg_normal = theme.bg_secondary,
    callback = fn,
    {
      widget = wibox.container.constraint,
      height = config.dpi(40),
      strategy = "exact",
      {
        widget = wibox.container.place,
        {
          widget = wibox.widget.imagebox,
          image = icon
        }
      }
    }
  }

  return w
end

return power_button
