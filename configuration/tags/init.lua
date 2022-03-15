local awful = require("awful")
local config = require("configuration/config")

screen.connect_signal(
  "request::desktop_decoration",
  function(s)
    for i, tag in pairs(config.tags) do
      awful.tag.add(
        i,
        {
          screen = s,
          name = tag.name,
          layout = tag.layout or awful.layout.suit.max
        }
      )
    end
  end
)
