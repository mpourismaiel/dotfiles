local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local config = require("configuration.config")

local lockscreen = {mt = {}}

-- Check module if valid
local module_check = function(name)
  if package.loaded[name] then
    return true
  else
    for _, searcher in ipairs(package.searchers or package.loaders) do
      local loader = searcher(name)
      if type(loader) == "function" then
        package.preload[name] = loader
        return true
      end
    end
    return false
  end
end

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

      -- Accept only the single charactered key
      -- Ignore 'Shift', 'Control', 'Return', 'F1', 'F2', etc., etc.
      if #key == 1 then
        if input_password == nil then
          input_password = key
          text:set_markup("<span font_size='14pt'>" .. input_password .. "</span>")
          return
        end
        input_password = input_password .. key
        text:set_markup("<span font_size='14pt'>" .. input_password .. "</span>")
      end
    end,
    keyreleased_callback = function(self, mod, key, command)
      if not type_again then
        return
      end

      -- Validation
      if key == "Return" then
        if true then
          awesome.emit_signal("module::lockscreen:hide")
          self:stop()
          return
        end

        -- Validate password
        local authenticated = false
        if input_password ~= nil then
          -- If lua-pam library is 'okay'
          if module_check("liblua_pam") then
            local pam = require("liblua_pam")
            authenticated = pam:auth_current_user(input_password)
          end
        end

        if authenticated then
          self:stop()
          awesome.emit_signal("module::lockscreen:hide")
        else
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
      screen.visible = false
    end
  )

  awesome.connect_signal(
    "module::lockscreen:fail",
    function()
      gears.timer.start_new(
        1,
        function()
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
