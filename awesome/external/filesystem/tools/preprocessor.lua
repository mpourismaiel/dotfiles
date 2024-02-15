local in_file = io.open(arg[1], "r")
local out_file = io.open(arg[2], "w+")

local function read_example(path)
    local f = io.open(string.format("./examples/%s.lua", path))
    local content = {"-- @usage"}

    for line in f:lines() do
        table.insert(content, string.format("--    %s", line))
    end

    return table.concat(content, "\n")
end

for line in in_file:lines() do
    local match = line:match("<%%EXAMPLE_(%w+)%%>")
    if match then
        line = read_example(match:gsub("_", "/"))
    end

    out_file:write(line .. "\n")
end

in_file:close()
out_file:close()
