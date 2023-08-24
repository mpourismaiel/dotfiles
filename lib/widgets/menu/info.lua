local wibox = require("wibox")
local gears = require("gears")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")
local cpu_daemon = require("lib.daemons.hardware.cpu")
local ram_daemon = require("lib.daemons.hardware.ram")
local keyboard_layout_daemon = require("lib.daemons.hardware.keyboard_layout")
local battery = require("lib.widgets.menu.battery")
local wbutton = require("lib.widgets.button")
local wtext = require("lib.widgets.text")
local console = require("lib.helpers.console")

local instance = nil
local info = {mt = {}}

local function device_widget(image, default_value)
  local w =
    wibox.widget {
    widget = wibox.container.constraint,
    strategy = "exact",
    width = config.dpi(60),
    height = config.dpi(60),
    {
      widget = wbutton,
      bg_normal = theme.bg_secondary,
      rounded = theme.rounded_rect_large,
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
              image = image
            }
          }
        },
        {
          widget = wibox.container.place,
          {
            widget = wtext,
            text = default_value,
            id = "text_role"
          }
        }
      }
    }
  }

  w._private.update_value = function(v)
    w:get_children_by_id("text_role")[1].text = v
  end
  return w
end

local function cpu_widget()
  local w = device_widget(theme.cpu_icon, "50%")
  cpu_daemon:set_slim(false)
  cpu_daemon:connect_signal(
    "update::slim",
    function(self, value)
      w._private.update_value(value .. "%")
    end
  )
  return w
end

local function ram_widget()
  local w = device_widget(theme.ram_icon, "50%")

  ram_daemon:connect_signal(
    "update",
    function(self, total, used, free, shared, buff_cache, available, total_swap, used_swap, free_swap)
      local used_ram_percentage = math.floor((used / total) * 100)
      w._private.update_value(used_ram_percentage .. "%")
    end
  )
  return w
end

local function keyboard_layout_widget()
  local w = device_widget(theme.keyboard_icon, "en")

  keyboard_layout_daemon:connect_signal(
    "update",
    function(self, layout)
      w._private.update_value(layout)
    end
  )

  return w
end

local function new()
  local ret =
    wibox.widget {
    layout = wibox.layout.fixed.horizontal,
    spacing = theme.menu_horizontal_spacing,
    cpu_widget(),
    ram_widget(),
    battery().widget,
    keyboard_layout_widget()
  }
  gears.table.crush(ret, info, true)

  return ret
end

if not instance then
  instance = new()
end
return instance
