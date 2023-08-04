---@diagnostic disable: missing-fields

-------------------------------------------
-- @author https://github.com/Kasper24
-- @copyright 2021-2022 Kasper24
-------------------------------------------
local wibox = require("wibox")
local gears = require("gears")
local config = require("lib.config")
local theme = require("lib.config.theme")
local wtext = require("lib.widgets.text")
local wbutton = require("lib.widgets.button")
local setmetatable = setmetatable
local os = os

local calendar = {
  mt = {}
}

local function day_name_widget(name)
  return wibox.widget {
    widget = wibox.container.constraint,
    strategy = "exact",
    width = config.dpi(35),
    height = config.dpi(35),
    {
      widget = wibox.container.place,
      halign = "center",
      {
        widget = wtext,
        font_size = config.dpi(10),
        bold = true,
        color = theme.fg_normal,
        text = name
      }
    }
  }
end

local function date_widget(self, index)
  local text =
    wibox.widget {
    widget = wtext,
    font_size = config.dpi(10)
  }

  local widget =
    wibox.widget {
    widget = wibox.container.constraint,
    strategy = "exact",
    width = config.dpi(35),
    height = config.dpi(35),
    {
      widget = wbutton,
      id = "background_role",
      paddings = 0,
      shape = gears.shape.circle,
      {
        widget = wibox.container.place,
        halign = "center",
        valign = "center",
        text
      }
    }
  }
  widget.bg_role = widget:get_children_by_id("background_role")[1]

  self:connect_signal(
    index .. "::updated",
    function(self, date, is_current, month_difference)
      text:set_text(date)

      if is_current == true then
        -- today
        widget.bg_role.bg_normal = theme.bg_primary
        widget.bg_role.callback = nil
        text:set_foreground(theme.fg_primary)
      elseif month_difference ~= 0 then
        widget.bg_role.bg_normal = theme.bg_normal
        widget.bg_role.callback = function()
          self:change_month(month_difference)
        end
        text:set_foreground(theme.fg_inactive)
      else
        -- this month
        widget.bg_role.bg_normal = theme.bg_normal
        widget.bg_role.callback = nil
        text:set_foreground(theme.fg_primary)
      end
    end
  )

  return widget
end

function calendar:set_date(date)
  self._private.date = date

  local first_day =
    os.date(
    "*t",
    os.time {
      year = date.year,
      month = date.month,
      day = 1
    }
  )
  local last_day =
    os.date(
    "*t",
    os.time {
      year = date.year,
      month = date.month + 1,
      day = 0
    }
  )
  local month_days = last_day.day

  local time =
    os.time {
    year = date.year,
    month = date.month,
    day = 1
  }
  self:get_children_by_id("current_month_button")[1]:set_label(os.date("%B", time))
  self:get_children_by_id("current_year_button")[1]:set_label(os.date("%Y", time))

  local index = 1
  local days_to_add_at_month_start = first_day.wday - 1
  local days_to_add_at_month_end = 42 - last_day.day - days_to_add_at_month_start

  local previous_month_last_day =
    os.date(
    "*t",
    os.time {
      year = date.year,
      month = date.month,
      day = 0
    }
  ).day
  for day = previous_month_last_day - days_to_add_at_month_start, previous_month_last_day - 1, 1 do
    self:emit_signal(index .. "::updated", day, false, -1)
    index = index + 1
  end

  local current_date = os.date("*t")
  for day = 1, month_days do
    local is_current = day == current_date.day and date.month == current_date.month and date.year == current_date.year
    self:emit_signal(index .. "::updated", day, is_current, 0)
    index = index + 1
  end

  for day = 1, days_to_add_at_month_end do
    self:emit_signal(index .. "::updated", day, false, 1)
    index = index + 1
  end
end

function calendar:set_date_current()
  self:set_date(os.date("*t"))
end

function calendar:set_month_current()
  local date = os.date("*t")
  self:set_date(
    {
      year = self._private.date.year,
      month = date.month,
      day = self._private.date.day
    }
  )
end

function calendar:set_year_current()
  local date = os.date("*t")
  self:set_date(
    {
      year = date.year,
      month = self._private.date.month,
      day = self._private.date.day
    }
  )
end

function calendar:change_year(increment)
  local new_calendar_year = self._private.date.year + increment
  self:set_date(
    {
      year = new_calendar_year,
      month = self._private.date.month,
      day = self._private.date.day
    }
  )
end

function calendar:change_month(increment)
  local new_calendar_month = self._private.date.month + increment
  self:set_date(
    {
      year = self._private.date.year,
      month = new_calendar_month,
      day = self._private.date.day
    }
  )
end

local function new()
  local widget = nil

  widget =
    wibox.widget {
    layout = wibox.layout.fixed.vertical,
    spacing = config.dpi(15),
    {
      layout = wibox.layout.align.horizontal,
      forced_height = config.dpi(36),
      {
        layout = wibox.layout.align.horizontal,
        {
          widget = wibox.container.constraint,
          strategy = "exact",
          width = config.dpi(36),
          {
            widget = wbutton,
            bg_normal = theme.bg_normal,
            bg_hover = theme.bg_primary,
            paddings = 0,
            callback = function()
              widget:change_month(-1)
            end,
            {
              widget = wtext,
              font_size = config.dpi(10),
              text = "&lt;"
            }
          }
        },
        {
          widget = wibox.container.constraint,
          strategy = "exact",
          width = config.dpi(85),
          {
            widget = wbutton,
            paddings = 0,
            bg_normal = theme.bg_normal,
            bg_hover = theme.bg_primary,
            id = "current_month_button",
            callback = function()
              widget:set_month_current()
            end,
            {
              widget = wtext,
              font_size = config.dpi(10),
              text = os.date("%B")
            }
          }
        },
        {
          widget = wibox.container.constraint,
          strategy = "exact",
          width = config.dpi(36),
          {
            widget = wbutton,
            paddings = 0,
            bg_normal = theme.bg_normal,
            bg_hover = theme.bg_primary,
            callback = function()
              widget:change_month(1)
            end,
            {
              widget = wtext,
              font_size = config.dpi(10),
              text = ">"
            }
          }
        }
      },
      nil,
      {
        layout = wibox.layout.align.horizontal,
        {
          widget = wibox.container.constraint,
          strategy = "exact",
          width = config.dpi(36),
          {
            widget = wbutton,
            paddings = 0,
            bg_normal = theme.bg_normal,
            bg_hover = theme.bg_primary,
            callback = function()
              widget:change_year(-1)
            end,
            {
              widget = wtext,
              font_size = config.dpi(10),
              text = "&lt;"
            }
          }
        },
        {
          widget = wibox.container.constraint,
          strategy = "exact",
          width = config.dpi(50),
          {
            widget = wbutton,
            paddings = 0,
            bg_normal = theme.bg_normal,
            bg_hover = theme.bg_primary,
            id = "current_year_button",
            callback = function()
              widget:set_year_current()
            end,
            {
              widget = wtext,
              font_size = config.dpi(10),
              text = os.date("%Y")
            }
          }
        },
        {
          widget = wibox.container.constraint,
          strategy = "exact",
          width = config.dpi(36),
          {
            widget = wbutton,
            paddings = 0,
            bg_normal = theme.bg_normal,
            bg_hover = theme.bg_primary,
            callback = function()
              widget:change_year(1)
            end,
            {
              widget = wtext,
              font_size = config.dpi(10),
              text = ">"
            }
          }
        }
      }
    },
    {
      layout = wibox.layout.grid,
      id = "days",
      forced_num_rows = 6,
      forced_num_cols = 7,
      spacing = config.dpi(4),
      expand = true,
      day_name_widget("Su"),
      day_name_widget("Mo"),
      day_name_widget("Tu"),
      day_name_widget("We"),
      day_name_widget("Th"),
      day_name_widget("Fr"),
      day_name_widget("Sa")
    }
  }

  gears.table.crush(widget, calendar, true)

  for day = 1, 42 do
    widget:get_children_by_id("days")[1]:add(date_widget(widget, day))
  end
  widget:set_date_current()

  return widget
end

function calendar.mt:__call(...)
  return new()
end

return setmetatable(calendar, calendar.mt)
