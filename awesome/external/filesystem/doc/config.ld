project = 'lgi-async-extra'
title = 'lgi-async-extra'
description = 'An asynchronous high(er)-level API wrapper for lua-lgi'
full_description = [[
The API is callback-based, so the use of [async.lua](https://github.com/sclu1034/async.lua) for composition is
recommended. All callbacks receive an `err` value as first argument, and any non-error return values
after that.
The `err` value will be `nil` on success, or an error value otherwise. In almost all cases
it will be an instance of `GLib.Error`:

    read_non_existent_file(function(err, data)
        print(err) -- or `print(err.message)`
        assert(err.domain == Gio.IOErrorEnum)
        -- Checking the error code against a constant is the recommended way,
        -- but a bit verbose, due to LGI's mapping.
        -- See https://github.com/pavouk/lgi/blob/master/docs/guide.md for explanation on this mapping.
        assert(err.code == Gio.IOErrorEnum[Gio.IOErrorEnum.NOT_FOUND])
    end)
]]

template = true

format = 'discount'

pretty = 'lua'
prettify_files = 'show'
backtick_references = false
wrap = true
no_space_before_args = true

custom_tags = {
    {
        "async",
        hidden = true,
    },
    {
        "since",
    }
}
