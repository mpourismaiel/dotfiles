local awful = require("awful")
local beautiful = require("beautiful")
local wibox = require("wibox")
local gears = require("gears")
local naughty = require("naughty")
local lain = require("lain")
local http = require("socket.http")
local json = require("json")
local ltn12 = require("ltn12")

local markup = lain.util.markup

function setup_timer(update_function)
  local timer = gears.timer({timeout = 3})
  timer:connect_signal(
    "timeout",
    function()
      local resp = {}
      local result, status =
        http.request {
        method = "GET",
        url = "http://localhost:9102/read/5/40",
        sink = ltn12.sink.table(resp)
      }
      if (status == 200) then
        local resp_json = json.decode(table.concat(resp))
        update_function(resp_json)
      end
    end
  )
  timer:start()
  timer:emit_signal("timeout")
end

return function(update_widget)
  local clipboard = wibox.widget.base.make_widget_from_value({layout = wibox.layout.flex.vertical})

  clipboard._update_widget = update_widget
  clipboard._setup_timer = setup_timer

  local data = setmetatable({}, {__mode = "k"})
  -- clipboard._setup_timer(
  --   function(clips)
  --     clipboard._update_widget(clipboard, data, clips)
  --   end
  -- )

  return clipboard
end
