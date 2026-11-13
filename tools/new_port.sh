#!/usr/bin/env bash
# creates ports/<modid> from a mod jar: manifests, assets.toml recipe, git repo, Vineflower decompile, content inventory
#   new_port.sh <modid> <mod.jar> [display name] [more archives of the same mod...]
# the first archive is the one the assets.toml recipe pins, decompile.sh merges and remaps them all
set -euo pipefail

modid="${1:?modid}"
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
jar="$(absPath "${2:?mod jar}")"
name="${3:-$modid}"
port="$ports/$modid"

[[ -e "$port" ]] && fail "$port exists"
# ports inside a git work tree means a monorepo that already ignores build output
monorepo=false
[[ -d "$ports" ]] && git -C "$ports" rev-parse --is-inside-work-tree > /dev/null 2>&1 && monorepo=true
mkdir -p "$port/src" "$port/tools" "$port/reference/src"
cd "$port"

cat > Cargo.toml <<EOF
[package]
name = "$modid"
version = "0.1.0"
edition = "2024"
publish = false

[lib]
crate-type = ["cdylib"]

[dependencies]
b173_api = { path = "../../b1.7.3_rewrite/vendor/b1.7.3-modding-sdk/b173_api" }
serde = { version = "1", default-features = false, features = ["alloc", "derive"] }

[lints.rust]
non_snake_case = "allow"

[lints.clippy]
too_many_arguments = "allow"

[profile.release]
opt-level = "s"
lto = true
codegen-units = 1
panic = "abort"
strip = "debuginfo"

[workspace]
EOF

cat > mod.toml <<EOF
id = "$modid"
version = "0.1.0"
name = "$name"
description = "Port of $name to b1.7.3"
authors = ["original authors", "b173 port"]
license = "see the original mod, art built from the player's own download"
api = "1.0"
side = "both"

[network]
version = "1"

[depends]
loader = ">=0.1"
EOF

cat > src/lib.rs <<'EOF'
use b173_api::prelude::*;

#[mod_main]
fn register(_ctx: &mut RegisterCtx) -> Result<()>
{
    Ok(())
}
EOF

# a monorepo already ignores build output and reference/
$monorepo || printf 'target/\nreference/\nCargo.lock\n' > .gitignore
cat > rustfmt.toml <<'EOF'
edition = "2024"
unstable_features = true
max_width = 120
use_small_heuristics = "Max"
single_line_if_else_max_width = 50
tab_spaces = 4
newline_style = "Unix"
brace_style = "AlwaysNextLine"
control_brace_style = "AlwaysNextLine"
fn_single_line = true
where_single_line = true
empty_item_single_line = true
hex_literal_case = "Upper"
imports_granularity = "Module"
group_imports = "One"
use_field_init_shorthand = true
blank_lines_upper_bound = 1
EOF

cat > README.md <<EOF
# $name

Port of $name to the b1.7.3_rewrite mod loader. One \`.bmod\` runs on the client and the server.

## Assets

The textures, sounds and lang files belong to the original authors and are not in this repository or in the \`.bmod\`.
Put your own \`$(basename "$jar")\` in the game's \`mods/${modid}_assets/\` folder. On its next launch the client builds
the mod's art from it, following \`assets.toml\`.
EOF

cat > PORT_STATUS.md <<EOF
# $name port status

Source: $(basename "$jar") (\`reference/src\`, Vineflower decompile, never committed).
Target: b1.7.3_rewrite mod loader, one \`$modid-<version>.bmod\` for client and server.
Assets: \`assets.toml\` builds the art from \`mods/${modid}_assets/$(basename "$jar")\`, never committed or packed.

## Ledger

One row per block, item, entity, behavior (source class and method), event handler, recipe set, config option and
HUD element: what it is, the loader system it goes through, state (todo, built, proven how).

| Row | Source | Loader system | State |
|---|---|---|---|

## Beta differences

## Source bugs fixed

## Bugs

## Not checked
EOF

echo "== assets.toml"
runPython "$kitTools/recipe.py" "$jar" "$modid"

$monorepo || git init -q

"$kitTools/decompile.sh" "$port" "$jar" "${@:4}"
