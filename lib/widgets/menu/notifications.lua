local wibox = require("wibox")
local awful = require("awful")
local gears = require("gears")
local beautiful = require("beautiful")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")
local color = require("lib.helpers.color")
local global_state = require("lib.configuration.global_state")
local woverflow = require("wibox.layout.overflow")
local wbutton = require("lib.widgets.button")
local wcontainer = require("lib.widgets.menu.container")
local wscrollbar = require("lib.widgets.scrollbar")
local wtext = require("lib.widgets.text")
local list = require("lib.widgets.list")
local store = require("lib.module.store")

local preferences = store("preferences")

local clear_notifications =
  wibox.widget {
  widget = wbutton,
  padding_top = config.dpi(4),
  padding_bottom = config.dpi(4),
  padding_left = config.dpi(8),
  padding_right = config.dpi(8),
  callback = function()
    global_state.cache.update("notifications", {})
  end,
  {
    widget = wibox.widget.textbox,
    markup = "<span color='" .. beautiful.fg_normal .. "' font_size='10pt' font_weight='normal'>Clear all</span>"
  }
}

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
    layout = woverflow.vertical,
    forced_width = config.dpi(1000),
    spacing = config.dpi(10),
    scrollbar_widget = wscrollbar,
    scrollbar_width = config.dpi(10),
    step = 100
  },
  source = function()
    return global_state.cache.get("notifications")
  end,
  render_list = list.render_list,
  empty_widget = {
    widget = wtext,
    text = "No new notifications"
  },
  template = function()
    local template = {
      widget = wibox.container.constraint,
      height = config.dpi(150),
      strategy = "max",
      {
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
            layout = woverflow.vertical,
            forced_width = config.dpi(1000),
            spacing = config.dpi(10),
            scrollbar_widget = wscrollbar,
            scrollbar_width = config.dpi(10),
            step = 200,
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
        cached.container:add(actions)
      end
      cached.rendered_actions = true
    end
  end
}

notifications:connect_signal(
  "updated",
  function()
    clear_notifications.visible = #global_state.cache.get("notifications") > 0
  end
)

global_state.cache.listen(
  "notifications",
  function()
    notifications:emit_signal("update")
  end
)

local wp = {}
local notifications_widget =
  wibox.widget {
  layout = wibox.layout.fixed.vertical,
  spacing = config.dpi(16),
  {
    layout = wibox.layout.align.horizontal,
    {
      layout = wibox.layout.fixed.horizontal,
      spacing = config.dpi(10),
      {
        widget = wbutton,
        paddings = config.dpi(8),
        callback = function()
          preferences:toggle("dnd")
          wp.update_icon()
        end,
        {
          widget = wibox.container.constraint,
          strategy = "exact",
          width = config.dpi(16),
          height = config.dpi(16),
          {
            widget = wibox.widget.imagebox,
            id = "icon_role",
            image = theme.notification_icon
          }
        }
      },
      {
        widget = wtext,
        text = "Notifications",
        bold = true,
        font_size = config.dpi(14),
        foreground = theme.fg_primary
      }
    },
    nil,
    clear_notifications
  },
  notifications
}

wp.icon_role = notifications_widget:get_children_by_id("icon_role")[1]
wp.update_icon = function()
  wp.icon_role.image = preferences:get("dnd") and theme.notification_title_dnd_icon or theme.notification_title_icon
end

notifications_widget.reset = function()
  notifications:set_scroll_factor(0)
  notifications:emit_signal("update")
end

wp.update_icon()
return notifications_widget
