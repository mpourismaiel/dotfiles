local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local naughty = require("naughty")
local markup = require("lain.util.markup")
local helpers = require("helpers")
local pad = helpers.pad
local keygrabber = require("awful.keygrabber")
local createAnimObject = require("anim-object")

-- Appearance
local icon_size = beautiful.exit_screen_icon_size or 80
local text_font = beautiful.exit_screen_font or "sans 14"

-- Commands
local poweroff_command = function()
  awful.spawn.with_shell("shutdown now")
  awful.keygrabber.stop(exit_screen_grabber)
end
local reboot_command = function()
  awful.spawn.with_shell("reboot")
  awful.keygrabber.stop(exit_screen_grabber)
end
local suspend_command = function()
  awful.spawn.with_shell(string.format("%s & systemctl suspend", beautiful.lock_cmd))
  exit_screen_hide()
end
local exit_command = function()
  awful.spawn.with_shell("rm /tmp/started")
  awesome.quit()
end
local lock_command = function()
  awful.spawn.with_shell(string.format("%s", beautiful.lock_cmd))
  exit_screen_hide()
end

local username = os.getenv("USER")
-- Capitalize username
local goodbye_text = wibox.widget.textbox("Goodbye " .. username:sub(1, 1):upper() .. username:sub(2))
goodbye_text.font = beautiful.exit_screen_goodbye_font or "sans 50"
goodbye_widget = wibox.container.margin(goodbye_text, 0, 0, 0, 50)

local poweroff_icon = wibox.widget.imagebox(beautiful.icon_dir .. "/exit_screen/poweroff.png")
poweroff_icon.resize = true
poweroff_icon.forced_width = icon_size
poweroff_icon.forced_height = icon_size
local poweroff_text = wibox.widget.textbox("Poweroff")
poweroff_text.font = text_font

local poweroff =
  wibox.widget {
  {
    pad(5),
    poweroff_icon,
    pad(5),
    expand = "none",
    layout = wibox.layout.align.horizontal
  },
  pad(1),
  {
    pad(1),
    poweroff_text,
    pad(1),
    expand = "none",
    layout = wibox.layout.align.horizontal
  },
  layout = wibox.layout.fixed.vertical
}
poweroff:buttons(
  gears.table.join(
    awful.button(
      {},
      1,
      function()
        poweroff_command()
      end
    )
  )
)

local reboot_icon = wibox.widget.imagebox(beautiful.icon_dir .. "/exit_screen/reboot.png")
reboot_icon.resize = true
reboot_icon.forced_width = icon_size
reboot_icon.forced_height = icon_size
local reboot_text = wibox.widget.textbox("Reboot")
reboot_text.font = text_font

local reboot =
  wibox.widget {
  {
    pad(5),
    reboot_icon,
    pad(5),
    expand = "none",
    layout = wibox.layout.align.horizontal
  },
  pad(1),
  {
    pad(0),
    reboot_text,
    pad(0),
    expand = "none",
    layout = wibox.layout.align.horizontal
  },
  layout = wibox.layout.fixed.vertical
}
reboot:buttons(
  gears.table.join(
    awful.button(
      {},
      1,
      function()
        reboot_command()
      end
    )
  )
)

local suspend_icon = wibox.widget.imagebox(beautiful.icon_dir .. "/exit_screen/suspend.png")
suspend_icon.resize = true
suspend_icon.forced_width = icon_size
suspend_icon.forced_height = icon_size
local suspend_text = wibox.widget.textbox("Suspend")
suspend_text.font = text_font

local suspend =
  wibox.widget {
  {
    pad(5),
    suspend_icon,
    pad(5),
    expand = "none",
    layout = wibox.layout.align.horizontal
  },
  pad(1),
  {
    pad(0),
    suspend_text,
    pad(0),
    expand = "none",
    layout = wibox.layout.align.horizontal
  },
  layout = wibox.layout.fixed.vertical
}
suspend:buttons(
  gears.table.join(
    awful.button(
      {},
      1,
      function()
        suspend_command()
      end
    )
  )
)

local exit_icon = wibox.widget.imagebox(beautiful.icon_dir .. "/exit_screen/logout.png")
exit_icon.resize = true
exit_icon.forced_width = icon_size
exit_icon.forced_height = icon_size
local exit_text = wibox.widget.textbox("Exit")
exit_text.font = text_font

local exit =
  wibox.widget {
  {
    pad(5),
    exit_icon,
    pad(5),
    expand = "none",
    layout = wibox.layout.align.horizontal
  },
  pad(1),
  {
    pad(0),
    exit_text,
    pad(0),
    expand = "none",
    layout = wibox.layout.align.horizontal
  },
  layout = wibox.layout.fixed.vertical
}
exit:buttons(
  gears.table.join(
    awful.button(
      {},
      1,
      function()
        exit_command()
      end
    )
  )
)

local lock_icon = wibox.widget.imagebox(beautiful.icon_dir .. "/exit_screen/lock.png")
lock_icon.resize = true
lock_icon.forced_width = icon_size
lock_icon.forced_height = icon_size
local lock_text = wibox.widget.textbox("Lock")
lock_text.font = text_font

local lock =
  wibox.widget {
  {
    pad(5),
    lock_icon,
    pad(5),
    expand = "none",
    layout = wibox.layout.align.horizontal
  },
  pad(1),
  {
    pad(1),
    lock_text,
    pad(1),
    expand = "none",
    layout = wibox.layout.align.horizontal
  },
  layout = wibox.layout.fixed.vertical
}
lock:buttons(
  gears.table.join(
    awful.button(
      {},
      1,
      function()
        lock_command()
      end
    )
  )
)

local exit_screen_grabber
local exit_screen
function exit_screen_hide()
  awful.keygrabber.stop(exit_screen_grabber)
  exit_screen.visible = false
end
function exit_screen_show()
  local s = awful.screen.focused()

  -- Get screen geometry
  local screen_width = s.geometry.width
  local screen_height = s.geometry.height

  -- Create the widget
  exit_screen =
    wibox(
    {
      x = 0,
      y = 0,
      visible = false,
      ontop = true,
      screen = s,
      type = "dock",
      height = screen_height,
      width = screen_width
    }
  )

  -- Set widget colors
  exit_screen.bg = "#151515d6"
  exit_screen.fg = "#FEFEFE"

  exit_screen_setup()

  -- naughty.notify({text = "starting the keygrabber"})
  exit_screen_grabber =
    awful.keygrabber.run(
    function(_, key, event)
      if event == "release" then
        return
      end

      if key == "s" then
        suspend_command()
      elseif key == "e" then
        exit_command()
      elseif key == "l" then
        lock_command()
      elseif key == "p" then
        poweroff_command()
      elseif key == "r" then
        reboot_command()
      elseif key == "Escape" or key == "q" or key == "x" then
        exit_screen_hide()
      -- else awful.keygrabber.stop(exit_screen_grabber)
      end
    end
  )
  exit_screen.visible = true
end

function exit_screen_setup()
  exit_screen:buttons(
    gears.table.join(
      -- Middle click - Hide exit_screen
      awful.button(
        {},
        2,
        function()
          exit_screen_hide()
        end
      ),
      -- Right click - Hide exit_screen
      awful.button(
        {},
        3,
        function()
          exit_screen_hide()
        end
      )
    )
  )

  -- Item placement
  exit_screen:setup {
    pad(0),
    {
      {
        pad(0),
        goodbye_widget,
        pad(0),
        expand = "none",
        layout = wibox.layout.align.horizontal
      },
      {
        pad(0),
        {
          -- {
          poweroff,
          pad(3),
          reboot,
          pad(3),
          suspend,
          pad(3),
          exit,
          pad(3),
          lock,
          layout = wibox.layout.fixed.horizontal
          -- },
          -- widget = exit_screen_box
        },
        pad(0),
        expand = "none",
        layout = wibox.layout.align.horizontal
        -- layout = wibox.layout.fixed.horizontal
      },
      layout = wibox.layout.fixed.vertical
    },
    pad(0),
    expand = "none",
    layout = wibox.layout.align.vertical
  }
end
