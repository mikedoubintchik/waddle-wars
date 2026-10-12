#!/usr/bin/env python3
"""Static clean-import contract for ItemBox's optional authored dependencies.

Runs without Godot/imported resources. This deliberately proves the GDScript
can be scanned from source without class-scope resolution of wrapper/GLB files;
the normal focused Godot test separately proves those resources once imported.
"""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SOURCE_PATH = ROOT / "scripts/gameplay/item_box.gd"
SOURCE = SOURCE_PATH.read_text(encoding="utf-8")
ART_ROOT = "res://assets/art/interactives/item_cache"


def require(label: str, condition: bool) -> None:
    if not condition:
        raise AssertionError(label)
    print(f"[item-cache-fresh-import] PASS {label}")


require(
    "no class-scope authored preload",
    not re.search(r"preload\s*\(\s*[\"']" + re.escape(ART_ROOT), SOURCE),
)
require(
    "no typed preload resource constants",
    "const CACHE_SCENE: PackedScene = preload" not in SOURCE
    and "const CACHE_MATERIAL: StandardMaterial3D = preload" not in SOURCE,
)
require(
    "path-only class contract",
    "const CACHE_SCENE_PATH :=" in SOURCE
    and "const CACHE_MATERIAL_PATH :=" in SOURCE,
)
require(
    "lazy existence guards",
    'ResourceLoader.exists(CACHE_SCENE_PATH, "PackedScene")' in SOURCE
    and 'ResourceLoader.exists(CACHE_MATERIAL_PATH, "StandardMaterial3D")' in SOURCE,
)
require(
    "cached runtime loads",
    SOURCE.count("ResourceLoader.CACHE_MODE_REUSE") >= 2
    and "static var _cache_scene: PackedScene = null" in SOURCE
    and "static var _cache_material: StandardMaterial3D = null" in SOURCE,
)
require(
    "explicit scene-loader seam",
    "static func preload_authored_visual() -> bool:" in SOURCE
    and "if preload_authored_visual():" in SOURCE,
)
require(
    "behind-overlay warmup registration",
    "ShaderWarmup.register_external_probe(instance.mesh, _cache_material)" in SOURCE
    and "static var _cache_warmup_registered: bool = false" in SOURCE,
)

print("ITEM_CACHE_FRESH_IMPORT PASS")
