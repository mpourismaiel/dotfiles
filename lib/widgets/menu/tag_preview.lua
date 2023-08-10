local wibox = require("wibox")
local awful = require("awful")
local gears = require("gears")
local beautiful = require("beautiful")
local helpers = require("external.bling.helpers")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")
local cairo = require("lgi").cairo

local tag_preview = {mt = {}}

local function draw_widget(c, widget_width, widget_height)
  if
    not pcall(
      function()
        return type(c.content)
      end
    )
   then
    return
  end

  local content = nil
  if c.active then
    content = gears.surface(c.content)
  elseif c.prev_content then
    content = gears.surface(c.prev_content)
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
    widget = wibox.container.constraint,
    width = widget_width,
    height = widget_height,
    {
      id = "background_role",
      widget = wibox.container.background,
      shape = helpers.shape.rrect(config.dpi(10)),
      {
        widget = wibox.container.margin,
        margins = config.dpi(10),
        {
          layout = wibox.layout.fixed.vertical,
          fill_space = true,
          {
            widget = wibox.container.margin,
            margins = config.dpi(10),
            {
              widget = wibox.container.place,
              halign = "center",
              {
                layout = wibox.layout.fixed.horizontal,
                {
                  id = "icon_role",
                  widget = wibox.widget.imagebox,
                  resize = true,
                  forced_height = config.dpi(20),
                  forced_width = config.dpi(20)
                },
                {
                  widget = wibox.container.margin,
                  left = config.dpi(4),
                  right = config.dpi(4),
                  {
                    id = "name_role",
                    widget = wibox.widget.textbox,
                    align = "center"
                  }
                }
              }
            }
          },
          {
            widget = wibox.container.place,
            halign = "center",
            valign = "top",
            {
              id = "image_role",
              resize = true,
              clip_shape = helpers.shape.rrect(config.dpi(10)),
              widget = wibox.widget.imagebox
            }
          }
        }
      }
    }
  }

  for _, w in ipairs(widget:get_children_by_id("image_role")) do
    w.image = img
  end

  for _, w in ipairs(widget:get_children_by_id("name_role")) do
    w.markup =
      "<span font='" ..
      theme.font ..
        "' foreground='" ..
          beautiful.fg_primary .. "'>" .. c.name:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;") .. "</span>"
  end

  for _, w in ipairs(widget:get_children_by_id("icon_role")) do
    w.image = c.icon
  end

  local background = widget:get_children_by_id("background_role")[1]

  widget:connect_signal(
    "mouse::enter",
    function()
      background.bg = "#333333c0"
    end
  )

  widget:connect_signal(
    "mouse::leave",
    function()
      background.bg = "#00000000"
    end
  )

  widget:buttons(
    gears.table.join(
      awful.button(
        {},
        1,
        nil,
        function()
          awesome.emit_signal("widget::drawer::hide")

          if c ~= nil then
            c:raise()
            client.focus = c
          end
        end
      )
    )
  )

  return widget
end

function tag_preview:show(screen)
  self.grid:reset()
  local clients = screen.selected_tag:clients()
  for _, c in ipairs(clients) do
    c.tag_preview = {
      width = c.width,
      height = c.height,
      x = c.x,
      y = c.y
    }
  end
  for _, c in ipairs(clients) do
    local w =
      draw_widget(c, config.dpi((screen.geometry.width - config.dpi(400) - config.dpi(16) * 9) / 3), config.dpi(300))
    self.grid:add(w)
  end
end

local function new(args)
  args = args or {}
  args.total_width = args.total_width or config.dpi(1000)
  args.total_height = args.total_height or config.dpi(1000)
  args.spacing = args.spacing or config.dpi(16)
  args.padding = args.padding or config.dpi(16)

  local ret = {}
  gears.table.crush(ret, tag_preview)
  gears.table.crush(ret, args)
  ret.grid =
    wibox.widget {
    layout = wibox.layout.grid,
    forced_num_cols = 3,
    spacing = config.dpi(16)
  }
  ret.widget =
    wibox.widget {
    widget = ret.grid,
    spacing = config.dpi(20)
  }

  tag.connect_signal(
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

function tag_preview.mt:__call(...)
  return new(...)
end

return setmetatable(tag_preview, tag_preview.mt)
