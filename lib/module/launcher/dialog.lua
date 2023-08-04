local wibox = require("wibox")
local awful = require("awful")
local gears = require("gears")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")
local wbutton = require("lib.widgets.button")
local wtext = require("lib.widgets.text")
local wtext_input = require("lib.widgets.text_input")
local woverflow = require("wibox.layout.overflow")
local launcher = require("lib.module.launcher")
local store = require("lib.module.store")
local color = require("helpers.color")

local dialog = {instance = nil, mt = {}}

local terminal_commands_lookup = {
  ["xfce4-terminal"] = "xfce4-terminal",
  alacritty = "alacritty -e",
  termite = "termite -e",
  rxvt = "rxvt -e",
  terminator = "terminator -e"
}

for _, v in pairs(
  {
    "col_count",
    "row_count",
    "col_spacing",
    "row_spacing",
    "icon_size"
  }
) do
  ---@diagnostic disable-next-line: assign-type-mismatch
  dialog["set_" .. v] = function(self, val)
    if self._private[v] == val then
      return
    end
    self._private[v] = val
    self:emit_signal("widget::layout_changed")
    self:emit_signal("property::" .. v, val)
  end

  ---@diagnostic disable-next-line: assign-type-mismatch
  dialog["get_" .. v] = function(layout)
    return layout._private[v]
  end
end

function dialog:calculate_position()
  local wp = self._private
  local s = awful.screen.focused()
  wp.backdrop.screen = s
  wp.widget.screen = s

  wp.backdrop.x = s.geometry.x
  wp.backdrop.y = s.geometry.y
  wp.backdrop.width = s.geometry.width
  wp.backdrop.height = s.geometry.height

  local geo =
    awful.placement.centered(
    wp.widget,
    {
      honor_workarea = true,
      honor_padding = true,
      pretend = true
    }
  )
  wp.widget.x = geo.x
  wp.widget.y = geo.y
end

function dialog:render_apps()
  local wp = self._private
  local apps = gears.table.clone(wp.launcher.all_entries)
  table.sort(
    apps,
    function(a, b)
      local aFav = wp.favorites:get(a.name .. a.executable) ~= nil
      local bFav = wp.favorites:get(b.name .. b.executable) ~= nil

      if aFav ~= bFav then
        return aFav
      end

      local aHist = wp.history:get(a.executable) or 0
      local bHist = wp.history:get(b.executable) or 0

      if aHist ~= bHist then
        return aHist > bHist
      end

      return a.executable < b.executable
    end
  )

  wp.grid:reset()
  wp.grid.buttons = {}
  wp.grid.apps = {}

  local row = nil
  local last_index = 0
  for i, v in ipairs(apps) do
    if
      wp.query == "" or
        (string.find(v.name:lower(), wp.query:lower(), 1, true) ~= nil and self.search_commands or
          string.find(v.commandline, wp.query:lower(), 1, true) ~= nil)
     then
      last_index = last_index + 1
      if last_index % wp.col_count == 1 then
        row =
          wibox.widget {
          layout = wibox.layout.fixed.horizontal,
          spacing = wp.col_spacing
        }
        wp.grid:add(row)
      end

      local w =
        wibox.widget {
        widget = wibox.container.constraint,
        strategy = "exact",
        width = wp.icon_size + config.dpi(80),
        height = wp.icon_size + config.dpi(36),
        {
          widget = wbutton,
          margin = 0,
          paddings = config.dpi(5),
          id = "button",
          bg_normal = color.helpers.change_opacity(theme.bg_hover, 0.4),
          disable_hover = true,
          middle_click_callback = function()
            wp.favorites:add(
              v.name .. v.executable,
              function(val)
                if val then
                  return nil
                end

                return true
              end
            )
          end,
          callback = function()
            if wp.selected == i then
              self:run()
            else
              self:select(i)
            end
          end,
          {
            layout = wibox.layout.fixed.vertical,
            spacing = config.dpi(5),
            {
              widget = wibox.container.place,
              halign = "center",
              {
                widget = wibox.container.constraint,
                strategy = "exact",
                width = wp.icon_size,
                height = wp.icon_size,
                {
                  widget = wibox.widget.imagebox,
                  image = v.icon
                }
              }
            },
            {
              widget = wtext,
              text = v.name,
              halign = "center",
              ellipsize = true
            }
          }
        }
      }

      w.button = w:get_children_by_id("button")[1]
      table.insert(wp.grid.buttons, w.button)
      table.insert(wp.grid.apps, v)
      row:add(w)
    end
  end

  if last_index == 0 then
    wp.grid:add(
      wibox.widget {
        widget = wtext,
        text = "No results found",
        foreground = theme.fg_normal
      }
    )
    return
  end

  if wp.col_count - (last_index % wp.col_count) == wp.col_count then
    return
  end

  for i = 1, wp.col_count - (last_index % wp.col_count) do
    row:add(
      wibox.widget {
        widget = wibox.container.place,
        halign = "center",
        {
          widget = wibox.container.constraint,
          strategy = "exact",
          width = wp.icon_size + config.dpi(60),
          height = wp.icon_size + config.dpi(36)
        }
      }
    )
  end
end

function dialog:select(select, scroll_to_view)
  local wp = self._private
  if select == wp.selected then
    return
  end

  for _, w in pairs(wp.grid.buttons) do
    w:unhover()
  end

  if select > #wp.grid.apps then
    select = #wp.grid.apps
  elseif select < 1 then
    select = 1
  end
  wp.selected = select
  wp.grid.buttons[select]:hover()
end

function dialog:run()
  local wp = self._private
  if wp.selected == 0 or wp.selected > #wp.grid.apps then
    return
  end

  local entry = wp.grid.apps[wp.selected]
  if not entry then
    return
  end
  wp.history:add(
    entry.executable,
    function(val)
      if not val then
        return 1
      end

      return val + 1
    end
  )

  if entry.terminal == true and config.terminal ~= nil then
    local terminal_command = terminal_commands_lookup[config.terminal] or config.terminal
    awful.spawn(terminal_command .. " " .. entry.executable)
  else
    awful.spawn.easy_async(
      "gtk-launch " .. entry.executable,
      function(stdout, stderr)
        if stderr:match("^%s*(.-)%s*$") ~= "" then
          awful.spawn(entry.executable)
        end
      end
    )
  end

  awesome.emit_signal("module::launcher::hide")
end

function dialog:search(text)
  local wp = self._private
  wp.query = text or ""
  wp.query = wp.query:gsub("%W", "")
  self:select(1)
  self:render_apps()
end

local function run_keygrabber(self, modifiers, key, event)
  local wp = self._private
  if key == "Up" then
    self:select(wp.selected - wp.col_count, true)
  elseif key == "Down" then
    self:select(wp.selected + wp.col_count, true)
  elseif key == "Left" then
    self:select(wp.selected - 1, true)
  elseif key == "Right" then
    self:select(wp.selected + 1, true)
  elseif key == "Return" then
    self:run()
  elseif key == "Escape" then
    awesome.emit_signal("module::launcher::hide")
  end
end

local function new()
  if dialog.instance then
    return dialog.instance
  end

  local ret = {}
  ret._private = {
    col_count = 4,
    row_count = 2,
    col_spacing = config.dpi(10),
    row_spacing = config.dpi(10),
    icon_size = config.dpi(48),
    selected = 1,
    query = "",
    history = store("launcher-history", {}),
    favorites = store("launcher-favorites", {})
  }
  ret._private.launcher = launcher()
  gears.table.crush(ret, dialog)

  local wp = ret._private

  local backdrop =
    wibox {
    ontop = true,
    bg = "#ffffff00",
    type = "utility"
  }

  local widget =
    wibox {
    ontop = true,
    bg = color.helpers.change_opacity(theme.bg_normal, 0.25),
    type = "dialog",
    visible = false,
    width = config.dpi(600),
    height = config.dpi(400),
    shape = function(cr, w, h)
      gears.shape.rounded_rect(cr, w, h, theme.rounded_rect_large)
    end,
    widget = {
      widget = wibox.container.place,
      halign = "center",
      valign = "center",
      {
        widget = wibox.container.margin,
        margins = config.dpi(10),
        {
          widget = wibox.container.constraint,
          strategy = "exact",
          width = config.dpi(600),
          {
            layout = wibox.layout.fixed.vertical,
            spacing = config.dpi(10),
            {
              widget = wtext_input,
              unfocus_on_client_clicked = true,
              initial = "",
              id = "search",
              widget_template = wibox.widget {
                widget = wibox.container.background,
                shape = function(cr, w, h)
                  gears.shape.rounded_rect(cr, w, h, theme.rounded_rect_large)
                end,
                bg = color.helpers.change_opacity(theme.bg_normal, 0.6),
                {
                  widget = wibox.container.margin,
                  margins = config.dpi(15),
                  {
                    layout = wibox.layout.stack,
                    {
                      widget = wibox.widget.textbox,
                      id = "placeholder_role",
                      text = "Search..."
                    },
                    {
                      widget = wibox.widget.textbox,
                      id = "text_role"
                    }
                  }
                }
              }
            },
            {
              widget = wibox.container.constraint,
              strategy = "exact",
              height = config.dpi(400),
              {
                widget = wibox.container.place,
                valign = "top",
                {
                  widget = wibox.container.constraint,
                  strategy = "exact",
                  width = config.dpi(600),
                  {
                    widget = wibox.container.background,
                    shape = function(cr, width, height)
                      gears.shape.rounded_rect(cr, width, height, theme.rounded_rect_large)
                    end,
                    bg = color.helpers.change_opacity(theme.bg_normal, 0.6),
                    {
                      widget = wibox.container.margin,
                      margins = config.dpi(10),
                      {
                        layout = woverflow.vertical,
                        spacing = wp.row_spacing,
                        id = "grid"
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  backdrop:buttons(
    awful.util.table.join(
      awful.button(
        {},
        1,
        function()
          awesome.emit_signal("module::launcher::hide")
        end
      )
    )
  )

  wp.search = widget:get_children_by_id("search")[1]
  wp.backdrop = backdrop
  wp.widget = widget
  wp.grid = widget:get_children_by_id("grid")[1]
  ret:render_apps()
  ret:calculate_position()

  wp.search:connect_signal(
    "key::press",
    function(self, modifiers, key, event)
      run_keygrabber(ret, modifiers, key, event)
    end
  )

  wp.search:connect_signal(
    "property::text",
    function(w)
      ret:search(w.text)
    end
  )

  wp.grid:connect_signal(
    "layout::scroll",
    function()
      for _, w in pairs(wp.grid.buttons) do
        w:unhover()
      end
    end
  )

  awesome.connect_signal(
    "module::launcher::show",
    function()
      wp.backdrop.visible = true
      wp.widget.visible = true
      wp.grid:set_scroll_factor(0)
      ret:select(1)
      wp.search:focus()
    end
  )

  awesome.connect_signal(
    "module::launcher::hide",
    function()
      wp.search:unfocus()
      wp.search:set_text("")
      wp.query = ""
      ret:render_apps()
      wp.backdrop.visible = false
      wp.widget.visible = false
    end
  )

  return ret
end

function dialog.mt:__call(...)
  return new(...)
end

return setmetatable(dialog, dialog.mt)
