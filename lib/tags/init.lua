local awful = require("awful")
local config = require("lib.configuration")

tag.connect_signal(
  "request::default_layouts",
  function()
    awful.layout.append_default_layouts(config.available_layouts)
  end
)

screen.connect_signal(
  "request::desktop_decoration",
  function(s)
    for i, tag in pairs(config.tags) do
      if tag.layout == "local-layout-tabbed" then
        tag.layout = require("lib.layouts.tabbed")
      end

      awful.tag.add(
        i,
        {
          screen = s,
          layout = tag.layout or config.available_layouts[0],
          selected = i == 1
        }
      )
    end
  end
)
