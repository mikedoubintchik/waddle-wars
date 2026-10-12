#!/usr/bin/env python3
"""Cheap, disposable Apple private-key access check before an iOS archive.

Signs a tiny temporary executable with an explicit existing certificate SHA-1.
Creates no certificate, provisioning profile, or persistent artifact.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import tempfile
from pathlib import Path
from typing import Callable

Runner = Callable[..., subprocess.CompletedProcess[str]]


def probe(identity_sha1: str, runner: Runner = subprocess.run) -> dict:
    if not re.fullmatch(r"[A-F0-9]{40}", identity_sha1):
        raise ValueError("An explicit uppercase certificate SHA-1 is required")
    result: dict = {"state": "ios_signing_preflight_failed", "identity_sha1": identity_sha1,
                    "compile_exit": None, "codesign_exit": None, "verify_exit": None,
                    "ready_for_codesign": False}
    with tempfile.TemporaryDirectory(prefix="waddle-ios-signing-preflight-") as directory:
        source = Path(directory) / "main.c"
        binary = Path(directory) / "sign-probe"
        source.write_text("int main(void) { return 0; }\n")
        commands = (
            ("compile_exit", ["/usr/bin/clang", str(source), "-o", str(binary)]),
            ("codesign_exit", ["/usr/bin/codesign", "--force", "--sign", identity_sha1, str(binary)]),
            ("verify_exit", ["/usr/bin/codesign", "--verify", str(binary)]),
        )
        for key, command in commands:
            try:
                completed = runner(command, capture_output=True, text=True, timeout=60)
            except (OSError, subprocess.TimeoutExpired):
                result["failed_stage"] = key
                return result
            result[key] = completed.returncode
            if completed.returncode:
                result["failed_stage"] = key
                return result
    result["state"] = "ios_private_key_access_verified"
    result["ready_for_codesign"] = True
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--identity-sha1", required=True)
    args = parser.parse_args()
    try:
        result = probe(args.identity_sha1)
    except ValueError as error:
        result = {"state": "ios_signing_preflight_failed", "ready_for_codesign": False,
                  "error": str(error)}
    print(json.dumps(result, indent=2))
    return 0 if result["ready_for_codesign"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
