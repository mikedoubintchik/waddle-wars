#!/usr/bin/env python3
"""Unsigned native integration QA only: no Godot, game export, signing or upload.

Compile the exact official Android template with the pinned billing provider in
a fresh outside-checkout directory. This is not a runnable Waddle Wars build.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import time
import zipfile
import xml.etree.ElementTree as ET

from native_release import ROOT, read_config, sha256
from check_android_artifact import elf_failures

TEMPLATE_SHA256 = "ebbc49f2964cd6d1fdfe253ef7394631e7ca5ca471b87683bf69c446a53ac598"
BILLING_AAR_SHA256 = "b667b4ae3ecf91d7dea90bebd4ba5a7aef56cfc2cd7de4787aeb51a1927dcef7"
EXPORT_PLUGIN_SHA256 = "adeb55dc9b0894975f138f26303a5f9447caa92d74aee0afafb479c06e2648ee"
GRADLE_URL = r"https\://services.gradle.org/distributions/gradle-8.11.1-bin.zip"
PROVIDER_CLASS = "org.godotengine.plugin.googleplaybilling.GodotGooglePlayBilling"
PROVIDER_KEY = "org.godotengine.plugin.v2.GodotGooglePlayBilling"
ANDROID = "{http://schemas.android.com/apk/res/android}"
RESOLUTION_INIT = '''import groovy.json.JsonOutput
gradle.projectsEvaluated {
    def project = gradle.rootProject
    project.tasks.register('waddleIntegrationResolvedDependencies') {
        doLast {
            def artifacts = project.configurations.getByName('standardReleaseRuntimeClasspath')
                .resolvedConfiguration.resolvedArtifacts.collect { artifact ->
                    [group: artifact.moduleVersion.id.group,
                     name: artifact.moduleVersion.id.name,
                     version: artifact.moduleVersion.id.version,
                     file: artifact.file.canonicalPath]
                }
            new File(project.projectDir.parentFile, 'resolved_dependencies.json').text =
                JsonOutput.prettyPrint(JsonOutput.toJson(artifacts))
        }
    }
}
'''


def validate_destination(destination: Path) -> Path:
    if destination.is_symlink():
        raise ValueError("QA destination must not be a symlink")
    destination = destination.resolve()
    if destination.exists():
        raise ValueError("QA destination must be new; preserve prior logs/artifacts")
    source = ROOT.resolve()
    if destination == source or source in destination.parents:
        raise ValueError("QA destination must be outside the source checkout")
    return destination


def validate_inputs(templates: Path, sdk: Path, java: Path, *, include_billing: bool = True) -> dict:
    """Validate installed inputs without installing or accepting SDK licenses.

    Native billing integration/debug callers retain the strict historical
    default. The free launch exporter requests only template/SDK/JDK inputs;
    that result cannot be used as a native billing integration input set.
    """
    if type(include_billing) is not bool:
        raise ValueError("include_billing must be an explicit boolean")
    config = read_config()
    archive = templates / "android_source.zip"
    pinned = [(archive, TEMPLATE_SHA256)]
    billing = {}
    if include_billing:
        lock = json.loads((Path(__file__).with_name("billing_plugins.lock.json")).read_text())
        addon = ROOT / "addons/GodotGooglePlayBilling"
        aar = addon / "bin/release/GodotGooglePlayBilling-release.aar"
        pinned += [(aar, BILLING_AAR_SHA256), (addon / "export_plugin.gd", EXPORT_PLUGIN_SHA256)]
        billing = {"lock": lock, "aar": aar}
    version = templates / "version.txt"
    if not version.is_file() or version.read_text().strip() != config["godot_version"]:
        raise ValueError("Exact installed Godot template version required")
    for path, expected in pinned:
        if path.is_symlink() or not path.is_file() or sha256(path) != expected:
            raise ValueError(f"Pinned input missing or changed: {path.name}")
    if include_billing:
        installed = json.loads((addon / "waddle_install_receipt.json").read_text())
        for key in ("version", "sha256", "source_commit", "billing_library"):
            if installed.get(key) != lock["android"][key]:
                raise ValueError("Official billing installation receipt does not match lock")
    android = config["android"]
    required = (
        sdk / f"platforms/android-{android['target_sdk']}/android.jar",
        sdk / "build-tools" / android["build_tools"] / "apksigner",
        sdk / "ndk" / android["ndk_version"] / "source.properties",
        java / "bin/java",
    )
    if any(not path.is_file() for path in required):
        raise ValueError("Pinned SDK/build-tools/NDK/JDK missing; QA does not install or accept licenses")
    with zipfile.ZipFile(archive) as source:
        wrapper = source.read("gradle/wrapper/gradle-wrapper.properties").decode()
        if f"distributionUrl={GRADLE_URL}\n" not in wrapper:
            raise ValueError("Exact official Gradle 8.11.1 distribution required")
    return {"config": config, "archive": archive, "include_billing": include_billing, **billing,
            "pinned_input_hashes": {str(path): sha256(path) for path, _ in pinned}}


def extract_template(archive: Path, destination: Path) -> None:
    with zipfile.ZipFile(archive) as source:
        for entry in source.infolist():
            path = Path(entry.filename)
            if path.is_absolute() or ".." in path.parts or "\\" in entry.filename or ((entry.external_attr >> 16) & 0o170000) == 0o120000:
                raise ValueError("Unsafe Android template archive entry")
        source.extractall(destination)
    wrapper = destination / "gradlew"
    wrapper.chmod(wrapper.stat().st_mode | 0o100)
    # Godot normally creates this directory while exporting game resources.
    # The source ZIP omits empty directories; AGP still requires its presence
    # for the install-time asset-pack task even in this content-free QA build.
    (destination / "assetPackInstallTime/src/main/assets").mkdir(parents=True, exist_ok=True)


def build_environment(destination: Path, sdk: Path, java: Path) -> dict[str, str]:
    # Do not inherit payment tokens, release-key variables, global Gradle init
    # scripts/credentials, or Android-user settings. HOME itself is unchanged.
    environment = {key: os.environ[key] for key in ("PATH", "HOME", "TMPDIR", "LANG", "LC_ALL") if key in os.environ}
    environment.update({"JAVA_HOME": str(java), "ANDROID_HOME": str(sdk),
                        "ANDROID_SDK_ROOT": str(sdk),
                        "ANDROID_USER_HOME": str(destination / "android-user"),
                        "GRADLE_USER_HOME": str(destination / "gradle-user")})
    return environment


def gradle_command(destination: Path, inputs: dict) -> list[str]:
    if inputs.get("include_billing", True) is not True:
        raise ValueError("Native billing integration requires validated billing inputs")
    android = inputs["config"]["android"]
    return [str(destination / "template/gradlew"), "--no-daemon", "--max-workers=2", "--console=plain",
            "-Dorg.gradle.jvmargs=-Xmx2048m", "-Dorg.gradle.java.installations.auto-download=false",
            "-Pandroid.builder.sdkDownload=false", "-p", str(destination / "template"),
            "--init-script", str(destination / "resolved_dependencies.init.gradle"),
            "validateJavaVersion", "waddleIntegrationResolvedDependencies", "bundleStandardRelease",
            "-Pexport_package_name=" + inputs["config"]["bundle_id"],
            "-Pexport_version_code=1", "-Pexport_version_name=0.0.0",
            f"-Pexport_version_min_sdk={android['min_sdk']}", f"-Pexport_version_target_sdk={android['target_sdk']}",
            "-Pexport_enabled_abis=arm64-v8a", "-Pperform_signing=false", "-Pperform_zipalign=false",
            "-Pcompress_native_libraries=false",
            "-Pplugins_local_binaries=" + str(destination / "billing-release.aar"),
            "-Pplugins_remote_binaries=com.android.billingclient:billing-ktx:" + inputs["lock"]["android"]["billing_library"]]


def verify_dependencies(destination: Path, billing_version: str | None) -> list[dict]:
    destination = destination.resolve()
    artifacts = json.loads((destination / "resolved_dependencies.json").read_text())
    if not isinstance(artifacts, list):
        raise ValueError("Gradle resolved-dependency receipt must be an array")
    cache = (destination / "gradle-user").resolve()
    checked = []
    for artifact in artifacts:
        path = Path(artifact["file"]).resolve()
        if cache not in path.parents or not path.is_file():
            raise ValueError("Resolved Maven artifact outside the isolated Gradle cache")
        checked.append({"group": artifact["group"], "name": artifact["name"], "version": artifact["version"],
                        "path": str(path.relative_to(destination)), "sha256": sha256(path)})
    if billing_version is None:
        if any(item["group"] == "com.android.billingclient" for item in checked):
            raise ValueError("Free MVP debug build must not resolve Google Play Billing")
    else:
        for name in ("billing", "billing-ktx"):
            matches = [item for item in checked if item["group"] == "com.android.billingclient" and item["name"] == name]
            if len(matches) != 1 or matches[0]["version"] != billing_version:
                raise ValueError(f"Compiled provider dependency must resolve exactly {name}:{billing_version}")
    return checked


def dex_defines_class(data: bytes, descriptor: bytes) -> bool:
    """Require an actual class_def, not a descriptor string in another class."""
    if len(data) < 112 or data[:4] != b"dex\n" or data[7] != 0:
        return False
    strings, string_offset = struct.unpack_from("<II", data, 56)
    types, type_offset = struct.unpack_from("<II", data, 64)
    classes, class_offset = struct.unpack_from("<II", data, 96)
    if (string_offset + strings * 4 > len(data) or type_offset + types * 4 > len(data)
            or class_offset + classes * 32 > len(data)):
        return False
    for index in range(classes):
        type_index = struct.unpack_from("<I", data, class_offset + index * 32)[0]
        if type_index >= types:
            continue
        string_index = struct.unpack_from("<I", data, type_offset + type_index * 4)[0]
        if string_index >= strings:
            continue
        offset = struct.unpack_from("<I", data, string_offset + string_index * 4)[0]
        # Skip the ULEB128 UTF-16 length. Our class descriptor is ASCII.
        for _ in range(5):
            if offset >= len(data):
                break
            byte = data[offset]
            offset += 1
            if byte < 128:
                end = data.find(b"\0", offset)
                if end >= 0 and data[offset:end] == descriptor:
                    return True
                break
    return False


def verify_artifact(destination: Path, config: dict) -> dict:
    bundles = list((destination / "template/build/outputs/bundle/standardRelease").glob("*.aab"))
    if len(bundles) != 1:
        raise ValueError("Expected exactly one standardRelease AAB")
    bundle = bundles[0]
    with zipfile.ZipFile(bundle) as artifact:
        if artifact.testzip() is not None:
            raise ValueError("AAB ZIP checksum failed")
        names = artifact.namelist()
        if any(name.startswith("META-INF/") and name.upper().endswith((".RSA", ".DSA", ".EC", ".SF")) for name in names):
            raise ValueError("QA bundle unexpectedly signed")
        dex = [name for name in names if name.startswith("base/dex/") and name.endswith(".dex")]
        descriptor = ("L" + PROVIDER_CLASS.replace(".", "/") + ";").encode()
        if not any(dex_defines_class(artifact.read(name), descriptor) for name in dex):
            raise ValueError("Billing provider class missing from compiled DEX")
        libraries = [name for name in names if name.startswith("base/lib/") and name.endswith(".so")]
        if not libraries or any(not name.startswith("base/lib/arm64-v8a/") for name in libraries):
            raise ValueError("QA bundle must contain ARM64-only native libraries")
        alignment = {name: elf_failures(artifact.read(name)) for name in libraries}
    manifest_paths = list((destination / "template/build/intermediates/merged_manifests/standardRelease").rglob("AndroidManifest.xml"))
    if len(manifest_paths) != 1:
        raise ValueError("Expected exactly one Gradle merged standardRelease manifest")
    manifest = ET.parse(manifest_paths[0]).getroot()
    metadata = manifest.find(f"./application/meta-data[@{ANDROID}name='{PROVIDER_KEY}']")
    sdk = manifest.find("uses-sdk")
    if manifest.get("package") != config["bundle_id"] or metadata is None or metadata.get(ANDROID + "value") != PROVIDER_CLASS:
        raise ValueError("Merged manifest missing exact application/billing singleton identity")
    if sdk is None or sdk.get(ANDROID + "minSdkVersion") != str(config["android"]["min_sdk"]) or sdk.get(ANDROID + "targetSdkVersion") != str(config["android"]["target_sdk"]):
        raise ValueError("Merged manifest SDK levels differ from pinned launch config")
    if manifest.find(f"./uses-permission[@{ANDROID}name='com.android.vending.BILLING']") is None:
        raise ValueError("Merged manifest missing Google Play billing permission")
    return {"path": str(bundle.relative_to(destination)), "sha256": sha256(bundle), "bytes": bundle.stat().st_size,
            "unsigned": True, "compiled_provider_class": PROVIDER_CLASS,
            "merged_manifest": str(manifest_paths[0].relative_to(destination)),
            "merged_manifest_sha256": sha256(manifest_paths[0]), "dex_files": dex,
            "arm64_libraries_elf_findings": alignment,
            "android_16kb_structural_gate_passed": False,
            "android_16kb_packaging_checked": False}


def execute(destination: Path, inputs: dict, sdk: Path, java: Path) -> dict:
    destination.mkdir(parents=True)
    receipt_path = destination / "receipt.json"
    command = gradle_command(destination, inputs)
    receipt = {"schema_version": 1, "state": "building_native_integration_qa",
               "native_integration_only": True, "game_resources_exported": False,
               "store_ready": False, "signed": False, "device_tested": False,
               "billing_purchases_verified": False, "command": command,
               "pinned_input_hashes": inputs["pinned_input_hashes"],
               "dependencies": {"cache_initially_empty": True, "downloads_expected": True,
                                "scope": "Gradle8.11.1 plus AGP8.6.1/Kotlin2.1.21 and their official Maven dependencies, including Play Billing9.1.0; SDK/JDK auto-download disabled; no license acceptance"}}
    def save() -> None:
        receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
    save()
    try:
        extract_template(inputs["archive"], destination / "template")
        shutil.copy2(inputs["aar"], destination / "billing-release.aar")
        (destination / "resolved_dependencies.init.gradle").write_text(RESOLUTION_INIT)
        started = time.monotonic()
        with (destination / "gradle.log").open("w") as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT,
                                    env=build_environment(destination, sdk, java), check=False)
        receipt["elapsed_seconds"] = round(time.monotonic() - started, 3)
        receipt["exit_code"] = result.returncode
        if result.returncode:
            raise ValueError("Gradle integration failed; inspect preserved gradle.log")
        for path, digest in inputs["pinned_input_hashes"].items():
            if sha256(Path(path)) != digest:
                raise ValueError("Source template/addon changed during QA build")
        receipt["resolved_maven_artifacts"] = verify_dependencies(destination, inputs["lock"]["android"]["billing_library"])
        receipt["artifact"] = verify_artifact(destination, inputs["config"])
        receipt["state"] = "native_integration_compiled_qa_unverified"
        save()
        return receipt
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, ET.ParseError) as error:
        receipt["state"] = "native_integration_qa_failed"
        receipt["failure"] = str(error)
        save()
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--compile", action="store_true")
    parser.add_argument("--templates", type=Path, default=Path.home() / "Library/Application Support/Godot/export_templates/4.7.1.stable")
    parser.add_argument("--android-sdk", type=Path, default=Path.home() / "Library/Android/sdk")
    parser.add_argument("--java-home", type=Path, default=Path("/Applications/Android Studio.app/Contents/jbr/Contents/Home"))
    args = parser.parse_args()
    try:
        destination = validate_destination(args.destination)
        inputs = validate_inputs(args.templates.resolve(), args.android_sdk.resolve(), args.java_home.resolve())
        if not args.compile:
            print(json.dumps({"state": "plan_only_no_writes", "store_ready": False,
                              "command": gradle_command(destination, inputs),
                              "pinned_input_hashes": inputs["pinned_input_hashes"]}, indent=2))
            return 0
        receipt = execute(destination, inputs, args.android_sdk.resolve(), args.java_home.resolve())
        print(json.dumps({"state": receipt["state"], "store_ready": False,
                          "receipt": str(destination / "receipt.json"), "artifact": receipt["artifact"]}, indent=2))
        return 0
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, ET.ParseError) as error:
        print(f"build_android_integration_qa: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
