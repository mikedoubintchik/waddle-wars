#!/usr/bin/env python3
"""Pure-host iOS distribution orchestration tests, with all signing mocked.

No Xcode, Keychain, profile verification, artifact signing, UI, network, or
downloads run. These tests validate orchestration, not a distribution artifact.
"""
from __future__ import annotations

import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import plistlib
import signal
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

import build_ios_distribution as distribution

APP = "Waddle Wars: Penguin Panic"
BUNDLE = "com.blubberandbyte.waddlewars"
TEAM = "V8MBW2V2C2"
CERT_SHA1 = "FDD4551BC510B9A31794CDA660864E324B883712"
CERT_SHA256 = "7ad1acf0fafea0b8988ef21250f3b5ed8e688032b0eda42b75075542bad33ebc"
UUID = "f4d77af5-95b7-445d-b64d-9b981b15bc5c"
PRIVATE = "SYNTHETIC_PROVIDER_TOKEN_DO_NOT_EXPOSE"


class IOSDistributionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.folder = tempfile.TemporaryDirectory(prefix="ww-ios-distribution-fixture-")
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name).resolve()
        self.checkout = self.root / "source"
        self.checkout.mkdir()
        self.candidate = self.root / "candidate"
        self.run = self.root / "run"
        self.run.mkdir(mode=0o700)
        self.xcodebuild = self.root / "xcodebuild"
        self.cms = self.root / "cms-helper"
        self.security = self.root / "security"
        self.profile = self.root / "exact-waddle.mobileprovision"
        self.own = self.checkout / "build_ios_distribution.py"
        self.verifier = self.checkout / "verify_ios_artifact.py"
        for tool in (self.xcodebuild, self.cms, self.security):
            self.write(tool, b"synthetic installed executable; never run", 0o700)
        for source in (self.own, self.verifier):
            self.write(source, b"synthetic release source; never run")
        self.write(self.profile, b"synthetic public CMS profile; never verified")
        prepared = {"project.godot": b"synthetic project", "scripts/fixture.gd": b"synthetic script",
                    "assets/fixture.png": b"synthetic texture", "export_presets.cfg": b"synthetic ios release preset"}
        info = plistlib.dumps({"CFBundleDisplayName": APP, "CFBundleIdentifier": BUNDLE,
                              "CFBundleVersion": "3", "CFBundleShortVersionString": "1.0.0"})
        artifacts = {"project/build/ios/waddlewars.xcodeproj/project.pbxproj": b"synthetic Xcode project",
                     "project/build/ios/waddlewars/waddlewars-Info.plist": info,
                     "project/build/ios/waddlewars.pck": b"synthetic immutable game bytes"}
        for name, data in prepared.items():
            self.write(self.candidate / "project" / name, data)
        for name, data in artifacts.items():
            self.write(self.candidate / name, data)
        source_files = {name: hashlib.sha256(data).hexdigest() for name, data in prepared.items() if name != "export_presets.cfg"}
        self.source_sha = hashlib.sha256(json.dumps(source_files, sort_keys=True).encode()).hexdigest()
        self.export_receipt = {"schema_version": 1, "state": "exported_unverified", "platform": "ios", "store_ready": False,
            "source_sha256": self.source_sha, "source_files": source_files,
            "bundle_id": BUNDLE, "app_name": APP, "version": "1.0.0", "build_number": 3,
            "prepared_files": {name: hashlib.sha256(data).hexdigest() for name, data in prepared.items()},
            "artifacts": {name: hashlib.sha256(data).hexdigest() for name, data in artifacts.items()}}
        self.write_export_receipt()
        self.profile_result = {"state": "profile_signature_and_metadata_verified", "metadata_valid": True,
            "profile_eligible_for_archive": True, "profile_uuid": UUID, "profile_name": "Waddle Wars App Store",
            "team_id": TEAM, "app_id": BUNDLE, "matched_certificate_sha1": CERT_SHA1,
            "matched_certificate_sha256": CERT_SHA256, "mobileprovision_sha256": distribution.digest(self.profile),
            "store_ready": False}
        self.config = {"bundle_id": BUNDLE, "app_name": APP}
        self.tool_files = [self.own, self.verifier, self.xcodebuild, self.cms, self.security]
        self.public_calls: list[tuple[list[str], dict]] = []
        self.build_calls: list[list[str]] = []
        self.before_build = None
        self.after_build = None
        self.after_archive_gate = None
        self.after_ipa_gate = None
        self.fail_build = False
        self.archive_gate_flags = {}
        self.ipa_gate_flags = {}
        self.identity_output = f'  1) {CERT_SHA1} "Apple Distribution: Ninja Consulting, LLC ({TEAM})"\n'
        self.version_output = "Xcode 26.6\nBuild version 17F113\n"
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(distribution, "ROOT", self.checkout))
        self.stack.enter_context(patch.object(distribution, "OWN_SOURCE", self.own))
        self.stack.enter_context(patch.object(distribution, "IDENTITY_TOOL", self.security))
        self.stack.enter_context(patch.object(distribution.native, "read_config", side_effect=lambda: self.config))
        self.stack.enter_context(patch.object(distribution, "tools", return_value=self.tool_files))
        self.candidate_gate = self.stack.enter_context(patch.object(distribution, "verify_candidate",
            side_effect=lambda *a, **k: {"receipt": self.export_receipt,
                "receipt_sha256": distribution.digest(self.candidate / "receipt.json"),
                "project_files": self.export_receipt["prepared_files"]}))
        self.inspect_profile = self.stack.enter_context(patch.object(distribution, "inspect_signed_profile", side_effect=lambda *a, **k: self.profile_result))
        self.stack.enter_context(patch.object(distribution.subprocess, "run", side_effect=self.public_tool))
        self.stack.enter_context(patch.object(distribution, "build_step", side_effect=self.build_tool))
        self.archive_gate = self.stack.enter_context(patch.object(distribution, "verify_archive", side_effect=self.archive_artifact))
        self.ipa_gate = self.stack.enter_context(patch.object(distribution, "verify_ipa", side_effect=self.ipa_artifact))

    @staticmethod
    def write(path: Path, data: bytes, mode: int = 0o600) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        path.chmod(mode)

    def write_export_receipt(self) -> None:
        self.write(self.candidate / "receipt.json", json.dumps(self.export_receipt).encode())

    def archive_arguments(self) -> dict:
        return {"receipt_sha256": distribution.digest(self.candidate / "receipt.json"), "source_sha256": self.source_sha,
                "team_id": TEAM, "certificate_sha1": CERT_SHA1, "certificate_sha256": CERT_SHA256,
                "installed_profile": self.profile, "profile_sha256": distribution.digest(self.profile),
                "cms_helper": self.cms, "cms_helper_sha256": distribution.digest(self.cms), "xcodebuild": self.xcodebuild}

    def archive(self, **overrides) -> dict:
        arguments = self.archive_arguments()
        arguments.update(overrides)
        return distribution.archive(self.candidate, self.run, **arguments)

    def ipa(self, **overrides) -> dict:
        arguments = {"archive_receipt_sha256": distribution.digest(self.run / "archive-verification-receipt.json"),
                     "cms_helper": self.cms, "cms_helper_sha256": distribution.digest(self.cms), "xcodebuild": self.xcodebuild}
        arguments.update(overrides)
        return distribution.ipa(self.run, **arguments)

    def public_tool(self, command: list[str], **kwargs) -> subprocess.CompletedProcess:
        self.public_calls.append((command, kwargs))
        self.assertNotIn(PRIVATE, json.dumps(kwargs.get("env", {})))
        if command[0] == str(self.security):
            return subprocess.CompletedProcess(command, 0, self.identity_output, "")
        self.assertEqual(command, [str(self.xcodebuild), "-version"])
        if self.before_build:
            self.before_build()
        return subprocess.CompletedProcess(command, 0, self.version_output, "")

    def build_tool(self, command: list[str], log: Path, marker: str) -> dict:
        self.build_calls.append(command)
        self.assertNotIn("-allowProvisioningUpdates", command)
        self.assertNotIn("-allowProvisioningDeviceRegistration", command)
        self.write(log, (marker + "\n").encode())
        if self.fail_build:
            raise ValueError("Synthetic Xcode failure, outputs preserved")
        if "archive" in command:
            path = Path(command[command.index("-archivePath") + 1])
            app = path / "Products/Applications/waddlewars.app"
            self.write(app / "Info.plist", (self.candidate / "project/build/ios/waddlewars/waddlewars-Info.plist").read_bytes())
            self.write(app / "waddlewars", b"synthetic executable; not signed")
            self.write(app / "waddlewars.pck", b"synthetic immutable game bytes")
            self.write(app / "embedded.mobileprovision", self.profile.read_bytes())
        else:
            self.assertIn("-exportArchive", command)
            path = Path(command[command.index("-exportPath") + 1])
            self.write(path / "waddlewars.ipa", b"synthetic IPA; not a distribution artifact")
        if self.after_build:
            self.after_build()
        return {"exit_code": 0, "timed_out": False, "success_marker_seen": True, "log_sha256": distribution.digest(log)}

    def archive_artifact(self, candidate: Path, archive: Path, evidence: Path, **pins) -> dict:
        app = archive / "Products/Applications/waddlewars.app"
        result = {"schema_version": 1, "state": "signed_archive_verified",
            "signed_archive_verified": True, "store_ready": False, "archive_path": str(archive),
            "candidate_path": str(candidate), "candidate_receipt_sha256": distribution.digest(candidate / "receipt.json"),
            "source_sha256": self.source_sha, "source_files": self.export_receipt["source_files"],
            "version": "1.0.0", "build_number": 3, "app_name": APP,
            "team_id": TEAM, "bundle_id": BUNDLE, "signer_certificate_sha1": CERT_SHA1,
            "signer_certificate_sha256": CERT_SHA256, "profile": self.profile_result,
            "archive_app_file_sha256": {p.name: distribution.digest(p) for p in app.iterdir() if p.is_file()}}
        result.update(self.archive_gate_flags)
        if self.after_archive_gate:
            self.after_archive_gate()
        return result

    def ipa_artifact(self, *arguments, **pins) -> dict:
        result = {"schema_version": 1, "state": "ipa_verified", "ipa_verified": True, "store_ready": False,
            "source_sha256": self.source_sha, "version": "1.0.0", "build_number": 3,
            "team_id": TEAM, "bundle_id": BUNDLE, "app_name": APP}
        result.update(self.ipa_gate_flags)
        if self.after_ipa_gate:
            self.after_ipa_gate()
        return result

    def record(self, name: str = "archive-invocation.json") -> dict:
        return json.loads((self.run / name).read_text())

    def replace_archive_receipt(self, changes: dict) -> None:
        path = self.run / "archive-verification-receipt.json"
        current = json.loads(path.read_text())
        current.update(changes)
        self.write(path, json.dumps(current).encode())
        invocation = self.record()
        invocation["archive_verification_receipt_sha256"] = distribution.digest(path)
        self.write(self.run / "archive-invocation.json", json.dumps(invocation).encode())

    def assert_archive_failed(self) -> None:
        result = self.record()
        self.assertEqual(result["state"], "ios_archive_failed_preserved")
        self.assertIs(result["store_ready"], False)
        self.assertFalse((self.run / "archive-verification-receipt.json").exists())

    def assert_ipa_failed(self) -> None:
        result = self.record("ipa-invocation.json")
        self.assertEqual(result["state"], "ios_ipa_failed_preserved")
        self.assertIs(result["store_ready"], False)
        self.assertFalse((self.run / "ipa-verification-receipt.json").exists())

    def test_archive_delegates_exact_identity_and_remains_offline_not_store_ready(self) -> None:
        result = self.archive()
        self.assertEqual(result["state"], "ios_archive_verified_offline")
        for name in ("store_ready", "uploaded", "automatic_provisioning", "new_key_or_profile_created", "private_key_read_or_export_requested"):
            self.assertIs(result[name], False)
        command = self.build_calls[0]
        self.assertIn("CODE_SIGN_STYLE=Manual", command)
        self.assertIn("DEVELOPMENT_TEAM=" + TEAM, command)
        self.assertIn("CODE_SIGN_IDENTITY=" + CERT_SHA1, command)
        self.assertIn("PROVISIONING_PROFILE_SPECIFIER=" + UUID, command)
        self.archive_gate.assert_called_once_with(self.candidate, self.run / "WaddleWars-build3.xcarchive",
            self.run / "archive-verification", team_id=TEAM, certificate_sha1=CERT_SHA1, certificate_sha256=CERT_SHA256,
            installed_profile=self.profile, profile_sha256=distribution.digest(self.profile), cms_helper=self.cms,
            cms_helper_sha256=distribution.digest(self.cms))
        self.assertEqual(result["archive_verification_receipt_sha256"], distribution.digest(self.run / "archive-verification-receipt.json"))
        self.assertEqual(stat.S_IMODE((self.run / "archive-invocation.json").stat().st_mode), 0o600)

    def test_ipa_uses_manual_local_export_recipe_and_mandatory_artifact_gate(self) -> None:
        self.archive()
        result = self.ipa()
        self.assertEqual(result["state"], "ios_ipa_verified_offline")
        self.assertIs(result["uploaded"], False)
        self.assertIs(result["store_ready"], False)
        self.assertIs(result["automatic_provisioning"], False)
        self.assertIs(result["new_key_or_profile_created"], False)
        options = plistlib.loads((self.run / "export-options.plist").read_bytes())
        self.assertEqual(options, {"destination": "export", "method": "app-store-connect", "signingStyle": "manual",
            "teamID": TEAM, "signingCertificate": CERT_SHA1, "provisioningProfiles": {BUNDLE: UUID},
            "manageAppVersionAndBuildNumber": False, "generateAppStoreInformation": False, "uploadSymbols": False})
        self.assertEqual(stat.S_IMODE((self.run / "export-options.plist").stat().st_mode), 0o600)
        output = self.run / "ipa-export/waddlewars.ipa"
        self.assertEqual(result["artifact"]["sha256"], distribution.digest(output))
        self.ipa_gate.assert_called_once_with(output, self.run / "WaddleWars-build3.xcarchive",
            self.run / "archive-verification-receipt.json", self.run / "ipa-verification",
            ipa_sha256=distribution.digest(output), archive_receipt_sha256=distribution.digest(self.run / "archive-verification-receipt.json"),
            cms_helper=self.cms, cms_helper_sha256=distribution.digest(self.cms))

    def test_invalid_public_pins_rejected_before_preflight_or_build(self) -> None:
        for name in ("receipt_sha256", "source_sha256", "certificate_sha1", "certificate_sha256", "profile_sha256", "cms_helper_sha256"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.archive(**{name: "not-a-public-pin"})
        self.assertEqual(self.public_calls, [])
        self.assertEqual(self.build_calls, [])

    def test_wrong_receipt_or_source_pin_rejected_before_signing(self) -> None:
        for name in ("receipt_sha256", "source_sha256"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.archive(**{name: "b" * 64})
        self.assertEqual(self.build_calls, [])

    def test_wrong_profile_helper_pin_rejected_before_signing(self) -> None:
        for name in ("profile_sha256", "cms_helper_sha256"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.archive(**{name: "b" * 64})
        self.inspect_profile.assert_not_called()
        self.assertEqual(self.build_calls, [])

    def test_profile_public_der_identity_pin_mismatch_refused_before_signing(self) -> None:
        with self.assertRaises(ValueError):
            self.archive(certificate_sha256="0" * 64)
        self.assertEqual(self.build_calls, [])

    def test_invalid_team_rejected(self) -> None:
        with self.assertRaises(ValueError):
            self.archive(team_id="synthetic-invalid")
        self.assertEqual(self.build_calls, [])

    def test_identity_missing_or_duplicate_is_not_accepted(self) -> None:
        for output in ("0 valid identities found\n", self.identity_output * 2):
            self.identity_output = output
            with self.subTest(output=output), self.assertRaises(ValueError):
                self.archive()
        self.assertEqual(self.build_calls, [])

    def test_future_or_unreviewed_xcode_major_rejected_before_build(self) -> None:
        for version in ("Xcode 25.0\nBuild version ABC\n", "Xcode 27.0\nBuild version ABC\n", "malformed version"):
            self.version_output = version
            with self.subTest(version=version), self.assertRaises(ValueError):
                self.archive()
        self.assertEqual(self.build_calls, [])

    def test_nonprivate_run_rejected_without_changing_permissions(self) -> None:
        self.run.chmod(0o755)
        with self.assertRaises(ValueError):
            self.archive()
        self.assertEqual(stat.S_IMODE(self.run.stat().st_mode), 0o755)

    def test_checkout_run_refused(self) -> None:
        self.run = self.checkout
        self.run.chmod(0o700)
        with self.assertRaises(ValueError):
            self.archive()

    def test_symlinked_run_or_candidate_parent_refused(self) -> None:
        original = self.run
        linked = self.root / "linked-run"
        linked.symlink_to(original, target_is_directory=True)
        self.run = linked
        with self.assertRaises(ValueError):
            self.archive()
        self.run = original
        linked_candidate = self.root / "linked-candidate"
        linked_candidate.symlink_to(self.candidate, target_is_directory=True)
        self.candidate = linked_candidate
        with self.assertRaises(ValueError):
            self.archive()

    def test_relative_or_traversal_run_refused(self) -> None:
        for run in (Path("relative-run"), self.root / "unused/../run"):
            self.run = run
            with self.subTest(run=run), self.assertRaises(ValueError):
                self.archive()

    def test_every_existing_archive_destination_refuses_overwrite(self) -> None:
        for index, name in enumerate(("WaddleWars-build3.xcarchive", "Archive-build3.xcresult", "DerivedData",
                                      "archive-invocation.json", "archive-verification-receipt.json", "archive.log", "archive-verification")):
            self.run = self.root / ("run-existing-" + str(index))
            self.run.mkdir(mode=0o700)
            self.write(self.run / name, b"prior output must survive")
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.archive()
            self.assertEqual((self.run / name).read_bytes(), b"prior output must survive")
        self.assertEqual(self.build_calls, [])

    def test_prepared_and_exported_mutation_refused_before_build(self) -> None:
        for index, name in enumerate(("project/scripts/fixture.gd", "project/build/ios/waddlewars.pck")):
            original = (self.candidate / name).read_bytes()
            (self.candidate / name).write_bytes(b"changed frozen source")
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.archive()
            (self.candidate / name).write_bytes(original)
        self.assertEqual(self.build_calls, [])

    def test_candidate_false_store_flag_is_strict_boolean(self) -> None:
        for value in (True, 0, None, "false"):
            self.export_receipt["store_ready"] = value
            self.write_export_receipt()
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.archive()
        self.assertEqual(self.build_calls, [])

    def test_ios_launcher_override_flows_through_archive_and_ipa(self) -> None:
        self.config["ios"] = {"display_name": APP}
        self.config["app_name"] = "Separate store listing title"
        self.archive()
        self.ipa()
        self.assertEqual(len(self.build_calls), 2)

    def test_changed_ios_launcher_name_rejects_stale_candidate(self) -> None:
        self.config["ios"] = {"display_name": "Waddle Wars"}
        with self.assertRaisesRegex(ValueError, "identity/state"):
            self.archive()
        self.assertEqual(self.build_calls, [])

    def test_candidate_identity_platform_state_version_and_build_gate(self) -> None:
        original = dict(self.export_receipt)
        for name, value in (("state", "prepared_unbuilt"), ("platform", "android"), ("bundle_id", "wrong.app.id"),
                            ("app_name", "Waddle Wars"), ("version", "bad"), ("build_number", True), ("build_number", 0)):
            self.export_receipt = {**original, name: value}
            self.write_export_receipt()
            with self.subTest(name=name, value=value), self.assertRaises(ValueError):
                self.archive()
        self.assertEqual(self.build_calls, [])

    def test_unsafe_inventory_paths_refused_without_build(self) -> None:
        original = dict(self.export_receipt)
        for field in ("prepared_files", "artifacts"):
            for name in ("../escape", "/absolute", "relative//double", "./dot", "nested/../escape", "back\\slash"):
                self.export_receipt = {**original, field: {name: "a" * 64}}
                self.write_export_receipt()
                with self.subTest(field=field, name=name), self.assertRaises(ValueError):
                    self.archive()
        self.assertEqual(self.build_calls, [])

    def test_missing_or_nonobject_inventories_refused(self) -> None:
        original = dict(self.export_receipt)
        for field in ("prepared_files", "artifacts"):
            for value in ({}, [], None):
                self.export_receipt = {**original, field: value}
                self.write_export_receipt()
                with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                    self.archive()

    def test_duplicate_export_json_keys_refused_before_preflight(self) -> None:
        path = self.candidate / "receipt.json"
        data = json.dumps(self.export_receipt)
        path.write_text(data[:-1] + ', "platform":"ios"}')
        with self.assertRaises(ValueError):
            self.archive()
        self.assertEqual(self.build_calls, [])

    def test_oversize_export_json_receipt_refused_before_preflight(self) -> None:
        self.export_receipt["untrusted_padding"] = "x" * (8 * 1024 ** 2 + 1)
        self.write_export_receipt()
        with self.assertRaises(ValueError):
            self.archive()
        self.assertEqual(self.build_calls, [])

    def test_artifact_candidate_gate_failure_prevents_archive(self) -> None:
        self.candidate_gate.side_effect = ValueError("Synthetic frozen candidate rejected")
        with self.assertRaises(ValueError):
            self.archive()
        self.assertEqual(self.build_calls, [])

    def test_artifact_candidate_gate_mismatched_identity_refused(self) -> None:
        self.candidate_gate.side_effect = None
        self.candidate_gate.return_value = {"receipt": self.export_receipt,
            "receipt_sha256": "b" * 64, "project_files": self.export_receipt["prepared_files"]}
        with self.assertRaises(ValueError):
            self.archive()
        self.assertEqual(self.build_calls, [])

    def test_import_metadata_supplement_frozen_during_archive(self) -> None:
        supplement = self.candidate / "import-metadata.json"
        self.write(supplement, b'{"synthetic_public_import_metadata":true}')
        self.after_build = lambda: self.write(supplement, b'{"changed_import_metadata":true}')
        with self.assertRaisesRegex(ValueError, "release input changed"):
            self.archive()
        self.archive_gate.assert_not_called()
        self.assert_archive_failed()

    def test_additional_verifier_project_files_frozen_during_archive(self) -> None:
        path = self.candidate / "project/.godot/imported/synthetic.ctex"
        self.write(path, b"synthetic imported texture; not authored inventory")
        self.candidate_gate.side_effect = lambda *a, **k: {"receipt": self.export_receipt,
            "receipt_sha256": distribution.digest(self.candidate / "receipt.json"),
            "project_files": {**self.export_receipt["prepared_files"],
                ".godot/imported/synthetic.ctex": distribution.digest(path)}}
        self.after_build = lambda: self.write(path, b"changed imported texture")
        with self.assertRaisesRegex(ValueError, "release input changed"):
            self.archive()
        self.archive_gate.assert_not_called()
        self.assert_archive_failed()

    def test_title_mismatch_refused_even_with_recomputed_public_export_hash(self) -> None:
        relative = "project/build/ios/waddlewars/waddlewars-Info.plist"
        self.write(self.candidate / relative, plistlib.dumps({"CFBundleDisplayName": "Waddle Wars"}))
        self.export_receipt["artifacts"][relative] = distribution.digest(self.candidate / relative)
        self.write_export_receipt()
        with self.assertRaisesRegex(ValueError, "title mismatch"):
            self.archive()
        self.assertEqual(self.build_calls, [])

    def test_mutation_during_preflight_fails_before_xcode_archive(self) -> None:
        self.before_build = lambda: self.verifier.write_bytes(b"changed release source")
        with self.assertRaisesRegex(ValueError, "release input changed"):
            self.archive()
        self.assertEqual(self.build_calls, [])
        self.assert_archive_failed()

    def test_mutation_during_archive_rejected_before_artifact_gate(self) -> None:
        self.after_build = lambda: (self.candidate / "project/scripts/fixture.gd").write_bytes(b"changed source")
        with self.assertRaisesRegex(ValueError, "release input changed"):
            self.archive()
        self.archive_gate.assert_not_called()
        self.assert_archive_failed()

    def test_mutation_inside_archive_gate_discards_acceptance(self) -> None:
        self.after_archive_gate = lambda: self.cms.write_bytes(b"changed helper")
        with self.assertRaisesRegex(ValueError, "release input changed"):
            self.archive()
        self.assert_archive_failed()

    def test_build_failure_preserves_failed_state_and_log(self) -> None:
        self.fail_build = True
        with self.assertRaises(ValueError):
            self.archive()
        self.assert_archive_failed()
        self.assertTrue((self.run / "archive.log").is_file())

    def test_false_archive_gate_flags_rejected_not_promoted(self) -> None:
        for index, flags in enumerate(({"signed_archive_verified": False}, {"signed_archive_verified": 1},
                                        {"store_ready": True}, {"store_ready": 0})):
            self.run = self.root / ("false-archive-gate-" + str(index))
            self.run.mkdir(mode=0o700)
            self.archive_gate_flags = flags
            with self.subTest(flags=flags), self.assertRaises(ValueError):
                self.archive()
            self.assert_archive_failed()

    def test_second_archive_or_ipa_never_overwrites_first_attempt(self) -> None:
        first = self.archive()
        with self.assertRaises(ValueError):
            self.archive()
        self.assertEqual(self.record()["state"], first["state"])
        self.ipa()
        original = (self.run / "ipa-invocation.json").read_bytes()
        with self.assertRaises(ValueError):
            self.ipa()
        self.assertEqual((self.run / "ipa-invocation.json").read_bytes(), original)

    def test_changed_archive_gate_receipt_pin_refused_before_export(self) -> None:
        self.archive()
        with self.assertRaises(ValueError):
            self.ipa(archive_receipt_sha256="b" * 64)
        self.assertEqual(len(self.build_calls), 1)

    def test_changed_archive_app_refused_before_export(self) -> None:
        self.archive()
        self.write(self.run / "WaddleWars-build3.xcarchive/Products/Applications/waddlewars.app/waddlewars.pck", b"changed archived game")
        with self.assertRaises(ValueError):
            self.ipa()
        self.assertEqual(len(self.build_calls), 1)

    def test_absolute_archive_app_inventory_path_refused_before_export(self) -> None:
        self.archive()
        outside = self.root / "outside-archive-public-fixture.bin"
        self.write(outside, b"synthetic public fixture must not be treated as archive content")
        self.replace_archive_receipt({"archive_app_file_sha256": {str(outside): distribution.digest(outside)}})
        with self.assertRaises(ValueError):
            self.ipa()
        self.assertEqual(len(self.build_calls), 1)

    def test_ambiguous_dot_archive_app_inventory_path_refused_before_export(self) -> None:
        self.archive()
        app = self.run / "WaddleWars-build3.xcarchive/Products/Applications/waddlewars.app"
        self.replace_archive_receipt({"archive_app_file_sha256": {"./waddlewars.pck": distribution.digest(app / "waddlewars.pck")}})
        with self.assertRaises(ValueError):
            self.ipa()
        self.assertEqual(len(self.build_calls), 1)

    def test_empty_frozen_invocation_inventory_refused_before_export(self) -> None:
        self.archive()
        invocation = self.record()
        invocation["input_sha256"] = {}
        self.write(self.run / "archive-invocation.json", json.dumps(invocation).encode())
        with self.assertRaises(ValueError):
            self.ipa()
        self.assertEqual(len(self.build_calls), 1)

    def test_wrong_ipa_identity_cannot_select_another_team_or_signer(self) -> None:
        self.archive()
        self.replace_archive_receipt({"team_id": "WRONG12345"})
        with self.assertRaises(ValueError):
            self.ipa()
        self.assertEqual(len(self.build_calls), 1)

    def test_changed_frozen_export_source_refused_before_ipa_export(self) -> None:
        self.archive()
        self.write(self.candidate / "project/scripts/fixture.gd", b"changed source after archive")
        with self.assertRaises(ValueError):
            self.ipa()
        self.assertEqual(len(self.build_calls), 1)

    def test_matching_archive_invocation_and_helper_are_required(self) -> None:
        self.archive()
        path = self.run / "archive-invocation.json"
        original = self.record()
        for name, value in (("state", "archiving"), ("archive_verification_receipt_sha256", "b" * 64),
                            ("cms_helper", "/wrong/helper"), ("cms_helper_sha256", "b" * 64), ("archive_path", "/wrong/archive")):
            self.write(path, json.dumps({**original, name: value}).encode())
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.ipa()
        self.assertEqual(len(self.build_calls), 1)

    def test_false_ipa_gate_flags_rejected_not_promoted(self) -> None:
        for index, flags in enumerate(({"ipa_verified": False}, {"ipa_verified": 1}, {"store_ready": True}, {"store_ready": 0})):
            self.run = self.root / ("false-ipa-gate-" + str(index))
            self.run.mkdir(mode=0o700)
            self.archive()
            self.ipa_gate_flags = flags
            with self.subTest(flags=flags), self.assertRaises(ValueError):
                self.ipa()
            self.assert_ipa_failed()

    def test_export_failure_preserves_ipa_state_and_log(self) -> None:
        self.archive()
        self.fail_build = True
        with self.assertRaises(ValueError):
            self.ipa()
        self.assert_ipa_failed()
        self.assertTrue((self.run / "ipa-export.log").is_file())

    def test_recipe_mutation_during_export_refused_before_artifact_gate(self) -> None:
        self.archive()
        self.after_build = lambda: self.write(self.run / "export-options.plist", b"changed recipe")
        with self.assertRaisesRegex(ValueError, "release input changed"):
            self.ipa()
        self.ipa_gate.assert_not_called()
        self.assert_ipa_failed()

    def test_tool_mutation_inside_ipa_gate_discards_acceptance(self) -> None:
        self.archive()
        self.after_ipa_gate = lambda: self.verifier.write_bytes(b"changed verifier")
        with self.assertRaises(ValueError):
            self.ipa()
        self.assert_ipa_failed()

    def test_ipa_mutation_inside_gate_discards_acceptance(self) -> None:
        self.archive()
        self.after_ipa_gate = lambda: self.write(self.run / "ipa-export/waddlewars.ipa", b"changed IPA")
        with self.assertRaisesRegex(ValueError, "IPA changed"):
            self.ipa()
        self.assert_ipa_failed()

    def test_original_candidate_mutation_inside_ipa_gate_discards_acceptance(self) -> None:
        self.archive()
        self.after_ipa_gate = lambda: self.write(self.candidate / "project/assets/fixture.png", b"changed source")
        with self.assertRaises(ValueError):
            self.ipa()
        self.assert_ipa_failed()

    def test_unrelated_credentials_and_option_injection_never_reach_tools(self) -> None:
        names = ("APPLE_PASSWORD", "FASTLANE_SESSION", "CLERK_SECRET_KEY", "STRIPE_SECRET_KEY", "JAVA_TOOL_OPTIONS",
                 "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD", "DEVELOPER_DIR", "DYLD_INSERT_LIBRARIES")
        with patch.dict(os.environ, {name: PRIVATE for name in names}, clear=False):
            self.archive()
            self.ipa()
            child_environment = distribution.environment()
        self.assertNotIn(PRIVATE, json.dumps(child_environment))
        for name in names:
            self.assertNotIn(name, child_environment)
        for path in self.run.rglob("*.json"):
            self.assertNotIn(PRIVATE, path.read_text())


class IOSBuildStepTests(unittest.TestCase):
    def setUp(self) -> None:
        self.folder = tempfile.TemporaryDirectory(prefix="ww-ios-xcode-step-fixture-")
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name).resolve()
        self.log = self.root / "archive.log"
        self.marker = "** ARCHIVE SUCCEEDED **"
        self.child = Mock(pid=4123123, returncode=0)
        self.child.communicate.return_value = (self.marker + "\n", None)
        self.spawn = patch.object(distribution.subprocess, "Popen", return_value=self.child)
        self.spawn_mock = self.spawn.start()
        self.addCleanup(self.spawn.stop)
        self.kill = patch.object(distribution.os, "killpg")
        self.kill_mock = self.kill.start()
        self.addCleanup(self.kill.stop)

    def run_step(self) -> dict:
        with contextlib.redirect_stdout(io.StringIO()):
            return distribution.build_step(["synthetic-xcodebuild", "archive"], self.log, self.marker)

    def test_exact_terminal_success_marker_exit_and_private_log(self) -> None:
        result = self.run_step()
        self.assertTrue(result["success_marker_seen"])
        self.assertFalse(result["timed_out"])
        self.assertEqual(result["exit_code"], 0)
        self.assertEqual(stat.S_IMODE(self.log.stat().st_mode), 0o600)
        self.child.communicate.assert_called_once_with(timeout=1200)
        self.assertTrue(self.spawn_mock.call_args.kwargs["start_new_session"])

    def test_nonzero_even_with_success_marker_preserves_log_and_fails(self) -> None:
        self.child.returncode = 65
        with self.assertRaises(ValueError):
            self.run_step()
        self.assertIn(self.marker, self.log.read_text())

    def test_zero_without_terminal_marker_preserves_log_and_fails(self) -> None:
        self.child.communicate.return_value = ("synthetic incomplete Xcode output\n", None)
        with self.assertRaises(ValueError):
            self.run_step()
        self.assertIn("incomplete", self.log.read_text())

    def test_success_marker_inside_diagnostic_is_not_terminal_success(self) -> None:
        self.child.communicate.return_value = ("warning: expected terminal marker " + self.marker + " not present\n", None)
        with self.assertRaises(ValueError):
            self.run_step()
        self.assertTrue(self.log.is_file())

    def test_account_and_credential_diagnostics_fully_redacted(self) -> None:
        self.child.communicate.return_value = ("ordinary compiler progress\nAccount session failed " + PRIVATE + "\nAuthorization Bearer " + PRIVATE + "\n" + self.marker + "\n", None)
        result = self.run_step()
        self.assertEqual(result["redacted_account_diagnostic_lines"], 2)
        self.assertNotIn(PRIVATE, self.log.read_text())
        self.assertIn("ordinary compiler progress", self.log.read_text())

    def test_timeout_terminates_group_preserves_logs_even_if_late_success(self) -> None:
        self.child.communicate.side_effect = [subprocess.TimeoutExpired("synthetic", 1200), (self.marker + "\n", None)]
        with self.assertRaises(ValueError):
            self.run_step()
        self.kill_mock.assert_called_once_with(self.child.pid, signal.SIGTERM)
        self.assertTrue(self.log.is_file())

    def test_timeout_escalates_to_kill_once_and_preserves_log(self) -> None:
        self.child.communicate.side_effect = [subprocess.TimeoutExpired("synthetic", 1200),
            subprocess.TimeoutExpired("synthetic", 5), ("partial final output\n", None)]
        with self.assertRaises(ValueError):
            self.run_step()
        self.assertEqual(self.kill_mock.call_args_list[0].args, (self.child.pid, signal.SIGTERM))
        self.assertEqual(self.kill_mock.call_args_list[1].args, (self.child.pid, signal.SIGKILL))
        self.assertEqual(self.log.read_text(), "partial final output\n")

    def test_existing_log_never_overwritten_or_process_launched(self) -> None:
        self.log.write_text("prior output")
        with self.assertRaises(ValueError):
            self.run_step()
        self.spawn_mock.assert_not_called()
        self.assertEqual(self.log.read_text(), "prior output")

    def test_symlinked_log_refused_before_launch(self) -> None:
        target = self.root / "target.log"
        target.write_text("prior output")
        self.log.symlink_to(target)
        with self.assertRaises(ValueError):
            self.run_step()
        self.spawn_mock.assert_not_called()
        self.assertEqual(target.read_text(), "prior output")

    def test_public_preflight_nonzero_oversize_or_timeout_discards_raw_output(self) -> None:
        for result in (subprocess.CompletedProcess([], 1, PRIVATE, PRIVATE),
                       subprocess.CompletedProcess([], 0, "x" * (1024 ** 2 + 1), PRIVATE)):
            with patch.object(distribution.subprocess, "run", return_value=result):
                with self.assertRaises(ValueError) as caught:
                    distribution.checked_public(["synthetic-preflight"])
                self.assertNotIn(PRIVATE, str(caught.exception))
        with patch.object(distribution.subprocess, "run", side_effect=subprocess.TimeoutExpired("synthetic", 60)):
            with self.assertRaises(subprocess.TimeoutExpired):
                distribution.checked_public(["synthetic-preflight"])


if __name__ == "__main__":
    unittest.main()
