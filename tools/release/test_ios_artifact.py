"""Synthetic artifact-boundary tests; no signing, CMS, credentials, or devices.

Host inspection processes are always mocked. Public certificate/profile bytes,
Mach-O files, archives, and IPAs below are disposable fixtures, not real builds.
"""
from __future__ import annotations

from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import plistlib
import stat
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import warnings
import zipfile

import verify_ios_artifact as verifier


TEAM = "ABCDE12345"
BUNDLE = "com.example.synthetic"
TITLE = "Waddle Wars: Penguin Panic"
PUBLIC_CERT = b"synthetic-public-DER-certificate-not-real-X509"
CERT_SHA1 = hashlib.sha1(PUBLIC_CERT).hexdigest().upper()
CERT_SHA256 = hashlib.sha256(PUBLIC_CERT).hexdigest()
PROFILE_BYTES = b"synthetic-public-profile-not-real-CMS"
PROFILE_SHA256 = hashlib.sha256(PROFILE_BYTES).hexdigest()
NEUTRAL_LOCALIZATION = b"/* Localized versions of Info.plist keys */\n"
COMPILED_NEUTRAL_LOCALIZATION = bytes.fromhex(
    "62706c6973743030d0080000000000000101000000000000000100000000000000000000000000000009")
ENTITLEMENTS = {
    "application-identifier": TEAM + "." + BUNDLE,
    "com.apple.developer.team-identifier": TEAM,
    "get-task-allow": False,
    "beta-reports-active": True,
}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path: Path, data: bytes, mode: int = 0o644) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    path.chmod(mode)
    for parent in path.parents:
        if parent.name.startswith("ww-ios-artifact-fixture-"):
            break
        parent.chmod(0o755)
    return path


def macho(signature: bytes = b"synthetic-signature-archive", *, payload: bytes = b"immutable-native-code") -> bytes:
    header = struct.pack("<8I", 0xFEEDFACF, 0x0100000C, 0, 2, 1, 16, 0, 0)
    command = struct.pack("<4I", 0x1D, 16, 48 + len(payload), len(signature))
    return header + command + payload + signature


def zip_entries(path: Path, entries: list[tuple[str | zipfile.ZipInfo, bytes]]) -> None:
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", UserWarning)
        with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for name, data in entries:
                if isinstance(name, str):
                    entry = zipfile.ZipInfo(name)
                    entry.create_system = 3
                    entry.external_attr = (0o40755 if name.endswith("/") else 0o100644) << 16
                    if name.endswith("/"):
                        entry.external_attr |= 0x10
                    entry.compress_type = zipfile.ZIP_DEFLATED
                else:
                    entry = name
                archive.writestr(entry, data)


class ArtifactFixture(unittest.TestCase):
    def setUp(self) -> None:
        self.folder = tempfile.TemporaryDirectory(prefix="ww-ios-artifact-fixture-")
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name).resolve()
        self.candidate = self.root / "candidate"
        self.project = self.candidate / "project"
        self.archive = self.root / "synthetic.xcarchive"
        self.app = self.archive / "Products/Applications/waddlewars.app"
        self.installed_profile = write(self.root / "synthetic.mobileprovision", PROFILE_BYTES)
        self.helper = write(self.root / "synthetic-cms-helper", b"synthetic helper; never executed", 0o755)
        self.helper_hash = digest(self.helper)
        self.tools = {
            name: write(self.root / "tools" / name, b"synthetic tool; never executed " + name.encode(), 0o755)
            for name in ("lipo", "codesign", "otool", "strings", "nm", "python")
        }
        self.tool_patch = patch.object(verifier, "resolve_tools", return_value=self.tools)
        self.tool_patch.start()
        self.addCleanup(self.tool_patch.stop)
        self.commands: list[tuple[list[str], dict]] = []
        self.process_hook = None
        self.profile_overrides: dict = {}
        self.entitlement_overrides: dict = {}
        self.command_output_overrides: dict[str, tuple[bytes, bytes]] = {}
        self.duplicate_profile_keys = False
        self.codesign_display = "TeamIdentifier=" + TEAM + "\nIdentifier=" + BUNDLE + "\nAuthority=Apple Distribution: Synthetic (" + TEAM + ")\n"
        self.process_patch = patch.object(verifier.subprocess, "run", side_effect=self.synthetic_process)
        self.process_patch.start()
        self.addCleanup(self.process_patch.stop)
        self.sequence = 0

        self.info = {
            "CFBundleDisplayName": TITLE, "CFBundleName": "waddlewars",
            "CFBundleExecutable": "waddlewars", "CFBundleIdentifier": BUNDLE,
            "CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "3",
            "MinimumOSVersion": "15.0", "CFBundlePackageType": "APPL",
        }
        source = {
            "project.godot": b'[application]\nconfig/name="Waddle Wars"\nconfig/version="1.0.0"\n',
            "scripts/utilities/game_config.gd": b'const BUILD_ID: String = "synthetic"\n',
            "scripts/commerce/commerce_client.gd": b"# synthetic frozen runtime\n",
            "scenes/menus/main_menu.tscn": b"# synthetic frozen scene\n",
        }
        for name, raw in source.items():
            write(self.project / name, raw)
        presets = ('[preset.0]\nname="Synthetic iOS"\nplatform="iOS"\n'
                   '[preset.0.options]\napplication/app_store_team_id="' + TEAM + '"\n'
                   'application/bundle_identifier="' + BUNDLE + '"\n'
                   'application/short_version="1.0.0"\napplication/version="3"\n')
        write(self.project / "export_presets.cfg", presets.encode())
        pck = write(self.project / "build/ios/waddlewars/waddlewars.pck", b"synthetic-frozen-export-PCK")
        exported = write(self.project / "build/ios/waddlewars/waddlewars-Info.plist", plistlib.dumps(self.info))
        source_files = {name: hashlib.sha256(raw).hexdigest() for name, raw in source.items()}
        prepared = {name: digest(self.project / name) for name in (*source, "export_presets.cfg")}
        policy_path = str(exported.relative_to(self.candidate))
        self.receipt = {
            "schema_version": 1, "state": "exported_unverified", "platform": "ios",
            "app_name": TITLE, "project_name": "Waddle Wars", "bundle_id": BUNDLE,
            "version": "1.0.0", "build_number": 3, "godot_version": "4.7.1.stable",
            "source_files": source_files,
            "source_sha256": hashlib.sha256(json.dumps(source_files, sort_keys=True).encode()).hexdigest(),
            "prepared_files": prepared,
            "artifacts": {str(path.relative_to(self.candidate)): digest(path) for path in (pck, exported)},
            "ios_plist_policy": {"path": policy_path, "policy": "no-camera-microphone-photo-library-v1",
                                 "removed_keys": [], "before_sha256": digest(exported), "after_sha256": digest(exported)},
            "ios_display_name_policy": {"path": policy_path, "policy": "launcher-title-without-project-rename-v1",
                                        "app_name": TITLE, "before_sha256": digest(exported), "after_sha256": digest(exported)},
            "store_ready": False,
        }
        self.save_candidate()
        write(self.app / "Info.plist", plistlib.dumps(self.info))
        write(self.app / "waddlewars", macho(), 0o755)
        write(self.app / "waddlewars.pck", pck.read_bytes())
        write(self.app / "embedded.mobileprovision", PROFILE_BYTES)
        write(self.app / "_CodeSignature/CodeResources", b"synthetic archive resource seal")
        write(self.app / "assets/synthetic-resource", b"immutable app resource")
        write(self.archive / "Info.plist", plistlib.dumps({"ApplicationProperties": {
            "ApplicationPath": "Applications/waddlewars.app", "CFBundleIdentifier": BUNDLE,
            "CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "3",
        }}))

    def save_candidate(self) -> None:
        write(self.candidate / "receipt.json", json.dumps(self.receipt, sort_keys=True).encode())

    def evidence(self) -> Path:
        self.sequence += 1
        return self.root / ("evidence-%d" % self.sequence)

    def archive_options(self) -> dict:
        return {"team_id": TEAM, "certificate_sha1": CERT_SHA1, "certificate_sha256": CERT_SHA256,
                "installed_profile": self.installed_profile, "profile_sha256": PROFILE_SHA256,
                "cms_helper": self.helper, "cms_helper_sha256": self.helper_hash}

    def verify_archive(self, evidence: Path | None = None, **options) -> dict:
        return verifier.verify_archive(self.candidate, self.archive, evidence or self.evidence(),
                                       **{**self.archive_options(), **options})

    def signed_receipt(self) -> Path:
        result = self.verify_archive()
        path = write(self.root / "signed-archive.json", json.dumps(result, sort_keys=True).encode())
        return path

    def ipa_entries(self) -> list[tuple[zipfile.ZipInfo, bytes]]:
        entries = []
        for directory in (Path("Payload"), Path("Payload/waddlewars.app")):
            entry = zipfile.ZipInfo(str(directory) + "/")
            entry.create_system = 3
            entry.external_attr = (0o40755 << 16) | 0x10
            entries.append((entry, b""))
        for path in sorted(self.app.rglob("*")):
            name = "Payload/waddlewars.app/" + str(path.relative_to(self.app))
            if path.is_dir():
                name += "/"
            entry = zipfile.ZipInfo(name)
            entry.create_system = 3
            entry.external_attr = path.stat().st_mode << 16
            if path.is_dir():
                entry.external_attr |= 0x10
            entry.compress_type = zipfile.ZIP_DEFLATED
            entries.append((entry, b"" if path.is_dir() else path.read_bytes()))
        return entries

    def write_ipa(self, entries=None) -> Path:
        path = self.root / "synthetic.ipa"
        zip_entries(path, self.ipa_entries() if entries is None else entries)
        return path

    def verify_ipa(self, ipa: Path, receipt: Path, evidence: Path | None = None, **options) -> dict:
        return verifier.verify_ipa(ipa, self.archive, receipt, evidence or self.evidence(),
                                   **{"ipa_sha256": digest(ipa), "archive_receipt_sha256": digest(receipt),
                                      "cms_helper": self.helper, "cms_helper_sha256": self.helper_hash, **options})

    def synthetic_process(self, argv, **kwargs):
        command = [str(part) for part in argv]
        self.commands.append((command, kwargs))
        if self.process_hook is not None:
            self.process_hook(command, kwargs)
        output = b""
        error = b""
        tool = Path(command[0]).name
        if tool == "lipo":
            output = b"arm64\n"
        elif tool == "codesign":
            extraction = next((part for part in command if part.startswith("--extract-certificates=")), None)
            if extraction:
                write(Path(extraction.split("=", 1)[1] + "0"), PUBLIC_CERT)
            elif "--entitlements" in command or any(part.startswith("--entitlements=") for part in command):
                output = plistlib.dumps({**ENTITLEMENTS, **self.entitlement_overrides})
            elif "--verify" not in command:
                error = self.codesign_display.encode()
        elif tool == "otool":
            output = b"/System/Library/Frameworks/StoreKit.framework/StoreKit\n/System/Library/Frameworks/AuthenticationServices.framework/AuthenticationServices\n"
        elif tool == "strings":
            output = b"WaddleStoreKit\nWWStoreKitBridge\nWWAuthenticationBridge\n"
        elif tool == "nm":
            output = b"_stat\n_mach_absolute_time\n"
        elif tool == "python":
            profile = Path(command[command.index("--mobileprovision") + 1])
            result = {
                "state": "profile_signature_and_metadata_verified",
                "cms_signature_trust": "APPLE_PROVISIONING_POLICY_VERIFIED_OFFLINE",
                "profile_eligible_for_archive": True, "metadata_valid": True,
                "mobileprovision_sha256": digest(profile), "cms_helper_sha256": self.helper_hash,
                "matched_certificate_sha1": CERT_SHA1, "matched_certificate_sha256": CERT_SHA256,
                "team_id": TEAM, "app_id": BUNDLE, "profile_name": "Waddle Wars App Store",
                "profile_uuid": "88e2491b-2c5e-4f0e-b0d2-392a099bec93",
                "signing_authorized": False, "store_ready": False,
            }
            output = json.dumps({**result, **self.profile_overrides}).encode()
            if self.duplicate_profile_keys:
                output = b'{"team_id":"ZZZZZ12345",' + output[1:]
        else:
            raise AssertionError("Unmocked host operation: " + repr(command))
        output, error = self.command_output_overrides.get(tool, (output, error))
        kwargs["stdout"].write(output)
        kwargs["stderr"].write(error)
        kwargs["stdout"].flush()
        kwargs["stderr"].flush()
        return subprocess.CompletedProcess(command, 0)

    @contextmanager
    def changed(self, path: Path, data: bytes):
        prior = path.read_bytes()
        mode = stat.S_IMODE(path.stat().st_mode)
        path.write_bytes(data)
        try:
            yield
        finally:
            path.write_bytes(prior)
            path.chmod(mode)


class ArchiveBoundaryTests(ArtifactFixture):
    def test_valid_archive_records_boundaries_without_store_authorization(self) -> None:
        result = self.verify_archive()
        self.assertEqual(result["state"], "signed_archive_verified")
        self.assertTrue(result["signed_archive_verified"])
        for key in ("store_ready", "device_acceptance_passed", "store_upload_performed"):
            self.assertIs(result[key], False)
        self.assertEqual(result["source_files"], self.receipt["source_files"])
        self.assertEqual(result["source_sha256"], self.receipt["source_sha256"])
        self.assertEqual(result["app_name"], TITLE)
        self.assertIn("archive_app_file_sha256", result)
        self.assertIn("archive_app_inventory", result)
        self.assertTrue(self.commands)
        for command, kwargs in self.commands:
            self.assertEqual(kwargs["timeout"], 60)
            self.assertFalse(kwargs["check"])
            self.assertEqual(kwargs["env"].get("LC_ALL"), "C")
            self.assertLessEqual(set(kwargs["env"]), {"HOME", "TMPDIR", "PATH", "LANG", "LC_ALL", "TZ"})
            for key in ("HOME", "TMPDIR"):
                if key in os.environ:
                    self.assertEqual(kwargs["env"].get(key), os.environ[key])
            if Path(command[0]).name == "python":
                self.assertEqual(command[1:3], ["-I", "-S"])

    def test_candidate_receipt_rejects_invalid_identity_and_hash_shapes(self) -> None:
        mutations = {"schema_version": 0, "state": "prepared_unbuilt", "platform": "android",
                     "source_sha256": "0" * 64, "app_name": "", "source_files": {}, "prepared_files": {},
                     "artifacts": {}, "version": "", "build_number": 0}
        for key, value in mutations.items():
            with self.subTest(field=key), self.changed(self.candidate / "receipt.json",
                                                     json.dumps({**self.receipt, key: value}).encode()):
                with self.assertRaises(ValueError):
                    self.verify_archive()

    def test_frozen_runtime_export_and_pack_changes_are_rejected(self) -> None:
        paths = [self.project / "scripts/commerce/commerce_client.gd", self.project / "project.godot",
                 self.project / "export_presets.cfg", self.project / "build/ios/waddlewars/waddlewars.pck",
                 self.project / "build/ios/waddlewars/waddlewars-Info.plist", self.app / "waddlewars.pck"]
        for path in paths:
            with self.subTest(path=path.name), self.changed(path, path.read_bytes() + b"changed"):
                with self.assertRaises(ValueError):
                    self.verify_archive()

    def test_undeclared_runtime_or_export_files_rejected(self) -> None:
        for relative in ("scripts/undeclared.gd", "build/ios/undeclared.bin"):
            path = write(self.project / relative, b"unreviewed")
            try:
                with self.subTest(relative=relative), self.assertRaises(ValueError):
                    self.verify_archive()
            finally:
                path.unlink()

    def test_app_title_bundle_versions_and_permissions_rejected(self) -> None:
        fields = {"CFBundleDisplayName": "Wrong launcher", "CFBundleIdentifier": "com.example.other",
                  "CFBundleVersion": "4", "CFBundleShortVersionString": "2.0.0",
                  "CFBundleExecutable": "other", "NSCameraUsageDescription": "",
                  "NSPhotoLibraryUsageDescription": "", "NSMicrophoneUsageDescription": ""}
        for key, value in fields.items():
            with self.subTest(field=key), self.changed(self.app / "Info.plist", plistlib.dumps({**self.info, key: value})):
                with self.assertRaises(ValueError):
                    self.verify_archive()

    def test_localized_title_overrides_rejected(self) -> None:
        localized = write(self.app / "en.lproj/InfoPlist.strings", b'"CFBundleDisplayName" = "Wrong launcher";\n')
        with self.assertRaises(ValueError):
            self.verify_archive()
        self.assertTrue(localized.exists())

    def test_only_exact_neutral_exported_localization_is_allowed(self) -> None:
        localized = write(self.app / "en.lproj/InfoPlist.strings", NEUTRAL_LOCALIZATION)
        self.assertEqual(self.verify_archive()["state"], "signed_archive_verified")
        variants = (b'"CFBundleDisplayName" = "Wrong launcher";\n',
                    NEUTRAL_LOCALIZATION + "/* extra Unicode: é */\n".encode(),
                    b"/* Another neutral-looking comment */\n", b"\xef\xbb\xbf" + NEUTRAL_LOCALIZATION)
        for variant in variants:
            with self.subTest(bytes=variant), self.changed(localized, variant), self.assertRaises(ValueError):
                self.verify_archive()

    def freeze_neutral_localization(self) -> None:
        exported = write(self.project / "build/ios/waddlewars/en.lproj/InfoPlist.strings", NEUTRAL_LOCALIZATION)
        self.receipt["artifacts"][str(exported.relative_to(self.candidate))] = digest(exported)
        self.save_candidate()

    def test_xcode_compiled_empty_localization_is_bound_through_archive_and_ipa(self) -> None:
        self.freeze_neutral_localization()
        self.assertEqual(plistlib.loads(COMPILED_NEUTRAL_LOCALIZATION), {})
        self.assertEqual(hashlib.sha256(COMPILED_NEUTRAL_LOCALIZATION).hexdigest(),
                         "9261ecceda608ef174256e5fdc774c1e6e3dcf533409c1bc393d490d01c713f1")
        localized = write(self.app / "en.lproj/InfoPlist.strings", COMPILED_NEUTRAL_LOCALIZATION)
        receipt = self.signed_receipt()
        result = self.verify_ipa(self.write_ipa(), receipt)
        self.assertTrue(result["ipa_verified"])
        self.assertEqual(result["compiled_neutral_localizations"],
                         {"en.lproj/InfoPlist.strings": digest(localized)})

    def test_compiled_localization_requires_same_frozen_export_path(self) -> None:
        localized = write(self.app / "en.lproj/InfoPlist.strings", COMPILED_NEUTRAL_LOCALIZATION)
        with self.assertRaises(ValueError):
            self.verify_archive()
        self.freeze_neutral_localization()
        localized.rename(self.app / "en.lproj/unknown-InfoPlist.strings")
        write(self.app / "fr.lproj/InfoPlist.strings", COMPILED_NEUTRAL_LOCALIZATION)
        with self.assertRaises(ValueError):
            self.verify_archive()

    def test_compiled_localization_never_allows_keys_or_other_empty_encodings(self) -> None:
        self.freeze_neutral_localization()
        variants = [COMPILED_NEUTRAL_LOCALIZATION + b"\0", plistlib.dumps({})]
        variants.extend(plistlib.dumps({key: value}, fmt=plistlib.FMT_BINARY)
                        for key, value in (("CFBundleDisplayName", TITLE), ("CFBundleDisplayName", "Wrong"),
                                           ("NSCameraUsageDescription", ""), ("NSMicrophoneUsageDescription", ""),
                                           ("NSPhotoLibraryUsageDescription", "")))
        for variant in variants:
            with self.subTest(bytes=variant):
                write(self.app / "en.lproj/InfoPlist.strings", variant)
                with self.assertRaises(ValueError):
                    self.verify_archive()

    def test_compiled_localization_does_not_expand_export_source_policy(self) -> None:
        self.freeze_neutral_localization()
        exported = write(self.project / "build/ios/waddlewars/en.lproj/InfoPlist.strings",
                         COMPILED_NEUTRAL_LOCALIZATION)
        self.receipt["artifacts"][str(exported.relative_to(self.candidate))] = digest(exported)
        self.save_candidate()
        write(self.app / "en.lproj/InfoPlist.strings", COMPILED_NEUTRAL_LOCALIZATION)
        with self.assertRaises(ValueError):
            self.verify_archive()

    def test_compiled_localization_receipt_binding_cannot_change_for_ipa(self) -> None:
        self.freeze_neutral_localization()
        write(self.app / "en.lproj/InfoPlist.strings", COMPILED_NEUTRAL_LOCALIZATION)
        receipt = self.signed_receipt()
        result = json.loads(receipt.read_text())
        result["compiled_neutral_localizations"] = {}
        write(receipt, json.dumps(result).encode())
        with self.assertRaises(ValueError):
            self.verify_ipa(self.write_ipa(), receipt)

    def test_app_root_mode_cannot_mutate_during_archive_inspection(self) -> None:
        mode = stat.S_IMODE(self.app.stat().st_mode)
        def mutate(command, kwargs):
            self.process_hook = None
            self.app.chmod(0o777)
        self.process_hook = mutate
        try:
            with self.assertRaises(ValueError):
                self.verify_archive()
        finally:
            self.app.chmod(mode)

    def test_entitlements_and_profile_bindings_rejected(self) -> None:
        for key, value in (("application-identifier", TEAM + ".other"),
                           ("com.apple.developer.team-identifier", "ZZZZZ12345"),
                           ("get-task-allow", True), ("get-task-allow", 0),
                           ("beta-reports-active", False), ("beta-reports-active", 1)):
            self.entitlement_overrides = {key: value}
            with self.subTest(entitlement=key, value=value), self.assertRaises(ValueError):
                self.verify_archive()
        self.entitlement_overrides = {}
        for key, value in (("state", "metadata_valid_signing_blocked"), ("profile_eligible_for_archive", False),
                           ("cms_signature_trust", "UNVERIFIED"), ("team_id", "ZZZZZ12345"),
                           ("matched_certificate_sha256", "0" * 64), ("mobileprovision_sha256", "0" * 64)):
            self.profile_overrides = {key: value}
            with self.subTest(profile=key), self.assertRaises(ValueError):
                self.verify_archive()

    def test_profile_and_certificate_hash_mismatches_rejected(self) -> None:
        for options in ({"profile_sha256": "0" * 64}, {"certificate_sha1": "0" * 40},
                        {"certificate_sha256": "0" * 64}, {"cms_helper_sha256": "0" * 64}):
            with self.subTest(options=options), self.assertRaises(ValueError):
                self.verify_archive(**options)
        with self.changed(self.app / "embedded.mobileprovision", b"different profile"), self.assertRaises(ValueError):
            self.verify_archive()

    def test_architecture_native_bridges_and_signing_identity_are_required(self) -> None:
        outputs = (("lipo", b"x86_64\n", b""), ("lipo", b"arm64 x86_64\n", b""),
                   ("otool", b"StoreKit.framework/StoreKit\n", b""),
                   ("otool", b"/System/Library/Frameworks/StoreKit.framework/StoreKitBogus\n/System/Library/Frameworks/AuthenticationServices.framework/AuthenticationServices\n", b""),
                   ("strings", b"WaddleStoreKit\nWWStoreKitBridgeExtra\nWWAuthenticationBridge\n", b""),
                   ("python", b"not JSON", b""))
        for tool, output, error in outputs:
            self.command_output_overrides = {tool: (output, error)}
            with self.subTest(tool=tool, output=output), self.assertRaises(ValueError):
                self.verify_archive()
        self.command_output_overrides = {}
        original = self.codesign_display
        for display in (original.replace(TEAM, "ZZZZZ12345"), original.replace(BUNDLE, "com.example.other"),
                        original.replace("Apple Distribution", "Apple Development")):
            self.codesign_display = display
            with self.subTest(display=display), self.assertRaises(ValueError):
                self.verify_archive()

    def free_mvp_candidate(self) -> None:
        self.receipt["launch_edition"] = "free_offline_mvp"
        preset = self.project / "export_presets.cfg"
        preset.write_text(preset.read_text() + "plugins/WaddleStoreKit=false\n")
        self.receipt["prepared_files"]["export_presets.cfg"] = digest(preset)
        self.save_candidate()

    def test_native_account_capability_survives_archive_to_ipa_receipts(self) -> None:
        self.receipt.update({"launch_edition": "free_offline_mvp", "native_accounts_enabled": True,
                             "native_clerk_issuer": "https://clerk.waddlewars.io"})
        preset = self.project / "export_presets.cfg"
        preset.write_text(preset.read_text() + '\n'.join([
            'custom_features="native_accounts"', 'plugins/WaddleStoreKit=true',
            'storyboard/custom_image@2x="res://assets/art/ui/menu/launch_screen_portrait_v1.png"',
            'storyboard/custom_image@3x="res://assets/art/ui/menu/launch_screen_portrait_v1.png"',
            'storyboard/image_scale_mode=3', '']))
        settings = self.project / "project.godot"
        settings.write_text(settings.read_text() + '\n[account]\ndeletion_enabled=true\nauth_api_base="https://waddlewars.io"\n')
        self.receipt["prepared_files"].update({"export_presets.cfg": digest(preset), "project.godot": digest(settings)})
        self.save_candidate()
        archive = self.verify_archive()
        self.assertEqual(archive["platform"], "ios")
        self.assertIs(archive["native_accounts_enabled"], True)
        self.assertIs(archive["deferred_native_sdks_absent"], False)
        self.assertIs(archive["storekit_auth_frameworks_linked"], True)
        signed = write(self.root / "native-signed-archive.json", json.dumps(archive, sort_keys=True).encode())
        ipa = self.write_ipa()
        result = self.verify_ipa(ipa, signed)
        self.assertEqual(result["platform"], "ios")
        self.assertIs(result["native_accounts_enabled"], True)
        self.assertEqual(result["native_clerk_issuer"], "https://clerk.waddlewars.io")
        self.assertIs(result["storekit_auth_frameworks_linked"], True)
        self.assertIs(result["store_ready"], False)
        for platform in [None, "android"]:
            changed = dict(archive)
            if platform is None: changed.pop("platform")
            else: changed["platform"] = platform
            bad_receipt = write(self.root / "native-bad-archive.json", json.dumps(changed, sort_keys=True).encode())
            with self.subTest(platform=platform), self.assertRaises(ValueError):
                self.verify_ipa(ipa, bad_receipt)

    def test_free_mvp_requires_actual_native_sdk_absence(self) -> None:
        self.free_mvp_candidate()
        self.command_output_overrides = {"otool": (b"/System/Library/Frameworks/UIKit.framework/UIKit\n", b""),
                                         "strings": (b"Godot\n", b"")}
        result = self.verify_archive()
        self.assertEqual(result["launch_edition"], "free_offline_mvp")
        self.assertIs(result["deferred_native_sdks_absent"], True)
        self.assertIs(result["storekit_auth_frameworks_linked"], False)
        self.assertIs(result["store_ready"], False)
        self.verify_ipa(self.write_ipa(), self.signed_receipt())
        for tool, output in (
                ("otool", b"@rpath/StoreKit.framework/StoreKit\n"),
                ("otool", b"/System/Library/Frameworks/AuthenticationServices.framework/AuthenticationServices\n"),
                ("strings", b"_OBJC_CLASS_$_WWStoreKitBridge\n"),
                ("strings", b"_OBJC_CLASS_$_WWAuthenticationBridge\n")):
            self.command_output_overrides[tool] = (output, b"")
            with self.subTest(tool=tool, output=output), self.assertRaises(ValueError):
                self.verify_archive()
            self.command_output_overrides = {"otool": (b"UIKit\n", b""), "strings": (b"Godot\n", b"")}

    def test_free_mvp_requires_disabled_plugin_in_frozen_preset(self) -> None:
        self.receipt["launch_edition"] = "free_offline_mvp"
        self.save_candidate()
        with self.assertRaises(ValueError):
            self.verify_archive()

    def test_reviewed_template_requires_manifest_and_actual_capacity_absence(self) -> None:
        self.free_mvp_candidate()
        template = self.candidate / "inputs/ios-template.zip"
        template.parent.mkdir(parents=True, exist_ok=True)
        zip_entries(template, [("synthetic", b"fixture, not an engine")])
        pin = digest(template)
        self.receipt["ios_custom_template"] = {"path": "inputs/ios-template.zip", "sha256": pin}
        self.receipt["ios_engine_capability_policy"] = {"policy": "disk-capacity-disabled-template-v1", "template_sha256": pin}
        preset = self.project / "export_presets.cfg"
        preset.write_text(preset.read_text() + 'custom_template/release="' + str(template) + '"\nprivacy/disk_space_access_reasons=0\n')
        self.receipt["prepared_files"]["export_presets.cfg"] = digest(preset)
        manifest = {"NSPrivacyTracking": False, "NSPrivacyAccessedAPITypes": [
            {"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryFileTimestamp", "NSPrivacyAccessedAPITypeReasons": ["C617.1"]},
            {"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategorySystemBootTime", "NSPrivacyAccessedAPITypeReasons": ["35F9.1"]},
        ]}
        exported = write(self.project / "build/ios/waddlewars/PrivacyInfo.xcprivacy", plistlib.dumps(manifest))
        self.receipt["artifacts"][str(exported.relative_to(self.candidate))] = digest(exported)
        write(self.app / "PrivacyInfo.xcprivacy", exported.read_bytes())
        self.save_candidate()
        self.command_output_overrides = {"otool": (b"UIKit\n", b""), "strings": (b"Godot\n", b"")}
        result = self.verify_archive()
        self.assertIs(result["reviewed_capacity_imports_absent"], True)
        self.assertEqual(result["ios_engine_capability_policy"], self.receipt["ios_engine_capability_policy"])
        self.verify_ipa(self.write_ipa(), self.signed_receipt())
        for output in (b"_statvfs\n", b"_statfs$INODE64\n", b"_fgetattrlist\n"):
            self.command_output_overrides["nm"] = (output, b"")
            with self.subTest(output=output), self.assertRaises(ValueError):
                self.verify_archive()
        self.command_output_overrides["nm"] = (b"_stat\n", b"")
        self.command_output_overrides["strings"] = (b"NSURLVolumeAvailableCapacityForImportantUsageKey\n", b"")
        with self.assertRaises(ValueError):
            self.verify_archive()
        self.command_output_overrides["strings"] = (b"Godot\n", b"")
        manifest["NSPrivacyAccessedAPITypes"].append({"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryDiskSpace", "NSPrivacyAccessedAPITypeReasons": ["E174.1"]})
        exported.write_bytes(plistlib.dumps(manifest))
        (self.app / "PrivacyInfo.xcprivacy").write_bytes(exported.read_bytes())
        self.receipt["artifacts"][str(exported.relative_to(self.candidate))] = digest(exported)
        self.save_candidate()
        with self.assertRaises(ValueError):
            self.verify_archive()

    def test_ipa_cannot_change_frozen_launch_edition(self) -> None:
        self.free_mvp_candidate()
        self.command_output_overrides = {"otool": (b"UIKit\n", b""), "strings": (b"Godot\n", b"")}
        receipt = self.signed_receipt()
        source = json.loads(receipt.read_text())
        source["launch_edition"] = "commerce"
        receipt.write_text(json.dumps(source))
        with self.assertRaises(ValueError):
            self.verify_ipa(self.write_ipa(), receipt)

    def test_profile_cli_duplicate_json_keys_rejected(self) -> None:
        self.duplicate_profile_keys = True
        with self.assertRaises(ValueError):
            self.verify_archive()

    def test_failure_and_timeout_retains_evidence_without_success(self) -> None:
        for failure in (subprocess.TimeoutExpired(["synthetic-tool"], 60), OSError("synthetic tool failure")):
            def fail(command, kwargs, failure=failure):
                raise failure
            self.process_hook = fail
            evidence = self.evidence()
            with self.subTest(failure=type(failure).__name__), self.assertRaises(ValueError):
                self.verify_archive(evidence)
            self.assertTrue((evidence / "failure.json").is_file())
        self.process_hook = None
        with patch.object(verifier.subprocess, "run", return_value=subprocess.CompletedProcess(["synthetic"], 1)):
            with self.assertRaises(ValueError):
                self.verify_archive()

    def test_existing_evidence_never_overwritten(self) -> None:
        evidence = self.evidence()
        evidence.mkdir()
        marker = write(evidence / "reviewed", b"preserve existing evidence")
        with self.assertRaises(ValueError):
            self.verify_archive(evidence)
        self.assertEqual(marker.read_bytes(), b"preserve existing evidence")
        self.assertEqual(list(evidence.iterdir()), [marker])

    def test_noncanonical_input_cannot_bypass_evidence_containment(self) -> None:
        alias = self.root / "candidate-alias"
        alias.symlink_to(self.candidate, target_is_directory=True)
        candidates = (Path(os.path.relpath(self.candidate)), self.candidate / ".." / "candidate", alias)
        for candidate in candidates:
            evidence = self.candidate / "forbidden-evidence"
            with self.subTest(candidate=str(candidate)), self.assertRaises(ValueError):
                verifier.verify_archive(candidate, self.archive, evidence, **self.archive_options())
            self.assertFalse(evidence.exists())

    def test_input_and_inspection_tool_mutation_during_run_rejected(self) -> None:
        for path in (self.project / "scripts/commerce/commerce_client.gd", self.app / "assets/synthetic-resource",
                     self.archive / "Info.plist", self.candidate / "receipt.json", self.installed_profile,
                     self.helper, self.tools["codesign"]):
            original = path.read_bytes()
            def mutate(command, kwargs, path=path):
                self.process_hook = None
                path.write_bytes(path.read_bytes() + b"mutation during inspection")
            self.process_hook = mutate
            try:
                with self.subTest(input=path.name), self.assertRaises(ValueError):
                    self.verify_archive()
            finally:
                path.write_bytes(original)
        self.process_hook = None


class IpaBoundaryTests(ArtifactFixture):
    def test_export_may_only_tighten_embedded_profile_644_to_600(self) -> None:
        receipt = self.signed_receipt()
        entries = self.ipa_entries()
        for info, raw in entries:
            if info.filename.endswith("/embedded.mobileprovision"):
                info.external_attr = 0o100600 << 16
        result = self.verify_ipa(self.write_ipa(entries), receipt)
        self.assertTrue(result["ipa_verified"])
        self.assertEqual(result["app_inventory"]["embedded.mobileprovision"]["mode"], 0o600)

    def test_profile_mode_tightening_never_permits_changed_bytes_or_other_modes(self) -> None:
        receipt = self.signed_receipt()
        for mode, change in ((0o600, True), (0o400, False), (0o640, False),
                             (0o660, False), (0o755, False)):
            entries = []
            for info, raw in self.ipa_entries():
                if info.filename.endswith("/embedded.mobileprovision"):
                    info.external_attr = (stat.S_IFREG | mode) << 16
                    if change:
                        raw += b"changed"
                entries.append((info, raw))
            with self.subTest(mode=mode, bytes_changed=change), self.assertRaises(ValueError):
                self.verify_ipa(self.write_ipa(entries), receipt)

    def test_profile_tightening_cannot_expand_other_file_modes_or_reverse(self) -> None:
        receipt = self.signed_receipt()
        for suffix in ("/waddlewars.pck", "/assets/synthetic-resource", "/_CodeSignature/CodeResources"):
            entries = self.ipa_entries()
            for info, raw in entries:
                if info.filename.endswith(suffix):
                    info.external_attr = 0o100600 << 16
            with self.subTest(suffix=suffix), self.assertRaises(ValueError):
                self.verify_ipa(self.write_ipa(entries), receipt)
        (self.app / "embedded.mobileprovision").chmod(0o600)
        receipt = self.signed_receipt()
        entries = self.ipa_entries()
        for info, raw in entries:
            if info.filename.endswith("/embedded.mobileprovision"):
                info.external_attr = 0o100644 << 16
        with self.assertRaises(ValueError):
            self.verify_ipa(self.write_ipa(entries), receipt)

    def test_valid_ipa_preserves_archive_binding_without_store_authorization(self) -> None:
        receipt = self.signed_receipt()
        result = self.verify_ipa(self.write_ipa(), receipt)
        self.assertEqual(result["state"], "ipa_verified")
        self.assertTrue(result["ipa_verified"])
        for key in ("store_ready", "device_acceptance_passed", "store_upload_performed"):
            self.assertIs(result[key], False)

    def test_only_code_signature_payload_may_change_on_export(self) -> None:
        receipt = self.signed_receipt()
        entries = self.ipa_entries()
        replaced = []
        for info, raw in entries:
            if info.filename.endswith("/waddlewars"):
                raw = macho(b"different synthetic IPA signature, different length")
            elif info.filename.endswith("/_CodeSignature/CodeResources"):
                raw = b"different synthetic IPA resource seal"
            replaced.append((info, raw))
        self.assertEqual(self.verify_ipa(self.write_ipa(replaced), receipt)["state"], "ipa_verified")

    def test_non_signature_app_bytes_and_modes_cannot_change(self) -> None:
        receipt = self.signed_receipt()
        for suffix in ("/assets/synthetic-resource", "/waddlewars.pck", "/Info.plist", "/embedded.mobileprovision", "/waddlewars"):
            entries = []
            for info, raw in self.ipa_entries():
                if info.filename.endswith(suffix):
                    raw = macho(payload=b"different-native-code") if suffix == "/waddlewars" else raw + b"changed"
                entries.append((info, raw))
            with self.subTest(suffix=suffix), self.assertRaises(ValueError):
                self.verify_ipa(self.write_ipa(entries), receipt)
        entries = self.ipa_entries()
        for info, raw in entries:
            if info.filename.endswith("/assets/synthetic-resource"):
                info.external_attr = 0o100755 << 16
        with self.assertRaises(ValueError):
            self.verify_ipa(self.write_ipa(entries), receipt)

    def test_ipa_resource_inventory_cannot_add_or_remove_files(self) -> None:
        receipt = self.signed_receipt()
        missing = [(info, raw) for info, raw in self.ipa_entries()
                   if not info.filename.endswith("/assets/synthetic-resource")]
        extra = [*self.ipa_entries(), ("Payload/waddlewars.app/assets/unreviewed", b"extra resource")]
        for label, entries in (("removed", missing), ("added", extra)):
            with self.subTest(change=label), self.assertRaises(ValueError):
                self.verify_ipa(self.write_ipa(entries), receipt)

    def test_ipa_and_archive_receipt_hash_pins_required(self) -> None:
        receipt = self.signed_receipt()
        ipa = self.write_ipa()
        for options in ({"ipa_sha256": "0" * 64}, {"archive_receipt_sha256": "0" * 64},
                        {"cms_helper_sha256": "0" * 64}):
            with self.subTest(options=options), self.assertRaises(ValueError):
                self.verify_ipa(ipa, receipt, **options)
        with self.changed(self.app / "assets/synthetic-resource", b"archive changed after verification"), self.assertRaises(ValueError):
            self.verify_ipa(ipa, receipt)

    def test_ipa_inputs_and_tools_cannot_mutate_during_inspection(self) -> None:
        receipt = self.signed_receipt()
        ipa = self.write_ipa()
        for path in (ipa, receipt, self.archive / "Info.plist", self.helper, self.tools["strings"]):
            original = path.read_bytes()
            def mutate(command, kwargs, path=path):
                self.process_hook = None
                path.write_bytes(path.read_bytes() + b"changed during IPA inspection")
            self.process_hook = mutate
            try:
                with self.subTest(input=path.name), self.assertRaises(ValueError):
                    self.verify_ipa(ipa, receipt)
            finally:
                path.write_bytes(original)
        self.process_hook = None

    def test_ipa_evidence_inside_candidate_is_rejected_before_any_write(self) -> None:
        receipt = self.signed_receipt()
        evidence = self.candidate / "forbidden-evidence"
        with self.assertRaises(ValueError):
            self.verify_ipa(self.write_ipa(), receipt, evidence)
        self.assertFalse(evidence.exists())

    def test_app_root_modes_cannot_mutate_during_ipa_inspection(self) -> None:
        receipt = self.signed_receipt()
        ipa = self.write_ipa()
        mode = stat.S_IMODE(self.app.stat().st_mode)
        for target in ("archive", "unpacked"):
            def mutate(command, kwargs, target=target):
                self.process_hook = None
                app = self.app if target == "archive" else Path(command[-1]).parent
                # The first inspection command is lipo on the unpacked executable.
                app.chmod(0o777)
            self.process_hook = mutate
            try:
                with self.subTest(target=target), self.assertRaises(ValueError):
                    self.verify_ipa(ipa, receipt)
            finally:
                self.app.chmod(mode)
        self.process_hook = None


class ToolResolutionTests(unittest.TestCase):
    def setUp(self) -> None:
        folder = tempfile.TemporaryDirectory(prefix="ww-ios-artifact-fixture-tools-")
        self.addCleanup(folder.cleanup)
        self.root = Path(folder.name).resolve()
        self.toolchain = self.root / "toolchain/usr/bin"
        self.toolchain.mkdir(parents=True)
        self.patch = patch.object(verifier, "XCODE_TOOLCHAIN_BIN", self.toolchain)
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def test_concrete_tools_resolve_without_system_dispatchers(self) -> None:
        for name in ("lipo", "otool", "strings", "nm"):
            path = write(self.toolchain / name, b"synthetic inspection binary", 0o755)
            self.assertEqual(verifier._xcode_inspection_tool(name), path)

    def test_exact_in_toolchain_otool_alias_resolves_to_regular_binary(self) -> None:
        path = write(self.toolchain / "llvm-otool", b"synthetic inspection binary", 0o755)
        (self.toolchain / "otool").symlink_to("llvm-otool")
        self.assertEqual(verifier._xcode_inspection_tool("otool"), path)

    def test_tool_symlink_escape_is_rejected(self) -> None:
        path = write(self.root / "outside", b"synthetic inspection binary", 0o755)
        (self.toolchain / "otool").symlink_to(path)
        with self.assertRaises(ValueError):
            verifier._xcode_inspection_tool("otool")

    def test_hardlinked_tool_remains_rejected(self) -> None:
        path = write(self.toolchain / "lipo", b"synthetic inspection binary", 0o755)
        os.link(path, self.toolchain / "alias")
        with self.assertRaises(ValueError):
            verifier._xcode_inspection_tool("lipo")

    def test_nonexecutable_tool_is_rejected(self) -> None:
        write(self.toolchain / "strings", b"synthetic inspection binary", 0o644)
        with self.assertRaises(ValueError):
            verifier._xcode_inspection_tool("strings")

    def test_unknown_or_missing_tool_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            verifier._xcode_inspection_tool("../other")
        with self.assertRaises(OSError):
            verifier._xcode_inspection_tool("lipo")


class ZipAndMachOBoundaryTests(ArtifactFixture):
    def test_safe_extraction_preserves_file_and_directory_modes(self) -> None:
        app, count = verifier.extract_safe(self.write_ipa(), self.root / "extracted")
        self.assertGreater(count, 0)
        self.assertEqual(stat.S_IMODE(app.stat().st_mode), 0o755)
        self.assertEqual(stat.S_IMODE((app / "waddlewars").stat().st_mode), 0o755)
        self.assertEqual(stat.S_IMODE((app / "Info.plist").stat().st_mode), 0o644)

    def test_unsafe_zip_paths_duplicates_and_case_aliases_rejected(self) -> None:
        for name in ("../outside", "/outside", "Payload/../outside", "Payload//extra", "./Payload/extra",
                     "Payload\\extra", "Payload/waddlewars.app/Info.plist", "Payload/waddlewars.app/info.plist"):
            with self.subTest(name=name):
                ipa = self.write_ipa([*self.ipa_entries(), (name, b"unsafe")])
                with self.assertRaises(ValueError):
                    verifier.extract_safe(ipa, self.root / ("extract-bad-%d" % self.sequence))
                self.sequence += 1
        self.assertFalse((self.root / "outside").exists())

    def test_every_entry_type_and_mode_is_validated(self) -> None:
        for name, mode, raw in (("Payload/waddlewars.app/unsafe", 0o120777, b"target"),
                                ("Payload/waddlewars.app/unsafe", 0o020600, b"device"),
                                ("Payload/waddlewars.app/unsafe", 0o010600, b"fifo"),
                                ("Payload/waddlewars.app/unsafe", 0o040755, b""),
                                ("Payload/waddlewars.app/unsafe/", 0o100644, b""),
                                ("Payload/waddlewars.app/unsafe/", 0o040755, b"nonempty directory"),
                                ("Payload/waddlewars.app/unsafe", 0o104644, b"setuid"),
                                ("Payload/waddlewars.app/unsafe", 0o102644, b"setgid")):
            entry = zipfile.ZipInfo(name)
            entry.create_system = 3
            entry.external_attr = mode << 16
            ipa = self.write_ipa([*self.ipa_entries(), (entry, raw)])
            with self.subTest(name=name, mode=oct(mode)), self.assertRaises(ValueError):
                verifier.extract_safe(ipa, self.root / ("extract-type-%d" % self.sequence))
            self.sequence += 1

    def test_encrypted_zip_entries_rejected_before_extraction(self) -> None:
        ipa = self.write_ipa()
        raw = bytearray(ipa.read_bytes())
        local = raw.index(b"PK\x03\x04")
        central = raw.index(b"PK\x01\x02")
        struct.pack_into("<H", raw, local + 6, struct.unpack_from("<H", raw, local + 6)[0] | 1)
        struct.pack_into("<H", raw, central + 8, struct.unpack_from("<H", raw, central + 8)[0] | 1)
        ipa.write_bytes(raw)
        with self.assertRaises(ValueError):
            verifier.extract_safe(ipa, self.root / "encrypted-extract")

    def test_inventory_rejects_symlinks_and_tracks_resources_and_modes(self) -> None:
        before = verifier.app_inventory(self.app)
        resource = self.app / "assets/synthetic-resource"
        with self.changed(resource, b"modified resource"):
            self.assertNotEqual(verifier.app_inventory(self.app), before)
        resource.chmod(0o755)
        self.assertNotEqual(verifier.app_inventory(self.app), before)
        resource.chmod(0o644)
        (self.app / "alias").symlink_to(resource)
        with self.assertRaises(ValueError):
            verifier.app_inventory(self.app)

    def test_macho_signature_tail_only_is_normalized(self) -> None:
        binary = self.app / "waddlewars"
        before = verifier.code_without_signature(binary)
        with self.changed(binary, macho(b"changed signature bytes and length")):
            self.assertEqual(verifier.code_without_signature(binary), before)
        with self.changed(binary, macho(payload=b"changed immutable native code")):
            self.assertNotEqual(verifier.code_without_signature(binary), before)

    def test_malformed_macho_headers_commands_and_signature_ranges_rejected(self) -> None:
        good = macho()
        malformed = [b"not Mach-O", good[:31], good + b"uncovered tail"]
        for offset, value in ((4, 7), (16, 2), (20, 0), (32, 0), (36, 8), (40, 0), (44, 0), (44, 0xFFFFFFFF)):
            raw = bytearray(good)
            struct.pack_into("<I", raw, offset, value)
            malformed.append(bytes(raw))
        for index, raw in enumerate(malformed):
            with self.subTest(case=index), self.changed(self.app / "waddlewars", raw), self.assertRaises(ValueError):
                verifier.code_without_signature(self.app / "waddlewars")


class GeneratedUidBoundaryTests(ArtifactFixture):
    UID_PATH = "scripts/commerce/commerce_client.gd.uid"

    def declare(self, *, supplemental: bool) -> tuple[Path, dict, Path]:
        uid = write(self.project / self.UID_PATH, b"uid://synthetic123\n")
        metadata = {"schema_version": 1, "state": "godot_import_metadata_frozen",
                    "source_sha256": self.receipt["source_sha256"], "generated_uid_files": {self.UID_PATH: digest(uid)}}
        if supplemental:
            metadata["candidate_receipt_sha256"] = digest(self.candidate / "receipt.json")
        path = self.store_metadata(metadata, supplemental=supplemental)
        return uid, metadata, path

    def store_metadata(self, metadata: dict, *, supplemental: bool) -> Path:
        if supplemental:
            return write(self.candidate / "import-metadata.json", json.dumps(metadata, sort_keys=True).encode())
        self.receipt["import_metadata"] = metadata
        self.save_candidate()
        return self.candidate / "receipt.json"

    def test_canonical_uid_metadata_binds_archive_and_ipa(self) -> None:
        _, metadata, _ = self.declare(supplemental=False)
        result = self.verify_archive()
        self.assertEqual(result["generated_uid_files"], metadata["generated_uid_files"])
        self.assertIsNone(result["supplemental_import_metadata_sha256"])
        receipt = write(self.root / "signed-archive.json", json.dumps(result, sort_keys=True).encode())
        ipa = self.verify_ipa(self.write_ipa(), receipt)
        self.assertEqual(ipa["generated_uid_files"], metadata["generated_uid_files"])
        self.assertIsNone(ipa["supplemental_import_metadata_sha256"])

    def test_supplemental_uid_metadata_preserves_original_receipt(self) -> None:
        original = (self.candidate / "receipt.json").read_bytes()
        _, metadata, path = self.declare(supplemental=True)
        result = self.verify_archive()
        self.assertEqual(result["generated_uid_files"], metadata["generated_uid_files"])
        self.assertEqual(result["supplemental_import_metadata_sha256"], digest(path))
        self.assertEqual((self.candidate / "receipt.json").read_bytes(), original)
        receipt = write(self.root / "signed-archive.json", json.dumps(result, sort_keys=True).encode())
        ipa = self.verify_ipa(self.write_ipa(), receipt)
        self.assertEqual(ipa["generated_uid_files"], metadata["generated_uid_files"])
        self.assertEqual(ipa["supplemental_import_metadata_sha256"], digest(path))
        self.assertEqual((self.candidate / "receipt.json").read_bytes(), original)

    def test_uid_content_must_be_bounded_ascii_canonical_even_with_matching_hash(self) -> None:
        uid, metadata, _ = self.declare(supplemental=True)
        invalid = (b"", b"uid://UPPERCASE\n", b"uid://abc\r\n", b"uid://abc\n\n", b"uid://abc extra\n",
                   b"uid://" + b"a" * 123, "uid://é\n".encode(), b"not-a-UID")
        for raw in invalid:
            uid.write_bytes(raw)
            self.store_metadata({**metadata, "generated_uid_files": {self.UID_PATH: digest(uid)}}, supplemental=True)
            with self.subTest(content=raw), self.assertRaises(ValueError):
                self.verify_archive()

    def test_uid_inventory_requires_new_adjacent_prepared_script_and_exact_hash(self) -> None:
        _, metadata, _ = self.declare(supplemental=True)
        inventories = ({self.UID_PATH: "0" * 64}, {self.UID_PATH: "short"},
                       {"scripts/missing.gd.uid": metadata["generated_uid_files"][self.UID_PATH]},
                       {"export_presets.cfg.uid": metadata["generated_uid_files"][self.UID_PATH]},
                       {"../outside.gd.uid": metadata["generated_uid_files"][self.UID_PATH]},
                       {"scripts//commerce/commerce_client.gd.uid": metadata["generated_uid_files"][self.UID_PATH]},
                       {"build/generated.gd.uid": metadata["generated_uid_files"][self.UID_PATH]}, [])
        for inventory in inventories:
            self.store_metadata({**metadata, "generated_uid_files": inventory}, supplemental=True)
            with self.subTest(inventory=inventory), self.assertRaises(ValueError):
                self.verify_archive()

    def test_uid_metadata_rejects_wrong_binding_or_unreviewed_fields(self) -> None:
        _, metadata, _ = self.declare(supplemental=True)
        variants = ({**metadata, "schema_version": 2}, {**metadata, "schema_version": True},
                    {**metadata, "state": "unverified"}, {**metadata, "source_sha256": "0" * 64},
                    {**metadata, "candidate_receipt_sha256": "0" * 64},
                    {**metadata, "unreviewed_files": {}}, {key: value for key, value in metadata.items() if key != "generated_uid_files"})
        for variant in variants:
            self.store_metadata(variant, supplemental=True)
            with self.subTest(metadata=variant), self.assertRaises(ValueError):
                self.verify_archive()

    def test_canonical_metadata_rejects_supplemental_only_and_arbitrary_fields(self) -> None:
        _, metadata, _ = self.declare(supplemental=False)
        for extra in ({"candidate_receipt_sha256": digest(self.candidate / "receipt.json")}, {"unreviewed": True}):
            self.store_metadata({**metadata, **extra}, supplemental=False)
            with self.subTest(extra=extra), self.assertRaises(ValueError):
                self.verify_archive()

    def test_uid_metadata_forms_are_mutually_exclusive(self) -> None:
        _, metadata, _ = self.declare(supplemental=False)
        self.store_metadata({**metadata, "candidate_receipt_sha256": digest(self.candidate / "receipt.json")}, supplemental=True)
        with self.assertRaises(ValueError):
            self.verify_archive()

    def test_prepared_uid_cannot_be_redeclared_as_generated(self) -> None:
        uid, _, _ = self.declare(supplemental=False)
        self.receipt["prepared_files"][self.UID_PATH] = digest(uid)
        self.save_candidate()
        with self.assertRaises(ValueError):
            self.verify_archive()

    def test_supplemental_metadata_mutation_after_archive_rejected(self) -> None:
        _, _, path = self.declare(supplemental=True)
        receipt = self.signed_receipt()
        path.write_bytes(path.read_bytes() + b" \n")
        with self.assertRaises(ValueError):
            self.verify_ipa(self.write_ipa(), receipt)

    def test_uid_metadata_or_sidecar_mutation_during_archive_rejected(self) -> None:
        uid, _, metadata_path = self.declare(supplemental=True)
        for path in (uid, metadata_path):
            original = path.read_bytes()
            def mutate(command, kwargs, path=path):
                self.process_hook = None
                path.write_bytes(path.read_bytes() + b" \n")
            self.process_hook = mutate
            try:
                with self.subTest(path=path.name), self.assertRaises(ValueError):
                    self.verify_archive()
            finally:
                path.write_bytes(original)
        self.process_hook = None


class NativeAccountConfigurationTests(unittest.TestCase):
    def test_account_candidate_pins_runtime_plugin_origin_deletion_and_brand(self):
        with tempfile.TemporaryDirectory() as folder:
            project = Path(folder)
            preset = '\n'.join(['custom_features="native_accounts"', 'plugins/WaddleStoreKit=true',
                'storyboard/custom_image@2x="res://assets/art/ui/menu/launch_screen_portrait_v1.png"',
                'storyboard/custom_image@3x="res://assets/art/ui/menu/launch_screen_portrait_v1.png"',
                'storyboard/image_scale_mode=3'])
            settings = '[account]\ndeletion_enabled=true\nauth_api_base="https://waddlewars.io"\n'
            receipt = {'platform': 'ios', 'native_accounts_enabled': True}
            (project/'export_presets.cfg').write_text(preset)
            (project/'project.godot').write_text(settings)
            verifier._native_account_configuration(receipt, project)
            for changed in [preset.replace('native_accounts', ''), preset.replace('plugins/WaddleStoreKit=true', 'plugins/WaddleStoreKit=false'), preset.replace('launch_screen_portrait_v1', 'godot')]:
                (project/'export_presets.cfg').write_text(changed)
                with self.assertRaises(ValueError): verifier._native_account_configuration(receipt, project)
            (project/'export_presets.cfg').write_text(preset)
            for changed in [settings.replace('true', 'false'), settings.replace('waddlewars.io', 'staging.invalid')]:
                (project/'project.godot').write_text(changed)
                with self.assertRaises(ValueError): verifier._native_account_configuration(receipt, project)


if __name__ == "__main__":
    unittest.main()
