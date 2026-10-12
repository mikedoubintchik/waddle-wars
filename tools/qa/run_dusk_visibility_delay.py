#!/usr/bin/env python3
"""QA-only first-DUSK visibility delay. Root schedules this serialized native run."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

from run_dusk_real_prewarm import ROOT, ERRORS, prepare_check, sha

START = "func _spawn_chunk(index: int, difficulty: float) -> void:\n"
END = "\n\nfunc _chunk_rng("
BEFORE = '\tpreload("res://tests/runner_dusk_visibility_delay.gd").before_insert(self, chunk)\n'
AFTER = '\tpreload("res://tests/runner_dusk_visibility_delay.gd").after_insert(self, chunk)\n'


def patch_track(source):
    if source.count(START) != 1 or source.count(END) != 1:
        raise ValueError("spawn function boundary must match exactly once")
    start = source.index(START)
    end = source.index(END, start)
    body = source[start:end]
    if body.count("\tadd_child(chunk)\n") != 1 or body.count("\t_next_index = index + 1\n") != 1:
        raise ValueError("before/after insertion hooks must each match once")
    patched = body.replace("\tadd_child(chunk)\n", BEFORE + "\tadd_child(chunk)\n", 1)
    patched = patched.replace("\t_next_index = index + 1\n", "\t_next_index = index + 1\n" + AFTER, 1)
    return source[:start] + patched + source[end:]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("label")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,79}", args.label):
        parser.error("label must use letters, digits, _, -, maximum80 characters")
    out = ROOT / "qa_shots/runner" / args.label
    if out.exists():
        parser.error(f"refusing existing output: {out}")
    godot = shutil.which(os.environ.get("GODOT", "godot"))
    if not godot:
        parser.error("Godot executable missing; set GODOT to its path")
    original = ROOT / "scripts/runner/runner_track.gd"
    patched = patch_track(original.read_text())
    snapshot = out / "source_snapshot"
    snapshot.mkdir(parents=True)
    for name in ("assets", "data", "scenes", "scripts", "tests"):
        shutil.copytree(ROOT / name, snapshot / name)
    for name in ("project.godot", "run_runner_perf.sh"):
        shutil.copy2(ROOT / name, snapshot / name)
    (snapshot / "scripts/runner/runner_track.gd").write_text(patched)
    project = snapshot / "project.godot"
    lines = [line for line in project.read_text().splitlines() if not line.startswith(
        ("config/use_custom_user_dir=", "config/custom_user_dir_name="))]
    names = [index for index, line in enumerate(lines) if line.startswith("config/name=")]
    if len(names) != 1:
        raise SystemExit("isolated identity insertion ambiguous; refusing engine launch")
    identity = f"waddle-dusk-delay-prepare-{args.label}"
    lines[names[0] + 1:names[0] + 1] = ["config/use_custom_user_dir=true",
                                     f'config/custom_user_dir_name="{identity}"']
    project.write_text("\n".join(lines) + "\n")
    manifest = {"qa_counterfactual": True, "live_runtime_changed": False,
        "target_chunk": 17, "confirmed_hidden_draws": 2, "hook_count": 2,
        "before_insert_hook": BEFORE, "after_insert_hook": AFTER,
        "original_track_sha256": sha(original),
        "patched_track_sha256": sha(snapshot / "scripts/runner/runner_track.gd"),
        "helper_sha256": sha(snapshot / "tests/runner_dusk_visibility_delay.gd"),
        "unchanged_probe_sha256": sha(snapshot / "tests/runner_perf_probe.gd"),
        "unchanged_game_sha256": sha(snapshot / "scripts/runner/runner_game.gd"),
        "unchanged_wrapper_sha256": sha(snapshot / "run_runner_perf.sh"),
        "prepare_isolated_identity": identity, "prepare_project_sha256": sha(project)}
    for name in ("tests/runner_perf_probe.gd", "scripts/runner/runner_game.gd", "run_runner_perf.sh"):
        if sha(snapshot / name) != sha(ROOT / name):
            raise SystemExit(f"ordinary resource changed during copy: {name}")
    (out / "injection.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Isolated import and actual-runner parser guard: {out}", flush=True)
    prepare_check([godot, "--headless", "--import", "--path", str(snapshot)],
                  out, "prepare_import", strict_stderr=True)
    parsed = prepare_check([godot, "--headless", "--path", str(snapshot), "--quit-after", "120",
        "res://scenes/gameplay/runner.tscn", "--", "dusk_visibility_parse_only=true"], out, "prepare_scene")
    if "[dusk_visibility_delay] real-runner parser hook reached" not in parsed:
        raise SystemExit("actual runner did not reach parser hook; refusing renderer launch")
    manifest["real_scene_parser_guard_passed"] = True
    (out / "injection.json").write_text(json.dumps(manifest, indent=2) + "\n")
    command = ["bash", str(snapshot / "run_runner_perf.sh"), "tier=high", "w=1920", "h=1080",
        "seed=20260907", "warmup=0", "seconds=60", "keep_visible=true", "stream_trace=true",
        f"out={out / 'report.json'}", f"dusk_visibility_out={out}"]
    print("Running QA-only delayed-first-visibility diagnostic; no warmup modification.", flush=True)
    with (out / "run.log").open("w") as log:
        result = subprocess.run(command, cwd=snapshot, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode or re.search(ERRORS, (out / "run.log").read_text()):
        raise SystemExit("engine error; logs retained, no accepted result")
    audit = json.loads((out / "visibility_delay_report.json").read_text())
    report = json.loads((out / "report.json").read_text())
    if audit.get("success") is not True or len(audit.get("events", [])) != 7:
        raise SystemExit("visibility/cleanup/trace guard failed")
    bindings = {"res://scripts/runner/runner_track.gd": manifest["patched_track_sha256"],
        "res://tests/runner_perf_probe.gd": manifest["unchanged_probe_sha256"],
        "res://tests/runner_dusk_visibility_delay.gd": manifest["helper_sha256"]}
    if audit.get("source_sha256") != bindings:
        raise SystemExit("actual hook/probe/helper source bindings differ from copied experiment")
    frames = {frame["sample_frame_id"]: frame for window in report["stream_trace"]["windows"]
              for frame in window["frames"]}
    joined = {"scope": "Same monotonic clock; interval containment is correlation, not GPU attribution.",
        "event_intervals": [{"event": event, "containing_recorded_intervals": [frame for frame in
            frames.values() if frame["interval_start_usec"] <= event["monotonic_usec"] <= frame["interval_end_usec"]]}
            for event in audit["events"]]}
    (out / "visibility_frame_join.json").write_text(json.dumps(joined, indent=2) + "\n")
    print(f"Diagnostic complete: {out}; counterfactual, not a production fix.")


if __name__ == "__main__":
    main()
