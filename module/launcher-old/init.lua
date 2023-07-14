local awful = require("awful")
local beautiful = require("beautiful")
local list = require("module.launcher.list")
local theme = require("configuration.config.theme")
local launcher_widget_template = require("module.launcher.widget")
local filesystem = require("gears.filesystem")
local config_dir = filesystem.get_configuration_dir()

local select_all = false
local query = nil
local selected = 1
local parent = nil

local launcher = {mt = {}}
function launcher.new(screen)
  local app_list = list({screen = awful.screen.focused()})
  local launcher = launcher_widget_template(app_list)

  local update_query_input = function()
    launcher.input_select.bg = select_all and "#0000ff" or "#00000000"
    if query == nil or query == "" then
      launcher.input:set_markup(
        "<span foreground='" .. beautiful.fg_normal .. "' font='Inter Regular 12'>Search...</span>"
      )
    else
      launcher.input:set_markup(
        "<span foreground='" .. beautiful.fg_primary .. "' font='Inter Regular 12'>" .. query .. "</span>"
      )
    end
    app_list:emit_signal("launcher:list:update", (query == nil and "" or query), 0, selected)
  end
  update_query_input()

  local reset = function()
    query = nil
    selected = 1
    page = 0
    select_all = false
    update_query_input()
  end

  local query_grabber =
    awful.keygrabber {
    auto_start = true,
    stop_event = "release",
    mask_event_callback = true,
    keybindings = {
      awful.key {
        modifiers = {"Control"},
        key = "a",
        on_press = function()
          if query == nil or select_all == true then
            return
          end

          select_all = true
          update_query_input()
        end
      }
    },
    keypressed_callback = function(self, mod, key, command)
      -- Clear input string
      if key == "Escape" then
        if select_all == true then
          select_all = false
          query = nil
          update_query_input()
          return
        end

        -- Clear input threshold
        awesome.emit_signal("launcher:hide")
        return
      end

      if key == "BackSpace" then
        if query == nil then
          return
        end

        if select_all == true then
          query = nil
          select_all = false
          update_query_input()
          return
        end

        query = query:sub(1, -2)
        update_query_input()
        return
      end

      if key == "Up" or key == "Down" or key == "Right" or key == "Left" then
        if key == "Up" then
          selected = selected - 7
        elseif key == "Down" then
          selected = selected + 7
        elseif key == "Right" then
          selected = selected + 1
        elseif key == "Left" then
          selected = selected - 1
        end
        update_query_input()
        return
      end

      -- Accept only the single charactered key
      -- Ignore 'Shift', 'Control', 'Return', 'F1', 'F2', etc., etc.
      if #key == 1 then
        if select_all == true then
          select_all = false
          query = nil
        end

        if query == nil then
          query = key
          update_query_input()
          return
        end

        query = query .. key
        update_query_input()
      end
    end,
    keyreleased_callback = function(self, mod, key, command)
      if key == "Return" then
        app_list:emit_signal("launcher:exec", parent, query, page, selected)
        awesome.emit_signal("launcher:hide")
      end
    end
  }

  awesome.connect_signal(
    "launcher:update:selected",
    function(s)
      selected = s
    end
  )

  awesome.connect_signal(
    "launcher:show",
    function()
      launcher.widget.visible = true
      query_grabber:start()
      awful.spawn("node " .. config_dir .. "module/launcher/list.js crawl " .. theme.icon_theme)
    end
  )

  awesome.connect_signal(
    "launcher:hide",
    function()
      query_grabber:stop()
      launcher.widget.visible = false
      reset()
    end
  )
end

function launcher.mt:__call(...)
  return launcher.new(...)
end

return setmetatable(launcher, launcher.mt)
