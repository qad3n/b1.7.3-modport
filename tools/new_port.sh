#!/usr/bin/env bash
# creates ports/<modid> from a mod jar: manifests, git repo, Vineflower decompile in reference/src, content inventory
#   new_port.sh <modid> <mod.jar> [display name]
set -euo pipefail

modid="${1:?modid}"
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
jar="$(absPath "${2:?mod jar}")"
name="${3:-$modid}"
port="$ports/$modid"
vineflower="$(vineflowerJar)"
java="${JAVA:-java}"

[[ -e "$port" ]] && fail "$port exists"
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
b173_api = { path = "../../b1.7.3-rewrite/vendor/b1.7.3-modding-sdk/b173_api" }
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
license = "see the original mod, assets extracted from the user's jar"
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

printf 'target/\nassets/\nreference/\nCargo.lock\n' > .gitignore
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

cat > PORT_STATUS.md <<EOF
# $name port status

Source: $(basename "$jar") (\`reference/src\`, Vineflower decompile, never committed).
Target: b1.7.3-rewrite mod loader, one \`$modid-<version>.b173mod\` for client and server.
Assets: never committed, \`../../tools/modport/py.sh extract_assets.py <jar> $modid\` fills \`assets/$modid\`.

## Inventory

## Done

## Bugs to check at the end

## Todo, in order
EOF

git init -q

echo "== decompiling"
"$java" -jar "$vineflower" --indent-string="    " --log-level=warn "$jar" reference/src > reference/vineflower.log 2>&1 \
    || { echo "vineflower failed, see reference/vineflower.log" >&2; exit 1; }
# vineflower writes a jar when given a jar, unpack it so grep and the converters see sources
for out in reference/src/*.jar; do
    [[ -f "$out" ]] || continue
    unzipTo "$out" reference/src && rm "$out"
done

echo "== inventory"
"$kitTools/inventory.sh" reference/src > reference/inventory.txt
grep "^==" reference/inventory.txt
echo "full list: $port/reference/inventory.txt"
