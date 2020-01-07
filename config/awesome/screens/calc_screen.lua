local awful = require("awful")
local naughty = require("naughty")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local markup = require("lain.util.markup")
local keygrabber = require("awful.keygrabber")
local createAnimObject = require("utils.animation").createAnimObject

local margin = wibox.container.margin
local place = wibox.container.place
local background = wibox.container.background
local text = wibox.widget.textbox
local font_small = beautiful.font_base .. " 20"
local font_large = beautiful.font_base .. " 28"
local input_bg = "#ffffff11"
local rounded_rect = function(cr, width, height)
  gears.shape.rounded_rect(cr, width, height, 8)
end

function widget_button(w, action)
  local bg_normal = beautiful.widget_bg .. "00"
  local bg_hover = input_bg

  w = background(w, bg_normal, rounded_rect)
  w:connect_signal(
    "mouse::enter",
    function()
      w.bg = bg_hover
    end
  )

  w:connect_signal(
    "mouse::leave",
    function()
      w.bg = bg_normal
    end
  )

  w:buttons(gears.table.join(awful.button({}, 1, action)))

  return w
end

local calc_screen =
  wibox {
  visible = false,
  screen = nil
}
local backdrop = wibox {type = "dock", x = 0, y = 0}
local calc_screen_grabber

function calc_screen_show()
  local s = awful.screen.focused()
  local screen_width = s.geometry.width
  local screen_height = s.geometry.height
  backdrop =
    wibox(
    {
      type = "dock",
      height = screen_height,
      width = screen_width,
      x = 0,
      y = 0,
      screen = s,
      ontop = true,
      visible = true,
      opacity = 0,
      bg = beautiful.wibar_bg .. "cc"
    }
  )
  calc_screen =
    wibox(
    {
      x = 0,
      y = -100,
      visible = true,
      opacity = 0,
      ontop = true,
      screen = s,
      type = "dock",
      height = screen_height,
      width = screen_width,
      bg = "#ffffff00"
    }
  )
  createAnimObject(0.6, calc_screen, {opacity = 1, y = 0}, "outCubic")
  createAnimObject(0.6, backdrop, {opacity = 1}, "outCubic")

  backdrop:buttons(
    gears.table.join(
      awful.button(
        {},
        1,
        function()
          calc_screen_hide()
        end
      )
    )
  )

  calc_screen_setup(s)
end

function calc_screen_hide()
  local s = awful.screen.focused()
  backdrop.visible = false
  calc_screen.visible = false
  awful.keygrabber.stop(calc_screen_grabber)
end

function input_markup(str)
  return markup("#ffffff", markup.font(font_large, str))
end

local input_value = ""
local modifier = ""
local prev_value = ""

function calc_screen_setup(s)
  local input = text(input_markup("0"))
  input.align = "right"

  function calculate()
    if modifier == "" then
      return
    end

    if modifier == "+" then
      prev_value = tostring(tonumber(prev_value) + tonumber(input_value))
    elseif modifier == "-" then
      prev_value = tostring(tonumber(prev_value) - tonumber(input_value))
    elseif modifier == "*" then
      prev_value = tostring(tonumber(prev_value) * tonumber(input_value))
    elseif modifier == "/" then
      prev_value = tostring(tonumber(prev_value) / tonumber(input_value))
    end

    input:set_markup(input_markup(prev_value))
  end

  function append_number(value)
    input_value = input_value .. value
    input:set_markup(input_markup(input_value))
  end

  function apply_modifier(key)
    if prev_value ~= "" then
      calculate()
      modifier = key
      input_value = ""
      return
    end

    prev_value = input_value
    modifier = key
    input_value = ""
  end

  input_value = ""
  modifier = ""
  prev_value = ""

  calc_screen_grabber =
    awful.keygrabber.run(
    function(_, key, event)
      if event ~= "release" and (key == "Escape" or key == "q" or key == "x") then
        calc_screen_hide()
        return
      end

      if event == "release" then
        return
      end

      for index, value in ipairs({"0", "1", "2", "3", "4", "5", "6", "7", "8", "9"}) do
        if value == key then
          append_number(value)
          return
        end
      end

      for index, value in ipairs({"+", "-", "/", "*"}) do
        if value == key then
          apply_modifier(value)
        end
      end

      if key == "=" then
        calculate()
        modifier = ""
        input_value = prev_value
      end

      if key == "Return" then
        calculate()
        awful.spawn.with_shell("echo " .. prev_value .. " | xclip -sel clip -i")
        calc_screen_hide()
      end
    end
  )

  function button(str, action)
    return widget_button(
      wibox.container.constraint(
        place(text(markup("#ffffff", markup.font(font_small, str))), "center", "center"),
        "exact",
        80,
        80
      ),
      action
    )
  end

  local widgets = {
    layout = wibox.layout.flex.vertical,
    {
      layout = wibox.layout.flex.horizontal,
      place(
        background(
          margin(
            wibox.widget {
              layout = wibox.layout.fixed.vertical,
              margin(background(margin(input, 20, 20, 10, 10), input_bg, rounded_rect), 0, 0, 0, 10),
              wibox.widget {
                button(
                  "7",
                  function()
                    append_number("7")
                  end
                ),
                button(
                  "8",
                  function()
                    append_number("8")
                  end
                ),
                button(
                  "9",
                  function()
                    append_number("9")
                  end
                ),
                button(
                  "/",
                  function()
                    apply_modifier("/")
                  end
                ),
                button(
                  "4",
                  function()
                    append_number("4")
                  end
                ),
                button(
                  "5",
                  function()
                    append_number("5")
                  end
                ),
                button(
                  "6",
                  function()
                    append_number("6")
                  end
                ),
                button(
                  "*",
                  function()
                    apply_modifier("*")
                  end
                ),
                button(
                  "1",
                  function()
                    append_number("1")
                  end
                ),
                button(
                  "2",
                  function()
                    append_number("2")
                  end
                ),
                button(
                  "3",
                  function()
                    append_number("3")
                  end
                ),
                button(
                  "-",
                  function()
                    apply_modifier("-")
                  end
                ),
                button(
                  "+/-",
                  function()
                    input_value = tonumber(input_value) * -1
                    input:set_markup(input_markup(input_value))
                  end
                ),
                button(
                  "0",
                  function()
                    append_number("0")
                  end
                ),
                button("=", calculate),
                button(
                  "+",
                  function()
                    apply_modifier("+")
                  end
                ),
                spacing = 5,
                forced_num_cols = 4,
                forced_num_rows = 4,
                homogeneous = true,
                expand = true,
                layout = wibox.layout.grid
              }
            },
            10,
            10,
            10,
            10
          ),
          beautiful.wibar_bg .. "aa",
          rounded_rect
        ),
        "center",
        "center"
      )
    }
  }

  calc_screen:setup(widgets)
end
