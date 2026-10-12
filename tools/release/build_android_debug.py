#!/usr/bin/env python3
"""Prepare/build a retained full-game Android DEBUG APK, never a store release.

Default invocation is read-only planning. --prepare creates a new snapshot;
--compile prepares and builds one. --build-prepared consumes an unattempted debug
snapshot. No device installation, release-key fallback, SDK/JDK installation,
license acceptance, key generation, or upload is implemented.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import zipfile
import xml.etree.ElementTree as ET

import build_android_integration_qa as integration
from build_native import ERRORS, verify_snapshot
from check_android_artifact import check as check_alignment
import native_release as native

ROOT = native.ROOT
PRESET = "Android Full Game Debug"
DEBUG_AAR_SHA256 = "f7f8f3f1c8099e58127332c8c27f353a7eea079e749682d2ebd83d1bd4bd6f3d"
ENGINE_VERSION = "4.7.1.stable.official.a13da4feb"
OUTPUT = "waddle-wars-debug.apk"
EDITOR_SETTINGS = Path.home() / "Library/Application Support/Godot/editor_settings-4.7.tres"
GAME_SUFFIXES = {".gd", ".tscn", ".tres", ".res", ".gdshader", ".gdshaderinc", ".glb",
                 ".gltf", ".png", ".jpg", ".jpeg", ".svg", ".ttf", ".otf", ".ogg", ".wav", ".json"}
BUILD_PROPERTIES = {
    "org.gradle.daemon": "false", "org.gradle.workers.max": "2",
    "org.gradle.jvmargs": "-Xmx2048m", "org.gradle.parallel": "false",
    "org.gradle.java.installations.auto-download": "false",
    "android.builder.sdkDownload": "false",
}
RESOLUTION_TASK = '''
// Waddle development-only receipt; never injected into canonical releases.
tasks.register('waddleDebugResolvedDependencies') {
    doLast {
        def artifacts = configurations.getByName('standardDebugRuntimeClasspath')
            .resolvedConfiguration.resolvedArtifacts.collect { artifact ->
                [group: artifact.moduleVersion.id.group,
                 name: artifact.moduleVersion.id.name,
                 version: artifact.moduleVersion.id.version,
                 file: artifact.file.canonicalPath]
            }
        new File(projectDir, '../../../resolved_dependencies.json').text =
            groovy.json.JsonOutput.prettyPrint(groovy.json.JsonOutput.toJson(artifacts))
    }
}
// AGP creates variant tasks after this script is evaluated. Configure matching
// future tasks lazily rather than looking up an as-yet unregistered task.
tasks.matching { it.name == 'assembleStandardDebug' }.configureEach {
    finalizedBy('waddleDebugResolvedDependencies')
}
'''


def configured_tools(settings: Path, sdk: Path, java: Path) -> dict[str, Path]:
    """Read only three path settings. Never parse passwords/aliases or key bytes."""
    wanted = {"export/android/debug_keystore", "export/android/android_sdk_path",
              "export/android/java_sdk_path"}
    paths: dict[str, Path] = {}
    with settings.open() as stream:
        for line in stream:
            match = re.match(r"^\s*(export/android/[a-z_]+)\s*=", line)
            if not match or match[1] not in wanted:
                continue
            if match[1] in paths:
                raise ValueError("Duplicate configured Android tool path")
            value = json.loads(line[match.end():].strip())
            if not isinstance(value, str) or not value or not Path(value).is_absolute():
                raise ValueError("Godot Android tool paths must already be configured and absolute")
            paths[match[1]] = Path(value)
    if paths.keys() != wanted:
        raise ValueError("Existing Godot Android SDK/JDK/debug-keystore configuration required")
    key = paths["export/android/debug_keystore"]
    if key.is_symlink() or not key.is_file() or not os.access(key, os.R_OK):
        raise ValueError("Configured existing debug keystore missing/unreadable; refusing engine import or key generation")
    if paths["export/android/android_sdk_path"].resolve() != sdk.resolve() or paths["export/android/java_sdk_path"].resolve() != java.resolve():
        raise ValueError("SDK/JDK arguments must match normally configured Godot editor paths")
    return paths


def validate_inputs(templates: Path, sdk: Path, java: Path, settings: Path = EDITOR_SETTINGS) -> dict:
    # Reuse exact installed template/release-addon/lock/SDK and official wrapper
    # checks. The debug AAR is a separately pinned input, not a release substitute.
    include_billing = native.launch_edition(native.read_config()) == "commerce"
    inputs = integration.validate_inputs(templates, sdk, java, include_billing=include_billing)
    aar = ROOT / "addons/GodotGooglePlayBilling/bin/debug/GodotGooglePlayBilling-debug.aar"
    if include_billing and (aar.is_symlink() or not aar.is_file() or native.sha256(aar) != DEBUG_AAR_SHA256):
        raise ValueError("Pinned billing debug AAR missing or changed")
    tools = sdk / "build-tools" / inputs["config"]["android"]["build_tools"]
    if any(not (tools / name).is_file() for name in ("zipalign", "aapt2", "apksigner")):
        raise ValueError("Installed artifact-verification tools missing; no SDK downloads permitted")
    configured_tools(settings, sdk, java)
    if include_billing:
        inputs["pinned_input_hashes"][str(aar)] = DEBUG_AAR_SHA256
    inputs.update({"debug_aar": aar, "templates": templates, "sdk": sdk, "java": java,
                   "editor_settings": settings})
    return inputs


def debug_preset(config: dict, version: str, build: int) -> str:
    copied = json.loads(json.dumps(config))
    copied["android"]["preset_name"] = PRESET
    preset = native.export_preset(copied, "android", version, build)
    for old, new in (("gradle_build/export_format=1", "gradle_build/export_format=0"),
                     ('export_path="build/waddle-wars.aab"', f'export_path="build/{OUTPUT}"')):
        if preset.count(old) != 1:
            raise ValueError("Canonical Android preset contract changed; review debug derivative")
        preset = preset.replace(old, new)
    return preset


def bounded_properties(text: str) -> str:
    for key, value in BUILD_PROPERTIES.items():
        pattern = rf"(?m)^\s*{re.escape(key)}\s*=.*$"
        replacement = f"{key}={value}"
        text = re.sub(pattern, replacement, text) if re.search(pattern, text) else text.rstrip() + "\n" + replacement + "\n"
    return text


def game_identity(settings: str) -> dict[str, str]:
    names = ("config/name", "run/main_scene", "config/use_custom_user_dir", "config/custom_user_dir_name",
             "renderer/rendering_method", "renderer/rendering_method.mobile", "window/handheld/orientation")
    identity = {}
    for name in names:
        match = re.search(rf"(?m)^{re.escape(name)}=(.*)$", settings)
        if match:
            identity[name] = match[1]
    return identity


def save_receipt(destination: Path, receipt: dict) -> None:
    (destination / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")


def prepare_debug(destination: Path, inputs: dict, version: str, build: int) -> dict:
    destination = integration.validate_destination(destination)
    configured_tools(inputs["editor_settings"], inputs["sdk"], inputs["java"])
    config = inputs["config"]
    identity = game_identity((ROOT / "project.godot").read_text())
    if identity.get("config/name") != native.godot_string(config["project_name"]) or identity.get("renderer/rendering_method.mobile") != '"gl_compatibility"':
        raise ValueError("Full-game application/mobile renderer identity differs from reviewed contract")
    preset = debug_preset(config, version, build)
    receipt = {"schema_version": 1, "state": "debug_preparing", "platform": "android",
               "purpose": "full_game_android_debug", "development_only": True, "store_ready": False,
               "game_resources_exported": False, "device_tested": False, "billing_purchases_verified": False}
    try:
        # Shared safe runtime copying, exact template extraction, billing-plugin
        # activation and version stamping; canonical helper itself is unchanged.
        prepared = native.prepare(ROOT, destination, config, "android", version, build, "", inputs["templates"])
        receipt.update(prepared)
        receipt["state"] = "debug_preparing"
        project = destination / "project"
        (project / "export_presets.cfg").write_text(preset)
        game = project / "scripts/utilities/game_config.gd"
        stamp = f"native-android-debug-{build}-{receipt['source_sha256'][:12]}"
        contents, count = re.subn(r'(?m)^const BUILD_ID: String = ".*"$', f'const BUILD_ID: String = "{stamp}"', game.read_text())
        if count != 1:
            raise ValueError("Exactly one game build-ID declaration required")
        game.write_text(contents)
        properties = project / "android/build/gradle.properties"
        properties.write_text(bounded_properties(properties.read_text()))
        gradle = project / "android/build/build.gradle"
        gradle.write_text(gradle.read_text() + RESOLUTION_TASK)
        # The template omits this empty asset-pack directory; AGP still validates
        # the configured subproject even when APK resources live in src/main/assets.
        (project / "android/build/assetPackInstallTime/src/main/assets").mkdir(parents=True, exist_ok=True)
        if game_identity((project / "project.godot").read_text()) != identity:
            raise ValueError("Preparation changed application/save/renderer identity")
        for path, digest in inputs["pinned_input_hashes"].items():
            if native.sha256(Path(path)) != digest:
                raise ValueError("Pinned input changed during debug preparation")
        receipt.update({"state": "debug_prepared_unbuilt", "preset_name": PRESET, "build_id": stamp,
                        "development_only": True, "store_ready": False, "identity": identity,
                        "game_resources_exported": False, "debug_signing": "existing_godot_editor_debug_configuration",
                        "pinned_input_hashes": inputs["pinned_input_hashes"],
                        "host_paths": {key: str(inputs[key]) for key in ("templates", "sdk", "java")},
                        "prepared_files": {str(path.relative_to(project)): native.sha256(path) for path in native.files_in_project(project)}})
        save_receipt(destination, receipt)
        return receipt
    except (OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        if destination.is_dir():
            receipt.update({"state": "debug_prepare_failed", "development_only": True,
                            "store_ready": False, "failure": str(error)})
            save_receipt(destination, receipt)
        raise


def build_environment(destination: Path, inputs: dict) -> dict[str, str]:
    return integration.build_environment(destination, inputs["sdk"], inputs["java"])


def run_checked(command: list[str], log: Path, env: dict[str, str], *, scan_errors: bool = True) -> str:
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, check=False)
    failed = bool(result.returncode or (scan_errors and ERRORS.search(result.stdout + result.stderr)))
    # Godot deliberately omits signing arguments from its verbose command log.
    # Defense in depth: redact argument-style keystore fields without extracting
    # configured password/alias values or reading the private key.
    def sanitize(value: str) -> str:
        return re.sub(r"(?i)(-P(?:debug|release)_keystore_(?:file|alias|password)=)(?:\"[^\"]*\"|[^\s]*)", r"\1<redacted>", value)
    log.with_suffix(".stdout.log").write_text(sanitize(result.stdout))
    log.with_suffix(".stderr.log").write_text(sanitize(result.stderr))
    if failed:
        raise ValueError(f"Debug build step failed (exit {result.returncode}); inspect {log.parent / log.stem}")
    return result.stdout


def export_command(destination: Path, godot: str) -> list[str]:
    return [godot, "--headless", "--editor", "--path", str(destination / "project"),
            "--export-debug", PRESET, str(destination / OUTPUT)]


def exported_path(artifact: zipfile.ZipFile, resource: str, names: set[str]) -> str:
    """Accept direct resources or Godot's exported/imported remap targets."""
    if resource.startswith("/") or ".." in Path(resource).parts:
        raise ValueError("Unsafe runtime resource path")
    direct = "assets/" + resource
    if direct in names and artifact.getinfo(direct).file_size:
        return direct
    for suffix in (".remap", ".import"):
        remap = direct + suffix
        if remap not in names:
            continue
        text = artifact.read(remap).decode("utf-8")
        for encoded in re.findall(r'(?m)^path(?:\.[A-Za-z0-9_]+)?=("(?:[^"\\]|\\.)*")\s*$', text):
            target = json.loads(encoded)
            if not target.startswith("res://") or ".." in Path(target[6:]).parts:
                raise ValueError("Unsafe exported resource remap")
            path = "assets/" + target[6:]
            if path in names and artifact.getinfo(path).file_size:
                return path
    raise ValueError(f"Full-game runtime resource missing from APK: {resource}")


def verify_game_resources(artifact: zipfile.ZipFile, project: Path, receipt: dict) -> dict:
    names = set(artifact.namelist())
    for required in ("assets/project.binary", "assets/assets.sparsepck", "assets/_cl_"):
        if required not in names or not artifact.getinfo(required).file_size:
            raise ValueError("APK missing Godot full-game project/index/launch data")
    staged = project / "android/build/src/main/assets"
    files = sorted(path for path in staged.rglob("*") if path.is_file())
    if not files:
        raise ValueError("Exported Godot game-resource staging missing")
    hashes = {}
    for path in files:
        if path.is_symlink():
            raise ValueError("Symlink in exported game resources")
        name = "assets/" + str(path.relative_to(staged))
        if name not in names or hashlib.sha256(artifact.read(name)).hexdigest() != native.sha256(path):
            raise ValueError(f"APK game resource differs from actual Godot export: {name}")
        hashes[name] = native.sha256(path)
    ignored = [Path(name).parent for name in receipt["source_files"] if Path(name).name == ".gdignore"]
    resources = [name for name in receipt["source_files"]
                 if Path(name).parts[0] in ("assets", "data", "scenes", "scripts")
                 and Path(name).suffix in GAME_SUFFIXES
                 and not any(folder == Path(name).parent or folder in Path(name).parents for folder in ignored)]
    required = {"scenes/ui/main.tscn", "scenes/gameplay/runner.tscn", "scenes/gameplay/race.tscn",
                "scripts/utilities/game_config.gd", "scripts/save/save_manager.gd"}
    if not required.issubset(resources):
        raise ValueError("Source snapshot is not the complete expected game")
    mapping = {resource: exported_path(artifact, resource, names) for resource in resources}
    # Private/non-runtime files must not be smuggled into an otherwise valid APK.
    for name in names:
        if name.startswith("assets/"):
            relative = Path(name[7:])
            if relative.suffix.lower() in native.PRIVATE_SUFFIXES or any(part.startswith(".env") for part in relative.parts):
                raise ValueError("Private signing/environment file included in APK resources")
    return {"source_resource_count": len(mapping), "packaged_staged_file_count": len(hashes),
            "exported_resources_sha256": hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest(),
            "runtime_resource_mapping": mapping}


def record_apk(destination: Path, receipt: dict) -> dict:
    apk = destination / OUTPUT
    if apk.is_symlink() or not apk.is_file():
        raise ValueError("Godot did not produce the expected regular DEBUG APK")
    previous = receipt.get("artifact", {})
    digest = native.sha256(apk)
    if previous.get("sha256") and previous["sha256"] != digest:
        raise ValueError("APK changed after export/verification; immutable-artifact retry required")
    report = {**previous, "path": OUTPUT, "sha256": digest, "bytes": apk.stat().st_size}
    receipt["artifact"] = report
    save_receipt(destination, receipt)
    return report


def verification_logs(destination: Path) -> Path:
    logs = destination / "logs"
    logs.mkdir(exist_ok=True)
    previous = [int(path.name.split("-")[1]) for path in logs.glob("verify-*")
                if path.is_dir() and re.fullmatch(r"verify-\d+", path.name)]
    attempt = logs / f"verify-{max(previous, default=0) + 1:03d}"
    attempt.mkdir()
    return attempt


def verify_artifact(destination: Path, inputs: dict, receipt: dict, env: dict) -> dict:
    report = record_apk(destination, receipt)
    apk = destination / OUTPUT
    config = inputs["config"]
    tools = inputs["sdk"] / "build-tools" / config["android"]["build_tools"]
    logs = verification_logs(destination)
    receipt["verification_log_directory"] = str(logs.relative_to(destination))
    run_checked([str(tools / "apksigner"), "verify", "--verbose", str(apk)], logs / "signature.log", env, scan_errors=False)
    report["signature_verified"] = True
    receipt["signed"] = True
    save_receipt(destination, receipt)
    badging = run_checked([str(tools / "aapt2"), "dump", "badging", str(apk)], logs / "apk_manifest.log", env, scan_errors=False)
    commerce = native.launch_edition(config) == "commerce"
    expected = (f"package: name='{config['bundle_id']}'", f"versionCode='{receipt['build_number']}'",
                f"versionName='{receipt['version']}'", f"minSdkVersion:'{config['android']['min_sdk']}'",
                f"targetSdkVersion:'{config['android']['target_sdk']}'", "application-debuggable")
    if (any(value not in badging for value in expected)
            or ("uses-permission: name='com.android.vending.BILLING'" in badging) != commerce):
        raise ValueError("Actual signed APK package/version/SDK/debug/edition manifest differs from debug contract")
    app_name = native.validate_app_name(receipt.get("app_name"))
    labels = re.findall(r"(?m)^application-label:'(.*)'\s*$", badging)
    if labels != [app_name]:
        raise ValueError("Actual signed APK default launcher label differs from prepared display title")
    report["app_name"] = app_name
    report["default_launcher_label_verified"] = True
    report["actual_apk_manifest_verified"] = True
    save_receipt(destination, receipt)
    project = destination / "project"
    manifests = list((project / "android/build/build/intermediates/merged_manifests/standardDebug").rglob("AndroidManifest.xml"))
    if len(manifests) != 1:
        raise ValueError("Expected exactly one merged standardDebug manifest")
    manifest = ET.parse(manifests[0]).getroot()
    metadata = manifest.find(f"./application/meta-data[@{integration.ANDROID}name='{integration.PROVIDER_KEY}']")
    if (manifest.get("package") != config["bundle_id"]
            or (metadata is not None) != commerce
            or (commerce and metadata.get(integration.ANDROID + "value") != integration.PROVIDER_CLASS)):
        raise ValueError("Merged DEBUG manifest differs from production identity/edition")
    with zipfile.ZipFile(apk) as artifact:
        names = artifact.namelist()
        if artifact.testzip() is not None or len(names) != len(set(names)):
            raise ValueError("APK ZIP checksum failed or duplicate entries present")
        libraries = [name for name in names if name.startswith("lib/") and name.endswith(".so")]
        if not libraries or any(not name.startswith("lib/arm64-v8a/") for name in libraries):
            raise ValueError("DEBUG full-game APK must include ARM64-only native libraries")
        if any(artifact.getinfo(name).compress_type != zipfile.ZIP_STORED for name in libraries):
            raise ValueError("DEBUG native libraries must remain uncompressed")
        descriptor = ("L" + integration.PROVIDER_CLASS.replace(".", "/") + ";").encode()
        dex = [name for name in names if re.fullmatch(r"classes(?:\d+)?\.dex", name)]
        provider_present = any(integration.dex_defines_class(artifact.read(name), descriptor) for name in dex)
        if provider_present != commerce:
            raise ValueError("Compiled APK billing provider differs from launch edition")
        game = verify_game_resources(artifact, project, receipt)
    report.update({"compiled_provider_class": integration.PROVIDER_CLASS if commerce else None,
                   "merged_manifest_sha256": native.sha256(manifests[0]), "game_resources": game,
                   "device_tested": False, "billing_purchases_verified": False})
    receipt["game_resources_exported"] = True
    save_receipt(destination, receipt)
    alignment = check_alignment(apk, zipalign=tools / "zipalign")
    report["android_16kb"] = alignment
    (logs / "android_16kb.json").write_text(json.dumps(alignment, indent=2) + "\n")
    save_receipt(destination, receipt)
    if not alignment["structural_gate_passed"]:
        raise ValueError("DEBUG APK failed 16-KB structural/packaging checks; preserve artifact for diagnosis")
    record_apk(destination, receipt)
    return report


def verify_built(destination: Path, inputs: dict) -> dict:
    """Retry verifier only against the same APK; never import or compile again."""
    if destination.is_symlink():
        raise ValueError("Debug candidate must not be a symlink")
    destination = destination.resolve()
    receipt = json.loads((destination / "receipt.json").read_text())
    if (receipt.get("state") not in ("debug_build_failed", "debug_verification_failed", "debug_exported_unverified")
            or receipt.get("purpose") != "full_game_android_debug" or receipt.get("development_only") is not True
            or receipt.get("store_ready") is not False or not receipt.get("artifact", {}).get("sha256")):
        raise ValueError("Verification retry requires an already-exported development-only immutable APK")
    if native.sha256(destination / OUTPUT) != receipt["artifact"]["sha256"]:
        raise ValueError("APK changed; verification-only retry refused")
    original_pins = receipt.get("pinned_input_hashes", {})
    if (not isinstance(original_pins, dict)
            or any(original_pins.get(path) != digest for path, digest in inputs["pinned_input_hashes"].items())
            or any(native.sha256(Path(path)) != digest for path, digest in original_pins.items())):
        raise ValueError("Pinned verification inputs changed")
    dependencies = destination / "resolved_dependencies.json"
    if receipt.get("resolved_dependencies_sha256") and native.sha256(dependencies) != receipt["resolved_dependencies_sha256"]:
        raise ValueError("Resolved dependency build receipt changed")
    history = receipt.setdefault("verification_attempts", [])
    history.append({"state": receipt["state"], "failure": receipt.get("failure"),
                    "logs": receipt.get("verification_log_directory"),
                    "artifact": json.loads(json.dumps(receipt["artifact"]))})
    try:
        billing_version = inputs["lock"]["android"]["billing_library"] if inputs["include_billing"] else None
        receipt["resolved_maven_artifacts"] = integration.verify_dependencies(destination, billing_version)
        receipt["resolved_dependencies_sha256"] = native.sha256(dependencies)
        receipt["artifact"] = verify_artifact(destination, inputs, receipt, build_environment(destination, inputs))
        receipt["state"] = "debug_exported_unverified"
        receipt.pop("failure", None)
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, ET.ParseError) as error:
        receipt.update({"state": "debug_verification_failed", "failure": str(error)})
        raise
    finally:
        receipt["store_ready"] = False
        receipt["development_only"] = True
        save_receipt(destination, receipt)
    return receipt


def build_prepared(destination: Path, inputs: dict, godot: str) -> dict:
    if destination.is_symlink():
        raise ValueError("Debug candidate must not be a symlink")
    destination = destination.resolve()
    receipt = json.loads((destination / "receipt.json").read_text())
    if (receipt.get("state") != "debug_prepared_unbuilt" or receipt.get("purpose") != "full_game_android_debug"
            or receipt.get("development_only") is not True or receipt.get("store_ready") is not False
            or receipt.get("preset_name") != PRESET):
        raise ValueError("Only a fresh development-only debug candidate can be built; preserve attempted/release candidates")
    if receipt.get("pinned_input_hashes") != inputs["pinned_input_hashes"] or receipt.get("host_paths") != {key: str(inputs[key]) for key in ("templates", "sdk", "java")}:
        raise ValueError("Debug preparation inputs/host paths changed; prepare a fresh candidate")
    project = destination / "project"
    verify_snapshot(project, receipt)
    configured_tools(inputs["editor_settings"], inputs["sdk"], inputs["java"])
    if game_identity((project / "project.godot").read_text()) != receipt["identity"]:
        raise ValueError("Debug candidate application/save identity changed")
    if (destination / "gradle-user").exists() or (destination / "android-user").exists():
        raise ValueError("Debug build caches must be new and isolated; preserve prior attempts")
    (destination / "logs").mkdir()
    env = build_environment(destination, inputs)
    receipt.update({"state": "debug_building", "command": export_command(destination, godot),
                    "dependencies": {"cache_initially_empty": True, "downloads_expected": True,
                                     "scope": "Official pinned Gradle8.11.1/Maven dependencies only; SDK/JDK downloads and license acceptance disabled"}})
    save_receipt(destination, receipt)
    started = time.monotonic()
    try:
        version = run_checked([godot, "--version"], destination / "logs/engine.log", env).strip()
        if version != ENGINE_VERSION:
            raise ValueError(f"Exact pinned official Godot {ENGINE_VERSION} required")
        receipt["engine_version"] = version
        settings = project / "project.godot"
        original = settings.read_text()
        isolated = native.replace_setting(original, "application", "config/use_custom_user_dir", "true")
        isolated = native.replace_setting(isolated, "application", "config/custom_user_dir_name",
                                         native.godot_string("WaddleWarsAndroidDebugImport/" + receipt["source_sha256"][:16]))
        configured_tools(inputs["editor_settings"], inputs["sdk"], inputs["java"])
        settings.write_text(isolated)
        try:
            run_checked([godot, "--headless", "--editor", "--path", str(project), "--import"], destination / "logs/import.log", env)
        finally:
            settings.write_text(original)
        configured_tools(inputs["editor_settings"], inputs["sdk"], inputs["java"])
        run_checked(export_command(destination, godot), destination / "logs/export.log", env)
        record_apk(destination, receipt)
        billing_version = inputs["lock"]["android"]["billing_library"] if inputs["include_billing"] else None
        receipt["resolved_maven_artifacts"] = integration.verify_dependencies(destination, billing_version)
        receipt["resolved_dependencies_sha256"] = native.sha256(destination / "resolved_dependencies.json")
        save_receipt(destination, receipt)
        receipt["artifact"] = verify_artifact(destination, inputs, receipt, env)
        if game_identity(settings.read_text()) != receipt["identity"]:
            raise ValueError("Export changed application/save identity")
        for path, digest in inputs["pinned_input_hashes"].items():
            if native.sha256(Path(path)) != digest:
                raise ValueError("Pinned input changed during DEBUG build")
        receipt.update({"state": "debug_exported_unverified", "game_resources_exported": True, "signed": True})
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, ET.ParseError) as error:
        receipt.update({"state": "debug_build_failed", "failure": str(error)})
        raise
    finally:
        receipt["elapsed_seconds"] = round(time.monotonic() - started, 3)
        receipt["development_only"] = True
        receipt["store_ready"] = False
        save_receipt(destination, receipt)
    return receipt


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--prepare", action="store_true")
    mode.add_argument("--compile", action="store_true")
    mode.add_argument("--build-prepared", action="store_true")
    mode.add_argument("--verify-built", action="store_true", help="Verifier-only retry of the same immutable APK; no compilation")
    parser.add_argument("--version", default="1.0.0")
    parser.add_argument("--build-number", type=int, default=1)
    parser.add_argument("--godot", default=shutil.which("godot") or "godot")
    parser.add_argument("--templates", type=Path, default=Path.home() / "Library/Application Support/Godot/export_templates/4.7.1.stable")
    parser.add_argument("--android-sdk", type=Path, default=Path.home() / "Library/Android/sdk")
    parser.add_argument("--java-home", type=Path, default=Path("/Applications/Android Studio.app/Contents/jbr/Contents/Home"))
    args = parser.parse_args()
    try:
        inputs = validate_inputs(args.templates.resolve(), args.android_sdk.resolve(), args.java_home.resolve())
        if args.verify_built:
            receipt = verify_built(args.destination, inputs)
        elif args.build_prepared:
            receipt = build_prepared(args.destination, inputs, args.godot)
        else:
            destination = integration.validate_destination(args.destination)
            debug_preset(inputs["config"], args.version, args.build_number)
            if not (args.prepare or args.compile):
                print(json.dumps({"state": "plan_only_no_writes", "development_only": True, "store_ready": False,
                                  "command": export_command(destination, args.godot),
                                  "pinned_input_hashes": inputs["pinned_input_hashes"], "existing_debug_signing_configured": True}, indent=2))
                return 0
            receipt = prepare_debug(destination, inputs, args.version, args.build_number)
            if args.compile:
                receipt = build_prepared(destination, inputs, args.godot)
        print(json.dumps({"state": receipt["state"], "development_only": True, "store_ready": False,
                          "receipt": str(args.destination.resolve() / "receipt.json"),
                          "artifact": receipt.get("artifact", {}).get("path")}, indent=2))
        return 0
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, ET.ParseError) as error:
        print(f"build_android_debug: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
