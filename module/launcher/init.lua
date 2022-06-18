local gears = require("gears")
local awful = require("awful")
local wibox = require("wibox")
local naughty = require("naughty")
local list = require("module.launcher.list")
local config = require("configuration.config")
local theme = require("configuration.config.theme")
local filesystem = require("gears.filesystem")
local config_dir = filesystem.get_configuration_dir()

local launcher = {mt = {}}
function launcher.new(screen)
  local query_input_wrapper =
    wibox.widget.base.make_widget_from_value {
    widget = wibox.container.background,
    shape = gears.shape.rounded_rect,
    bg = "#666666aa",
    border_width = config.dpi(2),
    border_color = "#eeeeee66",
    {
      widget = wibox.container.margin,
      margins = config.dpi(1),
      {
        widget = wibox.container.margin,
        left = config.dpi(16),
        right = config.dpi(16),
        {
          widget = wibox.container.constraint,
          strategy = "exact",
          height = config.dpi(40),
          width = config.dpi(400),
          {
            widget = wibox.container.background,
            bg = "#00000000",
            id = "select_box",
            {
              widget = wibox.widget.textbox,
              id = "query"
            }
          }
        }
      }
    }
  }
  local query_select_box = query_input_wrapper:get_children_by_id("select_box")[1]
  local query_input = query_input_wrapper:get_children_by_id("query")[1]

  local app_list = list({screen = awful.screen.focused()})

  local widget =
    awful.popup {
    widget = {},
    type = "normal",
    ontop = true,
    visible = false,
    shape = gears.shape.rounded_rect,
    bg = "#11111130",
    placement = awful.placement.top_left(c),
    width = awful.screen.focused().geometry.width,
    height = awful.screen.focused().geometry.height,
    screen = awful.screen.focused()
  }

  widget:setup {
    widget = wibox.container.constraint,
    strategy = "exact",
    width = awful.screen.focused().geometry.width,
    height = awful.screen.focused().geometry.height,
    {
      widget = wibox.container.place,
      halign = "center",
      valign = "top",
      {
        layout = wibox.layout.fixed.vertical,
        {
          widget = wibox.container.place,
          halign = "center",
          {
            widget = wibox.container.margin,
            top = config.dpi(100),
            query_input_wrapper
          }
        },
        {
          widget = wibox.container.margin,
          top = config.dpi(100),
          bottom = config.dpi(100),
          {
            widget = wibox.container.constraint,
            strategy = "exact",
            width = config.dpi(1200),
            {
              widget = wibox.container.place,
              halign = "center",
              app_list
            }
          }
        }
      }
    }
  }

  local select_all = false
  local query = nil
  local selected = 1

  local update_query_input = function()
    query_select_box.bg = select_all and "#0000ff" or "#00000000"
    if query == nil or query == "" then
      query_input:set_markup("<span foreground='#cccccc' font='Inter Regular 12'>Search...</span>")
    else
      query_input:set_markup("<span foreground='#ffffff' font='Inter Regular 12'>" .. query .. "</span>")
    end
    app_list:emit_signal("launcher:list:update", (query == nil and "" or query), 0, selected)
  end
  update_query_input()

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
        app_list:emit_signal("launcher:exec", query, page, selected)
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
      widget.visible = true
      query_grabber:start()
      awful.spawn("node " .. config_dir .. "module/launcher/list.js crawl " .. theme.icon_theme)
    end
  )

  awesome.connect_signal(
    "launcher:hide",
    function()
      query_grabber:stop()
      widget.visible = false
      query = nil
      selected = 0
      page = 0
      select_all = false
      update_query_input()
    end
  )
end

function launcher.mt:__call(...)
  return launcher.new(...)
end

return setmetatable(launcher, launcher.mt)
