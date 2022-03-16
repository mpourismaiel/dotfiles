local wibox = require("wibox")
local gears = require("gears")
local config = require("configuration.config")

local container = {mt = {}}

function container.new(w)
  return wibox.widget {
    widget = wibox.container.background,
    bg = "#55555560",
    shape = gears.shape.rounded_rect,
    {
      widget = wibox.container.margin,
      margins = config.dpi(16),
      w
    }
  }
end

function container.mt:__call(...)
  return container.new(...)
end

return setmetatable(container, container.mt)
