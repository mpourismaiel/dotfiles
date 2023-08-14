-------------------------------------------
-- @author https://github.com/Kasper24
-- @copyright 2021-2022 Kasper24
-------------------------------------------
local awful = require("awful")
local gears = require("gears")
local hstring = require("lib.helpers.string")
local string = string
local ipairs = ipairs
local type = type

local inotify = {}
local instance = nil

inotify.events = {
  access = "access", -- file or directory contents were read
  modify = "modify", -- file or directory contents were written
  attrib = "attrib", -- file or directory attributes changed
  close_write = "close_write", -- file or directory closed, after being opened in writable mode
  close_nowrite = "close_nowrite", -- file or directory closed, after being opened in read-only mode
  close = "close", -- file or directory closed, regardless of read/write mode
  open = "open", -- file or directory opened
  moved_to = "moved_to", -- file or directory moved to watched directory
  moved_from = "moved_from", -- file or directory moved from watched directory
  move = "move", -- file or directory moved to or from watched directory
  move_self = "move_self", -- A watched file or directory was moved.
  create = "create", -- file or directory created within watched directory
  delete = "delete", -- file or directory deleted within watched directory
  delete_self = "delete_self", -- file or directory was deleted
  unmount = "unmount" -- file system containing file or directory unmounted
}

function inotify:watch(path, events)
  local ret = gears.object {}

  local command = string.format("inotifywait -m %s", path)
  if type(events) == "table" then
    for _, event in ipairs(events) do
      command = command .. " -e " .. event
    end
  elseif events ~= nil then
    command = command .. " -e " .. events
  end

  awful.spawn.easy_async(
    string.format("pidof -s %s", command),
    function(stdout)
      local is_running = stdout ~= ""
      if is_running == true then
        awful.spawn("pkill -f '" .. command .. "'", false)
      end

      ret.pid =
        awful.spawn.with_line_callback(
        command,
        {
          stdout = function(line)
            -- There are 2 possible print formats:
            ---- 1: When watching a directory and there's a new event on a file path_to_directory/ event file
            ---- 2: When watching a file and there's a new event path_to_file event

            -- 1:
            local event = line:match(path .. "/ (.-) ")
            if event ~= nil then
              -- 2:
              event = hstring.trim(event)
              local file = line:match(path .. "/ " .. event .. " (.*)")
              ret:emit_signal("event", event:lower(), path .. "/" .. file, file)
            else
              event = hstring.trim(line:match(path .. " (.* )"))
              ret:emit_signal("event", event:lower(), path .. "/")
            end
          end
        }
      )
    end
  )

  function ret:stop()
    awful.spawn("kill -9 " .. self.pid, false)
  end

  return ret
end

local function new()
  local ret = gears.object {}
  gears.table.crush(ret, inotify, true)

  return ret
end

if not instance then
  instance = new()
end
return instance
