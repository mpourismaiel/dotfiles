local assert = require("luassert")
local spy = require("luassert.spy")
local match = require("luassert.match")

local async = require("async")

describe('async.all', function()
    it('calls the final callback', function()
        local s = spy(function() end)

        async.wrap_sync(function(cb)
            async.all({},
                function(...)
                    s(...)
                    cb(...)
                end
            )
        end)

        assert.spy(s).was_called()
    end)

    it('calls all tasks', function()
        local task_1 = spy(function() end)
        local task_2 = spy(function() end)

        async.wrap_sync(function(cb)
            async.all({ task_1, task_2 }, cb)
        end)

        assert.spy(task_1).was_called()
        assert.spy(task_2).was_called()
    end)

    it('passes the error to final callback', function()
        local val = "error"
        local task_1 = spy(function(cb) cb(val) end)
        local task_2 = spy(function(cb) cb() end)

        local err = async.wrap_sync(function(cb)
            async.all({
                task_1,
                task_2,
            }, cb)
        end)

        assert.spy(task_1).was_called()
        -- Usually, this would have been called as well, but these callbacks all run synchronously.
        -- I can't change much about that until I pull in something that allows true asynchronous tasks.
        assert.spy(task_2).was_not_called()
        assert.is_same(val, err)
    end)
end)
