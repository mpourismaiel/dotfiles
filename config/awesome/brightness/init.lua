--[[

Brightness control
==================

based on `xbacklight`!

alternative ways to control brightness:
    sudo setpci -s 00:02.0 F4.B=80
    xgamma -gamma .75
    xrandr --output LVDS1 --brightness 0.9
    echo X > /sys/class/backlight/intel_backlight/brightness
    xbacklight

--]]
local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")

------------------------------------------
-- Private utility functions
------------------------------------------

local function readcommand(command)
    local file = io.popen(command)
    local text = file:read("*all")
    file:close()
    return text
end

local function quote_arg(str)
    return "'" .. string.gsub(str, "'", "'\\''") .. "'"
end

local function quote_args(first, ...)
    if #{...} == 0 then
        return quote_arg(first)
    else
        return quote_arg(first), quote_args(...)
    end
end

local function make_argv(...)
    return table.concat({quote_args(...)}, " ")
end

------------------------------------------
-- Volume control interface
------------------------------------------

local vcontrol = {}
local timer

function vcontrol:new(args)
    return setmetatable({}, {__index = self}):init(args)
end

function vcontrol:init(args)
    args = args or {}
    self.cmd = "xbacklight"
    self.step = args.step or "5"
    self.markup = args.markup
    self.level1 = args.level1
    self.level2 = args.level2
    self.level3 = args.level3
    self.level4 = args.level4

    self.widget = wibox.widget.textbox()
    self.widget.set_align("right")

    self.widget:connect_signal("mouse::enter", function() self:get() end)
    self.widget:buttons(
        awful.util.table.join(
            awful.button(
                {},
                1,
                function()
                    self:get()
                    self:up()
                end
            ),
            awful.button(
                {},
                3,
                function()
                    self:get()
                    self:down()
                end
            )
        )
    )
    self:get()

    return self.widget
end

function vcontrol:exec(...)
    return readcommand(make_argv(self.cmd, ...))
end

function vcontrol:get()
    if timer then timer:stop() end
    local brightness = math.floor(0.5 + tonumber(self:exec("-get") or "0"))
    local icon = ""
    if brightness <= 25 then
        icon = self.level1
    elseif brightness <= 50 then
        icon = self.level2
    elseif brightness <= 75 then
        icon = self.level3
    elseif brightness <= 100 then
        icon = self.level4
    end
    self.widget:set_markup(icon .. string.format(self.markup, string.format("%d", brightness) .. "%"))
    timer = gears.timer({
        timeout   = 5,
        autostart = true,
        callback  = function()
            self.widget:set_markup(icon)
            timer:stop()
        end
    })
    return brightness
end

function vcontrol:set(brightness)
    self:exec("-set", tostring(brightness))
    self:get()
end

function vcontrol:up()
    local brightnessLevel = self:get()
    if brightnessLevel == 100 then
        self:set(25)
    elseif brightnessLevel >= 75 then
        self:set(100)
    elseif brightnessLevel >= 50 then
        self:set(75)
    elseif brightnessLevel >= 25 then
        self:set(50)
    end
end

function vcontrol:down()
    local brightnessLevel = self:get()
    if brightnessLevel == 100 then
        self:set(75)
    elseif brightnessLevel >= 75 then
        self:set(50)
    elseif brightnessLevel >= 50 then
        self:set(25)
    elseif brightnessLevel >= 25 then
        self:set(100)
    end
end

return setmetatable(
    vcontrol,
    {
        __call = vcontrol.new
    }
)
