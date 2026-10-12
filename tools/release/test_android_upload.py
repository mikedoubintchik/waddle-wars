#!/usr/bin/env python3
"""Pure-host unsigned-export/signature-boundary regressions.

All ZIPs, SDK/template bytes and public tool fixtures are synthetic. Engines,
signatures and mandatory release verification are mocked at external boundaries;
no private credentials, builds, Keychain, devices, downloads or stores are used.
"""
from __future__ import annotations

import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import warnings
import zipfile

import build_android_debug as debug
import build_android_integration_qa as integration
import build_android_upload as upload
import native_release as native


PAYLOAD = {
    "BundleConfig.pb": b"synthetic bundle config, not an actual build",
    "base/manifest/AndroidManifest.xml": b"synthetic protobuf manifest",
    "base/dex/classes.dex": b"synthetic DEX",
    "assetPackInstallTime/assets/project.binary": b"synthetic Godot project",
    "assetPackInstallTime/assets/assets.sparsepck": b"synthetic game resources",
}
METADATA = {
    "META-INF/MANIFEST.MF": b"Manifest-Version: 1.0\r\n\r\n",
    "META-INF/UPLOAD.SF": b"synthetic signature manifest",
    "META-INF/UPLOAD.RSA": b"synthetic signature block; not a real signature",
}


def write_zip(path: Path, entries: dict | list, *, compression: int = zipfile.ZIP_STORED) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", UserWarning)
        with zipfile.ZipFile(path, "w", compression=compression) as archive:
            for name, data in (entries.items() if isinstance(entries, dict) else entries):
                archive.writestr(name, data)


class PayloadBoundaryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.folder = tempfile.TemporaryDirectory(prefix="ww-upload-payload-fixture-")
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name).resolve()
        self.bundle = self.root / "synthetic.aab"

    def test_payload_digest_covers_every_non_signature_byte(self) -> None:
        write_zip(self.bundle, PAYLOAD)
        expected = {name: hashlib.sha256(value).hexdigest() for name, value in PAYLOAD.items()}
        self.assertEqual(upload.artifact_payload(self.bundle, unsigned=True), expected)

    def test_signing_metadata_only_leaves_payload_immutable(self) -> None:
        write_zip(self.bundle, PAYLOAD)
        original = upload.artifact_payload(self.bundle, unsigned=True)
        write_zip(self.bundle, {**PAYLOAD, **METADATA})
        self.assertEqual(upload.artifact_payload(self.bundle), original)

    def test_unsigned_signature_metadata_is_rejected(self) -> None:
        for name, data in METADATA.items():
            with self.subTest(name=name):
                write_zip(self.bundle, {**PAYLOAD, name: data})
                with self.assertRaisesRegex(ValueError, "signature metadata"):
                    upload.artifact_payload(self.bundle, unsigned=True)

    def test_similar_metadata_names_are_payload_not_signature_exemptions(self) -> None:
        names = ("META-INF/UPLOAD.RSA.EXTRA", "META-INF/upload.rsa", "META-INF/TOOLONG123.SF",
                 "META-INF/services/plugin", "assets/META-INF/UPLOAD.RSA")
        for name in names:
            with self.subTest(name=name):
                write_zip(self.bundle, {**PAYLOAD, name: b"must be hashed"})
                self.assertIn(name, upload.artifact_payload(self.bundle, unsigned=True))

    def test_duplicate_and_casefold_alias_entries_are_rejected(self) -> None:
        for duplicate in ("BundleConfig.pb", "bundleconfig.pb"):
            with self.subTest(duplicate=duplicate):
                write_zip(self.bundle, [*PAYLOAD.items(), (duplicate, b"ambiguous replacement")])
                with self.assertRaisesRegex(ValueError, "duplicate"):
                    upload.artifact_payload(self.bundle)

    def test_unsafe_archive_paths_are_rejected(self) -> None:
        for name in ("/absolute", "../escape", "base/../escape", "base//entry", "./entry",
                     "base/./entry", "base\\entry", "space in name", "tab\tname", "nonascii-é"):
            with self.subTest(name=name):
                write_zip(self.bundle, {**PAYLOAD, name: b"unsafe"})
                with self.assertRaisesRegex(ValueError, "Unsafe"):
                    upload.artifact_payload(self.bundle)

    def test_zip_symlink_and_nonregular_entries_are_rejected(self) -> None:
        for mode in (0o120777, 0o020600, 0o010600):
            with self.subTest(mode=oct(mode)):
                item = zipfile.ZipInfo("base/unsafe")
                item.create_system = 3
                item.external_attr = mode << 16
                write_zip(self.bundle, [*PAYLOAD.items(), (item, b"unsafe")])
                with self.assertRaisesRegex(ValueError, "Unsafe"):
                    upload.artifact_payload(self.bundle)

    def test_directory_mode_and_name_must_agree(self) -> None:
        for name, mode in (("base/not-a-directory", 0o040755), ("base/not-a-file/", 0o100644)):
            with self.subTest(name=name):
                item = zipfile.ZipInfo(name)
                item.create_system = 3
                item.external_attr = mode << 16
                write_zip(self.bundle, [*PAYLOAD.items(), (item, b"")])
                with self.assertRaisesRegex(ValueError, "Unsafe"):
                    upload.artifact_payload(self.bundle)

    def test_nonempty_directory_is_rejected(self) -> None:
        write_zip(self.bundle, {**PAYLOAD, "base/bad/": b"directory payload"})
        with self.assertRaises(ValueError):
            upload.artifact_payload(self.bundle)

    def test_empty_directories_do_not_change_payload(self) -> None:
        write_zip(self.bundle, {**PAYLOAD, "base/empty/": b""})
        self.assertEqual(set(upload.artifact_payload(self.bundle)), set(PAYLOAD))

    def test_only_reviewed_stored_and_deflated_compression_is_allowed(self) -> None:
        for compression in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
            with self.subTest(allowed=compression):
                write_zip(self.bundle, PAYLOAD, compression=compression)
                self.assertEqual(set(upload.artifact_payload(self.bundle)), set(PAYLOAD))
        for compression in (zipfile.ZIP_BZIP2, zipfile.ZIP_LZMA):
            with self.subTest(rejected=compression):
                write_zip(self.bundle, PAYLOAD, compression=compression)
                with self.assertRaises(ValueError):
                    upload.artifact_payload(self.bundle)

    def test_empty_or_only_signature_archives_are_rejected(self) -> None:
        for entries in ({}, METADATA):
            with self.subTest(entries=list(entries)):
                write_zip(self.bundle, entries)
                with self.assertRaises(ValueError):
                    upload.artifact_payload(self.bundle)

    def test_relative_missing_and_file_symlink_rejected_before_hashing(self) -> None:
        write_zip(self.bundle, PAYLOAD)
        linked = self.root / "linked.aab"
        linked.symlink_to(self.bundle)
        for path in (Path("relative.aab"), self.root / "missing.aab", linked):
            with self.subTest(path=path), patch.object(upload.zipfile, "ZipFile") as archive:
                with self.assertRaisesRegex(ValueError, "absolute regular file"):
                    upload.artifact_payload(path)
                archive.assert_not_called()

    def test_corrupt_zip_cannot_produce_payload_receipt(self) -> None:
        self.bundle.write_bytes(b"not a ZIP")
        with self.assertRaises(zipfile.BadZipFile):
            upload.artifact_payload(self.bundle)

    def test_encrypted_inventory_is_rejected_before_reading_member_bytes(self) -> None:
        write_zip(self.bundle, PAYLOAD)
        data = bytearray(self.bundle.read_bytes())
        local = data.find(b"PK\x03\x04")
        central = data.find(b"PK\x01\x02")
        self.assertGreaterEqual(local, 0)
        self.assertGreaterEqual(central, 0)
        struct.pack_into("<H", data, local + 6, 1)
        struct.pack_into("<H", data, central + 8, 1)
        self.bundle.write_bytes(data)
        with self.assertRaisesRegex(ValueError, "Unsafe"):
            upload.artifact_payload(self.bundle)


class UploadWorkflowTests(unittest.TestCase):
    def setUp(self) -> None:
        self.folder = tempfile.TemporaryDirectory(prefix="ww-upload-workflow-fixture-")
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name).resolve()
        self.source = self.root / "source"
        self.source.mkdir()
        self.candidate = self.root / "candidate"
        self.sdk = self.root / "sdk"
        self.jdk = self.root / "jdk"
        self.templates = self.root / "4.7.1.stable"
        self.templates.mkdir()
        self.bundletool = self.root / "bundletool.jar"
        self.bundletool.write_bytes(b"synthetic public tool; never executed")
        self.pin = "a" * 64
        # Keep the original commerce fixture independent of the current launch
        # default; dedicated free-MVP cases opt into SDK omission explicitly.
        self.config = {**native.read_config(), "launch_edition": "commerce"}
        self.lock = json.loads((Path(__file__).with_name("billing_plugins.lock.json")).read_text())
        for name in ("java", "jarsigner", "keytool"):
            path = self.jdk / "bin" / name
            self.write(path, b"synthetic public executable; never executed")
            path.chmod(0o700)
        for name in ("platforms/android-36/android.jar", "build-tools/36.1.0/apksigner",
                     "ndk/29.0.14206865/source.properties"):
            self.write(self.sdk / name, b"synthetic installed SDK fixture")
        self.write(self.templates / "version.txt", b"4.7.1.stable\n")
        self.template_manifest = b'''<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools" package="com.blubberandbyte.waddlewars">
    <uses-permission android:name="com.android.vending.BILLING" />
    <application android:label="Waddle Wars: Penguin Panic">
        <profileable tools:targetApi="29" android:shell="true" android:enabled="true" />
        <activity android:name=".GodotApp" android:exported="true" />
    </application>
</manifest>
'''
        self.archive = self.templates / "android_source.zip"
        write_zip(self.archive, {
            "gradlew": b"#!/bin/sh\n# never executed\n",
            "gradle.properties": b"org.gradle.jvmargs=-Xmx9000m\norg.gradle.parallel=true\n",
            "gradle/wrapper/gradle-wrapper.properties": ("distributionUrl=" + integration.GRADLE_URL + "\n").encode(),
            "assetPackInstallTime/build.gradle": b"// synthetic fixture\n",
            "src/main/AndroidManifest.xml": self.template_manifest,
        })
        self.write(self.source / "project.godot", b'''[application]
config/name="Waddle Wars"
run/main_scene="res://scenes/ui/main.tscn"
[rendering]
renderer/rendering_method.mobile="gl_compatibility"
''')
        self.write(self.source / "scripts/utilities/game_config.gd", b'const BUILD_ID: String = "dev"\n')
        self.write(self.source / "scripts/runner/runner_game.gd", b"extends Node\n")
        self.write(self.source / "scenes/ui/main.tscn", b"[gd_scene format=3]\n")
        self.addon = self.source / "addons/GodotGooglePlayBilling"
        self.aar = self.addon / "bin/release/GodotGooglePlayBilling-release.aar"
        self.plugin = self.addon / "export_plugin.gd"
        self.write(self.aar, b"synthetic pinned release AAR")
        self.write(self.plugin, b"synthetic pinned export plugin\n")
        self.write(self.addon / "plugin.cfg", b"[plugin]\n")
        self.write(self.addon / "waddle_install_receipt.json", json.dumps({key: self.lock["android"][key]
                   for key in ("version", "sha256", "source_commit", "billing_library")}).encode())
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(native, "read_config", return_value=self.config))
        self.stack.enter_context(patch.object(integration, "read_config", return_value=self.config))
        for module in (integration, native):
            self.stack.enter_context(patch.object(module, "ROOT", self.source))
        for name, path in (("TEMPLATE_SHA256", self.archive), ("BILLING_AAR_SHA256", self.aar),
                           ("EXPORT_PLUGIN_SHA256", self.plugin)):
            self.stack.enter_context(patch.object(integration, name, native.sha256(path)))
        self.calls: list[tuple[list, dict]] = []
        self.engine_version = upload.ENGINE + "\n"
        self.engine_failure = None
        self.after_export = None
        self.import_settings = None
        self.manifests_seen: list[bytes] = []

    @staticmethod
    def write(path: Path, data: bytes) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def tools(self, command: list[str], **kwargs) -> subprocess.CompletedProcess:
        self.calls.append((command, kwargs))
        self.assertEqual(command[0], "synthetic-godot", "Unexpected external tool")
        # The real export boundary sees the patched manifest, never original
        # shell profiling. Mock only the engine, not policy/import preparation.
        manifest = self.candidate / "project/android/build/src/main/AndroidManifest.xml"
        current = manifest.read_bytes()
        expected = self.template_manifest.replace(b'android:shell="true" android:enabled="true"',
                                                 b'android:shell="false" android:enabled="false"')
        self.assertEqual(current, expected)
        self.manifests_seen.append(current)
        output = ""
        code = 0
        if "--version" in command:
            output = self.engine_version
        elif "--import" in command:
            self.import_settings = (self.candidate / "project/project.godot").read_text()
        elif "--export-release" in command:
            write_zip(Path(command[-1]), PAYLOAD)
            if self.after_export:
                self.after_export()
        else:
            self.fail("Unreviewed external command: " + repr(command))
        if self.engine_failure and self.engine_failure[0] in command:
            output, code = self.engine_failure[1:]
        return subprocess.CompletedProcess(command, code, output, "")

    def export(self) -> dict:
        with patch.object(upload.subprocess, "run", side_effect=self.tools):
            return upload.export(self.candidate, version="1.2.3", build=7, jdk=self.jdk,
                                 bundletool=self.bundletool, pin=self.pin, sdk=self.sdk,
                                 templates=self.templates, godot="synthetic-godot")

    def prepare_signed(self, *, payload: dict | None = None) -> dict:
        receipt = self.export()
        shutil.copyfile(self.candidate / upload.OUTPUT, self.candidate / upload.UNSIGNED)
        write_zip(self.candidate / upload.OUTPUT, {**(PAYLOAD if payload is None else payload), **METADATA})
        return receipt

    def verify(self, *, result: dict | None = None, failure: Exception | None = None) -> tuple[dict, object]:
        if result is None:
            result = {"state": "android_upload_artifact_verified_offline", "store_ready": False,
                      "upload_certificate_sha256": self.pin, "structural_gate_passed": True}
        with patch.object(upload, "verify", return_value=result, side_effect=failure) as verifier:
            receipt = upload.verify_candidate(self.candidate, jdk=self.jdk,
                                              bundletool=self.bundletool, pin=self.pin)
        return receipt, verifier

    def receipt(self) -> dict:
        return json.loads((self.candidate / "receipt.json").read_text())

    def assert_failed(self, state: str) -> None:
        receipt = self.receipt()
        self.assertEqual(receipt["state"], state)
        self.assertIs(receipt["store_ready"], False)
        self.assertIs(receipt["signed"], False)
        self.assertNotIn("android_release_verification", receipt)

    def test_missing_or_invalid_public_pin_refuses_before_preparation_or_engine(self) -> None:
        for pin in (None, "", "not-a-public-fingerprint"):
            self.pin = pin
            with self.subTest(pin=pin), self.assertRaises(ValueError):
                self.export()
            self.assertFalse(self.candidate.exists())
            self.assertEqual(self.calls, [])

    def test_missing_public_tool_or_nonexecutable_jdk_refuses_before_engine(self) -> None:
        self.bundletool.unlink()
        with self.assertRaises(ValueError):
            self.export()
        self.assertFalse(self.candidate.exists())
        self.assertEqual(self.calls, [])
        self.bundletool.write_bytes(b"synthetic public tool")
        (self.jdk / "bin/jarsigner").chmod(0o600)
        with self.assertRaises(ValueError):
            self.export()
        self.assertFalse(self.candidate.exists())
        self.assertEqual(self.calls, [])

    def test_missing_sdk_and_changed_pinned_template_refuse_without_installing(self) -> None:
        required = self.sdk / "platforms/android-36/android.jar"
        required.unlink()
        with self.assertRaisesRegex(ValueError, "does not install"):
            self.export()
        self.assertEqual(self.calls, [])
        self.assertFalse(self.candidate.exists())
        self.write(required, b"synthetic installed SDK fixture")
        self.archive.write_bytes(b"changed source archive")
        with self.assertRaisesRegex(ValueError, "Pinned input"):
            self.export()
        self.assertEqual(self.calls, [])

    def test_existing_candidate_checkout_destination_and_symlink_are_rejected(self) -> None:
        original = self.candidate
        original.mkdir()
        sentinel = original / "preserve.txt"
        sentinel.write_text("prior candidate must survive")
        for destination in (original, self.source / "new-candidate"):
            self.candidate = destination
            with self.subTest(destination=destination), self.assertRaises(ValueError):
                self.export()
        linked = self.root / "linked-candidate"
        linked.symlink_to(original, target_is_directory=True)
        self.candidate = linked
        with self.assertRaisesRegex(ValueError, "symlink"):
            self.export()
        self.assertEqual(sentinel.read_text(), "prior candidate must survive")
        self.assertEqual(self.calls, [])

    def test_relative_and_parent_traversal_candidate_paths_are_rejected_before_engine(self) -> None:
        for destination in (Path("relative-candidate"), self.root / ".." / "traversal-candidate"):
            self.candidate = destination
            with self.subTest(destination=destination), self.assertRaisesRegex(ValueError, "absolute candidate"):
                self.export()
            self.assertEqual(self.calls, [])

    def test_unsigned_export_uses_release_preset_but_cannot_claim_signed_or_store_ready(self) -> None:
        receipt = self.export()
        self.assertEqual(receipt["state"], "android_unsigned_awaiting_upload_signature")
        self.assertIs(receipt["signed"], False)
        self.assertIs(receipt["store_ready"], False)
        self.assertIs(receipt["device_tested"], False)
        self.assertIs(receipt["billing_purchases_verified"], False)
        self.assertIs(receipt["native_billing_build_inputs_included"], True)
        self.assertIn(str(Path(upload.__file__).with_name("billing_plugins.lock.json")), receipt["tool_sha256"])
        self.assertIs(receipt["game_resources_exported"], True)
        self.assertEqual(receipt["unsigned_artifact_sha256"], native.sha256(self.candidate / upload.OUTPUT))
        preset = (self.candidate / "project/export_presets.cfg").read_text()
        self.assertIn("package/signed=false", preset)
        self.assertNotIn("package/signed=true", preset)
        self.assertIn("gradle_build/export_format=1", preset)
        self.assertIn("version/code=7", preset)
        self.assertEqual([cmd[1] for cmd, _ in self.calls], ["--version", "--headless", "--headless"])

    def test_free_inputs_do_not_read_billing_lock_or_require_installed_addon(self) -> None:
        self.config["launch_edition"] = "free_offline_mvp"
        self.addon.rename(self.root / "deferred-billing-fixture")
        with patch.object(integration.json, "loads", side_effect=AssertionError("Billing metadata must not load")) as metadata:
            inputs = integration.validate_inputs(self.templates, self.sdk, self.jdk, include_billing=False)
            metadata.assert_not_called()
        self.assertIs(inputs["include_billing"], False)
        self.assertNotIn("lock", inputs)
        self.assertNotIn("aar", inputs)
        self.assertEqual(inputs["pinned_input_hashes"], {str(self.archive): native.sha256(self.archive)})
        with self.assertRaisesRegex(ValueError, "Pinned input missing"):
            integration.validate_inputs(self.templates, self.sdk, self.jdk)
        self.assertEqual(self.calls, [])

    def test_commerce_inputs_keep_default_exact_billing_provider_and_metadata_pins(self) -> None:
        inputs = integration.validate_inputs(self.templates, self.sdk, self.jdk)
        self.assertIs(inputs["include_billing"], True)
        self.assertEqual(inputs["aar"], self.aar)
        self.assertEqual(inputs["lock"], self.lock)
        self.assertEqual(inputs["pinned_input_hashes"], {
            str(path): native.sha256(path) for path in (self.archive, self.aar, self.plugin)})
        (self.addon / "waddle_install_receipt.json").write_text("{}")
        with self.assertRaisesRegex(ValueError, "billing installation receipt"):
            integration.validate_inputs(self.templates, self.sdk, self.jdk, include_billing=True)

    def test_free_export_requires_no_billing_addon_and_records_only_actual_build_inputs(self) -> None:
        self.config["launch_edition"] = "free_offline_mvp"
        self.addon.rename(self.root / "deferred-billing-fixture")
        real_validation = integration.validate_inputs
        with patch.object(integration, "validate_inputs", wraps=real_validation) as validation:
            receipt = self.export()
        validation.assert_called_once_with(self.templates, self.sdk, self.jdk, include_billing=False)
        self.assertEqual(receipt["launch_edition"], "free_offline_mvp")
        self.assertIs(receipt["native_billing_build_inputs_included"], False)
        self.assertEqual(receipt["pinned_input_hashes"], {str(self.archive): native.sha256(self.archive)})
        self.assertNotIn(str(Path(upload.__file__).with_name("billing_plugins.lock.json")), receipt["tool_sha256"])
        self.assertFalse(any(name.startswith(native.DEFERRED_SDK_PREFIXES) for name in receipt["prepared_files"]))
        self.assertNotIn("GodotGooglePlayBilling/plugin.cfg", (self.candidate / "project/project.godot").read_text())
        self.assertIs(receipt["signed"], False)
        self.assertIs(receipt["store_ready"], False)
        self.assertIs(receipt["billing_purchases_verified"], False)

    def test_changed_release_config_is_rejected_before_preparation_or_engine(self) -> None:
        changed = {**self.config, "app_name": "Other Penguin Panic"}
        with patch.object(integration, "read_config", return_value=changed), self.assertRaisesRegex(ValueError, "configuration changed"):
            self.export()
        self.assertFalse(self.candidate.exists())
        self.assertEqual(self.calls, [])

    def test_free_input_selection_retains_exact_template_sdk_jdk_and_wrapper_gates(self) -> None:
        self.config["launch_edition"] = "free_offline_mvp"
        for path in (self.sdk / "platforms/android-36/android.jar",
                     self.sdk / "build-tools/36.1.0/apksigner",
                     self.sdk / "ndk/29.0.14206865/source.properties", self.jdk / "bin/java"):
            retained = path.with_name(path.name + ".retained-fixture")
            path.rename(retained)
            try:
                with self.subTest(path=path), self.assertRaisesRegex(ValueError, "SDK/build-tools/NDK/JDK missing"):
                    integration.validate_inputs(self.templates, self.sdk, self.jdk, include_billing=False)
            finally:
                retained.rename(path)
        version = self.templates / "version.txt"
        version.write_text("wrong-version\n")
        with self.assertRaisesRegex(ValueError, "Exact installed Godot template version"):
            integration.validate_inputs(self.templates, self.sdk, self.jdk, include_billing=False)
        version.write_text("4.7.1.stable\n")
        original = self.archive.read_bytes()
        self.archive.write_bytes(b"changed pinned template")
        with self.assertRaisesRegex(ValueError, "Pinned input missing or changed"):
            integration.validate_inputs(self.templates, self.sdk, self.jdk, include_billing=False)
        self.archive.write_bytes(original)
        with zipfile.ZipFile(self.archive) as archive:
            entries = {name: archive.read(name) for name in archive.namelist()}
        entries["gradle/wrapper/gradle-wrapper.properties"] = b"distributionUrl=wrong-wrapper\n"
        write_zip(self.archive, entries)
        with patch.object(integration, "TEMPLATE_SHA256", native.sha256(self.archive)), self.assertRaisesRegex(ValueError, "Exact official Gradle 8.11.1"):
            integration.validate_inputs(self.templates, self.sdk, self.jdk, include_billing=False)
        self.assertEqual(self.calls, [])

    def test_child_environment_excludes_all_credentials_and_global_gradle_settings(self) -> None:
        private_names = ("GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD", "GODOT_ANDROID_KEYSTORE_RELEASE_PATH",
                         "GODOT_ANDROID_KEYSTORE_RELEASE_USER", "STRIPE_SECRET_KEY", "CLERK_SECRET_KEY",
                         "GRADLE_OPTS", "JAVA_TOOL_OPTIONS", "ANDROID_USER_HOME", "GRADLE_USER_HOME")
        inherited = {name: "synthetic-value-never-used" for name in private_names}
        inherited.update({"HOME": "/synthetic/user-home", "PATH": "/synthetic/bin", "LANG": "C"})
        with patch.dict(os.environ, inherited, clear=True):
            receipt = self.export()
        for _, kwargs in self.calls:
            env = kwargs["env"]
            self.assertEqual(env["HOME"], "/synthetic/user-home")
            for name in private_names[:-2]:
                self.assertNotIn(name, env)
            self.assertEqual(env["ANDROID_USER_HOME"], str(self.candidate / "android-user"))
            self.assertEqual(env["GRADLE_USER_HOME"], str(self.candidate / "gradle-user"))
            self.assertEqual(env["JAVA_HOME"], str(self.jdk))
            self.assertEqual(env["ANDROID_SDK_ROOT"], str(self.sdk))
        self.assertNotIn("synthetic-value-never-used", json.dumps(receipt))
        for path in (self.candidate / "logs").iterdir():
            self.assertNotIn("synthetic-value-never-used", path.read_text())

    def test_profiling_policy_applies_before_engine_and_snapshot_hash_uses_patched_bytes(self) -> None:
        receipt = self.export()
        relative = "android/build/src/main/AndroidManifest.xml"
        current = (self.candidate / "project" / relative).read_bytes()
        expected = self.template_manifest.replace(b'android:shell="true" android:enabled="true"',
                                                 b'android:shell="false" android:enabled="false"')
        self.assertEqual(current, expected)
        self.assertEqual(len(self.manifests_seen), 3)
        self.assertTrue(all(value == expected for value in self.manifests_seen))
        policy = receipt["android_manifest_policy"]
        self.assertEqual(policy["path"], "project/" + relative)
        self.assertEqual(policy["policy"], "no-release-shell-or-system-profiling-v1")
        self.assertEqual(policy["before_sha256"], hashlib.sha256(self.template_manifest).hexdigest())
        self.assertEqual(policy["after_sha256"], hashlib.sha256(expected).hexdigest())
        self.assertEqual(receipt["prepared_files"][relative], policy["after_sha256"])
        self.assertIs(policy["shell_profileable"], False)
        self.assertIs(policy["system_profileable"], False)
        with zipfile.ZipFile(self.archive) as archive:
            self.assertEqual(archive.read("src/main/AndroidManifest.xml"), self.template_manifest)

    def test_unknown_template_profileable_fails_before_engine_without_rewriting_manifest(self) -> None:
        self.template_manifest = self.template_manifest.replace(b'tools:targetApi="29"', b'tools:targetApi="30"')
        with zipfile.ZipFile(self.archive) as archive:
            entries = {name: archive.read(name) for name in archive.namelist()}
        entries["src/main/AndroidManifest.xml"] = self.template_manifest
        write_zip(self.archive, entries)
        # The synthetic fixture's known source pin follows that fixture only;
        # the real policy remains unmocked and refuses its unreviewed node.
        with patch.object(integration, "TEMPLATE_SHA256", native.sha256(self.archive)):
            with self.assertRaisesRegex(ValueError, "profiling node changed"):
                self.export()
        self.assertEqual(self.calls, [])
        self.assert_failed("android_unsigned_export_failed")
        self.assertEqual((self.candidate / "project/android/build/src/main/AndroidManifest.xml").read_bytes(),
                         self.template_manifest)

    def test_import_uses_isolated_user_directory_then_restores_project(self) -> None:
        receipt = self.export()
        self.assertIn("config/use_custom_user_dir=true", self.import_settings)
        self.assertIn("WaddleWarsUploadImport/" + receipt["source_sha256"][:16], self.import_settings)
        settings = self.candidate / "project/project.godot"
        self.assertNotIn("WaddleWarsUploadImport/", settings.read_text())
        self.assertEqual(native.sha256(settings), receipt["prepared_files"]["project.godot"])

    def test_gradle_resources_are_bounded_and_sdk_jdk_downloads_disabled(self) -> None:
        self.export()
        properties = (self.candidate / "project/android/build/gradle.properties").read_text()
        for key, value in debug.BUILD_PROPERTIES.items():
            self.assertIn(key + "=" + value + "\n", properties)
        self.assertNotIn("-Xmx9000m", properties)
        self.assertNotIn("org.gradle.parallel=true", properties)
        self.assertTrue((self.candidate / "project/android/build/assetPackInstallTime/src/main/assets").is_dir())

    def test_wrong_engine_is_terminal_export_failure_without_import(self) -> None:
        self.engine_version = "4.7.2.stable.synthetic\n"
        with self.assertRaisesRegex(ValueError, "Exact reviewed Godot"):
            self.export()
        self.assert_failed("android_unsigned_export_failed")
        self.assertEqual(len(self.calls), 1)

    def test_import_failure_restores_settings_and_retains_terminal_receipt(self) -> None:
        self.engine_failure = ("--import", "ERROR: synthetic import diagnostic\n", 0)
        with self.assertRaisesRegex(ValueError, "Build step failed"):
            self.export()
        self.assert_failed("android_unsigned_export_failed")
        self.assertNotIn("WaddleWarsUploadImport/", (self.candidate / "project/project.godot").read_text())
        self.assertIn("ERROR:", (self.candidate / "logs/import.log").read_text())
        self.assertFalse((self.candidate / upload.OUTPUT).exists())

    def test_export_nonzero_and_zero_exit_error_are_terminal_failures(self) -> None:
        for output, code in (("synthetic export failed", 1), ("SCRIPT ERROR: synthetic parse failure", 0)):
            with self.subTest(code=code):
                self.candidate = self.root / ("failure-" + str(code))
                self.engine_failure = ("--export-release", output, code)
                with self.assertRaisesRegex(ValueError, "Build step failed"):
                    self.export()
                self.assert_failed("android_unsigned_export_failed")
                self.assertEqual((self.candidate / "logs/unsigned-export.log").read_text(), output)

    def test_export_missing_artifact_cannot_await_signing(self) -> None:
        self.after_export = lambda: (self.candidate / upload.OUTPUT).unlink()
        with self.assertRaisesRegex(ValueError, "regular file"):
            self.export()
        self.assert_failed("android_unsigned_export_failed")

    def test_export_unexpected_signature_cannot_await_signing(self) -> None:
        self.after_export = lambda: write_zip(self.candidate / upload.OUTPUT, {**PAYLOAD, **METADATA})
        with self.assertRaisesRegex(ValueError, "signature metadata"):
            self.export()
        self.assert_failed("android_unsigned_export_failed")

    def test_runtime_mutation_during_export_is_rejected(self) -> None:
        self.after_export = lambda: (self.candidate / "project/scripts/runner/runner_game.gd").write_text("changed runtime\n")
        with self.assertRaisesRegex(ValueError, "runtime changed"):
            self.export()
        self.assert_failed("android_unsigned_export_failed")

    def test_tool_mutation_during_export_is_rejected(self) -> None:
        self.after_export = lambda: self.bundletool.write_bytes(b"changed public tool")
        with self.assertRaisesRegex(ValueError, "Release input changed"):
            self.export()
        self.assert_failed("android_unsigned_export_failed")

    def test_pinned_input_mutation_during_export_is_rejected(self) -> None:
        self.after_export = lambda: self.plugin.write_bytes(b"changed pinned plugin")
        with self.assertRaisesRegex(ValueError, "Release input changed"):
            self.export()
        self.assert_failed("android_unsigned_export_failed")

    def test_verified_signature_delegates_every_immutable_identity_to_mandatory_gate(self) -> None:
        original = self.prepare_signed()
        receipt, verifier = self.verify()
        output = self.candidate / upload.OUTPUT
        verifier.assert_called_once_with(output, artifact_sha256=native.sha256(output),
                                         upload_certificate_sha256=self.pin, package=self.config["bundle_id"],
                                         version="1.2.3", build_number=7, bundletool=self.bundletool, jdk=self.jdk,
                                         launch_edition="commerce")
        self.assertEqual(receipt["state"], "android_upload_artifact_verified_offline")
        self.assertIs(receipt["signed"], True)
        self.assertIs(receipt["store_ready"], False)
        self.assertIs(receipt["device_tested"], False)
        self.assertIs(receipt["billing_purchases_verified"], False)
        self.assertEqual(receipt["unsigned_artifact_sha256"], original["unsigned_artifact_sha256"])
        self.assertEqual(receipt["artifact"]["sha256"], native.sha256(output))
        self.assertNotEqual(receipt["artifact"]["sha256"], receipt["unsigned_artifact_sha256"])

    def test_free_mvp_snapshot_omissions_and_edition_reach_mandatory_verifier(self) -> None:
        self.config["launch_edition"] = "free_offline_mvp"
        original = self.prepare_signed()
        omitted = original["omitted_deferred_sdk_files"]
        self.assertTrue(omitted)
        for name, digest in omitted.items():
            self.assertTrue(name.startswith(native.DEFERRED_SDK_PREFIXES))
            self.assertEqual(digest, original["source_files"][name])
            self.assertNotIn(name, original["prepared_files"])
            self.assertFalse((self.candidate / "project" / name).exists())
        receipt, verifier = self.verify()
        self.assertEqual(receipt["launch_edition"], "free_offline_mvp")
        self.assertEqual(verifier.call_args.kwargs["launch_edition"], "free_offline_mvp")
        self.assertIs(receipt["billing_purchases_verified"], False)
        self.assertIs(receipt["store_ready"], False)

    def test_free_mvp_cannot_skip_arbitrary_missing_mismatched_or_exported_files(self) -> None:
        self.config["launch_edition"] = "free_offline_mvp"
        original = self.export()
        omitted_name = next(iter(original["omitted_deferred_sdk_files"]))
        cases = []
        arbitrary = json.loads(json.dumps(original))
        arbitrary["omitted_deferred_sdk_files"]["scripts/runner/runner_game.gd"] = arbitrary["source_files"]["scripts/runner/runner_game.gd"]
        cases.append(arbitrary)
        missing = json.loads(json.dumps(original))
        del missing["omitted_deferred_sdk_files"][omitted_name]
        cases.append(missing)
        mismatched = json.loads(json.dumps(original))
        mismatched["omitted_deferred_sdk_files"][omitted_name] = "0" * 64
        cases.append(mismatched)
        changed_original = json.loads(json.dumps(original))
        changed_original["source_files"][omitted_name] = "0" * 64
        cases.append(changed_original)
        prepared = json.loads(json.dumps(original))
        prepared["prepared_files"][omitted_name] = prepared["source_files"][omitted_name]
        cases.append(prepared)
        unsupported = json.loads(json.dumps(original))
        unsupported["launch_edition"] = "free"
        cases.append(unsupported)
        for index, receipt in enumerate(cases):
            with self.subTest(index=index), self.assertRaises(ValueError):
                upload.runtime_unchanged(self.candidate, receipt)
        upload.runtime_unchanged(self.candidate, original)

    def test_free_mvp_reintroduced_sdk_bytes_and_symlink_are_rejected(self) -> None:
        self.config["launch_edition"] = "free_offline_mvp"
        receipt = self.export()
        names = list(receipt["omitted_deferred_sdk_files"])
        present = self.candidate / "project" / names[0]
        self.write(present, (self.source / names[0]).read_bytes())
        with self.assertRaisesRegex(ValueError, "omitted native SDK file is present"):
            upload.runtime_unchanged(self.candidate, receipt)
        retained = self.root / "reintroduced-fixture-bytes"
        present.rename(retained)
        present.symlink_to(retained)
        with self.assertRaisesRegex(ValueError, "Symlink"):
            upload.runtime_unchanged(self.candidate, receipt)

    def test_historical_commerce_receipt_defaults_to_commerce_and_cannot_claim_omissions(self) -> None:
        receipt = self.prepare_signed()
        del receipt["launch_edition"]
        upload.save(self.candidate, receipt)
        _, verifier = self.verify()
        self.assertEqual(verifier.call_args.kwargs["launch_edition"], "commerce")
        receipt["omitted_deferred_sdk_files"] = {"scripts/runner/runner_game.gd": receipt["source_files"]["scripts/runner/runner_game.gd"]}
        with self.assertRaisesRegex(ValueError, "Commerce runtime must not omit"):
            upload.runtime_unchanged(self.candidate, receipt)

    def test_payload_replacement_addition_and_removal_rejected_before_verifier(self) -> None:
        self.prepare_signed()
        variants = ({**PAYLOAD, "base/dex/classes.dex": b"replaced game bytes"},
                    {**PAYLOAD, "assetPackInstallTime/assets/extra.bin": b"new unreviewed bytes"},
                    {key: value for key, value in PAYLOAD.items() if key != "base/dex/classes.dex"})
        for index, entries in enumerate(variants):
            with self.subTest(index=index):
                # Restore only the synthetic awaiting-signature receipt between independent cases.
                receipt = self.receipt()
                receipt["state"] = "android_unsigned_awaiting_upload_signature"
                upload.save(self.candidate, receipt)
                write_zip(self.candidate / upload.OUTPUT, {**entries, **METADATA})
                with patch.object(upload, "verify") as verifier:
                    with self.assertRaisesRegex(ValueError, "game payload"):
                        upload.verify_candidate(self.candidate, jdk=self.jdk, bundletool=self.bundletool, pin=self.pin)
                    verifier.assert_not_called()
                self.assert_failed("android_upload_verification_failed")

    def test_changed_retained_unsigned_bundle_rejected_before_verifier(self) -> None:
        self.prepare_signed()
        write_zip(self.candidate / upload.UNSIGNED, {**PAYLOAD, "extra": b"changed original"})
        with patch.object(upload, "verify") as verifier:
            with self.assertRaisesRegex(ValueError, "unsigned export changed"):
                upload.verify_candidate(self.candidate, jdk=self.jdk, bundletool=self.bundletool, pin=self.pin)
            verifier.assert_not_called()
        self.assert_failed("android_upload_verification_failed")

    def test_missing_retained_unsigned_bundle_rejected(self) -> None:
        self.prepare_signed()
        (self.candidate / upload.UNSIGNED).unlink()
        with self.assertRaisesRegex(ValueError, "Retained unsigned bundle"):
            self.verify()
        self.assert_failed("android_upload_verification_failed")

    def test_linked_signed_and_retained_unsigned_bundles_rejected(self) -> None:
        for name in (upload.OUTPUT, upload.UNSIGNED):
            with self.subTest(name=name):
                self.candidate = self.root / ("linked-" + name.name)
                self.prepare_signed()
                output = self.candidate / name
                target = self.root / (name.name + ".target")
                output.rename(target)
                output.symlink_to(target)
                with self.assertRaisesRegex(ValueError, "regular file"):
                    self.verify()
                self.assert_failed("android_upload_verification_failed")

    def test_changed_pinned_tools_and_addon_inputs_rejected_before_verifier(self) -> None:
        for path in (self.bundletool, self.jdk / "bin/keytool", self.plugin):
            with self.subTest(path=path):
                self.candidate = self.root / ("changed-" + path.name)
                self.prepare_signed()
                prior = path.read_bytes()
                path.write_bytes(b"changed immutable input")
                with patch.object(upload, "verify") as verifier:
                    with self.assertRaisesRegex(ValueError, "Release input changed"):
                        upload.verify_candidate(self.candidate, jdk=self.jdk, bundletool=self.bundletool, pin=self.pin)
                    verifier.assert_not_called()
                self.assert_failed("android_upload_verification_failed")
                path.write_bytes(prior)

    def test_runtime_mutation_after_external_signing_is_rejected(self) -> None:
        self.prepare_signed()
        (self.candidate / "project/scripts/runner/runner_game.gd").write_text("changed after signing\n")
        with patch.object(upload, "verify") as verifier:
            with self.assertRaises(ValueError):
                upload.verify_candidate(self.candidate, jdk=self.jdk, bundletool=self.bundletool, pin=self.pin)
            verifier.assert_not_called()
        self.assert_failed("android_upload_verification_failed")

    def test_public_pin_and_host_input_mismatch_are_rejected_without_verifier(self) -> None:
        self.prepare_signed()
        with patch.object(upload, "verify") as verifier:
            with self.assertRaisesRegex(ValueError, "public upload identity changed"):
                upload.verify_candidate(self.candidate, jdk=self.jdk, bundletool=self.bundletool, pin="b" * 64)
            with self.assertRaisesRegex(ValueError, "matching unverified"):
                upload.verify_candidate(self.candidate, jdk=self.root / "other-jdk", bundletool=self.bundletool, pin=self.pin)
            verifier.assert_not_called()
        self.assertIs(self.receipt()["store_ready"], False)
        self.assertIs(self.receipt()["signed"], False)

    def test_wrong_candidate_purpose_state_and_false_flags_are_rejected(self) -> None:
        original = self.prepare_signed()
        for updates in ({"purpose": "full_game_android_debug"}, {"state": "android_upload_verification_failed"},
                        {"signed": True}, {"store_ready": True}, {"signed": 0}, {"store_ready": 0}):
            with self.subTest(updates=updates):
                upload.save(self.candidate, {**original, **updates})
                with patch.object(upload, "verify") as verifier:
                    with self.assertRaisesRegex(ValueError, "matching unverified"):
                        upload.verify_candidate(self.candidate, jdk=self.jdk, bundletool=self.bundletool, pin=self.pin)
                    verifier.assert_not_called()

    def test_candidate_and_receipt_symlinks_are_rejected(self) -> None:
        self.prepare_signed()
        linked = self.root / "candidate-link"
        linked.symlink_to(self.candidate, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "regular candidate"):
            upload.verify_candidate(linked, jdk=self.jdk, bundletool=self.bundletool, pin=self.pin)
        receipt = self.candidate / "receipt.json"
        target = self.root / "receipt-target.json"
        receipt.rename(target)
        receipt.symlink_to(target)
        with self.assertRaisesRegex(ValueError, "regular file"):
            upload.verify_candidate(self.candidate, jdk=self.jdk, bundletool=self.bundletool, pin=self.pin)

    def test_mandatory_signature_identity_and_structural_failures_are_terminal(self) -> None:
        failures = (ValueError("wrong upload certificate pin"), ValueError("unexpected signer subject"),
                    ValueError("unsigned payload entry"), ValueError("16KB structural gate rejected"),
                    subprocess.TimeoutExpired("synthetic-public-tool", 20), zipfile.BadZipFile("synthetic ZIP"))
        for index, failure in enumerate(failures):
            with self.subTest(failure=type(failure).__name__):
                self.candidate = self.root / ("verifier-rejection-" + str(index))
                self.prepare_signed()
                with self.assertRaises(type(failure)):
                    self.verify(failure=failure)
                self.assert_failed("android_upload_verification_failed")

    def test_tool_mutation_inside_mandatory_gate_discards_acceptance(self) -> None:
        self.prepare_signed()
        def mutate(*args, **kwargs):
            self.bundletool.write_bytes(b"tool changed while mandatory verifier ran")
            return {"state": "android_upload_artifact_verified_offline", "store_ready": False}
        with patch.object(upload, "verify", side_effect=mutate):
            with self.assertRaisesRegex(ValueError, "Release input changed"):
                upload.verify_candidate(self.candidate, jdk=self.jdk, bundletool=self.bundletool, pin=self.pin)
        self.assert_failed("android_upload_verification_failed")

    def test_pinned_input_mutation_inside_mandatory_gate_discards_acceptance(self) -> None:
        self.prepare_signed()
        def mutate(*args, **kwargs):
            self.plugin.write_bytes(b"addon changed while mandatory verifier ran")
            return {"state": "android_upload_artifact_verified_offline", "store_ready": False}
        with patch.object(upload, "verify", side_effect=mutate):
            with self.assertRaisesRegex(ValueError, "Release input changed"):
                upload.verify_candidate(self.candidate, jdk=self.jdk, bundletool=self.bundletool, pin=self.pin)
        self.assert_failed("android_upload_verification_failed")

    def test_runtime_mutation_inside_mandatory_gate_discards_acceptance(self) -> None:
        self.prepare_signed()
        def mutate(*args, **kwargs):
            (self.candidate / "project/scripts/runner/runner_game.gd").write_text("changed while verifying\n")
            return {"state": "android_upload_artifact_verified_offline", "store_ready": False}
        with patch.object(upload, "verify", side_effect=mutate):
            with self.assertRaisesRegex(ValueError, "runtime changed"):
                upload.verify_candidate(self.candidate, jdk=self.jdk, bundletool=self.bundletool, pin=self.pin)
        self.assert_failed("android_upload_verification_failed")

    def test_signed_bundle_mutation_inside_mandatory_gate_discards_acceptance(self) -> None:
        self.prepare_signed()
        def mutate(*args, **kwargs):
            write_zip(self.candidate / upload.OUTPUT, {**PAYLOAD, **METADATA, "extra": b"late artifact mutation"})
            return {"state": "android_upload_artifact_verified_offline", "store_ready": False}
        with patch.object(upload, "verify", side_effect=mutate):
            with self.assertRaises(ValueError):
                upload.verify_candidate(self.candidate, jdk=self.jdk, bundletool=self.bundletool, pin=self.pin)
        self.assert_failed("android_upload_verification_failed")

    def test_retained_unsigned_mutation_inside_mandatory_gate_discards_acceptance(self) -> None:
        self.prepare_signed()
        def mutate(*args, **kwargs):
            write_zip(self.candidate / upload.UNSIGNED, {**PAYLOAD, "extra": b"late provenance mutation"})
            return {"state": "android_upload_artifact_verified_offline", "store_ready": False}
        with patch.object(upload, "verify", side_effect=mutate):
            with self.assertRaises(ValueError):
                upload.verify_candidate(self.candidate, jdk=self.jdk, bundletool=self.bundletool, pin=self.pin)
        self.assert_failed("android_upload_verification_failed")

    def test_symlinked_runtime_parent_is_rejected_before_mandatory_verifier(self) -> None:
        self.prepare_signed()
        scripts = self.candidate / "project/scripts"
        target = self.root / "runtime-scripts-target"
        scripts.rename(target)
        scripts.symlink_to(target, target_is_directory=True)
        with patch.object(upload, "verify") as verifier:
            with self.assertRaisesRegex(ValueError, "Symlink in runtime"):
                upload.verify_candidate(self.candidate, jdk=self.jdk, bundletool=self.bundletool, pin=self.pin)
            verifier.assert_not_called()
        self.assert_failed("android_upload_verification_failed")

    def test_missing_and_unsafe_runtime_inventory_is_rejected_before_verifier(self) -> None:
        original = self.prepare_signed()
        for inventory in ({}, {"scripts/runner/runner_game.gd": "a" * 64},
                          {"project.godot": "a" * 64, "../outside": "b" * 64},
                          {"project.godot": "a" * 64, "scripts/private.jks": "b" * 64}):
            with self.subTest(inventory=inventory):
                upload.save(self.candidate, {**original, "source_files": inventory})
                with patch.object(upload, "verify") as verifier:
                    with self.assertRaises(ValueError):
                        upload.verify_candidate(self.candidate, jdk=self.jdk, bundletool=self.bundletool, pin=self.pin)
                    verifier.assert_not_called()
                self.assert_failed("android_upload_verification_failed")

    def test_cli_failures_are_sanitized_and_nonzero(self) -> None:
        argv = ["build_android_upload.py", "export", str(self.candidate), "--jdk", str(self.jdk),
                "--bundletool", str(self.bundletool), "--upload-certificate-sha256", self.pin]
        error = "synthetic private provider value must never be echoed"
        stderr = io.StringIO()
        stdout = io.StringIO()
        with patch.object(sys, "argv", argv), patch.object(upload.os, "umask") as mask, \
                patch.object(upload, "export", side_effect=ValueError(error)), \
                contextlib.redirect_stderr(stderr), contextlib.redirect_stdout(stdout):
            code = upload.main()
        mask.assert_called_once_with(0o077)
        self.assertEqual(code, 1)
        self.assertEqual(stdout.getvalue(), "")
        self.assertEqual(stderr.getvalue(), "build_android_upload failed: ValueError\n")
        self.assertNotIn(error, stderr.getvalue())

    def test_cli_success_always_reports_not_store_ready(self) -> None:
        argv = ["build_android_upload.py", "verify", str(self.candidate), "--jdk", str(self.jdk),
                "--bundletool", str(self.bundletool), "--upload-certificate-sha256", self.pin]
        stdout = io.StringIO()
        synthetic = {"state": "android_upload_artifact_verified_offline", "store_ready": True,
                     "artifact": {"path": "synthetic.aab"}}
        with patch.object(sys, "argv", argv), patch.object(upload.os, "umask") as mask, \
                patch.object(upload, "verify_candidate", return_value=synthetic), \
                contextlib.redirect_stdout(stdout):
            self.assertEqual(upload.main(), 0)
        mask.assert_called_once_with(0o077)
        result = json.loads(stdout.getvalue())
        self.assertIs(result["store_ready"], False)
        self.assertEqual(result["state"], synthetic["state"])


if __name__ == "__main__":
    unittest.main()
