#!/usr/bin/env python3
"""Silent, isolated landscape/portrait catch captures; no production changes.

Usage: python3 tests/capture_runner_catch.py --out /absolute/fresh/evidence-dir
       Add --include-reduced for one reduced-motion landscape capture.
       Add --include-biomes for four fixed-distance 960x540 biome stills.
       --prepare-only retains one imported snapshot for shared focused checks;
       --prepared-scope /path/scope.json captures that exact unchanged snapshot.
Run only while the game window can stay visible. This is raster QA, not FPS QA.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import uuid


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--godot", default=shutil.which("godot") or "/opt/homebrew/bin/godot")
    parser.add_argument("--include-reduced", action="store_true")
    parser.add_argument("--include-biomes", action="store_true")
    parser.add_argument("--allow-unfocused-raster", action="store_true", help="Raster only: record focus, require visible submitted frames; no foreground input/performance claim")
    parser.add_argument("--nonactivating-visible-raster", action="store_true", help="Raster only: documented no-focus + floating window flags prevent occlusion without keyboard activation")
    parser.add_argument("--parse-only", action="store_true", help="Headless parser check; no raster acceptance")
    parser.add_argument("--prepare-only", action="store_true", help="Import and retain one isolated snapshot for focused gates")
    parser.add_argument("--prepared-scope", type=Path, help="Reuse a successfully imported, unchanged prepare-only scope.json")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    out = args.out.expanduser().resolve()
    if out.exists():
        parser.error("--out must be a fresh directory; previous evidence is never overwritten")
    out.mkdir(parents=True)
    if args.prepare_only and (args.parse_only or args.prepared_scope):
        parser.error("--prepare-only cannot be combined with parse/reuse modes")
    if args.nonactivating_visible_raster and (not args.allow_unfocused_raster or args.include_biomes):
        parser.error("--nonactivating-visible-raster requires --allow-unfocused-raster and orientation-only capture")
    prepared = json.loads(args.prepared_scope.read_text()) if args.prepared_scope else None
    project = Path(prepared["snapshot"]) if prepared else Path(tempfile.mkdtemp(prefix="waddle-wars-catch-capture-"))
    if prepared:
        if not prepared.get("prepared_import_passed") or not project.name.startswith("waddle-wars-catch-capture-"):
            parser.error("prepared scope must identify a successfully imported isolated capture snapshot")
        for name, expected in prepared["source_sha256"].items():
            if any(not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected
                   for path in (project / name, root / name)):
                parser.error(f"prepared source changed: {name}; re-prepare before accepting native output")
        if hashlib.sha256((root / "project.godot").read_bytes()).hexdigest() != prepared["root_project_sha256"]:
            parser.error("project configuration changed after preparation")
    run_id = "waddle-wars-frontend-catch-" + uuid.uuid4().hex[:12]
    source_project = (root / "project.godot").read_text()
    source_project = re.sub(r"^config/(?:use_custom_user_dir|custom_user_dir_name)=.*\n", "", source_project, flags=re.M)

    def identity(suffix: str) -> None:
        text = re.sub(r"^(config/name=.*)$", r'\1\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="' + run_id + "-" + suffix + '"', source_project, flags=re.M)
        (project / "project.godot").write_text(text)

    def execute(name: str, command: list[str], timeout: int) -> int:
        case = out / name
        case.mkdir(exist_ok=True)
        (case / "command.json").write_text(json.dumps(command, indent=2) + "\n")
        with (case / "stdout.log").open("w") as stdout, (case / "stderr.log").open("w") as stderr:
            try:
                code = subprocess.run(command, stdout=stdout, stderr=stderr, timeout=timeout).returncode
            except subprocess.TimeoutExpired:
                stderr.write("Fixture exceeded bounded wall deadline. No acceptance.\n")
                code = 124
        print(f"{name}: exit {code}; {case}", flush=True)
        return code

    def clean_user() -> None:
        # This project was authored above with a unique custom user identity.
        subprocess.run([args.godot, "--headless", "--audio-driver", "Dummy", "--path", str(project),
                        "--log-file", str(project / "cleanup.log"), "--script", "res://tests/test_user_data_cleaner.gd"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15, check=False)

    successful = False
    try:
        for name in (() if prepared else ("assets", "data", "scenes", "scripts", "tests")):
            if sys.platform == "darwin":
                subprocess.run(["cp", "-cR", str(root / name), str(project / name)], check=True)
            else:
                shutil.copytree(root / name, project / name)
        cached = root / ".godot/imported"
        if not prepared and cached.is_dir():
            (project / ".godot").mkdir()
            if sys.platform == "darwin":
                subprocess.run(["cp", "-cR", str(cached), str(project / ".godot/imported")], check=True)
            else:
                shutil.copytree(cached, project / ".godot/imported")
        identity("parse" if args.parse_only else "landscape")
        files = ["scripts/runner/runner_game.gd", "scripts/runner/runner_chaser.gd", "scripts/runner/runner_player.gd",
                 "scripts/runner/runner_painted_sea.gd", "scripts/ui/runner_hud.gd", "scripts/ui/runner_hud_art.gd",
                 "scripts/utilities/game_config.gd", "tests/capture_runner_catch.py",
                 "assets/art/ui/runner/runner_hud_icons_v1.webp",
                 "scripts/runner/runner_track.gd", "tests/runner_catch_capture.gd", "tests/runner_presentation_capture.gd",
                 "tests/runner_biome_shot.gd", "tests/runner_golden_shot.gd"]
        files.extend(["tests/runner_end_fidelity_test.gd", "tests/runner_end_fidelity_test.tscn"])
        files.extend(str(path.relative_to(project)) for path in sorted((project / "assets/art/runner/day/materials").glob("*"))
                     if path.suffix in (".gdshader", ".gdshaderinc", ".tres"))
        files.extend(str(path.relative_to(project)) for path in sorted((project / "assets/art/runner/materials").glob("runner_painted*"))
                     if path.is_file() and path.suffix != ".uid")
        files.extend(str(path.relative_to(project)) for path in sorted((project / "assets/art/runner/textures").glob("runner_painted*.webp")))
        files.extend(str(path.relative_to(project)) for path in sorted((project / "assets/art/ui/runner/inrun_v4").glob("*.webp")))
        files.extend(str(path.relative_to(project)) for path in sorted((project / "assets/art/ui/runner/inrun_v5").glob("*.webp")))
        files.extend(str(path.relative_to(project)) for path in sorted((project / "data/art/fragments").glob("runner*v5*.json")))
        files.extend(["scripts/ui/runner_hud_surface.gd", "scripts/ui/runner_end_art.gd",
                      "scripts/runner/runner_painted_clouds.gd",
                      "assets/art/runner/textures/runner_crystal_ice_v2.webp",
                      "assets/art/runner/textures/runner_cloud_bank_v1.webp",
                      "data/art/course_profiles/runner_day.tres"])
        files.append("scripts/ui/painted_menu_surface.gd")
        files.append("scripts/utilities/scene_router.gd")
        files.append("scripts/runner/runner_missions.gd")
        files.append("data/art/fragments/runner_inrun_v4.json")
        manifest = {"snapshot": str(project), "audio_driver": "Dummy", "isolated_user_prefix": run_id,
                    "root_project_sha256": hashlib.sha256((root / "project.godot").read_bytes()).hexdigest(),
                    "import_scope": "Reused content-addressed imports, importer validation; not fresh-cache acceptance",
                    "parse_only": args.parse_only, "include_biomes": args.include_biomes,
                    "allow_unfocused_raster": args.allow_unfocused_raster,
                    "nonactivating_visible_raster": args.nonactivating_visible_raster,
                    "prepared_scope": str(args.prepared_scope.resolve()) if args.prepared_scope else None,
                    "reference_source_sha256": {
                        str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
                        for path in [root / "art_src/ui/runner/inrun_v4" / name for name in (
                            "runner_hud_desktop_v5.png", "runner_hud_portrait_v5.png",
                            "avalanche_catch_desktop_v2.png", "avalanche_catch_portrait_v2.png",
                            "avalanche_results_desktop_v1.png", "avalanche_results_portrait_v1.png")]},
                    "source_sha256": {
                        name: hashlib.sha256((project / name).read_bytes()).hexdigest() for name in files}}
        (out / "scope.json").write_text(json.dumps(manifest, indent=2) + "\n")
        if not prepared:
            command = [args.godot, "--headless", "--audio-driver", "Dummy", "--import", "--path", str(project),
                       "--log-file", str(out / "import/engine.log")]
            if execute("import", command, 120) != 0:
                return 1
            import_text = (out / "import/stdout.log").read_text() + (out / "import/stderr.log").read_text()
            if re.search(r"SCRIPT ERROR:|Parse Error:|Failed loading resource|(?:^|\s)ERROR:", import_text):
                print("Import reports errors; no capture launched", flush=True)
                return 1
        if args.prepare_only:
            manifest["prepared_import_passed"] = True
            (out / "scope.json").write_text(json.dumps(manifest, indent=2) + "\n")
            successful = True
            print(f"Prepared snapshot retained for shared gates: {project}", flush=True)
            return 0
        if args.parse_only:
            code = execute("parse", [args.godot, "--headless", "--audio-driver", "Dummy", "--path", str(project),
                           "--log-file", str(out / "parse/engine.log"), "res://tests/runner_catch_capture.tscn", "--", "parse_only=1"], 30)
            successful = code == 0 and not (out / "parse/stderr.log").read_text().strip()
            return 0 if successful else 1
        cases = [("landscape", 960, 540, False), ("portrait", 540, 960, False)]
        if args.include_reduced:
            cases.append(("reduced-landscape", 960, 540, True))
        results = []
        for label, width, height, reduced in cases:
            identity(label)
            case = out / label
            command = [args.godot, "--audio-driver", "Dummy", "--path", str(project), "--rendering-method", "gl_compatibility",
                       "--log-file", str(case / "engine.log"), "res://tests/runner_catch_capture.tscn", "--",
                       f"out={case / 'runner.png'}", f"w={width}", f"h={height}", f"catch_reduced={int(reduced)}",
                       f"touch={int(height > width)}", "raster_background=1" if args.allow_unfocused_raster else "foreground_gate=1"]
            if args.nonactivating_visible_raster:
                command.append("raster_nonactivating_visible=1")
            code = execute(label, command, 90)
            report_path = case / "runner.json"
            report = json.loads(report_path.read_text()) if report_path.is_file() else {}
            results.append({"case": label, "exit": code, "status": report.get("status", "NO REPORT"),
                            "checks": report.get("check_count", 0), "failures": report.get("failed_count", 0),
                            "stderr_present": bool((case / "stderr.log").read_text().strip())})
            (out / "results.json").write_text(json.dumps(results, indent=2) + "\n")
            clean_user()
            if code != 0 or report.get("status") != "PASS":
                print("Stopping after failed bounded case; remaining captures not run.", flush=True)
                return 1
        if args.include_biomes:
            # Existing fixture streams normal chunks sequentially to four
            # fixed distances. Its authored still poses/HUD are synthetic;
            # render submissions and shipped biome materials remain real.
            # One process and the same source/import snapshot cover all four.
            identity("biomes")
            case = out / "biomes"
            command = [args.godot, "--audio-driver", "Dummy", "--path", str(project), "--rendering-method", "gl_compatibility",
                       "--log-file", str(case / "engine.log"), "res://tests/runner_biome_shot.tscn", "--",
                       f"out={case / 'runner.png'}", "w=960", "h=540", "touch=0",
                       "raster_background=1" if args.allow_unfocused_raster else "foreground_gate=1"]
            code = execute("biomes", command, 85)
            stdout = (case / "stdout.log").read_text()
            stderr = (case / "stderr.log").read_text()
            checks = []
            captures = []
            coverage_path = case / "runner_coverage.json"
            try:
                coverage_report = json.loads(coverage_path.read_text())
            except (OSError, ValueError):
                coverage_report = {}
            fixture_checks = coverage_report.get("checks", [])
            fixture_captures = coverage_report.get("captures", [])
            coverage_ok = (coverage_report.get("kind") == "runner_biome_committed_coverage"
                           and coverage_report.get("status") == "PASS"
                           and coverage_report.get("failed_count") == 0
                           and coverage_report.get("check_count") == len(fixture_checks)
                           and len(fixture_checks) >= 25 and len(fixture_captures) == 4
                           and all(check.get("passed") is True for check in fixture_checks))
            checks.append({"passed": coverage_ok,
                           "message": "preserved fixture receipt verifies all four committed courses"})
            for biome, distance in (("day", 180), ("dusk", 792), ("cave", 1404), ("night", 2016)):
                path = case / f"runner_{biome}.png"
                pixels = path.read_bytes() if path.is_file() else b""
                size = list(struct.unpack(">II", pixels[16:24])) if len(pixels) >= 24 and pixels[:8] == b"\x89PNG\r\n\x1a\n" else []
                raster_ok = size == [960, 540]
                logged_ok = f"saved {path} distance={distance}m err=0" in stdout
                matching = [capture for capture in fixture_captures
                            if capture.get("biome") == biome and capture.get("distance") == distance
                            and capture.get("path") == str(path)]
                coverage = matching[0].get("coverage", {}) if len(matching) == 1 else {}
                committed_ok = coverage_ok and all(coverage.get(key) is True for key in
                    ("committed_ahead", "required_chunks_visible", "spans_player", "forward_in_frustum"))
                checks.extend([{"passed": raster_ok, "message": f"{biome} actual PNG is 960x540"},
                               {"passed": logged_ok, "message": f"{biome} fixture saved at {distance}m successfully"},
                               {"passed": committed_ok, "message": f"{biome} visible committed deck spans player and forward view"}])
                captures.append({"biome": biome, "distance": distance, "path": str(path), "actual_size": size,
                                 "committed_coverage": coverage,
                                 "sha256": hashlib.sha256(pixels).hexdigest() if pixels else None})
            diagnostics = [line for line in (stdout + "\n" + stderr).splitlines()
                           if re.search(r"SCRIPT ERROR:|Parse Error:|Failed loading resource|^ERROR:", line)]
            known_teardown = r"^ERROR: (?:\d+ resources still in use at exit|\d+ RID allocations of type .* were leaked at exit\.|Pages in use exist at exit in PagedAllocator:)"
            runtime_errors = [line for line in diagnostics if not re.search(known_teardown, line)]
            checks.extend([{"passed": code == 0, "message": "four-biome fixture finished within bounded window"},
                           {"passed": not runtime_errors, "message": "no runtime script/resource/shader error beyond separately reported teardown diagnostics"}])
            failures = sum(not check["passed"] for check in checks)
            report = {"kind": "runner_four_biome_static_raster", "status": "PASS" if failures == 0 else "FAIL",
                      "check_count": len(checks), "failed_count": failures, "captures": captures, "checks": checks,
                      "engine_diagnostics": diagnostics, "stderr_present": bool(stderr.strip()),
                      "coverage_report": str(coverage_path),
                      "coverage_sha256": hashlib.sha256(coverage_path.read_bytes()).hexdigest() if coverage_path.is_file() else None,
                      "clean_engine_log": not diagnostics, "visual_review_required": True,
                      "limitations": "runner_biome_shot loads the real runner directly, freezes gameplay and poses player/HUD at synthetic distances. Shipped streaming advances once per ordinary process frame until full lookahead commits, with child processing enabled. Preserved coverage receipt verifies nearby visible deck mesh bounds span player and forward camera view. No forced draw or warmup bypass. Materials/contrast require image review. No SceneRouter, input, natural playthrough, browser, native or performance acceptance. Teardown diagnostics remain separately reported."}
            (case / "runner.json").write_text(json.dumps(report, indent=2) + "\n")
            results.append({"case": "biomes", "exit": code, "status": report["status"], "checks": len(checks),
                            "failures": failures, "stderr_present": bool(stderr.strip()), "visual_review_required": True})
            (out / "results.json").write_text(json.dumps(results, indent=2) + "\n")
            clean_user()
            if failures:
                print("Biome raster case failed; inspect preserved logs and partial captures.", flush=True)
                return 1
        successful = True
        print(f"Captures ready for image review: {out}", flush=True)
        return 0
    finally:
        if (project / "project.godot").is_file():
            clean_user()
        if successful and not args.prepare_only and not prepared:
            shutil.rmtree(project)
        else:
            print(f"Snapshot retained: {project}", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
