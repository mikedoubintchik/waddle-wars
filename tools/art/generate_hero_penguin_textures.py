#!/usr/bin/env python3
"""Generate deterministic 1024px hero-penguin feather maps.

No runtime dependency: outputs are committed authoring/runtime PNGs. Atlas is
neutral detail, sampled over semantic species colors by Godot shader.
"""

from __future__ import annotations

import argparse
import math
import random
import shutil
import struct
import zlib
from array import array
from pathlib import Path


SIZE = 1024
SEED = 0x57ADD1E
ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / "art_src/characters/textures"
RUNTIME_DIR = ROOT / "assets/art/characters/textures"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--size", type=int, default=SIZE)
    return parser.parse_args()


def smooth(value: float) -> float:
    return value * value * (3.0 - 2.0 * value)


def hash01(x: int, y: int, seed: int) -> float:
    value = (x * 0x1F123BB5) ^ (y * 0x5F356495) ^ seed
    value = (value ^ (value >> 16)) * 0x45D9F3B
    value = (value ^ (value >> 16)) * 0x45D9F3B
    value ^= value >> 16
    return (value & 0xFFFF) / 65535.0


def value_noise(x: float, y: float, cells: int, seed: int) -> float:
    ix = math.floor(x * cells)
    iy = math.floor(y * cells)
    fx = smooth(x * cells - ix)
    fy = smooth(y * cells - iy)
    x0 = ix % cells
    x1 = (ix + 1) % cells
    y0 = iy % cells
    y1 = (iy + 1) % cells
    a = hash01(x0, y0, seed)
    b = hash01(x1, y0, seed)
    c = hash01(x0, y1, seed)
    d = hash01(x1, y1, seed)
    top = a + (b - a) * fx
    bottom = c + (d - c) * fx
    return top + (bottom - top) * fy


def build_height(size: int) -> array:
    height = array("f", [0.0]) * (size * size)
    half = size // 2
    if half * 2 != size:
        raise ValueError("hero feather atlas requires even dimensions")
    for y in range(size):
        v = y / size
        row = y * size
        for x in range(size):
            cream = x >= half
            local_x = x - half if cream else x
            u = local_x / half
            region_seed = SEED ^ (0xC4E4A if cream else 0xD4A4B)
            broad = value_noise(u, v, 11 if cream else 15, region_seed)
            medium = value_noise(u, v, 37 if cream else 52, region_seed ^ 0xB16B00B5)
            # Low-amplitude value body; directional strokes below carry most
            # visible detail. This avoids cloudy/noisy mottling and moire.
            broad_gain = 0.024 if cream else 0.018
            medium_gain = 0.012 if cream else 0.009
            height[row + x] = ((broad - 0.5) * broad_gain
                               + (medium - 0.5) * medium_gain)

    # Hand-painted feather/barb marks: thousands of short, tapered, curved
    # strokes. Wrapped addressing keeps texture seamless without visible bands.
    rng = random.Random(SEED)
    for cream, count in ((False, 5600), (True, 6400)):
        region_start = half if cream else 0
        for _stroke in range(count):
            start_x = rng.uniform(0.0, half)
            start_y = rng.uniform(0.0, size)
            length = rng.uniform(11.0, 27.0) if cream else rng.uniform(8.0, 21.0)
            angle_spread = 0.54 if cream else 0.38
            angle = rng.uniform(-angle_spread, angle_spread) + math.pi * 0.5
            curve = rng.uniform(-0.030, 0.030) if cream else rng.uniform(-0.022, 0.022)
            radius = rng.uniform(1.25, 2.35) if cream else rng.uniform(1.10, 2.10)
            magnitude = rng.uniform(0.0032, 0.0080) if cream else rng.uniform(0.0028, 0.0072)
            amplitude = magnitude if rng.random() < 0.53 else -magnitude
            steps = max(5, int(length))
            for step in range(steps):
                t = step / max(1, steps - 1)
                taper = math.sin(math.pi * t) ** (0.82 if cream else 0.90)
                local_angle = angle + curve * step
                px = start_x + math.cos(local_angle) * length * t
                py = start_y + math.sin(local_angle) * length * t
                extent = max(1, math.ceil(radius))
                for oy in range(-extent, extent + 1):
                    for ox in range(-extent, extent + 1):
                        distance = math.sqrt(ox * ox + oy * oy)
                        if distance > radius:
                            continue
                        weight = (1.0 - distance / max(radius, 0.001)) ** 1.45
                        ix = region_start + int(round(px + ox)) % half
                        iy = int(round(py + oy)) % size
                        height[iy * size + ix] += amplitude * taper * weight
    return height


def clamp_byte(value: float) -> int:
    return max(0, min(255, int(round(value))))


def build_maps(size: int, height: array) -> tuple[bytes, bytes, bytes]:
    albedo = bytearray(size * size * 3)
    normal = bytearray(size * size * 3)
    orm = bytearray(size * size * 3)
    for y in range(size):
        row = y * size
        up = ((y - 1) % size) * size
        down = ((y + 1) % size) * size
        half = size // 2
        for x in range(size):
            index = row + x
            cream = x >= half
            region_start = half if cream else 0
            local_x = x - region_start
            left = row + region_start + ((local_x - 1) % half)
            right = row + region_start + ((local_x + 1) % half)
            h = height[index]
            fine = hash01(x, y, SEED ^ 0xA17A5) - 0.5
            # 5–8% authored value travel keeps directional feather strokes
            # visible in customize/title close-ups; generated mipmaps collapse
            # it cleanly before runner distance, avoiding shimmer.
            pigment = h * (360.0 if cream else 390.0) + fine * (1.5 if cream else 1.3)
            offset = index * 3
            base = (237.0, 232.0, 219.0) if cream else (224.0, 229.0, 236.0)
            albedo[offset] = clamp_byte(base[0] + pigment)
            albedo[offset + 1] = clamp_byte(base[1] + pigment * 0.94)
            albedo[offset + 2] = clamp_byte(base[2] + pigment * 0.82)

            dx = (height[right] - height[left]) * 10.0
            dy = (height[down + x] - height[up + x]) * 10.0
            nz = 1.0 / math.sqrt(dx * dx + dy * dy + 1.0)
            nx = -dx * nz
            ny = -dy * nz
            normal[offset] = clamp_byte((nx * 0.5 + 0.5) * 255.0)
            normal[offset + 1] = clamp_byte((ny * 0.5 + 0.5) * 255.0)
            normal[offset + 2] = clamp_byte((nz * 0.5 + 0.5) * 255.0)

            orm[offset] = clamp_byte(246.0 - max(0.0, -h) * 190.0)
            roughness = 202.0 if cream else 217.0
            orm[offset + 1] = clamp_byte(roughness + (0.5 - fine) * 5.0 + h * 220.0)
            orm[offset + 2] = 0
    return bytes(albedo), bytes(normal), bytes(orm)


def png_chunk(name: bytes, payload: bytes) -> bytes:
    return struct.pack(">I", len(payload)) + name + payload + struct.pack(
        ">I", zlib.crc32(name + payload) & 0xFFFFFFFF
    )


def encode_rgb_png(size: int, pixels: bytes) -> bytes:
    stride = size * 3
    rows = bytearray((stride + 1) * size)
    for y in range(size):
        target = y * (stride + 1)
        rows[target] = 0
        source = y * stride
        rows[target + 1: target + 1 + stride] = pixels[source: source + stride]
    header = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", header)
        + png_chunk(b"IDAT", zlib.compress(bytes(rows), 9))
        + png_chunk(b"IEND", b"")
    )


def write_map(name: str, png: bytes) -> None:
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    source = SOURCE_DIR / name
    runtime = RUNTIME_DIR / name
    source.write_bytes(png)
    shutil.copyfile(source, runtime)
    print(f"[hero-texture] {name} bytes={len(png)}")


def main() -> None:
    args = parse_args()
    if args.size != SIZE:
        raise SystemExit(f"hero texture contract requires {SIZE}, got {args.size}")
    height = build_height(args.size)
    albedo, normal, orm = build_maps(args.size, height)
    write_map("hero_penguin_v1_albedo.png", encode_rgb_png(args.size, albedo))
    write_map("hero_penguin_v1_normal.png", encode_rgb_png(args.size, normal))
    write_map("hero_penguin_v1_orm.png", encode_rgb_png(args.size, orm))


if __name__ == "__main__":
    main()
