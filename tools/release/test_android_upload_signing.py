#!/usr/bin/env python3
"""Pure-host upload-signing regressions; Keychain/JDK/compiler/build all mocked.

These tests create only synthetic fixture files. No private key, Keychain item,
credential, Android build, network request, or store mutation is performed.
"""
from __future__ import annotations

import contextlib
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import android_upload_signing as signing
import android_password_vault as vault

SYNTHETIC_PASSWORD = "DO_NOT_EXPOSE_SYNTHETIC_PASSWORD_0123456789"


def response(state: str, stage: str = "complete", **flags: bool) -> str:
    value = {"state": state, "stage": stage, "keychain_password_created": False,
             "key_generated": False, "backup_verified": False}
    value.update(flags)
    return json.dumps(value)


class UploadSigningTests(unittest.TestCase):
    def setUp(self) -> None:
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name).resolve()
        self.home = self.root / "home"
        (self.home / "Library/Application Support").mkdir(parents=True)
        self.destination = self.home / "Library/Application Support/WaddleWarsSigning" / signing.BUNDLE / "android-upload-v1"
        self.checkout = self.root / "checkout"
        self.checkout.mkdir()
        self.jdk = self.root / "installed-jdk"
        self.swiftc = self.root / "swiftc"
        self.python = self.root / "python"
        self.godot = self.root / "godot"
        self.bundletool = self.root / "bundletool.jar"
        self.sdk = self.root / "sdk"
        self.sdk.mkdir()
        for path in (self.swiftc, self.python, self.godot, *(self.jdk / "bin" / name for name in ("java", "keytool", "jarsigner"))):
            self.write(path, b"synthetic executable fixture; never run", 0o700)
        self.write(self.bundletool, b"synthetic public bundletool fixture")
        self.sources = self.checkout / "tools/release"
        for name in ("android_upload_signing.py", "android_upload_keychain.swift", "build_android_upload.py",
                     "native_release.py", "verify_android_release.py", "check_android_artifact.py"):
            self.write(self.sources / name, b"synthetic release source; never run")
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        for name, value in (("ROOT", self.checkout), ("SWIFT_SOURCE", self.sources / "android_upload_keychain.swift"),
                            ("OWN_SOURCE", self.sources / "android_upload_signing.py"), ("BUILD_SCRIPT", self.sources / "build_android_upload.py"),
                            ("__file__", str(self.sources / "android_upload_signing.py"))):
            self.stack.enter_context(patch.object(signing, name, value))
        self.stack.enter_context(patch.object(signing, "signing_directory", return_value=self.destination))
        self.calls: list[tuple[list[str], dict]] = []
        self.probe_state = "item_absent"
        self.bootstrap_failure: str | None = None
        self.sign_failure = False
        self.sign_failure_stage = "signing_aab"
        self.export_failure = False
        self.verify_failure = False
        self.mutate_source = False
        self.bad_backup = False
        self.bad_certificate = False
        self.mutate_unsigned = False
        self.stack.enter_context(patch.object(signing.subprocess, "run", side_effect=self.fake_run))

    @staticmethod
    def write(path: Path, data: bytes, mode: int = 0o600) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        path.chmod(mode)

    def setup_key(self) -> dict:
        return signing.setup(self.jdk, self.swiftc)

    def build_key(self) -> dict:
        return signing.build(self.root / "release", jdk=self.jdk, bundletool=self.bundletool,
                             godot=self.godot, sdk=self.sdk, python=self.python, version="1.0.0", build_number=3)

    def test_direct_p12_vault_preserves_key_and_offline_verifier(self) -> None:
        self.setup_key()
        self.write(vault.vault_path(self.destination), b"synthetic encrypted vault")

        def sign_direct(_jdk: Path, _directory: Path, _unsigned: Path, signed: Path, _password: bytes) -> dict:
            self.write(signed, b"signed synthetic fixture")
            return {"state": "sign_complete", "stage": "complete", "password_source": "encrypted_local_vault"}

        with patch.object(vault, "unlock", return_value=(b"synthetic-only-password", signing.digest(vault.vault_path(self.destination)))), \
             patch.object(vault, "validate_password"), patch.object(vault, "sign_aab", side_effect=sign_direct):
            receipt = signing.build(self.root / "release", jdk=self.jdk, bundletool=self.bundletool,
                                    godot=self.godot, sdk=self.sdk, python=self.python,
                                    version="1.0.0", build_number=3,
                                    vault_passphrase="synthetic-passphrase-123")
        self.assertEqual(receipt["state"], "android_upload_artifact_verified_offline")
        self.assertEqual(receipt["signing_password_transport"],
                         "encrypted_local_vault_to_jarsigner_child_environment")
        self.assertFalse(any(len(command) > 1 and command[1] == "sign" for command, _ in self.calls))

    def fake_run(self, command: list[str], **kwargs) -> subprocess.CompletedProcess:
        self.calls.append((command, kwargs))
        for argument in command:
            self.assertNotIn(SYNTHETIC_PASSWORD, argument)
        env = kwargs["env"]
        self.assertNotIn("GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD", env)
        self.assertNotIn("WADDLE_WARS_UPLOAD_PASSWORD", env)
        self.assertNotIn("JAVA_TOOL_OPTIONS", env)
        self.assertNotIn("JDK_JAVA_OPTIONS", env)
        self.assertNotIn("_JAVA_OPTIONS", env)
        if command[0] == str(self.swiftc):
            self.write(Path(command[-1]), b"synthetic compiled Keychain helper; never run", 0o700)
            return subprocess.CompletedProcess(command, 0, "", "")
        if command[1] == "probe":
            return subprocess.CompletedProcess(command, 0, response(self.probe_state), "")
        if command[1] == "bootstrap":
            if self.bootstrap_failure:
                password_created = self.bootstrap_failure != "creating_keychain_password"
                return subprocess.CompletedProcess(command, 1, response("operation_failed", self.bootstrap_failure,
                    keychain_password_created=password_created), SYNTHETIC_PASSWORD)
            self.write(Path(command[3]), b"encrypted synthetic PKCS12 fixture")
            self.write(Path(command[4]), b"mismatch" if self.bad_backup else b"encrypted synthetic PKCS12 fixture")
            self.write(Path(command[5]), b"bad" if self.bad_certificate else b"\x30" + b"public-certificate-fixture" * 12)
            if self.mutate_source:
                signing.SWIFT_SOURCE.write_bytes(b"changed source")
            return subprocess.CompletedProcess(command, 0, response("bootstrap_complete", keychain_password_created=True,
                key_generated=True, backup_verified=True), "")
        if command[1] == "sign":
            if self.sign_failure:
                return subprocess.CompletedProcess(command, 1, response("operation_failed", self.sign_failure_stage), SYNTHETIC_PASSWORD)
            self.write(Path(command[4]), b"signed synthetic fixture")
            if self.mutate_unsigned:
                Path(command[3]).write_bytes(b"changed unsigned output")
            return subprocess.CompletedProcess(command, 0, response("sign_complete"), "")
        if command[2] == "export":
            if self.export_failure:
                return subprocess.CompletedProcess(command, 1, SYNTHETIC_PASSWORD, SYNTHETIC_PASSWORD)
            candidate = Path(command[3])
            (candidate / "gradle-user").mkdir(parents=True, mode=0o700)
            (candidate / "gradle-user").chmod(0o700)
            self.write(candidate / "receipt.json", json.dumps({"state": "android_unsigned_awaiting_upload_signature",
                "app_name": signing.APP, "bundle_id": signing.BUNDLE}).encode())
            (candidate / "project/build").mkdir(parents=True, mode=0o700)
            (candidate / "project/build").chmod(0o700)
            self.write(candidate / "project/build/waddle-wars.aab", b"unsigned synthetic fixture")
            return subprocess.CompletedProcess(command, 0, "public export fixture", "")
        if command[2] == "verify":
            if self.verify_failure:
                return subprocess.CompletedProcess(command, 1, SYNTHETIC_PASSWORD, SYNTHETIC_PASSWORD)
            self.write(Path(command[3]) / "receipt.json", json.dumps({"state": "android_upload_artifact_verified_offline",
                "store_ready": False}).encode())
            return subprocess.CompletedProcess(command, 0, "public verifier fixture", "")
        raise AssertionError("Unexpected synthetic tool call")

    def assert_private_receipts_clean(self) -> None:
        for path in self.root.rglob("*.json"):
            self.assertNotIn(SYNTHETIC_PASSWORD, path.read_text())
        for path in self.destination.rglob("*") if self.destination.exists() else ():
            self.assertEqual(path.stat().st_uid, os.getuid())
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o700 if path.is_dir() or path.name == "keychain-helper" else 0o600)

    def test_success_first_key_has_public_pin_and_truthful_state(self) -> None:
        receipt = self.setup_key()
        self.assertEqual(receipt["state"], "intended_not_registered")
        self.assertIs(receipt["play_registered"], False)
        self.assertIs(receipt["off_device_recovery"], False)
        self.assertEqual(receipt["service"], "com.blubberandbyte.waddlewars.android.upload")
        self.assertEqual(receipt["account"], "waddlewars-upload-v1")
        self.assertEqual(receipt["encrypted_key_sha256"], receipt["encrypted_backup_sha256"])
        self.assertRegex(receipt["upload_certificate_sha256"], r"^[a-f0-9]{64}$")
        self.assert_private_receipts_clean()

    def test_existing_destination_refuses_before_any_subprocess(self) -> None:
        self.destination.mkdir(parents=True)
        with self.assertRaisesRegex(signing.SigningError, "already exists"):
            self.setup_key()
        self.assertEqual(self.calls, [])

    def test_second_setup_never_overwrites_first_key(self) -> None:
        first = self.setup_key()
        self.calls.clear()
        with self.assertRaises(signing.SigningError):
            self.setup_key()
        self.assertEqual(self.calls, [])
        self.assertEqual(signing.digest(self.destination / "primary/upload.p12"), first["encrypted_key_sha256"])

    def test_existing_exact_keychain_item_never_bootstraps(self) -> None:
        self.probe_state = "item_exists"
        with self.assertRaisesRegex(signing.SigningError, "Keychain item exists"):
            self.setup_key()
        self.assertFalse(any(command[1] == "bootstrap" for command, _ in self.calls if len(command) > 1))
        self.assertEqual(json.loads((self.destination / "receipt.json").read_text())["state"], "setup_failed")

    def test_unknown_keychain_probe_fails_closed(self) -> None:
        self.probe_state = "operation_failed"
        with self.assertRaises(signing.SigningError):
            self.setup_key()
        self.assertFalse((self.destination / "primary/upload.p12").exists())

    def test_failed_keychain_creation_preserves_attempt(self) -> None:
        self.bootstrap_failure = "creating_keychain_password"
        with self.assertRaises(signing.SigningError):
            self.setup_key()
        receipt = json.loads((self.destination / "receipt.json").read_text())
        self.assertIs(receipt["helper_result"]["keychain_password_created"], False)
        self.assertEqual(receipt["state"], "setup_failed")
        self.assert_private_receipts_clean()

    def test_failed_keytool_retains_truthful_created_password_flag(self) -> None:
        self.bootstrap_failure = "generating_upload_key"
        with self.assertRaises(signing.SigningError):
            self.setup_key()
        receipt = json.loads((self.destination / "receipt.json").read_text())
        self.assertIs(receipt["helper_result"]["keychain_password_created"], True)
        self.assertIs(receipt["helper_result"]["key_generated"], False)
        self.assert_private_receipts_clean()

    def test_failed_backup_stage_is_not_complete(self) -> None:
        self.bootstrap_failure = "copying_encrypted_backup"
        with self.assertRaises(signing.SigningError):
            self.setup_key()
        self.assertEqual(json.loads((self.destination / "receipt.json").read_text())["state"], "setup_failed")

    def test_failed_certificate_stage_is_not_complete(self) -> None:
        self.bootstrap_failure = "exporting_public_certificate"
        with self.assertRaises(signing.SigningError):
            self.setup_key()
        self.assertEqual(json.loads((self.destination / "receipt.json").read_text())["state"], "setup_failed")

    def test_bad_backup_rejected_after_success_response(self) -> None:
        self.bad_backup = True
        with self.assertRaisesRegex(signing.SigningError, "backup mismatch"):
            self.setup_key()
        self.assertTrue((self.destination / "primary/upload.p12").is_file())

    def test_bad_public_certificate_rejected(self) -> None:
        self.bad_certificate = True
        with self.assertRaisesRegex(signing.SigningError, "DER certificate"):
            self.setup_key()

    def test_source_mutation_marks_failed_and_preserves_keys(self) -> None:
        self.mutate_source = True
        with self.assertRaisesRegex(signing.SigningError, "changed during operation"):
            self.setup_key()
        self.assertTrue((self.destination / "primary/upload.p12").is_file())
        self.assertEqual(json.loads((self.destination / "receipt.json").read_text())["state"], "setup_failed")

    def test_relative_jdk_rejected_before_setup(self) -> None:
        with self.assertRaises(signing.SigningError):
            signing.setup(Path("relative"), self.swiftc)
        self.assertFalse(self.destination.exists())

    def test_traversal_tool_path_rejected(self) -> None:
        with self.assertRaises(signing.SigningError):
            signing.setup(self.jdk, self.root / "unused/../swiftc")
        self.assertFalse(self.destination.exists())

    def test_symlinked_tool_rejected(self) -> None:
        linked = self.root / "linked-swiftc"
        linked.symlink_to(self.swiftc)
        with self.assertRaises(signing.SigningError):
            signing.setup(self.jdk, linked)

    def test_symlinked_ancestor_rejected(self) -> None:
        linked = self.root / "linked-jdk"
        linked.symlink_to(self.jdk, target_is_directory=True)
        with self.assertRaises(signing.SigningError):
            signing.setup(linked, self.swiftc)

    def test_nonexecutable_tool_rejected(self) -> None:
        self.swiftc.chmod(0o600)
        with self.assertRaises(signing.SigningError):
            self.setup_key()

    def test_inside_checkout_destination_rejected(self) -> None:
        with patch.object(signing, "signing_directory", return_value=self.checkout / "keys"):
            with self.assertRaisesRegex(signing.SigningError, "outside checkout"):
                self.setup_key()

    def test_existing_parent_unsafe_permissions_not_silently_changed(self) -> None:
        self.destination.parent.parent.mkdir(mode=0o755)
        with self.assertRaisesRegex(signing.SigningError, "0700"):
            self.setup_key()
        self.assertEqual(stat.S_IMODE(self.destination.parent.parent.stat().st_mode), 0o755)

    def test_compiler_failure_keeps_private_failed_receipt(self) -> None:
        with patch.object(signing.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, SYNTHETIC_PASSWORD, SYNTHETIC_PASSWORD)):
            with self.assertRaisesRegex(signing.SigningError, "compilation failed"):
                self.setup_key()
        self.assert_private_receipts_clean()

    def test_raw_subprocess_exception_is_not_exposed(self) -> None:
        with patch.object(signing.subprocess, "run", side_effect=OSError(SYNTHETIC_PASSWORD)):
            with self.assertRaises(signing.SigningError) as caught:
                self.setup_key()
        self.assertNotIn(SYNTHETIC_PASSWORD, str(caught.exception))
        self.assert_private_receipts_clean()

    def test_malformed_helper_output_secret_never_exposed(self) -> None:
        self.setup_key()
        with patch.object(signing.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, SYNTHETIC_PASSWORD, SYNTHETIC_PASSWORD)):
            with self.assertRaises(signing.SigningError) as caught:
                signing.helper_call(self.destination / "keychain-helper", ["probe"], {})
        self.assertNotIn(SYNTHETIC_PASSWORD, str(caught.exception))

    def test_helper_extra_secret_field_rejected(self) -> None:
        value = json.loads(response("item_absent"))
        value["password"] = SYNTHETIC_PASSWORD
        with patch.object(signing.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, json.dumps(value), "")):
            with self.assertRaises(signing.SigningError):
                signing.helper_call(self.root / "helper", ["probe"], {})

    def test_parent_credentials_and_java_injection_not_inherited(self) -> None:
        with patch.dict(os.environ, {"JAVA_TOOL_OPTIONS": SYNTHETIC_PASSWORD, "JDK_JAVA_OPTIONS": SYNTHETIC_PASSWORD,
                                     "_JAVA_OPTIONS": SYNTHETIC_PASSWORD, "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD": SYNTHETIC_PASSWORD,
                                     "STRIPE_SECRET_KEY": SYNTHETIC_PASSWORD}, clear=False):
            self.setup_key()
            self.build_key()
        for _, call in self.calls:
            self.assertNotIn(SYNTHETIC_PASSWORD, json.dumps(call["env"]))

    def test_load_rejects_wrong_alias_without_reading_keychain(self) -> None:
        self.setup_key()
        path = self.destination / "receipt.json"
        value = json.loads(path.read_text())
        value["alias"] = "chancey-unrelated-app"
        signing.write_receipt(path, value)
        self.calls.clear()
        with self.assertRaises(signing.SigningError):
            signing.load_signing_receipt()
        self.assertEqual(self.calls, [])

    def test_load_rejects_modified_private_copy(self) -> None:
        self.setup_key()
        (self.destination / "backup/upload.p12").write_bytes(b"changed encrypted fixture")
        with self.assertRaises(signing.SigningError):
            signing.load_signing_receipt()

    def test_load_rejects_modified_helper(self) -> None:
        self.setup_key()
        (self.destination / "keychain-helper").write_bytes(b"changed executable fixture")
        with self.assertRaises(signing.SigningError):
            signing.load_signing_receipt()

    def test_load_rejects_unsafe_key_permissions(self) -> None:
        self.setup_key()
        (self.destination / "primary/upload.p12").chmod(0o644)
        with self.assertRaises(signing.SigningError):
            signing.load_signing_receipt()

    def test_load_rejects_changed_source(self) -> None:
        self.setup_key()
        signing.SWIFT_SOURCE.write_bytes(b"changed helper source")
        with self.assertRaises(signing.SigningError):
            signing.load_signing_receipt()

    def test_load_rejects_nonobject_receipt_without_traceback(self) -> None:
        self.setup_key()
        (self.destination / "receipt.json").write_text("[]")
        with self.assertRaises(signing.SigningError):
            signing.load_signing_receipt()

    def test_load_rejects_nonobject_tool_hashes(self) -> None:
        self.setup_key()
        path = self.destination / "receipt.json"
        value = json.loads(path.read_text())
        value["tool_sha256"] = []
        signing.write_receipt(path, value)
        with self.assertRaises(signing.SigningError):
            signing.load_signing_receipt()

    def test_source_mutation_at_compile_stops_before_keychain(self) -> None:
        fake_run = self.fake_run
        def changing_compiler(command: list[str], **kwargs) -> subprocess.CompletedProcess:
            result = fake_run(command, **kwargs)
            if command[0] == str(self.swiftc):
                signing.SWIFT_SOURCE.write_bytes(b"changed at compile")
            return result
        with patch.object(signing.subprocess, "run", side_effect=changing_compiler):
            with self.assertRaises(signing.SigningError):
                self.setup_key()
        self.assertEqual(len(self.calls), 1)

    def test_cli_discards_malicious_compiler_diagnostics(self) -> None:
        output, error = io.StringIO(), io.StringIO()
        with patch.object(signing.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, SYNTHETIC_PASSWORD, SYNTHETIC_PASSWORD)), \
             patch.object(signing.sys, "argv", ["android_upload_signing", "setup", "--jdk", str(self.jdk), "--swiftc", str(self.swiftc)]), \
             patch.object(signing.os, "umask"), contextlib.redirect_stdout(output), contextlib.redirect_stderr(error):
            self.assertEqual(signing.main(), 1)
        self.assertNotIn(SYNTHETIC_PASSWORD, output.getvalue() + error.getvalue())
        self.assert_private_receipts_clean()

    def test_success_build_exports_without_credentials_then_signs_and_verifies(self) -> None:
        self.setup_key()
        self.calls.clear()
        receipt = self.build_key()
        self.assertEqual(receipt["state"], "android_upload_artifact_verified_offline")
        self.assertIs(receipt["store_ready"], False)
        self.assertEqual([call[0][2] if call[0][0] == str(self.python) else call[0][1] for call in self.calls], ["export", "sign", "verify"])
        self.assertTrue((self.root / "release/project/build/waddle-wars-unsigned.aab").is_file())
        self.assertTrue((self.root / "release/project/build/waddle-wars.aab").is_file())
        self.assertEqual(stat.S_IMODE((self.root / "release/gradle-user").stat().st_mode), 0o700)
        self.assertFalse((self.root / "release-gradle-user").exists())
        self.assertEqual(receipt["gradle_user_home"], str(self.root / "release/gradle-user"))
        for command, call in self.calls:
            if command[0] == str(self.python):
                self.assertEqual(call["env"]["GRADLE_USER_HOME"], receipt["gradle_user_home"])
        self.assert_private_receipts_clean()

    def test_existing_candidate_never_overwritten(self) -> None:
        self.setup_key()
        (self.root / "release").mkdir()
        self.calls.clear()
        with self.assertRaises(signing.SigningError):
            self.build_key()
        self.assertEqual(self.calls, [])

    def test_existing_cache_refuses_launch(self) -> None:
        self.setup_key()
        (self.root / "release/gradle-user").mkdir(parents=True, mode=0o700)
        self.calls.clear()
        with self.assertRaises(signing.SigningError):
            self.build_key()
        self.assertEqual(self.calls, [])

    def test_existing_launcher_receipt_refuses_launch(self) -> None:
        self.setup_key()
        self.write(self.root / "release-signing-launch.json", b"{}")
        with self.assertRaises(signing.SigningError):
            self.build_key()

    def test_build_version_and_number_invalid_fail_before_tools(self) -> None:
        self.setup_key()
        for version, number in (("bad", 3), ("1.0.0", 0), ("1.0.0", True)):
            with self.subTest(version=version, number=number):
                self.calls.clear()
                with self.assertRaises(signing.SigningError):
                    signing.build(self.root / "release", jdk=self.jdk, bundletool=self.bundletool,
                        godot=self.godot, sdk=self.sdk, python=self.python, version=version, build_number=number)
                self.assertEqual(self.calls, [])

    def test_export_failure_preserves_private_launch_receipt_and_no_keychain_read(self) -> None:
        self.setup_key()
        self.calls.clear()
        self.export_failure = True
        with self.assertRaises(signing.SigningError):
            self.build_key()
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(json.loads((self.root / "release-signing-launch.json").read_text())["state"], "launch_failed_preserved_no_automatic_retry")
        self.assert_private_receipts_clean()

    def test_sign_failure_does_not_verify_or_discard_unsigned(self) -> None:
        self.setup_key()
        self.calls.clear()
        self.sign_failure = True
        with self.assertRaises(signing.SigningError):
            self.build_key()
        self.assertEqual(len(self.calls), 2)
        self.assertTrue((self.root / "release/project/build/waddle-wars-unsigned.aab").is_file())
        self.assert_private_receipts_clean()

    def test_locked_keychain_sign_failure_does_not_verify_or_print_secret(self) -> None:
        self.setup_key()
        self.calls.clear()
        self.sign_failure = True
        self.sign_failure_stage = "reading_app_specific_keychain_password"
        with self.assertRaises(signing.SigningError) as caught:
            self.build_key()
        self.assertNotIn(SYNTHETIC_PASSWORD, str(caught.exception))
        self.assertEqual(len(self.calls), 2)
        receipt = json.loads((self.root / "release-signing-launch.json").read_text())
        self.assertEqual(receipt["helper_result"]["stage"], "reading_app_specific_keychain_password")
        self.assert_private_receipts_clean()

    def test_verification_failure_not_promoted(self) -> None:
        self.setup_key()
        self.verify_failure = True
        with self.assertRaises(signing.SigningError):
            self.build_key()
        self.assertEqual(json.loads((self.root / "release-signing-launch.json").read_text())["state"], "launch_failed_preserved_no_automatic_retry")
        self.assert_private_receipts_clean()

    def test_unsigned_mutation_during_signing_rejected(self) -> None:
        self.setup_key()
        self.mutate_unsigned = True
        with self.assertRaisesRegex(signing.SigningError, "Unsigned payload changed"):
            self.build_key()

    def test_swift_source_has_no_password_output_or_generic_get_mode(self) -> None:
        source = Path(__file__).with_name("android_upload_keychain.swift").read_text()
        self.assertNotIn("SecItemUpdate", source.replace("// SecItemAdd, never SecItemUpdate/Delete:", ""))
        self.assertNotIn("SecItemDelete(", source)
        self.assertNotIn('arguments == ["get"]', source)
        self.assertNotIn("print(password", source)
        self.assertIn('"-storepass:env", passwordEnvironment', source)
        self.assertIn('"-keypass:env", passwordEnvironment', source)
        self.assertIn('"-keysize", "4096"', source)
        self.assertIn('"-validity", "10000"', source)
        self.assertIn("SecRandomCopyBytes", source)
        self.assertIn("child.standardError = output", source)
        self.assertIn("readDataToEndOfFile()", source)
        password_loader = source.split("func loadPassword()", 1)[1].split("func toolEnvironment", 1)[0]
        self.assertIn("nonInteractiveQuery()", password_loader)
        keychain_probe = source.split("func itemPresent()", 1)[1].split("func createPassword", 1)[0]
        self.assertIn("nonInteractiveQuery()", keychain_probe)
        self.assertIn("context.interactionNotAllowed = true", source)
        self.assertIn("kSecUseAuthenticationContext", source)
        self.assertNotIn("kSecUseAuthenticationUIFail", source)
        self.assertIn("timeout.schedule(deadline: .now() + 180)", source)
        self.assertIn("kill(child.processIdentifier, SIGTERM)", source)
        self.assertIn("kill(child.processIdentifier, SIGKILL)", source)
        self.assertIn("!deadline.didExpire()", source)


if __name__ == "__main__":
    unittest.main()
