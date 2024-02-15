local wibox = require("wibox")
local gears = require("gears")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")
local wbutton = require("lib.widgets.button")
local console = require("lib.helpers.console")

local tabs = {mt = {}}

function tabs:set_tabs(tabs)
  local wp = self._private
  self:reset_tabs()
  wp.tabs = tabs

  for _, tab in ipairs(tabs) do
    tab.button =
      wibox.widget {
      widget = wbutton,
      id = tab.id,
      shape = function(cr, w, h)
        gears.shape.rounded_rect(cr, w, h, theme.rounded_rect_normal)
      end,
      callback = function()
        self:set_active_tab(tab)
      end,
      label = tab.title
    }

    tab.widget =
      wibox.widget {
      widget = wibox.container.constraint,
      strategy = "min",
      width = wp.tab_constraint_width or config.dpi(36),
      height = wp.tab_constraint_height or config.dpi(36),
      tab.widget
    }

    wp.tab_buttons_role:add(tab.button)
    wp.tabs_widget_role:add_at(tab.widget, {x = -9999, y = 0})
  end

  self:set_active_tab(tabs[1].id)
end

function tabs:get_tabs()
  local wp = self._private
  return wp.tabs
end

function tabs:set_active_tab(tab_id)
  local wp = self._private

  if not wp.tabs then
    console():title("Tabs widget"):with_trace():log("No tabs set")
    return
  end

  local found = nil
  if type(tab_id) == "table" then
    found = tab_id
    tab_id = found.id
  else
    for _, tab in ipairs(wp.tabs) do
      if tab.id == tab_id then
        found = tab
        break
      end
    end
  end

  if not found then
    console():title("Tabs widget"):with_trace():log("Tab not found")
    return
  end

  if wp.active_tab == found then
    return
  end

  for _, tab in ipairs(wp.tabs) do
    if tab.id == found.id then
      tab.button:set_bg_normal(theme.bg_hover)
      tab.button:set_fg_normal(theme.fg_primary)
    else
      tab.button:set_bg_normal(theme.bg_primary)
      tab.button:set_fg_normal(theme.fg_normal)
    end
  end

  if wp.active_tab then
    wp.tabs_widget_role:move_widget(wp.active_tab.widget, {x = -9999, y = 0})
  end
  wp.active_tab = found
  wp.tabs_widget_role:move_widget(wp.active_tab.widget, {x = 0, y = 0})
end

function tabs:get_active_tab()
  local wp = self._private
  return wp.active_tab
end

function tabs:reset_tabs()
  local wp = self._private
  wp.tabs = nil
  wp.active_tab = nil
  wp.tab_buttons_role:reset()
  wp.tabs_widget_role:reset()
end

function tabs:set_forced_width(width)
  local wp = self._private
  wp.tab_constraint_width = width
  wp.tabs_constraint_role:set_width(width)

  if not wp.tabs then
    return
  end

  for _, w in ipairs(wp.tabs) do
    w.widget:set_width(width)
  end
end

function tabs:get_forced_width()
  local wp = self._private
  return wp.tabs_constraint_role:get_width()
end

function tabs:set_forced_height(height)
  local wp = self._private
  wp.tab_constraint_height = height - config.dpi(48)
  wp.tabs_constraint_role:set_height(height - config.dpi(48))

  if not wp.tabs then
    return
  end

  for _, w in ipairs(wp.tabs) do
    w.widget:set_height(wp.height)
  end
end

function tabs:get_forced_height()
  local wp = self._private
  return wp.tabs_constraint_role:get_height()
end

local function new()
  local ret =
    wibox.widget {
    layout = wibox.layout.fixed.vertical,
    spacing = config.dpi(12),
    {
      widget = wibox.container.constraint,
      strategy = "exact",
      height = config.dpi(36),
      {
        layout = wibox.layout.fixed.horizontal,
        spacing = config.dpi(12),
        id = "tab_buttons_role"
      }
    },
    {
      widget = wibox.container.constraint,
      strategy = "min",
      id = "tabs_constraint_role",
      {
        layout = wibox.layout.manual,
        id = "tabs_widget_role"
      }
    }
  }
  gears.table.crush(ret, tabs)

  local wp = ret._private
  wp.tabs = {}
  wp.active_tab = nil
  wp.tab_buttons_role = ret:get_children_by_id("tab_buttons_role")[1]
  wp.tabs_widget_role = ret:get_children_by_id("tabs_widget_role")[1]
  wp.tabs_constraint_role = ret:get_children_by_id("tabs_constraint_role")[1]

  return ret
end

tabs.mt.__call = function(_, ...)
  return new(...)
end

return setmetatable(tabs, tabs.mt)
