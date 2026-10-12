#!/usr/bin/env python3
"""Two untimed actual-runner rim-energy frames through the existing atlas route."""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("atlas_route", Path(__file__).with_name("run_hero_v12_atlas_runner_review.py"))
route = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(route)
SCRIPT = "tests/hero_v12_runner_rim_study.gd"
SCENE = "res://tests/hero_v12_runner_rim_study.tscn"
LABELS = ["baseline_current_rim", "rim_startup_energy_2_1"]
FILL_LABELS = ["hero_only_original_rim", "hero_only_low_fill_2_1"]
DIFFUSE_LABEL = "hero_only_low_diffuse_fill_4_2"
HERO_FILL_LAYER = 1 << 18


def float32(value):
    if type(value) not in (int, float):
        raise ValueError("Expected a numeric engine float")
    return struct.pack("<f", value)


def variant_labels(binding: dict) -> list[str]:
    study = binding.get("hero_fill_study", False)
    diffuse = binding.get("hero_fill_diffuse_study", False)
    if type(study) is not bool or type(diffuse) is not bool or (diffuse and not study):
        raise ValueError("Hero-fill study flag must be boolean")
    labels = LABELS + FILL_LABELS if study else LABELS
    if diffuse:
        labels = labels + [DIFFUSE_LABEL]
        if binding.get("hero_fill_diffuse_energy") != 4.2 or binding.get("hero_fill_specular") != 0.0:
            raise ValueError("Expected only the diffuse4.2 energy/specular0 recipe")
    if binding.get("variants") != labels:
        raise ValueError("Expected only explicitly bound rim variants")
    if study and (binding.get("hero_fill_layer") != HERO_FILL_LAYER or binding.get("hero_fill_y_offset") != .9):
        raise ValueError("Expected the private QA layer and .9m hero-fill recipe")
    return labels


def validate_report(report: dict, binding: dict) -> None:
    labels = variant_labels(binding)
    if binding.get("route") != "actual-runner-rim-energy-pair-v1" \
            or binding.get("rim_energy") != 2.1 or binding.get("freeze_after_running_seconds") != 1.0:
        raise ValueError("Expected exactly the bound original-rim-energy study")
    if report.get("passed") is not True or report.get("production_ready") is not False \
            or report.get("source_fidelity_approved") is not False or report.get("performance_measured") is not False \
            or report.get("original_rim_restored") is not True \
            or report.get("candidate_sha256") != binding["candidate_sha256"] \
            or report.get("shader_sha256") != binding["shader_sha256"]:
        raise ValueError("Actual runner rim binding/restoration/approval gate failed")
    before, changed = report.get("state_before"), report.get("state_variant")
    if not isinstance(before, dict) or not isinstance(changed, dict) or not before \
            or report.get("state_after_restore") != before:
        raise ValueError("Original runner state was not restored")
    if {k: v for k, v in before.items() if k != "lighting_environment"} != \
            {k: v for k, v in changed.items() if k != "lighting_environment"}:
        raise ValueError("Runner world, pose, material or camera changed")
    if before.get("engine_time_scale") != 0.0:
        raise ValueError("Expected frozen shader/particle time")
    change = report.get("rim_energy_change", {})
    energy = change.get("before")
    if type(energy) not in (float, int) or not 0 < energy < 2.1 \
            or float32(change.get("after")) != float32(2.1):
        raise ValueError("Expected measured positive blended rim energy versus original2.1")
    lights = before["lighting_environment"]
    expected = copy.deepcopy(lights["state"])
    rows = [row for row in expected if isinstance(row, list) and len(row) == 3
            and row[0] == change.get("light_path") and isinstance(row[2], dict)
            and row[2].get("class") == "OmniLight3D"]
    if len(rows) != 1 or float32(rows[0][2].get("light_energy")) != float32(energy) \
            or not str(rows[0][0]).endswith("/PlayerRim"):
        raise ValueError("Expected the uniquely identified existing PlayerRim")
    rows[0][2]["light_energy"] = change["after"]
    altered = changed["lighting_environment"]
    if altered.get("state") != expected:
        raise ValueError("A light/environment property besides rim energy changed")
    raw = bytes.fromhex(lights["state_bytes_hex"])
    needle = struct.pack("<I", 3) + float32(energy)
    replacement = struct.pack("<I", 3) + float32(2.1)
    expected_raw = raw.replace(needle, replacement)
    if raw.count(needle) != 1 or altered.get("state_bytes_hex") != expected_raw.hex():
        raise ValueError("Exact lighting bytes changed beyond one tagged float32 rim energy")
    for state in (before, changed, *[row.get("state", {}) for row in report.get("frames", [])]):
        for key in ("world", "pose", "material", "camera", "lighting_environment"):
            evidence = state.get(key, {})
            data = bytes.fromhex(evidence.get("state_bytes_hex", ""))
            if not data or hashlib.sha256(data).hexdigest() != evidence.get("sha256"):
                raise ValueError(f"Exact {key} state hash mismatch")
    frames = report.get("frames", [])
    if [row.get("variant") for row in frames] != labels \
            or [row.get("state") for row in frames[:2]] != [before, changed]:
        raise ValueError("Expected exactly the ordered actual frozen runner frames")
    if binding.get("hero_fill_study", False):
        validate_hero_fill(report)
    context = report.get("key_context", {})
    if context.get("seed") != 20260907 or context.get("biome") != 0 \
            or not 10 < context.get("distance", -1) < 30 or not 0.9 < context.get("elapsed", -1) < 2:
        raise ValueError("Expected ordinary sequential day chase near the first running second")


def validate_hero_fill(report: dict) -> None:
    before = report["state_before"]
    audit = report.get("layer_audit", {})
    inventory, paths = audit.get("geometry_inventory", {}), audit.get("hero_paths", [])
    if audit.get("private_bit") != HERO_FILL_LAYER or audit.get("occupied_before") != 0 \
            or not isinstance(inventory, dict) or not inventory or not paths or len(paths) != len(set(paths)) \
            or any(type(mask) is not int or mask & HERO_FILL_LAYER for mask in inventory.values()) \
            or any(path not in inventory or "/AuthoredHeroPenguin/" not in path for path in paths) \
            or not int(audit.get("camera_cull_mask", 0)) & HERO_FILL_LAYER:
        raise ValueError("Private hero-fill layer occupancy/camera/subtree gate failed")
    original = report.get("original_controls", {})
    if original.get("hero_layers") != {path: inventory[path] for path in paths}:
        raise ValueError("Original hero layers do not match actual scene inventory")
    rim_path = report["rim_energy_change"]["light_path"]
    world_before = before["world"]["state"]
    world_by_path = {row[0]: row for row in world_before}
    for path in paths:
        if world_by_path.get(path, [None] * 5)[4][0] != inventory[path]:
            raise ValueError("Declared hero layers differ from the original world snapshot")
    original_lights = {row[0]: row for row in before["lighting_environment"]["state"]}
    for index, frame in enumerate(report["frames"]):
        if frame.get("normalized_state") != before:
            raise ValueError("Normalized bytes changed outside explicitly controlled hero/rim fields")
        expected = copy.deepcopy(original)
        if index in (1, 3):
            expected["rim_energy"] = report["rim_energy_change"]["after"]
        if index == 4:
            expected["rim_energy"] = 4.2
            expected["rim_specular"] = 0.0
        if index >= 2:
            expected["hero_layers"] = {path: mask | HERO_FILL_LAYER for path, mask in original["hero_layers"].items()}
            expected["rim_cull_mask"] = HERO_FILL_LAYER
        if index >= 3:
            target_y = struct.unpack("<f", float32(original["player_global_y"] + .9))[0]
            expected["rim_global_position"][1] = target_y
            expected["rim_local_position"][1] = struct.unpack("<f", float32(
                original["rim_local_position"][1] + target_y - original["rim_global_position"][1]))[0]
        actual = frame.get("controls", {})
        for key in ("rim_energy", "rim_specular") if "rim_specular" in original else ("rim_energy",):
            if float32(actual.get(key)) != float32(expected[key]):
                raise ValueError("Hero-fill energy differs from its exact recipe")
            expected[key] = actual[key]
        for key in ("rim_local_position", "rim_global_position"):
            if len(actual.get(key, [])) != 3 or any(float32(a) != float32(b) for a, b in zip(actual[key], expected[key])):
                raise ValueError("Hero-fill changes more than the .9m vertical offset")
            expected[key] = actual[key]
        if actual != expected:
            raise ValueError("Hero-fill changed masks, original layer bits, basis, or another control")
        # The engine also normalizes these exact fields before var_to_bytes.
        # Independently compare human-readable actual snapshots so the allowed
        # changes are visible, not hidden behind a broad normalized hash.
        state = frame["state"]
        for key in ("pose", "material", "camera", "engine_time_scale", "world_scope"):
            if state.get(key) != before.get(key):
                raise ValueError("Hero-fill changed pose/material/camera or freeze scope")
        world = copy.deepcopy(state["world"]["state"])
        for row in world:
            path = row[0]
            if path in paths:
                if row[4][0] != actual["hero_layers"][path]:
                    raise ValueError("Actual hero layer does not match recorded control")
                row[4][0] = inventory[path]
            if path == rim_path:
                row[1:3] = world_by_path[path][1:3]
        if world != world_before:
            raise ValueError("Hero-fill changed unrelated world state")
        lights = copy.deepcopy(state["lighting_environment"]["state"])
        for row in lights:
            if row[0] == rim_path:
                if float32(row[2]["light_energy"]) != float32(actual["rim_energy"]) \
                        or row[2]["light_cull_mask"] != actual["rim_cull_mask"]:
                    raise ValueError("Actual rim does not match recorded controls")
                if "rim_specular" in actual and float32(row[2]["light_specular"]) != float32(actual["rim_specular"]):
                    raise ValueError("Actual rim specular does not match recorded control")
                row[1] = original_lights[rim_path][1]
                for prop in ("light_energy", "light_cull_mask", "transform", "light_specular"):
                    if prop not in original_lights[rim_path][2]:
                        continue
                    row[2][prop] = original_lights[rim_path][2][prop]
        if lights != before["lighting_environment"]["state"]:
            raise ValueError("Hero-fill changed unrelated lighting/environment state")


def prepare(atlas: Path, output: Path, hero_fill_study: bool = False) -> None:
    route.prepare(atlas, output, "Y03-runner-rim-study", "atlas")
    state, project = route.bound_state(output)
    binding = {"schema_version": 1, "route": "actual-runner-rim-energy-pair-v1",
        "candidate_sha256": state["candidate"]["glb_sha256"],
        "shader_sha256": state["candidate"]["shader_sha256"],
        "source_fixture_hashes": state["fixture_hashes"],
        "atlas_textures": state["atlas_binding"]["textures"],
        "scene_script_sha256": route.sha(project / SCRIPT),
        "capture_output": str(output / "runner_rim_frames"),
        "variants": LABELS + FILL_LABELS + [DIFFUSE_LABEL] if hero_fill_study else LABELS,
        "hero_fill_study": hero_fill_study,
        "rim_energy": 2.1, "freeze_after_running_seconds": 1.0,
        "performance_measured": False, "production_ready": False}
    if hero_fill_study:
        binding.update(hero_fill_layer=HERO_FILL_LAYER, hero_fill_y_offset=.9,
                       hero_fill_diffuse_study=True, hero_fill_diffuse_energy=4.2, hero_fill_specular=0.0)
    path = project / "qa_hero/runner_rim_binding.json"
    route.write_json(path, binding)
    route.write_json(output / "runner_rim_state.json", {"binding": binding,
        "binding_sha256": route.sha(path), "launcher_sha256": route.sha(Path(__file__)), "captured": False})
    route.common.run_engine(project, output / "runner_rim_parser.log",
                           ["--headless", SCENE, "--", "parsercheck=true"], timeout=30)
    print(f"RUNNER RIM STUDY PREPARED; no raster/art/performance approval: {output}")


def capture(output: Path) -> None:
    state, project = route.bound_state(output)
    metadata = json.loads((output / "runner_rim_state.json").read_text())
    if route.sha(project / "qa_hero/runner_rim_binding.json") != metadata["binding_sha256"]:
        raise ValueError("Runner rim binding changed")
    folder = output / "runner_rim_frames"
    if folder.exists():
        raise ValueError("Preserve prior runner rim evidence; prepare a fresh output")
    before_live = {name: route.sha(ROOT / name) for name in route.common.LIVE_FILES}
    route.common.run_engine(project, output / "runner_rim_capture.log",
                           [SCENE, "--", f"output={folder}"])
    if before_live != {name: route.sha(ROOT / name) for name in before_live}:
        raise ValueError("Live sources changed concurrently; inspect isolation")
    verify(output)


def verify(output: Path) -> None:
    state, project = route.bound_state(output)
    metadata = json.loads((output / "runner_rim_state.json").read_text())
    if route.sha(project / "qa_hero/runner_rim_binding.json") != metadata["binding_sha256"]:
        raise ValueError("Runner rim binding changed")
    route.common.check_engine_log(output / "runner_rim_capture.log")
    folder = output / "runner_rim_frames"
    report = json.loads((folder / "report.json").read_text())
    if report.get("binding_sha256") != metadata["binding_sha256"]:
        raise ValueError("Actual capture uses a different runner rim binding")
    validate_report(report, metadata["binding"])
    route.validate_report(report["source_material_report"], state)
    route.validate_report(report["final_material_report"], state)
    for frame in report["frames"]:
        name = frame["file"]
        if Path(name).name != name or route.sha(folder / name) != frame["png_sha256"]:
            raise ValueError("Actual runner PNG missing/changed")
    if len(list(folder.glob("*.png"))) != len(variant_labels(metadata["binding"])):
        raise ValueError("Expected exactly the bound actual runner PNGs")
    metadata.update(captured=True, report_sha256=route.sha(folder / "report.json"),
                    verifier_sha256=route.sha(Path(__file__)), performance_measured=False, production_ready=False)
    route.write_json(output / "runner_rim_verification.json", metadata)
    print(f"ACTUAL RUNNER RIM STUDY PASS; visual interpretation required: {output}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("prepare", "capture", "verify"))
    parser.add_argument("--atlas-dir", type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--hero-fill-study", action="store_true",
                        help="Append hero-only original-rim and lower2.1-fill controls")
    args = parser.parse_args()
    if args.mode == "prepare":
        if args.atlas_dir is None:
            parser.error("prepare requires --atlas-dir")
        prepare(args.atlas_dir.resolve(strict=True), args.output_dir.resolve(), args.hero_fill_study)
    else:
        if args.hero_fill_study:
            parser.error("--hero-fill-study is prepare-only; later modes use the immutable binding")
        {"capture": capture, "verify": verify}[args.mode](args.output_dir.resolve())


if __name__ == "__main__":
    main()
