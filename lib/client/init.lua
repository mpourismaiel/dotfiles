local capi = {
  client = client,
  mouse = mouse,
  awesome = awesome
}
local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")
local client_menu = require("lib.widgets.client_menu")
local wbutton = require("lib.widgets.button")

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
    local font = theme.font_name .. " 9pt"
    local color = c.active and theme.titlebar_fg_focus or theme.titlebar_fg_normal
    local label = gears.string.xml_escape(c.name or "unknown")
    ret:set_markup("<span font='" .. font .. "' color='" .. color .. "'>" .. label .. "</span>")
  end
  ret.update = update
  update_on_signal(c, "property::name", ret)
  update_on_signal(c, "property::active", ret)
  update()

  return ret
end

client.connect_signal(
  "manage",
  function(c)
    if c.floating and not c.maximized and not c.fullscreen then
      awful.spawn("xprop -id " .. c.window .. " -f _COMPTON_SHADOW 32c -set _COMPTON_SHADOW 1")
    else
      awful.spawn("xprop -id " .. c.window .. " -f _COMPTON_SHADOW 32c -set _COMPTON_SHADOW 0")
    end
  end
)

client.connect_signal(
  "property::maximized",
  function(c)
    local wp = c._private
    if not wp or not wp.titlebar_widgets then
      return
    end
    wp.titlebar_widgets.maximize_widget.image =
      c.maximized and theme.titlebar_icon_unmaximize or theme.titlebar_icon_maximize
  end
)

client.connect_signal(
  "property::active",
  function(c, is_active)
    local wp = c._private
    if not wp or not wp.titlebar_widgets then
      return
    end

    wp.titlebar_widgets.minimize_button.bg_normal = is_active and theme.titlebar_bg_focus or theme.titlebar_bg_normal
    wp.titlebar_widgets.maximize_button.bg_normal = is_active and theme.titlebar_bg_focus or theme.titlebar_bg_normal
    wp.titlebar_widgets.close_button.bg_normal = is_active and theme.titlebar_bg_focus or theme.titlebar_bg_normal
  end
)

client.connect_signal(
  "request::titlebars",
  function(c)
    c.menu = client_menu()

    local minimize_widget =
      wibox.widget {
      widget = wibox.widget.imagebox,
      image = theme.titlebar_icon_minimize
    }
    local maximize_widget =
      wibox.widget {
      widget = wibox.widget.imagebox,
      image = theme.titlebar_icon_maximize
    }
    local close_widget =
      wibox.widget {
      widget = wibox.widget.imagebox,
      image = theme.titlebar_icon_x
    }

    local actions =
      wibox.widget {
      widget = wibox.container.place,
      halign = "right",
      {
        layout = wibox.layout.fixed.horizontal,
        spacing = theme.titlebar_buttons_spacing,
        {
          widget = wbutton,
          margin = theme.titlebar_padding,
          paddings = config.dpi(6),
          bg_normal = theme.bg_normal,
          bg_hover = "#ffbd44c0",
          id = "minimize_button",
          callback = function()
            c.ontop = not c.ontop
            c.floating = c.ontop
          end,
          minimize_widget
        },
        {
          widget = wbutton,
          margin = theme.titlebar_padding,
          paddings = config.dpi(6),
          bg_normal = theme.bg_normal,
          bg_hover = "#00ca4ec0",
          id = "maximize_button",
          callback = function()
            c.maximized = not c.maximized
            maximize_widget.image = c.maximized and theme.titlebar_icon_unmaximize or theme.titlebar_icon_maximize
          end,
          maximize_widget
        },
        {
          widget = wbutton,
          margin = theme.titlebar_padding,
          paddings = config.dpi(6),
          bg_normal = theme.bg_normal,
          bg_hover = "#ff605cc0",
          id = "close_button",
          callback = function()
            c:kill()
          end,
          close_widget
        }
      }
    }

    awful.titlebar(
      c,
      {
        position = "top",
        size = theme.titlebar_size
      }
    ):setup(
      {
        layout = wibox.layout.flex.horizontal,
        buttons = {
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
              c.menu:toggle {
                coords = mouse.coords(),
                client = c
              }
            end
          )
        },
        {
          widget = wibox.container.margin,
          left = config.dpi(16),
          {
            widget = wibox.container.place,
            halign = "left",
            valign = "center",
            {
              widget = client_title_widget(c)
            }
          }
        },
        nil,
        actions
      }
    )

    c._private.titlebar_widgets = {
      minimize_button = actions:get_children_by_id("minimize_button")[1],
      maximize_button = actions:get_children_by_id("maximize_button")[1],
      close_button = actions:get_children_by_id("close_button")[1],
      maximize_widget = maximize_widget
    }
  end
)
