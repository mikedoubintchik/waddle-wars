#!/usr/bin/env python3
"""Deterministically build/export Glacier Gauntlet authored runtime art."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BLENDER = Path(shutil.which("blender") or "/opt/homebrew/bin/blender").resolve()
GENERATOR = ROOT / "art_src/courses/glacier/generate_glacier_kit.py"
TEXTURE_GENERATOR = ROOT / "tools/art/generate_glacier_textures.py"
SOURCE = ROOT / "art_src/courses/glacier/glacier_gauntlet_kit_v1.blend"
EXPORTER = ROOT / "tools/art/blender_export.py"
VALIDATOR = ROOT / "tools/art/validate_glb.mjs"
FRAGMENT = ROOT / "data/art/fragments/glacier_gauntlet_v1.json"
RUNTIME_ROOT = ROOT / "assets/art/courses/glacier"
TEXTURE_ROOT = RUNTIME_ROOT / "textures"
MATERIAL_ROOT = RUNTIME_ROOT / "materials"
PROFILE = ROOT / "data/art/course_profiles/glacier_gauntlet_v1.tres"
VERSION = "5.2.0"

# id, class, maximum XYZ bounds in Blender authoring axes, triangle min/max.
JOBS = [
    ("glacier_edge_kerb_v1", "repeated_prop", [1.5, 6.5, 2.0], 300, 1500),
    ("glacier_surface_inlay_v1", "repeated_prop", [2.5, 6.5, 0.5], 300, 1500),
    ("glacier_track_skin_patch_v1", "repeated_prop", [10.0, 8.0, 0.3], 300, 1500),
    ("glacier_route_beacon_v1", "repeated_prop", [2.5, 2.5, 4.5], 300, 1500),
    ("glacier_route_flag_v1", "repeated_prop", [2.5, 1.5, 4.0], 300, 1500),
    ("glacier_snow_fence_v1", "repeated_prop", [6.0, 3.5, 3.0], 300, 1500),
    ("glacier_expedition_crate_v1", "repeated_prop", [2.5, 2.5, 2.0], 300, 1500),
    ("glacier_rescue_sled_v1", "repeated_prop", [3.0, 7.0, 2.0], 300, 1500),
    ("glacier_field_tent_v1", "repeated_prop", [6.0, 5.5, 4.0], 300, 1500),
    ("glacier_field_lab_v1", "repeated_prop", [10.0, 12.0, 6.0], 300, 1500),
    ("glacier_camp_lamp_v1", "repeated_prop", [3.0, 3.0, 5.0], 300, 1500),
    ("glacier_weather_mast_v1", "repeated_prop", [3.0, 3.0, 6.0], 300, 1500),
    ("glacier_ice_spire_v1", "repeated_prop", [8.0, 8.0, 8.0], 300, 1500),
    ("glacier_ice_boulder_v1", "repeated_prop", [5.0, 5.0, 4.0], 300, 1500),
    ("glacier_snowbank_v1", "repeated_prop", [7.0, 4.0, 2.0], 300, 1500),
    ("glacier_layered_ridge_v1", "repeated_prop", [100.0, 24.0, 44.0], 300, 1500),
    ("glacier_cave_buttress_v1", "repeated_prop", [5.5, 5.5, 10.0], 300, 1500),
    ("glacier_duck_gate_v1", "obstacle", [18.0, 3.0, 5.0], 1500, 5000),
    ("glacier_snowball_warning_v1", "obstacle", [7.0, 3.0, 5.0], 1500, 5000),
    ("glacier_cracking_ice_marker_v1", "obstacle", [9.0, 3.0, 4.0], 1500, 5000),
    ("glacier_boost_marker_v1", "obstacle", [7.0, 6.5, 3.0], 1500, 5000),
    ("glacier_ice_arch_landmark_v1", "landmark", [40.0, 15.0, 22.0], 10000, 30000),
    ("glacier_frozen_fall_landmark_v1", "landmark", [40.0, 18.0, 24.0], 10000, 30000),
    ("glacier_summit_station_landmark_v1", "landmark", [42.0, 18.0, 16.0], 10000, 30000),
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
    print("[glacier-kit]", " ".join(command))
    subprocess.run(command, cwd=ROOT, env=env(), check=True)


def build_source() -> None:
    if not BLENDER.is_file():
        raise RuntimeError("Blender 5.2.0 LTS not found")
    run([sys.executable, str(TEXTURE_GENERATOR), "--output", str(TEXTURE_ROOT)])
    run([
        str(BLENDER), "--background", "--factory-startup", "--disable-autoexec",
        "--python-exit-code", "1",
        "--python", str(GENERATOR), "--", "--output", str(SOURCE),
        "--texture-root", str(TEXTURE_ROOT),
    ])


def job_record(asset_id: str, asset_class: str, bounds: list[float],
               minimum: int, maximum: int, source_hash: str) -> dict:
    return {
        "asset_class": asset_class,
        "collection": asset_id,
        "expected": {
            "bounds_meters_max": bounds,
            "lod0_triangles_max": maximum,
            "lod0_triangles_min": minimum,
            "pivot_policy": "ground_center",
            "pivot_tolerance_m": 0.01,
            "surfaces_max": 1 if asset_class != "landmark" else 3,
            "texture_size_max": 2048,
        },
        "export_animations": False,
        "forward_axis": "-Z",
        "id": asset_id,
        "license_id": "project_original",
        "output": f"assets/art/courses/glacier/{asset_id}.glb",
        "source": "art_src/courses/glacier/glacier_gauntlet_kit_v1.blend",
        "source_sha256": source_hash,
    }


def export_jobs() -> list[dict]:
    source_hash = sha256(SOURCE)
    records = sorted(
        (job_record(*job, source_hash) for job in JOBS), key=lambda record: record["id"]
    )
    for record in records:
        output = ROOT / record["output"]
        run([
            str(BLENDER), "--background", "--factory-startup", "--disable-autoexec",
            "--python-exit-code", "1",
            str(SOURCE), "--python", str(EXPORTER), "--",
            "--expected-version", VERSION,
            "--job-json", json.dumps(record, sort_keys=True, separators=(",", ":")),
            "--project-root", str(ROOT),
        ])
        run(["node", str(VALIDATOR), str(output)])
    return records


def write_runtime_support() -> None:
    MATERIAL_ROOT.mkdir(parents=True, exist_ok=True)
    material_path = MATERIAL_ROOT / "glacier_surface_v1.tres"
    material_path.write_text("""[gd_resource type=\"StandardMaterial3D\" load_steps=4 format=3]

[ext_resource type=\"Texture2D\" path=\"res://assets/art/courses/glacier/textures/glacier_surface_albedo_v1.png\" id=\"1_albedo\"]
[ext_resource type=\"Texture2D\" path=\"res://assets/art/courses/glacier/textures/glacier_surface_normal_v1.png\" id=\"2_normal\"]
[ext_resource type=\"Texture2D\" path=\"res://assets/art/courses/glacier/textures/glacier_surface_orm_v1.png\" id=\"3_orm\"]

[resource]
resource_name = \"Glacier Gauntlet painted surface\"
albedo_color = Color(1, 1, 1, 1)
albedo_texture = ExtResource(\"1_albedo\")
metallic = 1.0
roughness = 1.0
normal_enabled = true
normal_scale = 0.48
normal_texture = ExtResource(\"2_normal\")
ao_enabled = true
orm_texture = ExtResource(\"3_orm\")
vertex_color_use_as_albedo = true
""", encoding="utf-8")
    for asset_id, *_rest in JOBS:
        wrapper = RUNTIME_ROOT / f"{asset_id}.tscn"
        wrapper.write_text(f"""[gd_scene load_steps=2 format=3]

[ext_resource type=\"PackedScene\" path=\"res://assets/art/courses/glacier/{asset_id}.glb\" id=\"1_art\"]

[node name=\"{''.join(piece.title() for piece in asset_id.split('_'))}\" type=\"Node3D\"]

[node name=\"Art\" parent=\".\" instance=ExtResource(\"1_art\")]
""", encoding="utf-8")


def runtime_entries(records: list[dict], production_ready: bool) -> list[dict]:
    entries = []
    for record in records:
        asset_id = record["id"]
        wrapper = RUNTIME_ROOT / f"{asset_id}.tscn"
        glb = RUNTIME_ROOT / f"{asset_id}.glb"
        if not wrapper.is_file() or not glb.is_file():
            raise RuntimeError(f"runtime pair missing for {asset_id}")
        groups = ["course", "course_glacier", "glacier_gauntlet"]
        groups.append("landmark" if record["asset_class"] == "landmark"
                      else "obstacle" if record["asset_class"] == "obstacle"
                      else "dressing")
        entries.extend([
            {
                "groups": sorted(groups), "id": asset_id, "kind": "scene",
                "license_id": "project_original",
                "path": f"res://assets/art/courses/glacier/{asset_id}.tscn",
                "production_ready": production_ready, "sha256": sha256(wrapper),
                "source_export_id": asset_id,
            },
            {
                "groups": sorted(groups + ["runtime_mesh"]),
                "id": asset_id + "_mesh", "kind": "mesh",
                "license_id": "project_original",
                "path": f"res://assets/art/courses/glacier/{asset_id}.glb",
                "production_ready": production_ready, "sha256": sha256(glb),
                "source_export_id": asset_id,
            },
        ])
    anchor = "glacier_edge_kerb_v1"
    for role in ("albedo", "normal", "orm"):
        asset_id = f"glacier_surface_{role}_v1"
        path = TEXTURE_ROOT / f"{asset_id}.png"
        entries.append({
            "groups": ["course", "course_glacier", "glacier_gauntlet", "material_family"],
            "id": asset_id, "kind": "texture", "license_id": "project_original",
            "path": f"res://assets/art/courses/glacier/textures/{asset_id}.png",
            "production_ready": production_ready, "sha256": sha256(path),
            "source_export_id": anchor,
        })
    material = MATERIAL_ROOT / "glacier_surface_v1.tres"
    entries.append({
        "groups": ["course", "course_glacier", "glacier_gauntlet", "material_family"],
        "id": "glacier_surface_material_v1", "kind": "material",
        "license_id": "project_original",
        "path": "res://assets/art/courses/glacier/materials/glacier_surface_v1.tres",
        "production_ready": production_ready, "sha256": sha256(material),
        "source_export_id": anchor,
    })
    # CourseVisualProfile lives under data/art like the runner profiles. It is
    # config, not an assets/art runtime payload, so the strict ArtCatalog does
    # not register it. The focused contract validates it independently.
    if not PROFILE.is_file():
        raise RuntimeError(f"course profile missing: {PROFILE.relative_to(ROOT)}")
    return sorted(entries, key=lambda entry: entry["id"])


def write_fragment(records: list[dict], production_ready: bool) -> None:
    FRAGMENT.parent.mkdir(parents=True, exist_ok=True)
    profile_text = PROFILE.read_text(encoding="utf-8")
    updated_profile = re.sub(
        r"^approved_for_runtime = (?:true|false)$",
        f"approved_for_runtime = {str(production_ready).lower()}",
        profile_text,
        flags=re.MULTILINE,
    )
    if updated_profile == profile_text and (
            f"approved_for_runtime = {str(production_ready).lower()}" not in profile_text):
        raise RuntimeError("course profile readiness field missing")
    PROFILE.write_text(updated_profile, encoding="utf-8")
    payload = {
        "concepts": [],
        "generated_assets": [],
        "runtime_assets": runtime_entries(records, production_ready),
        "source_exports": records,
    }
    FRAGMENT.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"[glacier-kit] fragment {FRAGMENT.relative_to(ROOT)}")


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
        print("use --all, --source-only, or --fragment-only", file=sys.stderr)
        return 2
    try:
        if not args.fragment_only:
            build_source()
        if args.source_only:
            return 0
        records = (sorted(
            (job_record(*job, sha256(SOURCE)) for job in JOBS),
            key=lambda record: record["id"],
        )
                   if args.fragment_only else export_jobs())
        write_runtime_support()
        write_fragment(records, args.production_ready)
    except (OSError, RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"[glacier-kit] FAIL {exc}", file=sys.stderr)
        return 1
    print(f"[glacier-kit] PASS assets={len(JOBS)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
