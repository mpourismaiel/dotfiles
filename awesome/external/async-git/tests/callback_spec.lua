local assert = require("luassert")
local spy = require("luassert.spy")
local match = require("luassert.match")

local async = require("async")

describe('async.callback', function()
    local s

    before_each(function()
        s = spy(function() end)
    end)

    it('calls the wrapped function', function()
        local cb = async.callback(nil, s)
        assert.spy(s).was_not_called()

        cb()
        assert.spy(s).was_called(1)

        cb()
        assert.spy(s).was_called(2)
    end)

    it('passes arguments from the definition', function()
        local val_1 = "val_1"
        local val_2 = "val_2"
        local cb = async.callback(nil, s, val_1, val_2)

        cb()
        assert.spy(s).was_called_with(match.is_same(val_1), match.is_same(val_2))
    end)

    it('passes arguments from the call', function()
        local val_1 = "val_1"
        local val_2 = "val_2"
        local cb = async.callback(nil, s)

        cb(val_1)
        assert.spy(s).was_called_with(match.is_same(val_1))

        cb(val_1, val_2)
        assert.spy(s).was_called_with(match.is_same(val_1), match.is_same(val_2))
    end)

    it('passes all arguments in order', function()
        local val_1 = "val_1"
        local val_2 = "val_2"
        local val_3 = "val_3"
        local val_4 = "val_4"
        local cb = async.callback(nil, s, val_1, val_3)

        cb(val_2, val_4)
        assert.spy(s).was_called_with(
            match.is_same(val_1),
            match.is_same(val_3),
            match.is_same(val_2),
            match.is_same(val_4)
        )
    end)
end)
