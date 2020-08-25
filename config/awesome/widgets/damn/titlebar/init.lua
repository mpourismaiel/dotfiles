local awful = require('awful')
local wibox = require('wibox')
local gears = require('gears')
local titlebar_buttons = require("widgets/damn/titlebar/buttons")

local my_table = awful.util.table or gears.table
local margin = wibox.container.margin

local function titlebar(c)
  local titlebar_widget =
    awful.titlebar(
    c,
    {
      size = 50,
      position = "top",
      buttons = my_table.join(
        awful.button(
          {},
          1,
          function()
            client.focus = c
            c:raise()
            awful.mouse.client.move(c)
          end
        ),
        awful.button(
          {},
          3,
          function()
            client.focus = c
            c:raise()
            awful.mouse.client.resize(c)
          end
        )
      )
    }
  )

  titlebar_widget:setup {
    margin(awful.titlebar.widget.titlewidget(c), 16, 12, 5, 5),
    nil,
    {
      margin(titlebar_buttons.minimize(c), 5, 5, 5, 5),
      margin(titlebar_buttons.maximize(c), 5, 5, 5, 5),
      margin(titlebar_buttons.exit(c), 5, 15, 5, 5),
      layout = wibox.layout.fixed.horizontal
    },
    layout = wibox.layout.align.horizontal
  }
end

return titlebar
