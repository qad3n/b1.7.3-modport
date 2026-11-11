"""Cut an old-style sprite sheet from a mod jar into single modern sprites for a port's assets/<modid>.

Old mods (ModLoader and Forge before 1.5) draw blocks and items from 16x16 grid sheets. Ports use the modern
layout, one png per sprite under assets/<modid>/textures/block or item, so player texture packs can replace them.
Run from the port folder:
    python3 -I ../../tools/modport/split_sheet.py <sheet.png> <names.txt> <out folder> [--grid 16]
names.txt has one sprite per line: `<slot> <name> [span]`, slot counted left to right and top to bottom, span the
tiles across and down for big sprites such as 2x2 flow tiles. Blank lines and `#` lines are skipped.
Sheets are the mod authors' assets: the cut sprites are never committed.
"""

import argparse
import struct
import zlib
from pathlib import Path

SIGNATURE = b"\x89PNG\r\n\x1a\n"
# samples per pixel by png color type
CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}


def chunks(data: bytes):
    position = len(SIGNATURE)
    while position < len(data):
        length, kind = struct.unpack(">I4s", data[position : position + 8])
        yield kind, data[position + 8 : position + 8 + length]
        position += 12 + length


def paeth(left: int, up: int, corner: int) -> int:
    estimate = left + up - corner
    distances = (abs(estimate - left), abs(estimate - up), abs(estimate - corner))
    return (left, up, corner)[distances.index(min(distances))]


def unfilter(raw: bytes, width: int, height: int, stride: int) -> list[bytearray]:
    rows: list[bytearray] = []
    previous = bytearray(width * stride)
    position = 0
    for _ in range(height):
        kind = raw[position]
        line = bytearray(raw[position + 1 : position + 1 + width * stride])
        position += 1 + width * stride
        for i in range(len(line)):
            left = line[i - stride] if i >= stride else 0
            up = previous[i]
            corner = previous[i - stride] if i >= stride else 0
            line[i] = (line[i] + (0, left, up, (left + up) // 2, paeth(left, up, corner))[kind]) & 0xFF
        rows.append(line)
        previous = line
    return rows


def decode(path: Path) -> tuple[int, int, list[list[tuple[int, int, int, int]]]]:
    data = path.read_bytes()
    if not data.startswith(SIGNATURE):
        raise SystemExit(f"{path} is not a png")

    header, palette, alpha, compressed = b"", b"", b"", b""
    for kind, body in chunks(data):
        if kind == b"IHDR":
            header = body
        elif kind == b"PLTE":
            palette = body
        elif kind == b"tRNS":
            alpha = body
        elif kind == b"IDAT":
            compressed += body

    width, height, depth, color, _, _, interlace = struct.unpack(">IIBBBBB", header)
    if depth != 8 or interlace != 0 or color not in CHANNELS:
        raise SystemExit(f"{path}: only 8 bit non interlaced pngs are supported, re-save it first")

    stride = CHANNELS[color]
    rows = unfilter(zlib.decompress(compressed), width, height, stride)
    pixels = []
    for line in rows:
        out = []
        for x in range(width):
            sample = line[x * stride : (x + 1) * stride]
            if color == 6:
                out.append(tuple(sample))
            elif color == 2:
                out.append((*sample, 255))
            elif color == 4:
                out.append((sample[0], sample[0], sample[0], sample[1]))
            elif color == 0:
                out.append((sample[0], sample[0], sample[0], 255))
            else:
                index = sample[0]
                red, green, blue = palette[index * 3 : index * 3 + 3]
                out.append((red, green, blue, alpha[index] if index < len(alpha) else 255))
        pixels.append(out)
    return width, height, pixels


def encode(path: Path, size: int, pixels: list[list[tuple[int, int, int, int]]]) -> None:
    raw = b"".join(b"\x00" + bytes(channel for pixel in row for channel in pixel) for row in pixels)

    def chunk(kind: bytes, body: bytes) -> bytes:
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))

    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(SIGNATURE + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def names(path: Path) -> list[tuple[int, str, int]]:
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


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("sheet", type=Path)
    parser.add_argument("names", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--grid", type=int, default=16, help="tiles across the sheet")
    args = parser.parse_args()

    width, height, pixels = decode(args.sheet)
    tile = width // args.grid
    rows = height // tile

    for slot, name, span in names(args.names):
        left, top = slot % args.grid * tile, slot // args.grid * tile
        if slot // args.grid + span > rows or slot % args.grid + span > args.grid:
            raise SystemExit(f"slot {slot} with span {span} runs off the {args.grid} wide sheet")
        size = tile * span
        sprite = [pixels[top + y][left : left + size] for y in range(size)]
        encode(args.out / f"{name}.png", size, sprite)

    print(f"cut {len(names(args.names))} sprites of {tile} pixels into {args.out}")


if __name__ == "__main__":
    main()
