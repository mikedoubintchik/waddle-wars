#!/usr/bin/env python3
"""Generate deterministic 1024px painted atlases for the expedition item cache.

No third-party packages. Albedo carries broad hand-painted value separation;
normal and packed ORM carry frost grain, recessed seams, curvature, and baked
contact darkening. Runtime uses one opaque Compatibility-safe material.
"""

from __future__ import annotations

import argparse
import math
import struct
import zlib
from pathlib import Path


SIZE = 1024
TILES = 4


def _chunk(kind: bytes, payload: bytes) -> bytes:
    return (struct.pack(">I", len(payload)) + kind + payload
            + struct.pack(">I", zlib.crc32(kind + payload)))


def _write_png(path: Path, pixels: bytes) -> None:
    stride = SIZE * 3
    rows = b"".join(
        b"\x00" + pixels[y * stride:(y + 1) * stride]
        for y in range(SIZE)
    )
    payload = b"\x89PNG\r\n\x1a\n"
    payload += _chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
    payload += _chunk(b"IDAT", zlib.compress(rows, 9))
    payload += _chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)


def _noise(x: int, y: int, seed: int) -> float:
    value = (x * 374761393 + y * 668265263 + seed * 2246822519) & 0xFFFFFFFF
    value = ((value ^ (value >> 13)) * 1274126177) & 0xFFFFFFFF
    value ^= value >> 16
    return float(value & 0xFFFF) / 65535.0


def _u8(value: float) -> int:
    return max(0, min(255, round(value * 255.0)))


def _tile(x: int, y: int) -> tuple[int, float, float]:
    side = SIZE // TILES
    index = (y // side) * TILES + x // side
    return index, (x % side) / side, (y % side) / side


# One atlas serves every mesh role. Dominant navy/cream defines expedition
# hardware; violet owns every power-bearing face. Brass stays a narrow latch
# accent so gold collection and orange hazard semantics remain unambiguous.
BASES = [
    (0.055, 0.145, 0.255),  # 0 pressure-shell navy
    (0.080, 0.260, 0.370),  # 1 lifted shell bevel
    (0.805, 0.850, 0.815),  # 2 cream frost cap
    (0.475, 0.105, 0.835),  # 3 violet power aperture
    (0.720, 0.385, 0.990),  # 4 violet edge/rune
    (0.485, 0.365, 0.145),  # 5 muted brass fastener
    (0.070, 0.105, 0.145),  # 6 rubber carry grip
    (0.245, 0.350, 0.405),  # 7 cold steel cage
    (0.900, 0.875, 0.785),  # 8 worn cream highlight
    (0.300, 0.070, 0.555),  # 9 violet recess
    (0.120, 0.235, 0.330),  # 10 blue steel mid
    (0.635, 0.515, 0.275),  # 11 brass edge
    (0.030, 0.050, 0.090),  # 12 deep seam
    (0.590, 0.270, 0.905),  # 13 violet painted mid
    (0.720, 0.760, 0.740),  # 14 frosted metal
    (0.110, 0.145, 0.185),  # 15 dark grip mid
]


def _albedo() -> bytes:
    out = bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            index, u, v = _tile(x, y)
            base = BASES[index]
            broad = math.sin((u * 1.2 + v * 0.38 + index * 0.11) * math.tau) * 0.025
            brush = math.sin(v * math.tau * (4 + index % 5) + math.sin(u * 9.0)) * 0.012
            grain = (_noise(x // 3, y // 3, 97 + index) - 0.5) * 0.030
            edge = min(u, v, 1.0 - u, 1.0 - v)
            curvature = -0.11 * max(0.0, (0.060 - edge) / 0.060)
            # Sparse diagonal scuffs. Broad enough to survive mipmapping; never
            # a high-frequency procedural wallpaper.
            stroke = -0.055 if ((x + y * 2 + index * 29) % 211 < 4
                                and 0.12 < u < 0.88 and 0.12 < v < 0.88) else 0.0
            value = broad + brush + grain + curvature + stroke
            out.extend(_u8(channel + value) for channel in base)
    return bytes(out)


def _height(x: int, y: int) -> float:
    index, u, v = _tile(x % SIZE, y % SIZE)
    brush = math.sin(v * math.tau * (5 + index % 4) + math.sin(u * 8.0)) * 0.11
    peen = (_noise(x // 2, y // 2, 211 + index) - 0.5) * 0.16
    seam = -0.32 if min(u, v, 1.0 - u, 1.0 - v) < 0.030 else 0.0
    scuff = -0.14 if ((x + y * 2 + index * 29) % 211 < 4) else 0.0
    return brush + peen + seam + scuff


def _normal() -> bytes:
    out = bytearray()
    strength = 0.82
    for y in range(SIZE):
        for x in range(SIZE):
            nx = (_height(x - 1, y) - _height(x + 1, y)) * strength
            ny = (_height(x, y - 1) - _height(x, y + 1)) * strength
            nz = 1.0
            length = math.sqrt(nx * nx + ny * ny + nz * nz)
            out.extend((_u8(nx / length * 0.5 + 0.5),
                        _u8(ny / length * 0.5 + 0.5),
                        _u8(nz / length * 0.5 + 0.5)))
    return bytes(out)


def _orm() -> bytes:
    # R=AO, G=roughness, B=metallic. Atlas-border AO is intentionally baked;
    # runtime remains grounded when SSAO and glow are unavailable.
    roughness = [0.64, 0.55, 0.82, 0.28, 0.24, 0.44, 0.78, 0.50,
                 0.76, 0.34, 0.48, 0.40, 0.84, 0.30, 0.61, 0.73]
    metallic = [0.08, 0.12, 0.00, 0.04, 0.05, 0.36, 0.00, 0.30,
                0.00, 0.03, 0.24, 0.42, 0.00, 0.04, 0.20, 0.00]
    out = bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            index, u, v = _tile(x, y)
            edge = min(u, v, 1.0 - u, 1.0 - v)
            ao = 0.66 + min(edge / 0.095, 1.0) * 0.34
            if ((x + y * 2 + index * 29) % 211 < 5):
                ao -= 0.15
            grain = (_noise(x // 4, y // 4, 307 + index) - 0.5) * 0.065
            out.extend((_u8(ao), _u8(roughness[index] + grain), _u8(metallic[index])))
    return bytes(out)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    output = Path(args.output)
    maps = {
        "item_cache_albedo_v1.png": _albedo(),
        "item_cache_normal_v1.png": _normal(),
        "item_cache_orm_v1.png": _orm(),
    }
    for name, pixels in maps.items():
        path = output / name
        _write_png(path, pixels)
        print(f"[item-cache-textures] {path} bytes={path.stat().st_size}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
