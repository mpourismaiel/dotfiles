local wibox = require("wibox")
local gears = require("gears")
local constraint = require("lib.widgets.components.constraint")
local margin = require("lib.widgets.components.margin")
local place = require("lib.widgets.components.place")
local shape = require("lib.widgets.components.shape")
local background = require("lib.widgets.components.background")

local container = {mt = {}}

function container:set_widget(widget)
  self._private.place_role:set_widget(widget)
  return self
end

function container:get_widget()
  return self._private.place_role:get_widget()
end

local function new()
  local ret =
    wibox.widget {
    widget = wibox.container.margin,
    id = "margins",
    {
      widget = wibox.container.constraint,
      id = "constraint",
      {
        widget = wibox.container.background,
        id = "background",
        {
          widget = wibox.container.margin,
          id = "paddings",
          {
            widget = wibox.container.place,
            id = "place"
          }
        }
      }
    }
  }

  local wp = ret._private
  wp.margin_role = ret:get_children_by_id("margins")[1]
  wp.constraint_role = ret:get_children_by_id("constraint")[1]
  wp.background_role = ret:get_children_by_id("background")[1]
  wp.padding_role = ret:get_children_by_id("paddings")[1]
  wp.place_role = ret:get_children_by_id("place")[1]

  gears.table.crush(ret, container)
  gears.table.crush(ret, constraint.build_properties(wp.constraint_role))
  gears.table.crush(ret, margin.build_properties(wp.padding_role, "paddings_all", "padding"))
  gears.table.crush(ret, margin.build_properties(wp.margin_role, "margins_all", "margin"))
  gears.table.crush(ret, place.build_properties(wp.place_role))
  gears.table.crush(ret, shape.build_properties(wp.background_role))
  gears.table.crush(ret, background.build_properties(wp.background_role))

  ret:set_valign("top")
  ret:set_halign("left")

  return ret
end

function container.mt:__call(...)
  return new(...)
end

return setmetatable(container, container.mt)
