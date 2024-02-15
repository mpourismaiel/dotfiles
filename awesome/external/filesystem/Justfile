outdir := "out"
# Use 5.3 when available, otherwise fall back to what's installed as default version.
# This is primarily needed for Arch, where 5.4 is the default, which breaks LGI.
lua := `command -v lua5.3 2>/dev/null || command -v lua`

doc:
    @mkdir -p "{{outdir}}/doc" "{{outdir}}/src"
    @sh tools/process_docs.sh "{{outdir}}"
    ldoc --config=doc/config.ld --dir "{{outdir}}/doc" --project lgi-async-extra "{{outdir}}/src"
    sass doc/ldoc.scss "{{outdir}}/doc/ldoc.css"

test *ARGS:
    busted --config-file=.busted.lua --lua="{{lua}}" {{ARGS}} spec

check *ARGS:
    find src/ -iname '*.lua' | xargs luacheck {{ARGS}}

make version="scm-1":
    if {{lua}} -v | grep LuaJIT; then echo "Rocks for LuaJIT should be built with Lua 5.1 instead" >&2; exit 1; fi
    luarocks --lua-version "$({{lua}} -v 2>&1 | sed 's/Lua \(5\.[0-9]\).*/\1/')" --local make rocks/lgi-async-extra-{{version}}.rockspec

clean:
    rm -r "{{outdir}}"
