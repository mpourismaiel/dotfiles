local assert = require("luassert")
local spy = require("luassert.spy")
local match = require("luassert.match")

local async = require("async")

describe('async.do_while', function()
    it('calls the final callback', function()
        local s_final = spy(function() end)
        local s_iteratee = spy(function(cb) cb() end)
        local s_test = spy(function(cb) cb(nil, false) end)

        async.wrap_sync(function(cb)
            async.do_while(
                s_iteratee,
                s_test,
                function(...)
                    s_final(...)
                    cb(...)
                end
            )
        end)

        assert.spy(s_final).was_called()
        assert.spy(s_iteratee).was_called_with(match.is_function())
        assert.spy(s_test).was_called_with(match.is_function())
    end)

    it('passes iteratee result to test function', function()
        local val = "value"
        local s_iteratee = spy(function(cb) cb(nil, val) end)
        local s_test = spy(function(_, cb) cb(nil, false) end)

        async.wrap_sync(function(cb)
            async.do_while(
                s_iteratee,
                s_test,
                function(...)
                    cb(...)
                end
            )
        end)

        assert.spy(s_test).was_called_with(match.is_same(val), match.is_function())
    end)

    it('passes the last result of iteratee', function()
        local val = "value"
        local s_final = spy(function() end)
        local s_iteratee = spy(function(cb) cb(nil, val) end)

        async.wrap_sync(function(cb)
            async.do_while(
                s_iteratee,
                function(_, cb) cb(nil, false) end,
                function(...)
                    s_final(...)
                    cb(...)
                end
            )
        end)

        assert.spy(s_final).was_called_with(match.is_nil(), match.is_same(val))
    end)

    it('passes the error from the iterator callback', function()
        local err = "error"
        local s_final = spy(function() end)
        local s_iteratee = spy(function(cb) cb(err) end)
        local s_test = spy(function(cb) cb(nil, false) end)

        async.wrap_sync(function(cb)
            async.do_while(
                s_iteratee,
                s_test,
                function(...)
                    s_final(...)
                    cb(...)
                end
            )
        end)

        assert.spy(s_test).was_not_called()
        assert.spy(s_final).was_called_with(match.is_same(err))
    end)

    it('passes the error from the test callback', function()
        local err = "error"
        local s_final = spy(function() end)
        local s_iteratee = spy(function(cb) cb() end)
        local s_test = spy(function(cb) cb(err) end)

        async.wrap_sync(function(cb)
            async.do_while(
                s_iteratee,
                s_test,
                function(...)
                    s_final(...)
                    cb(...)
                end
            )
        end)

        -- The iteratee should have been called first and not be affected
        assert.spy(s_iteratee).was_called()
        assert.spy(s_final).was_called_with(match.is_same(err))
    end)

    it('calls the iterator until the test fails', function()
        local count = 1
        local max = 5

        local s_final = spy(function() end)
        local s_iteratee = spy(function(cb)
            -- Iteration should have been stopped before that
            assert.is_not_equal(max, count)
            count = count + 1
            cb(nil, count)
        end)
        local s_test = spy(function(count, cb)
            cb(nil, count < max)
        end)

        async.wrap_sync(function(cb)
            async.do_while(
                s_iteratee,
                s_test,
                function(...)
                    s_final(...)
                    cb(...)
                end
            )
        end)

        assert.is_equal(max, count)
        assert.spy(s_iteratee).was_called(max - 1)
        assert.spy(s_test).was_called(max - 1)
        assert.spy(s_final).was_called(1)
        assert.spy(s_final).was_called_with(match.is_nil(), match.is_equal(count))
    end)
end)
