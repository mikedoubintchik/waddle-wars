#!/usr/bin/env python3
"""Quarantined literal-paint candidate review through the real game facade.

Prepare imports and tests without a window. Capture opens sequential QA windows.
Play requires completed capture gates; it never changes the live project or save.
This is geometry/controller integration, not source-material or performance proof.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[2]
SCENE = "res://tests/hero_v12_facade_capture.tscn"
RUNNER = "res://tests/hero_v12_runner_capture.tscn"
LIVE_FILES = (
    "scripts/characters/hero_penguin_rig.gd",
    "scripts/characters/penguin_visual.gd",
    "scripts/runner/runner_game.gd",
    "scripts/runner/runner_player.gd",
    "scripts/runner/runner_camera_composition.gd",
    "assets/art/characters/hero_penguin_v1.tscn",
    "assets/art/characters/hero_penguin_v1.glb",
)
WRAPPER = '''[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://tests/hero_v12_review_rig.gd" id="1"]
[ext_resource type="PackedScene" path="res://qa_hero/candidate.glb" id="2"]

[node name="HeroPenguinRig" type="Node3D"]
script = ExtResource("1")

[node name="Model" parent="." instance=ExtResource("2")]
'''
RUNTIME_WRAPPER = WRAPPER.replace("hero_v12_review_rig.gd", "hero_runtime_review_rig.gd")
RUNTIME_RESOURCES = (
    "assets/art/characters/hero_penguin_v1_material.tres",
    "scripts/shaders/hero_penguin_v1.gdshader",
    *(f"assets/art/characters/textures/hero_penguin_v1_{kind}.png" for kind in ("albedo", "normal", "orm")),
)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n")


def candidate_document(path: Path, material_mode: str = "literal") -> dict:
    data = path.read_bytes()
    if len(data) < 20 or struct.unpack_from("<4sII", data) != (b"glTF", 2, len(data)):
        raise ValueError("Candidate must be a complete glTF 2 GLB")
    length, kind = struct.unpack_from("<II", data, 12)
    if kind != 0x4E4F534A:
        raise ValueError("Missing GLB JSON chunk")
    document = json.loads(data[20:20 + length])
    primitives = [p for mesh in document.get("meshes", []) for p in mesh["primitives"]]
    if material_mode == "runtime":
        # Existing semantic-color asset is a pipeline fixture, not literal paint.
        # Keep this intentionally narrow; arbitrary new models need their own
        # declared contract rather than inheriting palette interpretation.
        if sha(path) != sha(ROOT / "assets/art/characters/hero_penguin_v1.glb"):
            raise ValueError("Runtime fixture requires the exact current canonical GLB")
        if len(primitives) != 1 or document.get("materials") or "COLOR_0" not in primitives[0]["attributes"]:
            raise ValueError("Canonical runtime fixture requires one semantic-color surface without PBR")
    elif material_mode != "literal" or len(primitives) != 2 or any("COLOR_0" not in p["attributes"] for p in primitives):
        raise ValueError("This route requires exactly two literal COLOR_0 surfaces; not an atlas GLB")
    return document


def local_image(source: Path, uri: str) -> Path:
    if not uri or "/" in uri or "\\" in uri or ":" in uri or uri in (".", ".."):
        raise ValueError(f"Expected a same-directory external image filename: {uri!r}")
    image = source.parent / uri
    if image.is_symlink() or not image.is_file() or image.resolve().parent != source.parent.resolve():
        raise ValueError(f"Unsafe or missing external image: {uri}")
    return image


def godot_binary() -> str:
    for value in (os.environ.get("GODOT"), "godot", "godot4", "/Applications/Godot.app/Contents/MacOS/Godot"):
        if value and shutil.which(value):
            return str(shutil.which(value))
    raise RuntimeError("Godot not found; set GODOT")


def run_engine(project: Path, log: Path, args: list[str], timeout: int = 240) -> None:
    command = [godot_binary(), "--path", str(project), "--audio-driver", "Dummy", "--rendering-method", "gl_compatibility", *args]
    write_json(log.with_suffix(".command.json"), {"command": command})
    with log.open("w") as stream:
        result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
    write_json(log.with_suffix(".result.json"), {"exit_code": result.returncode, "log_sha256": sha(log)})
    check_engine_log(log)


def check_engine_log(log: Path) -> None:
    result = json.loads(log.with_suffix(".result.json").read_text())
    text = log.read_text()
    # Shutdown warnings remain visible, but parser/resource/runtime errors are never exit-0 PASS.
    if sha(log) != result["log_sha256"] or result["exit_code"] or re.search(r"SCRIPT ERROR:|SHADER ERROR:|(?:^|\n)ERROR:|Failed loading resource", text):
        raise RuntimeError(f"Godot review failed ({result['exit_code']}); inspect {log}")


def fixture_hashes(project: Path) -> dict[str, str]:
    """Bind actual imported fixture, including material/import settings and helpers."""
    return {str(path.relative_to(project)): sha(path) for path in sorted(project.rglob("*"))
        if path.is_file() and ".godot" not in path.relative_to(project).parts
        and "__pycache__" not in path.parts and path.suffix != ".pyc"}


def verify_fixture(project: Path, state: dict) -> None:
    expected = state.get("fixture_hashes")
    if not isinstance(expected, dict) or not expected or fixture_hashes(project) != expected:
        raise ValueError("Prepared fixture changed or lacks complete binding; prepare a fresh review")


def prepare(candidate: Path, output: Path, material_mode: str = "literal") -> None:
    candidate = candidate.resolve(strict=True)
    document = candidate_document(candidate, material_mode)
    if output.exists():
        raise ValueError("Use a fresh output directory; rejected evidence is retained")
    if not output.is_relative_to(ROOT / "qa_shots" / "hero"):
        raise ValueError("QA output must be a fresh child of qa_shots/hero")
    output.mkdir(parents=True)
    project = output / "isolated_project"
    project.mkdir()
    before = {name: sha(ROOT / name) for name in LIVE_FILES}
    for name in ("assets", "data", "scenes", "scripts", "tests", "addons"):
        if not (ROOT / name).exists():
            continue
        shutil.copytree(ROOT / name, project / name, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    identity = "waddle-v12-runner-review-" + uuid.uuid4().hex
    config = (ROOT / "project.godot").read_text()
    config = re.sub(r"^config/(?:use_custom_user_dir|custom_user_dir_name)=.*\n", "", config, flags=re.M)
    config = config.replace('config/name="Waddle Wars"',
        f'config/name="Waddle Wars — QA candidate (unapproved)"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="{identity}"')
    if identity not in config:
        raise ValueError("Could not set isolated save identity")
    (project / "project.godot").write_text(config)
    asset = project / "qa_hero"
    asset.mkdir()
    shutil.copy2(candidate, asset / "candidate.glb")
    # Preserve literal authored clip names (slide_loop etc.), like the live
    # canonical import. Godot otherwise interprets and strips loop suffixes.
    (asset / "candidate.glb.import").write_text('''[remap]
importer="scene"
type="PackedScene"

[params]
nodes/use_name_suffixes=false
meshes/create_shadow_meshes=false
animation/import=true
animation/import_rest_as_RESET=false
skins/use_named_skins=true
''')
    if material_mode == "runtime":
        canonical_import = (ROOT / "assets/art/characters/hero_penguin_v1.glb.import").read_text()
        params = canonical_import.split("[params]", 1)[1]
        (asset / "candidate.glb.import").write_text(
            '[remap]\nimporter="scene"\ntype="PackedScene"\n\n[params]' + params)
    images = {}
    for image in document.get("images", []):
        if "uri" in image:
            original = local_image(candidate, image["uri"])
            shutil.copy2(original, asset / original.name)
            images[original.name] = sha(original)
    binding = {"schema_version": 1, "glb_sha256": sha(candidate), "source_path": str(candidate),
        "external_images": images, "color_contract": "literal-linear-COLOR_0",
        "production_ready": False, "source_material_recipe_reproduced": False,
        "material_mode": material_mode, "candidate_label": "Canonical runtime integration fixture" if material_mode == "runtime" else "Literal paint candidate"}
    if material_mode == "runtime":
        binding["color_contract"] = "runtime-semantic-COLOR_0"
        binding["runtime_resources"] = {name: sha(ROOT / name) for name in RUNTIME_RESOURCES}
    wrapper = RUNTIME_WRAPPER if material_mode == "runtime" else WRAPPER
    write_json(asset / "candidate_binding.json", binding)
    (project / "assets/art/characters/hero_penguin_v1.tscn").write_text(wrapper)
    for name in (name for name in LIVE_FILES if name.startswith("scripts/")):
        if sha(project / name) != before[name]:
            raise ValueError(f"Production script changed in snapshot: {name}")
    state = {"schema_version": 1, "project": str(project), "identity": identity,
        "binding": binding, "live_files_before": before, "prepared": False,
        "capture_gates_passed": False, "performance_measured": False, "production_ready": False}
    write_json(output / "review_state.json", state)
    run_engine(project, output / "import.log", ["--headless", "--import"])
    run_engine(project, output / "preflight.log", ["--headless", SCENE, "--", f"output={output / 'preflight'}"])
    report = json.loads((output / "preflight/candidate_review.json").read_text())
    if not report["passed"] or report.get("candidate_sha256") != binding["glb_sha256"]:
        raise RuntimeError("Candidate material/motion preflight rejected")
    run_engine(project, output / "runner-preflight.log", ["--headless", RUNNER, "--", "mode=preflight", f"output={output / 'runner-preflight'}"])
    runner = json.loads((output / "runner-preflight/candidate_runner_review.json").read_text())
    if not runner.get("passed") or not runner.get("actual_runner_started") or runner.get("candidate_sha256") != binding["glb_sha256"]:
        raise RuntimeError("Actual runner selected a different candidate")
    state["live_files_after_prepare"] = {name: sha(ROOT / name) for name in LIVE_FILES}
    state["live_unchanged"] = state["live_files_before"] == state["live_files_after_prepare"]
    if not state["live_unchanged"]:
        raise ValueError("Live files changed while preparing; inspect concurrent work before continuing")
    state["prepared"] = True
    state["fixture_hashes"] = fixture_hashes(project)
    write_json(output / "review_state.json", state)
    print(f"PREPARED (no rendered pixels): {output}", flush=True)


def bound_state(output: Path) -> tuple[dict, Path]:
    if not output.is_relative_to(ROOT / "qa_shots" / "hero"):
        raise ValueError("Expected a QA hero output directory")
    state = json.loads((output / "review_state.json").read_text())
    project = Path(state["project"])
    if project.resolve() != output / "isolated_project" or not state["prepared"]:
        raise ValueError("Review is not a prepared isolated project")
    verify_fixture(project, state)
    config = (project / "project.godot").read_text()
    if f'config/custom_user_dir_name="{state["identity"]}"' not in config or "config/use_custom_user_dir=true" not in config:
        raise ValueError("Save isolation changed")
    if sha(project / "qa_hero/candidate.glb") != state["binding"]["glb_sha256"]:
        raise ValueError("Bound candidate changed")
    for name, digest in state["binding"]["external_images"].items():
        if sha(local_image(project / "qa_hero/candidate.glb", name)) != digest:
            raise ValueError("Bound external image changed")
    for name in (name for name in LIVE_FILES if name.startswith("scripts/")):
        if sha(project / name) != state["live_files_before"][name]:
            raise ValueError(f"Snapshot gameplay/controller modified: {name}")
    wrapper = RUNTIME_WRAPPER if state["binding"].get("material_mode") == "runtime" else WRAPPER
    if (project / "assets/art/characters/hero_penguin_v1.tscn").read_text() != wrapper:
        raise ValueError("QA wrapper changed")
    return state, project


def capture(output: Path) -> None:
    state, project = bound_state(output)
    reports = {}
    for view in ("front", "chase"):
        for fps in (30, 60):
            name = f"{view}_{fps}"
            folder = output / name
            if not folder.exists():
                run_engine(project, output / f"{name}.log", [SCENE, "--", f"output={folder}",
                    f"view={view}", "orientation=landscape", "motion=run", f"fps={fps}", "seconds=1.6", "render=beauty"])
            check_engine_log(output / f"{name}.log")
            report = json.loads((folder / "candidate_review.json").read_text())
            sequence = folder / f"hero_penguin_run_{view}_landscape_{fps}fps"
            timeline = json.loads((sequence / "timeline.json").read_text())
            expected_frames = round(fps * 1.6)
            if not report["passed"] or report["candidate_sha256"] != state["binding"]["glb_sha256"] \
                    or timeline["asset_sha256"] != report["candidate_sha256"] \
                    or timeline["fps"] != fps or timeline["frame_count"] != expected_frames \
                    or len(list(sequence.glob("frame_*.png"))) != expected_frames:
                raise ValueError(f"Capture contact/material gate rejected: {name}")
            reports[name] = report
    parity = {}
    for view in ("front", "chase"):
        slow, fast = reports[f"{view}_30"]["samples"], reports[f"{view}_60"]["samples"]
        fields = ("pelvis_roll", "chest_roll", "head_roll", "left_sole_world_y", "right_sole_world_y")
        # Both arrays include the initial zero-time pose. Compare coincident steps.
        errors = {field: max(abs(row[field] - fast[index * 2][field]) for index, row in enumerate(slow)) for field in fields}
        steady = {field: max(abs(row[field] - fast[index * 2][field])
            for index, row in enumerate(slow) if index / 30 >= 0.10) for field in fields}
        parity[view] = {"max_errors": errors, "passed": all(value < 0.001 for value in errors.values()),
            "steady_run_from_seconds": 0.10, "steady_run_max_errors": steady,
            "steady_run_passed": all(value < 0.001 for value in steady.values())}
    state["motion_30_60_parity"] = parity
    write_json(output / "review_state.json", state)
    if not (output / "runner").exists():
        run_engine(project, output / "runner.log", [RUNNER, "--", f"output={output / 'runner'}", "seconds=2.5"])
    check_engine_log(output / "runner.log")
    runner = json.loads((output / "runner/candidate_runner_review.json").read_text())
    if not runner["passed"]:
        raise ValueError("Normal runner capture rejected")
    passed = all(row["passed"] for row in parity.values())
    material_scope = "canonical runtime materials" if state["binding"].get("material_mode") == "runtime" else "literal paint, not final source material"
    state.update(capture_gates_passed=passed, motion_30_60_parity=parity,
        capture_scope=f"geometry, {material_scope}, inherited controller, real runner camera; not performance or visual approval")
    write_json(output / "review_state.json", state)
    if not passed:
        raise ValueError(f"Capture retained; full transition 30/60 parity failed. See {output / 'review_state.json'}")
    print(f"CAPTURE GATES PASS; fidelity unapproved: {output}", flush=True)


def capture_runner(output: Path) -> None:
    """Bounded runner diagnostic; deliberately cannot unlock play/full gates."""
    _state, project = bound_state(output)
    if (output / "runner").exists():
        raise ValueError("Runner evidence already exists; use a fresh prepared review")
    run_engine(project, output / "runner.log", [RUNNER, "--", f"output={output / 'runner'}", "seconds=2.5"])
    report = json.loads((output / "runner/candidate_runner_review.json").read_text())
    if not report["passed"]:
        raise ValueError("Runner diagnostic rejected")
    print(f"RUNNER DIAGNOSTIC PASS; full capture/play gates unchanged: {output}", flush=True)


def play(output: Path) -> None:
    state, project = bound_state(output)
    if not state["capture_gates_passed"]:
        raise ValueError("Play requires completed capture gates")
    command = [godot_binary(), "--path", str(project), "--audio-driver", "Dummy", "--rendering-method", "gl_compatibility", RUNNER, "--", "mode=play"]
    with (output / "play.log").open("w") as stream:
        process = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
    write_json(output / "play_process.json", {"pid": process.pid, "command": command,
        "save_identity": state["identity"], "project_retained": True, "production_ready": False})
    print(f"QA PLAY launched pid={process.pid}; project/save retained: {output}", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("prepare", "capture", "capture-runner", "play"))
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--candidate-glb", type=Path)
    parser.add_argument("--material-mode", choices=("literal", "runtime"), default="literal")
    args = parser.parse_args()
    output = args.output_dir.resolve()
    if args.mode == "prepare":
        if args.candidate_glb is None:
            parser.error("prepare requires --candidate-glb")
        prepare(args.candidate_glb, output, args.material_mode)
    elif args.mode == "capture":
        capture(output)
    elif args.mode == "capture-runner":
        capture_runner(output)
    else:
        play(output)


if __name__ == "__main__":
    main()
