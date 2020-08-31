local awful = require("awful")
local beautiful = require("beautiful")

return function(keys)
  local rules = {
    {
      rule = {},
      properties = {
        border_width = beautiful.border_width,
        border_color = beautiful.border_normal,
        focus = awful.client.focus.filter,
        raise = true,
        keys = keys.clientkeys,
        buttons = keys.clientbuttons,
        screen = awful.screen.preferred,
        placement = awful.placement.no_overlap + awful.placement.no_offscreen,
        size_hints_honor = false
      }
    },
    {
      rule_any = {
        instance = {
          "DTA", -- Firefox addon DownThemAll.
          "copyq" -- Includes session name in class.
        },
        class = {
          "Arandr",
          "Gpick",
          "Sxiv",
          "Wpa_gui",
          "pinentry",
          "veromix",
          "xtightvncviewer"
        },
        name = {
          "Event Tester" -- xev.
        },
        role = {
          "pop-up" -- e.g. Google Chrome's (detached) Developer Tools.
        }
      },
      properties = {floating = true}
    },
    {
      rule_any = {type = {"dialog"}},
      properties = {titlebars_enabled = true},
      callback = function(c)
        awful.placement.centered(c, nil)
      end
    },
    {
      rule = {type = {"dialog"}, class = {"TelegramDesktop"}},
      properties = {titlebars_enabled = false},
    },
    {
      rule_any = {type = {"normal"}},
      except_any = {class = {"jetbrains-studio"}},
      properties = {titlebars_enabled = true}
    },
    {
      rule_any = {class = {"Google-chrome-beta", "firefox"}},
      properties = {
        screen = 1,
        tag = awful.util.tagnames[1],
        maximized = true
      }
    },
    {
      rule_any = {class = {"Code"}},
      properties = {
        screen = 1,
        tag = awful.util.tagnames[2],
        maximized = true
      }
    },
    {
      rule_any = {class = awful.util.variables.terminal_tag_terminals},
      properties = {screen = 1, tag = awful.util.tagnames[3], titlebars_enabled = false}
    },
    {
      rule_any = {
        class = {
          "Minecraft Launcher",
          "minecraft-launcher",
          "Minecraft 1.14.4"
        }
      },
      properties = {
        screen = 1,
        tag = awful.util.tagnames[4],
        maximized = true,
        fullscreen = true,
        focus = true,
        titlebars_enabled = true
      }
    },
    {
      rule = {class = "Steam"},
      properties = {titlebars_enabled = false}
    },
    {
      rule = {class = "TelegramDesktop"},
      properties = {screen = 1, tag = awful.util.tagnames[5]}
    },
    {
      rule = {
        class = "jetbrains-.*",
        instance = "sun-awt-X11-XWindowPeer",
        name = "win*"
      },
      properties = {
        floating = true,
        focus = true,
        focusable = false,
        ontop = true,
        placement = awful.placement.restore,
        screen = 1,
        tag = awful.util.tagnames[2],
        buttons = {},
        titlebars_enabled = true
      }
    },
    {
      rule_any = {class = {"albert"}},
      properties = {
        border_width = 0
      }
    },
    {
      rule_any = {class = {"dota2"}},
      properties = {
        screen = 1,
        tag = awful.util.tagnames[6],
        fullscreen = true
      }
    }
  }

  awful.rules.rules = rules
  return {rules = rules}
end
