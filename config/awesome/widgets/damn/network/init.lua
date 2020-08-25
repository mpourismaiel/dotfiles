local capi = {
  awesome = awesome,
  client = client
}
local setmetatable = setmetatable
local pairs = pairs
local ipairs = ipairs
local table = table
local beautiful = require("beautiful")
local awful = require("awful")
local wibox = require("wibox")
local naughty = require("naughty")
local gears = require("gears")
local fixed = require("wibox.layout.fixed")
local timer = require("gears.timer")
local base = require("wibox.widget.base")
local http_request = require "http.request"
local json = require("json")
local ltn12 = require("ltn12")
local clickable_container = require("widgets.clickable-container")

local network_manager = {mt = {}}

local function network_list_update(widget, buttons, data, style, update_function, args)
  local resp = {}
  local headers, stream = assert(http_request.new_from_uri("http://localhost:9103/list"):go())
  local body = assert(stream:get_body_as_string())
  if headers:get ":status" == "200" then
    local resp_json = json.decode(body)
    update_function(
      widget,
      buttons,
      data,
      resp_json,
      {
        widget_template = args.widget_template
      }
    )
  end
end

function network_manager.new(args, buttons, style, update_function, base_widget)
  local widget = base.make_widget_from_value(args.layout or fixed.vertical)

  local margins =
    args and args.margins or
    {
      bottom = 50,
      right = 0
    }

  if widget.set_spacing and (args.style and args.style.spacing) then
    widget:set_spacing(args.style and args.style.spacing)
  end

  local indicator = wibox.widget.textbox()
  local indicator_widget =
    clickable_container(wibox.container.constraint(wibox.container.place(indicator), "exact", 36))
  widget.indicator_widget = indicator_widget

  function widget.update_indicator(signal)
    indicator:set_markup(awful.util.theme_functions.icon_string({ icon = "", font = "Font Awesome 5 Pro" }))
  end

  widget.update_indicator()
  local popup =
    awful.popup {
    screen = awful.screen.focused(),
    visible = false,
    ontop = true,
    shape = function(cr, w, h)
      return gears.shape.partially_rounded_rect(cr, w, h, true, true, false, false, 5)
    end,
    border_width = 2,
    border_color = beautiful.separator,
    offset = {y = 5},
    widget = widget
  }
  widget.popup = popup

  local data = setmetatable({}, {__mode = "k"})
  local queued_update = {}
  function widget._do_network_list_update_now()
    network_list_update(widget, args.buttons, data, args.style, args.update_function, args)
    queued_update[widget] = false
  end

  function widget._do_network_list_update()
    -- Add a delayed callback for the first update.
    if not queued_update[widget] then
      timer.delayed_call(widget._do_network_list_update_now)
      queued_update[widget] = true
    end
  end

  local update_timer =
    gears.timer {
    autostart = false,
    timeout = 30,
    callback = function()
      widget._do_network_list_update()
    end
  }

  -- widget._do_network_list_update()

  indicator_widget:buttons(
    {
      awful.button(
        {},
        awful.button.names.LEFT,
        function()
          if popup.visible then
            popup.visible = not popup.visible
          else
            update_timer:stop()
            widget._do_network_list_update()
            gears.timer.delayed_call(
              function()
                update_timer:start()
                popup.visible = true
                awful.placement.bottom_right(
                  popup,
                  {
                    margins = {
                      bottom = 50,
                      right = 0
                    },
                    parent = awful.screen.focused()
                  }
                )
              end
            )
          end
        end
      )
    }
  )
  indicator_widget.visible = false

  return widget
end

function network_manager.mt:__call(...)
  return network_manager.new(...)
end

return setmetatable(network_manager, network_manager.mt)
