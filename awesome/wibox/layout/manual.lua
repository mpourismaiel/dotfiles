---------------------------------------------------------------------------
-- A layout with widgets added at specific positions.
--
-- Use cases include desktop icons, complex custom composed widgets, a floating
-- client layout and fine grained control over the output.
--
--
--
--<object class=&#34img-object&#34 data=&#34../images/AUTOGEN_wibox_layout_defaults_manual.svg&#34 alt=&#34Usage example&#34 type=&#34image/svg+xml&#34></object>
--
-- @usage
-- local w1, w2 = generic_widget(), generic_widget()
-- w1.point  = {x=75,y=5}
-- w1.text   = &#34first&#34
-- w1.forced_width = 50
-- w2.text = &#34second&#34
-- w2.point  = function(geo, args)
--     -- Bottom right
--     return {
--         x = args.parent.width-geo.width,
--         y = args.parent.height-geo.height
--     }
-- end
-- wibox.layout {
--     w1,
--     w2,
--     generic_widget(&#34third&#34),
--     layout  = wibox.layout.manual
-- }
-- @author Emmanuel Lepage Vallee
-- @copyright 2016 Emmanuel Lepage Vallee
-- @layoutmod wibox.layout.manual
-- @supermodule wibox.widget.base
---------------------------------------------------------------------------
local gtable = require("gears.table")
local gears = require("gears")
local base = require("wibox.widget.base")
local unpack = unpack or table.unpack -- luacheck: globals unpack (compatibility with Lua 5.1)

local manual_layout = {}

--- Add some widgets to the given stack layout.
--
-- @method add
-- @tparam widget ... Widgets that should be added
-- @interface layout
-- @noreturn

--- Remove a widget from the layout.
--
-- @method remove
-- @tparam number index The widget index to remove
-- @treturn boolean index If the operation is successful
-- @interface layout

--- Insert a new widget in the layout at position `index`.
--
-- @method insert
-- @tparam number index The position
-- @tparam widget widget The widget
-- @treturn boolean If the operation is successful.
-- @emits widget::inserted
-- @emitstparam widget::inserted widget self The fixed layout.
-- @emitstparam widget::inserted widget widget index The inserted widget.
-- @emitstparam widget::inserted number count The widget count.
-- @interface layout
function manual_layout:insert(index, widget)
  table.insert(self._private.widgets, index, widget)

  -- Add the point
  if widget.point then
    table.insert(self._private.pos, index, widget.point)
  end

  self:emit_signal("widget::inserted", widget, #self._private.widgets)

  self:emit_signal("widget::layout_changed")
end

--- Remove one or more widgets from the layout.
--
-- The last parameter can be a boolean, forcing a recursive seach of the
-- widget(s) to remove.
--
-- @method remove_widgets
-- @tparam widget ... Widgets that should be removed (must at least be one)
-- @treturn boolean If the operation is successful

function manual_layout:fit(_, width, height)
  return width, height
end

local function geometry(self, new)
  self._new_geo = new
  return self._new_geo or self
end

function manual_layout:layout(context, width, height)
  local res = {}

  for k, v in ipairs(self._private.widgets) do
    local pt = self._private.pos[k] or {x = 0, y = 0}
    local w, h = base.fit_widget(self, context, v, width, height)

    -- Make sure the signature is compatible with `awful.placement`. `Wibox`,
    -- doesn't depend on `awful`, but it is still nice not to have to code
    -- geometry functions again and again.
    if type(pt) == "function" or (getmetatable(pt) or {}).__call then
      local geo = {
        x = 0,
        y = 0,
        width = w,
        height = h,
        geometry = geometry
      }
      pt =
        pt(
        geo,
        {
          parent = {
            x = 0,
            y = 0,
            width = width,
            height = height,
            geometry = geometry
          }
        }
      )
      -- Trick to ensure compatibility with `awful.placement`
      gtable.crush(pt, geo._new_geo or {})
    end

    assert(pt.x)
    assert(pt.y)

    table.insert(res, base.place_widget_at(v, pt.x, pt.y, pt.width or w, pt.height or h))
  end

  return res
end

function manual_layout:remove(index)
  if not index or index < 1 or index > #self._private.pos then
    return false
  end

  table.remove(self._private.widgets, index)
  table.remove(self._private.pos, index)

  self:emit_signal("widget::layout_changed")

  return true
end

function manual_layout:remove_widgets(...)
  local args = {...}

  local ret = true
  for k, rem_widget in ipairs(args) do
    local idx, l = self:index(rem_widget, false)

    if idx and l and l.remove then
      l:remove(idx, false)
    else
      ret = false
    end
  end

  return #args > 0 and ret
end

function manual_layout:replace_widget(widget, widget2, recursive)
  local idx, l = self:index(widget, recursive)

  if idx and l then
    l:set(idx, widget2)
    return true
  end

  return false
end

function manual_layout:set(index, widget2)
  if (not widget2) or (not self._private.widgets[index]) then
    return false
  end

  base.check_widget(widget2)

  local w = self._private.widgets[index]

  self._private.widgets[index] = widget2

  self:emit_signal("widget::layout_changed")
  self:emit_signal("widget::replaced", widget2, w, index)

  return true
end

function manual_layout:add(...)
  local wdgs = {}
  local old_count = #self._private.widgets

  for _, v in ipairs {...} do
    local w = base.make_widget_from_value(v)
    base.check_widget(w)
    table.insert(wdgs, w)
  end

  gtable.merge(self._private.widgets, wdgs)

  -- Add the points
  for k, v in ipairs(wdgs) do
    if v.point then
      self._private.pos[old_count + k] = v.point
    end
  end

  self:emit_signal("widget::layout_changed")
end

--- Add a widget at a specific point.
--
-- The point can either be a function or a table. The table follow the generic
-- geometry format used elsewhere in Awesome.
--
-- * *x*: The horizontal position.
-- * *y*: The vertical position.
-- * *width*: The width.
-- * *height*: The height.
--
-- If a function is used, it follows the same prototype as `awful.placement`
-- functions.
--
-- * *geo*:
--     * *x*: The horizontal position (always 0).
--     * *y*: The vertical position (always 0).
--     * *width*: The width.
--     * *height*: The height.
--     * *geometry*: A function to get or set the geometry (for compatibility).
--       The function is compatible with the `awful.placement` prototype.
-- * *args*:
--     * *parent* The layout own geometry
--         * *x*: The horizontal position (always 0).
--         * *y*: The vertical position (always 0).
--         * *width*: The width.
--         * *height*: The height.
--         * *geometry*: A function to get or set the geometry (for compatibility)
--           The function is compatible with the `awful.placement` prototype.
--
--
--
--<object class=&#34img-object&#34 data=&#34../images/AUTOGEN_wibox_layout_manual_add_at.svg&#34 alt=&#34Usage example&#34 type=&#34image/svg+xml&#34></object>
--
-- @usage
-- local l = wibox.layout {
--     layout  = wibox.layout.manual
-- }
-- --
-- -- Option 1: Set the point directly in the widget
-- local w1        = generic_widget()
-- w1.point        = {x=75, y=5}
-- w1.text         = &#34first&#34
-- w1.forced_width = 50
-- l:add(w1)
-- --
-- -- Option 2: Set the point directly in the widget as a function
-- local w2  = generic_widget()
-- w2.text   = &#34second&#34
-- w2.point  = function(geo, args)
--     return {
--         x = args.parent.width  - geo.width,
--         y = 0
--     }
-- end
-- l:add(w2)
-- --
-- -- Option 3: Set the point directly in the widget as an `awful.placement`
-- -- function.
-- local w3 = generic_widget()
-- w3.text  = &#34third&#34
-- w3.point = awful.placement.bottom_right
-- l:add(w3)
-- --
-- -- Option 4: Use `:add_at` instead of using the `.point` property. This works
-- -- with all 3 ways to define the point.
-- -- function.
-- local w4 = generic_widget()
-- w4.text  = &#34fourth&#34
-- l:add_at(w4, awful.placement.centered + awful.placement.maximize_horizontally)
--
-- @method add_at
-- @tparam widget widget The widget.
-- @tparam table|function point Either an `{x=x,y=y}` table or a function
--  returning the new geometry.
-- @noreturn
function manual_layout:add_at(widget, point)
  assert(not widget.point, "2 points are specified, only one is supported")

  -- Check is the point function is valid
  if type(point) == "function" or (getmetatable(point) or {}).__call then
    local fake_geo = {x = 0, y = 0, width = 1, height = 1, geometry = geometry}
    local pt =
      point(
      fake_geo,
      {
        parent = {
          x = 0,
          y = 0,
          width = 10,
          height = 10,
          geometry = geometry
        }
      }
    )
    assert(pt and pt.x and pt.y, "The point function doesn't seem to be valid")
  end

  self._private.pos[#self._private.widgets + 1] = point
  self:add(base.make_widget_from_value(widget))
end

--- Move a widget (by index).
--
-- @method move
-- @tparam number index The widget index.
-- @tparam table|function point A new point value.
-- @noreturn
-- @see add_at
function manual_layout:move(index, point)
  assert(self._private.pos[index])
  self._private.pos[index] = point
  self:emit_signal("widget::layout_changed")
end

--- Move a widget.
--
--
--
--<object class=&#34img-object&#34 data=&#34../images/AUTOGEN_wibox_layout_manual_move_widget.svg&#34 alt=&#34Usage example&#34 type=&#34image/svg+xml&#34></object>
--
-- @usage
-- local l = wibox.layout {
--     layout  = wibox.layout.manual
-- }
-- --
-- local w1        = generic_widget()
-- w1.point        = {x=75, y=5}
-- w1.text         = &#34first&#34
-- w1.forced_width = 50
-- l:add(w1)
-- l:move_widget(w1, awful.placement.bottom_right)
--
-- @method move_widget
-- @tparam widget widget The widget.
-- @tparam table|function point A new point value.
-- @noreturn
-- @see add_at
function manual_layout:move_widget(widget, point)
  local idx, l = self:index(widget, false)

  if idx then
    l:move(idx, point)
  end
end

function manual_layout:get_children()
  return self._private.widgets
end

function manual_layout:set_children(children)
  self:reset()
  self:add(unpack(children))
end

function manual_layout:reset()
  self._private.widgets = {}
  self._private.pos = {}
  self:emit_signal("widget::layout_changed")
end

--- Create a manual layout.
--
-- @constructorfct wibox.layout.manual
-- @tparam table ... Widgets to add to the layout.

local function new_manual(...)
  local ret = base.make_widget(nil, nil, {enable_properties = true})

  gtable.crush(ret, manual_layout, true)
  ret._private.widgets = {}
  ret._private.pos = {}

  ret:add(...)

  return ret
end

----- Set a widget at a specific index, replacing the current one.
--
-- @tparam number index A widget or a widget index
-- @tparam widget widget2 The widget to replace the previous one with
-- @treturn boolean Returns `true` if the widget was replaced successfully,
--   `false` otherwise.
-- @method set
-- @emits widget::replaced
-- @emitstparam widget::replaced widget self The layout.
-- @emitstparam widget::replaced widget widget The inserted widget.
-- @emitstparam widget::replaced widget previous The previous widget.
-- @emitstparam widget::replaced number index The replaced index.
-- @interface layout

--- Replace the first instance of `widget` in the layout with `widget2`.
--
-- @tparam widget widget The widget to replace
-- @tparam widget widget2 The widget to replace `widget` with
-- @tparam[opt=false] boolean recursive Recurse into all compatible layouts to
--   find the widget.
-- @treturn boolean Returns `true` if the widget was replaced successfully,
--   `false` otherwise.
-- @method replace_widget
-- @emits widget::replaced
-- @emitstparam widget::replaced widget self The layout.
-- @emitstparam widget::replaced widget widget index The inserted widget.
-- @emitstparam widget::replaced widget previous The previous widget.
-- @emitstparam widget::replaced number index The replaced index.
-- @interface layout

--- Swap 2 widgets in a layout.
--
-- @tparam number index1 The first widget index
-- @tparam number index2 The second widget index
-- @treturn boolean Returns `true` if the widget was replaced successfully,
--   `false` otherwise.
-- @method swap
-- @emits widget::swapped
-- @emitstparam widget::swapped widget self The layout.
-- @emitstparam widget::swapped widget widget1 The first widget.
-- @emitstparam widget::swapped widget widget2 The second widget.
-- @emitstparam widget::swapped number index1 The first index.
-- @emitstparam widget::swapped number index1 The second index.
-- @interface layout

--- Swap 2 widgets in a layout.
--
-- If `widget1` is present multiple time, only the first instance is swapped.
--
-- Calls `set` internally, so the signal `widget::replaced` is emitted for both
-- widgets as well.
--
-- @tparam widget widget1 The first widget
-- @tparam widget widget2 The second widget
-- @tparam[opt=false] boolean recursive Recurse into all compatible layouts to
--   find the widget.
-- @treturn boolean Returns `true` if the widget was replaced successfully,
--   `false` otherwise.
-- @method swap_widgets
-- @emits widget::swapped
-- @emitstparam widget::swapped widget self The layout.
-- @emitstparam widget::swapped widget widget1 The first widget.
-- @emitstparam widget::swapped widget widget2 The second widget.
-- @emitstparam widget::swapped number index1 The first index.
-- @emitstparam widget::swapped number index1 The second index.
-- @interface layout
-- @see set

--- Reset the layout. This removes all widgets from the layout.
-- @method reset
-- @noreturn
-- @emits widget::reset
-- @emitstparam widget::reset widget self The layout.
-- @interface layout

-- vim: filetype=lua:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80

return setmetatable(
  manual_layout,
  {
    __call = function(_, ...)
      return new_manual(...)
    end
  }
)
