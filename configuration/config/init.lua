local awful = require("awful")
local gears = require("gears")
local filesystem = require("gears.filesystem")
local xresources = require("beautiful.xresources")

local config_dir = filesystem.get_configuration_dir()
local images_dir = filesystem.get_configuration_dir() .. "/images"

local config = {
  terminal = "xfce4-terminal",
  taskManager = "system-monitoring-center",
  modkey = "Mod4",
  dpi = xresources.apply_dpi,
  wallpaper = os.getenv("HOME") .. "/Pictures/wallpaper.jpg",
  images_dir = images_dir,
  auto_start = {
    debug_mode = false,
    apps = {
      -- Compositor
      "picom -b --experimental-backends --dbus --config " .. config_dir .. "/configuration/picom.conf",
      -- Polkit and keyring
      "/usr/bin/lxqt-policykit-agent &" .. " eval $(gnome-keyring-daemon -s --components=pkcs11,secrets,ssh,gpg)",
      -- Load X colors
      "xrdb $HOME/.Xresources",
      -- Audio equalizer
      "pulseeffects --gapplication-service",
      -- Lockscreen timer
      [[
      xidlehook --not-when-fullscreen --not-when-audio --timer 600 \
      "awesome-client 'awesome.emit_signal(\"module::lockscreen:show\")'" ""
      ]]
    }
  },
  commands = {
    rofi_appmenu = "bash " .. config_dir .. "configuration/rofi/launcher.sh " .. config_dir .. "configuration/rofi",
    full_screenshot = "flameshot full -p /home/mahdi/Pictures/Screenshots/ -c",
    area_screenshot = "flameshot gui",
    bluetooth = "blueman-manager"
  },
  tags = {
    {
      name = "1",
      layout = awful.layout.suit.max
    },
    {
      name = "2",
      layout = awful.layout.suit.max
    },
    {
      name = "3",
      layout = awful.layout.suit.tile
    },
    {
      name = "4",
      layout = awful.layout.suit.max
    },
    {
      name = "5",
      layout = awful.layout.suit.max
    },
    {
      name = "6",
      layout = awful.layout.suit.max
    }
  }
}

config.auto_start_extra = config_dir .. "/config/autostart"

function file_exists(file)
  local f = io.open(file, "rb")
  if f then
    f:close()
  end
  return f ~= nil
end

function lines_from(file)
  if not file_exists(file) then
    return {}
  end
  local lines = {}
  for line in io.lines(file) do
    if string.sub(line, 1, 1) ~= "#" then
      lines[#lines + 1] = line
    end
  end
  return lines
end

if config.initialized ~= true then
  if file_exists(config.auto_start_extra) then
    local lines = lines_from(config.auto_start_extra)
    config.auto_start.apps = gears.table.join(config.auto_start.apps, lines)
  end

  config.initialized = true
end

if file_exists(config_dir .. "/config/configuration.json") then
  -- read config_dir .. "/config/configuration.json" and load the json as config_override_table
  local json = require("json")
  local f = io.open(config_dir .. "/config/configuration.json", "rb")
  local content = f:read("*all")
  f:close()
  local config_override_table = json.decode(content)
  -- iterate over the table and override config
  for k, v in pairs(config_override_table) do
    -- if the key is a table, iterate over it and override the config
    if type(v) == "table" then
      -- if the key is not present in config, create it
      if config[k] == nil then
        config[k] = {}
      end

      for k2, v2 in pairs(v) do
        config[k][k2] = v2
      end
    else
      config[k] = v
    end
  end
end

return config
