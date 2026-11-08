# shared paths and helpers, sourced by every kit script
# shellcheck shell=bash

kitTools="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# workspace above this repo unless B173_ROOT is set
root="${B173_ROOT:-$(cd "$kitTools/../.." && pwd)}"
game="$root/b1.7.3_rewrite"
sdk="$game/vendor/b1.7.3-modding-sdk"
ports="$root/ports"

# windows runs the kit in git bash, where native binaries carry .exe
case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*) windows=true; exe=".exe" ;;
    *) windows=false; exe="" ;;
esac

readonly VINEFLOWER_VERSION="1.12.0"
readonly VINEFLOWER_SHA256="1dfcfe974395734fa467ce620661c7623d05ba83670de0529b1fbd63ff548b9d"
readonly VINEFLOWER_URL="https://repo1.maven.org/maven2/org/vineflower/vineflower/$VINEFLOWER_VERSION/vineflower-$VINEFLOWER_VERSION.jar"

fail()
{
    echo "$*" >&2
    exit 1
}

absPath()
{
    local path="$1"
    [[ -e "$path" ]] || fail "no such file: $path"
    if [[ -d "$path" ]]; then
        (cd "$path" && pwd)
    else
        echo "$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
    fi
}

sha256()
{
    if command -v sha256sum > /dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# VINEFLOWER, then the decompile pipeline's copy, then a verified download into the user cache
vineflowerJar()
{
    local local="$root/b1.7.3_decomp/tools/bin/vineflower-$VINEFLOWER_VERSION.jar"
    local cached="${XDG_CACHE_HOME:-$HOME/.cache}/b173-modport/vineflower-$VINEFLOWER_VERSION.jar"
    if [[ -n "${VINEFLOWER:-}" ]]; then echo "$VINEFLOWER"; return; fi
    if [[ -f "$local" ]]; then echo "$local"; return; fi
    if [[ ! -f "$cached" ]]; then
        mkdir -p "$(dirname "$cached")"
        echo "downloading Vineflower $VINEFLOWER_VERSION from Maven Central" >&2
        curl -fsSL "$VINEFLOWER_URL" -o "$cached.part" || fail "Vineflower download failed, set VINEFLOWER to a local jar"
        [[ "$(sha256 "$cached.part")" == "$VINEFLOWER_SHA256" ]] || { rm -f "$cached.part"; fail "Vineflower checksum mismatch"; }
        mv "$cached.part" "$cached"
    fi
    echo "$cached"
}

# python 3 by any platform name except the windows store stub
runPython()
{
    local candidate
    for candidate in python3 python py; do
        if command -v "$candidate" > /dev/null && "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 8))' 2> /dev/null; then
            "$candidate" -I "$@"
            return
        fi
    done
    fail "python 3.8 or newer not found"
}

# the launcher's data folder, as the rewrite launcher picks it per platform
launcherData()
{
    if $windows; then
        echo "$(cygpath -u "$APPDATA")/beta173"
    elif [[ "$(uname -s)" == Darwin ]]; then
        echo "$HOME/Library/Application Support/beta173"
    else
        echo "${XDG_DATA_HOME:-$HOME/.local/share}/beta173"
    fi
}

unzipTo()
{
    runPython -m zipfile -e "$1" "$2"
}

# cargo-b173 from PATH, else the SDK build, building it on first use
cargoB173()
{
    if command -v cargo-b173 > /dev/null; then
        cargo-b173 b173 "$@"
        return
    fi
    local built="$sdk/target/release/cargo-b173$exe"
    [[ -x "$built" ]] || (cd "$sdk" && cargo build --release -p mod_tool) || fail "cargo-b173 build failed"
    "$built" b173 "$@"
}
