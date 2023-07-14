local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local beautiful = require("beautiful")
local config = require("configuration.config")
local helpers = require("module.helpers")
local global_state = require("configuration.config.global_state")

local lockscreen = {mt = {}}

function lockscreen.new(s)
  global_state.cache.set("lockscreen", false)

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

  local notifications_count = wibox.widget.textbox()
  notifications_count.update_text = function(n)
    if n > 0 then
      notifications_count:set_markup(
        "<span font='Inter' font_size='10pt' color='" .. beautiful.fg_normal .. "'>" .. n .. " New Notifications</span>"
      )
      return
    end

    notifications_count:set_markup(
      "<span font='Inter' font_size='10pt' color='" .. beautiful.fg_normal .. "'>No New Notifications</span>"
    )
  end
  global_state.cache.listen(
    "notifications",
    function()
      local n = #global_state.cache.get("notifications")
      if global_state.cache.get("lockscreen") == false then
        global_state.cache.set("lockscreen_notifications", n)
        return
      end

      local i = n - global_state.cache.get("lockscreen_notifications")
      notifications_count.update_text(i)
    end
  )

  local username = os.getenv("USER")
  local username_text = wibox.widget.textbox()
  local username_margin = config.dpi(10)
  if username == nil or username == "" then
    username_margin = 0
  else
    username_text:set_markup(
      "<span font='Inter Bold' font_size='11pt' color='" ..
        beautiful.fg_primary ..
          "'>" ..
            username:gsub(
              "(%l)(%w*)",
              function(a, b)
                return string.upper(a) .. b
              end
            ) ..
              "</span>"
    )
  end

  local text = wibox.widget.textbox()
  local text_bg =
    wibox.widget {
    layout = wibox.layout.fixed.vertical,
    {
      widget = wibox.container.background,
      bg = "#ffffff22",
      shape = gears.shape.rounded_rect,
      radius = config.dpi(6),
      {
        widget = wibox.container.margin,
        left = config.dpi(10),
        right = config.dpi(10),
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
        widget = wibox.container.background,
        shape = gears.shape.rounded_rect,
        radius = config.dpi(6),
        bg = "#ffffff22",
        {
          layout = wibox.layout.fixed.vertical,
          spacing = config.dpi(1),
          spacing_widget = wibox.widget {
            widget = wibox.widget.separator,
            color = "#ffffff22",
            forced_height = config.dpi(1)
          },
          {
            widget = wibox.container.margin,
            margins = config.dpi(10),
            {
              layout = wibox.layout.fixed.vertical,
              {
                widget = wibox.container.margin,
                bottom = username_margin,
                username_text
              },
              text_bg
            }
          },
          {
            widget = wibox.container.margin,
            margins = config.dpi(10),
            {
              layout = wibox.layout.fixed.horizontal,
              fill_space = true,
              notifications_count
            }
          }
        }
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
      text:set_markup(
        "<span font='Inter' font_size='10pt' color='" .. beautiful.fg_normal .. "'>Please input your password...</span>"
      )
      return
    end

    text:set_markup("<span font='Inter' font_size='6pt' color='" .. beautiful.fg_primary .. "'>" .. pw .. "</span>")
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
      screen.visible = true
      input_password = nil
      type_again = true
      global_state.cache.set("lockscreen", true)
      notifications_count.update_text(0)
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
      password_grabber:stop()
      input_password = nil
      screen.visible = false
      global_state.cache.set("lockscreen", false)
      global_state.cache.set("lockscreen_notifications", #global_state.cache.get("notifications"))
    end
  )

  awesome.connect_signal(
    "module::lockscreen:fail",
    function()
      text:set_markup(
        "<span font='Inter' color='" .. beautiful.fg_error .. "' font_size='10pt'><b>Failed to login</b></span>"
      )

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
