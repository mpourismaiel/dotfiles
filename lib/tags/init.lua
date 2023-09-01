local gears = require("gears")
local awful = require("awful")
local config = require("lib.configuration")

local tabbed = require("lib.layouts.tabbed")

tag.connect_signal(
  "request::default_layouts",
  function()
    local available_layouts = {}
    for _, layout in pairs(config.available_layouts) do
      if layout == "local-layout-tabbed" then
        table.insert(available_layouts, tabbed)
      else
        gears.debug.dump(layout)
        table.insert(available_layouts, layout)
      end
    end
    awful.layout.append_default_layouts(available_layouts)
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
