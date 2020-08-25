local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local lain = require("lain")
local clickable_container = require("widgets.clickable-container")
local markup = lain.util.markup

return function(widget, buttons, data, response)
  widget:reset()

  widget:add(
    wibox.container.background(
      wibox.container.place(
        wibox.container.constraint(
          wibox.container.margin(
            wibox.widget.textbox(markup.font(beautiful.font_base .. " Bold 12", "Available Networks")),
            20
          ),
          "exact",
          300,
          50
        ),
        "left",
        "center"
      ),
      "#050505"
    )
  )

  local more_menu, more_menu_container, more_menu_controller
  for i, network in ipairs(response.devices) do
    local cache = data[network]
    local signal, ssid, ssid_margin, connected, ssid_container, container
    if cache then
      signal = cache.signal
      ssid = cache.ssid
      ssid_container = cache.ssid_container
      connected = cache.connected
      container = cache.container
    else
      signal = wibox.widget.textbox()
      ssid = wibox.widget.textbox()
      connected = wibox.widget.textbox()
      ssid_container =
        clickable_container(
        wibox.container.place(
          wibox.container.constraint(
            wibox.widget {
              wibox.container.margin(
                {
                  wibox.container.margin(signal, 0, 15),
                  ssid,
                  layout = wibox.layout.fixed.horizontal
                },
                20
              ),
              nil,
              wibox.container.margin(connected, 0, 20),
              layout = wibox.layout.align.horizontal
            },
            "exact",
            300,
            50
          ),
          "left",
          "center"
        )
      )
      container = ssid_container

      data[network] = {
        signal,
        ssid = ssid,
        ssid_container = ssid_container,
        connected = connected,
        container = container
      }
    end

    local icon_string = ""
    if network.signal > 66 then
      icon_string = ""
    elseif network.signal > 33 then
      icon_string = ""
    end
    signal:set_markup(awful.util.theme_functions.icon_string({ icon = icon_string, font = "Font Awesome 5 Pro" }))
    ssid:set_markup(markup.font(beautiful.font_base .. " Bold 10", network.ssid))

    if network.inUse then
      connected:set_markup("Connected")
    else
      connected:set_markup("")
    end

    container:buttons(
      {
        awful.button(
          {},
          awful.button.names.LEFT,
          function()
            if network.inUse then
              awful.spawn("nmcli d wifi disconnect '" .. network.ssid .. "'")
            else
              awful.spawn("nmcli d wifi connect '" .. network.ssid .. "'")
            end
            widget.popup.visible = false
          end
        )
      }
    )

    if i < 7 then
      widget:add(container)
    -- elseif i < 15 then
    --   if more_menu == nil then
    --     more_menu =
    --       wibox.widget {
    --       layout = wibox.layout.fixed.vertical
    --     }

    --     more_menu_container =
    --       awful.popup {
    --       screen = awful.screen.focused(),
    --       visible = false,
    --       ontop = true,
    --       shape = gears.shape.rectangle,
    --       offset = {y = 5},
    --       widget = wibox.container.background(more_menu, "#ff0000")
    --     }
    --     more_menu_container:move_next_to(widget.popup)

    --     more_menu_controller =
    --       wibox.container.background(
    --       wibox.container.constraint(
    --         wibox.container.margin(
    --           wibox.widget.textbox(markup.font(beautiful.font_base .. " Bold 10", "More")),
    --           15,
    --           15,
    --           10,
    --           10
    --         ),
    --         "exact",
    --         300
    --       ),
    --       "#292929"
    --     )

    --     more_menu_controller:buttons(
    --       {
    --         awful.button(
    --           {},
    --           awful.button.names.LEFT,
    --           function()
    --             awful.placement.bottom_right(
    --               more_menu_container,
    --               {
    --                 margins = {
    --                   bottom = 50,
    --                   right = 400
    --                 },
    --                 parent = awful.screen.focused()
    --               }
    --             )
    --             more_menu_container.visible = not more_menu_container.visible
    --           end
    --         )
    --       }
    --     )

    --     widget:add(more_menu_controller)
    --   end

    --   more_menu:add(container)
    end
    if more_menu_container then
      more_menu_container.visible = false
    end
  end

  widget:add(
    wibox.container.background(
      wibox.container.place(
        wibox.container.constraint(
          wibox.container.margin(wibox.widget.textbox(markup.font(beautiful.font_base .. " Bold 12", "VPNs")), 20),
          "exact",
          300,
          50
        ),
        "left",
        "center"
      ),
      "#050505"
    )
  )

  for i, network in ipairs(response.vpns) do
    local cache = data[network]
    local name, name_margin, connected, name_container, container
    if cache then
      signal = cache.signal
      name = cache.name
      name_container = cache.name_container
      connected = cache.connected
      container = cache.container
    else
      name = wibox.widget.textbox()
      connected = wibox.widget.textbox()
      name_container =
        clickable_container(
        wibox.container.place(
          wibox.container.constraint(
            wibox.widget {
              wibox.container.margin(
                {
                  name,
                  layout = wibox.layout.fixed.horizontal
                },
                20
              ),
              nil,
              wibox.container.margin(connected, 0, 20),
              layout = wibox.layout.align.horizontal
            },
            "exact",
            300,
            50
          ),
          "left",
          "center"
        )
      )
      container = name_container

      data[network] = {
        name = name,
        name_container = name_container,
        connected = connected,
        container = container
      }
    end

    name:set_markup(markup.font(beautiful.font_base .. " Bold 10", network.name))

    if network.connected then
      connected:set_markup("Connected")
    else
      connected:set_markup("")
    end

    container:buttons(
      {
        awful.button(
          {},
          awful.button.names.LEFT,
          function()
            if network.connected then
              awful.spawn("nmcli con down '" .. network.name .. "'")
            else
              awful.spawn("nmcli con up '" .. network.name .. "'")
            end
            widget.popup.visible = false
          end
        )
      }
    )

    widget:add(container)
  end
end
