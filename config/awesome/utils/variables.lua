local awful = require("awful")
local wibox = require("wibox")
local naughty = require("naughty")
local gears = require("gears")
local os = os
local background = wibox.container.background

local default_dir = require("awful.util").get_themes_dir() .. "default"
local icon_dir = os.getenv("HOME") .. "/.config/awesome/themes/damn/icons"
local clean_icons = os.getenv("HOME") .. "/.config/awesome/themes/icons"
awful.util.icons = {
  default_dir = default_dir,
  icon_dir = icon_dir,
  clean_icons = clean_icons
}

awful.util.wallpaper = {
  desktop = os.getenv("HOME") .. "/Pictures/Wallpapers/shooting-star-wallpaper.png",
  lockscreen = os.getenv("HOME") .. "/Pictures/Wallpapers/shooting-star-wallpaper.png"
}

awful.util.theme = {
  default_dir = default_dir,
  icon_dir = icon_dir,
  wallpaper = awful.util.wallpaper.desktop,
  font_base = "FiraCode",
  font_only = "FiraCode Bold",
  font = "FiraCode Bold 10",
  hotkeys_font = "FiraCode 10",
  font_icon = "fontello",
  useless_gap = 0,
  primary = "#FC4384",
  white = "#ffffff",
  sidebar_bg = gears.color(
    {
      type = "linear",
      from = {0, 20},
      to = {0, 70},
      stops = {{0, "#1a1a1a"}, {1, "#050505"}}
    }
  ),
  -- colors
  separator = "#292929",
  bg_systray = "#171520",
  fg_normal = "#ffffff99",
  fg_normal_secondary = "#ffffff66",
  fg_focus = "#86848a",
  bg_focus = "#151515",
  bg_normal = "#151515",
  fg_urgent = "#CC9393",
  bg_urgent = "#151515",
  bg_panel = "#1a1a1a",
  -- systray
  systray_icon_spacing = 15,
  -- border styles
  border_width = 3,
  border_normal = "#292929",
  border_focus = "#FC4384",
  hotkeys_border_width = 3,
  hotkeys_border_color = "#252525",
  -- tag list styles
  taglist_fg_focus = "#86848a",
  taglist_bg_occupied = "#f5f5f500",
  taglist_bg_focus = "#FC4384",
  taglist_border = "#ffffff33",
  taglist_bg_urgent = "#f5f5f500",
  taglist_fg_urgent = "#ffffff33",
  taglist_font = "Font Awesome 5 Free Solid 12",
  taglist_disable_icon = false,
  -- wibar styles
  widget_bg = "#241b2f",
  wibar_bg = "#171520",
  -- menu styles
  menu_height = 20,
  menu_width = 160,
  menu_icon_size = 32,
  -- notification styles
  notification_border_color = "#FC4384",
  notification_border_width = 2,
  notification_width = 300,
  notification_margin = 16,
  notification_fg = "#ffffff",
  notification_font = "FiraCode Bold 10",
  notification_message_font = "FiraCode 10",
  -- layout box styles
  layout_tile = clean_icons .. "/tiled.svg",
  layout_max = clean_icons .. "/maximized.svg",
  layout_floating = clean_icons .. "/float.svg",
  -- task list styles
  tasklist_bg_normal = "#1f1f1f",
  tasklist_bg_focus = "#1f1f1f",
  tasklist_bg_urgent = "#1f1f1f",
  tasklist_fg_focus = "#86848a",
  tasklist_plain_task_name = true,
  tasklist_disable_icon = false,
  -- title bar styles
  titlebar_bg = "#171520",
  titlebar_fg = "#86848a",
  titlebar_fg_focus = "#86848a",
  titlebar_height = 32,
  titlebar_close_button_normal = default_dir .. "/titlebar/close_normal.png",
  titlebar_close_button_focus = default_dir .. "/titlebar/close_focus.png",
  titlebar_minimize_button_normal = default_dir .. "/titlebar/minimize_normal.png",
  titlebar_minimize_button_focus = default_dir .. "/titlebar/minimize_focus.png",
  titlebar_sticky_button_normal_inactive = default_dir .. "/titlebar/sticky_normal_inactive.png",
  titlebar_sticky_button_focus_inactive = default_dir .. "/titlebar/sticky_focus_inactive.png",
  titlebar_sticky_button_normal_active = default_dir .. "/titlebar/sticky_normal_active.png",
  titlebar_sticky_button_focus_active = default_dir .. "/titlebar/sticky_focus_active.png",
  titlebar_floating_button_normal_inactive = default_dir .. "/titlebar/floating_normal_inactive.png",
  titlebar_floating_button_focus_inactive = default_dir .. "/titlebar/floating_focus_inactive.png",
  titlebar_floating_button_normal_active = default_dir .. "/titlebar/floating_normal_active.png",
  titlebar_floating_button_focus_active = default_dir .. "/titlebar/floating_focus_active.png",
  titlebar_maximized_button_normal_inactive = default_dir .. "/titlebar/maximized_normal_inactive.png",
  titlebar_maximized_button_focus_inactive = default_dir .. "/titlebar/maximized_focus_inactive.png",
  titlebar_maximized_button_normal_active = default_dir .. "/titlebar/maximized_normal_active.png",
  titlebar_maximized_button_focus_active = default_dir .. "/titlebar/maximized_focus_active.png"
}

awful.util.modkey = "Mod4"
awful.util.altkey = "Mod1"
awful.util.terminal = "alacritty"

naughty.config.padding = 20
naughty.config.defaults.icon_size = 36
naughty.config.defaults.margin = 10
naughty.config.defaults.position = "bottom_right"

awful.util.tagnames = {
  "Browser",
  "Code",
  "Terminal",
  "Files",
  "Messaging",
  "Games"
}

awful.util.variables = {
  _previous_tag = nil,
  terminal_tag_terminals = {"Terminator", "XTerm", "kitty", "Alacritty", "Hyper"}
}
awful.util.variables.terminal_tag_allowlist = gears.table.clone(awful.util.variables.terminal_tag_terminals)
awful.util.variables.terminal_tag_allowlist[#awful.util.variables.terminal_tag_allowlist + 1] = "albert"

awful.util.tasklist_buttons = require("utils.tasklist.buttons")
local terminal_tasklist = require("widgets.damn.terminal.tasklist")
awful.util.terminal_tasklist = terminal_tasklist.wibar
awful.util.terminal_tasklist:setup(terminal_tasklist.widgets)

tag.connect_signal("request::default_layouts", function()
  awful.layout.append_default_layouts({
    awful.layout.suit.tile,
    awful.layout.suit.floating,
    awful.layout.suit.max
  })
end)

awful.util.tags = {
  {
    icon = clean_icons .. "/browser.png",
    text = awful.util.tagnames[1],
    layout = awful.layout.suit.max
  },
  {
    icon = clean_icons .. "/code.png",
    text = awful.util.tagnames[2],
    layout = awful.layout.suit.max
  },
  {
    icon = clean_icons .. "/terminal.png",
    text = awful.util.tagnames[3],
    layout = awful.layout.suit.tile,
    rules = awful.util.variables.terminal_tag_allowlist,
    wibar = awful.util.terminal_tasklist
  },
  {
    icon = clean_icons .. "/files.png",
    text = awful.util.tagnames[4],
    layout = awful.layout.suit.max
  },
  {
    icon = clean_icons .. "/messaging.png",
    text = awful.util.tagnames[5],
    layout = awful.layout.suit.max
  },
  {
    icon = clean_icons .. "/games.png",
    text = awful.util.tagnames[6]
  }
}

awful.util.theme_functions = {}
