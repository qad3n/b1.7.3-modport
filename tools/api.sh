#!/usr/bin/env bash
# compact b173 mod API index for porting, one line per item, read this instead of the SDK sources
#   api.sh                      every topic below
#   api.sh sdk [file]           pub signatures of b173_api, optionally one file (world, register, screen, terrain, ...)
#   api.sh spec [Struct]        fields of a mod_protocol::spec struct (EntitySpec, BlockSpec, ItemSpec, ...)
#   api.sh enum <Name>          variants of a mod_protocol enum (EntityField, EventKind, ModelOp, WorldRequest, ...)
#   api.sh find <word>          SDK signatures and protocol variants naming the word, the fastest way to an API
#   api.sh templates            block and entity template names
#   api.sh events               EventKind names
#   api.sh console              loader dev console usage
#   api.sh hooks                hook catalog names
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
api="$sdk/b173_api/src"
protocol="$sdk/mod_protocol/src"
loader="$game/crates/modloader"

sdkIndex()
{
    cd "$api"
    if [[ -n "${1:-}" ]]; then
        find . -name "$1.rs" -o -path "./$1/*.rs"
    else
        find . -name '*.rs' ! -name vanilla.rs ! -name dispatch.rs ! -name rt.rs | sort
    fi | tr '\n' '\0' | xargs -0 grep -HnE '^[[:space:]]*(pub )?(fn|struct|enum|trait|type) |^[[:space:]]*pub const [A-Z_]+: [A-Za-z]+ =|^impl|^pub use' \
        | sed -E 's|^\./||; s/[[:space:]]+/ /g; s/ ?\{.*$//; s/:([0-9]+): ?/:\1 /; s/ where .*$//' \
        | grep -vE '^[a-z_/]+\.rs:[0-9]+ fn [a-z]' \
        | grep -vE ' fn overridden\(' || true
}

# every protocol source, the abi is one file in old SDKs and a folder of files since API 2.0
protocolFiles()
{
    find "$protocol" -name '*.rs' | sort
}

enumVariants()
{
    if [[ "$1" == HostCall ]]; then
        printf 'HostCall is one enum per group, ask for a group: '
        protocolFiles | tr '\n' '\0' | xargs -0 grep -ohE '^pub enum [A-Za-z]+Request' | cut -d' ' -f3 | tr '\n' ' '
        echo
        return
    fi
    protocolFiles | tr '\n' '\0' | xargs -0 awk -v name="$1" 'FNR == 1 { on = 0 } $0 ~ "pub enum " name "( |$)" { on = 1; next } on && /^}/ { on = 0 } on' \
        | grep -vE '^[[:space:]]*//' | grep -oE '^    [A-Z][A-Za-z0-9]*( \{[^}]*\}?|\([^)]*\))?' | sed 's/^    //' | tr '\n' ' '
    echo
}

specFields()
{
    protocolFiles | tr '\n' '\0' | xargs -0 awk -v name="$1" 'FNR == 1 { on = 0 } $0 ~ "pub struct " name "( |$)" { on = 1; print; next } on && /^}/ { on = 0 } on && /pub / { gsub(/^ +/, "  "); print }'
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
    find)
        word="${2:?word}"
        sdkIndex | grep -i -- "$word" || true
        protocolFiles | tr '\n' '\0' | xargs -0 grep -hiE "^    (pub )?[A-Za-z_]*$word" | sed 's/^ */protocol: /' | cut -c1-200 | sort -u || true
        ;;
    all)
        echo "== templates"; templateNames
        echo "== events"; enumVariants EventKind
        echo "== entity fields"; enumVariants EntityField
        echo "== console"; "$0" console
        echo "== spec structs"; "$0" spec
        echo "== sdk"; sdkIndex
        ;;
    *) sed -n '2,12p' "$0"; exit 1 ;;
esac
