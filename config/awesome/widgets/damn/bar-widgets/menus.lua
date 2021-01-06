local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local lain = require("lain")
local system_info = require("widgets.damn.system-info")
local createAnimObject = require("utils.animation").createAnimObject
require "logging.file"
local logger = logging.file("/tmp/log.log")

local textbox = wibox.widget.textbox
local constraint = wibox.container.constraint
local margin = wibox.container.margin
local place = wibox.container.place
local background = wibox.container.background
local layout = wibox.layout
local markup = lain.util.markup
local action_icon = awful.util.theme_functions.colored_icon("#ffffff")

local function create_button(w, action, color, hover_color)
  local bg_normal = color and color or awful.util.theme.widget_bg .. (hover_color and "ee" or "00")
  local bg_hover = (hover_color and awful.util.theme.widget_bg .. "ff" or awful.util.theme.widget_bg .. "ff")

  w = background(w, bg_normal)
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

  if type(action) == "function" then
    w:buttons({awful.button({}, 1, action)})
  end

  return w
end

local menus = {mt = {}}

function menus.menu(items, width, height, has_margin)
  has_margin = has_margin == nil and true or false
  local widget = wibox.widget.base.make_widget_from_value(items)
  return {
    widget = margin(
      background(
        constraint(widget, "exact", width, height),
        "#1f1f1f",
        function(cr, w, h)
          return gears.shape.rounded_rect(cr, w, h, 5)
        end
      ),
      has_margin and 10 or 0
    ),
    updatable_widget = widget
  }
end

function menus.new()
  local menu = {}
  menu.backdrop =
    wibox {
    x = 0,
    y = 0,
    visible = false,
    bg = "#00000000",
    ontop = true
  }
  menu.backdrop2 =
    wibox {
    x = 0,
    y = 0,
    visible = false,
    bg = "#00000000",
    ontop = true
  }

  menu.display =
    wibox {
    x = 10,
    y = 0,
    opacity = 0,
    visible = false,
    bg = "#00000000",
    ontop = true
  }

  local user_image = wibox.widget.imagebox(os.getenv("HOME") .. "/.cache/user.jpg", true, gears.shape.circle)
  user_image.forced_width = 100
  user_image.forced_height = 100

  local system_info_without_partitions = {
    layout = layout.flex.horizontal,
    system_info(
      markup("#ffffff", markup.font("Roboto Regular 10", "CPU")),
      lain.widget.cpu(
        {
          settings = function()
            widget:set_markup(markup("#ffffff", markup.font("Roboto Light 11", cpu_now.usage .. "%")))
          end
        }
      )
    ),
    system_info(
      markup("#ffffff", markup.font("Roboto Regular 10", "RAM")),
      lain.widget.mem(
        {
          timeout = 1,
          settings = function()
            widget:set_markup(markup("#ffffff", markup.font("Roboto Light 11", mem_now.perc .. "%")))
          end
        }
      )
    )
  }

  local system_info_menu = menus.menu(system_info_without_partitions, 400, 70)

  local partitions = {}
  for i, s in ipairs {
    {partition = "sdb3", name = "/", widget = root_used},
    {partition = "sdb4", name = "/home", widget = home_used},
    {partition = "sda2", name = "/Games", widget = games_used}
  } do
    awful.widget.watch(
      string.format('bash -c "df -hl | grep \'%s\' | awk \'{print $5}\'"', s.partition),
      120,
      function(_, stdout)
        partitions[i] =
          system_info(
          markup("#ffffff", markup.font("Roboto Regular 10", s.name)),
          textbox(markup("#ffffff", markup.font("Roboto Light 11", string.gsub(stdout, "^%s*(.-)%s*$", "%1"))))
        )
        local items = gears.table.join(system_info_without_partitions, partitions)
        system_info_menu.updatable_widget:reset()
        system_info_menu.updatable_widget:setup(items)
      end
    )
  end

  local power =
    constraint(
    place(action_icon({icon = "", size = 14, font_weight = "light", font = "Font Awesome 5 Pro"})),
    "exact",
    50,
    50
  )
  power:buttons(
    awful.util.table.join(
      awful.button(
        {},
        1,
        function()
          exit_screen_show(false)
        end
      )
    )
  )

  local stripe1 =
    menus.menu(
    {
      layout = layout.flex.vertical,
      textbox(),
      place(
        {
          layout = layout.fixed.vertical,
          constraint(
            place(action_icon({icon = "", size = 14, font_weight = "light", font = "Font Awesome 5 Pro"})),
            "exact",
            50,
            50
          ),
          power
        },
        "center",
        "bottom"
      )
    },
    50,
    500,
    false
  ).widget

  local stripe2 =
    wibox.widget {
    layout = layout.fixed.vertical,
    menus.menu(
      {
        layout = layout.fixed.horizontal,
        place(margin(user_image, 20, 20), "left", "center"),
        {
          layout = layout.fixed.vertical,
          margin(
            textbox(
              markup("#ffffff", markup.font("Roboto Bold 24", "Hello, " .. os.getenv("USER"):gsub("^%l", string.upper)))
            ),
            0,
            0,
            20
          ),
          wibox.widget.textclock(
            markup(awful.util.theme.fg_normal, markup.font("Roboto Light 12", "Today is %A, %b %d, %Y"))
          )
        }
      },
      400,
      140
    ).widget,
    margin(system_info_menu.widget, 0, 0, 10),
    margin(
      menus.menu(
        {
          layout = layout.flex.vertical,
          place(
            textbox(
              markup(awful.util.theme.fg_normal, markup.font("Roboto Light 14", "You haven't added any projects"))
            )
          )
        },
        400,
        270
      ).widget,
      0,
      0,
      10
    )
  }

  local stripes = {
    margin(stripe1, 0, 0, 0, 10),
    margin(stripe2, 0, 0, 0, 10)
  }

  menu.display:setup {
    layout = layout.fixed.horizontal,
    wibox.widget(
      gears.table.crush(
        {
          layout = layout.fixed.horizontal
        },
        stripes
      )
    )
  }

  local function show_backdrop(s, screen_width, screen_height)
    menu.backdrop.screen = s
    menu.backdrop.width = screen_width
    menu.backdrop.height = screen_height - 50
    menu.backdrop.visible = true
    menu.backdrop2.screen = s
    menu.backdrop2.width = screen_width
    menu.backdrop2.height = screen_height - 560
    menu.backdrop2.visible = true
  end

  local function show_display(s, screen_width, screen_height)
    menu.display.screen = s
    menu.display.width = screen_width
    menu.display.height = 500
    menu.display.y = screen_height - 550
    menu.display.visible = true
    createAnimObject(1, menu.display, {opacity = 1}, "outCubic")
    -- for i, stripe in ipairs(stripes) do
    --   createAnimObject(0.5, stripe, { bottom = 10 }, "outCubic", 0.5 + i / 2)
    -- end
  end

  local function hide_everything()
    gears.timer {
      autostart = true,
      single_shot = true,
      timeout = #stripes / 2 - 1,
      callback = function()
        menu.display.visible = false
        menu.backdrop.visible = false
        menu.backdrop2.visible = false
      end
    }
    -- for i, stripe in ipairs(stripes) do
    --   createAnimObject(0.5, stripe, { bottom = 0 }, "outCubic", i / 2)
    -- end
  end

  menu.backdrop:buttons({awful.button({}, 1, hide_everything)})
  menu.display:buttons({awful.button({}, 1, hide_everything)})

  menu.widget =
    create_button(
    constraint(
      place(
        awful.util.theme_functions.colored_icon(awful.util.theme.fg_normal)(
          {
            icon = "",
            size = 12,
            font = "Font Awesome 5 Pro"
          }
        )
      ),
      "exact",
      50,
      50
    ),
    function()
      local screen = awful.screen.focused()
      local screen_width = screen.geometry.width
      local screen_height = screen.geometry.height
      show_backdrop(screen, screen_width, screen_height)
      show_display(screen, screen_width, screen_height)
    end,
    "#1f1f1f"
  )

  return menu.widget
end

function menus.mt:__call(...)
  return menus.new(...)
end

return setmetatable(menus, menus.mt)
