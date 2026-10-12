#!/usr/bin/env python3
"""Check existing Android upload-password access before a costly AAB export."""
from __future__ import annotations

import json
import subprocess
import tempfile
from pathlib import Path
from typing import Callable

SOURCE = Path(__file__).with_name("android_keychain_preflight.swift")
Runner = Callable[..., subprocess.CompletedProcess[str]]


def probe(runner: Runner = subprocess.run) -> dict:
    failure = {"state": "android_password_access_failed", "ready_for_password_read": False}
    with tempfile.TemporaryDirectory(prefix="waddle-android-keychain-preflight-") as directory:
        executable = Path(directory) / "keychain-preflight"
        try:
            compiled = runner(["/usr/bin/swiftc", str(SOURCE), "-o", str(executable)],
                              capture_output=True, text=True, timeout=90)
            if compiled.returncode:
                return {**failure, "failed_stage": "compile"}
            checked = runner([str(executable)], capture_output=True, text=True, timeout=30)
            result = json.loads(checked.stdout)
        except (OSError, subprocess.TimeoutExpired, ValueError, TypeError):
            return {**failure, "failed_stage": "probe"}
    if (not isinstance(result, dict) or set(result) != {"state", "keychain_status", "ready_for_password_read"}
            or type(result["keychain_status"]) is not int
            or type(result["ready_for_password_read"]) is not bool
            or result["state"] not in {"android_password_access_verified", "android_password_access_failed"}
            or (checked.returncode == 0) != result["ready_for_password_read"]
            or (result["keychain_status"] == 0) != result["ready_for_password_read"]):
        return {**failure, "failed_stage": "invalid_result"}
    return result


def main() -> int:
    result = probe()
    print(json.dumps(result, indent=2))
    return 0 if result["ready_for_password_read"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
