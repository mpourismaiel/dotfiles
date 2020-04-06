local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local naughty = require("naughty")
local lain = require("lain")
local http = require("socket.http")
local json = require("json")
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
local icon = awful.util.theme_functions.icon_fn("#ffffffcc")
local font = awful.util.theme_functions.font_fn

local action_screen =
  wibox {
  visible = false,
  screen = nil
}

local info_image = function(icon)
  return margin(
    place(constraint(imagebox(awful.util.theme_functions.icon_dir .. "/" .. icon), "max", 24, 24)),
    0,
    0,
    0,
    10
  )
end

local lock_image = imagebox(awful.util.theme_functions.icon_dir .. "/lock.svg")
local lock_icon =
  background(
  margin(
    wibox.widget {
      layout = wibox.layout.align.horizontal,
      constraint(lock_image, "max", 50, 50)
    },
    30,
    30,
    20,
    20
  ),
  "#000000",
  function(cr, width, height)
    gears.shape.rounded_rect(cr, width, height, 8)
  end
)

function reset_indicator()
  lock_image.image = awful.util.theme_functions.icon_dir .. "/lock.svg"
  lock_icon.bg = "#000000"
end

local reset_indicator_timer =
  gears.timer {
  timeout = 0.1,
  callback = reset_indicator
}

local time_text = textclock(markup("#000000", markup.font("SourceCodePro Semibold 110", "%H:%M")))
local date_text = textclock(markup("#000000", markup.font("SourceCodePro 21", "%a\n%b %d\n%Y")))

local time = nil

local battery_text =
  lain.widget.bat(
  {
    notify = "off",
    settings = function()
      widget:set_markup(markup("#FFFFFF", markup.font("SourceCodePro 12", bat_now.perc .. "%")))
    end
  }
).widget

local battery =
  wibox.widget {
  layout = wibox.layout.align.vertical,
  info_image("battery.svg"),
  place(battery_text)
}

local keyboard_layout =
  wibox.widget {
  layout = wibox.layout.align.vertical,
  info_image("keyboard.svg"),
  place(layout_indicator())
}

local github_notification_count = text(markup("#FFFFFF", markup.font("SourceCodePro 12", "...")))

if awful.util.theme_functions.set_github_listener then
  awful.util.theme_functions.set_github_listener(
    function(text)
      github_notification_count:set_markup(
        markup("#FFFFFF", markup.font("SourceCodePro 12", text == "" and "0" or text))
      )
    end
  )
end

local github_notifications =
  wibox.widget {
  layout = wibox.layout.align.vertical,
  info_image("github.svg"),
  place(github_notification_count)
}

local cpu =
  lain.widget.cpu(
  {
    settings = function()
      widget:set_markup(markup("#FFFFFF", markup.font("SourceCodePro 12", cpu_now.usage .. "%")))
    end
  }
)

local cpu_info =
  wibox.widget {
  layout = wibox.layout.align.vertical,
  info_image("cpu.svg"),
  place(cpu.widget)
}

local mem =
  lain.widget.mem(
  {
    timeout = 1,
    settings = function()
      widget:set_markup(markup("#FFFFFF", markup.font("SourceCodePro 12", mem_now.perc .. "%")))
    end
  }
)

local mem_info =
  wibox.widget {
  layout = wibox.layout.align.vertical,
  info_image("ram.svg"),
  place(mem.widget)
}

local audio_volume =
  lain.widget.alsa(
  {
    settings = function()
      local vlevel = ""
      if volume_now.status == "on" then
        vlevel = markup.font("SourceCodePro 12", volume_now.level .. "%")
      else
        vlevel = markup.font("SourceCodePro 12", "0%")
      end
      widget:set_markup(markup("#FFFFFF", vlevel))
    end
  }
).widget

local audio =
  wibox.widget {
  layout = wibox.layout.align.vertical,
  info_image("speaker.svg"),
  place(audio_volume)
}

audio:connect_signal("button::press", helpers.audio.mute)

function lock_screen_setup()
  time =
    margin(
    wibox.widget {
      layout = wibox.layout.stack,
      margin(
        background(
          margin(pad(0), 400, 0, 137),
          "#ffffff",
          function(cr, width, height)
            gears.shape.rounded_rect(cr, width, 137, 8)
          end
        ),
        0,
        0,
        40
      ),
      {
        layout = wibox.layout.align.horizontal,
        margin(
          wibox.widget {
            layout = wibox.layout.align.horizontal,
            time_text,
            margin(date_text, 10, 0, 10)
          },
          25,
          25,
          10,
          0
        )
      }
    }
  )

  action_screen:setup {
    layout = wibox.layout.flex.vertical,
    background(
      wibox.widget {
        layout = wibox.layout.flex.horizontal,
        place(
          wibox.widget {
            layout = wibox.layout.align.vertical,
            time,
            {
              layout = wibox.layout.align.horizontal,
              margin(lock_icon, 0, 10),
              background(
                margin(
                  wibox.widget {
                    layout = wibox.layout.flex.horizontal,
                    battery,
                    keyboard_layout,
                    github_notifications,
                    audio,
                    cpu_info,
                    mem_info
                  },
                  40,
                  40,
                  20,
                  20
                ),
                "#000000",
                function(cr, width, height)
                  gears.shape.rounded_rect(cr, width, height, 8)
                end
              )
            }
          },
          "center",
          "center"
        )
      },
      "#000000b3"
    )
  }
end

local locked_keygrabber = awful.keygrabber {}

function authenticate(self, sequence)
  local username = os.getenv("USER")

  reset_indicator_timer:stop()
  locked_keygrabber:start()

  if string.len(sequence) <= 1 then
    locked_keygrabber:stop()
    self:start()
    return
  end

  lock_icon.bg = "#ffffff22"

  awful.spawn.with_line_callback(
    os.getenv("HOME") .. "/bin/auth " .. username .. " " .. sequence,
    {
      exit = function(_, code)
        if code ~= 0 then
          locked_keygrabber:stop()
          self:start()
          lock_icon.bg = "#ff000088"
          gears.timer {
            timeout = 0.5,
            autostart = true,
            single_shot = true,
            callback = function()
              lock_icon.bg = "#000000"
            end
          }
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
    awful.key {
      modifiers = {},
      key = "Escape",
      on_press = function()
        lock_screen_grabber:start()
      end
    },
    awful.key {modifiers = {awful.util.altkey}, key = "m", on_press = helpers.audio.mute}
  },
  keyreleased_callback = function()
    lock_icon.bg = "#ffffff22"
    reset_indicator_timer:again()
  end,
  stop_key = "Return",
  stop_event = "release",
  start_callback = function()
    reset_indicator()
  end,
  stop_callback = function(self, stop_key, stop_mods, sequence)
    authenticate(self, sequence)
  end
}

function lock_screen_show()
  lock_icon.bg = "#ff000088"
  gears.timer {
    timeout = 0.5,
    autostart = true,
    single_shot = true,
    callback = function()
      lock_screen_grabber:start()
      lock_icon.bg = "#000000"
    end
  }

  lock_screen_setup()
  time.bottom = 100
  createAnimObject(3, time, {bottom = 0}, "outCubic")
end

function lock_screen_hide()
  createAnimObject(3, time, {bottom = 100}, "outCubic")
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

local poweroff =
  action_button(awful.util.theme_functions.icon_dir .. "/exit_screen/poweroff.png", "Poweroff", poweroff_command)
local reboot = action_button(awful.util.theme_functions.icon_dir .. "/exit_screen/reboot.png", "Reboot", reboot_command)
local suspend =
  action_button(awful.util.theme_functions.icon_dir .. "/exit_screen/suspend.png", "Suspend", suspend_command)
local exit = action_button(awful.util.theme_functions.icon_dir .. "/exit_screen/logout.png", "Exit", exit_command)
local lock = action_button(awful.util.theme_functions.icon_dir .. "/exit_screen/lock.png", "Lock", lock_command)

local spacing = margin(text(), 0, 0)
local buttons = {
  -- {
  poweroff,
  spacing,
  reboot,
  spacing,
  suspend,
  spacing,
  exit,
  spacing,
  lock,
  layout = wibox.layout.fixed.horizontal
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
          bgimage = awful.util.wallpaper.lockscreen
        }
      )

      if screen == "lock" then
        lock_screen_show()
      else
        exit_screen_show()
      end

      createAnimObject(3, action_screen, {opacity = 1}, "outCubic")
    end
  end
end
