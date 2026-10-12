#!/usr/bin/env python3
"""Frozen material rasters via the existing strict isolated atlas route.

Prepare/capture intentionally launch Godot only when explicitly invoked. This
tool neither edits live assets nor treats diagnostic variants as production fixes.
Optional studies add a receiver-shadow frame and/or a matched half-key pair to
the unchanged default three.
"""
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
SCRIPT = "tests/hero_v12_atlas_material_diagnostic.gd"
SCENE = "res://tests/hero_v12_atlas_material_diagnostic.tscn"
NORMAL_ANCHOR = "NORMAL_MAP_DEPTH = normal_strength;"
NORMAL_DIAGNOSTIC = "NORMAL_MAP_DEPTH = normal_strength * feather;"
LABELS = ("baseline", "hard_normal_zero", "hard_specular_zero")
RECEIVER_LABEL = "receiver_shadows_disabled"
KEY_LABELS = ("half_key_shadows_received", "half_key_receiver_shadows_disabled")
RENDER_ANCHOR = "render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;"
RENDER_DIAGNOSTIC = RENDER_ANCHOR[:-1] + ", shadows_disabled;"


def shader_float_matches(value, expected: float) -> bool:
    """Compare shader float32 values, not Godot's rounded JSON decimal text."""
    if type(value) not in (float, int):
        return False
    try:
        return struct.pack("<f", value) == struct.pack("<f", expected)
    except (OverflowError, struct.error):
        return False


def normal_variant(source: str) -> str:
    if source.count(NORMAL_ANCHOR) != 1 or "float feather = smoothstep(0.25, 0.75, masks.a);" not in source:
        raise ValueError("Expected exact baseline normal-depth expression and semantic feather mask")
    route.validate_shader_defaults(source)
    return source.replace(NORMAL_ANCHOR, NORMAL_DIAGNOSTIC)


def receiver_shadow_variant(source: str) -> str:
    """Disable receiving shadows only; retain the original lighting and casting."""
    if source.count(RENDER_ANCHOR) != 1 or source.count("render_mode ") != 1:
        raise ValueError("Expected the exact baseline render-mode declaration")
    route.validate_shader_defaults(source)
    return source.replace(RENDER_ANCHOR, RENDER_DIAGNOSTIC)


def variant_labels(binding: dict) -> tuple[str, ...]:
    # Older three-frame evidence predates the optional flag and remains valid.
    study = binding.get("receiver_shadow_study", False)
    key_study = binding.get("key_energy_study", False)
    if type(study) is not bool or type(key_study) is not bool:
        raise ValueError("Optional study flags must be boolean")
    labels = LABELS + (RECEIVER_LABEL,) if study else LABELS
    if key_study:
        labels += KEY_LABELS
        if binding.get("key_energy_values") != {"before": .54, "after": .27}:
            raise ValueError("Key-energy study requires the exact bound .54 to .27 recipe")
    if binding.get("variants") != list(labels):
        raise ValueError("Bound diagnostic variants do not match the optional study")
    if (study or key_study) and not binding.get("receiver_shadows_disabled_shader_sha256"):
        raise ValueError("Receiver-shadow study requires its exact shader hash")
    return labels


def prepare(atlas: Path, output: Path, receiver_shadow_study: bool = False,
            key_energy_study: bool = False) -> None:
    # All package validation, isolated saves, immutable fixture copies, import,
    # and real facade headless preflight come from the existing route.
    shader = (ROOT / route.SHADER).read_text()
    variant = normal_variant(shader)
    receiver_variant = receiver_shadow_variant(shader) if receiver_shadow_study or key_energy_study else None
    route.prepare(atlas, output, "Y03-material-diagnostic", "atlas")
    state, project = route.bound_state(output)
    binding = {"schema_version": 1, "route": "frozen-atlas-material-three-frame-v1",
        "candidate_sha256": state["candidate"]["glb_sha256"],
        "baseline_shader_sha256": state["candidate"]["shader_sha256"],
        "hard_normal_zero_shader_sha256": hashlib.sha256(variant.encode()).hexdigest(),
        "scene_script_sha256": route.sha(project / SCRIPT), "capture_output": str(output / "material_frames"),
        "variants": list((LABELS + (RECEIVER_LABEL,) if receiver_shadow_study else LABELS)
                         + (KEY_LABELS if key_energy_study else ())),
        "receiver_shadow_study": receiver_shadow_study, "frozen_front_frame": 24, "fps": 30,
        "key_energy_study": key_energy_study,
        "production_ready": False, "performance_measured": False}
    if receiver_variant is not None:
        binding["receiver_shadows_disabled_shader_sha256"] = hashlib.sha256(receiver_variant.encode()).hexdigest()
    if key_energy_study:
        binding["key_energy_values"] = {"before": .54, "after": .27}
    labels = variant_labels(binding)
    path = project / "qa_hero/material_diagnostic_binding.json"
    route.write_json(path, binding)
    route.write_json(output / "material_diagnostic_state.json", {"binding": binding,
        "binding_sha256": route.sha(path), "launcher_sha256": route.sha(Path(__file__)), "captured": False})
    # General import discovers resources but does not necessarily parse this
    # new inherited scene. Resolve it explicitly before opening a QA window.
    # This exits before raster/material work and is not a rendered test pass.
    route.common.run_engine(project, output / "material_parser.log",
        ["--headless", SCENE, "--", "parsercheck=true"], timeout=30)
    print(f"PREPARED {len(labels)}-FRAME DIAGNOSTIC; no raster/art/performance approval: {output}")


def validate_report(report: dict, binding: dict) -> None:
    labels = variant_labels(binding)
    if report.get("passed") is not True or report.get("production_ready") is not False \
            or report.get("source_fidelity_approved") is not False or report.get("performance_measured") is not False \
            or report.get("candidate_sha256") != binding["candidate_sha256"] \
            or report.get("geometry_lighting_camera_pose_unchanged") is not (not binding.get("key_energy_study", False)) \
            or report.get("original_material_restored") is not True:
        raise ValueError("Diagnostic binding/state/restoration gate failed")
    frames = report.get("frames", [])
    if [row.get("variant") for row in frames] != list(labels):
        raise ValueError(f"Expected exactly {len(labels)} ordered diagnostic frames")
    before = report.get("state_before")
    if not isinstance(before, dict) or not before or report.get("state_after_restore") != before:
        raise ValueError("Geometry, pose, camera or lights changed across frames")
    half = report.get("half_key_state")
    if binding.get("key_energy_study", False):
        if report.get("geometry_camera_pose_unchanged") is not True:
            raise ValueError("Half-key study must preserve geometry, camera and pose")
        validate_half_key_state(before, half, report.get("key_energy_change", {}))
    for row in frames:
        expected = half if row["variant"] in KEY_LABELS else before
        if row.get("state") != expected:
            raise ValueError("Geometry, pose, camera or lights changed across frames")
    for key in ("pose", "lighting_environment", "camera"):
        evidence = before.get(key, {})
        try:
            raw = bytes.fromhex(evidence["state_bytes_hex"])
        except (KeyError, TypeError, ValueError) as error:
            raise ValueError(f"Exact {key} state bytes missing") from error
        if not raw or hashlib.sha256(raw).hexdigest() != evidence.get("sha256"):
            raise ValueError(f"Exact {key} state hash mismatch")
    pose = report.get("frozen_pose", {})
    if (pose.get("motion"), pose.get("fps"), pose.get("frame"), pose.get("fixed_steps_after_frame_zero"),
            pose.get("automatic_animation_processing")) != ("run", 30, 24, 24, False):
        raise ValueError("Expected the same frozen front frame24 at30Hz")
    materials = [row["material"] for row in frames]
    expected_shaders = [binding["hard_normal_zero_shader_sha256"] if label == "hard_normal_zero"
        else binding["receiver_shadows_disabled_shader_sha256"] if label in (RECEIVER_LABEL, KEY_LABELS[1])
        else binding["baseline_shader_sha256"] for label in labels]
    if [item.get("shader_sha256") for item in materials] != expected_shaders:
        raise ValueError("Shader changes exceed explicitly bound diagnostics")
    base, normal, specular = [item["uniforms"]["state"] for item in materials[:3]]
    if normal != base or specular != {**base, "hard_specular": 0.0} \
            or any(item["uniforms"]["state"] != base for item in materials[3:]) \
            or not all(shader_float_matches(base.get(key), value) for key, value in
                       (("normal_strength", 1.0), ("hard_specular", .5), ("feather_specular", .4))):
        raise ValueError("Textures/feather parameters or unspecified material uniforms changed")


def validate_half_key_state(before: dict, half: dict, change: dict) -> None:
    """Allow exactly one key energy scalar, including its serialized float bits."""
    if not isinstance(half, dict) or not isinstance(change, dict) \
            or not shader_float_matches(change.get("before"), .54) \
            or not shader_float_matches(change.get("after"), .27):
        raise ValueError("Expected bound half-key energy .54 to .27")
    if {k: v for k, v in half.items() if k != "lighting_environment"} != \
            {k: v for k, v in before.items() if k != "lighting_environment"}:
        raise ValueError("Half-key study changed geometry, pose or camera")
    original = before["lighting_environment"]
    altered = half.get("lighting_environment", {})
    expected = copy.deepcopy(original["state"])
    matches = [row for row in expected if isinstance(row, list) and len(row) == 3
               and row[0] == change.get("light_path") and isinstance(row[2], dict)
               and row[2].get("class") == "DirectionalLight3D"]
    if len(matches) != 1 or not shader_float_matches(matches[0][2].get("light_energy"), .54):
        raise ValueError("Half-key study must identify the original key light uniquely")
    matches[0][2]["light_energy"] = change["after"]
    if altered.get("state") != expected:
        raise ValueError("Half-key study changed another lighting property")
    # Godot var_to_bytes stores these exactly representable float32 values as
    # a FLOAT type tag (3) followed by four bytes. Fail closed if the engine
    # changes its encoding or the original lighting state has ambiguity.
    source = bytes.fromhex(original["state_bytes_hex"])
    needle, replacement = struct.pack("<If", 3, .54), struct.pack("<If", 3, .27)
    expected_bytes = source.replace(needle, replacement)
    if source.count(needle) != 1 or altered.get("state_bytes_hex") != expected_bytes.hex() \
            or altered.get("sha256") != hashlib.sha256(expected_bytes).hexdigest():
        raise ValueError("Half-key exact state bytes changed beyond one tagged float32 energy")


def capture(output: Path) -> None:
    state, project = route.bound_state(output)
    diagnostic_path = output / "material_diagnostic_state.json"
    diagnostic = json.loads(diagnostic_path.read_text())
    path = project / "qa_hero/material_diagnostic_binding.json"
    if route.sha(path) != diagnostic["binding_sha256"]:
        raise ValueError("Diagnostic binding changed")
    if (output / "material_frames").exists():
        raise ValueError("Retain existing raster evidence; prepare another fresh output")
    before_live = {name: route.sha(ROOT / name) for name in route.common.LIVE_FILES}
    route.common.run_engine(project, output / "material_diagnostic.log",
        [SCENE, "--", f"output={output / 'material_frames'}"])
    if before_live != {name: route.sha(ROOT / name) for name in before_live}:
        raise ValueError("Live source changed concurrently; inspect before claiming isolation")
    verify(output)


def verify(output: Path) -> None:
    """Revalidate retained raw evidence without rerendering or rewriting it."""
    state, project = route.bound_state(output)
    diagnostic_path = output / "material_diagnostic_state.json"
    diagnostic = json.loads(diagnostic_path.read_text())
    if route.sha(project / "qa_hero/material_diagnostic_binding.json") != diagnostic["binding_sha256"]:
        raise ValueError("Diagnostic binding changed")
    route.common.check_engine_log(output / "material_diagnostic.log")
    # Recheck immutable package/gameplay/shader fixture after the window closes.
    route.bound_state(output)
    report = json.loads((output / "material_frames/report.json").read_text())
    if report.get("binding_sha256") != diagnostic["binding_sha256"]:
        raise ValueError("Captured report uses a different diagnostic binding")
    validate_report(report, diagnostic["binding"])
    route.validate_report(report["source_material_report"], state)
    route.validate_report(report["final_material_report"], state)
    for frame in report["frames"]:
        filename = frame["file"]
        if Path(filename).name != filename or route.sha(output / "material_frames" / filename) != frame["png_sha256"]:
            raise ValueError("Actual diagnostic PNG missing/changed")
    count = len(variant_labels(diagnostic["binding"]))
    if len(list((output / "material_frames").glob("*.png"))) != count:
        raise ValueError(f"Expected exactly {count} captured PNGs")
    diagnostic.update(captured=True, report_sha256=route.sha(output / "material_frames/report.json"),
                      verifier_sha256=route.sha(Path(__file__)),
                      production_ready=False, performance_measured=False)
    # Preserve original capture metadata when a validator representation issue
    # is repaired. This sidecar identifies exactly which verifier accepted it.
    route.write_json(output / "material_diagnostic_verification.json", diagnostic)
    print(f"{count}-FRAME DIAGNOSTIC PASS; interpretation still required: {output}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("prepare", "capture", "verify"))
    parser.add_argument("--atlas-dir", type=Path)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--receiver-shadow-study", action="store_true",
                        help="Prepare an optional fourth frame with hero shadow reception disabled")
    parser.add_argument("--key-energy-study", action="store_true",
                        help="Append a matched received-shadow ON/OFF pair with key energy .54 to .27")
    args = parser.parse_args()
    output = args.output_dir.resolve()
    if args.mode == "prepare":
        if args.atlas_dir is None:
            parser.error("prepare requires --atlas-dir")
        prepare(args.atlas_dir.resolve(strict=True), output, args.receiver_shadow_study, args.key_energy_study)
    elif args.mode == "capture":
        if args.receiver_shadow_study or args.key_energy_study:
            parser.error("Study flags are prepare-only; capture uses its immutable binding")
        capture(output)
    else:
        if args.receiver_shadow_study or args.key_energy_study:
            parser.error("Study flags are prepare-only; verify uses its immutable binding")
        verify(output)


if __name__ == "__main__":
    main()
