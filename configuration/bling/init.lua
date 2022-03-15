local awful = require("awful")
local wibox = require("wibox")
local bling = require("bling")
local config = require("configuration.config")

bling.widget.tag_preview.enable {
  show_client_content = true, -- Whether or not to show the client content
  scale = 0.25, -- The scale of the previews compared to the screen
  honor_padding = true, -- Honor padding when creating widget size
  honor_workarea = true, -- Honor work area when creating widget size
  placement_fn = function(c) -- Place the widget using awful.placement (this overrides x & y)
    awful.placement.top_left(
      c,
      {
        margins = {
          left = config.dpi(64),
          top = config.dpi(16)
        }
      }
    )
  end,
  background_widget = wibox.widget {
    image = config.wallpaper,
    horizontal_fit_policy = "fit",
    vertical_fit_policy = "fit",
    widget = wibox.widget.imagebox
  }
}
