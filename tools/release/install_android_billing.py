#!/usr/bin/env python3
"""Install the exact official MIT Android billing release into an empty target.

Only the addon directory is written. Shared project settings stay untouched;
native_release.py enables the editor export plugin in prepared Android projects.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path
import sys
import urllib.request
import zipfile

LOCK = Path(__file__).with_name("billing_plugins.lock.json")


def install(project: Path, archive: bytes, lock: dict) -> dict:
    plugin = lock["android"]
    digest = hashlib.sha256(archive).hexdigest()
    if digest != plugin["sha256"]:
        raise ValueError("Billing release digest mismatch")
    destination = project / "addons/GodotGooglePlayBilling"
    if destination.exists():
        raise ValueError("Billing addon already exists; existing files are never overwritten")
    entries = []
    with zipfile.ZipFile(io.BytesIO(archive)) as zipped:
        for item in zipped.infolist():
            if item.is_dir():
                continue
            path = Path(item.filename)
            if path.is_absolute() or ".." in path.parts or ((item.external_attr >> 16) & 0o170000) == 0o120000:
                raise ValueError("Unsafe billing archive path")
            parts = path.parts
            try:
                start = parts.index("GodotGooglePlayBilling") + 1
            except ValueError:
                continue
            relative = Path(*parts[start:])
            if not relative.parts:
                continue
            entries.append((relative, zipped.read(item)))
    required = {"plugin.cfg", "BillingClient.gd", "export_plugin.gd"}
    if not required.issubset({str(relative) for relative, _ in entries}):
        raise ValueError("Billing archive missing expected addon structure")
    if not any(relative.suffix == ".aar" for relative, _ in entries):
        raise ValueError("Billing archive missing Android AAR")
    destination.mkdir(parents=True)
    for relative, content in entries:
        path = destination / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
    receipt = {"name": plugin["name"], "version": plugin["version"], "sha256": digest, "source_commit": plugin["source_commit"], "billing_library": plugin["billing_library"], "license": plugin["license"]}
    (destination / "waddle_install_receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return receipt


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path)
    args = parser.parse_args()
    try:
        lock = json.loads(LOCK.read_text())
        request = urllib.request.Request(lock["android"]["release_url"], headers={"User-Agent": "WaddleWarsNativeBuild/1.0"})
        with urllib.request.urlopen(request, timeout=30) as response:
            archive = response.read(2_000_001)
        if len(archive) > 2_000_000:
            raise ValueError("Billing release unexpectedly large")
        print(json.dumps(install(args.project.resolve(), archive, lock), indent=2))
        return 0
    except (ValueError, OSError, zipfile.BadZipFile) as error:
        print(f"install_android_billing: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
