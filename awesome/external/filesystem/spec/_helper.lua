local lgi = require("lgi")
local GLib = lgi.GLib

local DEFAULT_TIMEOUT = 2000

-- Runs a test function inside a GLib loop, to drive asynchronous operations.
-- Busted itself cannot currently do this.
function run(timeout, fn)
    if type(timeout) == "function" then
        fn = timeout
        timeout = DEFAULT_TIMEOUT
    else
        timeout = timeout or DEFAULT_TIMEOUT
    end

    return function()
        local loop = GLib.MainLoop()
        local err

        GLib.idle_add(GLib.PRIORITY_DEFAULT, function()
            fn(function(e)
                err = e
                loop:quit()
            end)
        end)

        GLib.timeout_add(GLib.PRIORITY_DEFAULT, timeout, function()
            err = string.format("Test did not finish within %d seconds. Check for GLib/LGI messages", timeout / 1000)
            loop:quit()
        end)

        loop:run()

        if err then
            error(err)
        end
    end
end


-- Wraps a functions with `assert`s to relay errors to a callback.
-- For convenience, the `err` parameter can be used to shortcurcuit on a caller error.
--
-- The `run` helper can then catch the error and print it.
function wrap_asserts(cb, err, fn)
    if type(err) == "function" then
        fn = err
        err = nil
    end

    if err then
        return cb(err)
    end

    local ok, err = pcall(fn)
    if ok then
        cb(nil)
    else
        local msg = err.message or tostring(err)
        cb(debug.traceback(msg .. "\n", 2))
    end
end
