#!/usr/bin/env python3
"""Run deterministic Blender 5.2.0 GLB exports declared by source manifest."""

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
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
SOURCE_MANIFEST = ROOT / "art_src/runner/source_manifest.json"
RUNTIME_MANIFEST = ROOT / "assets/art/art_manifest.json"
BLENDER_EXPORT_SCRIPT = ROOT / "tools/art/blender_export.py"
GLTF_VALIDATOR_SCRIPT = ROOT / "tools/art/validate_glb.mjs"
EXPECTED_VERSION = "5.2.0"
EXPECTED_GLTF_VALIDATOR_VERSION = "2.0.0-dev.3.10"
VERSION_RE = re.compile(r"^Blender\s+(\d+\.\d+\.\d+)", re.MULTILINE)
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
ASSET_CLASSES = {
    "character", "character_lod", "gameplay_interactive", "gameplay_interactive_lod",
    "landmark", "obstacle", "repeated_prop",
}


def load_manifest() -> dict[str, Any]:
    try:
        value = json.loads(SOURCE_MANIFEST.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"cannot read {SOURCE_MANIFEST.relative_to(ROOT)}: {exc}") from exc
    if not isinstance(value, dict):
        raise RuntimeError("source manifest root must be an object")
    if value.get("blender_version") != EXPECTED_VERSION:
        raise RuntimeError(f"source manifest must pin Blender {EXPECTED_VERSION}")
    exports = value.get("exports")
    if not isinstance(exports, list):
        raise RuntimeError("source manifest exports must be an array")
    return value


def approved_license_ids() -> set[str]:
    try:
        value = json.loads(RUNTIME_MANIFEST.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"cannot read {RUNTIME_MANIFEST.relative_to(ROOT)}: {exc}") from exc
    licenses = value.get("licenses") if isinstance(value, dict) else None
    if not isinstance(licenses, list):
        raise RuntimeError("runtime manifest licenses must be an array")
    return {
        str(entry.get("id", ""))
        for entry in licenses
        if isinstance(entry, dict) and str(entry.get("id", ""))
    }


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def blender_candidates(explicit: str | None) -> list[Path]:
    if explicit:
        return [Path(explicit).expanduser().resolve()]
    if os.environ.get("BLENDER_BIN"):
        return [Path(os.environ["BLENDER_BIN"]).expanduser().resolve()]
    raw: list[str] = []
    discovered = shutil.which("blender")
    if discovered:
        raw.append(discovered)
    raw.extend(
        [
            "/Applications/Blender.app/Contents/MacOS/Blender",
            "/opt/homebrew/bin/blender",
            "/usr/local/bin/blender",
        ]
    )
    result: list[Path] = []
    for value in raw:
        candidate = Path(value).expanduser().resolve()
        if candidate not in result:
            result.append(candidate)
    return result


def find_blender(explicit: str | None) -> Path:
    candidates = blender_candidates(explicit)
    for candidate in candidates:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate
    checked = ", ".join(str(path) for path in candidates) or "PATH"
    raise FileNotFoundError(
        "Blender 5.2.0 LTS not found. Install exact version or set BLENDER_BIN. "
        f"Checked: {checked}"
    )


def check_blender(blender: Path) -> str:
    result = subprocess.run(
        [str(blender), "--version"],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
        env=deterministic_environment(),
    )
    output = result.stdout + result.stderr
    match = VERSION_RE.search(output)
    if result.returncode != 0 or match is None:
        raise RuntimeError(f"cannot determine Blender version from {blender}: {output.strip()}")
    version = match.group(1)
    if version != EXPECTED_VERSION:
        raise RuntimeError(
            f"wrong Blender version: expected {EXPECTED_VERSION}, found {version} at {blender}"
        )
    return output.splitlines()[0]


def find_node() -> Path:
    discovered = shutil.which("node")
    if not discovered:
        raise FileNotFoundError("Node.js not found; install Node and run npm ci --prefix tools/art")
    return Path(discovered).resolve()


def check_gltf_validator(node: Path) -> str:
    result = subprocess.run(
        [str(node), str(GLTF_VALIDATOR_SCRIPT), "--version"],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
        env=deterministic_environment(),
    )
    output = result.stdout + result.stderr
    if result.returncode != 0:
        raise RuntimeError(
            "Khronos glTF Validator unavailable. Run npm ci --prefix tools/art. "
            f"Details: {output.strip()}"
        )
    if EXPECTED_GLTF_VALIDATOR_VERSION not in output:
        raise RuntimeError(
            f"wrong glTF Validator version; expected {EXPECTED_GLTF_VALIDATOR_VERSION}: "
            f"{output.strip()}"
        )
    return output.strip()


def validate_glb(node: Path, output: Path) -> int:
    result = subprocess.run(
        [str(node), str(GLTF_VALIDATOR_SCRIPT), str(output)],
        cwd=ROOT,
        check=False,
        env=deterministic_environment(),
    )
    return result.returncode


def deterministic_environment() -> dict[str, str]:
    env = os.environ.copy()
    env.update({"LC_ALL": "C", "LANG": "C", "PYTHONHASHSEED": "0", "TZ": "UTC"})
    return env


def self_test_blender(blender: Path) -> int:
    command = [
        str(blender),
        "--background",
        "--factory-startup",
        "--disable-autoexec",
        "--python",
        str(BLENDER_EXPORT_SCRIPT),
        "--",
        "--self-test",
        "--expected-version",
        EXPECTED_VERSION,
    ]
    print("[art-export] self-test:", " ".join(command))
    return subprocess.run(command, cwd=ROOT, env=deterministic_environment(), check=False).returncode


def select_jobs(manifest: dict[str, Any], requested_ids: list[str]) -> list[dict[str, Any]]:
    jobs = [job for job in manifest["exports"] if isinstance(job, dict)]
    jobs.sort(key=lambda job: str(job.get("id", "")))
    if not requested_ids:
        return jobs
    by_id = {str(job.get("id", "")): job for job in jobs}
    missing = sorted(set(requested_ids) - set(by_id))
    if missing:
        raise RuntimeError(f"unknown export job ID(s): {', '.join(missing)}")
    return [by_id[job_id] for job_id in sorted(set(requested_ids))]


def safe_project_path(value: str, root: Path) -> Path:
    path = (ROOT / value).resolve()
    try:
        path.relative_to(root.resolve())
    except ValueError as exc:
        raise RuntimeError(f"unsafe manifest path outside {root.relative_to(ROOT)}: {value}") from exc
    return path


def validate_job_registration(job: dict[str, Any], license_ids: set[str]) -> None:
    job_id = str(job.get("id", ""))
    source = safe_project_path(str(job.get("source", "")), ROOT / "art_src")
    output = safe_project_path(str(job.get("output", "")), ROOT / "assets/art")
    if source.suffix.lower() != ".blend" or not source.is_file():
        raise RuntimeError(f"export {job_id}: source missing or not .blend: {source}")
    expected_hash = str(job.get("source_sha256", ""))
    if not SHA_RE.fullmatch(expected_hash) or file_sha256(source) != expected_hash:
        raise RuntimeError(f"export {job_id}: source_sha256 is invalid or stale")
    if output.suffix.lower() != ".glb":
        raise RuntimeError(f"export {job_id}: output must be .glb")
    if str(job.get("license_id", "")) not in license_ids:
        raise RuntimeError(f"export {job_id}: license_id is not approved by runtime manifest")
    if str(job.get("asset_class", "")) not in ASSET_CLASSES:
        raise RuntimeError(f"export {job_id}: asset_class is invalid")
    if job.get("forward_axis") != "-Z":
        raise RuntimeError(f"export {job_id}: forward_axis must be -Z")


def export_job(blender: Path, node: Path, job: dict[str, Any]) -> int:
    job_id = str(job.get("id", ""))
    source = safe_project_path(str(job.get("source", "")), ROOT / "art_src")
    output = safe_project_path(str(job.get("output", "")), ROOT / "assets/art")
    if source.suffix.lower() != ".blend" or not source.is_file():
        raise RuntimeError(f"export {job_id}: source missing or not .blend: {source.relative_to(ROOT)}")
    if output.suffix.lower() != ".glb":
        raise RuntimeError(f"export {job_id}: output must be .glb")
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(f".{output.stem}.{os.getpid()}.candidate.glb")
    temporary.unlink(missing_ok=True)
    blender_job = dict(job)
    blender_job["output"] = str(temporary.relative_to(ROOT))
    command = [
        str(blender),
        "--background",
        "--factory-startup",
        "--disable-autoexec",
        str(source),
        "--python",
        str(BLENDER_EXPORT_SCRIPT),
        "--",
        "--expected-version",
        EXPECTED_VERSION,
        "--job-json",
        json.dumps(blender_job, ensure_ascii=False, sort_keys=True, separators=(",", ":")),
        "--project-root",
        str(ROOT),
    ]
    print(f"[art-export] START {job_id}: {source.relative_to(ROOT)} -> {output.relative_to(ROOT)}")
    try:
        result = subprocess.run(command, cwd=ROOT, env=deterministic_environment(), check=False)
        if result.returncode != 0:
            print(f"[art-export] FAIL {job_id}: Blender exit {result.returncode}", file=sys.stderr)
            return result.returncode
        if not temporary.is_file() or temporary.stat().st_size == 0:
            print(f"[art-export] FAIL {job_id}: candidate output missing or empty", file=sys.stderr)
            return 1
        if validate_glb(node, temporary) != 0:
            print(f"[art-export] FAIL {job_id}: Khronos validation failed", file=sys.stderr)
            return 1
        os.replace(temporary, output)
    finally:
        temporary.unlink(missing_ok=True)
    digest = file_sha256(output)
    print(f"[art-export] PASS {job_id}: bytes={output.stat().st_size} sha256={digest}")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--all", action="store_true", help="export every registered job")
    parser.add_argument("--id", action="append", default=[], help="export one job ID; repeatable")
    parser.add_argument("--dry-run", action="store_true", help="print selected jobs without Blender")
    parser.add_argument("--check-blender", action="store_true", help="verify exact Blender binary/version")
    parser.add_argument("--check-validator", action="store_true", help="verify pinned Khronos glTF Validator")
    parser.add_argument("--self-test-blender", action="store_true", help="run exporter capability test in Blender")
    parser.add_argument("--blender", help="explicit Blender executable; otherwise BLENDER_BIN/PATH/app locations")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        manifest = load_manifest()
        select_for_export = args.all or bool(args.id)
        jobs = select_jobs(manifest, args.id) if select_for_export or args.dry_run else []
        licenses = approved_license_ids()
        for job in jobs:
            validate_job_registration(job, licenses)
    except RuntimeError as exc:
        print(f"[art-export] FAIL {exc}", file=sys.stderr)
        return 1

    if args.dry_run:
        if not jobs:
            print("[art-export] PASS no authored Blender export jobs registered")
        for job in jobs:
            print(
                "[art-export] JOB "
                f"{job.get('id')}: {job.get('source')}::{job.get('collection')} -> {job.get('output')}"
            )
        return 0

    if args.check_validator:
        try:
            node = find_node()
            print(check_gltf_validator(node))
        except (FileNotFoundError, RuntimeError) as exc:
            print(f"[art-export] FAIL {exc}", file=sys.stderr)
            return 4
        if not args.check_blender and not args.self_test_blender and not args.all and not args.id:
            return 0

    needs_blender = args.check_blender or args.self_test_blender or bool(jobs)
    if not needs_blender:
        if manifest["exports"] and not args.all and not args.id:
            print("[art-export] PASS no export requested; use --all or --id")
        else:
            print("[art-export] PASS no authored Blender export jobs registered; Blender not required")
        return 0
    try:
        blender = find_blender(args.blender)
        version_line = check_blender(blender)
    except FileNotFoundError as exc:
        print(f"[art-export] MISSING {exc}", file=sys.stderr)
        return 2
    except RuntimeError as exc:
        print(f"[art-export] FAIL {exc}", file=sys.stderr)
        return 3
    print(f"[art-export] PASS {version_line} at {blender}")
    if args.self_test_blender:
        code = self_test_blender(blender)
        if code != 0:
            return code
    if args.check_blender and not args.all and not args.id:
        return 0
    if not jobs:
        print("[art-export] PASS no authored Blender export jobs registered")
        return 0
    try:
        node = find_node()
        print(check_gltf_validator(node))
    except (FileNotFoundError, RuntimeError) as exc:
        print(f"[art-export] FAIL {exc}", file=sys.stderr)
        return 4
    try:
        for job in jobs:
            code = export_job(blender, node, job)
            if code != 0:
                return code
    except (OSError, RuntimeError) as exc:
        print(f"[art-export] FAIL {exc}", file=sys.stderr)
        return 1
    print("[art-export] NOTE outputs require explicit runtime-manifest registration/hash review")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
