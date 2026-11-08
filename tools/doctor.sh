#!/usr/bin/env bash
# checks a workspace for everything the kit needs and prints the command that fixes each gap
#   doctor.sh
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

missing=0

check()
{
    local label="$1" test="$2" fix="$3"
    if eval "$test" > /dev/null 2>&1; then
        echo "ok       $label"
    else
        echo "missing  $label: $fix"
        missing=$((missing + 1))
    fi
}

javaMajor()
{
    java -version 2>&1 | head -1 | sed -E 's/.*version "([0-9]+).*/\1/'
}

echo "workspace $root"
check "b1.7.3-rewrite" "[[ -f '$game/Cargo.toml' ]]" "git clone --recurse-submodules https://github.com/qad3n/b1.7.3-rust-rewrite.git '$game'"
check "modding SDK submodule" "[[ -f '$sdk/b173_api/Cargo.toml' ]]" "git -C '$game' submodule update --init --recursive"
check "cargo" "command -v cargo" "install Rust from https://rustup.rs"
check "wasm32 target" "rustup target list --installed | grep -q wasm32-unknown-unknown" "rustup target add wasm32-unknown-unknown"
check "nightly rustfmt" "cargo +nightly fmt --version" "rustup toolchain install nightly --component rustfmt"
check "cargo-b173" "command -v cargo-b173 || [[ -x '$sdk/target/release/cargo-b173' ]]" "(cd '$sdk' && cargo build --release -p mod_tool)"
check "game binaries" "[[ -x '$game/target/release/beta173' && -x '$game/target/release/beta173_server' ]]" "(cd '$game' && cargo build --release)"
check "game assets" "[[ -n \"\$(ls -A '$game/assets' | grep -v README.md)\" ]]" "see $game/assets/README.md"
check "java 17+" "(( \$(javaMajor) >= 17 ))" "install a JDK 17 or newer"
check "python 3" "command -v python3" "install Python 3"
check "curl and unzip" "command -v curl && command -v unzip" "install curl and unzip"
check "skill installed" "[[ -f '$root/.claude/skills/modport/SKILL.md' ]]" "$kitTools/../install.sh"
check "ports folder" "[[ -d '$ports' ]]" "mkdir -p '$ports'"

if [[ -f "$root/b1.7.3_decomp/tools/bin/vineflower-$VINEFLOWER_VERSION.jar" || -n "${VINEFLOWER:-}" ]]; then
    echo "ok       Vineflower"
else
    echo "info     Vineflower $VINEFLOWER_VERSION downloads from Maven Central on the first new_port.sh"
fi

(( missing == 0 )) && echo "ready" || { echo "$missing missing"; exit 1; }
