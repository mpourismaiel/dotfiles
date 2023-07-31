local wibox = require("wibox")
local gears = require("gears")
local config = require("configuration.config")
local theme = require("configuration.config.theme")
local wcontainer = require("configuration.widgets.menu.container")
local wtext = require("configuration.widgets.text")

local profile = {mt = {}}

local function new()
  if not config.profile_image then
    return wibox.widget {}
  end

  local username = os.getenv("USER")

  local ret =
    wibox.widget {
    widget = wcontainer,
    {
      layout = wibox.layout.fixed.horizontal,
      spacing = theme.menu_horizontal_spacing,
      {
        widget = wibox.container.constraint,
        strategy = "exact",
        width = config.dpi(36),
        height = config.dpi(36),
        {
          widget = wibox.widget.imagebox,
          image = config.profile_image,
          resize = true
        }
      },
      {
        widget = wibox.container.place,
        valign = "center",
        {
          widget = wtext,
          text = username,
          font_weight = "bold",
          font_size = config.dpi(12)
        }
      }
    }
  }

  gears.table.crush(ret, profile, true)

  return ret
end

function profile.mt:__call(...)
  return new(...)
end

return setmetatable(profile, profile.mt)
