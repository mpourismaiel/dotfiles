local gears = require("gears")
local naughty = require("naughty")
local awful = require("awful")
local console = require("lib.helpers.console")
local inotify = require("lib.helpers.inotify")
local filesystem = require("external.filesystem")

local instance = nil
local display = {}

function display:update_list()
  local wp = self._private
  wp.list = {}
  filesystem.list_contents(
    wp.autorandr_storage,
    function(err, list)
      if err ~= nil then
        console():title("display:update_list"):log("error: " .. err)
      end

      for _, file in ipairs(list) do
        if file:get_file_type() == "DIRECTORY" then
          table.insert(
            wp.list,
            {
              active = wp.default_display == file:get_name(),
              title = file:get_name()
            }
          )
        end
      end

      self:emit_signal("property::list", wp.list)
    end
  )
end

function display:startup()
  local wp = self._private
  if wp.startup_tries > 5 then
    return
  end

  awful.spawn.with_line_callback(
    "autorandr --current",
    {
      stdout = function(line)
        wp.default_display = line
        self:emit_signal("default::display", line)

        self:update_list()
        inotify:watch(
          wp.autorandr_storage,
          {
            inotify.events.create,
            inotify.events.modify,
            inotify.events.delete,
            inotify.events.moved_from,
            inotify.events.moved_to,
            inotify.events.move_self,
            inotify.events.delete_self,
            inotify.events.attrib
          }
        ):connect_signal(
          "event",
          function()
            self:update_list()
          end
        )
      end,
      stderr = function(line)
        wp.timer =
          gears.timer {
          timeout = 1,
          autostart = true,
          single_shot = true,
          callback = function()
            wp.startup_tries = wp.startup_tries + 1
            self:startup()
          end
        }
      end
    }
  )
end

local function new()
  local ret = gears.object()
  ret._private = {}
  gears.table.crush(ret, display)

  local wp = ret._private
  wp.timer = nil
  wp.startup_tries = 0
  wp.default_display = nil
  wp.autorandr_storage = os.getenv("HOME") .. "/.config/autorandr"
  wp.list = {}

  ret:startup()

  return ret
end

if not instance then
  instance = new()
end
return instance
