local capi = {
  awesome = awesome
}
local wibox = require("wibox")
local gears = require("gears")
local awful = require("awful")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")
local animation_new = require("lib.helpers.animation-new")
local console = require("lib.helpers.console")

local dialog = {mt = {}}

dialog.backdrop =
  wibox {
  ontop = true,
  bg = "#000000",
  opacity = 0.0,
  type = "utility"
}
dialog.backdrop:buttons(
  gears.table.join(
    awful.button(
      {},
      1,
      function()
        local screen = dialog.backdrop.screen
        if not screen or not screen.dialog_shown or not screen.dialogs or not screen.dialogs[screen.dialog_shown] then
          return
        end
        screen.dialogs[screen.dialog_shown]:hide()
      end
    )
  )
)

for _, v in pairs(
  {
    "position",
    "animation",
    "name",
    "widget",
    "shape",
    "width",
    "height",
    "type",
    "bg"
  }
) do
  ---@diagnostic disable-next-line: assign-type-mismatch
  dialog["get_" .. v] = function(layout)
    return layout._private[v]
  end
end

function dialog:show(screen)
  local wp = self._private
  if not screen then
    screen = awful.screen.focused()
  end

  if not wp.name then
    gears.debug.print_warning("Dialog has no name")
    return
  end

  if not screen.dialogs then
    screen.dialogs = {}
  end

  screen.dialogs[wp.name] = self
  screen.dialog_shown = wp.name

  if not screen.backdrop then
    screen.backdrop = dialog.backdrop
    dialog.backdrop.screen = screen
    awful.placement.maximize(
      dialog.backdrop,
      {
        honor_workarea = false,
        honor_padding = false,
        margins = 0
      }
    )

    dialog.backdrop.visible = true
  end

  if wp.display.visible then
    return
  end

  wp.display.screen = screen
  wp.display.visible = true

  if wp.animation then
    wp.animation:startAnimation("visible", {from_start = true})
    return
  end

  if wp.position then
    local geo =
      wp.position(
      wp.display,
      wp.position_args or
        {
          honor_workarea = true,
          honor_padding = true,
          pretend = true
        }
    )
    wp.display.x = geo.x
    wp.display.y = geo.y
  else
    awful.placement.centered(wp.display, {honor_workarea = true, honor_padding = true})
  end
end

function dialog:hide()
  local wp = self._private
  if not wp.display.visible then
    return
  end

  local screen = wp.display.screen
  if not screen or not screen.dialog_shown or not screen.dialogs then
    return
  end

  screen.dialog_shown = nil
  if wp.animation then
    wp.animation:startAnimation("invisible")
  end
  wp.display.visible = false
  dialog.backdrop.visible = false
  screen.backdrop = nil
end

function dialog:toggle(...)
  local wp = self._private
  if wp.display.visible then
    self:hide()
  else
    self:show(...)
  end
end

function dialog:set_position(position, args)
  local wp = self._private
  wp.position = position
  wp.position_args =
    args or
    {
      honor_workarea = true,
      honor_padding = true
    }
  wp.position_args.pretend = true
end

function dialog:set_animation(animation)
  local wp = self._private
  wp.animation = animation
end

function dialog:set_name(name)
  console():title("dialog:set_name"):log(name)
  local wp = self._private
  wp.name = name
end

function dialog:set_widget(widget)
  local wp = self._private
  wp.display.widget = widget
end

function dialog:set_shape(shape)
  local wp = self._private
  wp.display.shape = shape
end

function dialog:set_width(width)
  local wp = self._private
  wp.display.width = width
end

function dialog:set_height(height)
  local wp = self._private
  wp.display.height = height
end

function dialog:set_type(type)
  local wp = self._private
  wp.display.type = type
end

function dialog:set_bg(bg)
  local wp = self._private
  wp.display.bg = bg
end

function dialog:connect_signal(...)
  local wp = self._private
  wp.display:connect_signal(...)
end

local function new(args)
  args = args or {}
  local ret = {_private = {}}
  gears.table.crush(ret, dialog, true)

  local wp = ret._private
  wp.name = args.name
  wp.animation = args.animation
  wp.position = args.position
  wp.position_args = args.position_args
  wp.display =
    wibox {
    ontop = true,
    visible = false,
    bg = args.bg or theme.bg_normal,
    type = args.type or "dialog",
    width = args.width or config.dpi(1),
    height = args.height or config.dpi(1),
    shape = args.shape or function(cr, w, h)
        gears.shape.rounded_rect(cr, w, h, theme.rounded_rect_large)
      end,
    widget = args.widget or wibox.widget {}
  }

  return ret
end

function dialog.mt:__call(...)
  return new(...)
end

return setmetatable(dialog, dialog.mt)
