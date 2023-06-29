local wibox = require("wibox")
local awful = require("awful")
local helpers = require("bling.helpers")
local gears = require("gears")
local config = require("configuration.config")
local theme = require("configuration.config.theme")
local cairo = require("lgi").cairo

local tag_preview = {mt = {}}

local function draw_widget(c, widget_width, widget_height, x, y)
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
    width = widget_width,
    height = widget_height,
    widget = wibox.container.constraint,
    {
      shape = helpers.shape.rrect(config.dpi(10)),
      widget = wibox.container.background,
      {
        widget = wibox.container.margin,
        margins = config.dpi(10),
        {
          fill_space = true,
          layout = wibox.layout.fixed.vertical,
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
                  resize = true,
                  forced_height = config.dpi(20),
                  forced_width = config.dpi(20),
                  widget = wibox.widget.imagebox
                },
                {
                  left = config.dpi(4),
                  right = config.dpi(4),
                  widget = wibox.container.margin,
                  {
                    id = "name_role",
                    align = "center",
                    widget = wibox.widget.textbox
                  }
                }
              }
            }
          },
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

  -- TODO: have something like a create callback here?

  for _, w in ipairs(widget:get_children_by_id("image_role")) do
    w.image = img -- TODO: copy it with gears.surface.xxx or something
  end

  for _, w in ipairs(widget:get_children_by_id("name_role")) do
    w.markup =
      "<span font='" ..
      theme.font ..
        "' foreground='#ffffff'>" .. c.name:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;") .. "</span>"
  end

  for _, w in ipairs(widget:get_children_by_id("icon_role")) do
    w.image = c.icon -- TODO: detect clienticon
  end

  widget.point = function(geo, args)
    return {
      x = x,
      y = y
    }
  end

  return widget
end

local function calculateNewDimensions(client, container, spacing, padding, clientsCount)
  local ratio = client.tag_preview.width / client.tag_preview.height
  local newWidth = (container.width - (2 * (spacing + padding) * clientsCount)) / clientsCount
  local newHeight = newWidth / ratio

  if newHeight > (container.height - 2 * (spacing + padding)) then
    newHeight = (container.height - 2 * (spacing + padding)) / clientsCount
    newWidth = newHeight * ratio
  end

  return newWidth, newHeight
end

local function resizeAndPositionClients(clients, container, spacing, padding)
  local clientsCount = 0
  for _ in pairs(clients) do
    clientsCount = clientsCount + 1
  end

  local x = padding
  local y = padding

  for key, client in pairs(clients) do
    local newWidth, newHeight = calculateNewDimensions(client, container, spacing, padding, clientsCount)

    client.tag_preview.width = newWidth
    client.tag_preview.height = newHeight
    client.tag_preview.x = x
    client.tag_preview.y = y

    x = x + newWidth + spacing

    if x + newWidth + padding > container.width then
      x = padding
      y = y + newHeight + spacing
    end

    if y + newHeight + padding > container.height then
      break
    end
  end
end

function tag_preview:show()
  self.list:reset()
  local clients = awful.screen.focused().selected_tag:clients()
  for _, c in ipairs(clients) do
    c.tag_preview = {
      width = c.width,
      height = c.height,
      x = c.x,
      y = c.y
    }
  end
  resizeAndPositionClients(
    clients,
    {
      width = self.total_width,
      height = self.total_height
    },
    self.spacing,
    self.padding
  )
  for _, c in ipairs(clients) do
    local w = draw_widget(c, c.tag_preview.width, c.tag_preview.height, c.tag_preview.x, c.tag_preview.y)
    self.list:add(w)
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
  ret.list =
    wibox.widget {
    layout = wibox.layout.fixed.horizontal,
    spacing = config.dpi(16)
  }
  ret.widget =
    wibox.widget {
    widget = ret.list
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
