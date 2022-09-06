local wibox = require("wibox")
local awful = require("awful")
local gears = require("gears")
local config = require("configuration.config")

local function launcher_widget_template(app_list)
  local query_input_wrapper =
    wibox.widget.base.make_widget_from_value {
    widget = wibox.container.background,
    shape = gears.shape.rounded_rect,
    bg = "#666666aa",
    border_width = config.dpi(2),
    border_color = "#eeeeee66",
    {
      widget = wibox.container.margin,
      margins = config.dpi(1),
      {
        widget = wibox.container.margin,
        left = config.dpi(16),
        right = config.dpi(16),
        {
          widget = wibox.container.constraint,
          strategy = "exact",
          height = config.dpi(40),
          width = config.dpi(400),
          {
            widget = wibox.container.background,
            bg = "#00000000",
            id = "select_box",
            {
              widget = wibox.widget.textbox,
              id = "query"
            }
          }
        }
      }
    }
  }
  local query_select_box = query_input_wrapper:get_children_by_id("select_box")[1]
  local query_input = query_input_wrapper:get_children_by_id("query")[1]

  local parent_selector = wibox.widget {}

  local widget =
    awful.popup {
    widget = {},
    type = "normal",
    ontop = true,
    visible = false,
    shape = gears.shape.rounded_rect,
    bg = "#11111130",
    placement = awful.placement.top_left(c),
    width = awful.screen.focused().geometry.width,
    height = awful.screen.focused().geometry.height,
    screen = awful.screen.focused()
  }

  widget:setup {
    widget = wibox.container.constraint,
    strategy = "exact",
    width = awful.screen.focused().geometry.width,
    height = awful.screen.focused().geometry.height,
    {
      widget = wibox.container.place,
      halign = "center",
      valign = "top",
      {
        layout = wibox.layout.fixed.vertical,
        {
          widget = wibox.container.place,
          halign = "center",
          {
            widget = wibox.container.margin,
            top = config.dpi(100),
            {
              layout = wibox.layout.fixed.vertical,
              parent_selector,
              {
                widget = wibox.container.margin,
                top = config.dpi(16),
                query_input_wrapper
              }
            }
          }
        },
        {
          widget = wibox.container.margin,
          top = config.dpi(100),
          bottom = config.dpi(100),
          {
            widget = wibox.container.constraint,
            strategy = "exact",
            width = config.dpi(1200),
            {
              widget = wibox.container.place,
              halign = "center",
              app_list
            }
          }
        }
      }
    }
  }

  return {
    widget = widget,
    input = query_input,
    input_select = query_select_box
  }
end

return launcher_widget_template
