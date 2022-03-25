local capi = {
  client = client
}
local awful = require("awful")
local wibox = require("wibox")
local config = require("configuration.config")
local filesystem = require("gears.filesystem")

local config_dir = filesystem.get_configuration_dir()

local instances = {}
local function update_on_signal(c, signal, widget)
  local sig_instances = instances[signal]
  if sig_instances == nil then
    sig_instances = setmetatable({}, {__mode = "k"})
    instances[signal] = sig_instances
    capi.client.connect_signal(
      signal,
      function(cl)
        local widgets = sig_instances[cl]
        if widgets then
          for _, w in pairs(widgets) do
            w.update()
          end
        end
      end
    )
  end
  local widgets = sig_instances[c]
  if widgets == nil then
    widgets = setmetatable({}, {__mode = "v"})
    sig_instances[c] = widgets
  end
  table.insert(widgets, widget)
end

local function client_title_widget(c)
  local ret = wibox.widget.textbox()

  local function update()
    ret:set_markup("<span font_size='9pt' color='#ffffffaa'>" .. (c.name or "unknown") .. "</span>")
  end
  ret.update = update
  update_on_signal(c, "property::name", ret)
  update()

  return ret
end

local titlebar_button = function(w, hover_color, onclick)
  local widget =
    wibox.widget {
    widget = wibox.container.background,
    bg = "",
    {
      widget = wibox.container.margin,
      margins = config.dpi(8),
      buttons = {
        awful.button({}, 1, onclick)
      },
      w
    }
  }

  widget:connect_signal(
    "mouse::enter",
    function()
      widget.bg = hover_color
    end
  )
  widget:connect_signal(
    "mouse::leave",
    function()
      widget.bg = ""
    end
  )

  return widget
end

client.connect_signal(
  "request::titlebars",
  function(c)
    local buttons = {
      awful.button(
        {},
        1,
        function()
          c:activate {context = "titlebar", action = "mouse_move"}
        end
      ),
      awful.button(
        {},
        3,
        function()
          c:activate {context = "titlebar", action = "mouse_resize"}
        end
      )
    }

    local maximize_widget =
      wibox.widget {
      widget = wibox.widget.imagebox,
      image = c.maximized and config_dir .. "images/unmaximize.svg" or config_dir .. "images/maximize.svg"
    }
    local minimize_widget =
      wibox.widget {
      widget = wibox.widget.imagebox,
      image = config_dir .. "images/minimize.svg"
    }
    local close_widget =
      wibox.widget {
      widget = wibox.widget.imagebox,
      image = config_dir .. "images/x.svg"
    }

    awful.titlebar(
      c,
      {
        position = "top",
        size = config.dpi(36),
        bg = "#111111c0"
      }
    ):setup {
      layout = wibox.layout.flex.horizontal,
      buttons = buttons,
      {
        widget = wibox.container.margin,
        left = config.dpi(16),
        {
          widget = client_title_widget(c)
        }
      },
      nil,
      {
        widget = wibox.container.place,
        halign = "right",
        {
          layout = wibox.layout.fixed.horizontal,
          titlebar_button(
            minimize_widget,
            "#ffbd44c0",
            function()
              c.minimized = not c.minimized
            end
          ),
          titlebar_button(
            maximize_widget,
            "#00ca4ec0",
            function()
              c.maximized = not c.maximized
              maximize_widget.image =
                c.maximized and config_dir .. "images/unmaximize.svg" or config_dir .. "images/maximize.svg"
            end
          ),
          titlebar_button(
            close_widget,
            "#ff605cc0",
            function()
              c:kill()
            end
          )
        }
      }
    }
  end
)
