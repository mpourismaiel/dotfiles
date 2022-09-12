local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local filesystem = require("gears.filesystem")
local config = require("configuration.config")
local theme = require("configuration.config.theme")

local container = require("configuration.widgets.menu.container")
local clock = require("configuration.widgets.menu.clock")
local weather = require("configuration.widgets.menu.weather")
local power_button = require("configuration.widgets.menu.power-button")
local volumeslider = require("configuration.widgets.volume.slider")
local notification_widget = require("configuration.notifications.widget")
local global_state = require("configuration.config.global_state")
local list = require("configuration.widgets.list")

local config_dir = filesystem.get_configuration_dir()
local menu_icon = config_dir .. "/images/circle.svg"
local close_icon = config_dir .. "/images/x.svg"

local menu = {mt = {}}

function menu.new(screen)
  local toggle_template = {
    widget = wibox.container.constraint,
    strategy = "exact",
    height = config.dpi(48),
    {
      id = "background",
      widget = wibox.container.background,
      bar_widget_wrapper(
        wibox.widget {
          widget = wibox.container.margin,
          margins = config.dpi(4),
          wibox.widget.imagebox(menu_icon)
        }
      )
    },
    buttons = {
      awful.button(
        {},
        1,
        function()
          awesome.emit_signal("widget::drawer:toggle")
        end
      )
    }
  }

  local toggle = wibox.widget.base.make_widget_from_value(toggle_template)
  local background = toggle:get_children_by_id("background")[1]

  toggle:connect_signal(
    "mouse::enter",
    function()
      background.bg = "#eeeeee30"
    end
  )
  toggle:connect_signal(
    "mouse::leave",
    function()
      background.bg = ""
    end
  )

  function table.slice(tbl, first, last, step)
    local sliced = {}

    for i = first or 1, last or #tbl, step or 1 do
      sliced[#sliced + 1] = tbl[i]
    end

    return sliced
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
      local f = finish or #global_state.cache.notifications
      if f - s < 3 then
        s = f - 3
      end
      if s < 1 then
        s = 1
      end
      return table.slice(global_state.cache.notifications, s, f)
    end,
    render_list = list.render_list,
    empty_widget = {
      widget = wibox.widget.textbox,
      markup = "<span color='#ffffffaa' font_size='12pt' font_weight='normal'>No new notifications</span>"
    },
    template = function()
      local template = {
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
      local l = wibox.widget.base.make_widget_from_value(container(template, 16, 16, 8, 8))

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
      cached.title:set_markup("<span font_size='12pt' font_weight='bold' color='#ffffff'>" .. data.title .. "</span>")
      cached.text:set_markup(
        "<span font_size='10pt' font_weight='normal' color='#ffffff'>" .. data.message .. "</span>"
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
              global_state.cache.notifications_remove(data.id)
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
      notifications.finish = #global_state.cache.notifications
    end
  )

  global_state.cache.notifications_subscribe(
    function()
      notifications:emit_signal("update")
    end
  )

  local backdrop =
    wibox {
    ontop = true,
    screen = screen,
    bg = "#ffffff00",
    type = "utility",
    x = screen.geometry.x,
    y = screen.geometry.y,
    width = screen.geometry.width,
    height = screen.geometry.height
  }

  local drawer =
    awful.popup {
    widget = {},
    ontop = true,
    visible = false,
    type = "normal",
    screen = screen,
    width = config.dpi(400),
    height = screen.geometry.height - config.dpi(16),
    shape = gears.shape.rounded_rect,
    placement = function(c)
      return awful.placement.top_left(
        c,
        {
          margins = {
            top = config.dpi(8),
            left = config.dpi(56)
          }
        }
      )
    end,
    bg = "#44444430"
  }

  backdrop:buttons(
    awful.util.table.join(
      awful.button(
        {},
        1,
        function()
          backdrop.visible = false
          drawer.visible = false
        end
      )
    )
  )

  drawer:setup {
    widget = wibox.container.constraint,
    width = config.dpi(400),
    height = screen.geometry.height - config.dpi(16),
    strategy = "exact",
    {
      widget = wibox.container.margin,
      margins = config.dpi(16),
      {
        layout = wibox.layout.align.vertical,
        spacing = config.dpi(16),
        {
          layout = wibox.layout.fixed.vertical,
          spacing = config.dpi(16),
          container(weather()),
          {
            layout = wibox.layout.flex.horizontal,
            spacing = config.dpi(16),
            container(clock())
          }
        },
        {
          widget = wibox.container.margin,
          top = config.dpi(16),
          bottom = config.dpi(16),
          container(
            {
              layout = wibox.layout.fixed.vertical,
              spacing = config.dpi(16),
              {
                widget = wibox.widget.textbox,
                markup = "<span font='Inter bold 14' color='#ffffff'>Notifications</span>"
              },
              notifications
            }
          )
        },
        {
          widget = wibox.container.place,
          valign = "bottom",
          {
            layout = wibox.layout.fixed.vertical,
            spacing = config.dpi(16),
            container(volumeslider),
            {
              layout = wibox.layout.flex.horizontal,
              spacing = config.dpi(8),
              container(power_button("lock")),
              container(power_button("sleep")),
              container(power_button("logout")),
              container(power_button("reboot")),
              container(power_button("power"))
            }
          }
        }
      }
    }
  }

  awesome.connect_signal(
    "widget::drawer:toggle",
    function()
      backdrop.visible = not backdrop.visible
      drawer.visible = not drawer.visible
      notifications.start = 1
      notifications:emit_signal("update")
    end
  )

  awesome.connect_signal(
    "widget::drawer:hide",
    function()
      backdrop.visible = false
      drawer.visible = false
    end
  )

  return toggle
end

function menu.mt:__call(...)
  return menu.new(...)
end

return setmetatable(menu, menu.mt)
