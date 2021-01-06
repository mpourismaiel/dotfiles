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
local theme_pad = awful.util.theme_functions.pad_fn
local keygrabber = require("awful.keygrabber")
local createAnimObject = require("utils.animation").createAnimObject

local margin = wibox.container.margin
local place = wibox.container.place
local background = wibox.container.background
local constraint = wibox.container.constraint
local textbox = wibox.widget.textbox
local font = awful.util.theme_functions.font_fn

local exit_screen =
  wibox {
  visible = false,
  screen = nil
}
local backdrop = wibox {type = "dock", x = 0, y = 0}
local exit_screen_grabber
local isLocked = false

function exit_screen_show(is_locked)
  isLocked = is_locked and true or false
  local s = awful.screen.focused()
  local screen_width = s.geometry.width
  local screen_height = s.geometry.height
  backdrop =
    wibox(
    {
      type = "dock",
      height = screen_height,
      width = screen_width,
      x = 0,
      y = 0,
      screen = s,
      ontop = true,
      visible = true,
      opacity = 1,
      bg = "#00000000"
    }
  )
  exit_screen =
    wibox(
    {
      x = 0,
      y = 0,
      visible = true,
      ontop = true,
      screen = s,
      type = "dock",
      height = screen_height,
      width = screen_width,
      opacity = 1,
      bg = "#12121266"
    }
  )

  createAnimObject(0.6, exit_screen, {opacity = 1}, "outCubic")
  createAnimObject(0.6, backdrop, {opacity = 1}, "outCubic")

  exit_screen_setup(s)
end

function exit_screen_hide()
  local s = awful.screen.focused()
  local screen_height = s.geometry.height
  createAnimObject(0.6, exit_screen, {opacity = 0}, "outCubic")
  createAnimObject(
    0.6,
    backdrop,
    {opacity = 0},
    "outCubic",
    function()
      backdrop.visible = false
      exit_screen.visible = false
    end
  )
  gears.timer {
    autostart = true,
    single_shot = true,
    timeout = 0.3,
    callback = function()
      awful.keygrabber.stop(exit_screen_grabber)
    end
  }
end

local widgets = {
  layout = wibox.layout.fixed.horizontal
}

function exit_button(title, command)
  local button =
    wibox.widget {
    layout = wibox.layout.stack,
    margin(textbox(markup("#00000033", markup.font("Roboto Bold 120", title))), 2, 0, 3),
    textbox(markup("#ffffff", markup.font("Roboto Bold 120", title)))
  }

  button:buttons(awful.util.table.join(awful.button({}, 1, command)))

  return margin(button, 30, 30, 0, 0)
end

local function lock_command()
  exit_screen_hide()
  gears.timer {
    autostart = true,
    single_shot = true,
    timeout = 0.3,
    callback = action_screen_toggle("show", "lock")
  }
end

local function poweroff_command()
  awful.spawn.with_shell("shutdown now")
end

local function reboot_command()
  awful.spawn.with_shell("reboot")
end

local function suspend_command()
  lock_screen_show()
  exit_screen_hide()
  awful.spawn.with_shell("systemctl suspend")
end

local function exit_command()
  awful.spawn.with_shell("rm /tmp/started")
  awesome.quit()
end

function exit_screen_setup(s)
  gears.timer {
    autostart = true,
    single_shot = true,
    timeout = 0.3,
    callback = function()
      backdrop:buttons(
        awful.util.table.join(
          awful.button(
            {},
            1,
            function()
              exit_screen_hide()
            end
          )
        )
      )

      exit_screen_grabber =
        awful.keygrabber.run(
        function(_, key, event)
          if event == "release" then
            return
          end
          if key == "Escape" or key == "q" or key == "x" then
            exit_screen_hide()
          end
        end
      )
    end
  }

  local lock = margin(isLocked and wibox.widget {} or exit_button("Lock", lock_command), 500)
  lock.opacity = 0
  local suspend = margin(exit_button("Suspend", suspend_command), 500)
  suspend.opacity = 0
  local reboot = margin(exit_button("Restart", reboot_command), 500)
  reboot.opacity = 0
  local poweroff = margin(exit_button("Shutdown", poweroff_command), 500)
  poweroff.opacity = 0
  local exit = margin(exit_button("Exit", exit_command), 500)
  exit.opacity = 0

  createAnimObject(
    0.3,
    lock,
    {left = 0, opacity = 1},
    "outCubic",
    function()
    end
  )
  createAnimObject(
    0.3,
    suspend,
    {left = 0, opacity = 1},
    "outCubic",
    function()
    end,
    0.05
  )
  createAnimObject(
    0.3,
    reboot,
    {left = 0, opacity = 1},
    "outCubic",
    function()
    end,
    0.1
  )
  createAnimObject(
    0.3,
    poweroff,
    {left = 0, opacity = 1},
    "outCubic",
    function()
    end,
    0.15
  )
  createAnimObject(
    0.3,
    exit,
    {left = 0, opacity = 1},
    "outCubic",
    function()
    end,
    0.2
  )

  exit_screen:setup(
    {
      layout = wibox.layout.flex.vertical,
      margin(
        {
          layout = wibox.layout.flex.vertical,
          lock,
          suspend,
          reboot,
          poweroff,
          exit
        },
        30
      )
    }
  )
end
