#!/usr/bin/env python3
"""Pure host regressions; no Gradle, Godot, download, signing or device."""
from pathlib import Path
import json
import os
import struct
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import build_android_integration_qa as qa
from native_release import read_config


def dex(descriptor: bytes, defined: bool = True) -> bytes:
    data = bytearray(220 + len(descriptor))
    data[:8] = b"dex\n039\0"
    struct.pack_into("<II", data, 56, 1, 112)
    struct.pack_into("<II", data, 64, 1, 116)
    struct.pack_into("<II", data, 96, 1 if defined else 0, 120)
    struct.pack_into("<I", data, 112, 160)
    struct.pack_into("<I", data, 116, 0)
    struct.pack_into("<I", data, 120, 0)
    data[160] = len(descriptor)
    data[161:161 + len(descriptor)] = descriptor
    return bytes(data)


def elf() -> bytes:
    data = bytearray(256)
    data[:6] = b"\x7fELF\x02\x01"
    struct.pack_into("<H", data, 18, 183)
    struct.pack_into("<Q", data, 32, 64)
    struct.pack_into("<HH", data, 54, 56, 1)
    struct.pack_into("<IIQQQQQQ", data, 64, 1, 5, 0, 0, 0, 128, 128, 16384)
    return bytes(data)


class AndroidIntegrationQaTests(unittest.TestCase):
    def setUp(self) -> None:
        self.config = read_config()
        self.inputs = {"config": self.config, "lock": {"android": {"billing_library": "9.1.0"}}}

    def test_refuse_checkout_existing_and_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / "source"
            source.mkdir()
            alias = root / "alias"
            alias.symlink_to(root / "missing")
            with patch.object(qa, "ROOT", source):
                for path in (source, source / "new", root, alias):
                    with self.assertRaises(ValueError):
                        qa.validate_destination(path)
                self.assertEqual(qa.validate_destination(root / "new"), (root / "new").resolve())

    def test_archive_traversal_and_symlink_refused(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for index, name in enumerate(("../escape", "/absolute", "bad\\escape", "link")):
                archive = root / f"source{index}.zip"
                with zipfile.ZipFile(archive, "w") as zipped:
                    item = zipfile.ZipInfo(name)
                    if name == "link":
                        item.external_attr = 0o120777 << 16
                    zipped.writestr(item, b"unsafe")
                with self.assertRaises(ValueError):
                    qa.extract_template(archive, root / f"out{index}")
            self.assertFalse((root / "escape").exists())

    def test_environment_strips_credentials_and_isolates_caches(self) -> None:
        with patch.dict(os.environ, {"HOME": "/real/home", "PATH": "/usr/bin",
                                    "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD": "secret",
                                    "STRIPE_SECRET_KEY": "secret", "GRADLE_OPTS": "unsafe"}, clear=True):
            environment = qa.build_environment(Path("/qa"), Path("/sdk"), Path("/java"))
        self.assertEqual(environment["HOME"], "/real/home")
        self.assertEqual(environment["GRADLE_USER_HOME"], "/qa/gradle-user")
        self.assertEqual(environment["ANDROID_USER_HOME"], "/qa/android-user")
        for key in ("STRIPE_SECRET_KEY", "GRADLE_OPTS", "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD"):
            self.assertNotIn(key, environment)

    def test_content_free_template_creates_required_empty_asset_directory(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            archive = root / "source.zip"
            with zipfile.ZipFile(archive, "w") as zipped:
                zipped.writestr("gradlew", "#!/bin/sh\n")
                zipped.writestr("assetPackInstallTime/build.gradle", "fixture")
            qa.extract_template(archive, root / "template")
            assets = root / "template/assetPackInstallTime/src/main/assets"
            self.assertTrue(assets.is_dir())
            self.assertEqual(list(assets.iterdir()), [])

    def test_fixed_unsigned_bounded_official_compile_command(self) -> None:
        command = qa.gradle_command(Path("/qa"), self.inputs)
        for argument in ("--no-daemon", "--max-workers=2", "-Pperform_signing=false",
                         "-Pexport_enabled_abis=arm64-v8a", "-Pcompress_native_libraries=false",
                         "-Pandroid.builder.sdkDownload=false", "bundleStandardRelease",
                         "waddleIntegrationResolvedDependencies",
                         "-Pplugins_remote_binaries=com.android.billingclient:billing-ktx:9.1.0"):
            self.assertIn(argument, command)
        self.assertFalse(any("keystore" in argument.lower() for argument in command))

    def test_input_billing_selection_requires_explicit_boolean_before_host_reads(self) -> None:
        with patch.object(qa, "read_config") as config:
            for value in (None, 0, 1, "false", [], {}):
                with self.subTest(value=value), self.assertRaisesRegex(ValueError, "explicit boolean"):
                    qa.validate_inputs(Path("/templates"), Path("/sdk"), Path("/java"), include_billing=value)
            config.assert_not_called()

    def test_free_template_inputs_cannot_be_used_for_native_billing_compile(self) -> None:
        with self.assertRaisesRegex(ValueError, "requires validated billing inputs"):
            qa.gradle_command(Path("/qa"), {"config": self.config, "include_billing": False})

    def test_resolved_version_not_requested_version(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            cache = root / "gradle-user/caches"
            cache.mkdir(parents=True)
            artifacts = []
            for name in ("billing", "billing-ktx"):
                path = cache / f"{name}.aar"
                path.write_bytes(b"resolved artifact")
                artifacts.append({"group": "com.android.billingclient", "name": name,
                                  "version": "9.1.0", "file": str(path)})
            receipt = root / "resolved_dependencies.json"
            receipt.write_text(json.dumps(artifacts))
            checked = qa.verify_dependencies(root, "9.1.0")
            self.assertEqual(len(checked), 2)
            self.assertIn("sha256", checked[0])
            artifacts[0]["version"] = "9.2.0"
            receipt.write_text(json.dumps(artifacts))
            with self.assertRaises(ValueError):
                qa.verify_dependencies(root, "9.1.0")
            artifacts[0]["version"] = "9.1.0"
            artifacts[0]["file"] = str(root / "outside-cache.aar")
            (root / "outside-cache.aar").write_bytes(b"not isolated")
            receipt.write_text(json.dumps(artifacts))
            with self.assertRaises(ValueError):
                qa.verify_dependencies(root, "9.1.0")

    def test_class_must_be_defined_not_merely_mentioned(self) -> None:
        descriptor = ("L" + qa.PROVIDER_CLASS.replace(".", "/") + ";").encode()
        self.assertTrue(qa.dex_defines_class(dex(descriptor), descriptor))
        self.assertFalse(qa.dex_defines_class(dex(descriptor, False), descriptor))
        self.assertFalse(qa.dex_defines_class(b"bad" + descriptor, descriptor))
        invalid = bytearray(dex(descriptor))
        struct.pack_into("<I", invalid, 100, 999999)
        self.assertFalse(qa.dex_defines_class(bytes(invalid), descriptor))

    def test_unsigned_integration_not_16kb_release_pass(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            output = root / "template/build/outputs/bundle/standardRelease"
            output.mkdir(parents=True)
            manifest_dir = root / "template/build/intermediates/merged_manifests/standardRelease/processStandardReleaseManifest"
            manifest_dir.mkdir(parents=True)
            manifest = f'''<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="{self.config['bundle_id']}">
<uses-sdk android:minSdkVersion="24" android:targetSdkVersion="36" />
<uses-permission android:name="com.android.vending.BILLING" />
<application><meta-data android:name="{qa.PROVIDER_KEY}" android:value="{qa.PROVIDER_CLASS}" /></application></manifest>'''
            (manifest_dir / "AndroidManifest.xml").write_text(manifest)
            bundle = output / "template-standard-release.aab"
            descriptor = ("L" + qa.PROVIDER_CLASS.replace(".", "/") + ";").encode()
            with zipfile.ZipFile(bundle, "w") as zipped:
                zipped.writestr("base/dex/classes.dex", dex(descriptor))
                zipped.writestr("base/lib/arm64-v8a/libgodot_android.so", elf())
            report = qa.verify_artifact(root, self.config)
            self.assertTrue(report["unsigned"])
            self.assertFalse(report["android_16kb_structural_gate_passed"])
            self.assertFalse(report["android_16kb_packaging_checked"])
            with zipfile.ZipFile(bundle, "a") as zipped:
                zipped.writestr("META-INF/CERT.RSA", b"unexpected signing")
            with self.assertRaises(ValueError):
                qa.verify_artifact(root, self.config)


if __name__ == "__main__":
    unittest.main()
