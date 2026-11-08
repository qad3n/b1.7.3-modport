#!/usr/bin/env bash
# drives a b1.7.3-rewrite server and client for mod testing with client assets from B173_CLIENT_ASSETS or the launcher
#   modtest.sh install <file.b173mod>...   copy mods into the test server and client mods folders
#   modtest.sh server                      start the test server, console commands come from cmd.txt
#   modtest.sh client [name]               start a client that joins the test server
#   modtest.sh cmd <console command>       send a console command and print the reply lines
#   modtest.sh shot <file.png>             screenshot of the game window only, taken by the client itself
#   modtest.sh log [server|client] [n]     last n lines of a log
#   modtest.sh stop                        stop the client and the server
#   modtest.sh reset                       stop and delete the test world
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
# the test game keeps its own data folder in the build output so tests never touch the player's worlds
export B173_HOME="$game/target/modtest"
clientDir="$B173_HOME"
serverDir="$B173_HOME/server"
port="${MODTEST_PORT:-25566}"
assets="${B173_ASSETS:-${B173_CLIENT_ASSETS:-$(launcherData)/assets}}"

mkdir -p "$serverDir/mods" "$clientDir/mods"

stopPid()
{
    local file="$1"
    if [[ -f "$file" ]]; then
        kill "$(cat "$file")" 2>/dev/null || true
        rm -f "$file"
    fi
}

case "${1:-}" in
    install)
        shift
        for mod in "$@"; do
            cp "$mod" "$serverDir/mods/"
            cp "$mod" "$clientDir/mods/"
        done
        ;;
    server)
        if [[ ! -f "$serverDir/server.properties" ]]; then
            printf 'level-name=world\nonline-mode=false\nlevel-seed=1234\nview-distance=6\nserver-port=%s\n' "$port" \
                > "$serverDir/server.properties"
        fi
        : > "$serverDir/cmd.txt"
        cd "$serverDir"
        # the tail pid is kept so stop works without pkill, which git bash lacks
        (tail -f cmd.txt & echo $! > tail.pid; wait) \
            | B173_ASSETS="$assets" nohup "$game/target/release/beta173_server$exe" > console.txt 2>&1 &
        echo $! > server.pid
        for _ in $(seq 60); do
            grep -q "Done (" console.txt 2>/dev/null && break
            sleep 1
        done
        tail -1 console.txt
        ;;
    client)
        name="${2:-Tester}"
        cd "$clientDir"
        B173_DEVSHOT=1 B173_ASSETS="$assets" nohup "$game/target/release/beta173$exe" "$name" - "127.0.0.1:$port" > console.txt 2>&1 &
        echo $! > client.pid
        for _ in $(seq 60); do
            grep -q "logged in" "$serverDir/console.txt" 2>/dev/null && break
            sleep 1
        done
        grep "logged in\|failed\|refused" "$serverDir/console.txt" | tail -1
        ;;
    cmd)
        shift
        before=$(wc -l < "$serverDir/console.txt")
        echo "$*" >> "$serverDir/cmd.txt"
        sleep "${MODTEST_WAIT:-2}"
        tail -n +"$((before + 1))" "$serverDir/console.txt" | grep -v "^\s*$" | awk '!seen[$0]++' | sed 's/^[0-9-]* [0-9:]* //'
        ;;
    shot)
        target="${2:-$B173_HOME/shots/shot.png}"
        rm -f "$clientDir/devshot.done"
        touch "$clientDir/devshot.request"
        for _ in $(seq 50); do
            [[ -f "$clientDir/devshot.done" ]] && break
            sleep 0.2
        done
        latest=$(ls -t "$clientDir/screenshots/"*.png 2>/dev/null | head -1)
        [[ -n "$latest" ]] && mkdir -p "$(dirname "$target")" && cp "$latest" "$target" && echo "$target"
        ;;
    log)
        side="${2:-server}"
        dir="$serverDir"
        [[ "$side" == client ]] && dir="$clientDir"
        tail -n "${3:-40}" "$dir/console.txt"
        ;;
    stop)
        stopPid "$clientDir/client.pid"
        if [[ -f "$serverDir/server.pid" ]]; then
            echo stop >> "$serverDir/cmd.txt"
            sleep 3
        fi
        stopPid "$serverDir/server.pid"
        stopPid "$serverDir/tail.pid"
        ;;
    reset)
        "$0" stop
        rm -rf "$serverDir/world"
        ;;
    *)
        sed -n '2,10p' "$0"
        exit 1
        ;;
esac
