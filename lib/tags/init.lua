local awful = require("awful")
local config = require("lib.config")

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
  "request::desktop_decoration",
  function(s)
    for i, tag in pairs(config.tags) do
      awful.tag.add(
        i,
        {
          screen = s,
          layout = tag.layout or awful.layout.suit.max,
          selected = i == 1
        }
      )
    end
  end
)
