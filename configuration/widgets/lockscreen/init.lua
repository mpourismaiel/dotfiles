local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local config = require("configuration.config")
local helpers = require("module.helpers")

local lockscreen = {mt = {}}

function lockscreen.new(s)
  local screen =
    wibox {
    screen = s,
    visible = false,
    ontop = true,
    type = "splash",
    width = s.geometry.width,
    height = s.geometry.height,
    bg = "",
    fg = "#ffffff"
  }

  local text = wibox.widget.textbox()
  screen:setup {
    layout = wibox.layout.stack,
    {
      widget = wibox.container.margin,
      margins = config.dpi(48),
      {
        widget = wibox.container.place,
        valign = "bottom",
        halign = "left",
        {
          layout = wibox.layout.fixed.vertical,
          text,
          {
            widget = wibox.container.place,
            halign = "center",
            valign = "bottom",
            require("configuration.widgets.lockscreen.clock")()
          },
          {
            widget = wibox.container.place,
            halign = "center",
            valign = "top",
            require("configuration.widgets.lockscreen.date")()
          }
        }
      }
    }
  }

  local update_password_input = function()
    local pw = ""
    for i = 1, #input_password, 1 do
      pw = pw .. "⬤"
    end
    text:set_markup("<span font_size='8pt'>" .. pw .. "</span>")
  end

  local type_again = true
  local password_grabber =
    awful.keygrabber {
    auto_start = true,
    stop_event = "release",
    mask_event_callback = true,
    keybindings = {
      awful.key {
        modifiers = {"Control"},
        key = "u",
        on_press = function()
          input_password = nil
        end
      }
    },
    keypressed_callback = function(self, mod, key, command)
      if not type_again then
        return
      end

      -- Clear input string
      if key == "Escape" then
        -- Clear input threshold
        input_password = nil
        return
      end

      if key == "BackSpace" then
        if input_password == nil then
          return
        end
        input_password = input_password:sub(1, -2)
        update_password_input()
        return
      end

      -- Accept only the single charactered key
      -- Ignore 'Shift', 'Control', 'Return', 'F1', 'F2', etc., etc.
      if #key == 1 then
        if input_password == nil then
          input_password = key
          update_password_input()
          return
        end
        input_password = input_password .. key
        update_password_input()
      end
    end,
    keyreleased_callback = function(self, mod, key, command)
      if not type_again then
        return
      end

      -- Validation
      if key == "Return" then
        -- Validate password
        local authenticated = false
        if input_password ~= nil then
          -- If lua-pam library is 'okay'
          if helpers.module_check("liblua_pam") then
            local pam = require("liblua_pam")
            authenticated = pam:auth_current_user(input_password)
          else
            text:set_markup("<span color='#ff0000' font_size='14pt'>no liblua</span>")
            awesome.emit_signal("module::lockscreen:fail")
            type_again = false
            input_password = nil
            return
          end
        end

        if authenticated then
          self:stop()
          awesome.emit_signal("module::lockscreen:hide")
        else
          text:set_markup("<span color='#ff0000' font_size='14pt'>Failed to login</span>")
          awesome.emit_signal("module::lockscreen:fail")
        end

        -- Allow typing again and empty password container
        type_again = false
        input_password = nil
      end
    end
  }

  awesome.connect_signal(
    "module::lockscreen:show",
    function()
      screen.visible = true

      gears.timer.start_new(
        0.5,
        function()
          -- Start key grabbing for password
          password_grabber:start()
        end
      )
    end
  )

  awesome.connect_signal(
    "module::lockscreen:hide",
    function()
      password_grabber:stop()
      screen.visible = false
    end
  )

  awesome.connect_signal(
    "module::lockscreen:fail",
    function()
      gears.timer.start_new(
        1,
        function()
          input_password = nil
          type_again = true
        end
      )
    end
  )
end

screen.connect_signal(
  "request::desktop_decoration",
  function(s)
    lockscreen.new(s)
  end
)
