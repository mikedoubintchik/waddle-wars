#!/usr/bin/env python3
"""Build a prepared candidate locally, keeping source checkout untouched.

Android requires normally configured Godot SDK/JDK paths and externally supplied
release-keystore environment variables. iOS emits an Xcode project only. This
script never signs iOS archives, uploads builds, installs SDKs, or opens accounts.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import zipfile
import zlib
from xml.etree.ElementTree import ParseError
import xml.etree.ElementTree as ET
from xml.parsers.expat import ExpatError

from native_release import sha256, files_in_project, validate_app_name

ERRORS = re.compile(r"SCRIPT ERROR:|Parse Error:|Failed to load script|ERROR:|Export failed", re.I)
SIGNING_ENV = (
    "GODOT_ANDROID_KEYSTORE_RELEASE_PATH",
    "GODOT_ANDROID_KEYSTORE_RELEASE_USER",
    "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD",
)
# Godot 4.7.1's installed iOS template emits these keys unconditionally. Waddle
# uses neither capture nor photo-library APIs; empty declarations generate
# Xcode warnings. A new declared use must receive an explicit policy update.
UNUSED_IOS_PURPOSE_KEYS = (
    "NSCameraUsageDescription",
    "NSPhotoLibraryUsageDescription",
    "NSMicrophoneUsageDescription",
)


def apply_android_release_policy(manifest: Path) -> dict:
    """Disable only the pinned template's profiling node in a fresh snapshot.

    Godot's 4.7.1 main manifest intentionally permits shell profiling in release.
    Waddle's release gate requires it off; debug build preparation is unchanged.
    Preserve all other manifest bytes and record this isolated policy mutation.
    """
    if (not manifest.is_absolute() or any(p.is_symlink() for p in (manifest, *manifest.parents))
            or not manifest.is_file()):
        raise ValueError("Android release manifest must be a regular file")
    original = manifest.read_bytes()
    if len(original) > 256 * 1024 or re.search(rb"<!\s*(?:DOCTYPE|ENTITY)", original, re.I):
        raise ValueError("Unsupported Android release manifest")
    try:
        text = original.decode("utf-8")
        root = ET.fromstring(text)
    except (UnicodeError, ParseError) as error:
        raise ValueError("Malformed Android release manifest") from error
    android = "{http://schemas.android.com/apk/res/android}"
    tools = "{http://schemas.android.com/tools}"
    apps = root.findall("application")
    nodes = root.findall(".//profileable")
    if (root.tag != "manifest" or len(apps) != 1 or len(nodes) != 1
            or apps[0].findall("profileable") != nodes or len(nodes[0])
            or set(nodes[0].attrib) != {android + "shell", android + "enabled", tools + "targetApi"}
            or nodes[0].get(tools + "targetApi") != "29"
            or any(nodes[0].get(android + key) not in ("true", "false") for key in ("shell", "enabled"))):
        raise ValueError("Pinned Android profiling node changed; policy review required")
    blocks = re.findall(r"<profileable\b[^>]*?/>", text)
    if len(blocks) != 1:
        raise ValueError("Ambiguous Android profiling node")
    updated = blocks[0]
    for key in ("shell", "enabled"):
        updated, count = re.subn(r'android:' + key + r'="(?:true|false)"',
                                'android:' + key + '="false"', updated)
        if count != 1:
            raise ValueError("Unsupported Android profiling node formatting")
    replacement = text.replace(blocks[0], updated, 1).encode("utf-8")
    if replacement != original:
        manifest.write_bytes(replacement)
    return {"policy": "no-release-shell-or-system-profiling-v1",
            "before_sha256": hashlib.sha256(original).hexdigest(),
            "after_sha256": sha256(manifest), "shell_profileable": False,
            "system_profileable": False}


def apply_ios_display_name(info_plist: Path, app_name: str) -> dict:
    """Stamp only the exported launcher title, preserving bundle/save identity.

    The pinned Godot Apple exporter derives its default title from config/name;
    changing that setting would conflate the display name with save identity.
    This policy operates on the exported, unsigned Xcode project only.
    """
    app_name = validate_app_name(app_name)
    if info_plist.is_symlink() or not info_plist.is_file():
        raise ValueError("Exported iOS app Info.plist must be a regular file")
    original = info_plist.read_bytes()
    try:
        info = plistlib.loads(original)
    except (plistlib.InvalidFileException, ValueError, TypeError, ExpatError) as error:
        raise ValueError("Invalid exported iOS app Info.plist") from error
    if not isinstance(info, dict):
        raise ValueError("Exported iOS app Info.plist must contain a dictionary")
    previous = info.get("CFBundleDisplayName")
    if previous is not None and not isinstance(previous, str):
        raise ValueError("Exported iOS app display name must be a string")
    if previous != app_name:
        info["CFBundleDisplayName"] = app_name
        info_plist.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_XML, sort_keys=True))
    return {
        "policy": "launcher-title-without-project-rename-v1",
        "app_name": app_name, "previous_display_name": previous,
        "before_sha256": hashlib.sha256(original).hexdigest(),
        "after_sha256": sha256(info_plist),
    }


def apply_ios_permission_policy(info_plist: Path) -> dict:
    """Remove only unused blank purpose strings from the exported app plist."""
    if info_plist.is_symlink() or not info_plist.is_file():
        raise ValueError("Exported iOS app Info.plist must be a regular file")
    original = info_plist.read_bytes()
    try:
        info = plistlib.loads(original)
    except (plistlib.InvalidFileException, ValueError, TypeError, ExpatError) as error:
        raise ValueError("Invalid exported iOS app Info.plist") from error
    if not isinstance(info, dict):
        raise ValueError("Exported iOS app Info.plist must contain a dictionary")
    # Validate the entire policy before making any change. Nonempty or invalid
    # values can indicate a new permission feature; silently deleting them
    # would hide that declaration and potentially break its runtime request.
    present = [key for key in UNUSED_IOS_PURPOSE_KEYS if key in info]
    for key in present:
        if not isinstance(info[key], str) or info[key].strip():
            raise ValueError(f"Unexpected declared iOS permission: {key}; review Waddle permission policy")
    if present:
        for key in present:
            del info[key]
        info_plist.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_XML, sort_keys=True))
    return {
        "policy": "no-camera-microphone-photo-library-v1",
        "removed_keys": present,
        "before_sha256": hashlib.sha256(original).hexdigest(),
        "after_sha256": sha256(info_plist),
    }


def verify_snapshot(project: Path, receipt: dict) -> None:
    if not receipt.get("prepared_files"):
        raise ValueError("Prepared snapshot hashes missing")
    names = set(receipt["prepared_files"])
    for name in names:
        if Path(name).is_absolute() or ".." in Path(name).parts:
            raise ValueError("Unsafe prepared snapshot path")
    current_names = {str(path.relative_to(project)) for path in files_in_project(project)}
    if current_names != names:
        raise ValueError("Prepared file set changed; prepare a fresh candidate")
    for name, digest in receipt["prepared_files"].items():
        path = project / name
        if path.is_symlink() or not path.is_file() or sha256(path) != digest:
            raise ValueError(f"Prepared source changed: {name}; prepare a fresh candidate")


def collect_generated_import_metadata(project: Path, prepared: dict, artifacts: dict,
                                      source_sha256: str) -> dict:
    """Freeze only new Godot script/shader UIDs; never overwrite source provenance."""
    if not isinstance(source_sha256, str) or not re.fullmatch(r"[0-9a-f]{64}", source_sha256):
        raise ValueError("Frozen source hash required for import metadata")
    expected = dict(prepared)
    for name, value in artifacts.items():
        if not name.startswith("project/build/"):
            raise ValueError("Unsupported export artifact path")
        relative = name.removeprefix("project/")
        if relative in expected and expected[relative] != value:
            raise ValueError("Prepared/export inventory conflict")
        expected[relative] = value
    current = {str(path.relative_to(project)): path for path in files_in_project(project)}
    if set(expected) - set(current):
        raise ValueError("Frozen export file disappeared")
    for name, value in expected.items():
        if sha256(current[name]) != value:
            raise ValueError("Frozen source/export bytes changed during import")
    generated = {}
    for name in sorted(set(current) - set(expected)):
        path = current[name]
        if (not name.endswith((".gd.uid", ".gdshader.uid")) or name[:-4] not in prepared
                or path.stat().st_size > 128
                or not re.fullmatch(rb"uid://[a-z0-9]+\n?", path.read_bytes())):
            raise ValueError("Unexpected Godot import-generated file")
        generated[name] = sha256(path)
    return {"schema_version": 1, "state": "godot_import_metadata_frozen",
            "source_sha256": source_sha256, "generated_uid_files": generated}


def run_checked(command: list[str], log: Path, *, env: dict | None = None) -> None:
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env, check=False)
    output = result.stdout
    # Godot can exit zero after an error. Classify the original diagnostic:
    # a configured signing value may itself contain an error marker.
    failed = bool(result.returncode or ERRORS.search(output))
    effective_env = os.environ if env is None else env
    # Longest first also hides a password beginning with the signing alias;
    # replacing the alias first would leave the password suffix exposed.
    secrets = {effective_env.get(key, "") for key in SIGNING_ENV} - {""}
    for value in sorted(secrets, key=len, reverse=True):
        output = output.replace(value, "<redacted-signing-value>")
    log.write_text(output)
    if failed:
        raise ValueError(f"Build step failed (exit {result.returncode}); inspect {log}")


def android_verification_inputs(upload_certificate_sha256: str | None, bundletool: Path | None,
                                jdk: Path | None) -> dict:
    """Public, credential-free prerequisites checked before any heavy export."""
    from verify_android_release import fingerprint, regular_file
    if not upload_certificate_sha256 or bundletool is None or jdk is None:
        raise ValueError("Android release requires --upload-certificate-sha256, --bundletool and --jdk; no build started")
    certificate = fingerprint(upload_certificate_sha256, "Upload certificate SHA256")
    bundletool = regular_file(bundletool, "Existing bundletool JAR")
    if bundletool.suffix != ".jar" or not jdk.is_absolute() or jdk.is_symlink() or not jdk.is_dir():
        raise ValueError("Existing bundletool JAR and explicit JDK directory required; no build started")
    jdk = jdk.resolve()
    for name in ("java", "jarsigner", "keytool"):
        if not os.access(regular_file(jdk / "bin" / name, f"Existing JDK {name}"), os.X_OK):
            raise ValueError("Existing JDK tools must be executable; no build started")
    return {"upload_certificate_sha256": certificate, "bundletool": bundletool, "jdk": jdk}


def verify_android_output(output: Path, receipt: dict, inputs: dict) -> dict:
    from verify_android_release import regular_file, verify
    # Do not resolve away a symlink before the verifier can reject it, and do
    # not hash a linked target before enforcing this post-export file guard.
    regular_file(output, "Exported Android AAB")
    try:
        return verify(output, artifact_sha256=sha256(output),
                      upload_certificate_sha256=inputs["upload_certificate_sha256"],
                      package=receipt["bundle_id"], version=receipt["version"],
                      build_number=receipt["build_number"], bundletool=inputs["bundletool"], jdk=inputs["jdk"],
                      launch_edition=receipt.get("launch_edition", "commerce"))
    except (subprocess.TimeoutExpired, ParseError, zipfile.BadZipFile, RuntimeError, zlib.error) as error:
        # The build orchestrator must persist build_failed for library-level
        # verification failures too, not leave an abandoned building receipt.
        raise ValueError(f"Android release verification failed: {type(error).__name__}") from error


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--godot", default=shutil.which("godot") or "godot")
    parser.add_argument("--android-sdk", type=Path, default=Path.home() / "Library/Android/sdk")
    parser.add_argument("--upload-certificate-sha256", help="Public registered/intended Android upload signer pin; never a key")
    parser.add_argument("--bundletool", type=Path, help="Explicit existing bundletool JAR for Android verification")
    parser.add_argument("--jdk", type=Path, help="Explicit existing JDK for credential-free Android verification")
    args = parser.parse_args()
    candidate = args.candidate.resolve()
    project = candidate / "project"
    try:
        receipt = json.loads((candidate / "receipt.json").read_text())
        if receipt["state"] != "prepared_unbuilt":
            raise ValueError("Candidate already built or attempted; preserve logs and prepare a new candidate")
        verify_snapshot(project, receipt)
        from native_release import verify_ios_template_binding
        verify_ios_template_binding(candidate, receipt)
        validate_app_name(receipt.get("app_name"))
        from native_release import launch_edition, omitted_sdk_prefixes, native_accounts_enabled
        offline_mvp = launch_edition(receipt) == "free_offline_mvp"
        if any(name.startswith(omitted_sdk_prefixes(receipt)) for name in receipt["prepared_files"]):
            raise ValueError("Free MVP snapshot must omit deferred native billing/auth SDKs")
        android_inputs = None
        if receipt["platform"] == "android":
            android_inputs = android_verification_inputs(args.upload_certificate_sha256, args.bundletool, args.jdk)
            if any(key not in receipt for key in ("bundle_id", "version", "build_number")):
                raise ValueError("Android candidate identity missing; prepare a fresh candidate before building")
        engine = subprocess.run([args.godot, "--version"], text=True, capture_output=True, check=False)
        version = engine.stdout.strip()
        if engine.returncode or not version.startswith(receipt["godot_version"]):
            raise ValueError(f"Exact Godot {receipt['godot_version']} required")
        if receipt["platform"] == "android":
            if not offline_mvp and not (project / "addons/GodotGooglePlayBilling/BillingClient.gd").is_file():
                raise ValueError("Pinned Android billing addon missing; install it before preparing")
            missing = [key for key in SIGNING_ENV if not os.environ.get(key)]
            if missing:
                raise ValueError("Missing release signing configuration: " + ", ".join(missing))
            if not Path(os.environ[SIGNING_ENV[0]]).is_file():
                raise ValueError("Configured Android release keystore file missing")
            if not (project / "android/build/build.gradle").is_file():
                raise ValueError("Android build template absent; supply --templates during prepare")
            from native_release import read_config
            android = read_config()["android"]
            prerequisites = (
                args.android_sdk / f"platforms/android-{android['target_sdk']}/android.jar",
                args.android_sdk / "build-tools" / android["build_tools"] / "apksigner",
                args.android_sdk / "ndk" / android["ndk_version"] / "source.properties",
            )
            if any(not path.is_file() for path in prerequisites):
                raise ValueError("Pinned Android SDK/build-tools/NDK missing; build will not install SDK components automatically")
            manifest = project / "android/build/src/main/AndroidManifest.xml"
            receipt["android_manifest_policy"] = {"path": str(manifest.relative_to(candidate)),
                                                  **apply_android_release_policy(manifest)}
            receipt["prepared_files"] = {str(p.relative_to(project)): sha256(p)
                                         for p in files_in_project(project)}
        elif not offline_mvp or native_accounts_enabled(receipt):
            plugin = project / "ios/plugins/WaddleStoreKit"
            if any(not (plugin / name).is_file() for name in ("WaddleStoreKit.gdip", "WaddleStoreKit.debug.a", "WaddleStoreKit.release.a", "waddle_build_receipt.json")):
                raise ValueError("Complete built WaddleStoreKit iOS plugin missing; build/install debug and release binaries before preparing")
            from install_ios_billing import verify_plugin
            lock = json.loads(Path(__file__).with_name("billing_plugins.lock.json").read_text())
            verify_plugin(plugin, lock)
        (candidate / "logs").mkdir(exist_ok=True)
        (project / "build/ios").mkdir(parents=True, exist_ok=True)
        receipt["state"] = "building"
        receipt["engine_version"] = version
        (candidate / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        # Editor import cannot run game autoloads. A temporary custom user path
        # also prevents accidental import-time tooling touching a player's save.
        settings_path = project / "project.godot"
        original_settings = settings_path.read_text()
        from native_release import replace_setting, godot_string
        isolated = replace_setting(original_settings, "application", "config/use_custom_user_dir", "true")
        isolated = replace_setting(isolated, "application", "config/custom_user_dir_name", godot_string("WaddleWarsNativeImport/" + receipt["source_sha256"][:16]))
        settings_path.write_text(isolated)
        try:
            run_checked([args.godot, "--headless", "--editor", "--path", str(project), "--import"], candidate / "logs/import.log")
        finally:
            settings_path.write_text(original_settings)
        # Restore real application identity before export: saves must survive
        # upgrades. No application entry point is run during export either.
        output = project / ("build/waddle-wars.aab" if receipt["platform"] == "android" else "build/ios/waddlewars.zip")
        run_checked([args.godot, "--headless", "--editor", "--path", str(project), "--export-release", receipt["preset_name"], str(output)], candidate / "logs/export.log")
        verify_ios_template_binding(candidate, receipt)
        if receipt["platform"] == "android" and not output.is_file():
            raise ValueError("Godot did not produce the expected AAB")
        if receipt["platform"] == "android":
            receipt["android_release_verification"] = verify_android_output(output, receipt, android_inputs)
        if receipt["platform"] == "ios":
            info_plist = output.parent / output.stem / f"{output.stem}-Info.plist"
            receipt["ios_plist_policy"] = {
                "path": str(info_plist.relative_to(candidate)),
                **apply_ios_permission_policy(info_plist),
            }
            receipt["ios_display_name_policy"] = {
                "path": str(info_plist.relative_to(candidate)),
                **apply_ios_display_name(info_plist, receipt["app_name"]),
            }
        outputs = sorted(path for path in (project / "build").rglob("*") if path.is_file())
        if not outputs:
            raise ValueError("No native export files produced")
        receipt["state"] = "android_upload_artifact_verified_offline" if receipt["platform"] == "android" else "exported_unverified"
        receipt["artifacts"] = {str(path.relative_to(candidate)): sha256(path) for path in outputs}
        receipt["import_metadata"] = collect_generated_import_metadata(
            project, receipt["prepared_files"], receipt["artifacts"], receipt["source_sha256"])
        receipt["store_ready"] = False
        (candidate / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        print(json.dumps({"state": receipt["state"], "store_ready": False, "artifacts": receipt["artifacts"]}, indent=2))
        return 0
    except (ValueError, OSError, KeyError) as error:
        receipt_path = candidate / "receipt.json"
        if receipt_path.is_file():
            attempted = json.loads(receipt_path.read_text())
            if attempted.get("state") == "building":
                attempted["state"] = "build_failed"
                receipt_path.write_text(json.dumps(attempted, indent=2) + "\n")
        print(f"build_native: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
