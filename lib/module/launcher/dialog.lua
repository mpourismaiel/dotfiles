local capi = {
  awesome = awesome
}
local wibox = require("wibox")
local awful = require("awful")
local gears = require("gears")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")
local wcontainer = require("lib.widgets.container")
local wbutton = require("lib.widgets.button")
local wtext = require("lib.widgets.text")
local wtext_input = require("lib.widgets.text_input")
local woverflow = require("wibox.layout.overflow")
local launcher = require("lib.module.launcher")
local store = require("lib.module.store")
local color = require("lib.helpers.color")
local console = require("lib.helpers.console")
local debounce = require("lib.helpers.debounce")

local instance = nil
local dialog = {mt = {}}

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

function dialog:create_cache()
  local wp = self._private
  wp.cache = {}
  local apps = gears.table.clone(wp.launcher.all_entries)
  for i, v in ipairs(apps) do
    local w =
      wibox.widget {
      widget = wbutton,
      strategy = "exact",
      width = wp.icon_size + config.dpi(80),
      height = wp.icon_size + config.dpi(36),
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

    w.button = w:get_children_by_id("button")[1]
    wp.cache[self:get_cache_key(v)] = w
  end
end

function dialog:get_cache_key(entry)
  return entry.name .. entry.executable
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

  local results = {}
  for _, app in pairs(apps) do
    local include_app = true
    if wp.category == "favorites" and wp.favorites:get(app.name .. app.executable) == nil then
      include_app = false
    end

    if
      (wp.query == "" and include_app) or
        (wp.query ~= "" and
          (string.find(app.name:lower(), wp.query:lower(), 1, true) ~= nil or
            string.find(app.commandline, wp.query:lower(), 1, true) ~= nil))
     then
      table.insert(results, app)
    end
  end

  wp.grid:reset()
  wp.grid.buttons = {}
  wp.grid.apps = {}

  if wp.category == "favorites" and #results == 0 and wp.query == "" then
    wp.grid:add(
      wibox.widget {
        widget = wibox.container.margin,
        margins = config.dpi(10),
        {
          widget = wtext,
          text = "Press 'mouse middle button' to favorite an application",
          foreground = theme.fg_normal,
          align = "center",
          valign = "center"
        }
      }
    )
    return
  end

  local i = 1
  if wp.query and wp.is_url then
    local button =
      wibox.widget {
      widget = wbutton,
      callback = function()
        if wp.selected == 1 then
          self:run()
        else
          self:select(i)
        end
      end,
      {
        widget = wtext,
        text = "Open in browser",
        foreground = theme.fg_normal,
        halign = "left",
        valign = "center"
      }
    }
    table.insert(wp.grid.buttons, button)
    table.insert(wp.grid.apps, {executable = wp.query})
    button:unhover()

    wp.grid:add(button)
    i = i + 1
  end

  local row = nil
  for j, app in ipairs(results) do
    if j % wp.col_count == 1 then
      row =
        wibox.widget {
        layout = wibox.layout.fixed.horizontal,
        spacing = wp.col_spacing
      }
      wp.grid:add(row)
    end

    local w = wp.cache[self:get_cache_key(app)]
    if w then
      w.button.callback = function()
        if wp.selected == j + i then
          self:run()
        else
          self:select(j + i)
        end
      end
      table.insert(wp.grid.buttons, w.button)
      table.insert(wp.grid.apps, app)
      w.button:unhover()

      ---@diagnostic disable-next-line: undefined-field, need-check-nil
      row:add(w)
    end
  end

  if #results == 0 then
    wp.grid:add(
      wibox.widget {
        widget = wtext,
        text = "No results found",
        foreground = theme.fg_normal
      }
    )
    return
  end

  if wp.col_count - (#results % wp.col_count) == wp.col_count then
    return
  end

  local empty =
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

  for i = 1, wp.col_count - (#results % wp.col_count) do
    ---@diagnostic disable-next-line: undefined-field, need-check-nil
    row:add(empty)
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

  if wp.is_url then
    awful.spawn("xdg-open " .. entry.executable)
    capi.awesome.emit_signal("module::launcher::hide")
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

  capi.awesome.emit_signal("module::launcher::hide")
end

function dialog:search(text)
  local wp = self._private
  wp.is_url = false
  wp.query = text or ""

  if wp.query:match("^%w+://[^.]+%..+") then
    wp.is_url = true
    self:render_apps()
    return
  end

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
    capi.awesome.emit_signal("module::launcher::hide")
  end
end

local function new()
  if instance then
    return instance
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
    favorites = store("launcher-favorites", {}),
    category = "favorites",
    is_url = false,
    cache = {}
  }
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
    bg = theme.enable_blur and color.helpers.change_opacity(theme.bg_normal, 0.25) or
      color.helpers.lighten(theme.bg_normal, 0.05),
    type = "dialog",
    visible = false,
    width = config.dpi(600),
    height = config.dpi(700),
    shape = function(cr, w, h)
      gears.shape.rounded_rect(cr, w, h, theme.rounded_rect_large)
    end,
    widget = {
      widget = wcontainer,
      halign = "center",
      valign = "center",
      paddings_all = config.dpi(10),
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
          widget = wcontainer,
          strategy = "exact",
          height = config.dpi(700),
          width = config.dpi(600),
          paddings_all = config.dpi(10),
          valign = "top",
          bg = color.helpers.change_opacity(theme.bg_normal, 0.6),
          shape = function(cr, width, height)
            gears.shape.rounded_rect(cr, width, height, theme.rounded_rect_large)
          end,
          {
            layout = wibox.layout.fixed.vertical,
            spacing = config.dpi(10),
            {
              layout = wibox.layout.fixed.horizontal,
              spacing = config.dpi(10),
              wibox.widget {
                widget = wbutton,
                shape = function(cr, w, h)
                  gears.shape.rounded_rect(cr, w, h, theme.rounded_rect_normal)
                end,
                callback = function()
                  wp.category = "all"
                  ret:render_apps()
                end,
                label = "All Applications"
              },
              wibox.widget {
                widget = wbutton,
                shape = function(cr, w, h)
                  gears.shape.rounded_rect(cr, w, h, theme.rounded_rect_normal)
                end,
                callback = function()
                  wp.category = "favorites"
                  ret:render_apps()
                end,
                label = "Favorites"
              }
            },
            {
              layout = woverflow.vertical,
              spacing = wp.row_spacing,
              step = 200,
              id = "grid"
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
          capi.awesome.emit_signal("module::launcher::hide")
        end
      )
    )
  )

  wp.search = widget:get_children_by_id("search")[1]
  wp.backdrop = backdrop
  wp.widget = widget
  wp.grid = widget:get_children_by_id("grid")[1]
  wp.launcher =
    launcher(
    {
      icon_theme = theme.icon_theme or "Papirus",
      icon_size = theme.launcher_icon_size
    }
  )
  wp.launcher.callback = function()
    ret:create_cache()
    ret:render_apps()
  end
  wp.launcher:generate_apps()

  wp.search:connect_signal(
    "key::press",
    function(self, modifiers, key, event)
      run_keygrabber(ret, modifiers, key, event)
    end
  )

  wp.search:connect_signal(
    "property::text",
    -- debounce(
    function(w)
      ret:search(w.text)
    end
    --   ,0.2
    -- )
  )

  wp.grid:connect_signal(
    "layout::scroll",
    function()
      for _, w in pairs(wp.grid.buttons) do
        w:unhover()
      end
    end
  )

  capi.awesome.connect_signal(
    "module::launcher::show",
    function()
      wp.backdrop.visible = true
      wp.widget.visible = true
      ret:calculate_position()

      wp.grid:set_scroll_factor(0)
      ret:select(1)
      wp.search:focus()
    end
  )

  capi.awesome.connect_signal(
    "module::launcher::hide",
    function()
      wp.search:unfocus()
      wp.search:set_text("")
      wp.query = ""
      wp.is_url = false
      wp.category = "favorites"
      wp.backdrop.visible = false
      wp.widget.visible = false
      ret:render_apps()
    end
  )

  instance = ret
  return ret
end

function dialog.mt:__call(...)
  return new(...)
end

return setmetatable(dialog, dialog.mt)
