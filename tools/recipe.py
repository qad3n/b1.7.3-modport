"""Write a port's assets.toml, the recipe the loader follows to build the mod's art from the player's own download.

Mod assets belong to their authors: they never go in the port's assets/ or its .bmod. The player drops the original
download in mods/<modid>_assets/ and the client converts it with this recipe. Run from the port folder:
    ../../tools/modport/py.sh recipe.py <mod.jar> <modid> [--source <jar namespace>] [--url <download page>]
        [--sheet <sheet path in jar> <names.txt> <to folder>]...
The download is pinned by name and sha256. Folders whose files are all lower case are copied whole, others file by
file with lower case targets. Old-style grid sheets become [[slice]] steps, names.txt lines being `<slot> <name> [span]`
counted left to right and top to bottom, a span above 1 a [[compose]] of span x span tiles.
Port specific steps go in the port's own tools/recipe.py, which calls this one and appends them.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import struct
import zipfile
from collections import Counter
from pathlib import Path

# jar texture folders across versions -> port folders, anything else keeps its path
FOLDERS = [
    ("textures/blocks/", "textures/block/"),
    ("textures/block/", "textures/block/"),
    ("textures/items/", "textures/item/"),
    ("textures/item/", "textures/item/"),
    ("textures/entities/", "textures/entity/"),
    ("textures/entity/", "textures/entity/"),
    ("textures/models/armor/", "textures/armor/"),
    ("textures/tile_entities/", "textures/tile/"),
]
COPIED = (".png", ".ogg", ".wav", ".mcmeta")
LANG_FILES = ("lang/en_US.lang", "lang/en_us.lang", "lang/en_us.json")
LEGACY_NAME = re.compile(r"^(tile|item|entity)\.(?:[a-z0-9_]+[.:])?([a-z0-9_.]+)\.name$")
MODERN_NAME = re.compile(r"^(block|item|entity)\.([a-z0-9_]+)\.[a-z0-9_.]+$")
MODERN_KIND = {"block": "tile", "item": "item", "entity": "entity"}
# png width sits right after the signature and the IHDR length and tag
PNG_WIDTH = struct.Struct(">I")
PNG_WIDTH_OFFSET = 16
GRID = 16


def quote(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def sourceNamespace(names: list[str]) -> str | None:
    counts = Counter(name.split("/")[1] for name in names if name.startswith("assets/") and name.count("/") > 2)
    counts.pop("minecraft", None)
    return counts.most_common(1)[0][0] if counts else None


def target(rest: str) -> str:
    for source, mapped in FOLDERS:
        if rest.startswith(source):
            return mapped + rest[len(source):]
    return rest


# mapped folder a file sits in, else its second level folder, or the file itself when it sits higher
def group(rest: str) -> str:
    for source, _ in FOLDERS:
        if rest.startswith(source):
            return source.rstrip("/")
    parts = rest.split("/")
    return "/".join(parts[:2]) if len(parts) > 2 else rest


def copies(names: list[str], prefix: str) -> list[str]:
    files = [name[len(prefix):] for name in names if name.startswith(prefix) and name.endswith(COPIED)]
    folders = {}
    for rest in files:
        folders.setdefault(group(rest), []).append(rest)
    lines = []
    for folder, members in sorted(folders.items()):
        others = [name[len(prefix):] for name in names if name.startswith(f"{prefix}{folder}/") and not name.endswith("/")]
        whole = all(rest == rest.lower() for rest in members) and len(others) == len(members) and folder not in members
        if whole:
            lines += ["[[copy]]", f"from = {quote(f'{prefix}{folder}/')}", f"to = {quote(target(folder + '/'))}", ""]
            continue
        for rest in sorted(members):
            lines += ["[[copy]]", f"from = {quote(prefix + rest)}", f"to = {quote(target(rest).lower())}", ""]
    return lines


def langKeys(jar: zipfile.ZipFile, path: str) -> list[str]:
    text = jar.read(path).decode("utf-8")
    if path.endswith(".json"):
        return list(json.loads(text))
    return [line.split("=", 1)[0].strip() for line in text.splitlines() if "=" in line and not line.startswith("#")]


# first matching rule wins, so exact legacy keys come first and the modid prefix catches the rest
def lang(jar: zipfile.ZipFile, names: list[str], prefix: str, modid: str) -> list[str]:
    path = next((prefix + file for file in LANG_FILES if prefix + file in names), None)
    if path is None:
        return []
    keys = langKeys(jar, path)
    lines = ["[[lang]]", f"from = {quote(path)}", "rules = ["]
    modern = []
    for key in keys:
        legacy = LEGACY_NAME.match(key)
        if not legacy:
            match = MODERN_NAME.match(key)
            if match and match.group(1, 2) not in modern:
                modern.append(match.group(1, 2))
            continue
        if any(other != key and other.startswith(key) for other in keys):
            raise SystemExit(f"{key} is a prefix of another key, an exact rule would catch both")
        lines.append(f"    {{ from = {quote(key)}, to = {quote(f'{legacy[1]}.{modid}.{legacy[2]}.name')} }},")
    for kind, namespace in modern:
        mapped = f"{MODERN_KIND[kind]}.{modid}."
        lines.append(f"    {{ from = {quote(f'{kind}.{namespace}.')}, to = {quote(mapped)}, add = \".name\" }},")
    lines.append(f"    {{ from = \"\", to = {quote(modid + '.')} }},")
    return lines + ["]", ""]


def sheetNames(path: Path) -> list[tuple[int, str, int]]:
    found = []
    for number, line in enumerate(path.read_text().splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) not in (2, 3):
            raise SystemExit(f"{path}:{number}: expected <slot> <name> [span]")
        found.append((int(parts[0]), parts[1], int(parts[2]) if len(parts) == 3 else 1))
    return found


def sheet(jar: zipfile.ZipFile, source: str, namesPath: Path, folder: str) -> list[str]:
    width = PNG_WIDTH.unpack_from(jar.read(source), PNG_WIDTH_OFFSET)[0]
    tile = width // GRID
    folder = folder.rstrip("/") + "/"
    sprites = sheetNames(namesPath)
    single = [(slot, name) for slot, name, span in sprites if span == 1]
    lines = []
    if single:
        lines += ["[[slice]]", f"from = {quote(source)}", f"to = {quote(folder)}", f"tile = {tile}", "", "[slice.tiles]"]
        lines += [f"{slot} = {quote(name)}" for slot, name in single] + [""]
    for slot, name, span in sprites:
        if span == 1:
            continue
        if slot % GRID + span > GRID:
            raise SystemExit(f"{source} slot {slot} with span {span} runs off the {GRID} wide sheet")
        size = tile * span
        rect = f"[{slot % GRID * tile}, {slot // GRID * tile}, {size}, {size}]"
        lines += ["[[compose]]", f"from = {quote(source)}", f"to = {quote(f'{folder}{name}.png')}"]
        lines += [f"canvas = [{size}, {size}]", f"parts = [{{ rect = {rect}, at = [0, 0] }}]", ""]
    return lines


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("jar", type=Path)
    parser.add_argument("modid")
    parser.add_argument("--source", help="namespace under assets/ in the jar, detected when absent")
    parser.add_argument("--url", help="download page shown to players who lack the file")
    parser.add_argument("--sheet", nargs=3, action="append", default=[], metavar=("SHEET", "NAMES", "TO"))
    parser.add_argument("--out", type=Path, default=Path("assets.toml"))
    args = parser.parse_args()

    sha = hashlib.sha256(args.jar.read_bytes()).hexdigest()
    lines = ["# generated by tools/recipe.py from the pinned jar", "", "[[download]]", f"name = {quote(args.jar.name)}"]
    if args.url:
        lines.append(f"url = {quote(args.url)}")
    lines += [f"sha256 = [{quote(sha)}]", ""]
    with zipfile.ZipFile(args.jar) as jar:
        names = sorted(jar.namelist())
        source = args.source or sourceNamespace(names)
        prefix = f"assets/{source}/" if source else None
        if prefix:
            lines += copies(names, prefix)
        for path, namesPath, folder in args.sheet:
            lines += sheet(jar, path, Path(namesPath), folder)
        if prefix:
            lines += lang(jar, names, prefix, args.modid)
    args.out.write_text("\n".join(lines).rstrip("\n") + "\n")
    origin = f"assets/{source}" if source else "no assets/ namespace"
    print(f"wrote {args.out} from {origin} and {len(args.sheet)} sheets")


if __name__ == "__main__":
    main()
