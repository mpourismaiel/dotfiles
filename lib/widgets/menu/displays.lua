local wibox = require("wibox")
local gears = require("gears")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")
local display_daemon = require("lib.daemons.hardware.display")
local wcontainer = require("lib.widgets.menu.container")
local wbutton = require("lib.widgets.button")
local wtext = require("lib.widgets.text")

local displays = {mt = {}}

local function display_widget(display)
  local name = display.title
  name = name:gsub("-", " "):gsub("^%l", string.upper)

  local w =
    wibox.widget {
    widget = wbutton,
    halign = "left",
    {
      layout = wibox.layout.fixed.horizontal,
      spacing = theme.menu_horizontal_spacing,
      id = "inside_role",
      {
        widget = wibox.container.constraint,
        strategy = "exact",
        width = config.dpi(16),
        height = config.dpi(16),
        {
          widget = wibox.container.place,
          {
            widget = wibox.widget.imagebox,
            image = theme.displays_icon
          }
        }
      },
      {
        widget = wtext,
        text = name
      }
    }
  }

  return w
end

local function new(args)
  args = args or {}
  args.width = args.width or config.dpi(400)
  args.height = args.height or config.dpi(400)

  local ret = {_private = {}}
  gears.table.crush(ret, displays)

  local wp = ret._private
  wp.callback = args.callback or nil

  wp.toggle =
    wibox.widget {
    widget = wbutton,
    strategy = "exact",
    width = config.dpi(60),
    height = config.dpi(60),
    bg_normal = theme.bg_secondary,
    rounded = theme.rounded_rect_large,
    callback = function()
      if not wp.callback then
        return
      end
      local screen_height = wp.callback("Display Manager", wp.menu)
      wp.menu.height = screen_height
    end,
    paddings = 0,
    {
      layout = wibox.layout.fixed.vertical,
      spacing = config.dpi(8),
      {
        widget = wibox.container.constraint,
        strategy = "exact",
        width = config.dpi(16),
        height = config.dpi(16),
        {
          widget = wibox.container.place,
          {
            widget = wibox.widget.imagebox,
            image = theme.displays_icon
          }
        }
      },
      {
        widget = wtext,
        id = "default_display_title_role"
      }
    }
  }

  wp.menu =
    wibox.widget {
    widget = wibox.container.constraint,
    strategy = "exact",
    width = args.width,
    height = args.height,
    {
      widget = wcontainer,
      {
        layout = wibox.layout.fixed.vertical,
        spacing = theme.menu_vertical_spacing,
        id = "list_role"
      }
    }
  }

  wp.list_role = wp.menu:get_children_by_id("list_role")[1]
  wp.default_display_title_role = wp.toggle:get_children_by_id("default_display_title_role")[1]

  display_daemon:connect_signal(
    "property::list",
    function(self, list)
      wp.list_role:reset()
      for _, display in pairs(list) do
        wp.list_role:add(display_widget(display))
      end
    end
  )

  display_daemon:connect_signal(
    "default::display",
    function(self, display)
      wp.default_display_title_role:set_text(display)
    end
  )

  ret.toggle = wp.toggle
  return ret
end

function displays.mt:__call(...)
  return new(...)
end

return setmetatable(displays, displays.mt)
