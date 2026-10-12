"""Host build diagnostics and plist policy; no engine, credentials or signing."""
from contextlib import redirect_stdout
import hashlib
import io
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile
import zlib
from xml.etree.ElementTree import ParseError

from build_native import (SIGNING_ENV, UNUSED_IOS_PURPOSE_KEYS,
                          android_verification_inputs, apply_ios_permission_policy, apply_ios_display_name,
                          main, run_checked, sha256, verify_android_output)


class BuildDiagnosticTests(unittest.TestCase):
    def setUp(self) -> None:
        self.folder = tempfile.TemporaryDirectory(prefix="ww-build-log-fixture-")
        self.addCleanup(self.folder.cleanup)
        self.log = Path(self.folder.name) / "build.log"
        self.environment = patch.dict("build_native.os.environ", {}, clear=True)
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def run_fixture(self, output: str, code: int = 0, env: dict | None = None) -> None:
        completed = subprocess.CompletedProcess(["synthetic-engine"], code, output)
        with patch("build_native.subprocess.run", return_value=completed) as run:
            run_checked(["synthetic-engine"], self.log, env=env)
            self.assertEqual(run.call_args.kwargs["env"], env)

    def test_success_preserves_public_log(self) -> None:
        self.run_fixture("Export completed\n")
        self.assertEqual(self.log.read_text(), "Export completed\n")

    def test_nonzero_exit_still_fails_and_sanitizes(self) -> None:
        secret = "synthetic-password-value"
        with self.assertRaisesRegex(ValueError, "exit 1"):
            self.run_fixture("tool stopped " + secret, 1, {SIGNING_ENV[2]: secret})
        self.assertNotIn(secret, self.log.read_text())
        self.assertIn("<redacted-signing-value>", self.log.read_text())

    def test_zero_exit_error_cannot_be_hidden_by_redaction(self) -> None:
        for marker in ("ERROR:", "SCRIPT ERROR:", "Parse Error:", "Export failed"):
            with self.subTest(marker=marker):
                with self.assertRaisesRegex(ValueError, "exit 0"):
                    self.run_fixture(marker + " diagnostic", env={SIGNING_ENV[1]: marker})
                self.assertNotIn(marker, self.log.read_text())

    def test_explicit_environment_uses_child_values(self) -> None:
        env = dict(zip(SIGNING_ENV, (
            "/synthetic/child-release.jks", "synthetic-child-alias", "synthetic-child-password")))
        with patch.dict("build_native.os.environ", {SIGNING_ENV[2]: "unrelated-parent-value"}):
            self.run_fixture(" | ".join(env.values()), env=env)
        self.assertEqual(self.log.read_text().count("<redacted-signing-value>"), 3)
        for secret in env.values():
            self.assertNotIn(secret, self.log.read_text())

    def test_inherited_environment_values_are_sanitized(self) -> None:
        env = dict(zip(SIGNING_ENV, (
            "/synthetic/parent-release.jks", "synthetic-parent-alias", "synthetic-parent-password")))
        with patch.dict("build_native.os.environ", env):
            self.run_fixture(" | ".join(env.values()))
        for secret in env.values():
            self.assertNotIn(secret, self.log.read_text())

    def test_overlapping_signing_values_leave_no_secret_suffix(self) -> None:
        env = {SIGNING_ENV[1]: "synthetic-prefix", SIGNING_ENV[2]: "synthetic-prefix-private-suffix"}
        self.run_fixture(" | ".join(env.values()), env=env)
        self.assertEqual(self.log.read_text(), "<redacted-signing-value> | <redacted-signing-value>")

    def test_explicit_empty_environment_does_not_rewrite_public_log(self) -> None:
        with patch.dict("build_native.os.environ", {SIGNING_ENV[1]: "public"}):
            self.run_fixture("public output", env={})
        self.assertEqual(self.log.read_text(), "public output")


class AndroidReleaseBuildGateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.folder = tempfile.TemporaryDirectory(prefix="ww-android-build-gate-fixture-")
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name).resolve()
        self.jdk = self.root / "synthetic-jdk"
        (self.jdk / "bin").mkdir(parents=True)
        for name in ("java", "jarsigner", "keytool"):
            path = self.jdk / "bin" / name
            path.write_bytes(b"Synthetic tool; never executed")
            path.chmod(0o700)
        self.bundletool = self.root / "synthetic-bundletool.jar"
        self.bundletool.write_bytes(b"Synthetic bundletool; never executed")

    def test_requires_all_public_inputs_without_running_tools(self) -> None:
        with patch("verify_android_release.subprocess.run") as run:
            for inputs in ((None, self.bundletool, self.jdk), ("a" * 64, None, self.jdk),
                           ("a" * 64, self.bundletool, None)):
                with self.subTest(inputs=inputs), self.assertRaisesRegex(ValueError, "no build started"):
                    android_verification_inputs(*inputs)
            run.assert_not_called()

    def test_checks_pin_paths_and_executability_before_export(self) -> None:
        with self.assertRaisesRegex(ValueError, "64 hexadecimal"):
            android_verification_inputs("not-a-public-fingerprint", self.bundletool, self.jdk)
        with self.assertRaisesRegex(ValueError, "absolute regular file"):
            android_verification_inputs("a" * 64, Path("relative.jar"), self.jdk)
        (self.jdk / "bin" / "keytool").chmod(0o600)
        with self.assertRaisesRegex(ValueError, "executable"):
            android_verification_inputs("a" * 64, self.bundletool, self.jdk)

    def test_accepts_public_pin_without_reading_signing_environment(self) -> None:
        with patch.dict("build_native.os.environ", {}, clear=True):
            inputs = android_verification_inputs(":".join(["AB"] * 32), self.bundletool, self.jdk)
        self.assertEqual(inputs, {"upload_certificate_sha256": "ab" * 32,
                                  "bundletool": self.bundletool, "jdk": self.jdk})

    def test_postexport_verifier_receives_immutable_artifact_and_candidate_identity(self) -> None:
        output = self.root / "synthetic.aab"
        output.write_bytes(b"Synthetic export; never signed or uploaded")
        receipt = {"bundle_id": "com.example.synthetic", "version": "1.0.0", "build_number": 2}
        inputs = {"upload_certificate_sha256": "b" * 64, "bundletool": self.bundletool, "jdk": self.jdk}
        expected = {"state": "android_upload_artifact_verified_offline", "store_ready": False}
        with patch("verify_android_release.verify", return_value=expected) as verify:
            self.assertEqual(verify_android_output(output, receipt, inputs), expected)
        verify.assert_called_once_with(output, artifact_sha256=sha256(output),
                                       upload_certificate_sha256="b" * 64, package="com.example.synthetic",
                                       version="1.0.0", build_number=2,
                                       bundletool=self.bundletool, jdk=self.jdk, launch_edition="commerce")

    def test_signature_failure_cannot_be_labelled_success(self) -> None:
        output = self.root / "synthetic.aab"
        output.write_bytes(b"Synthetic rejected export")
        receipt = {"bundle_id": "com.example.synthetic", "version": "1.0.0", "build_number": 2}
        inputs = {"upload_certificate_sha256": "b" * 64, "bundletool": self.bundletool, "jdk": self.jdk}
        with patch("verify_android_release.verify", side_effect=ValueError("signature rejected")):
            with self.assertRaisesRegex(ValueError, "signature rejected"):
                verify_android_output(output, receipt, inputs)

    def test_export_symlink_is_rejected_before_hashing_or_verification(self) -> None:
        target = self.root / "synthetic-target.aab"
        target.write_bytes(b"Synthetic linked export")
        output = self.root / "synthetic-linked.aab"
        output.symlink_to(target)
        with patch("build_native.sha256") as digest, patch("verify_android_release.verify") as verify:
            with self.assertRaisesRegex(ValueError, "absolute regular file"):
                verify_android_output(output, {}, {})
            digest.assert_not_called()
            verify.assert_not_called()

    def test_library_verification_failures_reach_build_failure_handler(self) -> None:
        output = self.root / "synthetic.aab"
        output.write_bytes(b"Synthetic export")
        receipt = {"bundle_id": "com.example.synthetic", "version": "1.0.0", "build_number": 2}
        inputs = {"upload_certificate_sha256": "b" * 64, "bundletool": self.bundletool, "jdk": self.jdk}
        failures = (subprocess.TimeoutExpired("synthetic-tool", 120), ParseError("synthetic XML"),
                    zipfile.BadZipFile("synthetic ZIP"), RuntimeError("synthetic archive"), zlib.error("synthetic CRC"))
        for failure in failures:
            with self.subTest(failure=type(failure).__name__), patch("verify_android_release.verify", side_effect=failure):
                with self.assertRaisesRegex(ValueError, "Android release verification failed"):
                    verify_android_output(output, receipt, inputs)


class IOSPermissionPolicyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.folder = tempfile.TemporaryDirectory(prefix="ww-ios-plist-fixture-")
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        self.info_plist = self.root / "Synthetic-Info.plist"
        self.identity = {
            "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
            "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
            "MinimumOSVersion": "15.0",
            "CFBundleURLTypes": [{
                "CFBundleURLName": "com.example.synthetic.auth",
                "CFBundleURLSchemes": ["com.example.synthetic.auth"],
            }],
            "UISupportedInterfaceOrientations": [
                "UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft"],
            "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False},
            "SyntheticUntouchedPurposeDescription": "Fixture value must survive",
        }

    def write_plist(self, values: object) -> bytes:
        original = plistlib.dumps(values)
        self.info_plist.write_bytes(original)
        return original

    def test_removes_unused_blanks_and_preserves_identity_auth_and_orientation(self) -> None:
        values = {**self.identity, **dict.fromkeys(UNUSED_IOS_PURPOSE_KEYS, "")}
        values["NSMicrophoneUsageDescription"] = " \t\n"
        self.write_plist(values)
        result = apply_ios_permission_policy(self.info_plist)
        self.assertEqual(plistlib.loads(self.info_plist.read_bytes()), self.identity)
        self.assertEqual(result["removed_keys"], list(UNUSED_IOS_PURPOSE_KEYS))
        self.assertNotEqual(result["before_sha256"], result["after_sha256"])
        self.assertEqual(result["after_sha256"], sha256(self.info_plist))

    def test_display_title_changes_only_exported_display_key(self) -> None:
        original = {**self.identity, "CFBundleName": "Waddle Wars", "CFBundleDisplayName": "Waddle Wars"}
        self.write_plist(original)
        result = apply_ios_display_name(self.info_plist, "Waddle Wars: Penguin Panic")
        expected = {**original, "CFBundleDisplayName": "Waddle Wars: Penguin Panic"}
        self.assertEqual(plistlib.loads(self.info_plist.read_bytes()), expected)
        self.assertEqual(result["previous_display_name"], "Waddle Wars")
        self.assertEqual(result["app_name"], expected["CFBundleDisplayName"])
        self.assertEqual(result["after_sha256"], sha256(self.info_plist))
        self.assertNotEqual(result["before_sha256"], result["after_sha256"])

    def test_display_title_insertion_escaping_and_repeat_is_byte_preserving(self) -> None:
        self.write_plist(self.identity)
        title = 'Ice & "Snow"'
        first = apply_ios_display_name(self.info_plist, title)
        stamped = self.info_plist.read_bytes()
        self.assertEqual(plistlib.loads(stamped), {**self.identity, "CFBundleDisplayName": title})
        second = apply_ios_display_name(self.info_plist, title)
        self.assertEqual(self.info_plist.read_bytes(), stamped)
        self.assertIsNone(first["previous_display_name"])
        self.assertEqual(second["before_sha256"], second["after_sha256"])

    def test_display_title_rejects_bad_input_without_changing_export(self) -> None:
        original = self.write_plist({**self.identity, "CFBundleDisplayName": "Waddle Wars"})
        for title in (None, "", "x" * 31, "bad\nname"):
            with self.subTest(title=title), self.assertRaises(ValueError):
                apply_ios_display_name(self.info_plist, title)
            self.assertEqual(self.info_plist.read_bytes(), original)
        original = self.write_plist({**self.identity, "CFBundleDisplayName": False})
        with self.assertRaisesRegex(ValueError, "display name must be a string"):
            apply_ios_display_name(self.info_plist, "Waddle Wars: Penguin Panic")
        self.assertEqual(self.info_plist.read_bytes(), original)

    def test_display_title_refuses_missing_symlinked_malformed_and_non_dictionary_plists(self) -> None:
        with self.assertRaisesRegex(ValueError, "regular file"):
            apply_ios_display_name(self.info_plist, "Waddle Wars: Penguin Panic")
        self.write_plist(self.identity)
        linked = self.root / "linked.plist"
        linked.symlink_to(self.info_plist)
        with self.assertRaisesRegex(ValueError, "regular file"):
            apply_ios_display_name(linked, "Waddle Wars: Penguin Panic")
        for original in (b"<plist><dict>", plistlib.dumps(["Synthetic wrong root"])):
            with self.subTest(original=original):
                self.info_plist.write_bytes(original)
                with self.assertRaises(ValueError):
                    apply_ios_display_name(self.info_plist, "Waddle Wars: Penguin Panic")
                self.assertEqual(self.info_plist.read_bytes(), original)

    def test_absent_keys_are_byte_preserving_and_repeat_is_idempotent(self) -> None:
        self.write_plist({**self.identity, **dict.fromkeys(UNUSED_IOS_PURPOSE_KEYS, "")})
        apply_ios_permission_policy(self.info_plist)
        sanitized = self.info_plist.read_bytes()
        result = apply_ios_permission_policy(self.info_plist)
        self.assertEqual(self.info_plist.read_bytes(), sanitized)
        self.assertEqual(result["removed_keys"], [])
        self.assertEqual(result["before_sha256"], result["after_sha256"])

    def test_declared_new_permission_requires_review_before_any_file_change(self) -> None:
        for key in UNUSED_IOS_PURPOSE_KEYS:
            with self.subTest(key=key):
                values = {**self.identity, **dict.fromkeys(UNUSED_IOS_PURPOSE_KEYS, "")}
                values[key] = "Synthetic newly declared capture feature"
                original = self.write_plist(values)
                with self.assertRaisesRegex(ValueError, "Unexpected declared iOS permission"):
                    apply_ios_permission_policy(self.info_plist)
                self.assertEqual(self.info_plist.read_bytes(), original)

    def test_invalid_value_is_not_silently_deleted(self) -> None:
        for value in (False, 0, []):
            with self.subTest(value=value):
                original = self.write_plist({**self.identity, "NSCameraUsageDescription": value})
                with self.assertRaisesRegex(ValueError, "Unexpected declared iOS permission"):
                    apply_ios_permission_policy(self.info_plist)
                self.assertEqual(self.info_plist.read_bytes(), original)

    def test_missing_and_symlinked_app_plists_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "regular file"):
            apply_ios_permission_policy(self.info_plist)
        original = self.write_plist({**self.identity, "NSCameraUsageDescription": ""})
        other = self.root / "symlinked.plist"
        other.symlink_to(self.info_plist)
        with self.assertRaisesRegex(ValueError, "regular file"):
            apply_ios_permission_policy(other)
        self.assertEqual(self.info_plist.read_bytes(), original)

    def test_malformed_and_non_dictionary_plists_rejected_without_changes(self) -> None:
        for original in (b"<plist><dict>", plistlib.dumps(["Synthetic wrong root"])):
            with self.subTest(original=original):
                self.info_plist.write_bytes(original)
                with self.assertRaises(ValueError):
                    apply_ios_permission_policy(self.info_plist)
                self.assertEqual(self.info_plist.read_bytes(), original)

    def test_canonical_build_records_sanitized_plist_hash(self) -> None:
        candidate = self.root / "candidate"
        project = candidate / "project"
        plugin = project / "ios/plugins/WaddleStoreKit"
        plugin.mkdir(parents=True)
        for name in ("WaddleStoreKit.gdip", "WaddleStoreKit.debug.a", "WaddleStoreKit.release.a", "waddle_build_receipt.json"):
            (plugin / name).write_bytes(b"Synthetic plugin fixture")
        (project / "project.godot").write_text('[application]\nconfig/name="Synthetic"\n')
        # Template binding is checked before and after export. Supply the
        # prepared preset this synthetic candidate previously omitted.
        (project / "export_presets.cfg").write_text(
            '[preset.0]\nname="Synthetic iOS"\nplatform="iOS"\n'
            '[preset.0.options]\nprivacy/disk_space_access_reasons=1\n')
        receipt_path = candidate / "receipt.json"
        receipt_path.write_text(json.dumps({
            "state": "prepared_unbuilt", "platform": "ios",
            "godot_version": "4.7.1.stable", "source_sha256": "a" * 64,
            "preset_name": "Synthetic iOS",
            "app_name": "Waddle Wars: Penguin Panic",
            "prepared_files": {str(path.relative_to(project)): hashlib.sha256(path.read_bytes()).hexdigest()
                               for path in project.rglob("*") if path.is_file()},
        }))
        exported_plist = project / "build/ios/waddlewars/waddlewars-Info.plist"

        def synthetic_export(command: list[str], log: Path) -> None:
            if "--export-release" in command:
                exported_plist.parent.mkdir(parents=True)
                exported_plist.write_bytes(plistlib.dumps({
                    **self.identity, **dict.fromkeys(UNUSED_IOS_PURPOSE_KEYS, "")}))

        version = subprocess.CompletedProcess(["synthetic-engine"], 0, "4.7.1.stable.synthetic\n")
        with patch("build_native.sys.argv", ["build_native.py", str(candidate), "--godot", "synthetic-engine"]), \
                patch("build_native.verify_snapshot"), \
                patch("install_ios_billing.verify_plugin"), \
                patch("build_native.subprocess.run", return_value=version), \
                patch("build_native.run_checked", side_effect=synthetic_export), \
                redirect_stdout(io.StringIO()):
            self.assertEqual(main(), 0)
        receipt = json.loads(receipt_path.read_text())
        relative = "project/build/ios/waddlewars/waddlewars-Info.plist"
        self.assertEqual(receipt["state"], "exported_unverified")
        self.assertEqual(receipt["ios_plist_policy"]["path"], relative)
        self.assertEqual(receipt["ios_plist_policy"]["removed_keys"], list(UNUSED_IOS_PURPOSE_KEYS))
        self.assertEqual(receipt["ios_plist_policy"]["after_sha256"], receipt["ios_display_name_policy"]["before_sha256"])
        self.assertEqual(receipt["ios_display_name_policy"]["after_sha256"], receipt["artifacts"][relative])
        self.assertEqual(plistlib.loads(exported_plist.read_bytes()), {**self.identity, "CFBundleDisplayName": "Waddle Wars: Penguin Panic"})
        self.assertFalse(receipt["store_ready"])
        self.assertEqual(receipt["import_metadata"], {
            "schema_version": 1, "state": "godot_import_metadata_frozen",
            "source_sha256": "a" * 64, "generated_uid_files": {},
        })

    def test_missing_candidate_title_rejected_before_engine_or_export(self) -> None:
        candidate = self.root / "old-prepared-candidate"
        candidate.mkdir()
        receipt_path = candidate / "receipt.json"
        original = {"state": "prepared_unbuilt", "platform": "ios"}
        receipt_path.write_text(json.dumps(original))
        with patch("build_native.sys.argv", ["build_native.py", str(candidate)]), \
                patch("build_native.verify_snapshot"), \
                patch("build_native.subprocess.run") as engine, \
                patch("build_native.run_checked") as export, \
                patch("build_native.sys.stderr", io.StringIO()):
            self.assertEqual(main(), 1)
        engine.assert_not_called()
        export.assert_not_called()
        self.assertEqual(json.loads(receipt_path.read_text()), original)


if __name__ == "__main__":
    unittest.main()
