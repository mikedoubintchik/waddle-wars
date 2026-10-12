"""Apple signing preflight refuses false passes and leaves no candidate output."""
from __future__ import annotations

import subprocess
import unittest
from pathlib import Path

from signing_preflight import probe


IDENTITY = "A" * 40


class SigningPreflightTests(unittest.TestCase):
    def test_success_requires_compile_sign_and_verify(self) -> None:
        commands: list[list[str]] = []
        def runner(command: list[str], **_: object) -> subprocess.CompletedProcess[str]:
            commands.append(command)
            if len(commands) == 1:
                Path(command[-1]).write_bytes(b"synthetic executable")
            return subprocess.CompletedProcess(command, 0, "", "")
        result = probe(IDENTITY, runner)
        self.assertTrue(result["ready_for_codesign"])
        self.assertEqual(result["state"], "ios_private_key_access_verified")
        self.assertEqual([command[0] for command in commands],
                         ["/usr/bin/clang", "/usr/bin/codesign", "/usr/bin/codesign"])
        self.assertFalse(Path(commands[0][-1]).exists())

    def test_signing_failure_stops_before_verify(self) -> None:
        commands: list[list[str]] = []
        def runner(command: list[str], **_: object) -> subprocess.CompletedProcess[str]:
            commands.append(command)
            return subprocess.CompletedProcess(command, 1 if len(commands) == 2 else 0, "", "")
        result = probe(IDENTITY, runner)
        self.assertFalse(result["ready_for_codesign"])
        self.assertEqual(result["failed_stage"], "codesign_exit")
        self.assertIsNone(result["verify_exit"])
        self.assertEqual(len(commands), 2)

    def test_invalid_identity_refused_without_running_tools(self) -> None:
        with self.assertRaisesRegex(ValueError, "SHA-1"):
            probe("not-an-identity", lambda *_args, **_kwargs: self.fail("ran tool"))

    def test_timeout_is_failure(self) -> None:
        def runner(command: list[str], **_: object) -> subprocess.CompletedProcess[str]:
            raise subprocess.TimeoutExpired(command, 60)
        result = probe(IDENTITY, runner)
        self.assertFalse(result["ready_for_codesign"])
        self.assertEqual(result["failed_stage"], "compile_exit")


if __name__ == "__main__":
    unittest.main()
