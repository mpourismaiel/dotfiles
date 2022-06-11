local wibox = require("wibox")
local gears = require("gears")
local awful = require("awful")
local theme = require("configuration.config.theme")
local config = require("configuration.config")

local osd = {}

function osd.create(w)
  local osd =
    awful.popup {
    widget = {},
    type = "normal",
    width = theme.osd_width,
    height = theme.osd_height,
    screen = awful.screen.focused(),
    ontop = true,
    visible = false,
    shape = gears.shape.rounded_rect,
    bg = "#44444430",
    placement = function(c)
      return awful.placement.right(
        c,
        {
          margins = {
            right = config.dpi(24)
          }
        }
      )
    end
  }

  osd:setup {
    widget = wibox.container.constraint,
    strategy = "exact",
    width = theme.osd_width,
    height = theme.osd_height,
    w
  }

  return osd
end

return osd
