local theme_assets = require("beautiful.theme_assets")
local config = require("lib.configuration")

local gfs = require("gears.filesystem")
local themes_path = gfs.get_themes_dir()
local config_dir = gfs.get_configuration_dir()

local theme = {}

theme.font_name = "Inter"
theme.font_size = 10
theme.font_size_large = config.dpi(12)
theme.font = theme.font_name .. " Regular " .. theme.font_size

theme.enable_blur = true
theme.transparency = 0.6

theme.notification_color = "#2D87E2"

theme.bg_normal = "#111111"
theme.bg_primary = "#222222"
theme.bg_secondary = "#181818"
theme.bg_hover = "#333333"
theme.bg_press = "#3f3f3f"
theme.bg_focus = "#535d6c"
theme.bg_urgent = "#ff0000"
theme.bg_systray = theme.bg_secondary
theme.systray_icon_spacing = config.dpi(16)

theme.fg_normal = "#cccccc"
theme.fg_primary = "#ffffff"
theme.fg_inactive = "#888888"
theme.fg_press = "#ffffff"
theme.fg_error = "#dc2626"
theme.fg_focus = "#ffffff"
theme.fg_urgent = "#ffffff"

theme.rounded_rect_normal = config.dpi(6)
theme.rounded_rect_large = config.dpi(8)

theme.button_shape = "rounded"
theme.button_halign = "center"
theme.button_valign = "center"
theme.button_padding_left = config.dpi(20)
theme.button_padding_right = config.dpi(20)
theme.button_padding_top = config.dpi(10)
theme.button_padding_bottom = config.dpi(10)
theme.button_check_icon = config_dir .. "images/check.svg"

theme.bar_padding = config.dpi(3)
theme.bar_width = config.dpi(48)
theme.bar_clock_hour_font_size = 12
theme.bar_clock_hour_bold = true
theme.bar_clock_minute_font_size = 13
theme.bar_clock_minute_bold = false

theme.tasklist_icon_size = config.dpi(64)

theme.launcher_star_icon = config_dir .. "images/x.svg"
theme.launcher_icon_size = config.dpi(64)

theme.switcher_position = "max_left"
theme.switcher_width = config.dpi(300)
theme.switcher_margin_left = config.dpi(16)
theme.switcher_margin_right = config.dpi(16)
theme.switcher_margin_top = config.dpi(16)
theme.switcher_margin_bottom = config.dpi(16)

theme.menu_position = "bottom_left"
theme.menu_vertical_spacing = config.dpi(12)
theme.menu_horizontal_spacing = config.dpi(12)
theme.menu_margin_left = config.dpi(16)
theme.menu_margin_bottom = config.dpi(8)
theme.menu_container_padding_left = config.dpi(16)
theme.menu_container_padding_right = config.dpi(16)
theme.menu_container_padding_top = config.dpi(12)
theme.menu_container_padding_bottom = config.dpi(12)
theme.menu_height = config.dpi(600)
theme.menu_close_icon = config_dir .. "images/x.svg"

theme.calendar_position = "bottom_left"
theme.calendar_vertical_spacing = config.dpi(12)
theme.calendar_vertical_spacing = config.dpi(12)
theme.calendar_horizontal_spacing = config.dpi(12)
theme.calendar_horizontal_spacing = config.dpi(12)
theme.calendar_margin_left = config.dpi(16)
theme.calendar_margin_bottom = config.dpi(8)
theme.calendar_width = config.dpi(320)
theme.calendar_height = config.dpi(400)
theme.calendar_widget_width = config.dpi(320)

theme.notification_position = "bottom_right"
theme.notification_title_icon = config_dir .. "images/bell.svg"
theme.notification_title_dnd_icon = config_dir .. "images/bell-off.svg"
theme.notification_padding_top = config.dpi(8)
theme.notification_padding_bottom = config.dpi(8)
theme.notification_padding_left = config.dpi(16)
theme.notification_padding_right = config.dpi(16)
theme.notification_width = config.dpi(400)
theme.notification_max_height = config.dpi(400)
theme.notification_icon_size = config.dpi(24)
theme.notification_action_halign = "right"
theme.notification_close_icon = config_dir .. "images/x.svg"

theme.battery_icon = config_dir .. "images/battery.svg"
theme.battery_10_icon = config_dir .. "images/battery-10.svg"
theme.battery_25_icon = config_dir .. "images/battery-25.svg"
theme.battery_50_icon = config_dir .. "images/battery-50.svg"
theme.battery_75_icon = config_dir .. "images/battery-75.svg"
theme.battery_100_icon = config_dir .. "images/battery-100.svg"
theme.battery_charging_icon = config_dir .. "images/battery-charging.svg"

theme.volume_low_icon = config_dir .. "images/volume.svg"
theme.volume_medium_icon = config_dir .. "images/volume-1.svg"
theme.volume_high_icon = config_dir .. "images/volume-2.svg"
theme.volume_icon = config_dir .. "images/volume-2.svg"
theme.volume_mute_icon = config_dir .. "images/volume-x.svg"

theme.wifi_icon = config_dir .. "images/wifi.svg"
theme.wifi_100_icon = config_dir .. "images/wifi.svg"
theme.wifi_75_icon = config_dir .. "images/wifi-75.svg"
theme.wifi_50_icon = config_dir .. "images/wifi-50.svg"
theme.wifi_25_icon = config_dir .. "images/wifi-25.svg"
theme.wifi_0_icon = config_dir .. "images/wifi-0.svg"

theme.displays_icon = config_dir .. "images/monitor.svg"
theme.compositor_icon = config_dir .. "images/compositor.svg"
theme.download_icon = config_dir .. "images/download.svg"
theme.cpu_icon = config_dir .. "images/cpu.svg"
theme.ram_icon = config_dir .. "images/ram.svg"
theme.keyboard_icon = config_dir .. "images/keyboard.svg"

theme.useless_gap = config.dpi(0)
theme.border_width = config.dpi(0)
theme.border_color_normal = "#000000"
theme.border_color_active = "#535d6c"
theme.border_color_marked = "#91231c"

theme.shutdown_icon = config_dir .. "/images/power.svg"

theme.notification_font = theme.font
theme.notification_bg = ""
theme.notification_fg = "#ffffff"

theme.titlebar_size = config.dpi(36)
theme.titlebar_button_size = config.dpi(24)
theme.titlebar_buttons_spacing = config.dpi(2)
theme.titlebar_padding = config.dpi(4)
theme.titlebar_bg_normal = theme.bg_primary
theme.titlebar_bg_focus = theme.bg_normal
theme.titlebar_fg_normal = theme.fg_normal
theme.titlebar_fg_focus = theme.fg_focus
theme.titlebar_icon_unmaximize = config_dir .. "images/unmaximize.svg"
theme.titlebar_icon_maximize = config_dir .. "images/maximize.svg"
theme.titlebar_icon_minimize = config_dir .. "images/minimize.svg"
theme.titlebar_icon_x = config_dir .. "images/x.svg"

theme.titlebar_bg = theme.bg_normal

theme.wallpaper = config.wallpaper

theme.layout_floating = themes_path .. "default/layouts/floatingw.png"
theme.layout_max = themes_path .. "default/layouts/maxw.png"
theme.layout_tile = themes_path .. "default/layouts/tilew.png"

-- Generate Awesome icon:
theme.awesome_icon = theme_assets.awesome_icon(config.dpi(15), theme.bg_focus, theme.fg_focus)

-- Define the icon theme for application icons. If not set then the icons
-- from /usr/share/icons and /usr/share/icons/hicolor will be used.
theme.icon_theme = "Papirus"

theme.osd_height = config.dpi(300)
theme.osd_width = config.dpi(56)

return theme
