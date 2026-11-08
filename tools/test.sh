#!/usr/bin/env bash
# port test cycle on top of tools/rewrite/modtest.sh, which owns the one shared test server and client
#   test.sh deploy <port dir> [--game] [--force]   build the port, stop the test server, install the port alone, start it
#                                                  --game rebuilds the game binaries and cargo-b173 first (after loader or SDK changes)
#                                                  --force takes over a test server that is already running
#   test.sh errors [n]                             last n panic, trap, error and refusal lines of the test server and client
set -euo pipefail

# workspace above this repo unless B173_ROOT is set
root="${B173_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
game="$root/b1.7.3-rewrite"
modtest="$root/tools/rewrite/modtest.sh"
serverDir="$game/run/modtest-server"
clientDir="$game/run/modtest-client"

running()
{
    [[ -f "$serverDir/server.pid" ]] && kill -0 "$(cat "$serverDir/server.pid")" 2>/dev/null
}

deploy()
{
    local port="" buildGame=false force=false
    for arg in "$@"; do
        case "$arg" in
            --game) buildGame=true ;;
            --force) force=true ;;
            *) port="$(realpath "$arg")" ;;
        esac
    done
    [[ -n "$port" ]] || { sed -n '3,5p' "$0"; exit 1; }
    if running && ! $force; then
        echo "test server already running, another session may be using it; ask the user, then pass --force" >&2
        exit 1
    fi
    if $buildGame; then
        (cd "$game" && cargo build --release --bin beta173 --bin beta173_server)
        (cd "$game/vendor/b1.7.3-modding-sdk" && cargo build --release -p mod_tool)
    fi
    "$game/vendor/b1.7.3-modding-sdk/target/release/cargo-b173" b173 build --path "$port"
    local mod
    mod=$(ls -t "$port"/target/*.b173mod | head -1)
    "$modtest" stop
    rm -f "$serverDir/mods/"*.b173mod "$clientDir/mods/"*.b173mod
    "$modtest" install "$mod"
    "$modtest" server
}

errors()
{
    for dir in "$serverDir" "$clientDir"; do
        [[ -f "$dir/console.txt" ]] || continue
        echo "== $(basename "$dir")"
        grep -iE "panic|trap|error|exception|failed|refused" "$dir/console.txt" | tail -n "${1:-20}" || true
    done
}

case "${1:-}" in
    deploy) shift; deploy "$@" ;;
    errors) errors "${2:-}" ;;
    *) sed -n '2,6p' "$0"; exit 1 ;;
esac
