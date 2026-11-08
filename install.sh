#!/usr/bin/env bash
# links the kit into a beta 1.7.3 workspace: the skill into .claude/skills/modport and the tools into tools/modport
#   install.sh [workspace]    workspace defaults to the folder that holds this repo
set -euo pipefail

kit="$(cd "$(dirname "$0")" && pwd)"
workspace="$(cd "${1:-$kit/..}" && pwd)"

link()
{
    local target="$1" at="$2"
    mkdir -p "$(dirname "$at")"
    if [[ -e "$at" && ! -L "$at" ]]; then
        echo "$at exists and is not a link, move it away first" >&2
        exit 1
    fi
    ln -sfn "$(python3 -c 'import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$target" "$(dirname "$at")")" "$at"
    echo "$at -> $(readlink "$at")"
}

link "$kit/skills/modport" "$workspace/.claude/skills/modport"
link "$kit/tools" "$workspace/tools/modport"
mkdir -p "$workspace/ports"
B173_ROOT="$workspace" "$kit/tools/doctor.sh" || true
