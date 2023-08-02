local theme_assets = require("beautiful.theme_assets")
local config = require("configuration.config")

local gfs = require("gears.filesystem")
local themes_path = gfs.get_themes_dir()
local config_dir = gfs.get_configuration_dir()

local theme = {}

theme.font_name = "Inter"
theme.font_size = config.dpi(10)
theme.font = theme.font_name .. " Regular " .. theme.font_size

theme.transparency = 0.6

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

theme.bar_padding = config.dpi(3)
theme.bar_width = config.dpi(48)

theme.launcher_star_icon = config_dir .. "images/x.svg"

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

theme.notification_position = "bottom_right"
theme.notification_padding_top = config.dpi(8)
theme.notification_padding_bottom = config.dpi(8)
theme.notification_padding_left = config.dpi(16)
theme.notification_padding_right = config.dpi(16)
theme.notification_width = config.dpi(400)
theme.notification_max_height = config.dpi(400)
theme.notification_icon_size = config.dpi(24)
theme.notification_action_halign = "right"
theme.notification_close_icon = config_dir .. "images/x.svg"

theme.useless_gap = config.dpi(0)
theme.border_width = config.dpi(0)
theme.border_color_normal = "#000000"
theme.border_color_active = "#535d6c"
theme.border_color_marked = "#91231c"

theme.shutdown_icon = config_dir .. "/images/power.svg"

-- There are other variable sets
-- overriding the default one when
-- defined, the sets are:
-- taglist_[bg|fg]_[focus|urgent|occupied|empty|volatile]
-- tasklist_[bg|fg]_[focus|urgent]
-- titlebar_[bg|fg]_[normal|focus]
-- tooltip_[font|opacity|fg_color|bg_color|border_width|border_color]
-- prompt_[fg|bg|fg_cursor|bg_cursor|font]
-- hotkeys_[bg|fg|border_width|border_color|shape|opacity|modifiers_fg|label_bg|label_fg|group_margin|font|description_font]
-- Example:
--theme.taglist_bg_focus = "#ff0000"

-- Generate taglist squares:
local taglist_square_size = config.dpi(4)
theme.taglist_squares_sel = theme_assets.taglist_squares_sel(taglist_square_size, theme.fg_normal)
theme.taglist_squares_unsel = theme_assets.taglist_squares_unsel(taglist_square_size, theme.fg_normal)

-- Variables set for theming notifications:
-- notification_font
-- notification_[bg|fg]
-- notification_[width|height|margin]
-- notification_[border_color|border_width|shape|opacity]
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

theme.wallpaper = config.wallpaper

-- You can use your own layout icons like this:
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
