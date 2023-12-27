local capi = {
  awesome = awesome
}
local naughty = require("naughty")
local awful = require("awful")
local gears = require("gears")
local gtimer = require("gears.timer")
local config_dir = gears.filesystem.get_configuration_dir()

local picom = {}
local instance = nil

function picom:turn_on()
  local wp = self._private
  if wp.compositor == nil then
    return
  end

  local cmd = wp.compositor .. " --config " .. config_dir .. "/lib/" .. wp.compositor .. ".conf"
  awful.spawn(cmd, false)
end

function picom:turn_off()
  local wp = self._private
  if wp.compositor == nil then
    return
  end

  awful.spawn("pkill -f " .. wp.compositor, false)
end

function picom:toggle()
  if capi.awesome.composite_manager_running == true then
    self:turn_off()
  else
    self:turn_on()
  end
end

function picom:get_branch()
  return self._private.branch
end

function picom:get_state()
  return capi.awesome.composite_manager_running
end

local function new()
  local ret = gears.object {}
  gears.table.crush(ret, picom, true)
  ret._private = {
    compositor = "compfy"
  }
  local wp = ret._private

  awful.spawn.easy_async_with_shell(
    "command -v compfy",
    function(stdout, stderr, reason, exit_code)
      if exit_code == 0 then
        wp.compositor = "compfy"
      else
        awful.spawn.easy_async_with_shell(
          "command -v picom",
          function(stdout, stderr, reason, exit_code)
            if exit_code == 0 then
              wp.compositor = "picom"
              naughty.notification {
                title = "Missing dependency!",
                message = "Install compfy for a better compositor experience. Using picom.",
                timeout = 5
              }
            else
              wp.compositor = nil
              naughty.notification {
                title = "Missing dependency!",
                message = "Install compfy for transparency, shadows and blurs to work.",
                timeout = 5
              }
            end
          end
        )
      end
    end
  )

  ret:turn_on()

  ret._private = {}
  gears.timer.delayed_call(
    function()
      gtimer.poller {
        timeout = 2,
        callback = function()
          if ret._private.state ~= capi.awesome.composite_manager_running then
            ret:emit_signal("state", capi.awesome.composite_manager_running)
            ret._private.state = capi.awesome.composite_manager_running
          end
        end
      }
    end
  )

  return ret
end

if not instance then
  instance = new()
end
return instance
