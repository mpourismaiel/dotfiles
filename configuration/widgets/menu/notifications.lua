local wibox = require("wibox")
local awful = require("awful")
local gears = require("gears")
local beautiful = require("beautiful")
local config = require("configuration.config")
local theme = require("configuration.config.theme")
local color = require("helpers.color")
local global_state = require("configuration.config.global_state")
local wbutton = require("configuration.widgets.button")
local wcontainer = require("configuration.widgets.menu.container")
local wtext = require("configuration.widgets.text")
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

local function actions_widget(n, cache)
  if not n.actions or #(n.actions) == 0 then
    return nil
  end

  local actions =
    wibox.widget {
    layout = wibox.layout.fixed.horizontal,
    spacing = config.dpi(15)
  }

  for _, action in ipairs(n.actions) do
    local button =
      wibox.widget {
      widget = wbutton,
      bg_normal = color.helpers.change_opacity(theme.bg_primary, 0.6),
      padding_top = theme.notification_padding_top,
      padding_bottom = theme.notification_padding_bottom,
      padding_left = theme.notification_padding_left,
      padding_right = theme.notification_padding_right,
      callback = function()
        action:invoke()
        cache.container:remove(3)
      end,
      label = action.name
    }
    actions:add(button)
  end

  return wibox.widget {
    widget = wibox.container.margin,
    margins = config.dpi(10),
    {
      widget = wibox.container.place,
      halign = theme.notification_action_halign,
      actions
    }
  }
end

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
      padding_left = 0,
      padding_right = 0,
      padding_top = 0,
      padding_bottom = 0,
      {
        layout = wibox.layout.fixed.vertical,
        id = "container",
        {
          widget = wibox.container.background,
          bg = color.helpers.change_opacity(theme.bg_secondary, 0.6),
          {
            widget = wibox.container.margin,
            margins = config.dpi(10),
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
                widget = wtext,
                id = "title"
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
                    image = theme.notification_close_icon
                  }
                }
              }
            }
          }
        },
        {
          widget = wibox.container.margin,
          margins = config.dpi(10),
          {
            widget = wtext,
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
      container = l:get_children_by_id("container")[1],
      primary = l
    }
  end,
  render_template = function(cached, data)
    cached.title:set_text(data.title)
    cached.text:set_text(data.message)

    if data.icon then
      local icon = gears.surface.load_silently(data.icon)
      cached.image:set_image(icon)
    else
      cached.image_container.visible = false
    end

    if not cached.rendered_close then
      cached.close.buttons = {
        awful.button(
          {},
          1,
          function()
            global_state.cache.remove("notifications", data.id)
          end
        )
      }
      cached.rendered_close = true
    end

    if not cached.rendered_actions then
      local actions = actions_widget(data, cached)
      if actions then
        cached.container:add()
      end
      cached.rendered_actions = true
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
