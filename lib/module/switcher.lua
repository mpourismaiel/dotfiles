local capi = {
  tag = tag
}
local wibox = require("wibox")
local gears = require("gears")
local awful = require("awful")
local cairo = require("lgi").cairo
local naughty = require("naughty")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")
local console = require("lib.helpers.console")
local animation_new = require("lib.helpers.animation-new")
local wdialog = require("lib.widgets.dialog")
local wtabs = require("lib.widgets.tabs")
local wcontainer = require("lib.widgets.menu.container")
local wbutton = require("lib.widgets.button")
local wtext = require("lib.widgets.text")
local wtext_input = require("lib.widgets.text_input")
local woverflow = require("wibox.layout.overflow")
local wscrollbar = require("lib.widgets.scrollbar")
local color = require("lib.helpers.color")

local instance = nil
local switcher = {}

local function get_placement()
  local theme_position = theme.switcher_position
  if theme_position == "max_left" then
    return function(self, screen)
      local left_geo =
        awful.placement.left(
        self,
        {
          margins = {
            left = theme.bar_width + theme.switcher_margin_left
          },
          parent = screen
        }
      )

      local vertical_geo =
        awful.placement.maximize(
        self,
        {
          margins = {
            top = theme.switcher_margin_top,
            bottom = theme.switcher_margin_bottom
          },
          parent = screen
        }
      )

      return {
        x = left_geo.x,
        y = vertical_geo.y,
        width = theme.switcher_width,
        height = vertical_geo.height
      }
    end
  end
end

local function get_switcher_items(screen)
  local ret = {}
  for k, v in ipairs(screen.tags) do
    for i, c in ipairs(v:clients()) do
      table.insert(ret, c)
    end
  end

  return ret
end

local function client_widget(client)
  local content = nil
  if client.active then
    content = gears.surface(client.content)
  elseif client.prev_content then
    content = gears.surface(client.prev_content)
  end

  local img = nil
  if content ~= nil then
    local cr = cairo.Context(content)
    local x, y, w, h = cr:clip_extents()
    img = cairo.ImageSurface.create(cairo.Format.ARGB32, w - x, h - y)
    cr = cairo.Context(img)
    cr:set_source_surface(content, 0, 0)
    cr.operator = cairo.Operator.SOURCE
    cr:paint()
  end

  local widget =
    wibox.widget {
    widget = wbutton,
    strategy = "exact",
    width = config.dpi(200),
    height = config.dpi(200),
    margin_right = config.dpi(16),
    margin_left = config.dpi(16),
    padding_left = config.dpi(8),
    padding_right = config.dpi(8),
    padding_top = config.dpi(8),
    padding_bottom = config.dpi(8),
    valign = "top",
    callback = function()
      client:emit_signal("request::activate", "switcher", {raise = true, switch_to_tag = true})
    end,
    {
      layout = wibox.layout.fixed.vertical,
      spacing = config.dpi(16),
      {
        widget = wibox.container.constraint,
        strategy = "exact",
        width = config.dpi(200),
        height = config.dpi(150),
        {
          widget = wibox.widget.imagebox,
          resize = true,
          clip_shape = function(cr, width, height)
            return gears.shape.rounded_rect(cr, width, height, theme.rounded_rect_normal)
          end,
          image = img
        }
      },
      {
        widget = wtext,
        text = client.name or client.class,
        font = theme.font,
        font_size = config.dpi(10),
        font_color = theme.fg_normal,
        single_line = true,
        halign = "center",
        ellipsize = "end"
      }
    }
  }

  widget.client = client

  return widget
end

function switcher:show(screen)
  if self.visible then
    return
  end

  if not screen then
    screen = awful.screen.focused()
  end

  local wp = self._private
  local clients = get_switcher_items(screen)
  if #clients == 0 then
    return
  end

  wp.count = #clients
  wp.selected = 1
  wp.clients_list:reset()
  for _, c in ipairs(clients) do
    wp.clients_list:add(client_widget(c))
  end
  self:select(0)

  local geo = wp.placement(self, screen)
  self:geometry(geo)
  self.screen = screen
  self.visible = true
end

function switcher:hide()
  if not self.visible then
    return
  end

  self.visible = false
  self.screen = nil
end

function switcher:toggle(...)
  if self.visible then
    self:hide()
  else
    self:show(...)
  end
end

function switcher:select(increment)
  local wp = self._private
  wp.selected = wp.selected + increment
  if wp.selected < 1 then
    wp.selected = wp.count
  elseif wp.selected > wp.count then
    wp.selected = 1
  end

  for _, w in ipairs(wp.clients_list.children) do
    w:unhover()
  end
  wp.clients_list.children[wp.selected]:hover()
end

function switcher:create_keygrabber()
  local wp = self._private
  return awful.keygrabber {
    keybindings = {
      awful.key {
        modifiers = {config.altkey},
        key = "Tab",
        on_press = function()
          if not self.visible then
            self:show()
            return
          end
          self:select(1)
        end
      },
      awful.key {
        modifiers = {config.altkey, "Shift"},
        key = "Tab",
        on_press = function()
          if not self.visible then
            self:show()
            return
          end
          self:select(-1)
        end
      }
    },
    stop_key = config.altkey,
    stop_event = "release",
    stop_callback = function()
      local w = wp.clients_list.children[wp.selected]
      if not w then
        return
      end

      w.client:emit_signal("request::activate", "switcher", {raise = true, switch_to_tag = true})
      self:hide()
    end,
    export_keybindings = true
  }
end

local function new(...)
  local ret =
    wibox {
    ontop = true,
    visible = false,
    type = "dialog",
    width = theme.switcher_width,
    height = config.dpi(800),
    bg = theme.bg_normal,
    shape = function(cr, width, height)
      return gears.shape.rounded_rect(cr, width, height, theme.rounded_rect_normal)
    end,
    widget = {
      widget = wibox.container.margin,
      left = config.dpi(20),
      right = config.dpi(10),
      top = config.dpi(24),
      bottom = config.dpi(24),
      {
        layout = woverflow.vertical,
        id = "clients_list",
        spacing = config.dpi(12),
        scrollbar_widget = wscrollbar,
        scrollbar_width = config.dpi(10),
        step = 200
      }
    }
  }
  gears.table.crush(ret, switcher, true)

  local wp = ret._private
  wp.selected = 1
  wp.count = 1
  wp.clients_list = ret:get_children_by_id("clients_list")[1]
  wp.placement = get_placement()

  ret:create_keygrabber()

  capi.tag.connect_signal(
    "property::selected",
    function(t)
      -- Awesome switches up tags on startup really fast it seems, probably depends on what rules you have set
      -- which can cause the c.content to not show the correct image
      gears.timer {
        timeout = 0.1,
        call_now = false,
        autostart = true,
        single_shot = true,
        callback = function()
          if t.selected == true then
            for _, c in ipairs(t:clients()) do
              c.prev_content = gears.surface.duplicate_surface(c.content)
            end
          end
        end
      }
    end
  )

  return ret
end

if not instance then
  instance = new()
end
return instance
