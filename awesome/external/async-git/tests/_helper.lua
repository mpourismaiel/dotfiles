local assert = require("luassert")
local spy = require("luassert.spy")
local match = require("luassert.match")


local function match_dag_result(state, arguments)
    local key = arguments[1]
    local matcher = arguments[2]
    return function(results)
        if type(results) ~= "table" or type(results[key]) ~= "table" then
            return false
        end

        return matcher(table.unpack(results[key]))
    end
end

assert:register("matcher", "dag_result", match_dag_result)
