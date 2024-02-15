package = "lgi-async-extra"
version = "0.2.0-1"

source = {
    url = "git://github.com/sclu1034/lgi-async-extra.git",
    tag = "v0.2.0"
}

description = {
    summary = "An asynchronous high(er)-level API wrapper for LGI",
    homepage = "https://github.com/sclu1034/lgi-async-extra",
    license = "GPLv3"
}

dependencies = {
    "lua >= 5.1",
    "lgi",
    "async.lua"
}

build = {
    type = "builtin",
    modules = {
        ["lgi-async-extra.file"] = "src/lgi-async-extra/file.lua",
        ["lgi-async-extra.stream"] = "src/lgi-async-extra/stream.lua",
    },
    copy_directories = {
        "spec"
    }
}
