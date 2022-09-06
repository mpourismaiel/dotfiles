local awful = require("awful")
local hotkeys_popup = require("awful.hotkeys_popup")
local config = require("configuration.config")
local global_state = require("configuration.config.global_state")

require("awful.hotkeys_popup.keys")

awful.keyboard.append_global_keybindings(
  {
    awful.key({config.modkey}, "s", hotkeys_popup.show_help, {description = "show help", group = "awesome"}),
    awful.key({config.modkey, "Control"}, "r", awesome.restart, {description = "reload awesome", group = "awesome"}),
    awful.key(
      {config.modkey, "Shift"},
      "q",
      function()
        awesome.emit_signal("widget::drawer:toggle")
      end,
      {description = "quit awesome", group = "awesome"}
    ),
    awful.key(
      {config.modkey},
      "Return",
      function()
        awful.spawn(config.terminal)
      end,
      {description = "open a terminal", group = "launcher"}
    ),
    awful.key(
      {config.modkey},
      "l",
      function()
        awesome.emit_signal("module::lockscreen:show")
      end,
      {description = "lock desktop", group = "launcher"}
    ),
    awful.key(
      {config.modkey},
      "b",
      function()
        global_state.bar.visible = not global_state.bar.visible
      end,
      {description = "open application drawer", group = "launcher"}
    ),
    awful.key(
      {config.modkey},
      "d",
      function()
        awful.spawn(config.commands.rofi_appmenu, false)
      end,
      {description = "open application drawer", group = "launcher"}
    ),
    awful.key(
      {config.modkey, "Shift"},
      "d",
      function()
        awesome.emit_signal("launcher:show")
      end,
      {description = "open application drawer", group = "launcher"}
    ),
    awful.key(
      {config.modkey},
      "Escape",
      function()
        awesome.emit_signal("widget::systray:toggle")
      end,
      {
        description = "toggle systray",
        group = "systray"
      }
    ),
    awful.key(
      {},
      "Print",
      function()
        awful.spawn.easy_async_with_shell(
          config.commands.full_screenshot,
          function()
          end
        )
      end,
      {description = "fullscreen screenshot", group = "Utility"}
    ),
    awful.key(
      {"Shift"},
      "Print",
      function()
        awful.spawn.easy_async_with_shell(
          config.commands.area_screenshot,
          function()
          end
        )
      end,
      {description = "area/selected screenshot", group = "Utility"}
    ),
    awful.key(
      {},
      "XF86AudioRaiseVolume",
      function()
        awful.spawn("amixer -D pulse sset Master 5%+", false)
        awesome.emit_signal("widget::volume")
      end,
      {description = "increase volume up by 5%", group = "hotkeys"}
    ),
    awful.key(
      {},
      "XF86AudioLowerVolume",
      function()
        awful.spawn("amixer -D pulse sset Master 5%-", false)
        awesome.emit_signal("widget::volume")
      end,
      {description = "decrease volume up by 5%", group = "hotkeys"}
    ),
    awful.key(
      {},
      "XF86AudioMute",
      function()
        awful.spawn("amixer -D pulse set Master 1+ toggle", false)
      end,
      {description = "toggle mute", group = "hotkeys"}
    ),
    awful.key(
      {},
      "XF86AudioNext",
      function()
        awful.spawn("playerctl next", false)
      end,
      {description = "next music", group = "hotkeys"}
    ),
    awful.key(
      {},
      "XF86AudioPrev",
      function()
        awful.spawn("playerctl previous", false)
      end,
      {description = "previous music", group = "hotkeys"}
    ),
    awful.key(
      {},
      "XF86AudioPlay",
      function()
        awful.spawn("playerctl play-pause", false)
      end,
      {description = "play/pause music", group = "hotkeys"}
    ),
    awful.key(
      {},
      "XF86AudioMicMute",
      function()
        awful.spawn("amixer set Capture toggle", false)
      end,
      {description = "mute microphone", group = "hotkeys"}
    )
  }
)

awful.keyboard.append_global_keybindings(
  {
    awful.key(
      {config.modkey},
      "Tab",
      function()
        awful.client.focus.byidx(1)
      end,
      {description = "focus next by index", group = "client"}
    ),
    awful.key(
      {config.modkey, "Shift"},
      "Tab",
      function()
        awful.client.focus.byidx(-1)
      end,
      {description = "focus previous by index", group = "client"}
    ),
    awful.key(
      {config.modkey},
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
      {config.modkey},
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
      {config.modkey},
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
      {config.modkey},
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
      {config.modkey, "Shift"},
      "Left",
      function()
        awful.client.swap.global_bydirection("left")
      end,
      {description = "swap with left client", group = "client"}
    ),
    awful.key(
      {config.modkey, "Shift"},
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
      {config.modkey, "Shift"},
      "Up",
      function()
        awful.client.swap.global_bydirection("up")
      end,
      {description = "swap with upper client", group = "client"}
    ),
    awful.key(
      {config.modkey, "Shift"},
      "Down",
      function()
        awful.client.swap.global_bydirection("down")
      end,
      {
        description = "swap with bottom client",
        group = "client"
      }
    )
  }
)

awful.keyboard.append_global_keybindings(
  {
    awful.key(
      {config.modkey},
      "u",
      awful.client.urgent.jumpto,
      {description = "jump to urgent client", group = "client"}
    ),
    awful.key(
      {config.modkey},
      "space",
      function()
        awful.layout.inc(1)
      end,
      {description = "select next", group = "layout"}
    ),
    awful.key(
      {config.modkey, "Shift"},
      "space",
      function()
        awful.layout.inc(-1)
      end,
      {description = "select previous", group = "layout"}
    )
  }
)

awful.keyboard.append_global_keybindings(
  {
    awful.key {
      modifiers = {config.modkey},
      keygroup = "numrow",
      description = "only view tag",
      group = "tag",
      on_press = function(index)
        local screen = awful.screen.focused()
        local tag = screen.tags[index]
        if tag then
          tag:view_only()
        end
      end
    },
    awful.key {
      modifiers = {config.modkey, "Shift"},
      keygroup = "numrow",
      description = "move focused client to tag",
      group = "tag",
      on_press = function(index)
        if client.focus then
          local tag = client.focus.screen.tags[index]
          if tag then
            client.focus:move_to_tag(tag)
          end
        end
      end
    }
  }
)

client.connect_signal(
  "request::default_mousebindings",
  function()
    awful.mouse.append_client_mousebindings(
      {
        awful.button(
          {},
          1,
          function(c)
            c:activate {context = "mouse_click"}
          end
        ),
        awful.button(
          {config.modkey},
          1,
          function(c)
            c:activate {context = "mouse_click", action = "mouse_move"}
          end
        ),
        awful.button(
          {config.modkey},
          3,
          function(c)
            c:activate {context = "mouse_click", action = "mouse_resize"}
          end
        )
      }
    )
  end
)

client.connect_signal(
  "request::default_keybindings",
  function()
    awful.keyboard.append_client_keybindings(
      {
        awful.key(
          {config.modkey},
          "f",
          function(c)
            c.fullscreen = not c.fullscreen
            c:raise()
          end,
          {description = "toggle fullscreen", group = "client"}
        ),
        awful.key(
          {config.modkey},
          "q",
          function(c)
            c:kill()
          end,
          {description = "close", group = "client"}
        ),
        awful.key(
          {config.modkey},
          "c",
          awful.client.floating.toggle,
          {description = "toggle floating", group = "client"}
        ),
        awful.key(
          {config.modkey},
          "t",
          function(c)
            c.ontop = not c.ontop
          end,
          {description = "toggle keep on top", group = "client"}
        ),
        awful.key(
          {config.modkey},
          "n",
          function(c)
            -- The client currently has the input focus, so it cannot be
            -- minimized, since minimized clients can't have the focus.
            c.minimized = true
          end,
          {description = "minimize", group = "client"}
        ),
        awful.key(
          {config.modkey},
          "m",
          function(c)
            c.maximized = not c.maximized
            c:raise()
          end,
          {description = "(un)maximize", group = "client"}
        )
      }
    )
  end
)
