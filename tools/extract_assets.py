"""Copy a mod's textures, sounds and lang out of the user's own jar into a port's assets/<modid>.

Mod assets belong to their authors, so they are never committed. Run from the port folder:
    python3 -I ../../tools/modport/extract_assets.py <mod.jar> <modid> [--source <jar namespace>]
Port specific extras (sprites built from 3D renderers, special lang keys) go in the port's own tools script, run after this.
"""

import argparse
import json
import re
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
LEGACY_NAME = re.compile(r"^(tile|item|entity)\.(?:[a-z0-9_]+[.:])?([a-z0-9_.]+)\.name$")
MODERN_NAME = re.compile(r"^(block|item|entity)\.[a-z0-9_]+\.([a-z0-9_.]+)$")
MODERN_KIND = {"block": "tile", "item": "item", "entity": "entity"}


def sourceNamespace(jar: zipfile.ZipFile) -> str:
    counts = Counter(name.split("/")[1] for name in jar.namelist() if name.startswith("assets/") and name.count("/") > 2)
    counts.pop("minecraft", None)
    if not counts:
        raise SystemExit("no assets/<namespace>/ folder in the jar")
    return counts.most_common(1)[0][0]


def target(rest: str) -> str:
    for source, mapped in FOLDERS:
        if rest.startswith(source):
            return mapped + rest[len(source):]
    return rest


def copyFiles(jar: zipfile.ZipFile, prefix: str, out: Path) -> int:
    count = 0
    for name in jar.namelist():
        if not name.startswith(prefix) or not name.endswith(COPIED):
            continue
        path = out / target(name[len(prefix):]).lower()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(jar.read(name))
        count += 1
    return count


def langEntries(jar: zipfile.ZipFile, prefix: str) -> dict[str, str]:
    names = set(jar.namelist())
    for name in (prefix + "lang/en_US.lang", prefix + "lang/en_us.lang"):
        if name in names:
            text = jar.read(name).decode("utf-8")
            pairs = (line.split("=", 1) for line in text.splitlines() if "=" in line and not line.startswith("#"))
            return {key.strip(): value.strip() for key, value in pairs}
    if prefix + "lang/en_us.json" in names:
        return json.loads(jar.read(prefix + "lang/en_us.json"))
    return {}


def portKey(key: str, modid: str) -> str:
    legacy = LEGACY_NAME.match(key)
    if legacy:
        return f"{legacy[1]}.{modid}.{legacy[2]}.name"
    modern = MODERN_NAME.match(key)
    if modern:
        return f"{MODERN_KIND[modern[1]]}.{modid}.{modern[2]}.name"
    return f"{modid}.{key}"


def writeLang(entries: dict[str, str], modid: str, out: Path) -> int:
    lines = [f"{portKey(key, modid)}={value}" for key, value in entries.items()]
    path = out / "lang" / "en_US.lang"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return len(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("jar")
    parser.add_argument("modid")
    parser.add_argument("--source", help="namespace under assets/ in the jar, detected when absent")
    parser.add_argument("--out", help="output folder, default assets/<modid> in the current folder")
    args = parser.parse_args()
    out = Path(args.out or f"assets/{args.modid}")
    with zipfile.ZipFile(args.jar) as jar:
        source = args.source or sourceNamespace(jar)
        prefix = f"assets/{source}/"
        files = copyFiles(jar, prefix, out)
        keys = writeLang(langEntries(jar, prefix), args.modid, out)
    print(f"{files} files and {keys} lang keys from assets/{source} into {out}")


if __name__ == "__main__":
    main()
