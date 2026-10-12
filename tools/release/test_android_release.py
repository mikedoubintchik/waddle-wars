#!/usr/bin/env python3
"""Pure host release-verifier tests; external tools and signatures are mocked.

Synthetic ZIP/DER bytes are deliberately not genuine signed builds/certificates.
These tests establish rejection/receipt contracts, never real AAB acceptance.
"""
from __future__ import annotations

import base64
from contextlib import redirect_stdout
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import warnings
import zipfile

import verify_android_release as release

PACKAGE = "com.blubberandbyte.waddlewars"
PACK = "assetPackInstallTime"
LIBRARY = "base/lib/arm64-v8a/libgodot_android.so"


def der(tag: int, content: bytes) -> bytes:
    length = len(content)
    encoded = bytes([length]) if length < 128 else bytes([0x82]) + length.to_bytes(2, "big")
    return bytes([tag]) + encoded + content


def certificate(name: str = "Waddle Upload", *, versioned: bool = True) -> bytes:
    attribute = der(0x30, der(0x06, b"\x55\x04\x03") + der(0x0C, name.encode()))
    subject = der(0x30, der(0x31, attribute))
    tbs = ((der(0xA0, der(0x02, b"\x02")) if versioned else b"")
           + der(0x02, b"\x01") + der(0x30, b"") + der(0x30, b"")
           + der(0x30, b"") + subject + der(0x30, b""))
    return der(0x30, der(0x30, tbs) + der(0x30, b"") + der(0x03, b"\x00"))


def signer_report(certs: list[bytes]) -> str:
    blocks = []
    for index, cert in enumerate(certs, 1):
        blocks.append(f"Certificate #{index}:\n-----BEGIN CERTIFICATE-----\n"
                      + base64.b64encode(cert).decode() + "\n-----END CERTIFICATE-----\n")
    return "Signer #1:\n\n" + "\n".join(blocks)


def base_manifest(**attributes: str) -> str:
    app_attributes = " ".join(f'android:{key}="{value}"' for key, value in attributes.items())
    return f'''<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="{PACKAGE}"
      android:versionCode="2" android:versionName="1.0.0">
      <uses-sdk android:minSdkVersion="24" android:targetSdkVersion="36"/>
      <uses-permission android:name="com.android.vending.BILLING"/>
      <application {app_attributes}>
        <meta-data android:name="{release.PROVIDER_KEY}" android:value="{release.PROVIDER_CLASS}"/>
      </application>
    </manifest>'''


def free_manifest(**attributes: str) -> str:
    return base_manifest(**attributes).replace(
        '<uses-permission android:name="com.android.vending.BILLING"/>', "").replace(
        f'<meta-data android:name="{release.PROVIDER_KEY}" android:value="{release.PROVIDER_CLASS}"/>', "")


def pack_manifest(delivery: str = "install-time", kind: str = "asset-pack") -> str:
    return f'''<manifest xmlns:android="http://schemas.android.com/apk/res/android"
      xmlns:dist="http://schemas.android.com/apk/distribution" package="{PACKAGE}" split="{PACK}"
      android:versionCode="2">
      <dist:module dist:type="{kind}"><dist:delivery><dist:{delivery}/></dist:delivery></dist:module>
    </manifest>'''


class AndroidReleaseTests(unittest.TestCase):
    def setUp(self) -> None:
        self.folder = tempfile.TemporaryDirectory(prefix="waddle-release-fixture-")
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name).resolve()
        self.aab = self.root / "waddle.aab"
        self.bundletool = self.root / "bundletool.jar"
        self.bundletool.write_bytes(b"synthetic-public-tool")
        self.jdk = self.root / "jdk"
        (self.jdk / "bin").mkdir(parents=True)
        for name in ("java", "jarsigner", "keytool"):
            tool = self.jdk / "bin" / name
            tool.write_bytes(b"synthetic-executable")
            tool.chmod(0o700)
        self.entries = {
            "META-INF/MANIFEST.MF": b"Manifest-Version: 1.0\r\n\r\n",
            "META-INF/UPLOAD.SF": b"synthetic-signature-manifest",
            "META-INF/UPLOAD.RSA": b"synthetic-signature-block",
            "BundleConfig.pb": b"synthetic-config",
            "base/manifest/AndroidManifest.xml": b"synthetic-protobuf-manifest",
            "base/dex/classes.dex": b"synthetic-dex",
            LIBRARY: b"synthetic-library",
            f"{PACK}/manifest/AndroidManifest.xml": b"synthetic-protobuf-pack",
            # Official module metadata layout, not a real protobuf/build fixture.
            f"{PACK}/assets.pb": b"synthetic assets targeting protobuf",
            f"{PACK}/assets/project.binary": b"synthetic-game-project",
            f"{PACK}/assets/assets.sparsepck": b"__CRC_SAMPLE__",
            "base/assets/_cl_": b"--path .",
        }
        self.write_aab()
        self.cert = certificate()
        self.cert_output = signer_report([self.cert])
        self.jar_output = self.jar_report()
        self.manifests = {"base": base_manifest(), PACK: pack_manifest()}
        self.structural = {"structural_gate_passed": True, "store_ready": False,
                           "failures": [], "libraries": {LIBRARY: []},
                           "packaging": '{"alignment": "PAGE_ALIGNMENT_16K"}'}
        self.validation_output = None
        self.validation_exit_code = 0
        self.validation_stderr = ""
        self.calls: list[tuple[list[str], dict]] = []
        self.process = patch.object(release.subprocess, "run", side_effect=self.run_fixture)
        self.run = self.process.start()
        self.addCleanup(self.process.stop)

    def write_aab(self, extra: list[tuple[str, bytes]] | None = None) -> None:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with zipfile.ZipFile(self.aab, "w", compression=zipfile.ZIP_STORED) as archive:
                for name, data in [*self.entries.items(), *(extra or [])]:
                    info = zipfile.ZipInfo(name, date_time=(2026, 10, 2, 12, 0, 0))
                    archive.writestr(info, data)

    def jar_report(self, *, unsigned: str | None = None, omit: str | None = None) -> str:
        rows = []
        for name, data in self.entries.items():
            if name == omit:
                continue
            flags = ("s" if name == "META-INF/MANIFEST.MF" else ""
                     if name in {"META-INF/UPLOAD.SF", "META-INF/UPLOAD.RSA"} or name.endswith("/") else "sm")
            if name == unsigned:
                flags = "m"
            rows.append(f"{flags:<5} {len(data):6} Fri Oct 02 12:00:00 UTC 2026 {name}")
        return "\n".join(rows) + '''
  s = signature was verified
  m = entry is listed in manifest
  k = at least one certificate was found in keystore
  ? = unsigned entry

- Signed by "CN=Waddle Upload"
    Digest algorithm: SHA-256
    Signature algorithm: SHA256withRSA, 2048-bit key

jar verified.

Warning:
''' + release.CHAIN_WARNING + '''
This jar contains entries whose signer certificate is self-signed.
This jar contains signatures that do not include a timestamp. Without a timestamp, users may not be able to validate this jar after any of the signer certificates expire (as early as 2056-10-02).
The signer certificate will expire on 2056-10-02.
'''

    def run_fixture(self, command: list[str], **kwargs: object) -> subprocess.CompletedProcess:
        self.calls.append((command, kwargs))
        executable = Path(command[0]).name
        if executable == "jarsigner":
            output = self.jar_output
        elif executable == "keytool":
            output = self.cert_output
        elif executable == "java":
            if "validate" in command:
                output = self.validation_summary() if self.validation_output is None else self.validation_output
                return subprocess.CompletedProcess(command, self.validation_exit_code, output, self.validation_stderr)
            module = next(arg.split("=", 1)[1] for arg in command if arg.startswith("--module="))
            output = self.manifests[module]
        elif command[0] == sys.executable and command[1] == str(release.CHECKER):
            output = json.dumps(self.structural)
        else:
            self.fail(f"Unexpected external tool: {command}")
        return subprocess.CompletedProcess(command, 0, output, "")

    def validation_summary(self) -> str:
        lines = ["App Bundle information", "------------", "Feature modules:", "\tFeature module: base"]
        for module in ("base", PACK):
            if module != "base":
                lines += ["Asset packs:", "\tAsset pack: " + module]
            for name in self.entries:
                if name.startswith(module + "/") and not name.endswith("/"):
                    relative = name[len(module) + 1:]
                    if relative not in release.SPECIAL_MODULE_FILES:
                        lines.append("\t\tFile: " + relative)
        return "\n".join(lines) + "\n"

    def verify(self, **updates: object) -> dict:
        options = {"artifact_sha256": release.sha256(self.aab),
                   "upload_certificate_sha256": hashlib.sha256(self.cert).hexdigest(),
                   "package": PACKAGE, "version": "1.0.0", "build_number": 2,
                   "bundletool": self.bundletool, "jdk": self.jdk}
        options.update(updates)
        return release.verify(self.aab, **options)

    def test_mock_signed_aab_verifies_contract_but_not_store_or_device(self) -> None:
        receipt = self.verify()
        self.assertEqual(receipt["state"], "android_upload_artifact_verified_offline")
        self.assertEqual(receipt["launch_edition"], "commerce")
        self.assertIs(receipt["native_billing_sdk_absence_verified"], False)
        self.assertIsNone(receipt["native_billing_sdk_absence"])
        self.assertIs(receipt["billing_acceptance_required"], True)
        self.assertIs(receipt["billing_purchases_deferred"], False)
        self.assertIs(receipt["manifests"][0]["billing_manifest_verified"], True)
        self.assertIs(receipt["manifests"][0]["native_billing_manifest_absence_verified"], False)
        self.assertEqual(receipt["artifact_sha256"], release.sha256(self.aab))
        self.assertEqual(receipt["upload_certificate_sha256"], hashlib.sha256(self.cert).hexdigest())
        self.assertTrue(receipt["signature_verified"])
        self.assertEqual(receipt["signed_payload_count"], len(self.entries) - 3)
        self.assertEqual(len(receipt["manifests"]), 2)
        self.assertEqual(receipt["manifests"][1]["delivery"], "install-time")
        for name in ("store_ready", "play_registration_verified", "play_app_signing_certificate_verified",
                     "device_tested", "billing_purchases_verified", "certificate_revocation_checked"):
            self.assertIs(receipt[name], False)
        self.assertIs(receipt["bundletool_validation"]["passed"], True)
        self.assertEqual(receipt["bundletool_validation"]["asset_packs"], [PACK])
        self.assertEqual(len(self.calls), 6)

    def test_explicit_commerce_keeps_historical_manifest_and_billing_gate(self) -> None:
        receipt = self.verify(launch_edition="commerce")
        self.assertEqual(receipt["launch_edition"], "commerce")
        self.assertIn("native billing acceptance", receipt["remaining_gates"])
        self.assertIs(receipt["billing_purchases_verified"], False)
        self.manifests["base"] = free_manifest()
        with self.assertRaisesRegex(ValueError, "billing permission missing"):
            self.verify()

    def test_free_offline_receipt_proves_sdk_absence_not_purchases_or_launch(self) -> None:
        self.manifests["base"] = free_manifest()
        receipt = self.verify(launch_edition="free_offline_mvp")
        self.assertEqual(receipt["launch_edition"], "free_offline_mvp")
        self.assertIs(receipt["signature_verified"], True)
        self.assertIs(receipt["native_billing_sdk_absence_verified"], True)
        absence = receipt["native_billing_sdk_absence"]
        self.assertIs(absence["verified"], True)
        self.assertIs(absence["permission_absence_verified"], True)
        self.assertIs(absence["provider_metadata_absence_verified"], True)
        self.assertEqual(absence["method"], "bounded_dex_class_string_scan")
        self.assertEqual(absence["dex_files"], {"base/dex/classes.dex": {
            "sha256": hashlib.sha256(self.entries["base/dex/classes.dex"]).hexdigest(),
            "bytes_scanned": len(self.entries["base/dex/classes.dex"]),
        }})
        self.assertEqual(absence["forbidden_class_string_markers"],
                         [marker.decode("ascii") for marker in release.BILLING_DEX_CLASS_MARKERS])
        self.assertEqual(absence["matched_class_string_markers"], [])
        self.assertIs(absence["arbitrary_obfuscated_code_absence_verified"], False)
        self.assertIs(receipt["manifests"][0]["native_billing_manifest_absence_verified"], True)
        self.assertIs(receipt["manifests"][0]["billing_manifest_verified"], False)
        self.assertIs(receipt["billing_acceptance_required"], False)
        self.assertIs(receipt["billing_purchases_deferred"], True)
        self.assertNotIn("native billing acceptance", receipt["remaining_gates"])
        for name in ("store_ready", "device_tested", "billing_purchases_verified",
                     "play_registration_verified", "play_app_signing_certificate_verified"):
            self.assertIs(receipt[name], False)
        self.assertEqual(len(self.calls), 6)

    def test_unknown_launch_edition_rejected_before_tools(self) -> None:
        for edition in ("free", "Free_offline_mvp", "", None, False, [], {}):
            with self.subTest(edition=edition), self.assertRaisesRegex(ValueError, "launch edition"):
                self.verify(launch_edition=edition)
        self.run.assert_not_called()

    def test_free_offline_billing_permission_in_either_android_declaration_rejected(self) -> None:
        for tag in ("uses-permission", "uses-permission-sdk-23"):
            self.manifests["base"] = free_manifest().replace("<application ",
                f'<{tag} android:name="{release.BILLING_PERMISSION}"/><application ')
            with self.subTest(tag=tag), self.assertRaisesRegex(ValueError, "must not declare native billing permission"):
                self.verify(launch_edition="free_offline_mvp")

    def test_free_offline_provider_metadata_name_value_and_alias_rejected(self) -> None:
        for name, value in ((release.PROVIDER_KEY, release.PROVIDER_CLASS),
                            (release.PROVIDER_KEY, "wrong"), ("alias", release.PROVIDER_CLASS),
                            ("GodotGooglePlayBilling", "wrong")):
            self.manifests["base"] = free_manifest().replace("</application>",
                f'<meta-data android:name="{name}" android:value="{value}"/></application>')
            with self.subTest(name=name, value=value), self.assertRaisesRegex(ValueError, "billing singleton metadata"):
                self.verify(launch_edition="free_offline_mvp")

    def test_free_offline_checks_billing_absence_in_asset_pack_manifest_too(self) -> None:
        self.manifests["base"] = free_manifest()
        for declaration in (
                f'<uses-permission-sdk-23 android:name="{release.BILLING_PERMISSION}"/>',
                f'<meta-data android:name="{release.PROVIDER_KEY}" android:value="{release.PROVIDER_CLASS}"/>'):
            self.manifests[PACK] = pack_manifest().replace("</manifest>", declaration + "</manifest>")
            with self.subTest(declaration=declaration), self.assertRaisesRegex(ValueError, "must not declare native billing"):
                self.verify(launch_edition="free_offline_mvp")

    def test_free_offline_known_billing_provider_dex_markers_rejected_before_tools(self) -> None:
        self.manifests["base"] = free_manifest()
        for marker in release.BILLING_DEX_CLASS_MARKERS:
            self.entries["base/dex/classes.dex"] = b"synthetic-dex\x00L" + marker + b"BillingClient;\x00"
            self.write_aab()
            self.jar_output = self.jar_report()
            with self.subTest(marker=marker), self.assertRaisesRegex(ValueError, "billing/provider DEX class strings"):
                self.verify(launch_edition="free_offline_mvp")
        self.run.assert_not_called()

    def test_free_offline_scans_every_dex_and_handles_chunk_boundary(self) -> None:
        self.manifests["base"] = free_manifest()
        self.entries["base/dex/classes2.dex"] = (b"x" * 29 +
            b"Lorg/godotengine/plugin/googleplaybilling/GodotGooglePlayBilling;\x00")
        self.write_aab()
        self.jar_output = self.jar_report()
        with patch.object(release, "DEX_READ_CHUNK_BYTES", 32), self.assertRaisesRegex(ValueError, "billing/provider DEX"):
            self.verify(launch_edition="free_offline_mvp")
        self.run.assert_not_called()
        self.entries["base/dex/classes2.dex"] = b"synthetic-second-dex-without-billing"
        self.write_aab()
        self.jar_output = self.jar_report()
        receipt = self.verify(launch_edition="free_offline_mvp")
        self.assertEqual(sorted(receipt["native_billing_sdk_absence"]["dex_files"]),
                         ["base/dex/classes.dex", "base/dex/classes2.dex"])

    def test_free_offline_empty_dex_rejected_before_tools(self) -> None:
        self.manifests["base"] = free_manifest()
        self.entries["base/dex/classes.dex"] = b""
        self.write_aab()
        self.jar_output = self.jar_report()
        with self.assertRaisesRegex(ValueError, "DEX inventory exceeds supported limits"):
            self.verify(launch_edition="free_offline_mvp")
        self.run.assert_not_called()

    def test_free_offline_does_not_relax_signing_structure_or_asset_gates(self) -> None:
        self.manifests["base"] = free_manifest()
        self.jar_output = self.jar_report(unsigned=LIBRARY)
        with self.assertRaisesRegex(ValueError, "Every AAB payload"):
            self.verify(launch_edition="free_offline_mvp")
        self.jar_output = self.jar_report()
        self.structural["structural_gate_passed"] = False
        with self.assertRaisesRegex(ValueError, "structural checker"):
            self.verify(launch_edition="free_offline_mvp")
        del self.entries[f"{PACK}/assets/project.binary"]
        self.write_aab()
        with self.assertRaisesRegex(ValueError, "game resource"):
            self.verify(launch_edition="free_offline_mvp")

    def test_cli_free_offline_edition_is_explicit_and_unknown_edition_rejected(self) -> None:
        self.manifests["base"] = free_manifest()
        argv = [str(self.aab), "--artifact-sha256", release.sha256(self.aab),
                "--upload-certificate-sha256", hashlib.sha256(self.cert).hexdigest(),
                "--package", PACKAGE, "--version", "1.0.0", "--build-number", "2",
                "--bundletool", str(self.bundletool), "--jdk", str(self.jdk), "--launch-edition"]
        output = io.StringIO()
        with redirect_stdout(output):
            status = release.main([*argv, "free_offline_mvp"])
        self.assertEqual(status, 0)
        receipt = json.loads(output.getvalue())
        self.assertIs(receipt["native_billing_sdk_absence_verified"], True)
        self.assertIs(receipt["billing_purchases_verified"], False)
        self.run.reset_mock()
        output = io.StringIO()
        with redirect_stdout(output):
            status = release.main([*argv, "unsupported"])
        self.assertEqual(status, 1)
        receipt = json.loads(output.getvalue())
        self.assertEqual(receipt["state"], "android_upload_artifact_rejected")
        self.assertIn("launch edition", receipt["error"])
        self.run.assert_not_called()

    def test_exact_asset_pack_assets_metadata_is_signed_and_format_validated(self) -> None:
        receipt = self.verify()
        self.assertEqual(receipt["signed_payload_count"], len(self.entries) - 3)
        validation = [command for command, _ in self.calls if "validate" in command]
        self.assertEqual(len(validation), 1)
        self.assertIn("--bundle=" + str(self.aab), validation[0])
        self.assertEqual(receipt["bundletool_validation"]["report_sha256"],
                         hashlib.sha256(self.validation_summary().encode()).hexdigest())

    def test_unsigned_asset_pack_assets_metadata_is_rejected(self) -> None:
        self.jar_output = self.jar_report(unsigned=f"{PACK}/assets.pb")
        with self.assertRaisesRegex(ValueError, "Every AAB payload"):
            self.verify()
        self.assertFalse(any("validate" in command for command, _ in self.calls))

    def test_empty_and_oversized_asset_pack_metadata_rejected_before_tools(self) -> None:
        for contents in (b"", b"x" * (release.MAX_ASSETS_CONFIG_BYTES + 1)):
            self.entries[f"{PACK}/assets.pb"] = contents
            self.write_aab()
            with self.subTest(size=len(contents)), self.assertRaisesRegex(ValueError, "bounded nonempty"):
                self.verify()
        self.run.assert_not_called()

    def test_asset_pack_metadata_does_not_allow_other_protobuf_code_or_resources(self) -> None:
        for name in ("other.pb", "assets.pb.extra", "Assets.pb", "native.pb", "resources.pb", "apex.pb",
                     "runtime_enabled_sdk_config.pb", "dex/classes.dex", "res/values.xml", "root/extra"):
            self.write_aab([(f"{PACK}/{name}", b"new unsupported module content")])
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.verify()
        self.run.assert_not_called()

    def test_asset_pack_metadata_cannot_allow_feature_or_on_demand_manifest(self) -> None:
        for xml in (pack_manifest(kind="feature"), pack_manifest(delivery="on-demand")):
            self.manifests[PACK] = xml
            with self.subTest(xml=xml), self.assertRaises(ValueError):
                self.verify()

    def test_bundletool_validation_failure_cannot_accept_malformed_asset_metadata(self) -> None:
        self.entries[f"{PACK}/assets.pb"] = b"malformed protobuf"
        self.write_aab()
        self.jar_output = self.jar_report()
        self.validation_exit_code = 1
        self.validation_stderr = "synthetic invalid protobuf diagnostic must not be echoed"
        with self.assertRaisesRegex(ValueError, "format validation failed"):
            self.verify()
        self.assertFalse(any("--module=" + PACK in command for command, _ in self.calls))
        self.assertFalse(any(command[0] == sys.executable for command, _ in self.calls))

    def test_bundletool_validation_unknown_empty_and_warning_output_rejected(self) -> None:
        for output in ("", "synthetic unknown validation format", self.validation_summary() + "Warning: ignored metadata\n"):
            self.validation_output = output
            with self.subTest(output=output), self.assertRaisesRegex(ValueError, "validation"):
                self.verify()

    def test_bundletool_validation_missing_duplicate_and_wrong_module_summary_rejected(self) -> None:
        good = self.validation_summary()
        for output in (good.replace("\t\tFile: assets/project.binary\n", ""),
                       good + "\t\tFile: assets/project.binary\n",
                       good.replace("\tAsset pack: " + PACK, "\tFeature module: " + PACK),
                       good.replace("\tFeature module: base", "\tFeature module: unknown"),
                       good + "\tAsset pack: unknown\n"):
            self.validation_output = output
            with self.subTest(output=output), self.assertRaisesRegex(ValueError, "validation"):
                self.verify()

    def test_tools_receive_clean_environment_and_explicit_jdk(self) -> None:
        poisoned = {"GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD": "must-not-inherit",
                    "JAVA_TOOL_OPTIONS": "must-not-inherit", "_JAVA_OPTIONS": "must-not-inherit",
                    "JDK_JAVA_OPTIONS": "must-not-inherit", "CLASSPATH": "must-not-inherit"}
        with patch.dict(os.environ, poisoned):
            self.verify()
        for command, kwargs in self.calls:
            env = kwargs["env"]
            self.assertEqual(env["PATH"].split(os.pathsep)[0], str(self.jdk / "bin"))
            self.assertTrue(kwargs["capture_output"])
            self.assertEqual(kwargs["timeout"], 120)
            self.assertFalse(kwargs["check"])
            for key in poisoned:
                if key != "JDK_JAVA_OPTIONS":
                    self.assertNotIn(key, env)
            self.assertNotIn("must-not-inherit", str(env) + str(command))
            self.assertNotIn("-keystore", command)
            self.assertNotIn("-storepass", command)
            self.assertNotIn("-revCheck", command)
            self.assertNotIn("-sign", command)
            if command[0] == sys.executable:
                self.assertIn("-Duser.home=/tmp/waddle-android-verify-", env["JDK_JAVA_OPTIONS"])
            else:
                self.assertEqual(Path(command[0]).parent, self.jdk / "bin")
                self.assertTrue(any("-Duser.home=/tmp/waddle-android-verify-" in arg for arg in command))

    def test_artifact_sha_mismatch_prevents_any_external_tool(self) -> None:
        with self.assertRaisesRegex(ValueError, "artifact SHA256 mismatch"):
            self.verify(artifact_sha256="0" * 64)
        self.run.assert_not_called()

    def test_invalid_expected_identity_prevents_external_tool(self) -> None:
        for options in ({"package": "../wrong"}, {"version": "1.0"}, {"build_number": 0},
                        {"build_number": True}, {"artifact_sha256": "ab"}, {"upload_certificate_sha256": "z" * 64}):
            with self.subTest(options=options), self.assertRaises(ValueError):
                self.verify(**options)
        self.run.assert_not_called()

    def test_certificate_colon_fingerprint_normalizes(self) -> None:
        value = hashlib.sha256(self.cert).hexdigest().upper()
        result = self.verify(upload_certificate_sha256=":".join(value[i:i + 2] for i in range(0, len(value), 2)))
        self.assertEqual(result["upload_certificate_sha256"], value.lower())

    def test_input_symlink_relative_and_missing_jdk_rejected(self) -> None:
        alias = self.root / "alias.aab"
        alias.symlink_to(self.aab)
        with self.assertRaises(ValueError):
            release.regular_file(alias, "AAB")
        for options in ({"bundletool": Path("bundletool.jar")}, {"jdk": self.root / "missing"}):
            with self.subTest(options=options), self.assertRaises(ValueError):
                self.verify(**options)
        self.run.assert_not_called()

    def test_duplicate_and_case_ambiguous_zip_names_rejected(self) -> None:
        for name in (LIBRARY, LIBRARY.upper()):
            self.write_aab([(name, b"extra")])
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, "duplicate"):
                self.verify()
        self.run.assert_not_called()

    def test_traversal_and_control_character_zip_names_rejected(self) -> None:
        for name in ("base/assets/../escape", "base/assets/a\\b", "/absolute", "base/assets/line\njar verified.", "base/assets/with space"):
            self.write_aab([(name, b"extra")])
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, "Unsafe"):
                self.verify()
        self.run.assert_not_called()

    def test_symlink_zip_entry_rejected_before_tools(self) -> None:
        with zipfile.ZipFile(self.aab, "a") as archive:
            info = zipfile.ZipInfo("base/assets/link")
            info.external_attr = 0o120777 << 16
            archive.writestr(info, b"../target")
        with self.assertRaisesRegex(ValueError, "Unsafe"):
            self.verify()
        self.run.assert_not_called()

    def test_crc_tamper_rejected_even_with_matching_container_sha(self) -> None:
        raw = self.aab.read_bytes()
        self.aab.write_bytes(raw.replace(b"__CRC_SAMPLE__", b"__BAD_SAMPLE__"))
        with self.assertRaisesRegex(ValueError, "CRC"):
            self.verify()
        self.run.assert_not_called()

    def test_unsigned_aab_and_multiple_signature_files_rejected(self) -> None:
        for extra in ([("META-INF/OTHER.SF", b"other")], [("META-INF/OTHER.RSA", b"other")],
                      [("META-INF/SIG-UNKNOWN", b"other")]):
            self.write_aab(extra)
            with self.subTest(extra=extra), self.assertRaises(ValueError):
                self.verify()
        del self.entries["META-INF/UPLOAD.RSA"]
        self.write_aab()
        with self.assertRaisesRegex(ValueError, "signature"):
            self.verify()
        self.run.assert_not_called()

    def test_missing_required_game_resources_rejected(self) -> None:
        del self.entries[f"{PACK}/assets/project.binary"]
        self.write_aab()
        with self.assertRaisesRegex(ValueError, "game resource"):
            self.verify()
        self.run.assert_not_called()

    def test_non_arm64_or_asset_pack_code_rejected(self) -> None:
        for name in ("base/lib/x86/libbad.so", f"{PACK}/dex/classes.dex"):
            self.write_aab([(name, b"extra")])
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.verify()
        self.run.assert_not_called()

    def test_unsigned_payload_rejected_despite_jar_verified(self) -> None:
        self.jar_output = self.jar_report(unsigned=LIBRARY)
        with self.assertRaisesRegex(ValueError, "Every AAB payload"):
            self.verify()

    def test_missing_entry_coverage_rejected_despite_jar_verified(self) -> None:
        self.jar_output = self.jar_report(omit=LIBRARY)
        with self.assertRaisesRegex(ValueError, "incomplete entry coverage"):
            self.verify()

    def test_unknown_jarsigner_entry_format_rejected(self) -> None:
        self.jar_output = self.jar_output.replace("UTC", "EDT")
        with self.assertRaisesRegex(ValueError, "format"):
            self.verify()

    def test_jarsigner_size_inventory_mismatch_rejected(self) -> None:
        self.jar_output = self.jar_output.replace(f"{len(self.entries[LIBRARY]):6} Fri", f"{999:6} Fri")
        with self.assertRaisesRegex(ValueError, "inventory differs"):
            self.verify()

    def test_multiple_signers_and_unsigned_status_rejected(self) -> None:
        for output in (self.jar_output + '\n- Signed by "CN=Other"\n',
                       self.jar_output.replace("jar verified.", "jar is unsigned.")):
            self.jar_output = output
            with self.subTest(output=output[-100:]), self.assertRaises(ValueError):
                self.verify()

    def test_unsafe_and_unknown_jarsigner_warnings_rejected(self) -> None:
        original = self.jar_output
        for warning in ("The signer certificate has expired.", "SHA1 is weak.",
                        "This jar contains unsigned entries which have not been integrity-checked.",
                        "Unknown future warning."):
            self.jar_output = original + warning + "\n"
            with self.subTest(warning=warning), self.assertRaises(ValueError):
                self.verify()

    def test_zero_exit_not_verified_rejected(self) -> None:
        self.jar_output = "Success without cryptographic proof\n"
        with self.assertRaisesRegex(ValueError, "verified signer"):
            self.verify()

    def test_wrong_public_signer_fingerprint_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "does not match"):
            self.verify(upload_certificate_sha256="0" * 64)

    def test_debug_signer_rejected_even_when_public_pin_matches(self) -> None:
        self.cert = certificate("Android Debug")
        self.cert_output = signer_report([self.cert])
        with self.assertRaisesRegex(ValueError, "Debug"):
            self.verify()

    def test_multiple_embedded_signers_rejected(self) -> None:
        self.cert_output += signer_report([certificate("Other")]).replace("Signer #1:", "Signer #2:")
        with self.assertRaisesRegex(ValueError, "multiple"):
            self.verify()

    def test_malformed_public_certificate_rejected(self) -> None:
        self.cert = b"not-x509"
        self.cert_output = signer_report([self.cert])
        with self.assertRaisesRegex(ValueError, "certificate"):
            self.verify()

    def test_x509_version_one_subject_supported(self) -> None:
        self.cert = certificate(versioned=False)
        self.cert_output = signer_report([self.cert])
        self.assertTrue(self.verify()["signature_verified"])

    def test_actual_manifest_package_version_build_sdk_mismatch_rejected(self) -> None:
        original = self.manifests["base"]
        for old, new in ((PACKAGE, "com.other.wrong"), ('versionCode="2"', 'versionCode="3"'),
                         ('versionName="1.0.0"', 'versionName="1.0.1"'),
                         ('minSdkVersion="24"', 'minSdkVersion="23"'),
                         ('targetSdkVersion="36"', 'targetSdkVersion="35"')):
            self.manifests["base"] = original.replace(old, new)
            with self.subTest(old=old), self.assertRaisesRegex(ValueError, "manifest"):
                self.verify()

    def test_debug_test_and_unknown_release_flags_rejected(self) -> None:
        for key, value in (("debuggable", "true"), ("testOnly", "true"),
                           ("profileableByShell", "true"), ("debuggable", "@bool/debug")):
            self.manifests["base"] = base_manifest(**{key: value})
            with self.subTest(key=key, value=value), self.assertRaisesRegex(ValueError, "release flags"):
                self.verify()

    def test_explicit_false_release_flags_pass(self) -> None:
        self.manifests["base"] = base_manifest(debuggable="false", testOnly="false", profileableByShell="false")
        self.assertTrue(self.verify()["signature_verified"])

    def test_shell_profileable_rejected(self) -> None:
        self.manifests["base"] = base_manifest().replace("</application>", '<profileable android:shell="true"/></application>')
        with self.assertRaisesRegex(ValueError, "shell profiling"):
            self.verify()

    def test_actual_godot_enabled_shell_profileable_release_manifest_is_rejected(self) -> None:
        self.manifests["base"] = base_manifest().replace("</application>",
            '<profileable android:enabled="true" android:shell="true"/></application>')
        with self.assertRaisesRegex(ValueError, "shell profiling"):
            self.verify()

    def test_profileable_explicitly_disabled_for_all_supported_android_versions_passes(self) -> None:
        self.manifests["base"] = base_manifest().replace("</application>",
            '<profileable android:enabled="false" android:shell="false"/></application>')
        self.assertTrue(self.verify()["manifests"][0]["release_flags_verified"])

    def test_enabled_false_cannot_override_shell_true_for_android_29(self) -> None:
        self.manifests["base"] = base_manifest().replace("</application>",
            '<profileable android:enabled="false" android:shell="true"/></application>')
        with self.assertRaisesRegex(ValueError, "shell profiling"):
            self.verify()

    def test_missing_billing_permission_or_singleton_rejected(self) -> None:
        original = self.manifests["base"]
        for old in ("com.android.vending.BILLING", release.PROVIDER_CLASS):
            self.manifests["base"] = original.replace(old, "wrong")
            with self.subTest(old=old), self.assertRaisesRegex(ValueError, "billing"):
                self.verify()

    def test_feature_on_demand_conditional_and_instant_modules_rejected(self) -> None:
        for xml in (pack_manifest(kind="feature"), pack_manifest(delivery="on-demand"),
                    pack_manifest().replace("<dist:install-time/>", "<dist:install-time><dist:conditions/></dist:install-time>"),
                    pack_manifest().replace('dist:type="asset-pack"', 'dist:type="asset-pack" dist:instant="true"')):
            self.manifests[PACK] = xml
            with self.subTest(xml=xml), self.assertRaises(ValueError):
                self.verify()

    def test_manifest_doctype_and_invalid_xml_rejected(self) -> None:
        for xml in ('<!DOCTYPE manifest [<!ENTITY x "bad">]>' + base_manifest(), "<manifest"):
            self.manifests["base"] = xml
            with self.subTest(xml=xml), self.assertRaises((ValueError, release.ET.ParseError)):
                self.verify()

    def test_base_feature_split_and_pack_split_mismatch_rejected(self) -> None:
        self.manifests["base"] = base_manifest().replace("<manifest ", '<manifest split="feature" ')
        with self.assertRaisesRegex(ValueError, "feature split"):
            self.verify()
        self.manifests["base"] = base_manifest()
        self.manifests[PACK] = pack_manifest().replace(f'split="{PACK}"', 'split="different"')
        with self.assertRaisesRegex(ValueError, "asset-only pack"):
            self.verify()

    def test_duplicate_jarsigner_entry_and_unverified_manifest_rejected(self) -> None:
        original = self.jar_output
        self.jar_output += original.splitlines()[0] + "\n"
        with self.assertRaisesRegex(ValueError, "inventory differs"):
            self.verify()
        # Avoid depending on a fixture's width; remove its manifest signature flag.
        lines = original.splitlines()
        lines[0] = " " + lines[0][1:]
        self.jar_output = "\n".join(lines) + "\n"
        with self.assertRaisesRegex(ValueError, "Every AAB payload"):
            self.verify()

    def test_public_chain_duplicate_and_unknown_keytool_format_rejected(self) -> None:
        for output in (signer_report([self.cert, self.cert]), "Certificate report without signer header"):
            self.cert_output = output
            with self.subTest(output=output[:40]), self.assertRaises(ValueError):
                self.verify()

    def test_actual_jdk_21_owner_display_line_preserves_der_pin_validation(self) -> None:
        self.cert_output = signer_report([self.cert]).replace("Certificate #1:\n",
            "Certificate #1:\nCertificate owner: CN=Waddle Wars Penguin Panic Android Upload\n\n")
        self.assertTrue(self.verify()["signature_verified"])
        with self.assertRaisesRegex(ValueError, "public upload certificate"):
            self.verify(upload_certificate_sha256="0" * 64)

    def test_owner_display_line_cannot_disguise_actual_der_debug_subject(self) -> None:
        self.cert = certificate("Android Debug")
        self.cert_output = signer_report([self.cert]).replace("Certificate #1:\n",
            "Certificate #1:\nCertificate owner: CN=Waddle Upload\n\n")
        with self.assertRaisesRegex(ValueError, "Debug"):
            self.verify()

    def test_owner_line_unknown_duplicate_empty_control_and_oversized_formats_rejected(self) -> None:
        for owner in ("Owner: CN=Waddle Upload\n", "Certificate owner: CN=A\nCertificate owner: CN=B\n",
                      "Certificate owner: \n", "Certificate owner: CN=bad\tname\n",
                      "Certificate owner: CN=" + "x" * 4097 + "\n"):
            self.cert_output = signer_report([self.cert]).replace("Certificate #1:\n", "Certificate #1:\n" + owner)
            with self.subTest(owner=owner[:80]), self.assertRaisesRegex(ValueError, "public signer chains"):
                self.verify()

    def test_structural_failure_and_wrong_inventory_rejected(self) -> None:
        for updates in ({"structural_gate_passed": False}, {"failures": ["bad ELF"]},
                        {"libraries": {"wrong.so": []}}, {"packaging": "PAGE_ALIGNMENT_4K"},
                        {"store_ready": True}):
            original = self.structural.copy()
            self.structural.update(updates)
            with self.subTest(updates=updates), self.assertRaisesRegex(ValueError, "structural checker"):
                self.verify()
            self.structural = original

    def test_nonzero_tool_status_rejects(self) -> None:
        self.run.side_effect = None
        self.run.return_value = subprocess.CompletedProcess([], 1, "jar verified.", "")
        with self.assertRaisesRegex(ValueError, "exit 1"):
            self.verify()

    def test_unexpected_stderr_rejects_without_echoing_contents(self) -> None:
        self.run.side_effect = None
        self.run.return_value = subprocess.CompletedProcess([], 0, self.jar_output, "untrusted diagnostic")
        with self.assertRaisesRegex(ValueError, "unsupported stderr") as raised:
            self.verify()
        self.assertNotIn("untrusted diagnostic", str(raised.exception))

    def test_timeout_has_no_success_receipt(self) -> None:
        self.run.side_effect = subprocess.TimeoutExpired(["synthetic"], 120)
        with self.assertRaises(subprocess.TimeoutExpired):
            self.verify()

    def test_artifact_mutation_during_tools_discards_all_acceptance(self) -> None:
        original = self.run_fixture
        def mutate(command: list[str], **kwargs: object) -> subprocess.CompletedProcess:
            result = original(command, **kwargs)
            if command[0] == sys.executable:
                self.aab.write_bytes(self.aab.read_bytes() + b"changed-after-check")
            return result
        self.run.side_effect = mutate
        with self.assertRaisesRegex(ValueError, "changed during verification"):
            self.verify()

    def test_tool_mutation_during_verification_discards_acceptance(self) -> None:
        original = self.run_fixture
        def mutate(command: list[str], **kwargs: object) -> subprocess.CompletedProcess:
            result = original(command, **kwargs)
            if command[0] == sys.executable:
                self.bundletool.write_bytes(b"changed-tool")
            return result
        self.run.side_effect = mutate
        with self.assertRaisesRegex(ValueError, "tool changed"):
            self.verify()

    def test_cli_rejection_returns_nonzero_machine_readable_blocked_receipt(self) -> None:
        output = io.StringIO()
        with redirect_stdout(output):
            status = release.main([str(self.aab), "--artifact-sha256", "0" * 64,
                                   "--upload-certificate-sha256", hashlib.sha256(self.cert).hexdigest(),
                                   "--package", PACKAGE, "--version", "1.0.0", "--build-number", "2",
                                   "--bundletool", str(self.bundletool), "--jdk", str(self.jdk)])
        self.assertEqual(status, 1)
        receipt = json.loads(output.getvalue())
        self.assertEqual(receipt["state"], "android_upload_artifact_rejected")
        self.assertIs(receipt["store_ready"], False)
        self.assertIs(receipt["signature_verified"], False)
        self.run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
