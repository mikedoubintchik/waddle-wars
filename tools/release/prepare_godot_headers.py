#!/usr/bin/env python3
"""Generate only four exact Godot 4.7.1 headers; never build an engine target."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys

from native_release import sha256

TARGETS = (
    "core/version_generated.gen.h",
    "core/disabled_classes.gen.h",
    "core/extension/gdextension_interface.gen.h",
    "core/object/gdvirtual.gen.h",
)


def prepare(source: Path, python: Path) -> dict:
    source = source.resolve()
    lock = json.loads(Path(__file__).with_name("billing_plugins.lock.json").read_text())
    commit = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    if commit != lock["ios"]["godot_source_commit"]:
        raise ValueError("Only the exact pinned Godot 4.7.1 source is supported")
    if subprocess.check_output(["git", "-C", str(source), "diff", "--name-only", "HEAD"], text=True).strip():
        raise ValueError("Godot source has tracked edits; use a clean isolated clone")
    # Keep the venv executable path: resolving its symlink selects the global
    # interpreter and loses the isolated SCons package.
    command = [str(python.absolute()), "-m", "SCons", "-j1", "platform=ios", "target=template_release", "arch=arm64", *TARGETS]
    # Explicit file targets, never the default/template engine target. Verify
    # SCons' plan contains no native compilation/linking before executing it.
    plan = subprocess.check_output([*command[:3], "--dry-run", *command[3:]], cwd=source, text=True, stderr=subprocess.STDOUT)
    allowed = {f"Generating {target} ..." for target in TARGETS}
    for line in plan.splitlines():
        if line.startswith(("Compiling ", "Linking ", "Creating ")) or (line.startswith("Generating ") and line not in allowed):
            raise ValueError("Header-only build plan unexpectedly requests a non-header action")
    subprocess.run(command, cwd=source, check=True)
    receipt = {"state": "headers_only", "engine_compiled": False, "godot_source_commit": commit,
               "command": command, "headers": {target: sha256(source / target) for target in TARGETS}}
    (source.parent / "godot_header_receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return receipt


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--python", type=Path, required=True, help="Python in an isolated venv with pinned SCons")
    args = parser.parse_args()
    try:
        print(json.dumps(prepare(args.source, args.python), indent=2))
        return 0
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"prepare_godot_headers: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
