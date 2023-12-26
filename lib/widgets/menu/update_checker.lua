local naughty = require("naughty")
local wibox = require("wibox")
local gears = require("gears")
local gtimer = require("gears.timer")
local awful = require("awful")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")
local wtext = require("lib.widgets.text")
local wbutton = require("lib.widgets.button")
local store = require("lib.module.store")

local store_update_count = store("update_count", {value = nil})
local store_last_checked = store("last_checked", {value = nil})
local empty_message = "No packages to update"
local error_message = "Error checking for updates"
local update_checker = {mt = {}}
local instance = nil

local function get_update_count_cmd()
  local package_managers = {
    arch = "checkupdates | wc -l",
    debian = "apt list --upgradable | grep -c upgradable"
    -- Add other package managers as needed
  }

  -- Detect package manager based on OS
  local os = io.popen("cat /etc/os-release | grep ^ID= | cut -d '=' -f 2"):read("*a"):gsub("\n", "")
  return package_managers[os]
end

local function fetch_updates()
  gtimer.delayed_call(
    function()
      local cmd = get_update_count_cmd()
      if cmd then
        ---@diagnostic disable-next-line: need-check-nil, undefined-field
        instance:update_widget("Loading")
        awful.spawn.easy_async_with_shell(
          cmd,
          function(stdout)
            local update_count = tonumber(stdout) or 0
            -- Store the count and the current time
            store_update_count:set("value", update_count)
            store_last_checked:set("value", os.time())
            ---@diagnostic disable-next-line: need-check-nil, undefined-field
            instance:update_widget(update_count == 0 and empty_message or update_count)
          end
        )
      else
        ---@diagnostic disable-next-line: need-check-nil, undefined-field
        instance:update_widget(error_message) -- Unsupported system
      end
    end
  )
end

local function should_fetch()
  local last_checked = store_last_checked:get("value") or 0
  return os.time() - last_checked > (12 * 60 * 60) -- 12 hours
end

function update_checker:new()
  local ret =
    wibox.widget {
    widget = wbutton,
    strategy = "exact",
    bg_normal = theme.bg_secondary,
    halign = "left",
    callback = function()
      fetch_updates()
    end,
    shape = "rectangle",
    paddings = 0,
    {
      widget = wibox.container.place,
      {
        widget = wtext,
        text = empty_message,
        foreground = theme.fg_inactive,
        id = "text_role"
      }
    }
  }

  gears.table.crush(ret, self)

  function ret:update_widget(count)
    local widget = self:get_children_by_id("text_role")[1]
    -- check if count is number and is more than 0
    if type(count) == "number" and count > 0 then
      widget.foreground = theme.fg_normal
      widget:set_text(tostring(count) .. " updates")

      if count > 100 then
        naughty.notify {
          title = "Updates available",
          text = "There are " .. count .. " updates available",
          preset = naughty.config.presets.critical,
          timeout = 10
        }
      end
    else
      widget.foreground = theme.fg_inactive
      widget:set_text(tostring(count))
    end
  end

  if should_fetch() then
    fetch_updates() -- Initial check for updates
  else
    local count = store_update_count:get("value") or empty_message
    ret:update_widget(count) -- Use cached count
  end

  -- Setup a timer to periodically check updates (twice a day)
  gears.timer {
    timeout = 12 * 60 * 60,
    autostart = true,
    callback = function()
      if should_fetch() then
        fetch_updates()
      end
    end
  }

  return ret
end

if not instance then
  instance = update_checker:new()
end

return instance
