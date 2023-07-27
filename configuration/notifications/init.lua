local naughty = require("naughty")
local gears = require("gears")
local awful = require("awful")
local wibox = require("wibox")
local animation = require("helpers.animation")
local config = require("configuration.config")
local theme = require("configuration.config.theme")
local color = require("helpers.color")
local wbutton = require("configuration.widgets.button")
local wtext = require("configuration.widgets.text")
local global_state = require("configuration.config.global_state")

local c = global_state.cache
local notification_timeout = 5

local function actions_widget(n)
  if not n.actions or #(n.actions) == 0 then
    return
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

local function escape_markup_string(s)
  return s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
end

naughty.connect_signal(
  "request::display",
  function(n)
    local screen = awful.screen.focused()
    if not screen.notifications then
      screen.notifications = {}
    end

    c.add("notifications", n)

    if global_state.cache.get("lockscreen") then
      return
    end

    n:set_timeout(4294967)
    n.anim_data = {y = 0, opacity = 0.0}
    local function placement_fn(w)
      local theme_position = theme.notification_position
      local position = {}
      if theme_position == "bottom_right" then
        position.fn = awful.placement.bottom_right
        position.margins = {bottom = n.anim_data.y, right = config.dpi(10)}
      end
      local result = position.fn(w, {margins = position.margins, pretend = true})
      w.x = result.x
      w.y = result.y
    end

    local w =
      awful.popup {
      maximum_height = theme.notification_max_height,
      width = theme.notification_width,
      ontop = true,
      screen = screen,
      bg = color.helpers.change_opacity(theme.bg_normal, theme.transparency),
      opacity = n.anim_data.opacity,
      shape = function(cr, width, height)
        gears.shape.rounded_rect(cr, width, height, theme.rounded_rect_large)
      end,
      widget = {
        widget = wibox.container.constraint,
        width = theme.notification_width,
        strategy = "exact",
        {
          layout = wibox.layout.fixed.vertical,
          (n.title ~= "" or n.icon ~= nil) and
            {
              widget = wibox.container.background,
              bg = color.helpers.change_opacity(theme.bg_secondary, 0.6),
              {
                widget = wibox.container.margin,
                margins = config.dpi(10),
                {
                  layout = wibox.layout.fixed.horizontal,
                  n.icon and
                    {
                      widget = wibox.container.margin,
                      right = config.dpi(10),
                      {
                        widget = wibox.container.constraint,
                        width = theme.notification_icon_size,
                        height = theme.notification_icon_size,
                        strategy = "exact",
                        {
                          widget = wibox.widget.imagebox,
                          image = n.icon or n.app_icon
                        }
                      }
                    } or
                    nil,
                  n.title and
                    {
                      widget = wtext,
                      foreground = theme.fg_primary,
                      font_weight = "Bold",
                      text = escape_markup_string(n.title)
                    } or
                    nil
                }
              }
            } or
            nil,
          {
            layout = wibox.layout.fixed.vertical,
            {
              widget = wibox.container.margin,
              margins = config.dpi(10),
              {
                widget = wtext,
                foreground = theme.fg_normal,
                text = escape_markup_string(n.message)
              }
            },
            actions_widget(n)
          }
        }
      }
    }

    n.widget = w

    local targetY = 10
    for _, prev_notification in ipairs(screen.notifications) do
      targetY = targetY + prev_notification.widget.height + 10
    end
    n.anim_data.y = targetY - 10
    placement_fn(n.widget)

    n.animation =
      animation {
      subject = n.anim_data,
      targets = {visible = {y = targetY, opacity = 1.0}, invisible = {y = targetY - 10, opacity = 0.0}},
      easing = "inOutCubic",
      duration = 0.25,
      signals = {
        ["anim::animation_started"] = function(s)
          n.widget.visible = true
        end,
        ["anim::animation_updated"] = function(s, delta)
          placement_fn(n.widget)
          n.widget.opacity = n.anim_data.opacity
        end,
        ["anim::animation_finished"] = function(s)
          if s.subject.y <= 0 then
            n.widget.visible = false
            n:destroy()
            n:emit_signal("notification_destroyed")
          end
        end
      }
    }

    table.insert(screen.notifications, n)
    n.animation.visible:startAnimation()

    n:connect_signal(
      "reposition",
      function()
        if n.reposition_animation then
          n.reposition_animation.resposition:stopAnimation()
        end

        local targetY = 10
        for _, prev_notification in ipairs(screen.notifications) do
          if prev_notification == n then
            break
          end
          targetY = targetY + prev_notification.widget.height + 10
        end
        n.animation.invisible.target.y = targetY - 10

        n.reposition_animation =
          animation {
          subject = n.anim_data,
          targets = {resposition = {y = targetY}},
          easing = "inOutCubic",
          duration = 0.25,
          signals = {
            ["anim::animation_updated"] = function(s, delta)
              placement_fn(n.widget)
            end
          }
        }

        n.reposition_animation.resposition:startAnimation()
      end
    )

    n:connect_signal(
      "notification_destroyed",
      function()
        for i, notification in ipairs(screen.notifications) do
          if notification == n then
            table.remove(screen.notifications, i)
            n.disapear_timer:stop()

            for _, prev_notification in ipairs(screen.notifications) do
              prev_notification:emit_signal("reposition")
            end

            break
          end
        end
      end
    )

    local time_remaining = notification_timeout
    local disapearing = false
    n.disapear_timer =
      gears.timer {
      timeout = 0.2,
      autostart = true,
      single_shot = false,
      callback = function()
        if
          time_remaining <= 0 and
            (not n.reposition_animation or not n.reposition_animation.resposition or
              not n.reposition_animation.resposition.animating)
         then
          disapearing = true
          n.animation.invisible:startAnimation()
          n.disapear_timer:stop()
        elseif time_remaining > 0 then
          time_remaining = time_remaining - 0.2
        end
      end
    }

    n.widget:connect_signal(
      "mouse::enter",
      function()
        n.disapear_timer:stop()
      end
    )

    n.widget:connect_signal(
      "mouse::leave",
      function()
        if disapearing then
          return
        end
        n.disapear_timer:again()
      end
    )

    n.widget.buttons =
      gears.table.join(
      awful.button(
        {},
        1,
        function()
          disapearing = true
          n.animation.invisible:startAnimation()
          n.disapear_timer:stop()
        end
      )
    )
  end
)
