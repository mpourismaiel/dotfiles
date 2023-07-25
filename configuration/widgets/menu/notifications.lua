local wibox = require("wibox")
local awful = require("awful")
local gears = require("gears")
local beautiful = require("beautiful")
local config = require("configuration.config")
local theme = require("configuration.config.theme")
local global_state = require("configuration.config.global_state")
local wcontainer = require("configuration.widgets.menu.container")
local list = require("configuration.widgets.list")

function table.slice(tbl, first, last, step)
  local sliced = {}

  for i = first or 1, last or #tbl, step or 1 do
    sliced[#sliced + 1] = tbl[i]
  end

  return sliced
end

local clear_notifications =
  wibox.widget {
  widget = wibox.container.place,
  halign = "middle",
  {
    widget = wibox.widget.textbox,
    markup = "<span color='" .. beautiful.fg_normal .. "' font_size='10pt' font_weight='normal'>Clear all</span>"
  }
}

clear_notifications:buttons(
  gears.table.join(
    awful.button(
      {},
      1,
      nil,
      function()
        global_state.cache.update("notifications", {})
      end
    )
  )
)

local notifications =
  list {
  layout = {
    layout = wibox.layout.fixed.vertical,
    spacing = config.dpi(8),
    fill_space = true
  },
  source = function(start, finish)
    local s = start or 1
    local f = finish or #global_state.cache.get("notifications")
    if f - s < 3 then
      s = f - 3
    end
    if s < 1 then
      s = 1
    end
    return table.slice(global_state.cache.get("notifications"), s, f)
  end,
  render_list = list.render_list,
  empty_widget = {
    widget = wibox.widget.textbox,
    markup = "<span color='" ..
      beautiful.fg_normal .. "' font_size='12pt' font_weight='normal'>No new notifications</span>"
  },
  template = function()
    local template = {
      widget = wcontainer,
      bg = theme.bg_normal,
      padding_left = config.dpi(8),
      padding_right = config.dpi(8),
      {
        layout = wibox.layout.fixed.horizontal,
        fill_space = true,
        {
          widget = wibox.container.margin,
          right = config.dpi(16),
          id = "image_container",
          {
            widget = wibox.container.place,
            valign = "top",
            {
              widget = wibox.widget.imagebox,
              forced_height = config.dpi(32),
              forced_width = config.dpi(32),
              id = "image"
            }
          }
        },
        {
          layout = wibox.layout.fixed.vertical,
          spacing = config.dpi(8),
          {
            layout = wibox.layout.stack,
            {
              widget = wibox.container.place,
              halign = "left",
              valign = "top",
              {
                widget = wibox.widget.textbox,
                id = "title"
              }
            },
            {
              widget = wibox.container.place,
              halign = "right",
              valign = "top",
              {
                widget = wibox.container.margin,
                margins = config.dpi(4),
                id = "close",
                {
                  widget = wibox.widget.imagebox,
                  forced_height = config.dpi(16),
                  forced_width = config.dpi(16),
                  image = close_icon
                }
              }
            }
          },
          {
            widget = wibox.widget.textbox,
            id = "text"
          }
        }
      }
    }
    local l = wibox.widget.base.make_widget_from_value(template)

    return {
      title = l:get_children_by_id("title")[1],
      text = l:get_children_by_id("text")[1],
      image = l:get_children_by_id("image")[1],
      image_container = l:get_children_by_id("image_container")[1],
      close = l:get_children_by_id("close")[1],
      primary = l
    }
  end,
  render_template = function(cached, data)
    cached.title:set_markup(
      "<span font_size='12pt' font_weight='bold' color='" .. beautiful.fg_primary .. "'>" .. data.title .. "</span>"
    )
    cached.text:set_markup(
      "<span font_size='10pt' font_weight='normal' color='" .. beautiful.fg_primary .. "'>" .. data.message .. "</span>"
    )

    if data.icon then
      local icon = gears.surface.load_silently(data.icon)
      cached.image:set_image(icon)
    else
      cached.image_container.visible = false
    end

    if cached.close._initiated ~= true then
      cached.close.buttons = {
        awful.button(
          {},
          1,
          function()
            global_state.cache.remove("notifications", data.id)
          end
        )
      }
      cached.close._initiated = true
    end
  end
}

notifications.buttons =
  gears.table.join(
  awful.button(
    {},
    5,
    nil,
    function()
      notifications.start = (notifications.start or 1) + 1
      if notifications.start > (notifications.finish or 1) then
        notifications.start = notifications.finish
      end
      notifications:emit_signal("update")
    end
  ),
  awful.button(
    {},
    4,
    nil,
    function()
      notifications.start = (notifications.start or 1) - 1
      if notifications.start < 1 then
        notifications.start = 1
      end
      notifications:emit_signal("update")
    end
  )
)

notifications:connect_signal(
  "updated",
  function()
    notifications.finish = #global_state.cache.get("notifications")
    clear_notifications.visible = #global_state.cache.get("notifications") > 0
  end
)

global_state.cache.listen(
  "notifications",
  function()
    notifications:emit_signal("update")
  end
)

local notifications_widget = {
  layout = wibox.layout.fixed.vertical,
  spacing = config.dpi(16),
  {
    layout = wibox.layout.align.horizontal,
    {
      widget = wibox.widget.textbox,
      markup = "<span font='Inter bold 14' color='" .. beautiful.fg_primary .. "'>Notifications</span>"
    },
    nil,
    clear_notifications
  },
  notifications
}

notifications_widget.reset = function()
  notifications.start = 1
  notifications:emit_signal("update")
end

return notifications_widget
