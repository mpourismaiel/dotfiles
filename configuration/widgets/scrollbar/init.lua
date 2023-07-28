-------------------------------------------
-- @author https://github.com/Kasper24
-- @copyright 2021-2022 Kasper24
-------------------------------------------
local wibox = require("wibox")
local gears = require("gears")
local theme = require("configuration.config.theme")
local setmetatable = setmetatable
local capi = {
  awesome = awesome
}

local scrollbar = {
  mt = {}
}

local function new()
  local widget =
    wibox.widget {
    widget = wibox.widget.separator,
    shape = gears.shape.rounded_rect,
    color = theme.bg_primary
  }

  return widget
end

function scrollbar.mt:__call(...)
  return new()
end

return setmetatable(scrollbar, scrollbar.mt)
