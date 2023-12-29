local capi = {
  awesome = awesome
}
local wibox = require("wibox")
local gears = require("gears")
local awful = require("awful")
local config = require("lib.configuration")
local theme = require("lib.configuration.theme")
local network_daemon = require("lib.daemons.hardware.network")
local animation_new = require("lib.helpers.animation-new")
local colors = require("lib.helpers.color")
local wbutton = require("lib.widgets.button")
local wtext = require("lib.widgets.text")
local wtext_input = require("lib.widgets.text_input")
local wscrollbar = require("lib.widgets.scrollbar")
local wcontainer = require("lib.widgets.menu.container")
local woverflow = require("wibox.layout.overflow")
local console = require("lib.helpers.console")

local network = {mt = {}}

local strength_icon = function(strength)
  if strength > 75 then
    return theme.wifi_100_icon
  elseif strength > 50 then
    return theme.wifi_75_icon
  elseif strength > 25 then
    return theme.wifi_50_icon
  elseif strength > 10 then
    return theme.wifi_25_icon
  else
    return theme.wifi_0_icon
  end
end

local function create_animation(background, name)
  return animation_new(
    {
      subject = {
        bg = colors.hex2rgba(theme.bg_secondary),
        fg = colors.hex2rgba(theme.fg_normal)
      },
      duration = 0.2
    }
  ):add(
    "normal",
    {
      target = {
        bg = colors.hex2rgba(theme.bg_secondary),
        fg = colors.hex2rgba(theme.fg_normal)
      }
    }
  ):add(
    "hover",
    {
      target = {
        bg = colors.hex2rgba(theme.bg_hover),
        fg = colors.hex2rgba(theme.fg_primary)
      }
    }
  ):onUpdate(
    function(_, subject)
      background.bg = colors.rgba2hex(subject.bg)
      name.foreground = colors.rgba2hex(subject.fg)
    end
  ):startAnimation("normal")
end

local function access_point_widget(layout, access_point)
  local widget, wp
  local closed_height = config.dpi(48)
  local opened_height = config.dpi(200)

  local name =
    wibox.widget {
    widget = wtext,
    text = access_point.ssid,
    foreground = theme.fg_normal,
    bold = true
  }

  local password_input =
    wibox.widget {
    widget = wtext_input,
    unfocus_on_client_clicked = true,
    initial = access_point.password,
    obscure = true,
    selection_bg = theme.bg_secondary,
    widget_template = wibox.widget {
      widget = wibox.container.background,
      shape = function(cr, w, h)
        gears.shape.rounded_rect(cr, w, h, theme.rounded_rect_large)
      end,
      bg = theme.bg_normal,
      {
        widget = wibox.container.margin,
        left = config.dpi(16),
        right = config.dpi(16),
        top = config.dpi(8),
        bottom = config.dpi(8),
        {
          layout = wibox.layout.stack,
          {
            widget = wibox.widget.textbox,
            id = "placeholder_role",
            text = "Password..."
          },
          {
            widget = wibox.widget.textbox,
            id = "text_role"
          }
        }
      }
    }
  }

  local connect_or_disconnect_label =
    wibox.widget {
    widget = wtext,
    text = access_point:is_active() and "Disconnect" or "Connect"
  }

  local connect_or_disconnect =
    wibox.widget {
    widget = wbutton,
    callback = function()
      access_point:toggle(password_input:get_text(), true) -- auto_connect_checkbox:get_state()
      wp.is_open = false
      widget.height = closed_height
      widget.contents_role:reset()
    end,
    padding_left = config.dpi(16),
    padding_right = config.dpi(16),
    padding_top = config.dpi(8),
    padding_bottom = config.dpi(8),
    connect_or_disconnect_label
  }

  network_daemon:dynamic_connect_signal(
    access_point.hw_address .. "::state",
    function(self, new_state, old_state)
      connect_or_disconnect_label:set_text("Connect")
      if new_state ~= network_daemon.DeviceState.ACTIVATED then
        connect_or_disconnect_label:set_text("Disconnect")
      end

      if new_state == network_daemon.DeviceState.PREPARE then
        -- show loading
      elseif new_state == network_daemon.DeviceState.ACTIVATED then
        layout:remove_widgets(widget)
        layout:insert(1, widget)
        connect_or_disconnect_label:set_text("Disconnect")
      end
    end
  )

  network_daemon:dynamic_connect_signal(
    "access_point::connected",
    function(self, ssid, strength)
      -- hide loading
    end
  )

  widget =
    wibox.widget {
    widget = wibox.container.constraint,
    strategy = "exact",
    height = closed_height,
    {
      widget = wibox.container.background,
      shape = function(cr, w, h)
        return gears.shape.rounded_rect(cr, w, h, theme.rounded_rect_normal)
      end,
      id = "background",
      {
        widget = wibox.container.margin,
        margins = config.dpi(16),
        {
          layout = wibox.layout.fixed.vertical,
          spacing = config.dpi(16),
          {
            layout = wibox.layout.fixed.horizontal,
            spacing = config.dpi(16),
            {
              widget = wibox.container.constraint,
              strategy = "exact",
              width = config.dpi(16),
              height = config.dpi(16),
              {
                widget = wibox.container.place,
                {
                  widget = wibox.widget.imagebox,
                  image = strength_icon(access_point.strength)
                }
              }
            },
            name
          },
          {
            layout = wibox.layout.fixed.vertical,
            spacing = config.dpi(16),
            id = "contents"
          }
        }
      }
    }
  }

  wp = widget._private
  widget.background_role = widget:get_children_by_id("background")[1]
  widget.contents_role = widget:get_children_by_id("contents")[1]
  wp.is_open = false
  wp.animation = create_animation(widget.background_role, name)

  widget:connect_signal(
    "mouse::enter",
    function()
      if wp.is_open then
        return
      end

      wp.animation:stopAnimation("normal"):startAnimation("hover")
    end
  )

  widget:connect_signal(
    "mouse::leave",
    function()
      if wp.is_open then
        return
      end

      wp.animation:stopAnimation("hover"):startAnimation("normal")
    end
  )

  widget:connect_signal(
    "button::press",
    function(self, _, _, button)
      if button == 1 and not wp.is_open then
        wp.is_open = true

        wp.animation:stopAnimation("hover"):startAnimation("normal")
        widget.height = opened_height
        widget.contents_role:reset()
        widget.contents_role:add(password_input)
        widget.contents_role:add(connect_or_disconnect)
      end
    end
  )

  widget.password_input = password_input
  return widget
end

local function new(args)
  args = args or {}
  args.width = args.width or config.dpi(400)
  args.height = args.height or config.dpi(400)

  local ret = gears.object({})
  ret._private = {}
  gears.table.crush(ret, network)

  local wp = ret._private
  wp.callback = args.callback or nil
  wp.width = args.width
  wp.height = args.width

  local rescan =
    wibox.widget {
    widget = wbutton,
    strategy = "exact",
    width = config.dpi(24),
    height = config.dpi(24),
    halign = "left",
    bg_normal = theme.bg_secondary,
    rounded = theme.rounded_rect_normal,
    callback = function()
      network_daemon:scan_access_points()
    end,
    {
      widget = wibox.container.constraint,
      strategy = "exact",
      width = config.dpi(16),
      height = config.dpi(16),
      {
        widget = wibox.container.place,
        {
          widget = wibox.widget.imagebox,
          image = theme.wifi_icon
        }
      }
    }
  }

  local show_menu = function()
    if not wp.callback then
      return
    end

    network_daemon:scan_access_points()

    wp.callback(
      wibox.widget {
        layout = wibox.layout.fixed.horizontal,
        spacing = theme.menu_horizontal_spacing,
        rescan,
        {
          widget = wtext,
          bold = true,
          text = "Wi-Fi Networks",
          font_size = 12
        }
      },
      wp.menu,
      ret
    )
  end

  local toggle =
    wibox.widget {
    widget = wbutton,
    strategy = "exact",
    width = config.dpi(args.width),
    height = config.dpi(60),
    halign = "left",
    bg_normal = theme.bg_secondary,
    rounded = theme.rounded_rect_large,
    callback = show_menu,
    paddings = config.dpi(16),
    {
      layout = wibox.layout.fixed.horizontal,
      spacing = config.dpi(8),
      {
        widget = wibox.container.constraint,
        strategy = "exact",
        width = config.dpi(24),
        height = config.dpi(24),
        {
          widget = wibox.container.place,
          {
            widget = wibox.widget.imagebox,
            image = theme.wifi_icon
          }
        }
      },
      {
        widget = wtext,
        text = "N/A",
        halign = "left",
        valign = "center",
        id = "wifi_name"
      }
    }
  }

  local menu =
    wibox.widget {
    widget = wibox.container.constraint,
    strategy = "exact",
    width = args.width,
    height = args.height,
    {
      widget = wcontainer,
      {
        layout = woverflow.vertical,
        spacing = config.dpi(12),
        scrollbar_widget = wscrollbar,
        scrollbar_width = config.dpi(10),
        step = 200,
        id = "wifi_list",
        {
          widget = wtext,
          text = "Wifi networks will be listed here"
        }
      }
    }
  }

  wp.wifi_name = toggle:get_children_by_id("wifi_name")[1]
  wp.wifi_list = menu:get_children_by_id("wifi_list")[1]

  local hw_addresses = {}
  local render_access_points = function(access_points)
    wp.wifi_list:reset()

    for _, hw_address in pairs(hw_addresses) do
      network_daemon:dynamic_disconnect_signals(hw_address .. "::state")
    end
    hw_addresses = {}
    network_daemon:dynamic_disconnect_signals("access_point::connected")

    for _, access_point in pairs(access_points) do
      table.insert(hw_addresses, access_point.hw_address)

      if access_point:is_active() then
        wp.wifi_list:insert(1, access_point_widget(wp.wifi_list, access_point))
      else
        wp.wifi_list:add(access_point_widget(wp.wifi_list, access_point))
      end
    end
  end

  network_daemon:connect_signal(
    "wireless_state",
    function(self, state)
      if not state then
        wp.wifi_name:set_text("N/A")
      end
    end
  )

  network_daemon:connect_signal(
    "access_point::connected",
    function(self, ssid, strength)
      wp.wifi_name:set_text(ssid)
    end
  )

  network_daemon:connect_signal(
    "scan_access_points::success",
    function()
      render_access_points(network_daemon:get_access_points())
    end
  )
  render_access_points(network_daemon:get_access_points())

  ret:connect_signal(
    "menu::property::width",
    function(_, height)
      menu.height = height
    end
  )

  ret:connect_signal(
    "menu::property::height",
    function(_, height)
      menu.height = height
    end
  )

  wp.menu = menu

  ret.toggle = toggle
  ret.hide_callback = function()
    for _, w in pairs(wp.wifi_list.children) do
      w.password_input:unfocus()
    end
  end

  return ret
end

function network.mt:__call(...)
  return new(...)
end

return setmetatable(network, network.mt)
