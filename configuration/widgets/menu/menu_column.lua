local wibox = require("wibox")
local gears = require("gears")
local config = require("configuration.config")

local menu_column = {mt = {}}

local function constraint(screen, w)
  return wibox.widget {
    widget = wibox.container.constraint,
    height = screen.geometry.height - config.dpi(32),
    strategy = "exact",
    w
  }
end

local function new(screen, w, width_constraint)
  local _w =
    constraint(
    screen,
    wibox.widget {
      widget = wibox.container.background,
      bg = "#111111f0",
      shape = gears.shape.rounded_rect,
      {
        widget = wibox.container.margin,
        margins = config.dpi(16),
        w
      }
    }
  )

  if width_constraint ~= nil then
    _w.width = config.dpi(width_constraint)
  end

  return wibox.widget {
    widget = wibox.container.margin,
    left = config.dpi(16),
    top = config.dpi(16),
    bottom = config.dpi(16),
    _w
  }
end

function menu_column.mt:__call(...)
  return new(...)
end

return setmetatable(menu_column, menu_column.mt)
