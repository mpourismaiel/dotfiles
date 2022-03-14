local awful = require("awful")
local hotkeys_popup = require("awful.hotkeys_popup")
require("awful.hotkeys_popup.keys")
local config = require("configuration.config")

awful.keyboard.append_global_keybindings(
  {
    awful.key({config.modkey}, "s", hotkeys_popup.show_help, {description = "show help", group = "awesome"}),
    awful.key(
      {config.modkey},
      "w",
      function()
        mymainmenu:show()
      end,
      {description = "show main menu", group = "awesome"}
    ),
    awful.key({config.modkey, "Control"}, "r", awesome.restart, {description = "reload awesome", group = "awesome"}),
    awful.key({config.modkey, "Shift"}, "q", awesome.quit, {description = "quit awesome", group = "awesome"}),
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
      "p",
      function()
        menubar.show()
      end,
      {description = "show the menubar", group = "launcher"}
    )
  }
)

awful.keyboard.append_global_keybindings(
  {
    awful.key({config.modkey}, "Left", awful.tag.viewprev, {description = "view previous", group = "tag"}),
    awful.key({config.modkey}, "Right", awful.tag.viewnext, {description = "view next", group = "tag"}),
    awful.key({config.modkey}, "Escape", awful.tag.history.restore, {description = "go back", group = "tag"})
  }
)

awful.keyboard.append_global_keybindings(
  {
    awful.key(
      {config.modkey},
      "j",
      function()
        awful.client.focus.byidx(1)
      end,
      {description = "focus next by index", group = "client"}
    ),
    awful.key(
      {config.modkey},
      "k",
      function()
        awful.client.focus.byidx(-1)
      end,
      {description = "focus previous by index", group = "client"}
    ),
    awful.key(
      {config.modkey},
      "Tab",
      function()
        awful.client.focus.history.previous()
        if client.focus then
          client.focus:raise()
        end
      end,
      {description = "go back", group = "client"}
    ),
    awful.key(
      {config.modkey, "Control"},
      "j",
      function()
        awful.screen.focus_relative(1)
      end,
      {description = "focus the next screen", group = "screen"}
    ),
    awful.key(
      {config.modkey, "Control"},
      "k",
      function()
        awful.screen.focus_relative(-1)
      end,
      {description = "focus the previous screen", group = "screen"}
    ),
    awful.key(
      {config.modkey, "Control"},
      "n",
      function()
        local c = awful.client.restore()
        -- Focus restored client
        if c then
          c:activate {raise = true, context = "key.unminimize"}
        end
      end,
      {description = "restore minimized", group = "client"}
    )
  }
)

awful.keyboard.append_global_keybindings(
  {
    awful.key(
      {config.modkey, "Shift"},
      "j",
      function()
        awful.client.swap.byidx(1)
      end,
      {description = "swap with next client by index", group = "client"}
    ),
    awful.key(
      {config.modkey, "Shift"},
      "k",
      function()
        awful.client.swap.byidx(-1)
      end,
      {description = "swap with previous client by index", group = "client"}
    ),
    awful.key(
      {config.modkey},
      "u",
      awful.client.urgent.jumpto,
      {description = "jump to urgent client", group = "client"}
    ),
    awful.key(
      {config.modkey},
      "l",
      function()
        awful.tag.incmwfact(0.05)
      end,
      {description = "increase master width factor", group = "layout"}
    ),
    awful.key(
      {config.modkey},
      "h",
      function()
        awful.tag.incmwfact(-0.05)
      end,
      {description = "decrease master width factor", group = "layout"}
    ),
    awful.key(
      {config.modkey, "Shift"},
      "h",
      function()
        awful.tag.incnmaster(1, nil, true)
      end,
      {description = "increase the number of master clients", group = "layout"}
    ),
    awful.key(
      {config.modkey, "Shift"},
      "l",
      function()
        awful.tag.incnmaster(-1, nil, true)
      end,
      {description = "decrease the number of master clients", group = "layout"}
    ),
    awful.key(
      {config.modkey, "Control"},
      "h",
      function()
        awful.tag.incncol(1, nil, true)
      end,
      {description = "increase the number of columns", group = "layout"}
    ),
    awful.key(
      {config.modkey, "Control"},
      "l",
      function()
        awful.tag.incncol(-1, nil, true)
      end,
      {description = "decrease the number of columns", group = "layout"}
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
      modifiers = {config.modkey, "Control"},
      keygroup = "numrow",
      description = "toggle tag",
      group = "tag",
      on_press = function(index)
        local screen = awful.screen.focused()
        local tag = screen.tags[index]
        if tag then
          awful.tag.viewtoggle(tag)
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
    },
    awful.key {
      modifiers = {config.modkey, "Control", "Shift"},
      keygroup = "numrow",
      description = "toggle focused client on tag",
      group = "tag",
      on_press = function(index)
        if client.focus then
          local tag = client.focus.screen.tags[index]
          if tag then
            client.focus:toggle_tag(tag)
          end
        end
      end
    },
    awful.key {
      modifiers = {config.modkey},
      keygroup = "numpad",
      description = "select layout directly",
      group = "layout",
      on_press = function(index)
        local t = awful.screen.focused().selected_tag
        if t then
          t.layout = t.layouts[index] or t.layout
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
          {config.modkey, "Shift"},
          "c",
          function(c)
            c:kill()
          end,
          {description = "close", group = "client"}
        ),
        awful.key(
          {config.modkey, "Control"},
          "space",
          awful.client.floating.toggle,
          {description = "toggle floating", group = "client"}
        ),
        awful.key(
          {config.modkey, "Control"},
          "Return",
          function(c)
            c:swap(awful.client.getmaster())
          end,
          {description = "move to master", group = "client"}
        ),
        awful.key(
          {config.modkey},
          "o",
          function(c)
            c:move_to_screen()
          end,
          {description = "move to screen", group = "client"}
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
        ),
        awful.key(
          {config.modkey, "Control"},
          "m",
          function(c)
            c.maximized_vertical = not c.maximized_vertical
            c:raise()
          end,
          {description = "(un)maximize vertically", group = "client"}
        ),
        awful.key(
          {config.modkey, "Shift"},
          "m",
          function(c)
            c.maximized_horizontal = not c.maximized_horizontal
            c:raise()
          end,
          {description = "(un)maximize horizontally", group = "client"}
        )
      }
    )
  end
)
