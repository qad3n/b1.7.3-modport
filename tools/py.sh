#!/usr/bin/env bash
# runs a kit python tool with whichever python 3 the platform has
#   py.sh <recipe.py|convert_models.py> [args]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

tool="${1:?tool name}"
shift
runPython "$kitTools/$tool" "$@"
