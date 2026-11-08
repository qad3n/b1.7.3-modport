#!/usr/bin/env bash
# links the kit into a beta 1.7.3 workspace: the skill into .claude/skills/modport and the tools into tools/modport
#   install.sh [workspace] [--copy]    workspace defaults to the folder that holds this repo, --copy copies instead of linking
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/tools/common.sh"

kit="$(cd "$(dirname "$0")" && pwd)"
workspace="$kit/.."
copy=false
for arg in "$@"; do
    case "$arg" in
        --copy) copy=true ;;
        *) workspace="$arg" ;;
    esac
done
workspace="$(cd "$workspace" && pwd)"

isLink()
{
    [[ -L "$1" ]] || { $windows && [[ -d "$1" ]] && fsutil reparsepoint query "$(cygpath -w "$1")" > /dev/null 2>&1; }
}

# a relative symlink on linux and macos, a junction on windows where symlinks need developer mode
link()
{
    local target="$1" at="$2"
    mkdir -p "$(dirname "$at")"
    if [[ -e "$at" ]] && ! isLink "$at" && ! $copy; then
        fail "$at exists and is not a link, move it away first"
    fi
    if $copy; then
        rm -rf "$at"
        cp -R "$target" "$at"
        echo "$at copied"
    elif $windows; then
        [[ -e "$at" ]] && cmd //c rmdir "$(cygpath -w "$at")" > /dev/null
        cmd //c mklink //J "$(cygpath -w "$at")" "$(cygpath -w "$target")" > /dev/null || fail "junction failed, rerun with --copy"
        echo "$at -> $target"
    else
        ln -sfn "$(runPython -c 'import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$target" "$(dirname "$at")")" "$at"
        echo "$at -> $(readlink "$at")"
    fi
}

link "$kit/skills/modport" "$workspace/.claude/skills/modport"
link "$kit/tools" "$workspace/tools/modport"
mkdir -p "$workspace/ports"
B173_ROOT="$workspace" "$kit/tools/doctor.sh" || true
