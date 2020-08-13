local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local naughty = require("naughty")
local markup = require("lain.util.markup")
local keygrabber = require("awful.keygrabber")
local createAnimObject = require("utils.animation").createAnimObject
local helpers = require("utils.helpers")
local my_table = awful.util.table or gears.table
local theme_pad = awful.util.theme_functions.pad_fn

local pad = helpers.pad
local margin = wibox.container.margin
local constraint = wibox.container.constraint
local background = wibox.container.background
local text = wibox.widget.textbox
local icon = awful.util.theme_functions.icon_fn()
local font = awful.util.theme_functions.font_fn

local panel_bg =
  gears.color(
  {
    type = "linear",
    from = {-20, 0},
    to = {50, 0},
    stops = {{0, "#050505"}, {1, awful.util.theme_functions.bg_panel}}
  }
)

function widget_info(w1, w2, w3, margins)
  margins = margins or 0
  local marginalizedW2 = margin(w2)
  local ret =
    wibox.widget {
    {
      {
        w1,
        marginalizedW2,
        layout = wibox.layout.fixed.horizontal
      },
      nil,
      w3,
      layout = wibox.layout.align.horizontal
    },
    widget = margin,
    left = 40,
    right = 40,
    top = margins + 10,
    bottom = margins + 10
  }
  ret:connect_signal(
    "mouse::enter",
    function()
      createAnimObject(1, marginalizedW2, {left = 10}, "outCubic")
    end
  )
  ret:connect_signal(
    "mouse::leave",
    function()
      createAnimObject(1, marginalizedW2, {left = 0}, "outCubic")
    end
  )
  return ret
end

function widget_button(w, action)
  local bg_normal = awful.util.theme_functions.widget_bg .. "00"
  local bg_hover = awful.util.theme_functions.widget_bg .. "ff"

  w = background(w, bg_normal)
  w:connect_signal(
    "mouse::enter",
    function()
      w.bg = bg_hover
    end
  )

  w:connect_signal(
    "mouse::leave",
    function()
      w.bg = bg_normal
    end
  )

  w:buttons(my_table.join(awful.button({}, 1, action)))

  return w
end

local notification_screen =
  wibox {
  visible = false,
  screen = nil
}
local backdrop = wibox {type = "dock", x = 0, y = 0}
local notification_screen_grabber

function notification_screen_show(show_rofi)
  local s = awful.screen.focused()
  local screen_width = s.geometry.width
  local screen_height = s.geometry.height
  backdrop =
    wibox(
    {
      type = "dock",
      height = screen_height,
      width = screen_width,
      x = 0,
      y = 0,
      screen = s,
      ontop = true,
      visible = true,
      opacity = 1,
      bg = beautiful.wibar_bg .. "cc"
    }
  )
  notification_screen =
    wibox(
    {
      x = screen_width - 400,
      y = 0,
      visible = true,
      ontop = true,
      screen = s,
      type = "dock",
      height = screen_height,
      width = 450,
      opacity = 1,
      bg = beautiful.wibar_bg
    }
  )
  -- createAnimObject(0.6, notification_screen, {x = screen_width - 400, opacity = 1}, "outCubic")
  -- createAnimObject(0.6, backdrop, {opacity = 1}, "outCubic")

  backdrop:buttons(
    awful.util.table.join(
      awful.button(
        {},
        1,
        function()
          notification_screen_hide()
        end
      )
    )
  )

  notification_screen_setup(s, show_rofi)
end

function notification_screen_hide()
  local s = awful.screen.focused()
  backdrop.visible = false
  notification_screen.x = screen_width
  notification_screen.opacity = 0
  notification_screen.visible = false
  -- createAnimObject(
  --   0.6,
  --   notification_screen,
  --   {x = screen_width, opacity = 0},
  --   "outCubic",
  --   function()
  --     notification_screen.visible = false
  --   end
  -- )
  gears.timer {
    autostart = true,
    timeout = 1,
    callback = function()
      awful.keygrabber.stop(notification_screen_grabber)
    end
  }
end

function title(txt)
  return text(markup("#FFFFFF", markup.font("FiraCode Bold 14", txt)))
end

awful.util.disable_notification = 0
local disable_notification_icon = icon("", 10, true, true)
local disable_notification_text = text(markup("#FFFFFF", theme_pad(2) .. "Disable Notifications"))
local disable_notification =
  widget_button(
  widget_info(disable_notification_icon, disable_notification_text, nil, 10),
  function()
    if awful.util.disable_notification == 0 then
      awful.util.disable_notification = 1
      disable_notification_icon:set_markup(icon("", 10, true, true, true))
      disable_notification_text:set_markup(markup("#FFFFFF", theme_pad(2) .. "Disable All Notifications"))
    elseif awful.util.disable_notification == 1 then
      awful.util.disable_notification = 2
      disable_notification_icon:set_markup(icon("", 10, true, true, true))
      disable_notification_text:set_markup(markup("#FFFFFF", theme_pad(2) .. "Enable Notifications"))
    elseif awful.util.disable_notification == 2 then
      awful.util.disable_notification = 0
      disable_notification_icon:set_markup(icon("", 10, true, true, true))
      disable_notification_text:set_markup(markup("#FFFFFF", theme_pad(2) .. "Disable Notifications"))
    end
  end
)

local notification_message = require("widgets.notification.message")
local notification_list =
  naughty.list.notifications {
  base_layout = wibox.widget {
    spacing = 20,
    layout = wibox.layout.fixed.vertical
  },
  widget_template = {
    {
      {
        {
          {
            widget = naughty.widget.icon
          },
          widget = constraint,
          strategy = "exact",
          width = 48,
          height = 48
        },
        {
          {
            naughty.widget.title,
            margin(text(""), 0, 0, 10),
            notification_message,
            {
              layout = wibox.widget {
                spacing_widget = wibox.widget {
                  orientation = "vertical",
                  span_ratio = 0.9,
                  widget = wibox.widget.separator
                },
                spacing = 3,
                layout = wibox.layout.flex.vertical
              },
              widget = naughty.list.widgets
            },
            layout = wibox.layout.fixed.vertical
          },
          widget = constraint,
          strategy = "exact",
          width = 189,
          height = 48
        },
        {
          {
            {
              widget = icon("", 10, true, true)
            },
            widget = wibox.container.place,
            valign = "center",
            halign = "center"
          },
          widget = constraint,
          strategy = "exact",
          width = 20,
          height = 48
        },
        spacing = 10,
        fill_space = true,
        layout = wibox.layout.fixed.horizontal
      },
      widget = margin,
      left = 40,
      right = 20,
      top = 10,
      bottom = 10
    },
    widget = background,
    bg = "#3f3f3f44"
  }
}

local empty_notification_message = margin(text(markup("#bbbbbb", font("You have no notifications!"))), 40, 40, 20)
empty_notification_message.visible = #naughty.active == 0

naughty.connect_signal(
  "property::active",
  function()
    empty_notification_message.visible = #naughty.active == 0
  end
)

local close_button = widget_button(wibox.container.margin(wibox.container.place(icon("", 12)), 20, 20, 15, 15))
close_button:buttons(
  awful.util.table.join(
    awful.button(
      {},
      1,
      function()
        naughty.destroy_all_notifications()
      end
    )
  )
)

local widgets = {
  {
    nil,
    {
      background(
        wibox.widget {
          close_button,
          margin(title("Notifications"), 20, 40, 15, 15),
          layout = wibox.layout.fixed.horizontal
        },
        panel_bg
      ),
      margin(pad(0), 0, 0, 10),
      notification_list,
      empty_notification_message,
      layout = wibox.layout.fixed.vertical
    },
    disable_notification,
    layout = wibox.layout.align.vertical
  },
  widget = background,
  bg = panel_bg
}

function notification_screen_setup(s)
  notification_screen_grabber =
    awful.keygrabber.run(
    function(_, key, event)
      if event == "release" then
        return
      end
      if key == "Escape" or key == "q" or key == "x" then
        notification_screen_hide()
      end
    end
  )

  notification_screen:setup(widgets)
end
