"""Synthetic local vault tests; never read real Keychain or upload key."""
from __future__ import annotations

import base64
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import android_password_vault as vault
import android_upload_signing as signing


PASSWORD = base64.b64encode(bytes(range(48)))
RECEIPT = {"encrypted_key_sha256": "a" * 64, "upload_certificate_sha256": "b" * 64}


class AndroidPasswordVaultTests(unittest.TestCase):
    def test_encrypted_round_trip_and_tamper_rejection(self) -> None:
        document = vault.encrypt(PASSWORD, "synthetic-passphrase-123", RECEIPT)
        serialized = json.dumps(document)
        self.assertNotIn(PASSWORD.decode(), serialized)
        self.assertEqual(vault.decrypt(document, "synthetic-passphrase-123", RECEIPT), PASSWORD)
        with self.assertRaises(signing.SigningError):
            vault.decrypt(document, "wrong-passphrase-123", RECEIPT)
        with self.assertRaises(signing.SigningError):
            vault.decrypt(document, "synthetic-passphrase-123",
                          {**RECEIPT, "upload_certificate_sha256": "c" * 64})
        with self.assertRaises(signing.SigningError):
            vault.decrypt({**document, "ciphertext": "!"}, "synthetic-passphrase-123", RECEIPT)

    def test_vault_requires_private_permissions_and_same_key(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary).resolve()
            path = vault.vault_path(directory)
            path.write_text(json.dumps(vault.encrypt(PASSWORD, "synthetic-passphrase-123", RECEIPT)))
            path.chmod(0o600)
            self.assertEqual(vault.unlock(directory, RECEIPT, "synthetic-passphrase-123")[0], PASSWORD)
            path.chmod(0o644)
            with self.assertRaises(signing.SigningError):
                vault.unlock(directory, RECEIPT, "synthetic-passphrase-123")

    def test_keychain_reader_uses_only_inherited_pipe(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            executable = Path(temporary) / "read-password"

            def fake_run(command: list[str], **kwargs) -> subprocess.CompletedProcess:
                if command[0] == "/usr/bin/swiftc":
                    executable.write_bytes(b"synthetic")
                    return subprocess.CompletedProcess(command, 0)
                self.assertEqual(kwargs["stdout"], subprocess.DEVNULL)
                self.assertEqual(kwargs["stderr"], subprocess.DEVNULL)
                fd = kwargs["pass_fds"][0]
                self.assertEqual(command[-1], str(fd))
                os.write(fd, PASSWORD)
                return subprocess.CompletedProcess(command, 0)

            with patch.object(vault, "SOURCE", Path(__file__)), \
                 patch.object(vault.tempfile, "TemporaryDirectory", return_value=tempfile.TemporaryDirectory(dir=temporary)), \
                 patch.object(vault.subprocess, "run", side_effect=fake_run):
                self.assertEqual(vault.read_existing_password(), PASSWORD)

    def test_direct_signing_keeps_password_out_of_argv_and_logs(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary).resolve()
            (directory / "primary").mkdir(mode=0o700)
            store = directory / "primary/upload.p12"
            store.write_bytes(b"synthetic encrypted key")
            store.chmod(0o600)
            unsigned, signed = directory / "unsigned.aab", directory / "signed.aab"
            unsigned.write_bytes(b"synthetic unsigned bundle")
            unsigned.chmod(0o600)
            jdk = directory / "synthetic-jdk"

            def fake_run(command: list[str], **kwargs) -> subprocess.CompletedProcess:
                self.assertNotIn(PASSWORD.decode(), command)
                self.assertEqual(kwargs["env"][vault.PASSWORD_ENV], PASSWORD.decode())
                self.assertEqual(kwargs["stdout"], subprocess.DEVNULL)
                self.assertEqual(kwargs["stderr"], subprocess.DEVNULL)
                self.assertEqual(command[-1], signing.ALIAS)
                signed.write_bytes(b"synthetic signed bundle")
                return subprocess.CompletedProcess(command, 0)

            with patch.object(signing, "jdk_tools"), patch.object(vault.subprocess, "run", side_effect=fake_run):
                result = vault.sign_aab(jdk, directory, unsigned, signed, PASSWORD)
            self.assertEqual(result["state"], "sign_complete")
            self.assertEqual(signed.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
