local capi = {
  screen = screen,
  tag = tag
}

local wibox = require("wibox")
local awful = require("awful")
local gears = require("gears")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")
local console = require("lib.helpers.console")

local layoutbox = {mt = {}}
local boxes = nil

local function line(width, r)
  return wibox.widget {
    widget = wibox.container.background,
    shape = function(cr, width, height)
      gears.shape.rounded_rect(cr, width, height, config.dpi(r and r or 0))
    end,
    bg = theme.fg_normal,
    {
      widget = wibox.container.constraint,
      strategy = "exact",
      width = config.dpi(width),
      height = config.dpi(2),
      {
        widget = wibox.widget.textbox,
        text = ""
      }
    }
  }
end

local layouts = {
  max = function(width)
    return wibox.widget {
      layout = wibox.layout.fixed.horizontal,
      line(width)
    }
  end,
  tile = function(width)
    return wibox.widget {
      layout = wibox.layout.fixed.horizontal,
      spacing = config.dpi(3),
      line(width / 3 * 1 - 1, 3),
      line(width / 3 * 1 - 1, 3),
      line(width / 3 * 1 - 1, 3)
    }
  end,
  machi = function(width)
    return wibox.widget {
      layout = wibox.layout.fixed.horizontal,
      spacing = config.dpi(3),
      line(width / 4 * 1 - 1, 3),
      line(width / 4 * 2 - 1, 3),
      line(width / 4 * 1 - 1, 3)
    }
  end,
  floating = function(width)
    return wibox.widget {
      layout = wibox.layout.fixed.horizontal,
      spacing = config.dpi(3),
      line(width / 10 * 1 - 1, 3),
      line(width / 10 * 7 - 1, 3),
      line(width / 10 * 2 - 1, 3)
    }
  end,
  not_found = function(width)
    return wibox.widget {
      layout = wibox.layout.fixed.horizontal,
      spacing = config.dpi(3),
      line(width / 4 * 1 - 1, 3),
      line(width / 4 * 1 - 1, 3),
      line(width / 4 * 1 - 1, 3),
      line(width / 4 * 1 - 1, 3)
    }
  end
}

local function get_screen(s)
  return s and capi.screen[s]
end

local function update(widget, screen)
  screen = get_screen(screen)
  local name = awful.layout.getname(awful.layout.get(screen))
  if not layouts[name] then
    name = "not_found"
  end
  widget:set_widget(layouts[name](widget._private.args_width))
end

local function update_from_tag(t)
  local screen = get_screen(t.screen)
  local widget = boxes[screen]
  if widget then
    update(widget, screen)
  end
end

local function new(screen, width)
  screen = get_screen(screen or 1)

  if boxes == nil then
    boxes = setmetatable({}, {__mode = "kv"})
    capi.tag.connect_signal("property::selected", update_from_tag)
    capi.tag.connect_signal("property::layout", update_from_tag)
    capi.tag.connect_signal(
      "property::screen",
      function()
        for s, w in pairs(boxes) do
          if s.valid then
            update(w, s)
          end
        end
      end
    )
    layoutbox.boxes = boxes
  end

  local ret = boxes[screen]
  if not ret then
    ret = wibox.container.background()
    ret._private.args_width = width

    update(ret, screen)
    boxes[screen] = ret
  end

  return ret
end

function layoutbox.mt:__call(...)
  return new(...)
end

return setmetatable(layoutbox, layoutbox.mt)
