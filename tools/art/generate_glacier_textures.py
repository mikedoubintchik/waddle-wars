#!/usr/bin/env python3
"""Generate Glacier Gauntlet's deterministic painted albedo/normal/ORM atlas.

No third-party packages. The atlas carries material response and brush grain;
semantic colour remains in COLOR_0 so obstacles never depend on texture hue.
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
    rows = b"".join(b"\x00" + pixels[y * stride:(y + 1) * stride]
                    for y in range(SIZE))
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


def _tile_coords(x: int, y: int) -> tuple[int, float, float]:
    side = SIZE // TILES
    index = (y // side) * TILES + x // side
    return index, (x % side) / side, (y % side) / side


def _albedo() -> bytes:
    # Near-neutral multipliers retain bright snow and saturated semantic paint.
    bases = [
        (0.985, 0.995, 1.000), (0.920, 0.975, 1.000),
        (0.860, 0.945, 0.995), (0.780, 0.900, 0.980),
        (0.970, 0.985, 1.000), (0.890, 0.965, 1.000),
        (0.825, 0.920, 0.985), (0.955, 0.980, 1.000),
        (0.985, 0.965, 0.925), (0.940, 0.975, 0.995),
        (0.900, 0.940, 0.975), (0.980, 0.990, 1.000),
        (0.965, 0.985, 1.000), (0.905, 0.955, 0.995),
        (0.840, 0.920, 0.980), (0.985, 0.975, 0.945),
    ]
    out = bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            index, u, v = _tile_coords(x, y)
            # Broad hand-painted sweep + tight wind grain + sparse ice scars.
            broad = math.sin((u * 1.7 + v * 0.43 + index * 0.17) * math.tau) * 0.018
            brush = math.sin(v * math.tau * (5 + index % 4) + math.sin(u * 10.0)) * 0.010
            grain = (_noise(x // 3, y // 3, index + 31) - 0.5) * 0.022
            scar = -0.075 if ((x + 19 * index) % 173 < 2 and (y + 7 * index) % 23 < 15) else 0.0
            edge = min(u, v, 1.0 - u, 1.0 - v)
            curvature = -0.045 * max(0.0, (0.045 - edge) / 0.045)
            value = broad + brush + grain + scar + curvature
            out.extend(_u8(channel + value) for channel in bases[index])
    return bytes(out)


def _height(x: int, y: int) -> float:
    index, u, v = _tile_coords(x % SIZE, y % SIZE)
    wind = math.sin((v * (6 + index % 4) + u * 0.4) * math.tau) * 0.16
    facets = math.sin((u + v) * math.tau * (2 + index % 3)) * 0.08
    brush = math.sin(v * math.tau * 17.0 + math.sin(u * 13.0)) * 0.045
    grain = (_noise(x, y, index + 149) - 0.5) * 0.10
    scar = -0.26 if ((x + index * 11) % 181 < 2) else 0.0
    return wind + facets + brush + grain + scar


def _normal() -> bytes:
    out = bytearray()
    strength = 1.15
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
    # R=AO, G=roughness, B=metallic. Ice tiles are glossy; snow and fabric
    # tiles stay broad and matte. Atlas-edge AO gives repeated forms curvature.
    roughness = [0.88, 0.54, 0.24, 0.16, 0.82, 0.46, 0.20, 0.72,
                 0.60, 0.34, 0.22, 0.76, 0.90, 0.50, 0.28, 0.64]
    metallic = [0.00, 0.02, 0.03, 0.04, 0.00, 0.04, 0.06, 0.00,
                0.02, 0.05, 0.08, 0.00, 0.00, 0.03, 0.06, 0.02]
    out = bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            index, u, v = _tile_coords(x, y)
            edge = min(u, v, 1.0 - u, 1.0 - v)
            ao = 0.72 + min(edge / 0.09, 1.0) * 0.28
            # Sparse painted cavities, independent of albedo, deepen contact.
            if ((x + index * 13) % 181 < 3 and (y + index * 5) % 29 < 18):
                ao -= 0.18
            grain = (_noise(x // 4, y // 4, index + 271) - 0.5) * 0.07
            out.extend((_u8(ao), _u8(roughness[index] + grain), _u8(metallic[index])))
    return bytes(out)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    root = Path(args.output)
    maps = {
        "glacier_surface_albedo_v1.png": _albedo(),
        "glacier_surface_normal_v1.png": _normal(),
        "glacier_surface_orm_v1.png": _orm(),
    }
    for name, pixels in maps.items():
        path = root / name
        _write_png(path, pixels)
        print(f"[glacier-textures] {path} bytes={path.stat().st_size}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
