local capi = {
  awesome = awesome
}
local awful = require("awful")
local gears = require("gears")
local config_dir = gears.filesystem.get_configuration_dir()

local picom = {}
local instance = nil

function picom:turn_on()
  local cmd = "picom --config " .. config_dir .. "/lib/picom.conf"
  awful.spawn(cmd, false)
end

function picom:turn_off()
  awful.spawn("pkill -f picom", false)
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

  ret:turn_on()

  ret._private = {}
  gears.timer.delayed_call(
    function()
      gears.timer.new {
        timeout = 2,
        callback = function()
          if ret._private.state ~= capi.awesome.composite_manager_running then
            ret:emit_signal("state", capi.awesome.composite_manager_running)
            ret._private.state = capi.awesome.composite_manager_running
          end
        end,
        wake_up = true,
        autostart = true,
        single_shot = false,
        call_now = true,
        randomized = true
      }
    end
  )

  return ret
end

if not instance then
  instance = new()
end
return instance
