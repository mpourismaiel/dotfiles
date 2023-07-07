local wibox = require("wibox")
local awful = require("awful")
local gears = require("gears")
local config = require("configuration.config")

local item = require("configuration.widgets.client_menu.item")

local instance = nil
local client_menu = {
  mt = {}
}

function client_menu:toggle(args)
  if self._private.visible then
    self:hide()
  else
    self:show(args)
  end
end

function client_menu:show(args)
  if self._private.visible then
    return
  end

  if not args.client then
    return
  end

  local s = args.client.screen

  self._private.visible = true
  self._private.backdrop.screen = s
  self._private.backdrop.x = args.client.screen.geometry.x
  self._private.backdrop.y = args.client.screen.geometry.y
  self._private.backdrop.width = args.client.screen.geometry.width
  self._private.backdrop.height = args.client.screen.geometry.height
  self._private.backdrop.visible = true

  local x = args.coords.x
  local y = args.coords.y
  local max_x = s.geometry.x + s.geometry.width
  local max_y = s.geometry.y + s.geometry.height

  if self._private.popup.width + x > max_x then
    self._private.popup.x = x - self._private.popup.width
  else
    self._private.popup.x = x
  end
  if self._private.popup.height + y > max_y then
    self._private.popup.y = y - self._private.popup.height
  else
    self._private.popup.y = y
  end

  self._private.popup.screen = s
  self._private.popup.visible = true
end

function client_menu:hide()
  if not self._private.visible then
    return
  end
  self._private.visible = false
  self._private.backdrop.visible = false
  self._private.popup.visible = false
end

local function new(args)
  if instance then
    return instance
  end

  args = args or {}

  local ret = {}
  ret._private = {}
  ret._private.client = args.client
  gears.table.crush(ret, args)
  gears.table.crush(ret, client_menu)

  ret._private.widget =
    wibox.widget {
    widget = wibox.container.constraint,
    width = config.dpi(300),
    strategy = "exact",
    {
      layout = wibox.layout.fixed.vertical,
      spacing_widget = wibox.widget {
        widget = wibox.widget.separator,
        orientation = "horizontal",
        forced_height = config.dpi(1),
        opacity = 1,
        color = "#000000ff"
      },
      {
        widget = item,
        {
          widget = wibox.widget.textbox,
          markup = "<span font='Inter Regular 11'>Minimize</span>"
        }
      },
      {
        widget = item,
        {
          widget = wibox.widget.textbox,
          markup = "<span font='Inter Regular 11'>Maximize</span>"
        }
      },
      {
        widget = item,
        {
          widget = wibox.widget.textbox,
          markup = "<span font='Inter Regular 11'>Close</span>"
        }
      }
    }
  }

  ret._private.backdrop =
    wibox {
    ontop = true,
    bg = "#ffffff00",
    type = "utility"
  }

  ret._private.backdrop:buttons(
    awful.util.table.join(
      awful.button(
        {},
        1,
        function()
          ret:hide()
        end
      )
    )
  )

  ret._private.popup =
    awful.popup {
    widget = ret._private.widget,
    visible = false,
    ontop = true,
    placement = awful.placement.centered,
    bg = "#00000000",
    shape = gears.shape.rounded_rect
  }

  instance = ret
  return ret
end

function client_menu.mt:__call(...)
  return new(...)
end

return setmetatable(client_menu, client_menu.mt)
