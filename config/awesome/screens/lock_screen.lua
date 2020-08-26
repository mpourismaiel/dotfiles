local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local naughty = require("naughty")
local lain = require("lain")
local http = require("socket.http")
local json = require("JSON")
local ltn12 = require("ltn12")
local secrets = require("secrets")
local markup = require("lain.util.markup")
local helpers = require("utils.helpers")
local my_table = awful.util.table or gears.table
local pad = helpers.pad
local theme_pad = beautiful.pad_fn
local keygrabber = require("awful.keygrabber")
local layout_indicator = require("widgets.layout-indicator")
local createAnimObject = require("utils.animation").createAnimObject

local margin = wibox.container.margin
local background = wibox.container.background
local text = wibox.widget.textbox
local textclock = wibox.widget.textclock
local place = wibox.container.place
local constraint = wibox.container.constraint
local imagebox = wibox.widget.imagebox

-- ================== LOCK SCREEN ================== --
local font = awful.util.theme_functions.font_fn

local action_screen =
  wibox {
  visible = false,
  screen = nil
}

local password_markup = function(password, is_plain)
  return markup(
    "#555555",
    markup.font(
      "Roboto " .. (is_plain and "Light 12" or "Regular 22"),
      is_plain and password or password:gsub(".", "•")
    )
  )
end
local password_input = wibox.widget.textbox(password_markup(""))

local keyboard_layout =
  layout_indicator(
  {
    markup_fn = function(text)
      return markup("#ffffffbb", markup.font("Roboto Bold 20", string.upper(text)))
    end
  }
)

local audio_volume =
  lain.widget.alsa(
  {
    settings = function()
      local vlevel = ""
      if volume_now.status == "on" then
        local level = tonumber(volume_now.level)

        if level <= 35 then
          vlevel = ""
        elseif level <= 65 then
          vlevel = ""
        elseif level <= 100 then
          vlevel = ""
        end
      else
        vlevel = ""
      end
      widget:set_markup(
        markup("#ffffffbb", awful.util.theme_functions.icon_string({icon = vlevel, size = 24, font_weight = false}))
      )
    end
  }
).widget

local audio = audio_volume

audio:connect_signal("button::press", helpers.audio.mute)

function lock_screen_setup()
  password_input:set_markup(password_markup("Please enter your password", true))
  local user_image = wibox.widget.imagebox(os.getenv("HOME") .. "/.cache/user.jpg", true, gears.shape.circle)
  user_image.forced_width = 128
  user_image.forced_height = 128

  action_screen:setup {
    layout = wibox.layout.flex.horizontal,
    place(
      margin(
        wibox.widget {
          layout = wibox.layout.stack,
          margin(place(textclock(markup("#00000033", markup.font("Roboto Bold 150", "%H")))), 2, 0, 0, 247),
          margin(place(textclock(markup("#00000033", markup.font("Roboto Bold 150", "%M")))), 2, 0, 53),
          margin(place(textclock(markup("#ffffff", markup.font("Roboto Bold 150", "%H")))), 0, 0, 0, 250),
          margin(place(textclock(markup("#ffffff", markup.font("Roboto Bold 150", "%M")))), 0, 0, 50),
          margin(place(textclock(markup("#ffffffcc", markup.font("Roboto Thin 50", "%m/%d")))), 0, 0, 290),
          margin(place(textclock(markup("#ffffffbb", markup.font("Roboto Light 25", "%A")))), 0, 0, 400)
        },
        40
      ),
      "left",
      "bottom"
    ),
    place(
      wibox.widget {
        layout = wibox.layout.fixed.vertical,
        margin(
          {
            layout = wibox.layout.fixed.vertical,
            place(margin(user_image, 0, 0, 0, 15)),
            place(
              {
                layout = wibox.layout.stack,
                margin(text(markup("#00000033", markup.font("Roboto Regular 28", os.getenv("USER")))), 2, 0, 2),
                text(markup("#ffffff", markup.font("Roboto Regular 28", "Mahdi")))
              }
            )
          },
          0,
          0,
          0,
          15
        ),
        {
          layout = wibox.layout.stack,
          background(
            constraint(text(""), "exact", 300, 40),
            "#ffffff88",
            function(cr, w, h)
              gears.shape.rounded_rect(cr, w, h, 10)
            end
          ),
          margin(password_input, 15, 15, 0, 0),
          margin(
            place(
              text(
                markup(
                  "#555555",
                  awful.util.theme_functions.icon_string(
                    {
                      icon = "",
                      size = 18
                    }
                  )
                )
              ),
              "right",
              "center"
            ),
            0,
            15
          )
        }
      }
    ),
    place(
      margin(
        wibox.widget {
          layout = wibox.layout.fixed.horizontal,
          margin(keyboard_layout, 0, 0, 3),
          margin(audio, 20)
        },
        0,
        40,
        0,
        40
      ),
      "right",
      "bottom"
    )
  }
end

local locked_keygrabber = awful.keygrabber {}

function authenticate(self, sequence)
  local username = os.getenv("USER")

  locked_keygrabber:start()

  if string.len(sequence) <= 1 then
    gears.timer.delayed_call(
      function()
        locked_keygrabber:stop()
        self:start()
      end
    )
    password_input:set_markup(password_markup("Please enter your password", true))
    return
  end

  awful.spawn.with_line_callback(
    os.getenv("HOME") .. "/bin/auth " .. username .. " " .. sequence,
    {
      exit = function(_, code)
        password_input:set_markup(password_markup(""))
        if code ~= 0 then
          locked_keygrabber:stop()
          self:start()
          password_input:set_markup(password_markup("Authentication failed", true))
          return
        end

        locked_keygrabber:stop()
        lock_screen_hide()
      end
    }
  )
end

local lock_screen_grabber =
  awful.keygrabber {
  keybindings = {
    awful.key {modifiers = {awful.util.altkey}, key = "m", on_press = helpers.audio.mute}
  },
  keyreleased_callback = function(self)
    password_input:set_markup(password_markup(self.sequence))
    if self.sequence == "" then
      password_input:set_markup(password_markup("Please enter your password", true))
    end
  end,
  stop_key = "Return",
  stop_event = "release",
  stop_callback = function(self, stop_key, stop_mods, sequence)
    authenticate(self, sequence)
  end
}

function lock_screen_show()
  gears.timer {
    timeout = 0.5,
    autostart = true,
    single_shot = true,
    callback = function()
      lock_screen_grabber:start()
    end
  }

  lock_screen_setup()
  action_screen.bottom = 100
  createAnimObject(3, action_screen, {bottom = 0}, "outCubic")
end

function lock_screen_hide()
  createAnimObject(3, action_screen, {bottom = 100}, "outCubic")
  action_screen_toggle("hide")()
end

-- ================== EXIT SCREEN ================== --
function action_button(icon, text, callback)
  local button_icon = wibox.widget.imagebox(icon)
  button_icon.resize = true
  button_icon.forced_width = 80
  button_icon.forced_height = 80
  local button_text = wibox.widget.textbox(markup("#ffffff", text))
  button_text.font = "FiraCode Bold 14"

  local button =
    wibox.widget {
    {
      pad(5),
      button_icon,
      pad(5),
      expand = "none",
      layout = wibox.layout.align.horizontal
    },
    pad(1),
    {
      pad(1),
      button_text,
      pad(1),
      expand = "none",
      layout = wibox.layout.align.horizontal
    },
    layout = wibox.layout.fixed.vertical
  }

  button:buttons(gears.table.join(awful.button({}, 1, callback)))

  return button
end

-- Commands
local poweroff_command = function()
  awful.spawn.with_shell("shutdown now")
end
local reboot_command = function()
  awful.spawn.with_shell("reboot")
end
local suspend_command = function()
  awful.spawn.with_shell(
    string.format(
      "%s & systemctl suspend",
      function()
        lock_screen_show()
        exit_screen_hide(true)
      end
    )
  )
end
local exit_command = function()
  awful.spawn.with_shell("rm /tmp/started")
  awesome.quit()
end
local lock_command = function()
  exit_screen_hide(true)
  gears.timer {
    timeout = 0.5,
    autostart = true,
    single_shot = true,
    callback = function()
      lock_screen_show()
    end
  }
end

local exit_actions = {
  s = poweroff_command,
  e = exit_command,
  l = lock_command,
  p = poweroff_command,
  r = reboot_command,
  Return = function()
    exit_screen_hide()
  end,
  Escape = function()
    exit_screen_hide()
  end,
  q = function()
    exit_screen_hide()
  end
}

local parse_exit_action = function(_, stop_key)
  exit_actions[stop_key]()
end

local exit_screen_grabber =
  awful.keygrabber {
  stop_key = gears.table.keys(exit_actions),
  stop_callback = parse_exit_action
}

local username = os.getenv("USER")
-- Capitalize username
local goodbye_text = text(markup("#ffffff", "Goodbye " .. username:sub(1, 1):upper() .. username:sub(2)))
goodbye_text.font = "FiraCode Bold 50"
goodbye_widget = margin(goodbye_text, 0, 0, 0, 50)

local poweroff = action_button(awful.util.icons.icon_dir .. "/exit_screen/poweroff.png", "Poweroff", poweroff_command)
local reboot = action_button(awful.util.icons.icon_dir .. "/exit_screen/reboot.png", "Reboot", reboot_command)
local suspend = action_button(awful.util.icons.icon_dir .. "/exit_screen/suspend.png", "Suspend", suspend_command)
local exit = action_button(awful.util.icons.icon_dir .. "/exit_screen/logout.png", "Exit", exit_command)
local lock = action_button(awful.util.icons.icon_dir .. "/exit_screen/lock.png", "Lock", lock_command)

local spacing = margin(text(), 0, 0)
local buttons = {
  -- {
  wibox.container.margin(
    wibox.container.place(
      {
        poweroff,
        spacing,
        reboot,
        spacing,
        suspend,
        layout = wibox.layout.fixed.horizontal
      }
    ),
    0,
    0,
    0,
    10
  ),
  wibox.container.place(
    {
      exit,
      spacing,
      lock,
      layout = wibox.layout.fixed.horizontal
    }
  ),
  layout = wibox.layout.fixed.vertical
}

function exit_screen_setup()
  action_screen:setup {
    layout = wibox.layout.flex.vertical,
    background(
      wibox.widget {
        layout = wibox.layout.flex.horizontal,
        place(
          wibox.widget {
            layout = wibox.layout.align.vertical,
            margin(place(goodbye_widget, "center", "center"), 0, 0, 0, 30),
            buttons
          },
          "center",
          "center"
        )
      },
      "#000000b3"
    )
  }
end

function exit_screen_show()
  exit_screen_setup()
  exit_screen_grabber:start()

  goodbye_widget.bottom = 150
  createAnimObject(3, goodbye_widget, {bottom = 0}, "outCubic")
end

function exit_screen_hide(dont_hide_action_screen)
  createAnimObject(3, goodbye_widget, {bottom = 150}, "outCubic")

  if dont_hide_action_screen ~= true then
    action_screen_toggle("hide")()
  end
end

function action_screen_toggle(state, screen)
  screen = screen or "lock"
  state = state or "hide"

  return function()
    if state == "hide" then
      createAnimObject(3, action_screen, {opacity = 0}, "outCubic")
      gears.timer {
        timeout = 0.3,
        autostart = true,
        single_shot = true,
        callback = function()
          action_screen.visible = false
        end
      }
    else
      awful.spawn.easy_async_with_shell(
        "cat " .. os.getenv("HOME") .. "/.cache/wallpaper-lock",
        function(stdout)
          local wallpaper = string.gsub(stdout, "^%s*(.-)%s*$", "%1")

          local s = awful.screen.focused()
          local screen_width = s.geometry.width
          local screen_height = s.geometry.height

          action_screen =
            wibox(
            {
              x = 0,
              y = 0,
              opacity = 0,
              visible = true,
              ontop = true,
              screen = s,
              type = "dock",
              height = screen_height,
              width = screen_width,
              bgimage = wallpaper
            }
          )

          if screen == "lock" then
            lock_screen_show()
          else
            exit_screen_show()
          end

          createAnimObject(3, action_screen, {opacity = 1}, "outCubic")
        end
      )
    end
  end
end
