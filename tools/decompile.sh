#!/usr/bin/env bash
# decompiles one or more mod archives into a port's reference/src and writes its inventory
#   decompile.sh <port folder> <jar or zip>...
# several archives are merged first (a mod shipped as core plus addons). A ModLoader era archive holds obfuscated
# beta names: it is remapped to MCP names when the workspace has the beta mappings, tiny-remapper and the client jar
# (B173_MAPPINGS, TINY_REMAPPER, B173_CLIENT_JAR or their b1.7.3_decomp and b1.7.3_files places), since no handler
# or registration can be read from one letter names
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

[[ $# -ge 2 ]] || { sed -n '2,7p' "$0"; exit 1; }
port="$(absPath "$1")"
shift
java="${JAVA:-java}"
vineflower="$(vineflowerJar)"
work="$port/reference/work"
rm -rf "$work" "$port/reference/src"
mkdir -p "$work/merged" "$port/reference/src"

for archive in "$@"; do
    unzipTo "$(absPath "$archive")" "$work/merged"
done
merged="$work/merged.jar"
(cd "$work/merged" && runPython -c 'import shutil, sys; shutil.make_archive(sys.argv[1], "zip", ".")' "$work/merged") && mv "$work/merged.zip" "$merged"

input="$merged"
if compgen -G "$work/merged/mod_*.class" > /dev/null; then
    mappings="${B173_MAPPINGS:-$root/b1.7.3_decomp/mappings/b1.7.3-client.tiny}"
    remapper="${TINY_REMAPPER:-$(ls "$root"/b1.7.3_decomp/tools/bin/tiny-remapper-*-fat.jar 2> /dev/null | head -1)}"
    client="${B173_CLIENT_JAR:-$root/b1.7.3_files/minecraft-b1.7.3-client.jar}"
    if [[ -f "$mappings" && -f "$remapper" && -f "$client" ]]; then
        echo "== remapping beta names to MCP"
        "$java" -jar "$remapper" "$merged" "$work/named.jar" "$mappings" client named "$client" --fixpackageaccess 2>&1 \
            | grep -v '^\[INFO\]' || true
        [[ -f "$work/named.jar" ]] || fail "remap failed"
        input="$work/named.jar"
    else
        echo "warning: ModLoader era archive left obfuscated, set B173_MAPPINGS, TINY_REMAPPER and B173_CLIENT_JAR" >&2
    fi
fi

echo "== decompiling"
"$java" -jar "$vineflower" --indent-string="    " --log-level=warn "$input" "$port/reference/src" > "$port/reference/vineflower.log" 2>&1 \
    || fail "vineflower failed, see $port/reference/vineflower.log"
# vineflower writes a jar when given a jar, unpack it so grep and the converters see sources
for out in "$port"/reference/src/*.jar; do
    [[ -f "$out" ]] || continue
    unzipTo "$out" "$port/reference/src" && rm "$out"
done
rm -rf "$work"

echo "== inventory"
"$kitTools/inventory.sh" "$port/reference/src" > "$port/reference/inventory.txt"
grep "^==" "$port/reference/inventory.txt" || true
echo "full list: $port/reference/inventory.txt"
