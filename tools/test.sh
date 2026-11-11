#!/usr/bin/env bash
# port test cycle on top of modtest.sh, which owns the one shared test server and client
#   test.sh deploy <port dir> [--game] [--force]   build the port, stop the test server, install the port alone, start it
#                                                  --game rebuilds the game binaries and cargo-b173 first (after loader or SDK changes)
#                                                  --force takes over a test server that is already running
#   test.sh errors [n]                             last n panic, trap, error and refusal lines of the test server and client
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
modtest="$kitTools/modtest.sh"
# the test game keeps its own data folder in the build output so tests never touch the player's worlds, MODTEST_HOME
# and MODTEST_PORT give a parallel session its own server
export B173_HOME="${MODTEST_HOME:-$game/target/modtest}"
clientDir="$B173_HOME"
serverDir="$B173_HOME/server"

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
            *) port="$(absPath "$arg")" ;;
        esac
    done
    [[ -n "$port" ]] || { sed -n '3,5p' "$0"; exit 1; }
    if running && ! $force; then
        fail "test server already running, another session may be using it; ask the user, then pass --force"
    fi
    if $buildGame; then
        (cd "$game" && cargo build --release --bin beta173 --bin beta173_server)
        (cd "$sdk" && cargo build --release -p mod_tool)
    fi
    cargoB173 build --path "$port"
    local mod
    mod=$(ls -t "$port"/target/*.bmod | head -1)
    "$modtest" stop
    rm -f "$serverDir/mods/"*.bmod "$clientDir/mods/"*.bmod
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
