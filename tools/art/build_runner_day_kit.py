#!/usr/bin/env python3
"""Deterministically build/export Waddle Wars runner DAY authored kit."""

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
GENERATOR = ROOT / "art_src/runner/day/generate_day_kit.py"
TEXTURE_GENERATOR = ROOT / "tools/art/generate_runner_day_textures.py"
SOURCE = ROOT / "art_src/runner/day/runner_day_kit_v1.blend"
EXPORTER = ROOT / "tools/art/blender_export.py"
VALIDATOR = ROOT / "tools/art/validate_glb.mjs"
FRAGMENT = ROOT / "data/art/fragments/runner_day_kit_v1.json"
RUNTIME_ROOT = ROOT / "assets/art/runner/day"
TEXTURE_ROOT = RUNTIME_ROOT / "textures"
VERSION = "5.2.0"
TRIM_REFERENCE = ROOT / "art_src/runner/day/runner_day_trim_reference_v1.png"
TRIM_PROMPT = ROOT / "art_src/runner/day/runner_day_trim_reference_v1.prompt.md"

JOBS = [
    ("runner_day_barrier_v1", "obstacle", [3.0, 1.5, 1.1], 1500, 5000),
    ("runner_day_cargo_stack_v1", "repeated_prop", [4.5, 3.5, 2.5], 300, 1500),
    ("runner_day_deck_kerb_v1", "repeated_prop", [12.25, 6.5, 1.6], 300, 1500),
    ("runner_day_deck_kerb_b_v1", "repeated_prop", [12.25, 6.5, 1.6], 300, 1500),
    ("runner_day_deck_kerb_c_v1", "repeated_prop", [12.25, 6.5, 1.6], 300, 1500),
    ("runner_day_gantry_v1", "obstacle", [11.5, 2.0, 5.5], 1500, 5000),
    ("runner_day_iceberg_cluster_v1", "repeated_prop", [18.0, 10.0, 11.0], 300, 1500),
    ("runner_day_icebreaker_landmark_v1", "landmark", [16.0, 22.0, 18.0], 10000, 30000),
    ("runner_day_radar_landmark_v1", "landmark", [14.0, 12.0, 15.0], 10000, 30000),
    ("runner_day_ramp_v1", "obstacle", [3.2, 4.5, 2.0], 1500, 5000),
    ("runner_day_research_hub_landmark_v1", "landmark", [25.0, 17.0, 15.0], 10000, 30000),
    ("runner_day_research_lab_v1", "repeated_prop", [11.0, 6.0, 5.5], 300, 1500),
    ("runner_day_signal_pylon_v1", "repeated_prop", [2.5, 3.0, 4.2], 300, 1500),
    ("runner_day_snowcat_v1", "obstacle", [2.8, 2.4, 2.6], 1500, 5000),
    ("runner_day_tunnel_shell_v1", "obstacle", [12.5, 6.5, 6.0], 1500, 5000),
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
    print("[day-kit]", " ".join(command))
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


def job_record(asset_id: str, asset_class: str, bounds: list[float], minimum: int,
               maximum: int, source_hash: str) -> dict:
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
        "output": f"assets/art/runner/day/{asset_id}.glb",
        "source": "art_src/runner/day/runner_day_kit_v1.blend",
        "source_sha256": source_hash,
    }


def export_jobs() -> list[dict]:
    source_hash = sha256(SOURCE)
    records = [job_record(*job, source_hash) for job in JOBS]
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


def runtime_entries(records: list[dict], production_ready: bool) -> list[dict]:
    entries = []
    for record in records:
        asset_id = record["id"]
        wrapper = RUNTIME_ROOT / f"{asset_id}.tscn"
        glb = RUNTIME_ROOT / f"{asset_id}.glb"
        if not glb.is_file():
            raise RuntimeError(f"GLB missing: {glb.relative_to(ROOT)}")
        if not wrapper.exists():
            # Wrapper is a deterministic runtime derivative. Create it only
            # after export produced the referenced GLB, so shared Godot scans
            # never observe a broken staged resource during source authoring.
            wrapper.write_text(
                "[gd_scene load_steps=2 format=3]\n\n"
                f"[ext_resource type=\"PackedScene\" path=\"res://assets/art/runner/day/{asset_id}.glb\" id=\"1_art\"]\n\n"
                f"[node name=\"{''.join(word.title() for word in asset_id.split('_'))}\" type=\"Node3D\"]\n\n"
                "[node name=\"Art\" parent=\".\" instance=ExtResource(\"1_art\")]\n",
                encoding="utf-8",
            )
        if not wrapper.is_file():
            raise RuntimeError(f"wrapper missing: {wrapper.relative_to(ROOT)}")
        groups = ["runner", "runner_day", "runner_golden_slice"]
        if record["asset_class"] == "landmark":
            groups.append("landmark")
        elif record["asset_class"] == "obstacle":
            groups.append("obstacle")
        else:
            groups.append("dressing")
        entries.append({
            "groups": sorted(groups),
            "id": asset_id,
            "kind": "scene",
            "license_id": "project_original",
            "path": f"res://assets/art/runner/day/{asset_id}.tscn",
            "production_ready": production_ready,
            "sha256": sha256(wrapper),
            "source_export_id": asset_id,
        })
        entries.append({
            "groups": sorted(groups + ["runtime_mesh"]),
            "id": asset_id + "_mesh",
            "kind": "mesh",
            "license_id": "project_original",
            "path": f"res://assets/art/runner/day/{asset_id}.glb",
            "production_ready": production_ready,
            "sha256": sha256(glb),
            "source_export_id": asset_id,
        })
    anchor = "runner_day_deck_kerb_v1"
    for role in ("albedo", "normal", "orm"):
        texture_id = f"runner_day_surface_{role}_v1"
        path = TEXTURE_ROOT / f"{texture_id}.png"
        entries.append({
            "groups": ["material_family", "runner", "runner_day", "runner_golden_slice"],
            "id": texture_id,
            "kind": "texture",
            "license_id": "project_original",
            "path": f"res://assets/art/runner/day/textures/{texture_id}.png",
            "production_ready": production_ready,
            "sha256": sha256(path),
            "source_export_id": anchor,
        })
    for role in ("shell", "surface"):
        shader_id = f"runner_day_{role}_shader_v1"
        shader_path = RUNTIME_ROOT / "materials" / f"runner_day_{role}_v1.gdshader"
        entries.append({
            "groups": ["material_family", "runner", "runner_day", "runner_golden_slice"],
            "id": shader_id,
            "kind": "resource",
            "license_id": "project_original",
            "path": f"res://assets/art/runner/day/materials/runner_day_{role}_v1.gdshader",
            "production_ready": production_ready,
            "sha256": sha256(shader_path),
            "source_export_id": anchor,
        })
        material_id = f"runner_day_{role}_material_v1"
        path = RUNTIME_ROOT / "materials" / f"runner_day_{role}_v1.tres"
        entries.append({
            "groups": ["material_family", "runner", "runner_day", "runner_golden_slice"],
            "id": material_id,
            "kind": "material",
            "license_id": "project_original",
            "path": f"res://assets/art/runner/day/materials/runner_day_{role}_v1.tres",
            "production_ready": production_ready,
            "sha256": sha256(path),
            "source_export_id": anchor,
        })
    return sorted(entries, key=lambda entry: entry["id"])


def write_fragment(records: list[dict], production_ready: bool) -> None:
    FRAGMENT.parent.mkdir(parents=True, exist_ok=True)
    if not TRIM_REFERENCE.is_file() or not TRIM_PROMPT.is_file():
        raise RuntimeError("runner DAY trim art-direction reference is missing")
    payload = {
        "concepts": [{
            "dimensions": [1254, 1254],
            "generated_on": "2026-08-18",
            "generator": "built-in image_gen.imagegen",
            "id": "runner_day_trim_reference_v1",
            "license_id": "project_original",
            "path": "art_src/runner/day/runner_day_trim_reference_v1.png",
            "prompt_path": "art_src/runner/day/runner_day_trim_reference_v1.prompt.md",
            "sha256": sha256(TRIM_REFERENCE),
            "status": "art_direction_only",
        }],
        "generated_assets": [],
        "runtime_assets": runtime_entries(records, production_ready),
        "source_exports": records,
    }
    FRAGMENT.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"[day-kit] fragment {FRAGMENT.relative_to(ROOT)}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--all", action="store_true", help="rebuild source and every runtime GLB")
    parser.add_argument("--source-only", action="store_true")
    parser.add_argument("--fragment-only", action="store_true")
    parser.add_argument("--production-ready", action="store_true",
                        help="mark runtime records ready only after capture/perf approval")
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
        records = ([job_record(*job, sha256(SOURCE)) for job in JOBS]
                   if args.fragment_only else export_jobs())
        write_fragment(records, args.production_ready)
    except (OSError, RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"[day-kit] FAIL {exc}", file=sys.stderr)
        return 1
    print(f"[day-kit] PASS assets={len(JOBS)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
