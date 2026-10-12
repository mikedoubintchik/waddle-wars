#!/usr/bin/env python3
"""Deterministically build/export the shared expedition item-cache art."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BLENDER = Path(shutil.which("blender") or "/opt/homebrew/bin/blender").resolve()
GENERATOR = ROOT / "art_src/interactives/item_cache/generate_item_cache.py"
TEXTURE_GENERATOR = ROOT / "tools/art/generate_item_cache_textures.py"
SOURCE = ROOT / "art_src/interactives/item_cache/item_cache_v1.blend"
EXPORTER = ROOT / "tools/art/blender_export.py"
VALIDATOR = ROOT / "tools/art/validate_glb.mjs"
RUNTIME_ROOT = ROOT / "assets/art/interactives/item_cache"
TEXTURE_ROOT = RUNTIME_ROOT / "textures"
MATERIAL_ROOT = RUNTIME_ROOT / "materials"
WRAPPER = RUNTIME_ROOT / "item_cache_v1.tscn"
MATERIAL = MATERIAL_ROOT / "item_cache_v1.tres"
FRAGMENT = ROOT / "data/art/fragments/item_cache_v1.json"
VERSION = "5.2.0"

JOBS = [
    ("item_cache_lod0_v1", 1500, 5000),
    ("item_cache_lod1_v1", 250, 1100),
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def env() -> dict[str, str]:
    result = os.environ.copy()
    result.update({"LC_ALL": "C", "LANG": "C", "PYTHONHASHSEED": "0", "TZ": "UTC"})
    return result


def run(command: list[str]) -> None:
    print("[item-cache-build]", " ".join(command))
    subprocess.run(command, cwd=ROOT, env=env(), check=True)


def build_source() -> None:
    if not BLENDER.is_file():
        raise RuntimeError("Blender 5.2.0 LTS not found")
    run([sys.executable, str(TEXTURE_GENERATOR), "--output", str(TEXTURE_ROOT)])
    run([
        str(BLENDER), "--background", "--factory-startup", "--disable-autoexec",
        "--python-exit-code", "1", "--python", str(GENERATOR), "--",
        "--output", str(SOURCE), "--texture-root", str(TEXTURE_ROOT),
    ])


def job_record(asset_id: str, minimum: int, maximum: int,
               source_hash: str) -> dict:
    return {
        "asset_class": "gameplay_interactive" if "lod0" in asset_id else "gameplay_interactive_lod",
        "collection": asset_id,
        "expected": {
            "bounds_meters_max": [1.4, 1.4, 1.4],
            "lod0_triangles_max": maximum,
            "lod0_triangles_min": minimum,
            "pivot_policy": "center",
            "pivot_tolerance_m": 0.01,
            "surfaces_max": 1,
            "texture_size_max": 1024,
        },
        "export_animations": False,
        "forward_axis": "-Z",
        "id": asset_id,
        "license_id": "project_original",
        "output": f"assets/art/interactives/item_cache/{asset_id}.glb",
        "source": "art_src/interactives/item_cache/item_cache_v1.blend",
        "source_sha256": source_hash,
    }


def export_jobs() -> list[dict]:
    source_hash = sha256(SOURCE)
    records = sorted(
        (job_record(asset_id, minimum, maximum, source_hash)
         for asset_id, minimum, maximum in JOBS),
        key=lambda record: record["id"],
    )
    for record in records:
        output = ROOT / record["output"]
        run([
            str(BLENDER), "--background", "--factory-startup", "--disable-autoexec",
            "--python-exit-code", "1", str(SOURCE), "--python", str(EXPORTER), "--",
            "--expected-version", VERSION,
            "--job-json", json.dumps(record, sort_keys=True, separators=(",", ":")),
            "--project-root", str(ROOT),
        ])
        run(["node", str(VALIDATOR), str(output)])
    return records


def write_runtime_support() -> None:
    MATERIAL_ROOT.mkdir(parents=True, exist_ok=True)
    MATERIAL.write_text("""[gd_resource type=\"StandardMaterial3D\" load_steps=4 format=3]

[ext_resource type=\"Texture2D\" path=\"res://assets/art/interactives/item_cache/textures/item_cache_albedo_v1.png\" id=\"1_albedo\"]
[ext_resource type=\"Texture2D\" path=\"res://assets/art/interactives/item_cache/textures/item_cache_normal_v1.png\" id=\"2_normal\"]
[ext_resource type=\"Texture2D\" path=\"res://assets/art/interactives/item_cache/textures/item_cache_orm_v1.png\" id=\"3_orm\"]

[resource]
resource_name = \"Expedition item cache painted atlas\"
albedo_color = Color(1, 1, 1, 1)
albedo_texture = ExtResource(\"1_albedo\")
metallic = 1.0
roughness = 1.0
normal_enabled = true
normal_scale = 0.56
normal_texture = ExtResource(\"2_normal\")
ao_enabled = true
orm_texture = ExtResource(\"3_orm\")
vertex_color_use_as_albedo = true
""", encoding="utf-8")
    RUNTIME_ROOT.mkdir(parents=True, exist_ok=True)
    WRAPPER.write_text("""[gd_scene load_steps=3 format=3]

[ext_resource type=\"PackedScene\" path=\"res://assets/art/interactives/item_cache/item_cache_lod0_v1.glb\" id=\"1_lod0\"]
[ext_resource type=\"PackedScene\" path=\"res://assets/art/interactives/item_cache/item_cache_lod1_v1.glb\" id=\"2_lod1\"]

[node name=\"ItemCacheV1\" type=\"Node3D\"]
metadata/asset_id = \"item_cache_v1\"
metadata/production_ready = false
metadata/semantic_color = \"violet_powerup\"
metadata/shape_cue = \"three_lobed_pod_four_point_aperture\"
metadata/visual_only = true

[node name=\"LOD0\" parent=\".\" instance=ExtResource(\"1_lod0\")]

[node name=\"LOD1\" parent=\".\" instance=ExtResource(\"2_lod1\")]
""", encoding="utf-8")


def runtime_entries(records: list[dict], production_ready: bool) -> list[dict]:
    entries = [
        {
            "groups": ["gameplay", "interactive", "item_cache", "powerup"],
            "id": "item_cache_v1", "kind": "scene", "license_id": "project_original",
            "path": "res://assets/art/interactives/item_cache/item_cache_v1.tscn",
            "production_ready": production_ready, "sha256": sha256(WRAPPER),
            "source_export_id": "item_cache_lod0_v1",
        },
        {
            "groups": ["gameplay", "interactive", "item_cache", "material_family"],
            "id": "item_cache_material_v1", "kind": "material",
            "license_id": "project_original",
            "path": "res://assets/art/interactives/item_cache/materials/item_cache_v1.tres",
            "production_ready": production_ready, "sha256": sha256(MATERIAL),
            "source_export_id": "item_cache_lod0_v1",
        },
    ]
    for record in records:
        output = ROOT / record["output"]
        entries.append({
            "groups": ["gameplay", "interactive", "item_cache", "runtime_mesh"],
            "id": record["id"], "kind": "mesh", "license_id": "project_original",
            "path": "res://" + record["output"],
            "production_ready": production_ready, "sha256": sha256(output),
            "source_export_id": record["id"],
        })
    for role in ("albedo", "normal", "orm"):
        path = TEXTURE_ROOT / f"item_cache_{role}_v1.png"
        entries.append({
            "groups": ["gameplay", "interactive", "item_cache", "material_family"],
            "id": f"item_cache_{role}_v1", "kind": "texture",
            "license_id": "project_original",
            "path": f"res://assets/art/interactives/item_cache/textures/item_cache_{role}_v1.png",
            "production_ready": production_ready, "sha256": sha256(path),
            "source_export_id": "item_cache_lod0_v1",
        })
    return sorted(entries, key=lambda entry: entry["id"])


def write_fragment(records: list[dict], production_ready: bool) -> None:
    if not WRAPPER.is_file() or not MATERIAL.is_file():
        raise RuntimeError("runtime support missing; export before fragment")
    payload = {
        "concepts": [],
        "generated_assets": [],
        "runtime_assets": runtime_entries(records, production_ready),
        "source_exports": records,
    }
    FRAGMENT.parent.mkdir(parents=True, exist_ok=True)
    FRAGMENT.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"[item-cache-build] fragment {FRAGMENT.relative_to(ROOT)} ready={production_ready}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--source-only", action="store_true")
    parser.add_argument("--fragment-only", action="store_true")
    parser.add_argument("--production-ready", action="store_true",
                        help="only after visual/performance signoff")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not (args.all or args.source_only or args.fragment_only):
        raise SystemExit("choose --all, --source-only, or --fragment-only")
    if args.source_only or args.all:
        build_source()
    if args.source_only and not args.all:
        return 0
    if args.fragment_only:
        if not SOURCE.is_file():
            raise RuntimeError(f"source missing: {SOURCE}")
        records = [
            job_record(asset_id, minimum, maximum, sha256(SOURCE))
            for asset_id, minimum, maximum in JOBS
        ]
    else:
        records = export_jobs()
    write_runtime_support()
    write_fragment(records, args.production_ready)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
