local wibox = require("wibox")
local gears = require("gears")
local config = require("configuration.config")

local menu_column = {mt = {}}

function menu_column.new(screen, w)
  return wibox.widget {
    widget = wibox.container.constraint,
    width = config.dpi(400),
    height = screen.geometry.height - config.dpi(16),
    strategy = "exact",
    {
      widget = wibox.container.background,
      bg = "#181818f0",
      shape = gears.shape.rounded_rect,
      {
        widget = wibox.container.margin,
        margins = config.dpi(16),
        w
      }
    }
  }
end

function menu_column.mt:__call(...)
  return menu_column.new(...)
end

return setmetatable(menu_column, menu_column.mt)
