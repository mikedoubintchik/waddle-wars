#!/usr/bin/env python3
"""Finish one isolated SVG raster with the shipped font; no new illustration.

Use the bundled Python/Pillow runtime. --project is the minimal project copied
for raster_feature_graphic.gd, not the game project. Outputs must be fresh.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, __version__ as pillow_version


BASE = Path("tools/release/store_assets")
INPUTS = (
    "assets/icons/icon.svg",
    "assets/fonts/AtkinsonHyperlegibleNext-wght.ttf",
    "assets/fonts/AtkinsonHyperlegibleNext-OFL.txt",
    "scripts/ui/main_menu.gd",
    str(BASE / "feature_graphic.template.svg"),
    str(BASE / "raster_feature_graphic.gd"),
    str(BASE / "make_feature_graphic.py"),
)
VECTOR_INPUTS = (INPUTS[0], INPUTS[3], INPUTS[4], INPUTS[5])
TEXT = (
    ("Waddle Wars:", 72, 176, 72, "Bold", "#f4faff"),
    ("Penguin Panic", 72, 255, 53, "Bold", "#7fd0f7"),
    ("OUTRUN THE AVALANCHE", 72, 347, 30, "SemiBold", "#f5c542"),
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def generate(project: Path) -> dict:
    project = project.resolve(strict=True)
    directory = project / BASE
    output = directory / "feature-graphic-1024x500.png"
    receipt_path = directory / "feature_graphic_receipt.json"
    if output.exists() or receipt_path.exists():
        raise ValueError("Fresh feature graphic outputs required")
    inputs = {name: sha256(project / name) for name in INPUTS}
    raster = directory / "feature-vector-raster.png"
    metadata = json.loads((directory / "feature-vector-raster.json").read_text())
    if metadata.get("width") != 1024 or metadata.get("height") != 500 \
            or metadata.get("raster_sha256") != sha256(raster):
        raise ValueError("Vector raster metadata mismatch")
    if metadata.get("inputs_sha256") != {name: inputs[name] for name in VECTOR_INPUTS}:
        raise ValueError("Vector raster source binding mismatch")
    with Image.open(raster) as original:
        original.load()
        if original.size != (1024, 500) or original.mode != "RGB":
            raise ValueError("Vector raster must be 1024x500 RGB")
        image = original.copy()
    draw = ImageDraw.Draw(image)
    typography = []
    for text, x, baseline, size, weight, color in TEXT:
        font = ImageFont.truetype(str(project / INPUTS[1]), size)
        font.set_variation_by_name(weight)
        bounds = draw.textbbox((x, baseline), text, font=font, anchor="ls", stroke_width=1)
        if bounds[0] < 64 or bounds[2] > 626 or bounds[1] < 64 or bounds[3] > 380:
            raise ValueError("Lettering exceeds its composition budget")
        draw.text((x, baseline + 3), text, font=font, anchor="ls", fill="#06132b", stroke_width=1)
        draw.text((x, baseline), text, font=font, anchor="ls", fill=color)
        typography.append({"text": text, "font_size": size, "weight": weight,
                           "baseline": [x, baseline], "bounds": list(bounds)})
    if inputs != {name: sha256(project / name) for name in INPUTS}:
        raise ValueError("Generation inputs changed")
    with output.open("xb") as handle:
        image.save(handle, format="PNG", optimize=False, compress_level=9)
    receipt = {
        "schema_version": 1,
        "state": "generated_unsubmitted",
        "store_ready": False,
        "app_name": "Waddle Wars: Penguin Panic",
        "scope": "existing_vector_mark_and_glyph_with_shipped_font_lettering",
        "inputs_sha256": inputs,
        "renderer": {"godot_version": metadata["godot_version"],
                     "pillow_version": pillow_version,
                     "vector_raster_sha256": sha256(raster)},
        "typography": typography,
        "output": {"path": str(BASE / output.name), "sha256": sha256(output),
                   "width": 1024, "height": 500, "format": "RGB8",
                   "alpha": False, "opaque": True},
    }
    # Exclusive receipt creation preserves any unexpected prior generation.
    with receipt_path.open("x", encoding="utf-8") as handle:
        handle.write(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    return receipt


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True)
    args = parser.parse_args()
    try:
        receipt = generate(args.project)
    except (OSError, ValueError, KeyError) as error:
        parser.exit(1, "Feature graphic generation failed: " + str(error) + "\n")
    print("generated_unsubmitted; store_ready=false; output_sha256=" + receipt["output"]["sha256"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
