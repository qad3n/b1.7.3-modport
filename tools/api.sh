#!/usr/bin/env bash
# compact b173 mod API index for porting, one line per item, read this instead of the SDK sources
#   api.sh                      every topic below
#   api.sh sdk [file]           pub signatures of b173_api, optionally one file (world, register, screen, terrain, ...)
#   api.sh spec [Struct]        fields of a mod_protocol::spec struct (EntitySpec, BlockSpec, ItemSpec, ...)
#   api.sh enum <Name>          variants of a mod_protocol::abi enum (HostCall, EntityField, EventKind, ModelOp, ...)
#   api.sh templates            block and entity template names
#   api.sh events               EventKind names
#   api.sh console              loader dev console usage
#   api.sh hooks                hook catalog names
set -euo pipefail

# workspace above this repo unless B173_ROOT is set
root="${B173_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
game="$root/b1.7.3-rewrite"
sdk="$game/vendor/b1.7.3-modding-sdk"
api="$sdk/b173_api/src"
protocol="$sdk/mod_protocol/src"
loader="$game/crates/modloader"

sdkIndex()
{
    local files=()
    cd "$api"
    if [[ -n "${1:-}" ]]; then
        mapfile -t files < <(find . -name "$1.rs" -o -path "./$1/*.rs")
    else
        mapfile -t files < <(find . -name '*.rs' ! -name vanilla.rs ! -name dispatch.rs ! -name rt.rs | sort)
    fi
    grep -HnE '^\s*(pub )?(fn|struct|enum|trait|type) |^\s*pub const [A-Z_]+: [A-Za-z]+ =|^impl|^pub use' "${files[@]}" \
        | sed -E 's|^\./||; s/[[:space:]]+/ /g; s/ ?\{.*$//; s/:([0-9]+): ?/:\1 /; s/ where .*$//' \
        | grep -vE '^[a-z_/]+\.rs:[0-9]+ fn [a-z]' \
        | grep -vE ' fn overridden\(' || true
}

enumVariants()
{
    awk -v name="$1" '$0 ~ "pub enum " name "( |$)" { on = 1; next } on && /^}/ { exit } on' "$protocol/abi.rs" "$protocol/spec.rs" \
        | grep -vE '^\s*//' | grep -oE '^    [A-Z][A-Za-z0-9]*( \{[^}]*\}?|\([^)]*\))?' | sed 's/^    //' | tr '\n' ' '
    echo
}

specFields()
{
    awk -v name="$1" '$0 ~ "pub struct " name "( |$)" { on = 1; print; next } on && /^}/ { exit } on && /pub / { gsub(/^ +/, "  "); print }' "$protocol/spec.rs"
}

templateNames()
{
    printf 'blocks: '
    awk '/BLOCK_TEMPLATES/ { on = 1 } on && /^\];/ { exit } on' "$loader/src/content/templates.rs" | grep -oE 'm_name: "[a-z_]+"' | cut -d'"' -f2 | tr '\n' ' '
    printf '\nentities: '
    awk '/ENTITY_TEMPLATES/ { on = 1 } on && /^\];/ { exit } on' "$loader/src/entities.rs" | grep -oE 'm_name: "[a-z_]+"' | cut -d'"' -f2 | tr '\n' ' '
    echo
}

case "${1:-all}" in
    sdk) sdkIndex "${2:-}" ;;
    spec)
        if [[ -n "${2:-}" ]]; then specFields "$2"; else grep -oE 'pub (struct|enum) [A-Za-z]+' "$protocol/spec.rs" | cut -d' ' -f3 | tr '\n' ' '; echo; fi
        ;;
    enum) enumVariants "${2:?enum name}" ;;
    templates) templateNames ;;
    events) enumVariants EventKind ;;
    console) grep -oE 'const USAGE: &str = "[^"]+"' "$loader/src/devtools.rs" | cut -d'"' -f2 | sed 's/ | /\n/g' ;;
    hooks) grep -E '^name = ' "$loader/hooks.toml" | cut -d'"' -f2 | tr '\n' ' '; echo ;;
    all)
        echo "== templates"; templateNames
        echo "== events"; enumVariants EventKind
        echo "== entity fields"; enumVariants EntityField
        echo "== console"; "$0" console
        echo "== spec structs"; "$0" spec
        echo "== sdk"; sdkIndex
        ;;
    *) sed -n '2,11p' "$0"; exit 1 ;;
esac
