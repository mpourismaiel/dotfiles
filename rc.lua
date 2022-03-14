-- awesome_mode: api-level=4:screen=on
-- If LuaRocks is installed, make sure that packages installed through it are
-- found (e.g. lgi). If LuaRocks is not installed, do nothing.
pcall(require, "luarocks.loader")

local gears = require("gears")
local awful = require("awful")
require("awful.autofocus")

local wibox = require("wibox")
local beautiful = require("beautiful")
local naughty = require("naughty")
local ruled = require("ruled")
local menubar = require("menubar")

require("configuration.keys")
require("configuration.ruled")
local taglist = require("configuration.widgets.taglist")

naughty.connect_signal(
  "request::display_error",
  function(message, startup)
    naughty.notification {
      urgency = "critical",
      title = "Oops, an error happened" .. (startup and " during startup!" or "!"),
      message = message
    }
  end
)

beautiful.init(gears.filesystem.get_themes_dir() .. "default/theme.lua")

tag.connect_signal(
  "request::default_layouts",
  function()
    awful.layout.append_default_layouts(
      {
        awful.layout.suit.max,
        awful.layout.suit.tile,
        awful.layout.suit.floating
      }
    )
  end
)

screen.connect_signal(
  "request::wallpaper",
  function(s)
    awful.wallpaper {
      screen = s,
      widget = {
        {
          image = beautiful.wallpaper,
          upscale = true,
          downscale = true,
          widget = wibox.widget.imagebox
        },
        valign = "center",
        halign = "center",
        tiled = false,
        widget = wibox.container.tile
      }
    }
  end
)

mykeyboardlayout = awful.widget.keyboardlayout()

mytextclock = wibox.widget.textclock()

screen.connect_signal(
  "request::desktop_decoration",
  function(s)
    awful.tag({"1", "2", "3", "4", "5", "6"}, s, awful.layout.layouts[1])

    s.mylayoutbox =
      awful.widget.layoutbox {
      screen = s,
      buttons = {
        awful.button(
          {},
          1,
          function()
            awful.layout.inc(1)
          end
        ),
        awful.button(
          {},
          3,
          function()
            awful.layout.inc(-1)
          end
        ),
        awful.button(
          {},
          4,
          function()
            awful.layout.inc(-1)
          end
        ),
        awful.button(
          {},
          5,
          function()
            awful.layout.inc(1)
          end
        )
      }
    }

    s.mytasklist =
      awful.widget.tasklist {
      screen = s,
      filter = awful.widget.tasklist.filter.currenttags,
      buttons = {
        awful.button(
          {},
          1,
          function(c)
            c:activate {context = "tasklist", action = "toggle_minimization"}
          end
        ),
        awful.button(
          {},
          3,
          function()
            awful.menu.client_list {theme = {width = 250}}
          end
        ),
        awful.button(
          {},
          4,
          function()
            awful.client.focus.byidx(-1)
          end
        ),
        awful.button(
          {},
          5,
          function()
            awful.client.focus.byidx(1)
          end
        )
      }
    }

    s.mywibox =
      awful.wibar {
      position = "top",
      height = 48,
      screen = s,
      widget = {
        layout = wibox.layout.align.horizontal,
        {
          -- Left widgets
          layout = wibox.layout.fixed.horizontal,
          mylauncher,
          taglist.new(s)
        },
        s.mytasklist, -- Middle widget
        {
          -- Right widgets
          layout = wibox.layout.fixed.horizontal,
          mykeyboardlayout,
          wibox.widget.systray(),
          mytextclock,
          s.mylayoutbox
        }
      }
    }
  end
)
