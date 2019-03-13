--[[

     Holo Awesome WM theme 3.0
     github.com/lcpz

--]] local gears = require("gears")
local lain = require("lain")
local awful = require("awful")
local naughty = require("naughty")
local wibox = require("wibox")
local layout_indicator = require("keyboard-layout-indicator")
-- local brightness = require("brightness")
local string, os = string, os
local my_table = awful.util.table or gears.table -- 4.{0,1} compatibility

local theme = {}
theme.default_dir = require("awful.util").get_themes_dir() .. "default"
theme.icon_dir = os.getenv("HOME") .. "/.config/awesome/themes/holo/icons"
theme.wallpaper = os.getenv("HOME") .. "/.config/awesome/themes/holo/wall.png"
theme.font = "Roboto Bold 10"
theme.exit_screen_font = "Roboto Bold 14"
theme.exit_screen_goodbye_font = "Roboto Bold 50"
theme.info_screen_font = theme.exit_screen_goodbye_font
theme.info_screen_widget_font = "Roboto Bold 30"
theme.taglist_font = "Font Awesome 5 Free 8"
theme.notification_border_color = "#0099CC"
theme.notification_border_width = 2
theme.systray_icon_spacing = 5
theme.bg_systray = "#303030"
theme.wibar_bg = "#242424"
theme.fg_normal = "#FFFFFF"
theme.fg_focus = "#0099CC"
theme.bg_focus = "#303030"
theme.bg_normal = "#242424"
theme.fg_urgent = "#CC9393"
theme.bg_urgent = "#006B8E"
theme.border_width = 3
theme.border_normal = "#252525"
theme.border_focus = "#fc4384"
theme.taglist_fg_focus = "#FC4384"
theme.taglist_bg_urgent = "#FC4384"
theme.taglist_bfg_urgent = "#FFFFFF"
theme.tasklist_bg_normal = "#222222"
theme.tasklist_fg_focus = "#FC4384"
theme.menu_height = 20
theme.menu_width = 160
theme.menu_icon_size = 32
theme.notification_width = 300
theme.notification_margin = 16
theme.awesome_icon = theme.icon_dir .. "/awesome_icon_white.png"
theme.awesome_icon_launcher = theme.icon_dir .. "/awesome_icon.png"
theme.spr_small = theme.icon_dir .. "/spr_small.png"
theme.spr_very_small = theme.icon_dir .. "/spr_very_small.png"
theme.spr_right = theme.icon_dir .. "/spr_right.png"
theme.spr_bottom_right = theme.icon_dir .. "/spr_bottom_right.png"
theme.spr_left = theme.icon_dir .. "/spr_left.png"
theme.bar = theme.icon_dir .. "/bar.png"
theme.bottom_bar = theme.icon_dir .. "/bottom_bar.png"
theme.calendar = theme.icon_dir .. "/cal.png"
theme.cpu = theme.icon_dir .. "/cpu.png"
theme.net_up = theme.icon_dir .. "/net_up.png"
theme.net_down = theme.icon_dir .. "/net_down.png"
theme.layout_tile = theme.icon_dir .. "/tile.png"
theme.layout_tileleft = theme.icon_dir .. "/tileleft.png"
theme.layout_tilebottom = theme.icon_dir .. "/tilebottom.png"
theme.layout_tiletop = theme.icon_dir .. "/tiletop.png"
theme.layout_fairv = theme.icon_dir .. "/fairv.png"
theme.layout_fairh = theme.icon_dir .. "/fairh.png"
theme.layout_spiral = theme.icon_dir .. "/spiral.png"
theme.layout_dwindle = theme.icon_dir .. "/dwindle.png"
theme.layout_max = theme.icon_dir .. "/max.png"
theme.layout_fullscreen = theme.icon_dir .. "/fullscreen.png"
theme.layout_centerwork = theme.icon_dir .. "/magnifier.png"
theme.layout_floating = theme.icon_dir .. "/floating.png"
theme.tasklist_plain_task_name = true
theme.tasklist_disable_icon = true
theme.useless_gap = 0
theme.titlebar_bg = theme.wibar_bg or "#202124"
theme.titlebar_fg = "#ffffff"
theme.titlebar_fg_focus = "#fc4384"
theme.titlebar_height = 32
theme.titlebar_close_button_normal = theme.default_dir .. "/titlebar/close_normal.png"
theme.titlebar_close_button_focus = theme.default_dir .. "/titlebar/close_focus.png"
theme.titlebar_minimize_button_normal = theme.default_dir .. "/titlebar/minimize_normal.png"
theme.titlebar_minimize_button_focus = theme.default_dir .. "/titlebar/minimize_focus.png"
theme.titlebar_sticky_button_normal_inactive = theme.default_dir .. "/titlebar/sticky_normal_inactive.png"
theme.titlebar_sticky_button_focus_inactive = theme.default_dir .. "/titlebar/sticky_focus_inactive.png"
theme.titlebar_sticky_button_normal_active = theme.default_dir .. "/titlebar/sticky_normal_active.png"
theme.titlebar_sticky_button_focus_active = theme.default_dir .. "/titlebar/sticky_focus_active.png"
theme.titlebar_floating_button_normal_inactive = theme.default_dir .. "/titlebar/floating_normal_inactive.png"
theme.titlebar_floating_button_focus_inactive = theme.default_dir .. "/titlebar/floating_focus_inactive.png"
theme.titlebar_floating_button_normal_active = theme.default_dir .. "/titlebar/floating_normal_active.png"
theme.titlebar_floating_button_focus_active = theme.default_dir .. "/titlebar/floating_focus_active.png"
theme.titlebar_maximized_button_normal_inactive = theme.default_dir .. "/titlebar/maximized_normal_inactive.png"
theme.titlebar_maximized_button_focus_inactive = theme.default_dir .. "/titlebar/maximized_focus_inactive.png"
theme.titlebar_maximized_button_normal_active = theme.default_dir .. "/titlebar/maximized_normal_active.png"
theme.titlebar_maximized_button_focus_active = theme.default_dir .. "/titlebar/maximized_focus_active.png"
theme.widget_container = function(
    widget,
    margin_left,
    margin_right,
    margin_top,
    margin_bottom,
    background_color,
    remove_background,
    shape,
    padding_left,
    padding_right,
    padding_top,
    padding_bottom)
    widget =
        wibox.container.margin(widget, padding_left or 0, padding_right or 0, padding_top or 0, padding_bottom or 0)

    if remove_background ~= true then
        widget = wibox.container.background(widget, background_color or theme.bg_focus, shape or gears.shape.rectangle)
    end

    return wibox.container.margin(widget, margin_left or 0, margin_right or 0, margin_top or 5, margin_bottom or 5)
end
theme.musicplr = string.format("%s -e 'ncmpc -p 6600 -h 127.0.0.1'", awful.util.terminal)
theme.lock_cmd =
    string.format("sh %s/.config/i3/i3lock %s/Pictures/Lockscreen/wallpaper.jpg", os.getenv("HOME"), os.getenv("HOME"))
theme.font_awesome = "Font Awesome 5 Free"

local markup = lain.util.markup
local blue = "#80CCE6"
local space3 = markup.font("Roboto 3", " ")

-- fs
local fs_free =
    lain.widget.fs(
    {
        settings = function()
            widget:set_markup(
                markup(
                    "#FFFFFF",
                    markup.font("Roboto 5", " ") ..
                        markup.font(theme.font_awesome .. " solid 10", "") ..
                            markup.font(theme.font, "  " .. fs_now["/home"].percentage .. "%")
                )
            )
        end
    }
)

local fs_bg = wibox.container.background(fs_free.widget, theme.bg_focus, gears.shape.rectangle)
local fs_widget = wibox.container.margin(fs_bg, 0, 0, 5, 5)

-- Ping
local ping =
    awful.widget.watch(
    string.format("sh %s/bin/show-ping.sh", os.getenv("HOME")),
    1,
    function(widget, stdout)
        widget:set_markup(
            markup(
                "#FFFFFF",
                markup.font("Roboto 5", " ") ..
                    markup.font(string.format("%s 10", theme.font_awesome), "") ..
                        markup.font(theme.font, "  " .. stdout) .. markup.font("Roboto 5", " ")
            )
        )
    end
)
local ping_bg = wibox.container.background(ping, theme.bg_focus, gears.shape.rectangle)
local ping_widget = wibox.container.margin(ping_bg, 0, 0, 5, 5)

local github =
    awful.widget.watch(
    string.format("sh %s/.config/polybar/scripts/inbox-github.sh", os.getenv("HOME")),
    60,
    function(widget, stdout)
        widget:set_markup(
            markup(
                "#FFFFFF",
                markup.font("Roboto 10", "  ") ..
                    markup.font(string.format("%s 10", theme.font_awesome), "") ..
                        markup.font("Roboto 10", string.format("  %s  ", stdout))
            )
        )
    end
)
local github_bg = wibox.container.background(github, theme.bg_focus, gears.shape.rectangle)
local github_widget = wibox.container.margin(github_bg, 0, 0, 5, 5)
function visit_github_notifications()
    awful.spawn.with_shell("google-chrome-beta https://github.com/notifications")
end

github_widget:connect_signal("button::press", visit_github_notifications)

local github_ask
--

--[[
github_widget:connect_signal(
    "mouse::enter",
    function()
        awful.spawn.easy_async(string.format(
            "sh %s/.config/polybar/scripts/inbox-github.sh",
            os.getenv("HOME")
        ), function(stdout)
            local notification_count = stdout == "" and "no" or stdout:gsub("%s+", "")
            github_ask_setup(notification_count)
            local timer = gears.timer {
                timeout   = 5,
                autostart = true,
                callback  = function()
                    github_ask.visible = false
                    timer:stop()
                end
            }
        end)
    end
)
]] function github_ask_setup(
    notification_count)
    if github_ask then
        github_ask.visible = false
    end

    local s = awful.screen.focused()
    github_ask =
        wibox(
        {
            screen = s,
            x = s.geometry.x + s.geometry.width - 316,
            y = s.geometry.y + 48,
            visible = true,
            ontop = true,
            type = "notification",
            bg = theme.wibar_bg,
            border_width = 2,
            border_color = theme.border_focus,
            height = 80,
            width = 300
        }
    )

    local github_text = wibox.widget.textbox()
    github_text:set_markup(
        markup(
            "#FFFFFF",
            markup.font(
                "Roboto 12",
                "You have " .. markup.font("Roboto Bold 12", notification_count) .. " notifications"
            )
        )
    )

    function create_button(text, action)
        local txt = wibox.widget.textbox()
        txt:set_markup(markup("#FFFFFF", markup.font("Roboto 12", text)))
        local bg = wibox.container.margin(txt, 10, 10, 5, 5)
        local btn = wibox.container.background(bg, theme.bg_focus, gears.shape.rectangle)
        btn:buttons(my_table.join(awful.button({}, 1, action)))

        return btn
    end

    local visit_website_button = create_button("Visit Github", visit_github_notifications)
    local clear_notifications_buttons = create_button("Mark as seen")
    local pad0 = wibox.widget.textbox(markup.font(theme.font, "  "))
    github_ask:setup {
        {
            pad0,
            github_text,
            pad0,
            layout = wibox.layout.align.horizontal
        },
        {
            pad0,
            {
                visit_website_button,
                pad0,
                clear_notifications_buttons,
                layout = wibox.layout.align.horizontal
            },
            pad0,
            layout = wibox.layout.align.horizontal
        },
        expand = "none",
        layout = wibox.layout.flex.vertical
    }

    github_ask:connect_signal(
        "button::press",
        function()
            github_ask.visible = false
        end
    )
end

local toggl =
    awful.widget.watch(
    string.format("sh %s/.config/polybar/scripts/toggl.sh", os.getenv("HOME")),
    60,
    function(widget, stdout)
        widget:set_markup(
            markup("#FFFFFF", markup.font("Roboto 10", "  ") .. markup.font(theme.font, stdout .. "    "))
        )
    end
)
local toggl_bg = wibox.container.background(toggl, theme.bg_focus, gears.shape.rectangle)
local toggl_widget = wibox.container.margin(toggl_bg, 0, 0, 5, 5)
toggl_widget:connect_signal(
    "button::press",
    function()
        awful.spawn.with_shell("google-chrome-beta https://www.toggl.com/app/timer")
    end
)

local toggl_report =
    awful.widget.watch(
    string.format("sh %s/.config/polybar/scripts/toggl-report.sh hide", os.getenv("HOME")),
    99999,
    function(widget, stdout)
        widget:set_markup(
            markup(
                "#FFFFFF",
                markup.font("Roboto 10", "  ") ..
                    markup.font(string.format("%s 10", theme.font_awesome), "") .. markup.font("Roboto 10", "  ")
            )
        )
    end
)
local toggl_report_bg = wibox.container.background(toggl_report, theme.bg_focus, gears.shape.rectangle)
local toggl_report_widget = wibox.container.margin(toggl_report_bg, 0, 0, 5, 5)
toggl_report_widget:connect_signal(
    "button::press",
    function()
        awful.spawn.with_shell(string.format("sh %s/.config/polybar/scripts/toggl-report.sh show", os.getenv("HOME")))
    end
)

-- System Tray - Systray
local systray_base = wibox.widget.systray(true)
local systray_bg = wibox.container.background(systray_base, theme.bg_focus, gears.shape.rectangle)
local systray_widget = wibox.container.margin(systray_bg, 0, 0, 5, 5)

-- Clock
local clock_icon = markup.font(string.format("%s Solid 9", theme.font_awesome), "")
local here_textclock = theme.widget_container(wibox.widget.textclock(clock_icon .. markup.font(theme.font, "  %H:%M  ")))
local frankfurt_textclock = theme.widget_container(wibox.widget.textclock(markup.font(theme.font, "%H:%M  "), 60, "+1"))

-- Keyboard
local keyboard = layout_indicator()
keyboard.font = theme.font
local keyboard_bg = wibox.container.background(keyboard, theme.bg_focus, gears.shape.rectangle)
local keyboard_widget = wibox.container.margin(keyboard_bg, 0, 0, 5, 5)

function relaunch_layout()
    awful.spawn.with_shell("setxkbmap -layout us,ir -option grp:alt_shift_toggle")
end

keyboard_widget:buttons(my_table.join(awful.button({}, 1, relaunch_layout)))

-- Calendar
local mytextcalendar =
    wibox.widget.textclock(markup.fontfg(theme.font, "#FFFFFF", space3 .. "%d %b " .. markup.font("Roboto 5", " ")))
local calendar_icon = wibox.widget.imagebox(theme.calendar)
local calbg = wibox.container.background(mytextcalendar, theme.bg_focus, gears.shape.rectangle)
local calendarwidget = wibox.container.margin(calbg, 0, 0, 5, 5)
theme.cal =
    lain.widget.cal(
    {
        attach_to = {here_textclock, frankfurt_textclock, mytextcalendar},
        notification_preset = {
            fg = "#FFFFFF",
            bg = theme.bg_normal,
            position = "bottom_right",
            font = "Roboto Mono 10"
        }
    }
)

-- Mail IMAP check
--[[ commented because it needs to be set before use ]]
theme.mail =
    lain.widget.imap(
    {
        timeout = 180,
        server = "server",
        mail = "mail",
        password = "keyring get mail",
        settings = function()
            mail_notification_preset.fg = "#FFFFFF"
            mail = ""
            count = ""

            if mailcount > 0 then
                mail = "Mail "
                count = mailcount .. " "
            end

            widget:set_markup(markup.font(theme.font, markup(blue, mail) .. markup("#FFFFFF", count)))
        end
    }
)
-- ]]
-- MPD
local mpd_icon = wibox.widget.textbox()
mpd_icon:set_markup(
    markup.font("Roboto 10", "  ") ..
        markup.font(string.format("%s 10", theme.font_awesome), "") .. markup.font("Roboto 10", "  ")
)
mpd_icon:buttons(
    my_table.join(
        awful.button(
            {},
            1,
            function()
                awful.spawn.with_shell(theme.musicplr)
            end
        )
    )
)
local mpd_icon_bg = wibox.container.background(mpd_icon, theme.bg_focus, gears.shape.rectangle)
local mpd_icon_widget = wibox.container.margin(mpd_icon_bg, 0, 0, 5, 5)

local prev_icon = wibox.widget.textbox()
prev_icon:set_markup(
    markup.font("Roboto 10", "  ") ..
        markup.font(string.format("%s 8", theme.font_awesome), "") .. markup.font("Roboto 10", "  ")
)
local prev_icon_widget =
    wibox.container.margin(wibox.container.background(prev_icon, theme.bg_focus, gears.shape.rectagle), 0, 0, 5, 5)

local next_icon = wibox.widget.textbox()
next_icon:set_markup(
    markup.font("Roboto 10", "  ") ..
        markup.font(string.format("%s 8", theme.font_awesome), "") .. markup.font("Roboto 10", "  ")
)
local next_icon_widget =
    wibox.container.margin(wibox.container.background(next_icon, theme.bg_focus, gears.shape.rectagle), 0, 0, 5, 5)

local stop_icon = wibox.widget.textbox()
stop_icon:set_markup(
    markup.font("Roboto 10", "  ") ..
        markup.font(string.format("%s 8", theme.font_awesome), "") .. markup.font("Roboto 10", "  ")
)
local stop_icon_widget =
    wibox.container.margin(wibox.container.background(stop_icon, theme.bg_focus, gears.shape.rectagle), 0, 0, 5, 5)

local pause_icon = wibox.widget.textbox()
pause_icon:set_markup(
    markup.font("Roboto 10", "  ") ..
        markup.font(string.format("%s 8", theme.font_awesome), "") .. markup.font("Roboto 10", "  ")
)
local pause_icon_widget =
    wibox.container.margin(wibox.container.background(pause_icon, theme.bg_focus, gears.shape.rectagle), 0, 0, 5, 5)

local play_pause_icon = wibox.widget.textbox()
play_pause_icon:set_markup(
    markup.font("Roboto 10", "  ") ..
        markup.font(string.format("%s 8", theme.font_awesome), "") .. markup.font("Roboto 10", "  ")
)
local play_pause_icon_widget =
    wibox.container.margin(
    wibox.container.background(play_pause_icon, theme.bg_focus, gears.shape.rectagle),
    0,
    0,
    5,
    5
)
theme.mpd =
    lain.widget.mpd(
    {
        notify = "off",
        settings = function()
            if mpd_now.state == "play" then
                mpd_now.artist = mpd_now.artist:upper():gsub("&.-;", string.lower)
                mpd_now.title = mpd_now.title:upper():gsub("&.-;", string.lower)
                widget:set_markup(
                    markup.font("Roboto 4", " ") ..
                        markup.font(theme.taglist_font, " " .. mpd_now.artist .. " - " .. mpd_now.title .. "  ") ..
                            markup.font("Roboto 5", " ")
                )
                play_pause_icon:set_markup(
                    markup.font("Roboto 10", "  ") ..
                        markup.font(string.format("%s 8", theme.font_awesome), "") .. markup.font("Roboto 10", "  ")
                )
            elseif mpd_now.state == "pause" then
                widget:set_markup(
                    markup.font("Roboto 4", " ") ..
                        markup.font(theme.taglist_font, " MPD PAUSED  ") .. markup.font("Roboto 5", " ")
                )
                play_pause_icon:set_markup(
                    markup.font("Roboto 10", "  ") ..
                        markup.font(string.format("%s 8", theme.font_awesome), "") .. markup.font("Roboto 10", "  ")
                )
            else
                widget:set_markup("")
                play_pause_icon:set_markup(
                    markup.font("Roboto 10", "  ") ..
                        markup.font(string.format("%s 8", theme.font_awesome), "") .. markup.font("Roboto 10", "  ")
                )
            end
        end
    }
)
local musicbg = wibox.container.background(theme.mpd.widget, theme.bg_focus, gears.shape.rectangle)
local musicwidget = wibox.container.margin(musicbg, 0, 0, 5, 5)

musicwidget:buttons(
    my_table.join(
        awful.button(
            {},
            1,
            function()
                awful.spawn(theme.musicplr)
            end
        )
    )
)
prev_icon:buttons(
    my_table.join(
        awful.button(
            {},
            1,
            function()
                os.execute("mpc prev")
                theme.mpd.update()
            end
        )
    )
)
next_icon:buttons(
    my_table.join(
        awful.button(
            {},
            1,
            function()
                os.execute("mpc next")
                theme.mpd.update()
            end
        )
    )
)
stop_icon:buttons(
    my_table.join(
        awful.button(
            {},
            1,
            function()
                play_pause_icon:set_markup(
                    arkup.font("Roboto 10", "  ") ..
                        markup.font(string.format("%s 8", theme.font_awesome), "") .. markup.font("Roboto 10", "  ")
                )
                os.execute("mpc stop")
                theme.mpd.update()
            end
        )
    )
)
play_pause_icon:buttons(
    my_table.join(
        awful.button(
            {},
            1,
            function()
                os.execute("mpc toggle")
                theme.mpd.update()
            end
        )
    )
)

-- Battery
local bat =
    lain.widget.bat(
    {
        settings = function()
            perc = bat_now.perc
            bat_icon = ""
            -- bat_now.ac_status == 1 means is charging
            if perc >= 90 then
                bat_icon = ""
            elseif perc >= 75 then
                bat_icon = ""
            elseif perc >= 50 then
                bat_icon = ""
            elseif perc >= 25 then
                bat_icon = ""
            else
                bat_icon.perc = ""
            end
            widget:set_markup(
                space3 ..
                    markup.font(string.format("%s 10", theme.font_awesome), bat_icon) ..
                        markup.font(theme.font, "  " .. perc .. "%") .. markup.font("Roboto 5", " ")
            )
        end
    }
)

local bat_bg = wibox.container.background(bat.widget, theme.bg_focus, gears.shape.rectangle)
local bat_widget = wibox.container.margin(bat_bg, 0, 0, 5, 5)

-- MEM
local mem =
    lain.widget.mem(
    {
        timeout = 1,
        settings = function()
            widget:set_markup(
                space3 ..
                    markup.font(string.format("%s 10", theme.font_awesome), "") ..
                        markup.font(theme.font, "  " .. mem_now.perc .. "% ")
            )
        end
    }
)
local mem_bg = wibox.container.background(mem.widget, theme.bg_focus, gears.shape.rectangle)
local mem_widget = wibox.container.margin(mem_bg, 0, 0, 5, 5)

-- / fs
--[[ commented because it needs Gio/Glib >= 2.54
theme.fs = lain.widget.fs({
    notification_preset = { bg = theme.bg_normal, font = "Monospace 9" },
})
--]]
-- ALSA volume bar
theme.volume =
    lain.widget.alsa(
    {
        settings = function()
            vlevel = markup.font(theme.font, volume_now.level)
            if volume_now.status == "on" then
                vlevel =
                    markup.font(string.format("%s 10", theme.font_awesome), " ") ..
                    markup.font("Roboto 10", "  ") .. vlevel .. markup.font("Roboto 10", "  ")
            else
                vlevel =
                    markup.font(string.format("%s 10", theme.font_awesome), " ") .. markup.font("Roboto 10", "   ")
            end
            widget:set_markup(markup("#FFFFFF", vlevel))
        end
    }
)
local volumewidget = wibox.container.background(theme.volume.widget, theme.bg_focus, gears.shape.rectangle)
volumewidget = wibox.container.margin(volumewidget, 0, 0, 5, 5)
theme.volume.widget:buttons(
    awful.util.table.join(
        awful.button(
            {},
            4,
            function()
                os.execute(string.format("%s set %s 5%%+", theme.volume.cmd, theme.volume.channel))
                theme.volume.update()
            end
        ),
        awful.button(
            {},
            5,
            function()
                os.execute(string.format("%s set %s 5%%-", theme.volume.cmd, theme.volume.channel))
                theme.volume.update()
            end
        ),
        awful.button(
            {},
            1,
            function()
                os.execute(
                    string.format(
                        "%s set %s toggle",
                        theme.volume.cmd,
                        theme.volume.togglechannel or theme.volume.channel
                    )
                )
                theme.volume.update()
            end
        )
    )
)
-- CPU
local cpu =
    lain.widget.cpu(
    {
        settings = function()
            widget:set_markup(
                markup.font(string.format("%s 10", theme.font_awesome), "") ..
                    markup.font(theme.font, "  " .. cpu_now.usage .. "% ") .. markup.font("Roboto 5", " ")
            )
        end
    }
)
local cpubg = wibox.container.background(cpu.widget, theme.bg_focus, gears.shape.rectangle)
local cpuwidget = wibox.container.margin(cpubg, 0, 0, 5, 5)

-- Net
local netdown_icon = wibox.widget.imagebox(theme.net_down)
local netup_icon = wibox.widget.imagebox(theme.net_up)
local net =
    lain.widget.net(
    {
        settings = function()
            widget:set_markup(
                markup.font("Roboto 1", " ") ..
                    markup.font(theme.font, net_now.received .. " - " .. net_now.sent) .. markup.font("Roboto 2", " ")
            )
        end
    }
)
local netbg = wibox.container.background(net.widget, theme.bg_focus, gears.shape.rectangle)
local networkwidget = wibox.container.margin(netbg, 0, 0, 5, 5)

-- Weather
theme.weather =
    lain.widget.weather(
    {
        city_id = 2643743, -- placeholder (London)
        notification_preset = {font = "Monospace 9", position = "bottom_right"}
    }
)

-- Launcher
local mylauncher = awful.widget.button({image = theme.awesome_icon_launcher})
mylauncher:connect_signal(
    "button::press",
    function()
        awful.spawn.with_shell("")
    end
)

-- Brightness
-- local brightness_widget_display =
--     brightness(
--     {
--         markup = markup("#FFFFFF", markup.font(theme.font_awesome .. " Solid 9", "") .. markup.font(theme.font, " %s"))
--     }
-- )
-- local brightness_widget_bg =
--     wibox.container.background(brightness_widget_display, theme.bg_focus, gears.shape.rectangle)
-- local brightness_widget = wibox.container.margin(brightness_widget_bg, 0, 0, 5, 5)

-- Separators
local first = wibox.widget.textbox('<span font="Roboto 7"> </span>')
local spr_small = wibox.widget.imagebox(theme.spr_small)
local spr_very_small = wibox.widget.imagebox(theme.spr_very_small)
local spr_right = wibox.widget.imagebox(theme.spr_right)
local spr_bottom_right = wibox.widget.imagebox(theme.spr_bottom_right)
local spr_left = wibox.widget.imagebox(theme.spr_left)
local bar = wibox.widget.imagebox(theme.bar)
local bottom_bar = wibox.widget.textbox('<span font="Roboto 10">    </span>')
local bottom_bar_bg = wibox.container.background(bottom_bar, theme.bg_focus, gears.shape.rectangle)
local bottom_bar_bg_widget = wibox.container.margin(bottom_bar_bg, 0, 0, 5, 5)

theme.widget_separator = function(length)
    local str = '<span font="Roboto 10">'
    for i = 1, length do
        str = str .. " "
    end
    str = str .. "</span>"
    return theme.widget_container(wibox.widget.textbox(str), 0, 0, 5, 5)
end

function theme.at_screen_connect(s)
    -- If wallpaper is a function, call it with the screen
    local wallpaper = theme.wallpaper
    if type(wallpaper) == "function" then
        wallpaper = wallpaper(s)
    end
    gears.wallpaper.maximized(wallpaper, s, true)

    -- Tags
    awful.tag(awful.util.tagnames, s, awful.layout.layouts[1])

    -- Create a promptbox for each screen
    s.mypromptbox = awful.widget.prompt()
    -- Create an imagebox widget which will contains an icon indicating which layout we're using.
    -- We need one layoutbox per screen.
    s.mylayoutbox = awful.widget.layoutbox(s)
    s.mylayoutbox:buttons(
        my_table.join(
            awful.button(
                {},
                1,
                function()
                    awful.layout.inc(1)
                end
            ),
            awful.button(
                {},
                2,
                function()
                    awful.layout.set(awful.layout.layouts[1])
                end
            ),
            awful.button(
                {},
                3,
                function()
                    awful.layout.inc(-1)
                end
            ),
            awful.button(
                {},
                4,
                function()
                    awful.layout.inc(1)
                end
            ),
            awful.button(
                {},
                5,
                function()
                    awful.layout.inc(-1)
                end
            )
        )
    )
    -- Create a taglist widget
    s.mytaglist = awful.widget.taglist(s, awful.widget.taglist.filter.noempty, awful.util.taglist_buttons)

    mytaglistcont = wibox.container.background(s.mytaglist, theme.bg_focus, gears.shape.rectangle)
    s.mytag = wibox.container.margin(mytaglistcont, 0, 0, 5, 5)

    -- Create a tasklist widget
    s.mytasklist =
        awful.widget.tasklist(
        s,
        awful.widget.tasklist.filter.currenttags,
        awful.util.tasklist_buttons,
        {
            bg_focus = theme.bg_focus,
            shape = gears.shape.rectangle,
            shape_border_width = 5,
            shape_border_color = theme.tasklist_bg_normal,
            align = "center"
        },
        nil,
        {
            {
                {
                    {
                        {
                            id     = 'icon_role',
                            widget = wibox.widget.imagebox,
                        },
                        margins = 2,
                        widget  = wibox.container.margin,
                    },
                    {
                        id     = 'text_role',
                        widget = wibox.widget.textbox,
                    },
                    layout = wibox.layout.fixed.horizontal,
                },
                left  = 10,
                right = 10,
                widget = wibox.container.margin
            },
            id     = 'background_role',
            widget = wibox.container.background,
        }
    )

    -- Create the wibox
    s.mywibox = awful.wibar({position = "top", screen = s, height = 32})

    -- Add widgets to the wibox
    s.mywibox:setup {
        layout = wibox.layout.align.horizontal,
        {
            -- Left widgets
            layout = wibox.layout.fixed.horizontal,
            s.mytag,
            spr_small,
            s.mypromptbox
        },
        nil, -- Middle widget
        {
            -- Right widgets
            layout = wibox.layout.fixed.horizontal,
            -- theme.mail.widget,
            github_widget,
            bar,
            toggl_widget,
            bar,
            toggl_report_widget,
            bar,
            prev_icon_widget,
            next_icon_widget,
            stop_icon_widget,
            play_pause_icon_widget,
            bar,
            mpd_icon_widget,
            bar,
            spr_very_small,
            spr_very_small,
            -- brightness_widget,
            spr_very_small,
            bar,
            spr_very_small,
            volumewidget,
            spr_very_small
        }
    }

    -- Create the bottom wibox
    s.mybottomwibox =
        awful.wibar(
        {
            position = "bottom",
            screen = s,
            border_width = 0,
            height = 32
        }
    )

    -- Add widgets to the bottom wibox
    s.mybottomwibox:setup {
        layout = wibox.layout.align.horizontal,
        {
            -- Left widgets
            layout = wibox.layout.fixed.horizontal,
            s.mylayoutbox
        },
        s.mytasklist, -- Middle widget
        {
            -- Right widgets
            layout = wibox.layout.fixed.horizontal,
            spr_bottom_right,
            ping_widget,
            bottom_bar_bg_widget,
            cpu_icon,
            cpuwidget,
            bottom_bar_bg_widget,
            mem_widget,
            bottom_bar_bg_widget,
            fs_widget,
            bottom_bar_bg_widget,
            bat_widget,
            bottom_bar_bg_widget,
            keyboard_widget,
            -- bottom_bar_bg_widget,
            -- calendar_icon,
            -- calendarwidget,
            bottom_bar_bg_widget,
            here_textclock,
            bottom_bar_bg_widget,
            systray_widget,
            spr_right
        }
    }
end

theme.titlebar_fun = function(c)end

return theme
