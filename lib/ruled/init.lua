local awful = require("awful")
local ruled = require("ruled")

local windows_apps = {
  class = {"unrealeditor.exe", "UnrealEditor"}
}

ruled.client.connect_signal(
  "request::rules",
  function()
    ruled.client.append_rule {
      id = "global",
      rule = {},
      except_any = windows_apps,
      properties = {
        focus = awful.client.focus.filter,
        raise = true,
        screen = awful.screen.preferred,
        placement = awful.placement.no_overlap + awful.placement.no_offscreen,
        titlebars_enabled = true,
        honor_workarea = true,
        honor_padding = true,
        skip_decoration = false
      }
    }

    -- Dialogs
    ruled.client.append_rule {
      id = "dialog",
      rule_any = {
        type = {"dialog"},
        class = {"Wicd-client.py", "calendar.google.com", "xdman-Main"}
      },
      except_any = windows_apps,
      properties = {
        titlebars_enabled = false,
        floating = true,
        above = true,
        ontop = true,
        skip_decoration = true,
        placement = awful.placement.centered
      }
    }

    -- Modals
    ruled.client.append_rule {
      id = "modal",
      rule_any = {
        type = {"modal"}
      },
      except_any = windows_apps,
      properties = {
        titlebars_enabled = true,
        floating = true,
        above = true,
        skip_decoration = true,
        placement = awful.placement.centered
      }
    }

    -- Utilities
    ruled.client.append_rule {
      id = "utility",
      rule_any = {
        type = {"utility"}
      },
      except_any = windows_apps,
      properties = {
        titlebars_enabled = false,
        floating = true,
        skip_decoration = true,
        placement = awful.placement.centered
      }
    }

    -- Splash
    ruled.client.append_rule {
      id = "splash",
      rule_any = {
        type = {"splash"},
        name = {"Discord Updater"},
        class = {"Windscribe"}
      },
      except_any = windows_apps,
      properties = {
        titlebars_enabled = false,
        round_corners = false,
        floating = true,
        above = true,
        skip_decoration = true,
        placement = awful.placement.centered
      }
    }

    ruled.client.append_rule {
      id = "terminals",
      rule_any = {
        class = {
          "URxvt",
          "XTerm",
          "UXTerm",
          "kitty",
          "K3rmit",
          "xfce4-terminal",
          "Xfce4-terminal"
        }
      },
      except_any = windows_apps,
      properties = {
        tag = "3",
        switch_to_tags = true,
        size_hints_honor = false,
        titlebars_enabled = true
      }
    }

    ruled.client.append_rule {
      rule_any = {class = {"Firefox", "Google-chrome", "Chromium"}},
      properties = {tag = "1"}
    }

    ruled.client.append_rule {
      id = "text",
      rule_any = {
        class = {
          "Geany",
          "Atom",
          "Subl3",
          "code-oss",
          "Code",
          "Code - Insiders",
          "UnrealEditor"
        },
        name = {
          "LibreOffice",
          "libreoffice"
        }
      },
      properties = {
        tag = "2",
        skip_decoration = false,
        titlebars_enabled = true
      }
    }

    ruled.client.append_rule {
      id = "unreal_editor",
      rule_any = {
        class = {
          "UnrealEditor",
          "unrealeditor.exe"
        }
      },
      properties = {
        tag = "2",
        skip_decoration = true,
        titlebars_enabled = false
      }
    }

    ruled.client.append_rule {
      id = "files",
      rule_any = {
        class = {
          "vlc",
          "Spotify",
          "dolphin",
          "ark",
          "Nemo",
          "File-roller",
          "discord",
          "Thunar"
        }
      },
      properties = {
        tag = "4",
        switch_to_tags = true
      }
    }

    ruled.client.append_rule {
      id = "multimedia",
      rule_any = {
        class = {
          "TelegramDesktop"
        }
      },
      properties = {
        tag = "5",
        switch_to_tags = true,
        placement = awful.placement.centered
      }
    }

    ruled.client.append_rule {
      id = "gaming",
      rule_any = {
        class = {
          "Wine",
          "dolphin-emu",
          "Steam",
          "dota2",
          "Citra",
          "supertuxkart"
        },
        name = {"Steam", "Elden Ring", "elden ring", "eldenring"}
      },
      properties = {
        tag = "6",
        skip_decoration = true,
        switch_to_tags = true,
        placement = awful.placement.centered
      }
    }

    ruled.client.append_rule {
      rule = {
        class = "Steam"
      },
      except = {
        name = "Steam"
      },
      properties = {
        floating = true,
        width = awful.screen.focused().geometry.width * 0.3,
        height = awful.screen.focused().geometry.height * 0.8
      }
    }

    ruled.client.append_rule {
      id = "gaming-fullscreen",
      rule_any = {
        class = {
          "dota2"
        },
        name = {"ELDEN RING"}
      },
      properties = {
        fullscreen = true
      }
    }
  end
)

ruled.notification.connect_signal(
  "request::rules",
  function()
    ruled.notification.append_rule {
      rule = {},
      properties = {
        screen = awful.screen.preferred
      }
    }
  end
)
