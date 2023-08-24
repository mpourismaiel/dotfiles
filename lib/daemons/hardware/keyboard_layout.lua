-------------------------------------------
-- @author https://github.com/Kasper24
-- @copyright 2021-2022 Kasper24
-------------------------------------------
local awful = require("awful")
local gobject = require("gears.object")
local gtable = require("gears.table")
local string_helpers = require("lib.helpers.string")

local keyboard_layout = {}
local instance = nil

function keyboard_layout:cycle_layout()
    self._private.widget:next_layout()
end

function keyboard_layout:get_current_layout_as_text()
    return string_helpers.trim(self._private.widget.widget.text:upper())
end

local function new()
    local ret = gobject {}
    gtable.crush(ret, keyboard_layout, true)

    ret._private = {}

    ret._private.widget = awful.widget.keyboardlayout()

    return ret
end
if not instance then
    instance = new()
end
return instance
