#!/usr/bin/env python3
"""Isolated headless Godot normal-import texture identity/storage verification."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def bound_inputs(source):
    binding = json.loads((source / "atlas_binding.json").read_text())
    if (binding.get("schema_version") != 1 or binding.get("uv_contract") != "unique-nonoverlapping-v1"
            or binding.get("texture_layout") != "shared-external-v1"
            or binding.get("projection_gate") != {"passed": True, "missing_pixels": 0}):
        raise ValueError("expected verified shared-external atlas binding")
    expected = {"hero_penguin_v12_atlas.glb": binding["glb_sha256"]}
    for kind in ("albedo", "normal", "orm", "masks"):
        expected[f"hero_penguin_v12_atlas_{kind}.png"] = binding["textures"][kind]
    for name, digest in expected.items():
        if hashlib.sha256((source / name).read_bytes()).hexdigest() != digest:
            raise ValueError(f"package binding mismatch: {name}")
    return expected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package-lod", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    source, output = args.package_lod.resolve(), args.output_dir.resolve()
    qa = (ROOT / "qa_shots/hero").resolve()
    if output == qa or not output.is_relative_to(qa) or output.exists():
        raise ValueError("audit output must be a fresh QA child")
    expected_inputs = bound_inputs(source)
    output.mkdir(parents=True)
    project = output / "isolated_project"
    atlas = project / "atlas"
    atlas.mkdir(parents=True)
    for path in source.iterdir():
        if path.suffix in (".glb", ".png", ".import", ".json") and path.is_file():
            shutil.copy2(path, atlas / path.name)
    fixture = (ROOT / "tests/fixtures/hero_v12_atlas_capture/project.godot.template").read_text()
    fixture = fixture.replace("waddle-v12-candidate-atlas-qa", "waddle-v12-shared-texture-qa-" + output.name)
    (project / "project.godot").write_text(fixture)
    for source_path in (ROOT / "tests/hero_v12_shared_texture_package_test.gd", ROOT / "tests/shaders/hero_v12_atlas_review.gdshader"):
        shutil.copy2(source_path, project / source_path.name)
    godot = shutil.which("godot")
    if not godot:
        raise RuntimeError("Godot unavailable")
    commands = {
        "import": [godot, "--headless", "--editor", "--import", "--path", str(project), "--rendering-method", "gl_compatibility"],
        "identity": [godot, "--headless", "--path", str(project), "--rendering-method", "gl_compatibility", "--script",
                     "res://hero_v12_shared_texture_package_test.gd", "--", "--out=" + str(output / "resource_identity_audit.json")],
    }
    for name, command in commands.items():
        run = subprocess.run(command, capture_output=True, text=True, timeout=180, check=False)
        (output / f"{name}.stdout.log").write_text(run.stdout)
        (output / f"{name}.stderr.log").write_text(run.stderr)
        if run.returncode or re.search(r"SCRIPT ERROR:|SHADER ERROR:|(^|\s)ERROR:", run.stdout + run.stderr):
            raise RuntimeError(f"{name} failed; logs retained at {output}: " + run.stderr[-3000:])
    report = json.loads((output / "resource_identity_audit.json").read_text())
    if not report["passed"]:
        raise RuntimeError("Godot resource identity/storage gate failed")
    for name, digest in expected_inputs.items():
        if hashlib.sha256((atlas / name).read_bytes()).hexdigest() != digest:
            raise RuntimeError("isolated import changed or did not load the bound input: " + name)
    report.update(bound_input_sha256=expected_inputs, isolated_import_inputs_exact=True,
                  source_binding_sha256=hashlib.sha256((source / "atlas_binding.json").read_bytes()).hexdigest())
    (output / "resource_identity_audit.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(f"[hero-shared-textures] PASS {output}: shared stored payload {report['shared_stored_payload_bytes']} bytes; not driver VRAM or FPS")


if __name__ == "__main__":
    main()
