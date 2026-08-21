#!/usr/bin/env python3
"""Derive tileable, de-lit hero feather maps from reviewed source swatches.

Source PNGs remain source-only concepts. This authoring step crops, de-lights,
periodicizes, neutralizes, and derives 1024 albedo/normal/ORM atlas maps. Normal
game builds consume committed outputs and never require Pillow/NumPy.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

try:
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter
except ImportError as exc:  # pragma: no cover - authoring environment guard.
    raise SystemExit(
        "V11 material derivation needs authoring-only Pillow and NumPy; "
        "normal Godot builds do not run this tool"
    ) from exc


ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = ROOT / "art_src/characters/material_sources"
SOURCE_TEXTURE_ROOT = ROOT / "art_src/characters/textures"
RUNTIME_TEXTURE_ROOT = ROOT / "assets/art/characters/textures"
DARK_SOURCE = SOURCE_ROOT / "hero_penguin_feather_dark_source_v1.png"
CREAM_SOURCE = SOURCE_ROOT / "hero_penguin_feather_cream_source_v1.png"
EXPECTED_SOURCE_SHA = {
    DARK_SOURCE.name: "4c811fb6203763d7ec82615644b43fa9b522dd83d3bc681a7e59273547678803",
    CREAM_SOURCE.name: "e2ae5502a33d62ed0fa94086102e43349163bc357bc15263b60e0421ed1a8e02",
}
ATLAS_SIZE = 1024
TILE_WIDTH = 512
TILE_HEIGHT = 1024
WORK_WIDTH = 640
WORK_HEIGHT = 1280


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir", type=Path,
        default=Path("/tmp/waddle-hero-penguin-v11-static/material"),
        help="review outputs; safe default stays outside repository",
    )
    parser.add_argument(
        "--apply", action="store_true",
        help="promote reviewed maps to art_src + runtime texture paths",
    )
    return parser.parse_args()


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify_sources() -> None:
    for path, expected in ((DARK_SOURCE, EXPECTED_SOURCE_SHA[DARK_SOURCE.name]),
                           (CREAM_SOURCE, EXPECTED_SOURCE_SHA[CREAM_SOURCE.name])):
        if not path.is_file():
            raise RuntimeError(f"missing source swatch: {path.relative_to(ROOT)}")
        actual = file_sha256(path)
        if actual != expected:
            raise RuntimeError(
                f"stale source swatch hash: {path.relative_to(ROOT)} {actual} != {expected}"
            )
        with Image.open(path) as image:
            if image.size != (1254, 1254) or image.mode != "RGB":
                raise RuntimeError(f"unexpected source format: {path.name} {image.mode} {image.size}")


def srgb_to_linear(value: np.ndarray) -> np.ndarray:
    return np.where(value <= 0.04045, value / 12.92,
                    ((value + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(value: np.ndarray) -> np.ndarray:
    value = np.clip(value, 0.0, 1.0)
    return np.where(value <= 0.0031308, value * 12.92,
                    1.055 * np.power(value, 1.0 / 2.4) - 0.055)


def periodicize(work: np.ndarray) -> np.ndarray:
    """Cross-fade unused source overlap so repeat boundaries stay continuous."""
    if work.shape[:2] != (WORK_HEIGHT, WORK_WIDTH):
        raise RuntimeError(f"unexpected work shape: {work.shape}")
    horizontal = np.empty((WORK_HEIGHT, TILE_WIDTH) + work.shape[2:], dtype=np.float32)
    overlap_x = WORK_WIDTH - TILE_WIDTH
    horizontal[:, overlap_x:] = work[:, overlap_x:TILE_WIDTH]
    weight_x = np.linspace(0.0, 1.0, overlap_x, dtype=np.float32)
    shape_x = (1, overlap_x) + (1,) * (work.ndim - 2)
    weight_x = weight_x.reshape(shape_x)
    horizontal[:, :overlap_x] = (
        work[:, TILE_WIDTH:TILE_WIDTH + overlap_x] * (1.0 - weight_x)
        + work[:, :overlap_x] * weight_x
    )

    output = np.empty((TILE_HEIGHT, TILE_WIDTH) + work.shape[2:], dtype=np.float32)
    overlap_y = WORK_HEIGHT - TILE_HEIGHT
    output[overlap_y:] = horizontal[overlap_y:TILE_HEIGHT]
    weight_y = np.linspace(0.0, 1.0, overlap_y, dtype=np.float32)
    shape_y = (overlap_y, 1) + (1,) * (work.ndim - 2)
    weight_y = weight_y.reshape(shape_y)
    output[:overlap_y] = (
        horizontal[TILE_HEIGHT:TILE_HEIGHT + overlap_y] * (1.0 - weight_y)
        + horizontal[:overlap_y] * weight_y
    )
    return output


def resize_source(path: Path) -> np.ndarray:
    with Image.open(path) as source:
        source = source.convert("RGB")
        crop_width = source.height // 2
        left = (source.width - crop_width) // 2
        source = source.crop((left, 0, left + crop_width, source.height))
        source = source.resize((WORK_WIDTH, WORK_HEIGHT), Image.Resampling.LANCZOS)
        return np.asarray(source, dtype=np.float32) / 255.0


def derive_tile(path: Path, cream: bool) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    linear = srgb_to_linear(resize_source(path))
    luminance = (linear[..., 0] * 0.2126 + linear[..., 1] * 0.7152
                 + linear[..., 2] * 0.0722).astype(np.float32)
    low = np.asarray(
        Image.fromarray(np.rint(np.clip(luminance, 0.0, 1.0) * 255.0).astype(np.uint8),
                        mode="L").filter(ImageFilter.GaussianBlur(38.0)),
        dtype=np.float32,
    ) / 255.0
    detail = np.clip(luminance / np.maximum(0.025, low), 0.72, 1.30)
    contrast = 0.72 if cream else 0.58
    log_height = np.clip(np.log(np.maximum(0.01, detail)) * contrast, -0.13, 0.13)

    # Semantic instance palettes own species color. Source contributes neutral
    # directional fibers and restrained warm/cool bias, never baked lighting.
    base = np.array((0.88, 0.84, 0.76) if cream else (0.74, 0.79, 0.86),
                    dtype=np.float32)
    albedo_linear = np.clip(base[None, None, :] * np.exp(log_height[..., None] * 0.24),
                            0.64, 1.0)
    albedo = periodicize(albedo_linear)
    height = periodicize(log_height)

    normal_height = height
    for _pass in range(2):
        normal_height = (
            normal_height * 4.0
            + np.roll(normal_height, 1, axis=0)
            + np.roll(normal_height, -1, axis=0)
            + np.roll(normal_height, 1, axis=1)
            + np.roll(normal_height, -1, axis=1)
        ) / 8.0
    dx = np.roll(normal_height, -1, axis=1) - np.roll(normal_height, 1, axis=1)
    dy = np.roll(normal_height, -1, axis=0) - np.roll(normal_height, 1, axis=0)
    strength = 2.0 if cream else 2.5
    normal = np.stack((-dx * strength, -dy * strength, np.ones_like(height)), axis=-1)
    normal /= np.maximum(1e-6, np.linalg.norm(normal, axis=-1, keepdims=True))
    normal = normal * 0.5 + 0.5

    ao = np.clip(0.975 + np.minimum(0.0, height) * 0.32, 0.88, 1.0)
    roughness_base = 0.79 if cream else 0.84
    roughness = np.clip(roughness_base - height * 0.16, 0.72, 0.90)
    orm = np.stack((ao, roughness, np.zeros_like(height)), axis=-1)
    return albedo, normal, orm


def encode_rgb(array: np.ndarray, *, linear: bool) -> Image.Image:
    value = linear_to_srgb(array) if linear else np.clip(array, 0.0, 1.0)
    return Image.fromarray(np.rint(value * 255.0).astype(np.uint8), mode="RGB")


def atlas(left: np.ndarray, right: np.ndarray) -> np.ndarray:
    result = np.empty((ATLAS_SIZE, ATLAS_SIZE, 3), dtype=np.float32)
    result[:, :TILE_WIDTH] = left
    result[:, TILE_WIDTH:] = right
    return result


def labeled_panel(image: Image.Image, label: str, size: tuple[int, int]) -> Image.Image:
    panel = Image.new("RGB", (size[0], size[1] + 28), "#343b43")
    panel.paste(image.resize(size, Image.Resampling.LANCZOS), (0, 28))
    ImageDraw.Draw(panel).text((8, 7), label, fill="#f1f4f6")
    return panel


def tile_preview(tile: Image.Image) -> Image.Image:
    thumb = tile.resize((192, 384), Image.Resampling.LANCZOS)
    result = Image.new("RGB", (384, 768))
    for y in (0, 384):
        for x in (0, 192):
            result.paste(thumb, (x, y))
    return result


def build_contacts(output_dir: Path, albedo_image: Image.Image,
                   normal_image: Image.Image, orm_image: Image.Image) -> None:
    dark = albedo_image.crop((0, 0, TILE_WIDTH, TILE_HEIGHT))
    cream = albedo_image.crop((TILE_WIDTH, 0, ATLAS_SIZE, TILE_HEIGHT))
    tile_panels = [
        labeled_panel(tile_preview(dark), "DARK 2x2 SEAM", (384, 768)),
        labeled_panel(tile_preview(cream), "CREAM 2x2 SEAM", (384, 768)),
    ]
    tile_contact = Image.new("RGB", (784, 796), "#343b43")
    tile_contact.paste(tile_panels[0], (0, 0))
    tile_contact.paste(tile_panels[1], (400, 0))
    tile_contact.save(output_dir / "hero_penguin_v11_material_tiles.png", optimize=True)

    panels: list[Image.Image] = []
    for size in (1024, 512, 256, 128):
        mip = albedo_image.resize((size, size), Image.Resampling.LANCZOS)
        panels.append(labeled_panel(mip, f"ALBEDO MIP {size}", (256, 256)))
    panels.append(labeled_panel(normal_image, "NORMAL", (256, 256)))
    roughness = orm_image.getchannel("G").convert("RGB")
    panels.append(labeled_panel(roughness, "ROUGHNESS", (256, 256)))
    contact = Image.new("RGB", (816, 584), "#343b43")
    for index, panel in enumerate(panels):
        contact.paste(panel, ((index % 3) * 272, (index // 3) * 292))
    contact.save(output_dir / "hero_penguin_v11_material_mips.png", optimize=True)


def seam_metrics(tile: np.ndarray) -> dict[str, float]:
    horizontal = float(np.mean(np.abs(tile[:, 0] - tile[:, -1])))
    vertical = float(np.mean(np.abs(tile[0] - tile[-1])))
    internal_x = float(np.mean(np.abs(tile[:, 255] - tile[:, 256])))
    internal_y = float(np.mean(np.abs(tile[511] - tile[512])))
    return {
        "repeat_edge_x_mean_abs": horizontal,
        "repeat_edge_y_mean_abs": vertical,
        "internal_x_mean_abs": internal_x,
        "internal_y_mean_abs": internal_y,
    }


def save_outputs(output_dir: Path, apply: bool) -> None:
    dark_albedo, dark_normal, dark_orm = derive_tile(DARK_SOURCE, False)
    cream_albedo, cream_normal, cream_orm = derive_tile(CREAM_SOURCE, True)
    albedo_data = atlas(dark_albedo, cream_albedo)
    normal_data = atlas(dark_normal, cream_normal)
    orm_data = atlas(dark_orm, cream_orm)
    albedo_image = encode_rgb(albedo_data, linear=True)
    normal_image = encode_rgb(normal_data, linear=False)
    orm_image = encode_rgb(orm_data, linear=False)

    output_dir.mkdir(parents=True, exist_ok=True)
    review = {
        "hero_penguin_v1_albedo.png": albedo_image,
        "hero_penguin_v1_normal.png": normal_image,
        "hero_penguin_v1_orm.png": orm_image,
    }
    for name, image in review.items():
        image.save(output_dir / name, optimize=True)
    # Source-proof Blender stills consume reviewed halves only. These remain
    # temporary derivations and are never promoted by --apply.
    for label, bounds in (("dark", (0, 0, TILE_WIDTH, TILE_HEIGHT)),
                          ("cream", (TILE_WIDTH, 0, ATLAS_SIZE, TILE_HEIGHT))):
        albedo_image.crop(bounds).save(
            output_dir / f"hero_penguin_v11_{label}_albedo_tile.png", optimize=True)
        normal_image.crop(bounds).save(
            output_dir / f"hero_penguin_v11_{label}_normal_tile.png", optimize=True)
        orm_image.crop(bounds).save(
            output_dir / f"hero_penguin_v11_{label}_orm_tile.png", optimize=True)
    build_contacts(output_dir, albedo_image, normal_image, orm_image)
    report = {
        "source_sha256": EXPECTED_SOURCE_SHA,
        "dark_albedo": seam_metrics(dark_albedo),
        "cream_albedo": seam_metrics(cream_albedo),
        "atlas_size": [ATLAS_SIZE, ATLAS_SIZE],
        "source_only_inputs": True,
        "production_ready": False,
    }
    (output_dir / "hero_penguin_v11_material_report.json").write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )

    if apply:
        SOURCE_TEXTURE_ROOT.mkdir(parents=True, exist_ok=True)
        RUNTIME_TEXTURE_ROOT.mkdir(parents=True, exist_ok=True)
        for name, image in review.items():
            image.save(SOURCE_TEXTURE_ROOT / name, optimize=True)
            image.save(RUNTIME_TEXTURE_ROOT / name, optimize=True)


def main() -> None:
    args = parse_args()
    verify_sources()
    save_outputs(args.output_dir.resolve(), args.apply)
    print(f"[hero-material-v11] PASS {args.output_dir.resolve()} apply={args.apply}")


if __name__ == "__main__":
    main()
