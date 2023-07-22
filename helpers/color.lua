local function hex2rgba(color)
  if not color then
    return nil
  end

  if type(color) == "table" then
    return color
  end

  local hex = color:gsub("#", "")
  local r = tonumber("0x" .. hex:sub(1, 2))
  local g = tonumber("0x" .. hex:sub(3, 4))
  local b = tonumber("0x" .. hex:sub(5, 6))
  local a = 1
  if #hex == 8 then
    a = tonumber("0x" .. hex:sub(7, 8)) / 255
  end
  return {r, g, b, a}
end

local function rgba2hex(color)
  local hex = "#"
  for i = 1, 3 do
    hex = hex .. string.format("%02x", math.floor(color[i]))
  end
  if color[4] then
    hex = hex .. string.format("%02x", math.floor(color[4] * 255))
  else
    hex = hex .. "ff"
  end
  return hex
end

return {
  hex2rgba = hex2rgba,
  rgba2hex = rgba2hex
}
