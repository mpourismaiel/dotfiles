local awful = require("awful")
local wibox = require("wibox")
local naughty = require("naughty")
local gears = require("gears")
local markup = require("lain.util.markup")
local menu = require("menus.menu")
local createAnimObject = require("utils.animation").createAnimObject
local margin = wibox.container.margin
local background = wibox.container.background
local text = wibox.widget.textbox
local textclock = wibox.widget.textclock
local place = wibox.container.place
local constraint = wibox.container.constraint

local exit_menu = {}

local function action_button(text, callback)
  local widget =
    constraint(
    place(
      margin(
        wibox.widget {
          layout = wibox.layout.stack,
          margin(wibox.widget.textbox(markup("#ffffff33", markup.font("Roboto Bold 28", text))), 2, 0, 2),
          wibox.widget.textbox(markup("#ffffff", markup.font("Roboto Bold 28", text)))
        },
        15,
        15
      ),
      "left"
    ),
    "exact",
    200,
    50
  )
  widget:buttons(gears.table.join(awful.button({}, 1, callback)))
  return widget
end

function worker()
  local function poweroff_command()
    awful.spawn.with_shell("shutdown now")
  end
  local function reboot_command()
    awful.spawn.with_shell("reboot")
  end
  local function suspend_command()
    lock_screen_show()
    exit_menu.hide()
    awful.spawn.with_shell("systemctl suspend")
  end
  local function exit_command()
    awful.spawn.with_shell("rm /tmp/started")
    awesome.quit()
  end

  local exit_actions = {
    s = poweroff_command,
    e = exit_command,
    p = poweroff_command,
    r = reboot_command,
    Return = function()
      exit_menu.hide()
    end,
    Escape = function()
      exit_menu.hide()
    end,
    q = function()
      exit_menu.hide()
    end
  }

  local parse_exit_action = function(_, stop_key)
    if exit_actions[stop_key] ~= nil then
      exit_actions[stop_key]()
    end
  end

  local exit_menu_grabber =
    awful.keygrabber {
    stop_key = gears.table.keys(exit_actions),
    stop_callback = parse_exit_action
  }

  local poweroff = action_button("Poweroff", poweroff_command)
  local reboot = action_button("Reboot", reboot_command)
  local suspend = action_button("Suspend", suspend_command)
  local exit = action_button("Exit", exit_command)

  return menu(
    {
      menus = {poweroff, reboot, suspend, exit},
      show = function()
        exit_menu_grabber:start()
      end,
      hide = function()
        exit_menu_grabber:stop()
      end
    }
  )
end

return setmetatable(
  exit_menu,
  {
    __call = function(_, ...)
      return worker(...)
    end
  }
)
