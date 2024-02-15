local lfs = require("lfs")
local gears = require("gears")
local awful = require("awful")

local icons = {mt = {}}

local function parse_file(file_name, file)
  if not file_name:match("%.desktop$") then
    return
  end

  local content = file:read("*a")
  file:close()

  local desktopEntry = {}
  for line in content:gmatch("[^\r\n]+") do
    local key, value = line:match("^([^=]+)=(.+)$")
    if key and value then
      desktopEntry[key] = value
    end
  end

  return {
    name = desktopEntry["Name"],
    icon = desktopEntry["Icon"],
    description = desktopEntry["Comment"],
    type = "Desktop",
    content = content
  }
end

local function new(screen)
  local desktop_path = os.getenv("HOME") .. "/Desktop"
  local files = {}
  for file_name in lfs.dir(desktop_path) do
    if file_name ~= "." and file_name ~= ".." then -- Check if it's a .desktop file
      local file, err = io.open(desktop_path .. "/" .. file_name, "r")
      if err then
        gears.debug.print_warning(err)
      elseif file then
        files[file_name] = parse_file(file_name, file)
      end
    end
  end
  return files
end

function icons.mt:__call(...)
  return new(...)
end

return setmetatable(icons, icons.mt)
