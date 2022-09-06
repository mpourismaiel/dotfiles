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
    bg = "#00000088",
    fg = "#ffffff"
  }

  local avatar =
    wibox.widget {
    widget = wibox.container.background,
    bg = "#ffffffff",
    shape = gears.shape.circle,
    {
      widget = wibox.widget.imagebox,
      image = config.images_dir .. "/avatar.png",
      clip_shape = gears.shape.circle,
      forced_width = config.dpi(96),
      forced_height = config.dpi(96)
    }
  }

  local username = wibox.widget.textbox()
  username:set_markup("<span font_size='24pt' color='#ffffffff'>" .. os.getenv("USER") .. "</span>")

  local text = wibox.widget.textbox()
  local text_bg =
    wibox.widget {
    layout = wibox.layout.fixed.vertical,
    {
      widget = wibox.container.background,
      bg = "#ffffff33",
      shape = gears.shape.rounded_rect,
      radius = config.dpi(6),
      {
        widget = wibox.container.margin,
        left = config.dpi(20),
        right = config.dpi(20),
        top = config.dpi(4),
        bottom = config.dpi(4),
        {
          widget = wibox.container.constraint,
          strategy = "exact",
          width = config.dpi(300),
          height = config.dpi(24),
          {
            widget = wibox.container.place,
            valign = "center",
            halign = "left",
            text
          }
        }
      }
    }
  }

  screen:setup {
    layout = wibox.layout.stack,
    {
      widget = wibox.container.place,
      valign = "center",
      halign = "center",
      {
        layout = wibox.layout.fixed.vertical,
        {
          widget = wibox.container.margin,
          bottom = config.dpi(12),
          {
            widget = wibox.container.place,
            halign = "center",
            avatar
          }
        },
        {
          widget = wibox.container.margin,
          bottom = config.dpi(12),
          {
            widget = wibox.container.place,
            halign = "center",
            username
          }
        },
        text_bg
      }
    },
    {
      widget = wibox.container.margin,
      margins = config.dpi(48),
      {
        widget = wibox.container.place,
        valign = "bottom",
        halign = "left",
        {
          layout = wibox.layout.fixed.vertical,
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
    local len = 0

    if input_password ~= nil then
      len = #input_password
    end

    for i = 1, len, 1 do
      pw = pw .. "⬤"
    end

    if pw == "" then
      text:set_markup("<span font_size='12pt' color='#ffffff99'>Please input your password...</span>")
      return
    end

    text:set_markup("<span font_size='6pt' color='#ffffffff'>" .. pw .. "</span>")
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
        if input_password == nil then
          return
        end

        -- Validate password
        local authenticated = false
        -- If lua-pam library is 'okay'
        if helpers.module_check("liblua_pam") then
          local pam = require("liblua_pam")
          authenticated = pam:auth_current_user(input_password)
        else
          awesome.emit_signal("module::lockscreen:fail")
          type_again = false
          input_password = nil
          return
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
      config.locked = true
      screen.visible = true
      input_password = nil
      type_again = true
      update_password_input()

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
      config.locked = false
      password_grabber:stop()
      input_password = nil
      screen.visible = false
    end
  )

  awesome.connect_signal(
    "module::lockscreen:fail",
    function()
      text:set_markup("<span color='#dc2626' font_size='14pt'><b>Failed to login</b></span>")

      gears.timer.start_new(
        2,
        function()
          input_password = nil
          type_again = true
          update_password_input()
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
