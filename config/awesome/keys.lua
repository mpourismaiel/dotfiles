local awful = require("awful")
local gears = require("gears")
local beautiful = require("beautiful")
local naughty = require("naughty")
local hotkeys_popup = require("awful.hotkeys_popup").widget
local lain = require("lain")
local switcher = require("widgets/my-switcher")
local helpers = require("utils.helpers")
require("awful.hotkeys_popup.keys")

local modkey = awful.util.modkey
local altkey = awful.util.altkey

local taglist_buttons =
  gears.table.join(
  awful.button(
    {},
    1,
    function(t)
      t:view_only()
    end
  ),
  awful.button(
    {},
    4,
    function(t)
      awful.tag.viewidx(-1, t.screen)
    end
  ),
  awful.button(
    {},
    5,
    function(t)
      awful.tag.viewidx(1, t.screen)
    end
  )
)

local globalkeys =
  gears.table.join(
  awful.key(
    {modkey},
    "\\",
    function()
      naughty.destroy_all_notifications()
    end,
    {description = "clear notifications", group = "notification"}
  ),
  awful.key(
    {},
    "Print",
    function()
      awful.spawn.with_shell("flameshot full -c -p ~/Pictures/Screenshots")
    end,
    {description = "take a fullscreen screenshot", group = "hotkeys"}
  ),
  awful.key(
    {"Shift"},
    "Print",
    function()
      awful.spawn.with_shell("flameshot gui")
    end,
    {description = "take a screenshot", group = "hotkeys"}
  ),
  awful.key(
    {modkey, "Shift"},
    "x",
    function()
      action_screen_toggle("show", "lock")()
    end,
    {description = "lock screen", group = "hotkeys"}
  ),
  awful.key({modkey}, "r", recorder_screen_show),
  awful.key({modkey}, "/", hotkeys_popup.show_help, {description = "show help", group = "awesome"}),
  awful.key(
    {modkey},
    "Down",
    function()
      awful.client.focus.global_bydirection("down")
      if client.focus then
        client.focus:raise()
      end
    end,
    {description = "focus down", group = "client"}
  ),
  awful.key(
    {modkey},
    "Up",
    function()
      awful.client.focus.global_bydirection("up")
      if client.focus then
        client.focus:raise()
      end
    end,
    {description = "focus up", group = "client"}
  ),
  awful.key(
    {modkey},
    "Left",
    function()
      awful.client.focus.global_bydirection("left")
      if client.focus then
        client.focus:raise()
      end
    end,
    {description = "focus left", group = "client"}
  ),
  awful.key(
    {modkey},
    "Right",
    function()
      awful.client.focus.global_bydirection("right")
      if client.focus then
        client.focus:raise()
      end
    end,
    {description = "focus right", group = "client"}
  ),
  awful.key(
    {modkey, "Shift"},
    "Left",
    function()
      awful.client.swap.global_bydirection("left")
    end,
    {description = "swap with left client", group = "client"}
  ),
  awful.key(
    {modkey, "Shift"},
    "Right",
    function()
      awful.client.swap.global_bydirection("right")
    end,
    {
      description = "swap with right client",
      group = "client"
    }
  ),
  awful.key(
    {modkey, "Shift"},
    "Up",
    function()
      awful.client.swap.global_bydirection("up")
    end,
    {description = "swap with upper client", group = "client"}
  ),
  awful.key(
    {modkey, "Shift"},
    "Down",
    function()
      awful.client.swap.global_bydirection("down")
    end,
    {
      description = "swap with bottom client",
      group = "client"
    }
  ),
  awful.key(
    {modkey, "Control"},
    "Left",
    function()
      awful.screen.focus_relative(1)
    end,
    {description = "focus the next screen", group = "screen"}
  ),
  awful.key(
    {modkey, "Control"},
    "Right",
    function()
      awful.screen.focus_relative(-1)
    end,
    {description = "focus the previous screen", group = "screen"}
  ),
  awful.key(
    {modkey},
    "n",
    function()
      notification_screen_show(true)
    end,
    {description = "show launcher", group = "awesome"}
  ),
  awful.key(
    {modkey},
    "d",
    function()
      awful.spawn.with_shell("sh $HOME/.config/rofi/launchers/colorful/launcher.sh")
    end,
    {description = "show launcher", group = "awesome"}
  ),
  awful.key(
    {},
    "XF86Calculator",
    function()
      calc_screen_show()
    end,
    {description = "show launcher", group = "awesome"}
  ),
  awful.key(
    {modkey},
    "c",
    function()
      calc_screen_show()
    end,
    {description = "show launcher", group = "awesome"}
  ),
  awful.key(
    {altkey},
    "Tab",
    function()
      switcher.switch(1, "Mod1", "Alt_L", "Shift", "Tab")
    end
  ),
  awful.key(
    {altkey, "Shift"},
    "Tab",
    function()
      switcher.switch(-1, "Mod1", "Alt_L", "Shift", "Tab")
    end
  ),
  awful.key(
    {modkey},
    "Tab",
    function()
      awful.client.focus.byidx(1)
    end,
    {description = "go to next client", group = "client"}
  ),
  awful.key(
    {modkey, "Shift"},
    "Tab",
    function()
      awful.client.focus.byidx(-1)
    end,
    {description = "go to previous client", group = "client"}
  ),
  awful.key(
    {modkey},
    "b",
    function()
      for s in screen do
        s.mytagbar.visible = not s.mytagbar.visible
        s.mytasklistbar.visible = not s.mytasklistbar.visible
        s.main_bar.visible = not s.main_bar.visible
      end
    end,
    {description = "toggle wibox", group = "awesome"}
  ),
  awful.key(
    {modkey, "Shift"},
    "n",
    function()
      lain.util.add_tag()
    end,
    {description = "add new tag", group = "tag"}
  ),
  awful.key(
    {modkey},
    "Return",
    function()
      awful.spawn(awful.util.terminal)
    end,
    {description = "open a terminal", group = "launcher"}
  ),
  awful.key({modkey, "Control"}, "r", awesome.restart, {description = "reload awesome", group = "awesome"}),
  awful.key({modkey, "Shift"}, "q", exit_screen_show, {description = "show exit screen", group = "awesome"}),
  awful.key(
    {modkey, "Shift"},
    "w",
    workstation_show,
    {description = "show workstation selector screen", group = "awesome"}
  ),
  awful.key(
    {modkey},
    "s",
    function()
      info_screen_show()
    end
  ),
  awful.key(
    {modkey, "Shift", "Control"},
    "Up",
    function()
      awful.tag.incnmaster(1, nil, true)
    end,
    {
      description = "increase the number of master clients",
      group = "layout"
    }
  ),
  awful.key(
    {modkey, "Shift", "Control"},
    "Down",
    function()
      awful.tag.incnmaster(-1, nil, true)
    end,
    {
      description = "decrease the number of master clients",
      group = "layout"
    }
  ),
  awful.key(
    {modkey, "Shift", "Control"},
    "Right",
    function()
      awful.tag.incncol(1, nil, true)
    end,
    {
      description = "increase the number of columns",
      group = "layout"
    }
  ),
  awful.key(
    {modkey, "Shift", "Control"},
    "Left",
    function()
      awful.tag.incncol(-1, nil, true)
    end,
    {
      description = "decrease the number of columns",
      group = "layout"
    }
  ),
  awful.key(
    {modkey},
    "space",
    function()
      awful.layout.inc(1)
    end,
    {description = "select next", group = "layout"}
  ),
  awful.key(
    {modkey, "Shift"},
    "space",
    function()
      awful.layout.inc(-1)
    end,
    {description = "select previous", group = "layout"}
  ),
  awful.key(
    {altkey},
    "Up",
    function()
      os.execute(string.format("amixer -q set %s 5%%+", awful.util.volume.channel))
      awful.util.volume.update()
      awful.util.volume_indicator.update()
    end,
    {description = "volume up", group = "hotkeys"}
  ),
  awful.key(
    {altkey},
    "Down",
    function()
      os.execute(string.format("amixer -q set %s 5%%-", awful.util.volume.channel))
      awful.util.volume.update()
      awful.util.volume_indicator.update()
    end,
    {description = "volume down", group = "hotkeys"}
  ),
  awful.key({altkey}, "m", helpers.audio.mute, {description = "toggle mute", group = "hotkeys"})
)

for i = 1, 9 do
  local descr_view, descr_move
  if i == 1 or i == 9 then
    descr_view = {description = "view tag #", group = "tag"}
    descr_move = {
      description = "move focused client to tag #",
      group = "tag"
    }
  end
  globalkeys =
    gears.table.join(
    globalkeys,
    awful.key(
      {modkey},
      "#" .. i + 9,
      function()
        local screen = awful.screen.focused()
        local tag = screen.tags[i]
        if tag then
          tag:view_only()
        end
      end,
      descr_view
    ),
    awful.key(
      {modkey, "Shift"},
      "#" .. i + 9,
      function()
        if client.focus then
          local tag = client.focus.screen.tags[i]
          if tag then
            local rules = tag.rules
            if rules == nil or rules[client.focus.class] == true then
              client.focus:move_to_tag(tag)
            end
          end
        end
      end,
      descr_move
    )
  )
end

-- special tags
globalkeys =
  gears.table.join(
  globalkeys,
  awful.key(
    {modkey},
    "g",
    function()
      local screen = awful.screen.focused()
      local tag = screen.tags[6]
      if tag then
        tag:view_only()
      end
    end,
    descr_view
  )
)

local clientkeys =
  gears.table.join(
  awful.key(
    {modkey},
    "f",
    function(c)
      c.fullscreen = not c.fullscreen
      c:raise()
    end,
    {description = "toggle fullscreen", group = "client"}
  ),
  awful.key(
    {modkey},
    "q",
    function(c)
      c:kill()
    end,
    {description = "close", group = "client"}
  ),
  awful.key(
    {modkey, "Shift"},
    "Return",
    function(c)
      c:swap(awful.client.getmaster())
    end,
    {description = "move to master", group = "client"}
  ),
  awful.key(
    {modkey},
    "o",
    function(c)
      c:f()
    end,
    {
      description = "move to screen",
      group = "client"
    }
  ),
  awful.key(
    {modkey},
    "m",
    function(c)
      c.maximized = not c.maximized
      c:raise()
    end,
    {description = "maximize", group = "client"}
  ),
  awful.key(
    {modkey},
    "z",
    beautiful.zen_mode,
    {
      description = "zen mode",
      group = "client"
    }
  )
)

local clientbuttons =
  gears.table.join(
  awful.button(
    {},
    1,
    function(c)
      c:emit_signal("request::activate", "mouse_click", {raise = true})
    end
  ),
  awful.button(
    {modkey},
    1,
    function(c)
      c:emit_signal("request::activate", "mouse_click", {raise = true})
      awful.mouse.client.move(c)
    end
  ),
  awful.button(
    {modkey},
    3,
    function(c)
      c:emit_signal("request::activate", "mouse_click", {raise = true})
      awful.mouse.client.resize(c)
    end
  )
)

awful.util.taglist_buttons = taglist_buttons
awful.util.globalkeys = globalkeys
awful.util.clientkeys = clientkeys
awful.util.clientbuttons = clientbuttons

return {
  taglist_buttons = taglist_buttons,
  globalkeys = globalkeys,
  clientkeys = clientkeys,
  clientbuttons = clientbuttons
}
