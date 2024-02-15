local assert = require("luassert")
local spy = require("luassert.spy")
local match = require("luassert.match")

local async = require("async")

describe('async.dag', function()
    it('calls the final callback', function()
        local s = spy(function() end)
        async.wrap_sync(function(cb)
            async.dag({}, function(...)
                s(...)
                cb(...)
            end)
        end)
        assert.spy(s).was_called_with(match.is_nil(), match.is_table())
    end)

    it('runs a task', function()
        local task = spy(function(_, cb) cb() end)
        async.wrap_sync(function(cb)
            async.dag({ task = {task} }, cb)
        end)
        assert.spy(task).was_called()
    end)

    it('runs concurrent tasks', function()
        local task_1 = spy(function(_, cb) cb() end)
        local task_2 = spy(function(_, cb) cb() end)

        async.wrap_sync(function(cb)
            async.dag({
                task_1 = {task_1},
                task_2 = {task_2},
            }, cb)
        end)

        assert.spy(task_1).was_called()
        assert.spy(task_2).was_called()
    end)

    it('resolves linear dependencies', function()
        local val = "value"
        local task_1 = spy(function(_, cb) cb(nil, val) end)
        local task_2 = spy(function(_, cb)
            assert.spy(task_1).was_called()
            cb()
        end)
        local task_3 = spy(function(_, cb)
            assert.spy(task_2).was_called()
            cb()
        end)

        async.wrap_sync(function(cb)
            async.dag({
                task_1 = {task_1},
                task_2 = {"task_1", task_2},
                task_3 = {"task_2", task_3},
            }, cb)
        end)

        assert.spy(task_1).was_called_with(match.is_table(), match.is_function())
        assert.spy(task_2).was_called_with(match.dag_result("task_1", match.is_equal(val)), match.is_function())
        assert.spy(task_3).was_called_with(match.is_table(), match.is_function())
    end)

    it('skips to final callback on error', function()
        local val = "error"
        local task_1 = spy(function(_, cb) cb(val) end)
        local task_2 = spy(function(_, cb) cb() end)

        local err = async.wrap_sync(function(cb)
            async.dag({
                task_1 = {task_1},
                task_2 = {"task_1", task_2},
            }, cb)
        end)

        assert.spy(task_1).was_called()
        assert.spy(task_2).was_not_called()
        assert.is_same(val, err)
    end)

    -- TODO: Figure out a way to test the race condition in `_run_queue`
end)
