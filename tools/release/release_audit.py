#!/usr/bin/env python3
"""Read-only native upload gate for one frozen iOS/Android source revision.

Checks receipt continuity and artifact bytes. It does not replace signature,
device, store, privacy, or review verification and never uploads anything.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from native_release import runtime_files, sha256


def read_record(path: Path) -> dict:
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 16 * 1024 * 1024:
        raise ValueError(f"Missing or oversized receipt: {path}")
    value = json.loads(path.read_text())
    if not isinstance(value, dict):
        raise ValueError(f"Receipt must be an object: {path}")
    return value


def source_snapshot(root: Path) -> tuple[str, dict[str, str]]:
    files = {str(path.relative_to(root)): sha256(path) for path in runtime_files(root)}
    return hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest(), files


def audit(root: Path, ios: Path, ios_run: Path, android: Path) -> dict:
    source_hash, source_files = source_snapshot(root)
    errors: list[str] = []
    ios_record = read_record(ios / "receipt.json")
    android_record = read_record(android / "receipt.json")
    ipa_record = read_record(ios_run / "ipa-invocation.json") if (ios_run / "ipa-invocation.json").is_file() else {}
    signing_path = android.with_name(android.name + "-signing-launch.json")
    signing_record = read_record(signing_path) if signing_path.is_file() else {}
    for platform, record in (("iOS", ios_record), ("Android", android_record)):
        if record.get("source_sha256") != source_hash or record.get("source_files") != source_files:
            errors.append(f"{platform} candidate source differs from current runtime")
        if record.get("native_accounts_enabled") is True:
            errors.append(f"{platform} optional-account edition requires separate account/privacy/runtime acceptance")
        if record.get("launch_edition") != "free_offline_mvp":
            errors.append(f"{platform} candidate is not the approved free MVP edition")
    versions = {(record.get("version"), record.get("build_number")) for record in (ios_record, android_record)}
    if len(versions) != 1 or None in next(iter(versions), (None, None)):
        errors.append("iOS and Android version/build identities differ")
    if ios_record.get("state") != "exported_unverified":
        errors.append("iOS frozen export has not passed its export state")
    if ipa_record.get("state") != "ios_ipa_verified_offline" or ipa_record.get("source_sha256") != source_hash:
        errors.append("iOS IPA has not passed offline archive/export verification")
    ipa = ipa_record.get("artifact") or {}
    ipa_path = Path(ipa.get("path", "")) if isinstance(ipa, dict) else Path("")
    if (not ipa_path.is_absolute() or not ipa_path.is_file() or ipa_path.is_symlink()
            or sha256(ipa_path) != ipa.get("sha256")):
        errors.append("iOS IPA is absent or differs from verified bytes")
    if android_record.get("state") != "android_upload_artifact_verified_offline":
        errors.append("Android AAB has not passed offline upload-signature verification")
    if (signing_record.get("state") != "android_upload_artifact_verified_offline"
            or signing_record.get("unsigned_sha256") is None):
        errors.append("Android signing launch has not passed")
    aab_path = android / "project/build/waddle-wars.aab"
    if (not aab_path.is_file() or aab_path.is_symlink()
            or sha256(aab_path) != signing_record.get("signed_aab_sha256")):
        errors.append("Android AAB is absent or differs from verified bytes")
    return {
        "source_sha256": source_hash,
        "runtime_files": len(source_files),
        "version": ios_record.get("version"),
        "build_number": ios_record.get("build_number"),
        "ios_candidate": str(ios),
        "ios_ipa": str(ipa_path) if ipa_path.is_absolute() else None,
        "android_candidate": str(android),
        "android_aab": str(aab_path),
        "ready_for_upload_offline": not errors,
        "remaining_external_gates": ["device smoke", "store processing", "privacy/listing review", "store approval"],
        "errors": errors,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--ios", type=Path, required=True)
    parser.add_argument("--ios-run", type=Path, required=True)
    parser.add_argument("--android", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = audit(args.root.resolve(), args.ios.resolve(), args.ios_run.resolve(), args.android.resolve())
        print(json.dumps(result, indent=2))
        return 0 if result["ready_for_upload_offline"] else 1
    except (ValueError, OSError, KeyError, json.JSONDecodeError) as error:
        print(json.dumps({"ready_for_upload_offline": False, "errors": [str(error)]}, indent=2))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
