local wibox = require("wibox")
local gears = require("gears")
local config = require("configuration.config")

local container = {mt = {}}

function container.new(w, padding_left, padding_right, padding_top, padding_bottom)
  return wibox.widget {
    widget = wibox.container.background,
    bg = "#30303060",
    shape = gears.shape.rounded_rect,
    {
      widget = wibox.container.margin,
      left = config.dpi(padding_left ~= nil and padding_left or 16),
      right = config.dpi(padding_right ~= nil and padding_right or 16),
      top = config.dpi(padding_top ~= nil and padding_top or 16),
      bottom = config.dpi(padding_bottom ~= nil and padding_bottom or 16),
      w
    }
  }
end

function container.mt:__call(...)
  return container.new(...)
end

return setmetatable(container, container.mt)
