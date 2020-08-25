-------------------------------------------------
-- Calendar Widget for Awesome Window Manager
-- Shows the current month and supports scroll up/down to switch month
-- More details could be found here:
-- https://github.com/streetturtle/awesome-wm-widgets/tree/master/calendar-widget

-- @author Pavel Makhov
-- @copyright 2019 Pavel Makhov
-------------------------------------------------

local awful = require("awful")
local beautiful = require("beautiful")
local wibox = require("wibox")
local gears = require("gears")
local naughty = require("naughty")
local lain = require("lain")
local markup = lain.util.markup

local background = wibox.container.background
local margin = wibox.container.margin
local place = wibox.container.place
local margin = wibox.container.margin

local calendar_widget = {}

local function worker(theme)
  local calendar_themes = {
    bg = "#1a1a1a",
    fg = theme.fg_normal,
    focus_date_bg = theme.primary,
    focus_date_fg = "#000000",
    weekend_day_bg = "#1a1a1a",
    weekday_fg = theme.primary,
    header_fg = theme.fg_normal,
    border = "#4C566A"
  }

  local styles = {}
  local function rounded_shape(size)
    return function(cr, width, height)
      gears.shape.rounded_rect(cr, width, height, size)
    end
  end

  styles.month = {
    padding = 4,
    bg_color = calendar_themes.bg,
    border_width = 0
  }

  styles.normal = {
    markup = function(t)
      return t
    end,
    shape = rounded_shape(4)
  }

  styles.focus = {
    fg_color = calendar_themes.focus_date_fg,
    bg_color = calendar_themes.focus_date_bg,
    markup = function(t)
      return "<b>" .. t .. "</b>"
    end,
    shape = rounded_shape(4)
  }

  styles.header = {
    fg_color = calendar_themes.header_fg,
    bg_color = calendar_themes.bg,
    markup = function(t)
      return "<b>" .. t .. "</b>"
    end
  }

  styles.weekday = {
    fg_color = calendar_themes.weekday_fg,
    bg_color = calendar_themes.bg,
    markup = function(t)
      return "<b>" .. t .. "</b>"
    end
  }

  local function decorate_cell(widget, flag, date)
    if flag == "monthheader" and not styles.monthheader then
      flag = "header"
    end

    -- highlight only today's day
    if flag == "focus" then
      local today = os.date("*t")
      if today.month ~= date.month then
        flag = "normal"
      end
    end

    local props = styles[flag] or {}
    if props.markup and widget.get_text and widget.set_markup then
      widget:set_markup(props.markup(widget:get_text()))
    end
    -- Change bg color for weekends
    local d = {year = date.year, month = (date.month or 1), day = (date.day or 1)}
    local weekday = tonumber(os.date("%w", os.time(d)))
    local default_bg = (weekday == 0 or weekday == 6) and calendar_themes.weekend_day_bg or calendar_themes.bg
    local ret =
      wibox.widget {
      {
        {
          widget,
          halign = "center",
          widget = wibox.container.place
        },
        margins = (props.padding or 2) + (props.border_width or 0),
        widget = wibox.container.margin
      },
      shape = props.shape,
      shape_border_color = props.border_color or "#000000",
      shape_border_width = props.border_width or 0,
      fg = props.fg_color or calendar_themes.fg,
      bg = props.bg_color or default_bg,
      widget = wibox.container.background
    }

    return ret
  end

  local cal =
    wibox.widget {
    date = os.date("*t"),
    font = theme.font_base .. ' 14',
    fn_embed = decorate_cell,
    long_weekdays = true,
    widget = wibox.widget.calendar.month
  }

  local popup =
    awful.popup {
    ontop = true,
    visible = false,
    shape = gears.shape.rectangle,
    offset = {y = 5},
    widget = cal
  }

  function update_widget()
    popup:set_widget(
      wibox.widget {
        background(
          margin(
            place(
              wibox.widget.textclock(markup(theme.fg_normal, markup.font("FiraCode Bold 16", "%H:%M")))
            ),
          0, 0, 10, 10),
          calendar_themes.bg
        ),
        margin(cal, 10, 10),
        layout = wibox.layout.fixed.vertical
      }
    )
    awful.placement.bottom_right(popup, {margins = {bottom = 50, right = 0}, parent = awful.screen.focused()})
  end

  popup:buttons(
    awful.util.table.join(
      awful.button(
        {},
        4,
        function()
          local a = cal:get_date()
          a.month = a.month + 1
          cal:set_date(nil)
          cal:set_date(a)
          update_widget()
        end
      ),
      awful.button(
        {},
        5,
        function()
          local a = cal:get_date()
          a.month = a.month - 1
          cal:set_date(nil)
          cal:set_date(a)
          update_widget()
        end
      )
    )
  )

  update_widget()

  function calendar_widget.toggle()
    if popup.visible then
      -- to faster render the calendar refresh it and just hide
      cal:set_date(nil) -- the new date is not set without removing the old one
      cal:set_date(os.date("*t"))
      popup:set_widget(nil) -- just in case
      update_widget()
      popup.visible = not popup.visible
    else
      awful.placement.bottom_right(popup, {margins = {bottom = 50, right = 0}, parent = awful.screen.focused()})
      popup.visible = true
    end
  end

  return calendar_widget
end

return setmetatable(
  calendar_widget,
  {
    __call = function(_, ...)
      return worker(...)
    end
  }
)
