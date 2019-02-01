--[[

     Awesome WM configuration template
     github.com/lcpz

--]]
-- {{{ Required libraries
local awesome, client, mouse, screen, tag = awesome, client, mouse, screen, tag
local ipairs, string, os, table, tostring, tonumber, type = ipairs, string, os, table, tostring, tonumber, type

local gears = require("gears")
local awful = require("awful")
require("awful.autofocus")
local wibox = require("wibox")
local beautiful = require("beautiful")
local naughty = require("naughty")
local lain = require("lain")
local helpers = require("helpers")
local hotkeys_popup = require("awful.hotkeys_popup").widget
require("awful.hotkeys_popup.keys")
local my_table = awful.util.table or gears.table -- 4.{0,1} compatibility
-- }}}

-- {{{ Error handling
-- Check if awesome encountered an error during startup and fell back to
-- another config (This code will only ever execute for the fallback config)
if awesome.startup_errors then
    naughty.notify(
        {
            preset = naughty.config.presets.critical,
            title = "Oops, there were errors during startup!",
            text = awesome.startup_errors
        }
    )
end

-- Handle runtime errors after startup
do
    local in_error = false
    awesome.connect_signal(
        "debug::error",
        function(err)
            if in_error then
                return
            end
            in_error = true

            naughty.notify(
                {
                    preset = naughty.config.presets.critical,
                    title = "Oops, an error happened!",
                    text = tostring(err)
                }
            )
            in_error = false
        end
    )
end
-- }}}

-- {{{ Autostart processes
awful.spawn.with_shell(string.format("sh %s/.config/awesome/autorun.sh", os.getenv("HOME")))
-- }}}

-- {{{ Variable definitions

local themes = {
    "blackburn", -- 1
    "copland", -- 2
    "dremora", -- 3
    "holo", -- 4
    "multicolor", -- 5
    "powerarrow", -- 6
    "powerarrow-dark", -- 7
    "rainbow", -- 8
    "steamburn", -- 9
    "vertex" -- 10
}

local chosen_theme = themes[4]
local modkey = "Mod4"
local altkey = "Mod1"
local terminal = "xterm"
local editor = os.getenv("EDITOR") or "vim"
local gui_editor = "code"
local browser = "google-chrome-beta"
local guieditor = "code"

awful.util.terminal = terminal
awful.util.tagnames = {"  ", "  ", "  ", "  ", "  ", " 6 ", " 7 ", " 8 ", " 9 "}
awful.layout.layouts = {
    awful.layout.suit.tile,
    awful.layout.suit.tile.left,
    awful.layout.suit.tile.bottom,
    awful.layout.suit.tile.top,
    lain.layout.centerwork,
    awful.layout.suit.floating,
    awful.layout.suit.max
}

local quake = lain.util.quake({
    border = 1,
    followtag = true
})

awful.util.taglist_buttons =
    my_table.join(
    awful.button(
        {},
        1,
        function(t)
            t:view_only()
        end
    ),
    awful.button(
        {modkey},
        1,
        function(t)
            if client.focus then
                client.focus:move_to_tag(t)
            end
        end
    ),
    awful.button({}, 3, awful.tag.viewtoggle),
    awful.button(
        {modkey},
        3,
        function(t)
            if client.focus then
                client.focus:toggle_tag(t)
            end
        end
    ),
    awful.button(
        {},
        4,
        function(t)
            lain.util.tag_view_nonempty(-1, t.screen)
        end
    ),
    awful.button(
        {},
        5,
        function(t)
            lain.util.tag_view_nonempty(1, t.screen)
        end
    )
)

awful.util.tasklist_buttons =
    my_table.join(
    awful.button(
        {},
        1,
        function(c)
            if c == client.focus then
                c.minimized = true
            else
                --c:emit_signal("request::activate", "tasklist", {raise = true})<Paste>

                -- Without this, the following
                -- :isvisible() makes no sense
                c.minimized = false
                if not c:isvisible() and c.first_tag then
                    c.first_tag:view_only()
                end
                -- This will also un-minimize
                -- the client, if needed
                client.focus = c
                c:raise()
            end
        end
    ),
    awful.button(
        {modkey},
        2,
        function(c)
            c:kill()
        end
    ),
    awful.button(
        {},
        3,
        function()
            local instance = nil

            return function()
                if instance and instance.wibox.visible then
                    instance:hide()
                    instance = nil
                else
                    instance = awful.menu.clients({theme = {width = 250}})
                end
            end
        end
    ),
    awful.button(
        {},
        4,
        function()
            awful.client.focus.byidx(1)
        end
    ),
    awful.button(
        {},
        5,
        function()
            awful.client.focus.byidx(-1)
        end
    )
)

beautiful.init(string.format("%s/.config/awesome/themes/%s/theme.lua", os.getenv("HOME"), chosen_theme))

local exit_screen = require("exit_screen")
local info_screen = require("info_screen")
require("dock")
-- }}}

naughty.config.padding = 20
naughty.config.defaults.icon_size = 36
naughty.config.defaults.margin = 10
naughty.config.defaults.position = "bottom_left"

-- {{{ Screen
-- Re-set wallpaper when a screen's geometry changes (e.g. different resolution)
screen.connect_signal(
    "property::geometry",
    function(s)
        -- Wallpaper
        if beautiful.wallpaper then
            local wallpaper = beautiful.wallpaper
            -- If wallpaper is a function, call it with the screen
            if type(wallpaper) == "function" then
                wallpaper = wallpaper(s)
            end
            gears.wallpaper.maximized(wallpaper, s, true)
        end

        if resize_exit_screen then
            resize_exit_screen()
        end
    end
)
-- Create a wibox for each screen and add it
awful.screen.connect_for_each_screen(
    function(s)
        beautiful.at_screen_connect(s)
    end
)
-- }}}

-- {{{ Mouse bindings
root.buttons(my_table.join(awful.button({}, 4, awful.tag.viewnext), awful.button({}, 5, awful.tag.viewprev)))
-- }}}

-- {{{ Key bindings
globalkeys =
    my_table.join(
    awful.key(
        {modkey},
        "z",
        function()
            quake:toggle()
        end,
        {description = "toggle quake", group = "quake"}
    ),
    -- Notifications
    awful.key(
        {modkey, "Shift"},
        "\\",
        function()
            naughty.toggle()
        end,
        {description = "toggle notifications", group = "notification"}
    ),
    awful.key(
        {modkey},
        "\\",
        function()
            naughty.destroy_all_notifications()
        end,
        {description = "clear notifications", group = "notification"}
    ),
    -- Take a screenshot
    awful.key(
        {},
        "Print",
        function()
            awful.spawn.with_shell("flameshot full -c -p ~/Pictures/Screenshots")
        end,
        {description = "take a fullscreen screenshot", group = "hotkeys"}
    ),
    awful.key(
        {"Shift"},
        "Print",
        function()
            awful.spawn.with_shell("flameshot gui")
        end,
        {description = "take a screenshot", group = "hotkeys"}
    ),
    -- X screen locker
    awful.key(
        {altkey, "Control"},
        "l",
        function()
            awful.spawn.with_shell(beautiful.lock_cmd)
        end,
        {description = "lock screen", group = "hotkeys"}
    ),
    awful.key(
        {modkey, "Shift"},
        "x",
        function()
            awful.spawn.with_shell(beautiful.lock_cmd)
        end,
        {description = "lock screen", group = "hotkeys"}
    ),
    -- Hotkeys
    awful.key({modkey}, "s", hotkeys_popup.show_help, {description = "show help", group = "awesome"}),
    -- Tag browsing
    awful.key({modkey}, "Escape", awful.tag.history.restore, {description = "go back", group = "tag"}),
    -- Default client focus
    -- awful.key(
    --     {modkey},
    --     "Left",
    --     function()
    --         awful.client.focus.byidx(1)
    --     end,
    --     {description = "focus next by index", group = "client"}
    -- ),
    -- awful.key(
    --     {modkey},
    --     "Right",
    --     function()
    --         awful.client.focus.byidx(-1)
    --     end,
    --     {description = "focus previous by index", group = "client"}
    -- ),
    -- By direction client focus
    awful.key(
        {modkey},
        "Down",
        function()
            awful.client.focus.global_bydirection("down")
            if client.focus then
                client.focus:raise()
            end
        end,
        {description = "focus down", group = "client"}
    ),
    awful.key(
        {modkey},
        "Up",
        function()
            awful.client.focus.global_bydirection("up")
            if client.focus then
                client.focus:raise()
            end
        end,
        {description = "focus up", group = "client"}
    ),
    awful.key(
        {modkey},
        "Left",
        function()
            awful.client.focus.global_bydirection("left")
            if client.focus then
                client.focus:raise()
            end
        end,
        {description = "focus left", group = "client"}
    ),
    awful.key(
        {modkey},
        "Right",
        function()
            awful.client.focus.global_bydirection("right")
            if client.focus then
                client.focus:raise()
            end
        end,
        {description = "focus right", group = "client"}
    ),
    awful.key(
        {modkey},
        "d",
        function()
            awful.spawn.with_shell("rofi -show drun")
        end,
        {description = "show main menu", group = "awesome"}
    ),
    -- Layout manipulation
    awful.key(
        {modkey, "Shift"},
        "Left",
        function()
            awful.client.swap.byidx(1)
        end,
        {description = "swap with next client by index", group = "client"}
    ),
    awful.key(
        {modkey, "Shift"},
        "Right",
        function()
            awful.client.swap.byidx(-1)
        end,
        {description = "swap with previous client by index", group = "client"}
    ),
    awful.key(
        {modkey, "Control"},
        "Left",
        function()
            awful.screen.focus_relative(1)
        end,
        {description = "focus the next screen", group = "screen"}
    ),
    awful.key(
        {modkey, "Control"},
        "Right",
        function()
            awful.screen.focus_relative(-1)
        end,
        {description = "focus the previous screen", group = "screen"}
    ),
    awful.key({modkey}, "u", awful.client.urgent.jumpto, {description = "jump to urgent client", group = "client"}),
    awful.key(
        {modkey},
        "Tab",
        function()
            awful.client.focus.history.previous()
            if client.focus then
                client.focus:raise()
            end
        end,
        {description = "go back", group = "client"}
    ),
    -- Show/Hide Wibox
    awful.key(
        {modkey},
        "b",
        function()
            for s in screen do
                s.mywibox.visible = not s.mywibox.visible
                if s.mybottomwibox then
                    s.mybottomwibox.visible = not s.mybottomwibox.visible
                end
            end
        end,
        {description = "toggle wibox", group = "awesome"}
    ),
    -- Dynamic tagging
    awful.key(
        {modkey, "Shift"},
        "n",
        function()
            lain.util.add_tag()
        end,
        {description = "add new tag", group = "tag"}
    ),
    awful.key(
        {modkey, "Shift"},
        "r",
        function()
            lain.util.rename_tag()
        end,
        {description = "rename tag", group = "tag"}
    ),
    awful.key(
        {modkey, "Shift"},
        "d",
        function()
            lain.util.delete_tag()
        end,
        {description = "delete tag", group = "tag"}
    ),
    -- Standard program
    awful.key(
        {modkey},
        "Return",
        function()
            awful.spawn(terminal)
        end,
        {description = "open a terminal", group = "launcher"}
    ),
    awful.key({modkey, "Control"}, "r", awesome.restart, {description = "reload awesome", group = "awesome"}),
    awful.key(
        {modkey, "Shift"},
        "q",
        function()
            exit_screen_show()
        end,
        {description = "quit awesome", group = "awesome"}
    ),
    awful.key(
        {modkey, "Shift"},
        "i",
        function()
            info_screen_show()
        end,
        {description = "quit awesome", group = "awesome"}
    ),
    awful.key(
        {altkey, "Shift"},
        "Right",
        function()
            awful.tag.incmwfact(0.05)
        end,
        {description = "increase master width factor", group = "layout"}
    ),
    awful.key(
        {altkey, "Shift"},
        "Left",
        function()
            awful.tag.incmwfact(-0.05)
        end,
        {description = "decrease master width factor", group = "layout"}
    ),
    awful.key(
        {modkey, "Shift"},
        "Up",
        function()
            awful.tag.incnmaster(1, nil, true)
        end,
        {description = "increase the number of master clients", group = "layout"}
    ),
    awful.key(
        {modkey, "Shift"},
        "Down",
        function()
            awful.tag.incnmaster(-1, nil, true)
        end,
        {description = "decrease the number of master clients", group = "layout"}
    ),
    awful.key(
        {modkey, "Control"},
        "Up",
        function()
            awful.tag.incncol(1, nil, true)
        end,
        {description = "increase the number of columns", group = "layout"}
    ),
    awful.key(
        {modkey, "Control"},
        "Down",
        function()
            awful.tag.incncol(-1, nil, true)
        end,
        {description = "decrease the number of columns", group = "layout"}
    ),
    awful.key(
        {modkey},
        "space",
        function()
            awful.layout.inc(1)
        end,
        {description = "select next", group = "layout"}
    ),
    awful.key(
        {modkey, "Shift"},
        "space",
        function()
            awful.layout.inc(-1)
        end,
        {description = "select previous", group = "layout"}
    ),
    awful.key(
        {modkey, "Control"},
        "n",
        function()
            local c = awful.client.restore()
            -- Focus restored client
            if c then
                client.focus = c
                c:raise()
            end
        end,
        {description = "restore minimized", group = "client"}
    ),
    -- Widgets popups
    awful.key(
        {altkey},
        "c",
        function()
            if beautiful.cal then
                beautiful.cal.show(7)
            end
        end,
        {description = "show calendar", group = "widgets"}
    ),
    awful.key(
        {altkey},
        "h",
        function()
            if beautiful.fs then
                beautiful.fs.show(7)
            end
        end,
        {description = "show filesystem", group = "widgets"}
    ),
    awful.key(
        {altkey},
        "w",
        function()
            if beautiful.weather then
                beautiful.weather.show(7)
            end
        end,
        {description = "show weather", group = "widgets"}
    ),
    -- Brightness
    awful.key(
        {},
        "XF86MonBrightnessUp",
        function()
            os.execute("xbacklight -inc 10")
        end,
        {description = "+10%", group = "hotkeys"}
    ),
    awful.key(
        {},
        "XF86MonBrightnessDown",
        function()
            os.execute("xbacklight -dec 10")
        end,
        {description = "-10%", group = "hotkeys"}
    ),
    -- ALSA volume control
    awful.key(
        {altkey},
        "Up",
        function()
            os.execute(string.format("amixer -q set %s 5%%+", beautiful.volume.channel))
            beautiful.volume.update()
        end,
        {description = "volume up", group = "hotkeys"}
    ),
    awful.key(
        {altkey},
        "Down",
        function()
            os.execute(string.format("amixer -q set %s 5%%-", beautiful.volume.channel))
            beautiful.volume.update()
        end,
        {description = "volume down", group = "hotkeys"}
    ),
    awful.key(
        {altkey},
        "m",
        function()
            os.execute(
                string.format("amixer -q set %s toggle", beautiful.volume.togglechannel or beautiful.volume.channel)
            )
            beautiful.volume.update()
        end,
        {description = "toggle mute", group = "hotkeys"}
    ),
    awful.key(
        {altkey, "Control"},
        "m",
        function()
            os.execute(string.format("amixer -q set %s 100%%", beautiful.volume.channel))
            beautiful.volume.update()
        end,
        {description = "volume 100%", group = "hotkeys"}
    ),
    awful.key(
        {altkey, "Control"},
        "0",
        function()
            os.execute(string.format("amixer -q set %s 0%%", beautiful.volume.channel))
            beautiful.volume.update()
        end,
        {description = "volume 0%", group = "hotkeys"}
    ),
    -- MPD control
    awful.key(
        {altkey, "Control"},
        "p",
        function()
            os.execute("mpc toggle")
            beautiful.mpd.update()
        end,
        {description = "mpc toggle", group = "widgets"}
    ),
    awful.key(
        {altkey, "Control"},
        "s",
        function()
            os.execute("mpc stop")
            beautiful.mpd.update()
        end,
        {description = "mpc stop", group = "widgets"}
    ),
    awful.key(
        {altkey, "Control"},
        "j",
        function()
            os.execute("mpc prev")
            beautiful.mpd.update()
        end,
        {description = "mpc prev", group = "widgets"}
    ),
    awful.key(
        {altkey, "Control"},
        "k",
        function()
            os.execute("mpc next")
            beautiful.mpd.update()
        end,
        {description = "mpc next", group = "widgets"}
    ),
    awful.key(
        {altkey},
        "0",
        function()
            local common = {text = "MPD widget ", position = "top_middle", timeout = 2}
            if beautiful.mpd.timer.started then
                beautiful.mpd.timer:stop()
                common.text = common.text .. lain.util.markup.bold("OFF")
            else
                beautiful.mpd.timer:start()
                common.text = common.text .. lain.util.markup.bold("ON")
            end
            naughty.notify(common)
        end,
        {description = "mpc on/off", group = "widgets"}
    ),
    -- Copy primary to clipboard (terminals to gtk)
    awful.key(
        {modkey},
        "c",
        function()
            awful.spawn.with_shell("xsel | xsel -i -b")
        end,
        {description = "copy terminal to gtk", group = "hotkeys"}
    ),
    -- Copy clipboard to primary (gtk to terminals)
    awful.key(
        {modkey},
        "v",
        function()
            awful.spawn.with_shell("xsel -b | xsel")
        end,
        {description = "copy gtk to terminal", group = "hotkeys"}
    ),
    -- Prompt
    awful.key(
        {modkey},
        "r",
        function()
            awful.screen.focused().mypromptbox:run()
        end,
        {description = "run prompt", group = "launcher"}
    ),
    awful.key(
        {modkey},
        "x",
        function()
            awful.prompt.run {
                prompt = "Add reminder: ",
                textbox = awful.screen.focused().mypromptbox.widget,
                exe_callback = function(input)
                    local txt = helpers.split(input, "@")
                    awful.spawn.with_shell(
                        string.format('echo \'notify-send -u critical Reminder "%s"\' | at %s', txt[1], txt[2])
                    )
                end
            }
        end,
        {description = "set reminder", group = "utility"}
    )
    --]]
)

clientkeys =
    my_table.join(
    awful.key({altkey, "Shift"}, "m", lain.util.magnify_client, {description = "magnify client", group = "client"}),
    awful.key(
        {modkey},
        "f",
        function(c)
            c.fullscreen = not c.fullscreen
            c:raise()
        end,
        {description = "toggle fullscreen", group = "client"}
    ),
    awful.key(
        {modkey},
        "q",
        function(c)
            c:kill()
        end,
        {description = "close", group = "client"}
    ),
    awful.key(
        {modkey, "Control"},
        "space",
        awful.client.floating.toggle,
        {description = "toggle floating", group = "client"}
    ),
    awful.key(
        {modkey, "Shift"},
        "Return",
        function(c)
            c:swap(awful.client.getmaster())
        end,
        {description = "move to master", group = "client"}
    ),
    awful.key(
        {modkey},
        "o",
        function(c)
            c:move_to_screen()
        end,
        {description = "move to screen", group = "client"}
    ),
    awful.key(
        {modkey},
        "t",
        function(c)
            c.ontop = not c.ontop
        end,
        {description = "toggle keep on top", group = "client"}
    ),
    awful.key(
        {modkey},
        "n",
        function(c)
            -- The client currently has the input focus, so it cannot be
            -- minimized, since minimized clients can't have the focus.
            c.minimized = true
        end,
        {description = "minimize", group = "client"}
    ),
    awful.key(
        {modkey},
        "m",
        function(c)
            c.maximized = not c.maximized
            c:raise()
        end,
        {description = "maximize", group = "client"}
    )
)

-- Bind all key numbers to tags.
-- Be careful: we use keycodes to make it works on any keyboard layout.
-- This should map on the top row of your keyboard, usually 1 to 9.
for i = 1, 9 do
    -- Hack to only show tags 1 and 9 in the shortcut window (mod+s)
    local descr_view, descr_toggle, descr_move, descr_toggle_focus
    if i == 1 or i == 9 then
        descr_view = {description = "view tag #", group = "tag"}
        descr_toggle = {description = "toggle tag #", group = "tag"}
        descr_move = {description = "move focused client to tag #", group = "tag"}
        descr_toggle_focus = {description = "toggle focused client on tag #", group = "tag"}
    end
    globalkeys =
        my_table.join(
        globalkeys,
        -- View tag only.
        awful.key(
            {modkey},
            "#" .. i + 9,
            function()
                local screen = awful.screen.focused()
                local tag = screen.tags[i]
                if tag then
                    tag:view_only()
                end
            end,
            descr_view
        ),
        -- Toggle tag display.
        awful.key(
            {modkey, "Control"},
            "#" .. i + 9,
            function()
                local screen = awful.screen.focused()
                local tag = screen.tags[i]
                if tag then
                    awful.tag.viewtoggle(tag)
                end
            end,
            descr_toggle
        ),
        -- Move client to tag.
        awful.key(
            {modkey, "Shift"},
            "#" .. i + 9,
            function()
                if client.focus then
                    local tag = client.focus.screen.tags[i]
                    if tag then
                        client.focus:move_to_tag(tag)
                    end
                end
            end,
            descr_move
        ),
        -- Toggle tag on focused client.
        awful.key(
            {modkey, "Control", "Shift"},
            "#" .. i + 9,
            function()
                if client.focus then
                    local tag = client.focus.screen.tags[i]
                    if tag then
                        client.focus:toggle_tag(tag)
                    end
                end
            end,
            descr_toggle_focus
        )
    )
end

clientbuttons =
    gears.table.join(
    awful.button(
        {},
        1,
        function(c)
            c:emit_signal("request::activate", "mouse_click", {raise = true})
        end
    ),
    awful.button(
        {modkey},
        1,
        function(c)
            c:emit_signal("request::activate", "mouse_click", {raise = true})
            awful.mouse.client.move(c)
        end
    ),
    awful.button(
        {modkey},
        3,
        function(c)
            c:emit_signal("request::activate", "mouse_click", {raise = true})
            awful.mouse.client.resize(c)
        end
    )
)

-- Set keys
root.keys(globalkeys)
-- }}}

-- {{{ Rules
-- Rules to apply to new clients (through the "manage" signal).
awful.rules.rules = {
    -- All clients will match this rule.
    {
        rule = {},
        properties = {
            border_width = beautiful.border_width,
            border_color = beautiful.border_normal,
            focus = awful.client.focus.filter,
            raise = true,
            keys = clientkeys,
            buttons = clientbuttons,
            screen = awful.screen.preferred,
            placement = awful.placement.no_overlap + awful.placement.no_offscreen,
            size_hints_honor = false
        }
    },
    -- Floating clients.
    {
        rule_any = {
            instance = {
                "DTA", -- Firefox addon DownThemAll.
                "copyq" -- Includes session name in class.
            },
            class = {
                "Arandr",
                "Gpick",
                "Kruler",
                "MessageWin", -- kalarm.
                "Sxiv",
                "Wpa_gui",
                "pinentry",
                "veromix",
                "xtightvncviewer"
            },
            name = {
                "Event Tester" -- xev.
            },
            role = {
                "AlarmWindow", -- Thunderbird's calendar.
                "pop-up" -- e.g. Google Chrome's (detached) Developer Tools.
            }
        },
        properties = {floating = true}
    },
    -- Titlebars
    {
        rule_any = {type = {"dialog"}},
        properties = {titlebars_enabled = true},
        callback = function(c)
            awful.placement.centered(c, nil)
        end
    },
    {
        rule_any = {type = {"normal"}},
        properties = {titlebars_enabled = false}
    },
    -- Set Firefox to always map on the first tag on screen 1.
    {
        rule = {class = "Google-chrome-beta"},
        properties = {screen = screen:count() == 2 and 2 or 1, tag = awful.util.tagnames[1]}
    },
    {
        rule = {class = "Code"},
        properties = {
            screen = screen:count() == 2 and 2 or 1,
            tag = awful.util.tagnames[2],
            maximized = false
        }
    },
    {
        rule = {class = "Terminator", "XTerm"},
        properties = {screen = 1, tag = awful.util.tagnames[3]}
    },
    {
        rule = {class = "TelegramDesktop"},
        properties = {screen = screen:count() == 2 and 2 or 1, tag = awful.util.tagnames[5]}
    }
}
-- }}}

-- {{{ Signals
-- Signal function to execute when a new client appears.
client.connect_signal(
    "manage",
    function(c)
        -- Set the windows at the slave,
        -- i.e. put it at the end of others instead of setting it master.
        -- if not awesome.startup then awful.client.setslave(c) end

        if awesome.startup and not c.size_hints.user_position and not c.size_hints.program_position then
            -- Prevent clients from being unreachable after screen count changes.
            awful.placement.no_offscreen(c)
        end
    end
)

-- Add a titlebar if titlebars_enabled is set to true in the rules.
client.connect_signal(
    "request::titlebars",
    function(c)
        -- Custom
        if beautiful.titlebar_fun then
            beautiful.titlebar_fun(c)
            return
        end

        -- Default
        -- buttons for the titlebar
        local buttons =
            my_table.join(
            awful.button(
                {},
                1,
                function()
                    c:emit_signal("request::activate", "titlebar", {raise = true})
                    awful.mouse.client.move(c)
                end
            ),
            awful.button(
                {},
                2,
                function()
                    c:kill()
                end
            ),
            awful.button(
                {},
                3,
                function()
                    c:emit_signal("request::activate", "titlebar", {raise = true})
                    awful.mouse.client.resize(c)
                end
            )
        )

        awful.titlebar(c, {size = 16}):setup {
            {
                -- Left
                awful.titlebar.widget.iconwidget(c),
                buttons = buttons,
                layout = wibox.layout.fixed.horizontal
            },
            {
                -- Middle
                {
                    -- Title
                    align = "center",
                    widget = awful.titlebar.widget.titlewidget(c)
                },
                buttons = buttons,
                layout = wibox.layout.flex.horizontal
            },
            {
                -- Right
                awful.titlebar.widget.floatingbutton(c),
                awful.titlebar.widget.maximizedbutton(c),
                awful.titlebar.widget.stickybutton(c),
                awful.titlebar.widget.ontopbutton(c),
                awful.titlebar.widget.closebutton(c),
                layout = wibox.layout.fixed.horizontal()
            },
            layout = wibox.layout.align.horizontal
        }
    end
)

-- Enable sloppy focus, so that focus follows mouse.
client.connect_signal(
    "mouse::enter",
    function(c)
        c:emit_signal("request::activate", "mouse_enter", {raise = true})
    end
)

-- No border for maximized clients
function border_adjust(c)
    if c.maximized then -- no borders if only 1 client visible
        c.border_width = 0
    elseif #awful.screen.focused().clients > 1 then
        c.border_width = beautiful.border_width
        c.border_color = beautiful.border_focus
    else
        c.border_width = 0
    end
end

client.connect_signal("property::maximized", border_adjust)
client.connect_signal("focus", border_adjust)
client.connect_signal(
    "unfocus",
    function(c)
        c.border_color = beautiful.border_normal
        c.border_width = 1
    end
)

-- possible workaround for tag preservation when switching back to default screen:
-- https://github.com/lcpz/awesome-copycats/issues/251
-- }}}
