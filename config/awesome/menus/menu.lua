local awful = require("awful")
local wibox = require("wibox")
local naughty = require("naughty")
local gears = require("gears")
local createAnimObject = require("utils.animation").createAnimObject

local function worker(args)
  local menu = {}
  local menus = {}
  for _, item in ipairs(args.menus or {}) do
    local widget = wibox.container.margin(item)
    widget.opacity = 0
    widget.top = 10
    menus[#menus + 1] = widget
  end

  menu.backdrop =
    wibox {
    x = 0,
    y = 0,
    opacity = 0,
    visible = false,
    ontop = true,
    bg = "#00000033"
  }

  menu.widget =
    awful.popup {
    ontop = true,
    visible = false,
    offset = {y = 5},
    bg = "#00000000",
    widget = wibox.widget(
      gears.table.crush(
        {
          layout = wibox.layout.fixed.vertical
        },
        menus
      )
    )
  }

  function menu.show()
    if args.show ~= nil then
      args.show()
    end
    local s = awful.screen.focused()
    local screen_width = s.geometry.width
    local screen_height = s.geometry.height

    menu.backdrop.screen = s
    menu.backdrop.width = screen_width
    menu.backdrop.height = screen_height
    menu.backdrop.visible = true

    menu.widget.screen = s
    awful.placement.bottom_left(menu.widget, {margins = {bottom = 60, left = 0}, parent = s})
    menu.widget.visible = true
    createAnimObject(1, menu.widget, {opacity = 1}, "outCubic")
    createAnimObject(1, menu.backdrop, {opacity = 1}, "outCubic")
    for delay, item in ipairs(menus) do
      -- createAnimObject(3, item, {opacity = 1, top = 0}, "outCubic", delay / 10)
      item.opacity = 1
      item.top = 0
    end
  end

  function menu.hide()
    if args.hide ~= nil then
      args.hide()
    end
    menu.backdrop.visible = false
    menu.widget.visible = false
    createAnimObject(1, menu.widget, {opacity = 0}, "outCubic")
    createAnimObject(1, menu.backdrop, {opacity = 0}, "outCubic")
    for _, item in ipairs(menus) do
      item.opacity = 0
      item.top = 10
    end
  end

  menu.backdrop:buttons(gears.table.join(awful.button({}, 1, menu.hide)))

  return menu
end

return setmetatable(
  {},
  {
    __call = function(_, ...)
      return worker(...)
    end
  }
)
