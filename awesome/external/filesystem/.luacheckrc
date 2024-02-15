std = "max"

ignore = {
    "431",
    "432",
    "412"
}

files[".luacheckrc"].std = "+luacheckrc"
files["rocks/*.rockspec"].std = "+rockspec"

files["spec/*_spec.lua"].std = "+busted"
files["spec/*.lua"] = {
    globals = {
        "wrap_asserts",
        "run"
    }
}
