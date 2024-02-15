local tostring = tostring
local ipairs = ipairs
local pairs = pairs
local table = table

local function remove_value(tbl, value)
  for index, _value in ipairs(tbl) do
    if _value == value then
      table.remove(tbl, index)
      break
    end
  end
end

local function generateTableDiff(oldObj, newObj, parentKey)
  local diff = {}

  for key, newValue in pairs(newObj) do
    local oldValue = oldObj[key]
    local currentKey = parentKey and (parentKey .. "." .. key) or key

    if type(newValue) == "table" and type(oldValue) == "table" then
      local nestedDiff = generateTableDiff(oldValue, newValue, currentKey)
      if next(nestedDiff) ~= nil then
        diff[key] = nestedDiff
      end
    elseif oldValue ~= newValue then
      diff[key] = newValue
    end
  end

  return diff
end

local function deepClone(original)
  local function copyTable(orig, copies)
    copies = copies or {}
    if orig == nil then
      return nil
    elseif type(orig) == "table" then
      if copies[orig] then
        return copies[orig]
      end
      local copy = {}
      copies[orig] = copy
      for origKey, origValue in pairs(orig) do
        copy[copyTable(origKey, copies)] = copyTable(origValue, copies)
      end
      return copy
    else
      return orig
    end
  end
  return copyTable(original)
end

return {
  generateTableDiff = generateTableDiff,
  deepClone = deepClone,
  remove_value = remove_value
}
