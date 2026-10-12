"""Android Keychain preflight reports access only after a valid Swift result."""
from __future__ import annotations

import json
import subprocess
import unittest
from pathlib import Path

from android_signing_preflight import probe


class AndroidSigningPreflightTests(unittest.TestCase):
    def test_success_requires_compilation_and_keychain_result(self) -> None:
        commands: list[list[str]] = []
        def runner(command: list[str], **_: object) -> subprocess.CompletedProcess[str]:
            commands.append(command)
            if len(commands) == 1:
                Path(command[-1]).write_bytes(b"synthetic helper")
                return subprocess.CompletedProcess(command, 0, "", "")
            output = json.dumps({"state": "android_password_access_verified", "keychain_status": 0,
                                 "ready_for_password_read": True})
            return subprocess.CompletedProcess(command, 0, output, "")
        result = probe(runner)
        self.assertTrue(result["ready_for_password_read"])
        self.assertEqual(len(commands), 2)
        self.assertFalse(Path(commands[0][-1]).exists())

    def test_auth_failure_is_not_a_pass(self) -> None:
        calls = 0
        def runner(command: list[str], **_: object) -> subprocess.CompletedProcess[str]:
            nonlocal calls
            calls += 1
            if calls == 1:
                return subprocess.CompletedProcess(command, 0, "", "")
            output = json.dumps({"state": "android_password_access_failed", "keychain_status": -25293,
                                 "ready_for_password_read": False})
            return subprocess.CompletedProcess(command, 1, output, "")
        result = probe(runner)
        self.assertEqual(result["keychain_status"], -25293)
        self.assertFalse(result["ready_for_password_read"])

    def test_inconsistent_success_is_rejected(self) -> None:
        calls = 0
        def runner(command: list[str], **_: object) -> subprocess.CompletedProcess[str]:
            nonlocal calls
            calls += 1
            return subprocess.CompletedProcess(command, 0, "{}" if calls == 2 else "", "")
        self.assertEqual(probe(runner)["failed_stage"], "invalid_result")


if __name__ == "__main__":
    unittest.main()
