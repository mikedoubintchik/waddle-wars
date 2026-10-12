#!/usr/bin/env python3
"""QA-only copied-source hook; reuse the ordinary isolated runner probe unchanged."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
NEEDLE = "\tbuild_finished = true\n\t_startup_warmup = ShaderWarmup.warm(self)"
HOOK = ('\t# QA COUNTERFACTUAL: copied source only; remove before ordinary countdown.\n'
        '\tif not await preload("res://tests/runner_dusk_real_prewarm.gd").warm(self):\n'
        '\t\treturn\n' + NEEDLE)
ERRORS = r"SCRIPT ERROR:|(?:^|\s)ERROR:|Failed loading resource"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare_check(command, out, name, strict_stderr=False):
    with (out / f"{name}.stdout.log").open("w") as stdout, (out / f"{name}.stderr.log").open("w") as stderr:
        result = subprocess.run(command, stdout=stdout, stderr=stderr, timeout=180)
    stdout = (out / f"{name}.stdout.log").read_text()
    stderr = (out / f"{name}.stderr.log").read_text()
    unexpected = [line for line in stderr.splitlines() if line.strip() and
                  line != "cannot connect to daemon at tcp:5037: Connection refused"]
    if result.returncode or re.search(ERRORS, stdout + stderr) or (strict_stderr and unexpected):
        raise SystemExit(f"{name} failed; logs retained, refusing renderer launch")
    return stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("label")
    parser.add_argument("mode", choices=("proof", "performance"))
    parser.add_argument("--scope", choices=("deck", "dressing"), default="deck")
    parser.add_argument("--proof-evidence", type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,79}", args.label):
        parser.error("label must contain only letters, digits, _ or -, maximum80 characters")
    out = ROOT / "qa_shots/runner" / args.label
    if out.exists():
        parser.error(f"refusing existing output: {out}")
    if args.mode == "performance" and not args.proof_evidence:
        parser.error("performance requires --proof-evidence from the separate accepted proof")
    godot = os.environ.get("GODOT") or next((shutil.which(name) for name in
        ("godot", "godot4", "godot4.7", "Godot", "/Applications/Godot.app/Contents/MacOS/Godot")
        if shutil.which(name)), None)
    if not godot or not Path(godot).is_file():
        parser.error("Godot executable missing; set GODOT=/absolute/path/to/godot")
    original = ROOT / "scripts/runner/runner_game.gd"
    source = original.read_text()
    if source.count(NEEDLE) != 1:
        parser.error("expected hook location must match exactly once; no patch applied")
    snapshot = out / "source_snapshot"
    snapshot.mkdir(parents=True)
    for name in ("assets", "data", "scenes", "scripts", "tests"):
        shutil.copytree(ROOT / name, snapshot / name)
    for name in ("project.godot", "run_runner_perf.sh"):
        shutil.copy2(ROOT / name, snapshot / name)
    patched = snapshot / "scripts/runner/runner_game.gd"
    # One validated mechanical rewrite of the copied file, never the live source.
    patched.write_text(source.replace(NEEDLE, HOOK, 1))
    project = snapshot / "project.godot"
    project_source = project.read_text()
    lines = [line for line in project_source.splitlines() if not line.startswith(
        ("config/use_custom_user_dir=", "config/custom_user_dir_name="))]
    name_lines = [index for index, line in enumerate(lines) if line.startswith("config/name=")]
    if len(name_lines) != 1:
        raise SystemExit("project identity insertion ambiguous; refusing engine launch")
    identity = f"waddle-dusk-prewarm-prepare-{args.label}"
    lines[name_lines[0] + 1:name_lines[0] + 1] = ["config/use_custom_user_dir=true",
                                              f'config/custom_user_dir_name="{identity}"']
    project.write_text("\n".join(lines) + "\n")
    manifest = {"qa_counterfactual": True, "live_runtime_changed": False,
                "mode": args.mode, "art_scope": args.scope, "hook_matches": 1, "hook": HOOK,
                "original_runner_game_sha256": sha(original),
                "patched_runner_game_sha256": sha(patched),
                "qa_helper_sha256": sha(snapshot / "tests/runner_dusk_real_prewarm.gd"),
                "prepare_isolated_identity": identity, "prepare_project_sha256": sha(project),
                "original_project_sha256": sha(ROOT / "project.godot"),
                "ordinary_wrapper_sha256": sha(snapshot / "run_runner_perf.sh"),
                "unchanged_probe_sha256": sha(snapshot / "tests/runner_perf_probe.gd")}
    if manifest["unchanged_probe_sha256"] != sha(ROOT / "tests/runner_perf_probe.gd"):
        raise SystemExit("probe copy differs; refusing engine launch")
    if args.proof_evidence:
        proof = json.loads(args.proof_evidence.read_text())
        if not all(proof.get(key) is True for key in ("success", "proof", "surface_coverage_pass")):
            raise SystemExit("proof did not pass; refusing performance launch")
        if proof.get("art_scope", "deck") != args.scope:
            raise SystemExit("proof art scope differs; refusing performance launch")
        for resource, digest in proof.get("source_sha256", {}).items():
            if not resource.startswith("res://") or ".." in Path(resource[6:]).parts:
                raise SystemExit("invalid proof resource path")
            if sha(snapshot / resource[6:]) != digest:
                raise SystemExit(f"proof source changed: {resource}")
        if len(proof.get("source_sha256", {})) != 11:
            raise SystemExit("proof source binding incomplete")
        manifest["proof_evidence"] = str(args.proof_evidence.resolve())
        manifest["proof_report_sha256"] = sha(args.proof_evidence)
    (out / "injection.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Isolated import + real-runner parser guard: {out}", flush=True)
    prepare_check([godot, "--headless", "--import", "--path", str(snapshot)],
                  out, "prepare_import", strict_stderr=True)
    parsed = prepare_check([godot, "--headless", "--path", str(snapshot), "--quit-after", "120",
        "res://scenes/gameplay/runner.tscn", "--", "dusk_real_prewarm_parse_only=true"], out, "prepare_scene")
    if "[dusk_real_prewarm] parser-only hook reached" not in parsed:
        raise SystemExit("real-scene prepare did not reach validated hook; refusing renderer launch")
    manifest["real_scene_parser_guard_passed"] = True
    (out / "injection.json").write_text(json.dumps(manifest, indent=2) + "\n")
    command = ["bash", str(snapshot / "run_runner_perf.sh"), "tier=high", "w=1920", "h=1080",
               "seed=20260907", "warmup=0", "seconds=60", "keep_visible=true", "stream_trace=true",
               f"out={out / 'report.json'}", f"dusk_real_prewarm_out={out}",
               f"dusk_real_prewarm_scope={args.scope}"]
    if args.mode == "proof":
        command.append("dusk_real_prewarm_proof=true")
    print(f"QA counterfactual {args.mode}; evidence: {out}", flush=True)
    with (out / "run.log").open("w") as log:
        result = subprocess.run(command, cwd=snapshot, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode or re.search(ERRORS, (out / "run.log").read_text()):
        raise SystemExit("engine error; evidence retained, no accepted result")
    audit = json.loads((out / "prewarm_report.json").read_text())
    if audit.get("success") is not True or audit.get("residual_qa_node_count") != 0:
        raise SystemExit("prewarm/cleanup audit failed")
    if args.scope == "dressing" and args.proof_evidence:
        def stable_inventory(rows):
            return [{key: value for key, value in row.items() if key not in
                     ("mesh_identity", "material_identity")} for row in rows]
        if audit.get("art_rng") != proof.get("art_rng") or stable_inventory(
                audit.get("dressing_inventory", [])) != stable_inventory(proof.get("dressing_inventory", [])):
            raise SystemExit("seeded dressing buffers/material contract differ from accepted proof")
    if args.mode == "performance" and not (out / "report.json").exists():
        raise SystemExit("ordinary performance report missing")
    print(f"Complete {args.mode}; inspect counterfactual evidence, not a production performance claim.")


if __name__ == "__main__":
    main()
