#!/usr/bin/env python3
"""Generate deterministic hand-painted DAY kit texture set without dependencies."""

from __future__ import annotations

import argparse
import math
import struct
import zlib
from pathlib import Path


SIZE = 1024
TILES = 4
PAINT_TILES = frozenset((0, 1, 2, 3, 7, 8, 9, 10, 13))
RIVET_TILES = frozenset((0, 1, 2, 3, 7, 8, 9, 10, 11, 12, 13))


def chunk(kind: bytes, payload: bytes) -> bytes:
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))


def write_png(path: Path, pixels: bytes) -> None:
    rows = b"".join(b"\x00" + pixels[y * SIZE * 3:(y + 1) * SIZE * 3] for y in range(SIZE))
    payload = b"\x89PNG\r\n\x1a\n"
    payload += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
    payload += chunk(b"IDAT", zlib.compress(rows, 9))
    payload += chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)


def hash_noise(x: int, y: int, seed: int) -> float:
    value = (x * 374761393 + y * 668265263 + seed * 2246822519) & 0xFFFFFFFF
    value = ((value ^ (value >> 13)) * 1274126177) & 0xFFFFFFFF
    value ^= value >> 16
    return float(value & 0xFFFF) / 65535.0


def value_noise(x: int, y: int, seed: int, cell: int) -> float:
    """Bilinear coarse noise for organic macro wear, without block artifacts."""
    gx, gy = x // cell, y // cell
    tx, ty = (x % cell) / cell, (y % cell) / cell
    tx = tx * tx * (3.0 - 2.0 * tx)
    ty = ty * ty * (3.0 - 2.0 * ty)
    a = hash_noise(gx, gy, seed)
    b = hash_noise(gx + 1, gy, seed)
    c = hash_noise(gx, gy + 1, seed)
    d = hash_noise(gx + 1, gy + 1, seed)
    top = a + (b - a) * tx
    bottom = c + (d - c) * tx
    return top + (bottom - top) * ty


def clamp8(value: float) -> int:
    return max(0, min(255, round(value * 255.0)))


def albedo() -> bytes:
    # Neutral tints multiply COLOR_0. Tiles vary paint response, not semantic
    # meaning; vertex colour remains authoritative for gameplay hues.
    # Keep atlas response near-neutral: semantic paint belongs to COLOR_0.
    # Earlier 0.72-0.85 tiles multiplied already-dark navy into literal black.
    bases = [
        (0.93, 0.96, 0.97), (0.89, 0.94, 0.96), (0.85, 0.91, 0.93), (0.84, 0.90, 0.92),
        (0.82, 0.89, 0.91), (0.90, 0.95, 0.95), (0.82, 0.89, 0.91), (0.93, 0.87, 0.79),
        (0.94, 0.88, 0.80), (0.86, 0.93, 0.94), (0.87, 0.95, 0.90), (0.95, 0.90, 0.78),
        (0.87, 0.91, 0.94), (0.91, 0.92, 0.88), (0.94, 0.96, 0.91), (0.98, 0.88, 0.72),
    ]
    out = bytearray()
    tile = SIZE // TILES
    for y in range(SIZE):
        for x in range(SIZE):
            tx, ty = x // tile, y // tile
            index = ty * TILES + tx
            u, v = (x % tile) / tile, (y % tile) / tile
            # Broad hand-painted rolls survive mipmapping and remain visible at
            # chase distance; the smaller strokes resolve only on near props.
            broad = math.sin((u * 1.08 + v * 0.37 + index * 0.19) * math.tau) * 0.060
            panel_roll = (value_noise(x, y, index + 313, 68) - 0.5) * (
                0.22 if index in PAINT_TILES else 0.12)
            brush = math.sin(v * math.tau * 1.5 + math.sin(u * 3.2)) * 0.018
            grain = (hash_noise(x // 8, y // 8, index + 17) - 0.5) * 0.008
            # One restrained broad scuff, not a field of one-pixel scratches.
            scuff_axis = 0.22 + ((index * 29) % 47) / 100.0
            scuff_distance = abs(u - scuff_axis - math.sin(v * 5.0 + index) * 0.025)
            scratch = (-0.075 * max(0.0, 1.0 - scuff_distance / 0.020)
                       if index != 5 else 0.0)
            edge = min(u, v, 1.0 - u, 1.0 - v)
            cavity = -0.085 * max(0.0, (0.060 - edge) / 0.060)
            rolled_edge = 0.060 * max(0.0, 1.0 - abs(edge - 0.075) / 0.030)
            frost = (0.070 * max(0.0, (0.18 - v) / 0.18)
                     if index not in (4, 5) and index % 4 != 3 else 0.0)
            # Broad irregular brush pass. Per-tile slope/offset prevent a
            # visible atlas stamp; width is large enough to survive mipmaps.
            slope = (-0.28, 0.18, -0.08, 0.32)[index % 4]
            offset = 0.24 + ((index * 37) % 43) / 100.0
            brush_line = offset + slope * (u - 0.5) + math.sin(u * 8.0 + index) * 0.025
            brush_distance = abs(v - brush_line)
            macro_brush = (0.115 * max(0.0, 1.0 - brush_distance / 0.24) ** 2
                           if index in PAINT_TILES else 0.0)
            # Clustered paint chips gather toward a different edge per tile.
            # Coarse deterministic noise creates broken shapes, never rings.
            edge_axis = u if index % 2 == 0 else v
            edge_axis = edge_axis if (index // 2) % 2 == 0 else 1.0 - edge_axis
            chip_zone = max(0.0, 1.0 - edge_axis / 0.34)
            chip_noise = value_noise(x, y, index + 509, 24)
            macro_chips = (-0.130 * chip_zone
                           * max(0.0, (chip_noise - 0.58) / 0.42)
                           if index in PAINT_TILES else 0.0)
            # Two broad service-wear tracks on deck paint. Their wandering
            # edges remain visible after mipmapping; this is macro history,
            # not another layer of high-frequency grunge.
            track_wear = 0.0
            if index == 13:
                left_track = 0.30 + math.sin(v * math.tau * 1.35) * 0.035
                right_track = 0.70 + math.sin(v * math.tau * 1.15 + 1.7) * 0.035
                track_distance = min(abs(u - left_track), abs(u - right_track))
                track_wear = -0.105 * max(0.0, 1.0 - track_distance / 0.090) ** 1.4
            material_roll = 0.0
            if index == 4:  # blue ice: broad cloudy depth, sparse scratches.
                material_roll = (value_noise(x, y, 733, 64) - 0.5) * 0.105
                scratch *= 1.35
            elif index == 5:  # compacted snow: soft mounds, never metal chips.
                material_roll = (value_noise(x, y, 811, 52) - 0.5) * 0.16
                broad *= 0.34
                brush *= 0.24
                grain *= 0.30
                cavity *= 0.28
                rolled_edge *= 0.25
            elif index == 14:  # tracked frost: broad cloudy deposits, no chips.
                material_roll = (value_noise(x, y, 881, 58) - 0.5) * 0.14
                broad *= 0.42
                brush *= 0.22
                grain *= 0.28
                cavity *= 0.30
                rolled_edge *= 0.28
                macro_chips = 0.0
            elif index in (6, 15):  # cold/warm glass: calm roll, no brush stamp.
                material_roll = (value_noise(x, y, 929 + index, 72) - 0.5) * 0.035
                broad *= 0.16
                brush *= 0.08
                grain *= 0.18
                cavity *= 0.45
                rolled_edge *= 0.30
            # Four restrained recessed rivets per tile. They supply readable
            # authored scale without turning the atlas into noisy grunge.
            rivet = 0.0
            if index in RIVET_TILES:
                for rx, ry in ((0.13, 0.13), (0.87, 0.13), (0.13, 0.87), (0.87, 0.87)):
                    distance = math.hypot(u - rx, v - ry)
                    if distance < 0.026:
                        rivet = min(rivet, -0.14 * (1.0 - distance / 0.026))
                    elif distance < 0.040:
                        rivet = max(rivet, 0.050 * (1.0 - (distance - 0.026) / 0.014))
            shade = (broad + panel_roll + brush + grain + scratch + cavity + rolled_edge + frost
                     + macro_brush + macro_chips + track_wear + material_roll + rivet)
            base = bases[index]
            out.extend(clamp8(channel + shade) for channel in base)
    return bytes(out)


def height_value(x: int, y: int) -> float:
    tile = SIZE // TILES
    tx, ty = x // tile, y // tile
    index = ty * TILES + tx
    u, v = (x % tile) / tile, (y % tile) / tile
    if index in (5, 14):
        # Low-frequency compacted-snow mounds. Sparse grain avoids plastic
        # smoothness while keeping normals quiet enough for mipmapped distance.
        return ((value_noise(x, y, 1201 + index, 38) - 0.5) * 0.78
                + (hash_noise(x, y, 1207 + index) - 0.5) * 0.045)
    if index in (6, 15):
        return ((value_noise(x, y, 1301 + index, 74) - 0.5) * 0.12
                + (hash_noise(x, y, 1307 + index) - 0.5) * 0.018)
    macro = ((value_noise(x, y, index + 1001, 48) - 0.5) * 0.62
             + (value_noise(x, y, index + 1103, 92) - 0.5) * 0.24)
    roll = math.sin(u * math.tau * (1.4 + index % 2) + math.sin(v * 4.0)) * 0.12
    brush = math.sin(v * math.tau * (2.2 + index % 2)) * 0.055
    grain = (hash_noise(x // 3, y // 3, index + 101) - 0.5) * 0.035
    seam = (-0.38 if index == 4 else -0.28) \
        if abs((x + index * 7) % 223 - 111) <= 1 else 0.0
    track_groove = 0.0
    if index == 13:
        left_track = 0.30 + math.sin(v * math.tau * 1.35) * 0.035
        right_track = 0.70 + math.sin(v * math.tau * 1.15 + 1.7) * 0.035
        distance = min(abs(u - left_track), abs(u - right_track))
        track_groove = -0.24 * max(0.0, 1.0 - distance / 0.080) ** 1.5
    edge_ridge = (0.0 if index == 4 else 0.24) * max(
        0.0, 1.0 - abs(min(u, v, 1.0 - u, 1.0 - v) - 0.055) / 0.018)
    rivet = 0.0
    if index in RIVET_TILES:
        for rx, ry in ((0.13, 0.13), (0.87, 0.13), (0.13, 0.87), (0.87, 0.87)):
            distance = math.hypot(u - rx, v - ry)
            if distance < 0.028:
                rivet = min(rivet, -0.48 * (1.0 - distance / 0.028))
    return macro + roll + brush + grain + seam + track_groove + edge_ridge + rivet


def normal() -> bytes:
    out = bytearray()
    strength = 2.05
    for y in range(SIZE):
        for x in range(SIZE):
            left = height_value((x - 1) % SIZE, y)
            right = height_value((x + 1) % SIZE, y)
            down = height_value(x, (y - 1) % SIZE)
            up = height_value(x, (y + 1) % SIZE)
            nx = (left - right) * strength
            ny = (down - up) * strength
            nz = 1.0
            length = math.sqrt(nx * nx + ny * ny + nz * nz)
            out.extend((clamp8(nx / length * 0.5 + 0.5),
                        clamp8(ny / length * 0.5 + 0.5),
                        clamp8(nz / length * 0.5 + 0.5)))
    return bytes(out)


def orm() -> bytes:
    # Palette order mirrors generate_day_kit.py. Painted powder coat stays
    # broad/rough; ice and glass catch controlled highlights; snow/rubber are
    # non-metallic; only gold fasteners carry meaningful metal response.
    roughness = [0.58, 0.55, 0.50, 0.58, 0.38, 0.88, 0.22, 0.48,
                 0.42, 0.42, 0.46, 0.32, 0.86, 0.62, 0.84, 0.26]
    metallic = [0.03, 0.05, 0.08, 0.04, 0.00, 0.00, 0.02, 0.02,
                0.02, 0.02, 0.02, 0.55, 0.00, 0.01, 0.00, 0.00]
    out = bytearray()
    tile = SIZE // TILES
    for y in range(SIZE):
        for x in range(SIZE):
            index = (y // tile) * TILES + x // tile
            u, v = (x % tile) / tile, (y % tile) / tile
            edge = min(u, v, 1.0 - u, 1.0 - v)
            ao = 0.72 + min(edge / 0.085, 1.0) * 0.28
            broad = (value_noise(x, y, index + 1601, 68) - 0.5) * 0.30
            grain = (hash_noise(x // 8, y // 8, index + 211) - 0.5) * 0.035
            frost = 0.14 * max(0.0, (0.14 - v) / 0.14)
            slope = (-0.28, 0.18, -0.08, 0.32)[index % 4]
            offset = 0.24 + ((index * 37) % 43) / 100.0
            brush_line = offset + slope * (u - 0.5) + math.sin(u * 8.0 + index) * 0.025
            worn = -0.20 * max(0.0, 1.0 - abs(v - brush_line) / 0.20) ** 2
            if index == 13:
                left_track = 0.30 + math.sin(v * math.tau * 1.35) * 0.035
                right_track = 0.70 + math.sin(v * math.tau * 1.15 + 1.7) * 0.035
                track_distance = min(abs(u - left_track), abs(u - right_track))
                worn -= 0.14 * max(0.0, 1.0 - track_distance / 0.095) ** 1.4
            rough = roughness[index] + broad + grain + frost + worn
            metal = metallic[index]
            out.extend((clamp8(ao), clamp8(rough), clamp8(metal)))
    return bytes(out)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    root = Path(args.output)
    write_png(root / "runner_day_surface_albedo_v1.png", albedo())
    write_png(root / "runner_day_surface_normal_v1.png", normal())
    write_png(root / "runner_day_surface_orm_v1.png", orm())
    for path in sorted(root.glob("*.png")):
        print(f"[day-textures] {path} bytes={path.stat().st_size}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
