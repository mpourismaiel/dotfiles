package = "async.lua"
version = "0.2.0-1"

source = {
    url = "git+https://github.com/sclu1034/async.lua.git",
    tag = "v0.2.0"
}

description = {
    summary = "Utilities for callback-style asynchronous Lua",
    homepage = "https://github.com/sclu1034/async.lua",
    license = "GPLv3"
}

dependencies = {
    "lua >= 5.1"
}

build = {
    type = "builtin",
    modules = {
        async = "src/async/async.lua",
        ["async.internal.util"] = "src/async/internal/util.lua"
    },
    copy_directories = {
        "doc", "examples", "tests"
    }
}
