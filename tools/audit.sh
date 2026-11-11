#!/usr/bin/env bash
# lists code in a port that bypasses the loader's name, tag, state and registry systems
#   audit.sh <port folder>      one block per rule with file:line hits, exit 1 when anything is found
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

[[ $# -eq 1 ]] || fail "usage: audit.sh <port folder>"
src="$(absPath "$1")/src"
[[ -d "$src" ]] || fail "no src folder in $1"

found=0

# rule name, then an extended regex matched against every Rust line, air checks against 0 are fine
rules=(
    "numeric id lookups, use world.is, blockIs or ItemRef::is"
    'resolve\(RegistryKind::(Block|Item)|Blocks\.id\(|Items\.get\([^)]*\)[^;]*\.id\(\)|\b(block|item)Id\(|ids::(block|item)\('
    "comparisons against numeric block ids, use world.is or world.tagged"
    '\.block\([^)]*\) *(==|!=) *[1-9a-zA-Z]|(==|!=) *Some\((block|id|here|below|above)\)|(==|!=) *[a-z]*\.block\('
    "metadata bits, register named states and use StateData"
    '\b(meta|metadata)[A-Za-z]* *(&|\||>>|<<) *(0x)?[0-9]+|setMeta\(|\.meta\(\)'
    "blocks placed by number, use world.place or world.setBlockState"
    'setBlock(Quiet)?\(|swapBlock\('
    "numeric items, use ItemRef::Named"
    'ItemRef::Numeric\([^_)]|ItemStack::of\([0-9]'
    "vanilla textures by sheet slot, use minecraft:block/<sprite> or minecraft:item/<sprite>"
    'minecraft:(terrain|items)/[0-9{]'
    "lists of vanilla names, use or add a tag"
    '^\s*"minecraft:[a-z_/]+",?\s*$|\[\s*"minecraft:[a-z_/]+",\s*"minecraft:'
)

for ((i = 0; i < ${#rules[@]}; i += 2)); do
    hits="$(grep -rnE --include='*.rs' "${rules[i + 1]}" "$src" | sed "s|^$src/||" || true)"
    [[ -n "$hits" ]] || continue

    found=1
    echo "== ${rules[i]} ($(wc -l <<< "$hits"))"
    echo "$hits"
done

ids="$(find "$src" -name ids.rs | sed "s|^$src/||")"
if [[ -n "$ids" ]]; then
    found=1
    echo "== private id cache, the SDK caches names and tags per content epoch"
    echo "$ids"
fi

if ((found == 0)); then
    echo "clean"
fi

exit "$found"
