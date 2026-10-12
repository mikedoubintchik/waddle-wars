#!/usr/bin/env python3
"""Atomically merge reviewed art-stream fragments into canonical manifests."""

from __future__ import annotations

import argparse
import copy
import json
import os
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
RUNTIME_MANIFEST = ROOT / "assets/art/art_manifest.json"
SOURCE_MANIFEST = ROOT / "art_src/runner/source_manifest.json"
DEFAULT_FRAGMENT_DIR = ROOT / "data/art/fragments"
FRAGMENT_KEYS = {
    "runtime_assets": ("runtime", "assets"),
    "source_exports": ("source", "exports"),
    "generated_assets": ("source", "generated_assets"),
    "concepts": ("source", "concepts"),
}


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def load_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot read {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ValueError(f"{path} root must be an object")
    return value


def load_fragments(directory: Path) -> list[dict[str, Any]]:
    if not directory.is_dir():
        return []
    fragments: list[dict[str, Any]] = []
    for path in sorted(directory.glob("*.json")):
        fragment = load_object(path)
        unknown = sorted(set(fragment) - set(FRAGMENT_KEYS))
        if unknown:
            raise ValueError(f"{path}: unknown keys: {', '.join(unknown)}")
        missing = sorted(set(FRAGMENT_KEYS) - set(fragment))
        if missing:
            raise ValueError(f"{path}: missing keys: {', '.join(missing)}")
        for key in FRAGMENT_KEYS:
            if not isinstance(fragment[key], list):
                raise ValueError(f"{path}: {key} must be an array")
            for index, entry in enumerate(fragment[key]):
                if not isinstance(entry, dict):
                    raise ValueError(f"{path}: {key}[{index}] must be an object")
                asset_id = entry.get("id")
                if not isinstance(asset_id, str) or not asset_id:
                    raise ValueError(f"{path}: {key}[{index}] requires non-empty id")
        fragments.append(fragment)
    return fragments


def _merge_entries(base: list[Any], additions: list[Any], label: str) -> int:
    by_id: dict[str, dict[str, Any]] = {}
    for entry in base:
        if not isinstance(entry, dict) or not isinstance(entry.get("id"), str):
            raise ValueError(f"central {label} contains entry without string id")
        asset_id = entry["id"]
        if asset_id in by_id:
            raise ValueError(f"duplicate central {label} ID {asset_id}")
        by_id[asset_id] = entry
    added = 0
    for raw in additions:
        entry = copy.deepcopy(raw)
        asset_id = str(entry["id"])
        existing = by_id.get(asset_id)
        if existing is not None:
            if existing != entry:
                raise ValueError(f"conflicting {label} ID {asset_id}")
            continue
        base.append(entry)
        by_id[asset_id] = entry
        added += 1
    base.sort(key=lambda entry: str(entry.get("id", "")))
    return added


def _assert_unique_field(entries: list[Any], label: str, field: str) -> None:
    seen: dict[str, str] = {}
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        value = entry.get(field)
        if not isinstance(value, str) or not value:
            continue
        asset_id = str(entry.get("id", "<unknown>"))
        if value in seen:
            raise ValueError(
                f"{label} IDs {seen[value]} and {asset_id} share {field} {value}"
            )
        seen[value] = asset_id


def merge_documents(
    runtime: dict[str, Any],
    source: dict[str, Any],
    fragments: list[dict[str, Any]],
) -> tuple[dict[str, Any], dict[str, Any], dict[str, int]]:
    merged_runtime = copy.deepcopy(runtime)
    merged_source = copy.deepcopy(source)
    if not isinstance(merged_runtime.get("assets"), list):
        raise ValueError("runtime assets must be an array")
    for key in ("exports", "generated_assets", "concepts"):
        if not isinstance(merged_source.get(key), list):
            raise ValueError(f"source {key} must be an array")

    counts = {key: 0 for key in FRAGMENT_KEYS}
    for fragment in fragments:
        counts["runtime_assets"] += _merge_entries(
            merged_runtime["assets"], fragment["runtime_assets"], "runtime_assets"
        )
        counts["source_exports"] += _merge_entries(
            merged_source["exports"], fragment["source_exports"], "source_exports"
        )
        counts["generated_assets"] += _merge_entries(
            merged_source["generated_assets"],
            fragment["generated_assets"],
            "generated_assets",
        )
        counts["concepts"] += _merge_entries(
            merged_source["concepts"], fragment["concepts"], "concepts"
        )

    _assert_unique_field(merged_runtime["assets"], "runtime assets", "path")
    _assert_unique_field(merged_source["exports"], "source exports", "output")
    _assert_unique_field(merged_source["generated_assets"], "generated assets", "path")
    _assert_unique_field(merged_source["concepts"], "concepts", "path")
    return merged_runtime, merged_source, counts


def _atomic_write(path: Path, text: str) -> None:
    candidate = path.with_name(f".{path.name}.{os.getpid()}.candidate")
    try:
        candidate.write_text(text, encoding="utf-8")
        os.replace(candidate, path)
    finally:
        candidate.unlink(missing_ok=True)


def apply_with_validation(runtime: dict[str, Any], source: dict[str, Any]) -> None:
    original_runtime = RUNTIME_MANIFEST.read_text(encoding="utf-8")
    original_source = SOURCE_MANIFEST.read_text(encoding="utf-8")
    _atomic_write(RUNTIME_MANIFEST, canonical_json(runtime))
    _atomic_write(SOURCE_MANIFEST, canonical_json(source))
    try:
        from validate_art import ArtValidator

        validator = ArtValidator()
        if not validator.validate():
            raise ValueError("merged manifests failed validation:\n" + "\n".join(validator.errors))
    except Exception:
        _atomic_write(RUNTIME_MANIFEST, original_runtime)
        _atomic_write(SOURCE_MANIFEST, original_source)
        raise


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--fragments",
        type=Path,
        default=DEFAULT_FRAGMENT_DIR,
        help="directory containing canonical fragment JSON files",
    )
    parser.add_argument("--apply", action="store_true", help="write and validate central manifests")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    fragment_dir = args.fragments.resolve()
    try:
        fragments = load_fragments(fragment_dir)
        runtime = load_object(RUNTIME_MANIFEST)
        source = load_object(SOURCE_MANIFEST)
        merged_runtime, merged_source, counts = merge_documents(runtime, source, fragments)
        if args.apply:
            apply_with_validation(merged_runtime, merged_source)
    except (OSError, ValueError) as exc:
        print(f"[art-merge] FAIL {exc}", file=sys.stderr)
        return 1
    action = "APPLIED" if args.apply else "CHECK"
    print(
        f"[art-merge] {action} fragments={len(fragments)} "
        + " ".join(f"{key}={value}" for key, value in counts.items())
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
