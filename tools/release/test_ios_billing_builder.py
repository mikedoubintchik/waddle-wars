"""Mocked iOS bridge build variants; no compiler, signing, engine or device runs."""
from contextlib import redirect_stderr, redirect_stdout
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import build_ios_billing as builder
from install_ios_billing import SOURCES, install, verify_plugin
from native_release import sha256


GENERATED_HEADERS = (
    "core/extension/gdextension_interface.gen.h",
    "core/version_generated.gen.h",
    "core/disabled_classes.gen.h",
    "core/object/gdvirtual.gen.h",
)
DEVICE_DEFINES = [
    "IOS_ENABLED", "APPLE_EMBEDDED_ENABLED", "UNIX_ENABLED",
    "COREAUDIO_ENABLED", "THREADS_ENABLED", "NDEBUG",
]
BUILD_CONFIGURATIONS = (("device", "arm64"), ("simulator", "arm64"), ("simulator", "x86_64"))


class IOSBillingBuilderTests(unittest.TestCase):
    def setUp(self) -> None:
        self.folder = tempfile.TemporaryDirectory(prefix="ww-ios-billing-builder-")
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name).resolve()
        self.headers = self.root / "headers"
        for name in GENERATED_HEADERS:
            path = self.headers / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("Synthetic generated header; never compiled")
        self.source = self.root / "source"
        self.source.mkdir()
        for name in SOURCES:
            (self.source / name).write_text("Synthetic bridge source: " + name)
        self.destination = self.root / "plugin"
        self.lock = json.loads(builder.LOCK.read_text())
        self.commit = self.lock["ios"]["godot_source_commit"]
        self.sdk_version = "26.5"
        self.symbols = "\n".join(
            "00000000 T __Z" + str(len(entry)) + entry + "v"
            for entry in ("init_waddle_storekit", "deinit_waddle_storekit")
        )
        self.commands = []
        self.output_commands = []
        for mock in (
            patch.object(builder, "SOURCE", self.source),
            patch.object(builder, "output", side_effect=self.fake_output),
            patch.object(builder.subprocess, "run", side_effect=self.fake_run),
        ):
            mock.start()
            self.addCleanup(mock.stop)

    def fake_output(self, command: list[str]) -> str:
        self.output_commands.append(command)
        if command[0] == "git":
            return self.commit
        if command[:2] == ["xcrun", "--sdk"]:
            if command[-1] == "--show-sdk-version":
                return self.sdk_version
            return "/synthetic/sdk/" + command[2]
        if command[:2] == ["xcrun", "--find"]:
            return "/synthetic/bin/" + command[2]
        if command[:2] == ["xcrun", "nm"]:
            return self.symbols
        self.fail("Unexpected external query: " + repr(command))

    def fake_run(self, command: list[str], *, cwd: Path, check: bool) -> subprocess.CompletedProcess:
        self.assertTrue(check)
        self.assertEqual(cwd.parent, self.destination)
        self.assertIn(cwd.name, ("objects-debug", "objects-release"))
        self.commands.append(command)
        Path(command[command.index("-o") + 1]).write_bytes(b"Synthetic compiled artifact")
        return subprocess.CompletedProcess(command, 0)

    def assert_compile_variant(self, receipt: dict, *, variant: str, sdk: str,
                               platform: str, target: str, architecture: str = "arm64") -> None:
        self.assertEqual(receipt["variant"], variant)
        self.assertEqual(receipt["sdk_name"], sdk)
        self.assertEqual(receipt["ios_sdk"], self.sdk_version)
        self.assertEqual(receipt["target_triple"], target)
        self.assertEqual(receipt["platform"], platform)
        self.assertEqual(receipt["architecture"], architecture)
        self.assertEqual(receipt["state"], "compiled_unverified")
        self.assertFalse(receipt["device_billing_passed"])
        self.assertFalse(receipt["device_authentication_passed"])
        self.assertFalse(receipt["store_ready"])
        self.assertEqual(json.loads((self.destination / "waddle_build_receipt.json").read_text()), receipt)
        sdk_queries = [command for command in self.output_commands if "--sdk" in command]
        self.assertEqual(sdk_queries, [
            ["xcrun", "--sdk", sdk, "--show-sdk-path"],
            ["xcrun", "--sdk", sdk, "--show-sdk-version"],
        ])
        compilations = [command for command in self.commands if "-target" in command]
        self.assertEqual(len(compilations), 4)
        expected_defines = [*DEVICE_DEFINES]
        if variant == "simulator":
            expected_defines.append("IOS_SIMULATOR")
        for command in compilations:
            self.assertEqual(command[command.index("-target") + 1], target)
            sdk_flag = "-sdk" if command[0].endswith("swiftc") else "-isysroot"
            self.assertEqual(command[command.index(sdk_flag) + 1], "/synthetic/sdk/" + sdk)
            if sdk_flag == "-isysroot":
                mode_defines = [arg[2:] for arg in command if arg.startswith("-D")]
                mode = "debug" if "DEBUG_ENABLED" in mode_defines else "release"
                self.assertEqual(mode_defines, expected_defines + (["DEBUG_ENABLED"] if mode == "debug" else []))
        self.assertEqual(receipt["engine_cpp_defines"], {
            "debug": [*expected_defines, "DEBUG_ENABLED"], "release": expected_defines,
        })
        self.assertEqual(set(receipt["source_hashes"]), set(SOURCES))
        for name in SOURCES:
            self.assertEqual(receipt["source_hashes"][name], sha256(self.source / name))
        for name, digest in receipt["artifacts"].items():
            self.assertEqual(digest, sha256(self.destination / name))

    def test_default_device_compilation_and_production_verification(self) -> None:
        receipt = builder.build(self.headers, self.destination, self.lock)
        self.assert_compile_variant(receipt, variant="device", sdk="iphoneos",
                                    platform="ios", target="arm64-apple-ios15.0")
        self.assertEqual(verify_plugin(self.destination, self.lock, self.source), receipt)

    def test_auth_policy_is_compiled_and_source_mutation_rejects_receipt(self) -> None:
        original_run = self.fake_run
        def mutate_during_build(command, *, cwd, check):
            result = original_run(command, cwd=cwd, check=check)
            (self.source / "WWAuthenticationPolicy.swift").write_text("Changed during compilation")
            return result
        with patch.object(builder.subprocess, "run", side_effect=mutate_during_build):
            with self.assertRaisesRegex(ValueError, "sources changed"):
                builder.build(self.headers, self.destination, self.lock)
        self.assertFalse((self.destination / "waddle_build_receipt.json").exists())
        for command in self.commands:
            if command[0].endswith("swiftc"):
                self.assertIn(str(self.source / "WWAuthenticationPolicy.swift"), command)

    def test_simulator_compilation_and_truthful_receipt(self) -> None:
        receipt = builder.build(self.headers, self.destination, self.lock, variant="simulator")
        self.assert_compile_variant(receipt, variant="simulator", sdk="iphonesimulator",
                                    platform="ios_simulator", target="arm64-apple-ios15.0-simulator")

    def test_x86_64_simulator_compilation_and_truthful_receipt(self) -> None:
        receipt = builder.build(self.headers, self.destination, self.lock,
                                variant="simulator", architecture="x86_64")
        self.assert_compile_variant(receipt, variant="simulator", sdk="iphonesimulator",
                                    platform="ios_simulator", target="x86_64-apple-ios15.0-simulator",
                                    architecture="x86_64")

    def test_production_verifier_and_installer_reject_simulator_receipt(self) -> None:
        for architecture in ("arm64", "x86_64"):
            with self.subTest(architecture=architecture):
                self.destination = self.root / ("plugin-" + architecture)
                builder.build(self.headers, self.destination, self.lock,
                              variant="simulator", architecture=architecture)
                with self.assertRaisesRegex(ValueError, "platform, architecture"):
                    verify_plugin(self.destination, self.lock, self.source)
                installed = self.root / ("production-installed-" + architecture)
                with self.assertRaisesRegex(ValueError, "platform, architecture"):
                    install(self.destination, installed, self.lock)
                self.assertFalse(installed.exists())

    def test_cli_defaults_to_device_and_forwards_simulator(self) -> None:
        for arguments, variant, architecture in (
            ([], "device", "arm64"),
            (["--architecture", "arm64"], "device", "arm64"),
            (["--variant", "simulator"], "simulator", "arm64"),
            (["--variant", "simulator", "--architecture", "x86_64"], "simulator", "x86_64"),
        ):
            with self.subTest(variant=variant, architecture=architecture), patch.object(builder, "build", return_value={}) as build:
                with patch.object(sys, "argv", ["build_ios_billing.py", "--godot-source", str(self.headers),
                                               *arguments, str(self.destination)]), redirect_stdout(io.StringIO()):
                    self.assertEqual(builder.main(), 0)
                build.assert_called_once_with(self.headers, self.destination, self.lock,
                                              variant=variant, architecture=architecture)

    def test_cli_rejects_unknown_variant_before_build(self) -> None:
        with patch.object(builder, "build") as build, redirect_stderr(io.StringIO()):
            with patch.object(sys, "argv", ["build_ios_billing.py", "--godot-source", str(self.headers),
                                           "--variant", "unknown", str(self.destination)]):
                with self.assertRaises(SystemExit) as error:
                    builder.main()
        self.assertEqual(error.exception.code, 2)
        build.assert_not_called()

    def test_api_rejects_unknown_variant_before_external_queries(self) -> None:
        with self.assertRaisesRegex(ValueError, "variant"):
            builder.build(self.headers, self.destination, self.lock, variant="unknown")
        self.assertEqual(self.output_commands, [])
        self.assertFalse(self.destination.exists())

    def test_cli_rejects_unknown_architecture_before_build(self) -> None:
        with patch.object(builder, "build") as build, redirect_stderr(io.StringIO()):
            with patch.object(sys, "argv", ["build_ios_billing.py", "--godot-source", str(self.headers),
                                           "--architecture", "unknown", str(self.destination)]):
                with self.assertRaises(SystemExit) as error:
                    builder.main()
        self.assertEqual(error.exception.code, 2)
        build.assert_not_called()

    def test_api_rejects_unknown_architecture_before_external_queries(self) -> None:
        with self.assertRaisesRegex(ValueError, "architecture"):
            builder.build(self.headers, self.destination, self.lock,
                          variant="simulator", architecture="unknown")
        self.assertEqual(self.output_commands, [])
        self.assertFalse(self.destination.exists())

    def test_api_rejects_x86_64_device_before_external_queries(self) -> None:
        with self.assertRaisesRegex(ValueError, "simulator-only"):
            builder.build(self.headers, self.destination, self.lock, architecture="x86_64")
        self.assertEqual(self.output_commands, [])
        self.assertFalse(self.destination.exists())

    def test_cli_rejects_x86_64_device_before_external_queries(self) -> None:
        with patch.object(sys, "argv", ["build_ios_billing.py", "--godot-source", str(self.headers),
                                       "--architecture", "x86_64", str(self.destination)]):
            with redirect_stderr(io.StringIO()):
                self.assertEqual(builder.main(), 1)
        self.assertEqual(self.output_commands, [])
        self.assertFalse(self.destination.exists())

    def test_existing_output_directory_is_never_overwritten(self) -> None:
        self.destination.mkdir()
        sentinel = self.destination / "existing.a"
        sentinel.write_bytes(b"Keep existing binaries")
        for variant, architecture in BUILD_CONFIGURATIONS:
            with self.subTest(variant=variant, architecture=architecture), self.assertRaisesRegex(ValueError, "must be new"):
                builder.build(self.headers, self.destination, self.lock, variant=variant, architecture=architecture)
        self.assertEqual(sentinel.read_bytes(), b"Keep existing binaries")
        self.assertEqual(self.output_commands, [])

    def test_exact_godot_commit_remains_required(self) -> None:
        self.commit = "0" * 40
        for variant, architecture in BUILD_CONFIGURATIONS:
            with self.subTest(variant=variant, architecture=architecture), self.assertRaisesRegex(ValueError, "exact pinned"):
                builder.build(self.headers, self.destination, self.lock, variant=variant, architecture=architecture)
        self.assertEqual(self.commands, [])
        self.assertFalse(self.destination.exists())

    def test_all_generated_headers_remain_required(self) -> None:
        for name in GENERATED_HEADERS:
            path = self.headers / name
            contents = path.read_text()
            path.unlink()
            for variant, architecture in BUILD_CONFIGURATIONS:
                with self.subTest(header=name, variant=variant, architecture=architecture), self.assertRaisesRegex(ValueError, "Generated Godot header missing"):
                    builder.build(self.headers, self.destination, self.lock, variant=variant, architecture=architecture)
            path.write_text(contents)
        self.assertEqual(self.commands, [])
        self.assertFalse(self.destination.exists())

    def test_minimum_sdk_gate_applies_to_both_variants(self) -> None:
        self.sdk_version = "25.9"
        for variant, architecture in BUILD_CONFIGURATIONS:
            with self.subTest(variant=variant, architecture=architecture), self.assertRaisesRegex(ValueError, "iOS 26 SDK"):
                builder.build(self.headers, self.destination, self.lock, variant=variant, architecture=architecture)
        self.assertEqual(self.commands, [])
        self.assertFalse(self.destination.exists())

    def test_missing_cpp_entrypoint_cannot_create_success_receipt(self) -> None:
        self.symbols = "00000000 T unmangled_init_waddle_storekit"
        with self.assertRaisesRegex(ValueError, r"C\+\+ plugin entrypoint missing"):
            builder.build(self.headers, self.destination, self.lock, variant="simulator")
        self.assertFalse((self.destination / "waddle_build_receipt.json").exists())

    def test_compiler_failure_cannot_create_success_receipt(self) -> None:
        with patch.object(builder.subprocess, "run", side_effect=subprocess.CalledProcessError(1, ["synthetic-compiler"])):
            with self.assertRaises(subprocess.CalledProcessError):
                builder.build(self.headers, self.destination, self.lock, variant="simulator")
        self.assertFalse((self.destination / "waddle_build_receipt.json").exists())

    def test_device_receipt_still_binds_artifact_and_source_bytes(self) -> None:
        builder.build(self.headers, self.destination, self.lock)
        artifact = self.destination / "WaddleStoreKit.release.a"
        contents = artifact.read_bytes()
        artifact.write_bytes(b"Changed artifact")
        with self.assertRaisesRegex(ValueError, "artifact missing or changed"):
            verify_plugin(self.destination, self.lock, self.source)
        artifact.write_bytes(contents)
        (self.source / "WWStoreKitBridge.swift").write_text("Changed source")
        with self.assertRaisesRegex(ValueError, "source changed after compilation"):
            verify_plugin(self.destination, self.lock, self.source)


if __name__ == "__main__":
    unittest.main()
