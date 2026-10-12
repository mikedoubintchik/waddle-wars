#!/usr/bin/env python3
"""Pure-host debug-APK regressions. All engine/signing/tool calls are mocked."""
from __future__ import annotations

import contextlib
import io
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import build_android_debug as debug
import build_android_integration_qa as integration
import native_release as native


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


class AndroidDebugTests(unittest.TestCase):
    def setUp(self) -> None:
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        self.source = self.root / "source"
        self.source.mkdir()
        self.destination = self.root / "retained-debug-candidate"
        self.sdk = self.root / "sdk"
        self.java = self.root / "java"
        self.templates = self.root / "4.7.1.stable"
        self.templates.mkdir()
        self.config = native.read_config()
        # Existing fixtures exercise the paid edition; production currently
        # selects the free MVP, covered separately below.
        self.config["launch_edition"] = "commerce"
        self.lock = json.loads((Path(__file__).with_name("billing_plugins.lock.json")).read_text())
        self.key = self.root / "godot/keystores/debug.keystore"
        self.write(self.key, b"opaque fixture; helper must never read these bytes")
        self.settings = self.root / "godot/editor_settings-4.7.tres"
        self.write_settings()
        for relative in ("platforms/android-36/android.jar", "build-tools/36.1.0/apksigner",
                         "build-tools/36.1.0/aapt2", "build-tools/36.1.0/zipalign",
                         "ndk/29.0.14206865/source.properties"):
            self.write(self.sdk / relative, b"installed fixture")
        self.write(self.java / "bin/java", b"installed fixture")
        self.write(self.templates / "version.txt", b"4.7.1.stable\n")
        self.archive = self.templates / "android_source.zip"
        with zipfile.ZipFile(self.archive, "w") as zipped:
            zipped.writestr("gradlew", "#!/bin/sh\n")
            zipped.writestr("build.gradle", "// official template fixture\n")
            zipped.writestr("gradle.properties", "org.gradle.jvmargs=-Xmx4536m\n")
            zipped.writestr("gradle/wrapper/gradle-wrapper.properties", "distributionUrl=" + integration.GRADLE_URL + "\n")
            zipped.writestr("assetPackInstallTime/build.gradle", "// fixture\n")
        self.write(self.source / "project.godot", b'''[application]
config/name="Waddle Wars"
run/main_scene="res://scenes/ui/main.tscn"
[rendering]
renderer/rendering_method="mobile"
renderer/rendering_method.mobile="gl_compatibility"
[display]
window/handheld/orientation=6
''')
        for relative, content in {
            "scripts/utilities/game_config.gd": b'const BUILD_ID: String = "dev"\nconst SAVE_VERSION: int = 1\n',
            "scripts/save/save_manager.gd": b'const SAVE_PATH = "user://save.json"\n',
            "scripts/runner/runner_game.gd": b"extends Node\n",
            "scenes/ui/main.tscn": b"[gd_scene format=3]\n",
            "scenes/gameplay/runner.tscn": b"[gd_scene format=3]\n",
            "scenes/gameplay/race.tscn": b"[gd_scene format=3]\n",
            "assets/example.png": b"texture fixture",
            "data/commerce/catalog.json": b'{"fixture":true}',
            "addons/GodotGooglePlayBilling/BillingClient.gd": b"extends RefCounted\n",
            "addons/GodotGooglePlayBilling/export_plugin.gd": b"pinned exporter fixture\n",
            "addons/GodotGooglePlayBilling/plugin.cfg": b"[plugin]\n",
            "addons/GodotGooglePlayBilling/bin/release/GodotGooglePlayBilling-release.aar": b"pinned release fixture",
            "addons/GodotGooglePlayBilling/bin/debug/GodotGooglePlayBilling-debug.aar": b"pinned debug fixture",
        }.items():
            self.write(self.source / relative, content)
        self.addon = self.source / "addons/GodotGooglePlayBilling"
        self.write(self.addon / "waddle_install_receipt.json", json.dumps({key: self.lock["android"][key] for key in
                   ("version", "sha256", "source_commit", "billing_library")}).encode())
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        for module in (debug, integration, native):
            self.stack.enter_context(patch.object(module, "ROOT", self.source))
        self.stack.enter_context(patch.object(native, "read_config", return_value=self.config))
        self.stack.enter_context(patch.object(integration, "read_config", return_value=self.config))
        for module, name, path in (
            (integration, "TEMPLATE_SHA256", self.archive),
            (integration, "BILLING_AAR_SHA256", self.addon / "bin/release/GodotGooglePlayBilling-release.aar"),
            (integration, "EXPORT_PLUGIN_SHA256", self.addon / "export_plugin.gd"),
            (debug, "DEBUG_AAR_SHA256", self.addon / "bin/debug/GodotGooglePlayBilling-debug.aar"),
        ):
            self.stack.enter_context(patch.object(module, name, native.sha256(path)))
        self.calls: list[list[str]] = []

    @staticmethod
    def write(path: Path, content: bytes) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)

    def write_settings(self, extra: str = "") -> None:
        text = "\n".join(f"export/android/{name} = {json.dumps(str(value))}" for name, value in
                         (("debug_keystore", self.key), ("android_sdk_path", self.sdk), ("java_sdk_path", self.java)))
        # Invalid credential syntax proves it is neither parsed nor extracted.
        self.write(self.settings, (text + "\nexport/android/debug_keystore_pass = NOT_PARSED_CREDENTIAL\n" + extra).encode())

    def inputs(self) -> dict:
        return debug.validate_inputs(self.templates, self.sdk, self.java, self.settings)

    def prepare(self) -> tuple[dict, dict]:
        inputs = self.inputs()
        return inputs, debug.prepare_debug(self.destination, inputs, "1.2.3", 7)

    def artifact_fixture(self, destination: Path, receipt: dict) -> None:
        project = destination / "project"
        staged = project / "android/build/src/main/assets"
        staged.mkdir(parents=True)
        for relative in receipt["source_files"]:
            if Path(relative).parts[0] in ("assets", "data", "scenes", "scripts") and Path(relative).suffix in debug.GAME_SUFFIXES:
                self.write(staged / relative, (project / relative).read_bytes())
        (staged / "scenes/ui/main.tscn").unlink()
        self.write(staged / ".godot/exported/main.scn", b"converted main scene")
        self.write(staged / "scenes/ui/main.tscn.remap", b'[remap]\npath="res://.godot/exported/main.scn"\n')
        for name in ("project.binary", "assets.sparsepck", "_cl_"):
            self.write(staged / name, b"Godot exported fixture")
        manifests = project / "android/build/build/intermediates/merged_manifests/standardDebug/processStandardDebugManifest"
        commerce = self.config["launch_edition"] == "commerce"
        billing_permission = '<uses-permission android:name="com.android.vending.BILLING"/>' if commerce else ""
        provider_metadata = (f'<meta-data android:name="{integration.PROVIDER_KEY}" '
                             f'android:value="{integration.PROVIDER_CLASS}"/>') if commerce else ""
        self.write(manifests / "AndroidManifest.xml", f'''<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="{self.config['bundle_id']}">
<uses-sdk android:minSdkVersion="24" android:targetSdkVersion="36"/>
{billing_permission}
<application android:debuggable="true">{provider_metadata}</application>
</manifest>'''.encode())
        descriptor = (("L" + integration.PROVIDER_CLASS.replace(".", "/") + ";") if commerce else "Lcom/godot/game/GodotApp;").encode()
        with zipfile.ZipFile(destination / debug.OUTPUT, "w") as zipped:
            zipped.writestr("classes.dex", dex(descriptor))
            zipped.writestr("lib/arm64-v8a/libgodot_android.so", elf())
            for path in staged.rglob("*"):
                if path.is_file():
                    zipped.write(path, "assets/" + str(path.relative_to(staged)))
        artifacts = []
        for name in (("billing", "billing-ktx") if commerce else ("androidx-core",)):
            path = destination / "gradle-user/caches" / (name + ".aar")
            self.write(path, b"resolved pinned dependency")
            artifacts.append({"group": "com.android.billingclient" if commerce else "androidx.core",
                              "name": name, "version": "9.1.0" if commerce else "1.0.0", "file": str(path)})
        self.write(destination / "resolved_dependencies.json", json.dumps(artifacts).encode())

    def mock_tools(self, command: list[str], **kwargs) -> subprocess.CompletedProcess:
        self.calls.append(command)
        if "env" in kwargs:
            self.assertNotIn("GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD", kwargs["env"])
        output = ""
        if "--version" in command:
            output = "4.7.1.stable.official.a13da4feb\n"
        elif "--import" in command:
            text = (self.destination / "project/project.godot").read_text()
            self.assertIn("config/use_custom_user_dir=true", text)
            self.assertIn("WaddleWarsAndroidDebugImport/", text)
        elif "--export-debug" in command:
            receipt = json.loads((self.destination / "receipt.json").read_text())
            text = (self.destination / "project/project.godot").read_text()
            self.assertEqual(debug.game_identity(text), receipt["identity"])
            self.artifact_fixture(self.destination, receipt)
        elif "badging" in command:
            output = f"package: name='{self.config['bundle_id']}' versionCode='7' versionName='1.2.3'\nminSdkVersion:'24'\ntargetSdkVersion:'36'\napplication-label:'{self.config['app_name']}'\napplication-debuggable\n"
            if self.config["launch_edition"] == "commerce":
                output += "uses-permission: name='com.android.vending.BILLING'\n"
        elif "verify" in command:
            output = "Verifies\nVerified using v2 scheme: true\n"
        elif "-c" in command:
            output = "Verification successful\n"
        else:
            self.fail("Unexpected external command: " + repr(command))
        return subprocess.CompletedProcess(command, 0, output, "")

    def test_configured_key_metadata_only_and_no_credentials_parsed(self) -> None:
        original = Path.open
        def guarded(path: Path, *args, **kwargs):
            self.assertNotEqual(path, self.key, "Private key file must never be opened")
            return original(path, *args, **kwargs)
        with patch.object(Path, "open", guarded):
            paths = debug.configured_tools(self.settings, self.sdk, self.java)
        self.assertEqual(paths["export/android/debug_keystore"], self.key)
        self.assertEqual(len(paths), 3)

    def test_missing_debug_key_refuses_before_engine(self) -> None:
        self.key.unlink()
        with patch.object(debug.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "refusing engine import"):
                self.inputs()
        run.assert_not_called()
        self.assertFalse(self.destination.exists())

    def test_debug_key_symlink_refused(self) -> None:
        target = self.root / "other.key"
        self.key.rename(target)
        self.key.symlink_to(target)
        with self.assertRaisesRegex(ValueError, "debug keystore"):
            self.inputs()

    def test_editor_sdk_mismatch_refused(self) -> None:
        with self.assertRaisesRegex(ValueError, "must match"):
            debug.configured_tools(self.settings, self.root / "other-sdk", self.java)

    def test_duplicate_editor_path_refused(self) -> None:
        self.write_settings(f'export/android/debug_keystore = {json.dumps(str(self.key))}\n')
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            self.inputs()

    def test_missing_editor_paths_refused(self) -> None:
        self.write(self.settings, b"export/android/debug_keystore_pass = ignored\n")
        with self.assertRaisesRegex(ValueError, "configuration required"):
            self.inputs()

    def test_pinned_debug_aar_required(self) -> None:
        self.write(self.addon / "bin/debug/GodotGooglePlayBilling-debug.aar", b"changed")
        with self.assertRaisesRegex(ValueError, "debug AAR"):
            self.inputs()

    def test_missing_sdk_tool_refuses_without_installation(self) -> None:
        (self.sdk / "build-tools/36.1.0/aapt2").unlink()
        with patch.object(debug.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "no SDK downloads"):
                self.inputs()
        run.assert_not_called()

    def test_prepare_debug_states_and_release_derivative_contract(self) -> None:
        with patch.object(debug.subprocess, "run") as run:
            inputs, receipt = self.prepare()
        run.assert_not_called()
        self.assertEqual(receipt["state"], "debug_prepared_unbuilt")
        self.assertTrue(receipt["development_only"])
        self.assertFalse(receipt["store_ready"])
        self.assertFalse(receipt["game_resources_exported"])
        self.assertEqual(receipt["bundle_id"], self.config["bundle_id"])
        self.assertEqual(receipt["app_name"], "Waddle Wars: Penguin Panic")
        self.assertEqual(receipt["project_name"], "Waddle Wars")
        self.assertEqual(receipt["preset_name"], debug.PRESET)
        project = self.destination / "project"
        preset = (project / "export_presets.cfg").read_text()
        for value in ("gradle_build/use_gradle_build=true", "gradle_build/export_format=0", 'gradle_build/min_sdk="24"',
                      'gradle_build/target_sdk="36"', "architectures/arm64-v8a=true", "architectures/x86_64=false",
                      "gradle_build/compress_native_libraries=false", "package/signed=true", 'export_filter="all_resources"',
                      'package/unique_name="com.blubberandbyte.waddlewars"', "*.keystore", "*.p8", ".env*"):
            self.assertIn(value, preset)
        self.assertIn("GodotGooglePlayBilling/plugin.cfg", (project / "project.godot").read_text())
        self.assertIn('package/name="Waddle Wars: Penguin Panic"', preset)
        self.assertEqual(debug.game_identity((project / "project.godot").read_text()), debug.game_identity((self.source / "project.godot").read_text()))
        self.assertIn(receipt["build_id"], (project / "scripts/utilities/game_config.gd").read_text())
        self.assertTrue(receipt["build_id"].startswith("native-android-debug-7-"))
        self.assertIn("standardDebugRuntimeClasspath", (project / "android/build/build.gradle").read_text())
        debug.verify_snapshot(project, receipt)
        self.assertEqual(inputs["config"]["android"]["preset_name"], "Android Play Release")

    def test_source_unchanged_and_nonruntime_files_excluded(self) -> None:
        self.write(self.source / ".envrc", b"do not export")
        self.write(self.source / "tests/fixture.gd", b"do not export")
        self.write(self.source / "qa_shots/private.txt", b"do not export")
        before = {str(path.relative_to(self.source)): native.sha256(path) for path in self.source.rglob("*") if path.is_file()}
        _, receipt = self.prepare()
        after = {str(path.relative_to(self.source)): native.sha256(path) for path in self.source.rglob("*") if path.is_file()}
        self.assertEqual(before, after)
        for name in (".envrc", "tests/fixture.gd", "qa_shots/private.txt"):
            self.assertNotIn(name, receipt["source_files"])
            self.assertFalse((self.destination / "project" / name).exists())

    def test_prepare_existing_candidate_never_overwritten(self) -> None:
        inputs, receipt = self.prepare()
        before = (self.destination / "receipt.json").read_bytes()
        with self.assertRaisesRegex(ValueError, "must be new"):
            debug.prepare_debug(self.destination, inputs, "1.2.3", 7)
        self.assertEqual(before, (self.destination / "receipt.json").read_bytes())

    def test_prepare_failure_preserved(self) -> None:
        self.write(self.source / "scripts/utilities/game_config.gd", b"no build ID declaration\n")
        with self.assertRaisesRegex(ValueError, "Exactly one"):
            debug.prepare_debug(self.destination, self.inputs(), "1.2.3", 7)
        receipt = json.loads((self.destination / "receipt.json").read_text())
        self.assertEqual(receipt["state"], "debug_prepare_failed")
        self.assertTrue(receipt["development_only"])
        self.assertFalse(receipt["store_ready"])

    def test_bounded_properties_replace_unsafe_template_defaults(self) -> None:
        text = debug.bounded_properties("org.gradle.jvmargs=-Xmx4536m\norg.gradle.workers.max=10\norg.gradle.parallel=true\n")
        for key, value in debug.BUILD_PROPERTIES.items():
            self.assertEqual(text.count(f"{key}={value}"), 1)
        self.assertNotIn("4536", text)
        self.assertEqual(debug.bounded_properties(text), text)

    def test_receipt_hook_waits_for_late_agp_variant_task_registration(self) -> None:
        self.assertIn("tasks.matching { it.name == 'assembleStandardDebug' }.configureEach", debug.RESOLUTION_TASK)
        self.assertNotIn("tasks.named('assembleStandardDebug')", debug.RESOLUTION_TASK)
        self.assertIn("finalizedBy('waddleDebugResolvedDependencies')", debug.RESOLUTION_TASK)

    def test_environment_no_release_debug_override_or_service_credentials(self) -> None:
        with patch.dict(os.environ, {"HOME": "/real/home", "PATH": "/usr/bin", "STRIPE_SECRET_KEY": "secret",
                                    "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD": "secret",
                                    "GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD": "override",
                                    "GRADLE_OPTS": "unsafe", "JAVA_TOOL_OPTIONS": "unsafe", "XDG_CONFIG_HOME": "/other"}, clear=True):
            env = debug.build_environment(self.destination, self.inputs())
        self.assertEqual(env["HOME"], "/real/home")
        self.assertEqual(env["GRADLE_USER_HOME"], str(self.destination / "gradle-user"))
        self.assertEqual(env["ANDROID_USER_HOME"], str(self.destination / "android-user"))
        self.assertEqual(set(env), {"HOME", "PATH", "JAVA_HOME", "ANDROID_HOME", "ANDROID_SDK_ROOT", "ANDROID_USER_HOME", "GRADLE_USER_HOME"})

    def test_mock_full_build_signed_game_verified_not_store_ready(self) -> None:
        inputs, _ = self.prepare()
        with patch.object(debug.subprocess, "run", side_effect=self.mock_tools):
            receipt = debug.build_prepared(self.destination, inputs, "mock-godot")
        self.assertEqual(receipt["state"], "debug_exported_unverified")
        self.assertTrue(receipt["development_only"])
        self.assertFalse(receipt["store_ready"])
        self.assertTrue(receipt["game_resources_exported"])
        self.assertTrue(receipt["signed"])
        self.assertFalse(receipt["device_tested"])
        self.assertFalse(receipt["billing_purchases_verified"])
        self.assertEqual(len(receipt["resolved_maven_artifacts"]), 2)
        self.assertTrue(receipt["artifact"]["signature_verified"])
        self.assertTrue(receipt["artifact"]["default_launcher_label_verified"])
        self.assertEqual(receipt["artifact"]["app_name"], "Waddle Wars: Penguin Panic")
        self.assertTrue(receipt["artifact"]["android_16kb"]["structural_gate_passed"])
        self.assertEqual(receipt["artifact"]["game_resources"]["source_resource_count"], 8)
        self.assertTrue(any("--export-debug" in command for command in self.calls))
        self.assertFalse(any("--export-release" in command for command in self.calls))
        self.assertEqual(len(self.calls), 6)
        self.assertNotIn("config/use_custom_user_dir", (self.destination / "project/project.godot").read_text())

    def test_free_mvp_debug_build_excludes_billing(self) -> None:
        self.config["launch_edition"] = "free_offline_mvp"
        inputs, prepared = self.prepare()
        self.assertFalse(inputs["include_billing"])
        self.assertNotIn("GodotGooglePlayBilling/plugin.cfg", (self.destination / "project/project.godot").read_text())
        self.assertIn("addons/GodotGooglePlayBilling/plugin.cfg", prepared["omitted_deferred_sdk_files"])
        with patch.object(debug.subprocess, "run", side_effect=self.mock_tools):
            receipt = debug.build_prepared(self.destination, inputs, "mock-godot")
        self.assertEqual(receipt["state"], "debug_exported_unverified")
        self.assertIsNone(receipt["artifact"]["compiled_provider_class"])
        self.assertEqual(len(receipt["resolved_maven_artifacts"]), 1)

    def test_free_mvp_rejects_billing_dependency(self) -> None:
        self.config["launch_edition"] = "free_offline_mvp"
        inputs, prepared = self.prepare()
        self.artifact_fixture(self.destination, prepared)
        self.write(self.destination / "gradle-user/caches/billing.aar", b"unexpected billing")
        self.write(self.destination / "resolved_dependencies.json", json.dumps([{
            "group": "com.android.billingclient", "name": "billing", "version": "9.1.0",
            "file": str(self.destination / "gradle-user/caches/billing.aar")
        }]).encode())
        with self.assertRaisesRegex(ValueError, "must not resolve Google Play Billing"):
            integration.verify_dependencies(self.destination, None)

    def test_release_candidate_rejected_before_engine(self) -> None:
        inputs, receipt = self.prepare()
        receipt["state"] = "prepared_unbuilt"
        debug.save_receipt(self.destination, receipt)
        with patch.object(debug.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "development-only"):
                debug.build_prepared(self.destination, inputs, "mock-godot")
        run.assert_not_called()

    def test_snapshot_change_rejected_before_engine(self) -> None:
        inputs, _ = self.prepare()
        self.write(self.destination / "project/scenes/ui/main.tscn", b"modified")
        with patch.object(debug.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "Prepared source changed"):
                debug.build_prepared(self.destination, inputs, "mock-godot")
        run.assert_not_called()

    def test_missing_key_between_prepare_and_build_no_engine_no_generation(self) -> None:
        inputs, _ = self.prepare()
        self.key.unlink()
        with patch.object(debug.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "refusing engine import"):
                debug.build_prepared(self.destination, inputs, "mock-godot")
        run.assert_not_called()

    def test_cached_candidate_refused_not_reused(self) -> None:
        inputs, _ = self.prepare()
        (self.destination / "gradle-user").mkdir()
        with patch.object(debug.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "must be new"):
                debug.build_prepared(self.destination, inputs, "mock-godot")
        run.assert_not_called()

    def test_parse_failure_exit_zero_preserved_and_identity_restored(self) -> None:
        inputs, receipt = self.prepare()
        def failed(command, **kwargs):
            if "--import" in command:
                return subprocess.CompletedProcess(command, 0, "", "SCRIPT ERROR: Parse Error: fixture\n")
            return self.mock_tools(command, **kwargs)
        with patch.object(debug.subprocess, "run", side_effect=failed):
            with self.assertRaisesRegex(ValueError, "exit 0"):
                debug.build_prepared(self.destination, inputs, "mock-godot")
        failed_receipt = json.loads((self.destination / "receipt.json").read_text())
        self.assertEqual(failed_receipt["state"], "debug_build_failed")
        self.assertFalse(failed_receipt["store_ready"])
        self.assertFalse(failed_receipt["game_resources_exported"])
        self.assertEqual(debug.game_identity((self.destination / "project/project.godot").read_text()), receipt["identity"])
        self.assertIn("Parse Error", (self.destination / "logs/import.stderr.log").read_text())
        with patch.object(debug.subprocess, "run") as run:
            with self.assertRaises(ValueError):
                debug.build_prepared(self.destination, inputs, "mock-godot")
        run.assert_not_called()

    def test_wrong_engine_version_attempt_preserved(self) -> None:
        inputs, _ = self.prepare()
        with patch.object(debug.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "4.7.2.stable.official\n", "")):
            with self.assertRaisesRegex(ValueError, "Exact pinned"):
                debug.build_prepared(self.destination, inputs, "mock-godot")
        self.assertEqual(json.loads((self.destination / "receipt.json").read_text())["state"], "debug_build_failed")

    def test_custom_engine_same_semver_rejected_before_import(self) -> None:
        inputs, _ = self.prepare()
        with patch.object(debug.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "4.7.1.stable.custom_build.a13da4feb\n", "")) as run:
            with self.assertRaisesRegex(ValueError, "Exact pinned official"):
                debug.build_prepared(self.destination, inputs, "mock-godot")
        self.assertEqual(run.call_count, 1)

    def test_late_alignment_failure_keeps_signed_full_game_artifact_proof(self) -> None:
        inputs, _ = self.prepare()
        alignment = {"structural_gate_passed": False, "store_ready": False,
                     "libraries": {"lib/arm64-v8a/libgodot_android.so": ["RELRO end not aligned"]},
                     "packaging": "Verification successful", "failures": ["RELRO end not aligned"]}
        with patch.object(debug.subprocess, "run", side_effect=self.mock_tools), patch.object(debug, "check_alignment", return_value=alignment):
            with self.assertRaisesRegex(ValueError, "16-KB structural"):
                debug.build_prepared(self.destination, inputs, "mock-godot")
        receipt = json.loads((self.destination / "receipt.json").read_text())
        self.assertEqual(receipt["state"], "debug_build_failed")
        self.assertTrue(receipt["signed"])
        self.assertTrue(receipt["game_resources_exported"])
        self.assertTrue(receipt["artifact"]["signature_verified"])
        self.assertTrue(receipt["artifact"]["actual_apk_manifest_verified"])
        self.assertTrue(receipt["artifact"]["sha256"])
        self.assertFalse(receipt["artifact"]["android_16kb"]["structural_gate_passed"])
        self.assertFalse(receipt["store_ready"])
        self.assertTrue((self.destination / "logs/verify-001/android_16kb.json").is_file())
        self.calls = []
        with patch.object(debug.subprocess, "run", side_effect=self.mock_tools):
            retried = debug.verify_built(self.destination, inputs)
        self.assertEqual(retried["state"], "debug_exported_unverified")
        self.assertEqual(retried["artifact"]["sha256"], receipt["artifact"]["sha256"])
        self.assertFalse(retried["store_ready"])
        self.assertEqual(len(self.calls), 3)
        self.assertFalse(any("--import" in command or "--export-debug" in command for command in self.calls))
        self.assertTrue((self.destination / "logs/verify-002/android_16kb.json").is_file())
        self.assertTrue((self.destination / "logs/verify-001/android_16kb.json").is_file())
        self.assertEqual(retried["verification_attempts"][0]["artifact"]["android_16kb"], alignment)

    def test_verification_only_refuses_modified_apk(self) -> None:
        inputs, _ = self.prepare()
        with patch.object(debug.subprocess, "run", side_effect=self.mock_tools):
            debug.build_prepared(self.destination, inputs, "mock-godot")
        with zipfile.ZipFile(self.destination / debug.OUTPUT, "a") as artifact:
            artifact.writestr("tampered", b"different immutable APK")
        with patch.object(debug.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "APK changed"):
                debug.verify_built(self.destination, inputs)
        run.assert_not_called()

    def test_signing_args_redacted_without_credential_extraction(self) -> None:
        self.destination.mkdir()
        result = subprocess.CompletedProcess([], 0, "-Pdebug_keystore_password=fixture-secret\n", '-Prelease_keystore_alias="fixture-alias"\n')
        with patch.object(debug.subprocess, "run", return_value=result):
            debug.run_checked(["mock-tool"], self.destination / "step.log", {})
        self.assertNotIn("fixture-secret", (self.destination / "step.stdout.log").read_text())
        self.assertNotIn("fixture-alias", (self.destination / "step.stderr.log").read_text())

    def test_runtime_resource_remaps_must_resolve_existing_nonempty_data(self) -> None:
        apk = self.root / "resource-fixture.apk"
        with zipfile.ZipFile(apk, "w") as zipped:
            zipped.writestr("assets/model.glb.import", '[remap]\npath="res://.godot/imported/model.scn"\n')
            zipped.writestr("assets/.godot/imported/model.scn", b"converted")
            zipped.writestr("assets/bad.tscn.remap", '[remap]\npath="res://../unsafe"\n')
            zipped.writestr("assets/empty.gd", b"")
        with zipfile.ZipFile(apk) as zipped:
            names = set(zipped.namelist())
            self.assertEqual(debug.exported_path(zipped, "model.glb", names), "assets/.godot/imported/model.scn")
            for name in ("bad.tscn", "empty.gd", "missing.tscn", "../unsafe"):
                with self.subTest(name=name), self.assertRaises(ValueError):
                    debug.exported_path(zipped, name, names)

    def test_missing_fullgame_resource_rejected(self) -> None:
        inputs, receipt = self.prepare()
        self.artifact_fixture(self.destination, receipt)
        del receipt["source_files"]["scenes/gameplay/runner.tscn"]
        with zipfile.ZipFile(self.destination / debug.OUTPUT) as artifact:
            with self.assertRaisesRegex(ValueError, "complete expected game"):
                debug.verify_game_resources(artifact, self.destination / "project", receipt)

    def test_staged_resource_tamper_rejected(self) -> None:
        _, receipt = self.prepare()
        self.artifact_fixture(self.destination, receipt)
        self.write(self.destination / "project/android/build/src/main/assets/project.binary", b"modified")
        with zipfile.ZipFile(self.destination / debug.OUTPUT) as artifact:
            with self.assertRaisesRegex(ValueError, "differs from actual Godot export"):
                debug.verify_game_resources(artifact, self.destination / "project", receipt)

    def test_private_file_inside_otherwise_valid_apk_rejected(self) -> None:
        _, receipt = self.prepare()
        self.artifact_fixture(self.destination, receipt)
        with zipfile.ZipFile(self.destination / debug.OUTPUT, "a") as artifact:
            artifact.writestr("assets/.envrc", b"should not be included")
        with zipfile.ZipFile(self.destination / debug.OUTPUT) as artifact:
            with self.assertRaisesRegex(ValueError, "Private signing/environment"):
                debug.verify_game_resources(artifact, self.destination / "project", receipt)

    def test_signature_tool_failure_fails_artifact_gate(self) -> None:
        inputs, receipt = self.prepare()
        self.artifact_fixture(self.destination, receipt)
        (self.destination / "logs").mkdir()
        with patch.object(debug.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, "", "DOES NOT VERIFY\n")):
            with self.assertRaisesRegex(ValueError, "exit 1"):
                debug.verify_artifact(self.destination, inputs, receipt, {})

    def test_installed_aapt2_min_sdk_label_wrong_floor_rejected(self) -> None:
        inputs, receipt = self.prepare()
        self.artifact_fixture(self.destination, receipt)
        def wrong_floor(command, **kwargs):
            result = self.mock_tools(command, **kwargs)
            if "badging" in command:
                result.stdout = result.stdout.replace("minSdkVersion:'24'", "minSdkVersion:'25'")
            return result
        with patch.object(debug.subprocess, "run", side_effect=wrong_floor):
            with self.assertRaisesRegex(ValueError, "manifest differs"):
                debug.verify_artifact(self.destination, inputs, receipt, debug.build_environment(self.destination, inputs))

    def test_actual_default_launcher_title_required(self) -> None:
        inputs, receipt = self.prepare()
        self.artifact_fixture(self.destination, receipt)
        label = f"application-label:'{self.config['app_name']}'\n"
        for replacement in ("", "application-label:'Waddle Wars'\n", label + label):
            with self.subTest(replacement=replacement):
                def wrong_label(command, **kwargs):
                    result = self.mock_tools(command, **kwargs)
                    if "badging" in command:
                        result.stdout = result.stdout.replace(label, replacement)
                    return result
                with patch.object(debug.subprocess, "run", side_effect=wrong_label):
                    with self.assertRaisesRegex(ValueError, "default launcher label"):
                        debug.verify_artifact(self.destination, inputs, receipt, debug.build_environment(self.destination, inputs))

    def test_release_abi_or_missing_provider_is_rejected(self) -> None:
        for changed_name in ("lib/x86_64/fake.so", "classes2.dex"):
            with self.subTest(changed_name=changed_name):
                inputs, receipt = self.prepare()
                self.artifact_fixture(self.destination, receipt)
                (self.destination / "logs").mkdir()
                if changed_name.startswith("lib/"):
                    with zipfile.ZipFile(self.destination / debug.OUTPUT, "a") as artifact:
                        artifact.writestr(changed_name, elf())
                else:
                    self.write(self.destination / "project/android/build/build/intermediates/merged_manifests/standardDebug/processStandardDebugManifest/AndroidManifest.xml", b'<manifest package="wrong"/>')
                with patch.object(debug.subprocess, "run", side_effect=self.mock_tools):
                    with self.assertRaises(ValueError):
                        debug.verify_artifact(self.destination, inputs, receipt, debug.build_environment(self.destination, inputs))
                # Each attempted fixture uses its own new retained directory.
                self.destination = self.root / "second-debug-candidate"


if __name__ == "__main__":
    unittest.main()
