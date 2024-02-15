-------------------------------------------
-- @author https://github.com/Kasper24
-- @copyright 2021-2022 Kasper24
-------------------------------------------
local capi = {
  awesome = awesome
}
local wibox = require("wibox")

local background = {
  mt = {}
}

local function new()
  local widget = wibox.container.background()

  function widget:get_type()
    return "background"
  end
  function widget:set_color(color)
    self._private.color = color
    widget:set_bg(color)
  end
  function widget:set_on_color(on_color)
    self._private.on_color = on_color
  end
  function widget:update_display_color(color)
    widget:set_bg(color)
  end

  return widget
end

function background.mt:__call(...)
  return new()
end

return setmetatable(background, background.mt)
