local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local filesystem = require("gears.filesystem")
local config = require("configuration.config")
local theme = require("configuration.config.theme")

local container = require("configuration.widgets.menu.container")
local menu_column = require("configuration.widgets.menu.menu_column")
local clock = require("configuration.widgets.menu.clock")
local notifications = require("configuration.widgets.menu.notifications")
local power_button = require("configuration.widgets.menu.power-button")
local volumeslider = require("configuration.widgets.volume.slider")
local tag_preview = require("configuration.widgets.menu.tag_preview")
local launcher = require("configuration.widgets.menu.launcher")()
local prompt = require("configuration.widgets.menu.launcher.prompt")

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
    bg = "#ffffff00",
    type = "utility",
    screen = screen,
    height = screen.geometry.height - config.dpi(16),
    placement = function(c)
      return awful.placement.top_left(
        c,
        {
          margins = {
            top = 0,
            left = config.dpi(48)
          }
        }
      )
    end
  }

  backdrop:buttons(
    awful.util.table.join(
      awful.button(
        {},
        1,
        function()
          awesome.emit_signal("widget::drawer:hide")
        end
      )
    )
  )

  local args = {}
  args.prompt_height = args.prompt_height or config.dpi(60)
  args.prompt_paddings = args.prompt_paddings or config.dpi(10)
  args.prompt_shape = args.prompt_shape or gears.shape.rounded_rect
  args.prompt_color = args.prompt_color or "#FFFFFF"
  args.prompt_border_color = args.prompt_border_color or args.prompt_color
  args.prompt_text_halign = args.prompt_text_halign or "left"
  args.prompt_text_valign = args.prompt_text_valign or "center"
  args.prompt_icon_text_spacing = args.prompt_icon_text_spacing or config.dpi(10)
  args.prompt_show_icon = args.prompt_show_icon == nil and true or args.prompt_show_icon
  args.prompt_icon_font = args.prompt_icon_font
  args.prompt_icon_color = args.prompt_icon_color or "#000000"
  args.prompt_icon = args.prompt_icon or ""
  args.prompt_icon_markup =
    args.prompt_icon_markup or
    string.format("<span size='xx-large' foreground='%s'>%s</span>", args.prompt_icon_color, args.prompt_icon)
  args.prompt_text = args.prompt_text or "<b>Search</b>: "
  args.prompt_start_text = args.prompt_start_text or ""
  args.prompt_font = args.prompt_font
  args.prompt_text_color = args.prompt_text_color or "#000000"

  local launcher_prompt =
    prompt {
    prompt = args.prompt_text,
    text = args.prompt_start_text,
    font = args.prompt_font,
    reset_on_stop = true,
    history_path = gears.filesystem.get_cache_dir() .. "/history",
    changed_callback = function(text)
      awesome.emit_signal("widgets::app_launcher::prompt_changed", text)
    end,
    keypressed_callback = function(mod, key, cmd)
      awesome.emit_signal("widgets::app_launcher::prompt_key_pressed", {mod = mod, key = key, cmd = cmd})
    end
  }

  tag_preview =
    tag_preview(
    {
      total_width = screen.geometry.width - config.dpi(400) - config.dpi(16) * 4,
      total_height = screen.geometry.height - config.dpi(16) * 2,
      spacing = config.dpi(16),
      padding = config.dpi(32)
    }
  )

  drawer:setup {
    layout = wibox.layout.stack,
    {
      widget = wibox.container.constraint,
      strategy = "exact",
      height = screen.geometry.height,
      width = screen.geometry.width,
      {
        layout = wibox.layout.manual,
        {
          widget = wibox.widget.imagebox,
          image = config.wallpaper,
          point = {
            x = config.dpi(-48),
            y = 0
          }
        }
      }
    },
    {
      layout = wibox.layout.fixed.horizontal,
      menu_column(
        screen,
        {
          layout = wibox.layout.align.vertical,
          spacing = config.dpi(16),
          {
            layout = wibox.layout.fixed.vertical,
            spacing = config.dpi(16),
            container(clock()),
            {
              widget = wibox.container.background,
              forced_height = args.prompt_height,
              shape = args.prompt_shape,
              bg = args.prompt_color,
              fg = args.prompt_text_color,
              border_width = args.prompt_border_width,
              border_color = args.prompt_border_color,
              {
                widget = wibox.container.margin,
                margins = args.prompt_paddings,
                {
                  widget = wibox.container.place,
                  halign = args.prompt_text_halign,
                  valign = args.prompt_text_valign,
                  {
                    layout = wibox.layout.fixed.horizontal,
                    spacing = args.prompt_icon_text_spacing,
                    {
                      widget = wibox.widget.textbox,
                      font = args.prompt_icon_font,
                      markup = args.prompt_icon_markup
                    },
                    launcher_prompt.textbox
                  }
                }
              }
            },
            launcher._private.widget
          },
          {
            widget = wibox.container.margin,
            top = config.dpi(16),
            bottom = config.dpi(16),
            container(notifications)
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
        },
        400
      ),
      {
        widget = wibox.container.constraint,
        height = screen.geometry.height,
        width = screen.geometry.width - config.dpi(400) - config.dpi(16) * 4,
        strategy = "exact",
        tag_preview.widget
      }
    }
  }

  awesome.connect_signal(
    "widget::drawer:toggle",
    function()
      local is_visible = backdrop.visible == true
      if is_visible then
        launcher_prompt:stop()
        launcher:hide()
      else
        tag_preview:show()
        launcher_prompt:start()
      end
      backdrop.visible = not backdrop.visible
      drawer.visible = not drawer.visible
      notifications.reset()
    end
  )

  awesome.connect_signal(
    "widget::drawer:hide",
    function()
      launcher_prompt:stop()
      launcher:hide()
      backdrop.visible = false
      drawer.visible = false
    end
  )

  awesome.connect_signal(
    "widgets::app_launcher::hide",
    function()
      launcher:hide()
      awesome.emit_signal("widget::drawer:hide")
    end
  )

  return toggle
end

function menu.mt:__call(...)
  return menu.new(...)
end

return setmetatable(menu, menu.mt)
