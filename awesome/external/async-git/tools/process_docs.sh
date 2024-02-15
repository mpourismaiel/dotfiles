#!/bin/sh

OUT="$1"
if [ -z "$OUT" ] || [ ! -d "$OUT" ]; then
    echo "No such directory: '$OUT'" >&2
    exit 1
fi

LUA=${LUA:-lua}

# Print the command to run similarly to how Just would do it.
run() {
    printf "\e[1;97m"
    echo "$@"
    printf "\e[0m"
    "$@"
}

find src -iname '*.lua' -not -path '*/internal/*' | while read -r f; do
    mkdir -p "$(dirname "$OUT/$f")"
    run "$LUA" ./tools/preprocessor.lua "$f" "$OUT/$f"
done
