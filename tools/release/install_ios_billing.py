#!/usr/bin/env python3
"""Install already compiled StoreKit binaries after source/artifact validation."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import sys

from native_release import ROOT, sha256

ARTIFACTS = ("WaddleStoreKit.gdip", "WaddleStoreKit.debug.a", "WaddleStoreKit.release.a")
SOURCES = ("WWStoreKitBridge.swift", "WWAuthenticationBridge.swift", "WWAuthenticationPolicy.swift", "waddle_storekit.mm", "waddle_storekit.h", "WaddleStoreKit.gdip")


def verify_plugin(folder: Path, lock: dict, source: Path | None = None) -> dict:
    receipt_path = folder / "waddle_build_receipt.json"
    if receipt_path.is_symlink():
        raise ValueError("Plugin receipt may not be a symlink")
    receipt = json.loads(receipt_path.read_text())
    if receipt.get("state") != "compiled_unverified" or receipt.get("godot_source_commit") != lock["ios"]["godot_source_commit"]:
        raise ValueError("Plugin compilation receipt does not match the exact Godot version")
    if receipt.get("plugin") != "WaddleStoreKit" or receipt.get("version") != lock["ios"]["version"]:
        raise ValueError("Plugin identity/version mismatch")
    if receipt.get("platform") != "ios" or receipt.get("architecture") != "arm64" or receipt.get("entrypoint_linkage") != "cplusplus":
        raise ValueError("Plugin platform, architecture, or generated entrypoint linkage mismatch")
    expected = ["IOS_ENABLED", "APPLE_EMBEDDED_ENABLED", "UNIX_ENABLED", "COREAUDIO_ENABLED", "THREADS_ENABLED", "NDEBUG"]
    if receipt.get("engine_cpp_defines") != {"debug": [*expected, "DEBUG_ENABLED"], "release": expected}:
        raise ValueError("Plugin C++ defines do not match the official threaded Godot templates")
    for name in ARTIFACTS:
        path = folder / name
        if path.is_symlink() or not path.is_file() or sha256(path) != receipt.get("artifacts", {}).get(name):
            raise ValueError(f"Compiled plugin artifact missing or changed: {name}")
    if source is not None:
        for name in SOURCES:
            if sha256(source / name) != receipt.get("source_hashes", {}).get(name):
                raise ValueError(f"Plugin source changed after compilation: {name}")
    return receipt


def install(folder: Path, destination: Path, lock: dict) -> dict:
    if destination.exists() or destination.is_symlink():
        raise ValueError("Installation directory must be new; installed binaries are never overwritten")
    receipt = verify_plugin(folder, lock, ROOT / "native/ios/WaddleStoreKit")
    destination.mkdir(parents=True)
    for name in (*ARTIFACTS, "waddle_build_receipt.json"):
        shutil.copy2(folder / name, destination / name)
    return receipt


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("compiled_folder", type=Path)
    parser.add_argument("--destination", type=Path, default=ROOT / "ios/plugins/WaddleStoreKit")
    args = parser.parse_args()
    try:
        lock = json.loads(Path(__file__).with_name("billing_plugins.lock.json").read_text())
        receipt = install(args.compiled_folder.resolve(), args.destination.absolute(), lock)
        print(json.dumps({"state": "installed_unverified", "destination": str(args.destination), "artifacts": receipt["artifacts"]}, indent=2))
        return 0
    except (ValueError, OSError, KeyError) as error:
        print(f"install_ios_billing: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
