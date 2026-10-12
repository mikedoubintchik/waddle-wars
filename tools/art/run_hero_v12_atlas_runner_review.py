#!/usr/bin/env python3
"""Quarantined baked-atlas review through real PenguinVisual and RunnerGame.

Requires a verified shared-external package; rejected bakes cannot unlock review
or play gates. Prepare is headless, capture opens sequential QA windows. Neither
changes live assets/saves. A gate PASS is integration proof, not art approval.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[2]
QA = ROOT / "qa_shots/hero"
KINDS = ("albedo", "normal", "orm", "masks")
GLB_NAME = "hero_penguin_v12_atlas.glb"
SHADER = "tests/shaders/hero_v12_atlas_review.gdshader"
SCENE = "res://tests/hero_v12_facade_capture.tscn"
RUNNER = "res://tests/hero_v12_atlas_runner_capture.tscn"
WRAPPER = '''[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://tests/hero_v12_atlas_review_rig.gd" id="1"]
[ext_resource type="PackedScene" path="res://qa_hero/candidate.glb" id="2"]

[node name="HeroPenguinRig" type="Node3D"]
script = ExtResource("1")

[node name="Model" parent="." instance=ExtResource("2")]
'''


def helper(filename: str):
    spec = importlib.util.spec_from_file_location(filename.removesuffix(".py"), Path(__file__).with_name(filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


common = helper("run_hero_v12_runner_review.py")
package = helper("package_hero_v12_shared_textures.py")
sha, write_json = common.sha, common.write_json


def verified_projection(binding: dict) -> bool:
    gate = binding.get("projection_gate")
    return (isinstance(gate, dict) and gate.get("passed") is True
            and type(gate.get("missing_pixels")) is int and gate["missing_pixels"] == 0)


def validate_shader_defaults(text: str) -> None:
    """No M-palette recolor: preserve ANY baked pigment with ratio-one defaults."""
    for name in ("dorsal", "ventral", "patch", "identity"):
        reference = re.search(rf"^uniform vec3 reference_{name}_linear = vec3\(([^)]+)\);$", text, re.M)
        desired = re.search(rf"^instance uniform vec3 {name}_linear = vec3\(([^)]+)\);$", text, re.M)
        if not reference or not desired or tuple(map(float, reference[1].split(","))) != tuple(map(float, desired[1].split(","))):
            raise ValueError(f"Shader default pigment ratio is not one: {name}")
    if re.search(r"\bCOLOR\b", re.sub(r"//[^\n]*", "", text)):
        raise ValueError("Atlas shader cannot depend on vertex COLOR")


def safe_file(folder: Path, name: str) -> Path:
    return common.local_image(folder / GLB_NAME, name)


def validate_document(document: dict, binary: bytes) -> None:
    primitives = [p for mesh in document.get("meshes", []) for p in mesh.get("primitives", [])]
    if len(primitives) != 2 or len(document.get("materials", [])) != 2:
        raise ValueError("Atlas review requires exactly two imported PBR surfaces")
    if any("TEXCOORD_0" not in p.get("attributes", {}) or "COLOR_0" in p.get("attributes", {}) for p in primitives):
        raise ValueError("Atlas requires unique TEXCOORD_0 and no COLOR_0")
    images = document.get("images", [])
    wanted = {f"hero_penguin_v12_atlas_{kind}.png" for kind in KINDS[:3]}
    if len(images) != 3 or {image.get("uri") for image in images} != wanted or any("bufferView" in image for image in images):
        raise ValueError("Atlas images must be exactly three shared external PBR filenames, without embedded payloads")
    views = document.get("bufferViews", [])
    if package.accessor_views(document) != set(range(len(views))):
        raise ValueError("Unreferenced bufferViews remain in geometry-only buffer")
    end = 0
    for view in sorted(views, key=lambda item: item.get("byteOffset", 0)):
        start, length = view.get("byteOffset", 0), view["byteLength"]
        if view.get("buffer", 0) != 0 or length <= 0 or start < end or start - end > 3 or start + length > len(binary):
            raise ValueError("Invalid, overlapping or bloated geometry buffer storage")
        end = start + length
    if len(binary) != end:
        raise ValueError("Unreferenced trailing binary payload remains")
    textures = document.get("textures", [])
    for primitive in primitives:
        material = document["materials"][primitive["material"]]
        pbr = material.get("pbrMetallicRoughness", {})
        if pbr.get("baseColorFactor", [1, 1, 1, 1]) != [1, 1, 1, 1] \
                or pbr.get("roughnessFactor", 1) != 1 or pbr.get("metallicFactor", 1) != 1 \
                or material.get("normalTexture", {}).get("scale", 1) != 1 \
                or material.get("occlusionTexture", {}).get("strength", 1) != 1:
            raise ValueError("PBR factors must preserve baked atlas values")
        for info, kind in ((pbr.get("baseColorTexture"), "albedo"),
                           (pbr.get("metallicRoughnessTexture"), "orm"),
                           (material.get("normalTexture"), "normal"),
                           (material.get("occlusionTexture"), "orm")):
            if not isinstance(info, dict) or info.get("texCoord", 0) != 0 or info.get("extensions"):
                raise ValueError("Every PBR texture must sample unchanged TEXCOORD_0")
            texture = textures[info["index"]]
            if texture.get("extensions") or images[texture["source"]]["uri"] != f"hero_penguin_v12_atlas_{kind}.png":
                raise ValueError("PBR map does not match shared atlas binding")


def validate_package(source: Path) -> tuple[dict, dict]:
    source = source.resolve(strict=True)
    binding_path = safe_file(source, "atlas_binding.json")
    binding = json.loads(binding_path.read_text())
    if type(binding.get("schema_version")) is not int or binding["schema_version"] != 1 \
            or binding.get("uv_contract") != "unique-nonoverlapping-v1" \
            or binding.get("texture_layout") != "shared-external-v1" or not verified_projection(binding):
        raise ValueError("Only verified zero-miss shared-external atlas packages may enter real runner review")
    glb = safe_file(source, GLB_NAME)
    if sha(glb) != binding.get("glb_sha256"):
        raise ValueError("Atlas GLB hash mismatch")
    if set(binding.get("textures", {})) != set(KINDS):
        raise ValueError("Atlas binding needs exactly four texture hashes")
    for kind in KINDS:
        if sha(safe_file(source, f"hero_penguin_v12_atlas_{kind}.png")) != binding["textures"][kind]:
            raise ValueError(f"Atlas PNG hash mismatch: {kind}")
    document, binary = package.split_glb(glb.read_bytes())
    validate_document(document, binary)
    return binding, document


def prepare(source: Path, output: Path, label: str, material_mode: str) -> None:
    if material_mode not in ("atlas", "imported") or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_. -]{0,79}", label):
        raise ValueError("Explicit short candidate label and atlas/imported material mode required")
    binding, _document = validate_package(source)
    validate_shader_defaults((ROOT / SHADER).read_text())
    if output.exists() or output == QA or not output.is_relative_to(QA):
        raise ValueError("Use a fresh dedicated child of qa_shots/hero; old evidence is retained")
    before = {name: sha(ROOT / name) for name in common.LIVE_FILES}
    project = output / "isolated_project"
    project.mkdir(parents=True)
    for name in ("assets", "data", "scenes", "scripts", "tests", "addons"):
        if not (ROOT / name).exists():
            continue
        shutil.copytree(ROOT / name, project / name, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    identity = "waddle-v12-atlas-runner-review-" + uuid.uuid4().hex
    config = (ROOT / "project.godot").read_text()
    config = re.sub(r"^config/(?:use_custom_user_dir|custom_user_dir_name)=.*\n", "", config, flags=re.M)
    config = config.replace('config/name="Waddle Wars"',
        f'config/name="Waddle Wars — QA {label} (unapproved)"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="{identity}"')
    if identity not in config:
        raise ValueError("Could not set isolated save identity")
    (project / "project.godot").write_text(config)
    asset = project / "qa_hero"
    asset.mkdir()
    shutil.copy2(source / GLB_NAME, asset / "candidate.glb")
    shutil.copy2(source / "atlas_binding.json", asset / "atlas_binding.json")
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
    for kind in KINDS:
        name = f"hero_penguin_v12_atlas_{kind}.png"
        shutil.copy2(source / name, asset / name)
        profile = "normal_texture.import" if kind == "normal" else "data_texture.import"
        shutil.copy2(ROOT / "tests/fixtures/hero_v12_atlas_capture" / profile, asset / f"{name}.import")
    candidate = {"schema_version": 1, "glb_sha256": binding["glb_sha256"],
        "atlas_binding_sha256": sha(source / "atlas_binding.json"), "source_package": str(source),
        "shader_sha256": sha(ROOT / SHADER), "candidate_label": label, "material_mode": material_mode,
        "production_ready": False, "source_fidelity_approved": False, "source_pigment_ratio": 1.0}
    write_json(asset / "candidate_binding.json", candidate)
    (project / "assets/art/characters/hero_penguin_v1.tscn").write_text(WRAPPER)
    protected = {name: sha(project / name) for name in before if name.startswith("scripts/")}
    if any(protected[name] != before[name] for name in protected):
        raise ValueError("Production gameplay/controller/camera changed during snapshot")
    # Bind every snapshot script/test/scene, not only the handful of live entry
    # points. Later captures must use exactly the prepared imported fixture.
    fixture_hashes = {str(path.relative_to(project)): sha(path)
        for folder in ("scripts", "scenes", "tests") for path in (project / folder).rglob("*")
        if path.is_file() and path.suffix in (".gd", ".gdshader", ".tscn", ".tres")}
    state = {"schema_version": 1, "route": "real-runner-shared-atlas-v1", "project": str(project),
        "identity": identity, "candidate": candidate, "atlas_binding": binding,
        "fixture_hashes": fixture_hashes, "candidate_binding_sha256": sha(asset / "candidate_binding.json"),
        "project_config_sha256": sha(project / "project.godot"), "live_files_before": before,
        "prepared": False, "capture_gates_passed": False, "production_ready": False,
        "source_fidelity_approved": False, "performance_measured": False}
    write_json(output / "review_state.json", state)
    common.run_engine(project, output / "import.log", ["--headless", "--import"])
    common.run_engine(project, output / "preflight.log", ["--headless", SCENE, "--", f"output={output / 'preflight'}"])
    validate_report(json.loads((output / "preflight/candidate_review.json").read_text()), state)
    common.run_engine(project, output / "runner-preflight.log", ["--headless", RUNNER, "--", "mode=preflight", f"output={output / 'runner-preflight'}"])
    validate_report(json.loads((output / "runner-preflight/candidate_runner_review.json").read_text()), state)
    state["live_files_after_prepare"] = {name: sha(ROOT / name) for name in before}
    state["live_unchanged"] = before == state["live_files_after_prepare"]
    if not state["live_unchanged"]:
        raise ValueError("Live files changed during prepare; inspect concurrent work before continuing")
    state["prepared"] = True
    state["fixture_hashes"] = common.fixture_hashes(project)
    write_json(output / "review_state.json", state)
    print(f"PREPARED {label}/{material_mode}; headless only, no art approval: {output}", flush=True)


def bound_state(output: Path) -> tuple[dict, Path]:
    if output == QA or not output.is_relative_to(QA):
        raise ValueError("Expected dedicated QA hero output directory")
    state = json.loads((output / "review_state.json").read_text())
    project = Path(state["project"])
    if state.get("route") != "real-runner-shared-atlas-v1" or not state.get("prepared") \
            or project.resolve() != output / "isolated_project" \
            or not state["identity"].startswith("waddle-v12-atlas-runner-review-"):
        raise ValueError("Not a prepared atlas runner review")
    common.verify_fixture(project, state)
    if sha(project / "project.godot") != state["project_config_sha256"]:
        raise ValueError("Save/project isolation changed")
    for name, digest in state["fixture_hashes"].items():
        if sha(project / name) != digest:
            raise ValueError(f"Prepared fixture/gameplay/controller/camera changed: {name}")
    asset = project / "qa_hero"
    if sha(asset / "candidate_binding.json") != state["candidate_binding_sha256"] \
            or sha(asset / "atlas_binding.json") != state["candidate"]["atlas_binding_sha256"] \
            or sha(asset / "candidate.glb") != state["candidate"]["glb_sha256"] \
            or not verified_projection(state["atlas_binding"]):
        raise ValueError("Prepared candidate/projection binding changed")
    for kind in KINDS:
        if sha(safe_file(asset, f"hero_penguin_v12_atlas_{kind}.png")) != state["atlas_binding"]["textures"][kind]:
            raise ValueError("Prepared external atlas map changed")
    if (project / "assets/art/characters/hero_penguin_v1.tscn").read_text() != WRAPPER:
        raise ValueError("QA-only wrapper changed")
    return state, project


def validate_report(report: dict, state: dict) -> None:
    candidate = state["candidate"]
    if report.get("passed") is not True or not verified_projection(report) \
            or report.get("candidate_sha256") != candidate["glb_sha256"] \
            or report.get("candidate_label") != candidate["candidate_label"] \
            or report.get("material_mode") != candidate["material_mode"] \
            or report.get("shader_sha256") != candidate["shader_sha256"] \
            or report.get("source_pigment_ratio") != 1.0 \
            or report.get("production_ready") is not False or report.get("source_fidelity_approved") is not False \
            or report.get("unique_total_texture_instances") != 4 or report.get("unique_pbr_texture_instances") != 3:
        raise ValueError("Bound atlas material/contact/projection review rejected")


def capture_runner(output: Path) -> dict:
    state, project = bound_state(output)
    folder = output / "runner"
    if not folder.exists():
        common.run_engine(project, output / "runner.log", [RUNNER, "--", f"output={folder}", "seconds=2.5"])
    common.check_engine_log(output / "runner.log")
    report = json.loads((folder / "candidate_runner_review.json").read_text())
    validate_report(report, state)
    if len(list(folder.glob("runner_*.png"))) != len(report["samples"]) or len(report["samples"]) < 5:
        raise ValueError("Real runner frames missing")
    print(f"RUNNER DIAGNOSTIC PASS; no full motion/art/performance claim: {output}", flush=True)
    return report


def capture(output: Path) -> None:
    state, project = bound_state(output)
    reports = {}
    for view in ("front", "chase"):
        for fps in (30, 60):
            name, folder = f"{view}_{fps}", output / f"{view}_{fps}"
            if not folder.exists():
                common.run_engine(project, output / f"{name}.log", [SCENE, "--", f"output={folder}",
                    f"view={view}", "orientation=landscape", "motion=run", f"fps={fps}", "seconds=1.6", "render=beauty"])
            common.check_engine_log(output / f"{name}.log")
            report = json.loads((folder / "candidate_review.json").read_text())
            validate_report(report, state)
            sequence = folder / f"hero_penguin_run_{view}_landscape_{fps}fps"
            timeline = json.loads((sequence / "timeline.json").read_text())
            count = round(fps * 1.6)
            if timeline["asset_sha256"] != state["candidate"]["glb_sha256"] or timeline["fps"] != fps \
                    or timeline["frame_count"] != count or len(list(sequence.glob("frame_*.png"))) != count:
                raise ValueError(f"Capture frames/hash missing: {name}")
            reports[name] = report
    parity = {}
    for view in ("front", "chase"):
        slow, fast = reports[f"{view}_30"]["samples"], reports[f"{view}_60"]["samples"]
        fields = ("pelvis_roll", "chest_roll", "head_roll", "left_sole_world_y", "right_sole_world_y")
        errors = {field: max(abs(row[field] - fast[index * 2][field]) for index, row in enumerate(slow)) for field in fields}
        parity[view] = {"max_errors": errors, "passed": all(value < 0.001 for value in errors.values()),
            "includes_initial_idle_to_run_transition": True}
    state["motion_30_60_parity"] = parity
    write_json(output / "review_state.json", state)
    capture_runner(output)
    state["capture_gates_passed"] = all(row["passed"] for row in parity.values())
    state["capture_scope"] = "bound atlas materials, inherited controller, actual facade and runner camera; no art or performance approval"
    write_json(output / "review_state.json", state)
    if not state["capture_gates_passed"]:
        raise ValueError("Strict 30/60 transition parity failed; evidence retained")
    print(f"CAPTURE INTEGRATION GATES PASS; art remains unapproved: {output}", flush=True)


def play(output: Path) -> None:
    state, project = bound_state(output)
    if not state["capture_gates_passed"]:
        raise ValueError("Play requires completed full capture gates")
    # Recheck immutable logs/reports/frames; this does not render completed runs.
    capture(output)
    command = [common.godot_binary(), "--path", str(project), "--audio-driver", "Dummy", "--rendering-method", "gl_compatibility", RUNNER, "--", "mode=play"]
    with (output / "play.log").open("w") as stream:
        process = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
    write_json(output / "play_process.json", {"pid": process.pid, "command": command,
        "save_identity": state["identity"], "project_retained": True, "production_ready": False})
    print(f"QA PLAY {state['candidate']['candidate_label']} pid={process.pid}; isolated save/project retained", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("prepare", "capture", "capture-runner", "play"))
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--atlas-dir", type=Path)
    parser.add_argument("--candidate-label")
    parser.add_argument("--material-mode", choices=("atlas", "imported"), default="atlas")
    args = parser.parse_args()
    output = args.output_dir.resolve()
    if args.mode == "prepare":
        if args.atlas_dir is None or not args.candidate_label:
            parser.error("prepare requires --atlas-dir and explicit --candidate-label")
        prepare(args.atlas_dir.resolve(strict=True), output, args.candidate_label, args.material_mode)
    else:
        {"capture": capture, "capture-runner": capture_runner, "play": play}[args.mode](output)


if __name__ == "__main__":
    main()
