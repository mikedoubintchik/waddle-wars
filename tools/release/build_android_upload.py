#!/usr/bin/env python3
"""Credential-free unsigned release export, then verify externally signed AAB.

The macOS app-specific upload-key launcher signs between these two operations.
Godot/Gradle never receive release credentials. An unsigned export is not a
successful signed build. All final acceptance uses the existing release gate.
No keys, devices, SDK installation, store requests or uploads are implemented.
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
import zipfile

import build_android_integration_qa as integration
import native_release as native
from build_android_debug import bounded_properties
from build_native import android_verification_inputs, apply_android_release_policy, run_checked, verify_snapshot
from verify_android_release import verify, regular_file

OUTPUT = Path("project/build/waddle-wars.aab")
UNSIGNED = Path("project/build/waddle-wars-unsigned.aab")
PURPOSE = "android_external_upload_signature"
ENGINE = "4.7.1.stable.official.a13da4feb"
SIGNED_METADATA = re.compile(r"META-INF/(?:MANIFEST\.MF|[A-Z0-9_-]{1,8}\.(?:SF|RSA|DSA|EC))")


def artifact_payload(path: Path, *, unsigned: bool = False) -> dict[str, str]:
    regular_file(path, "Android bundle")
    if path.stat().st_size > 1024 ** 3:
        raise ValueError("Bundle size exceeds supported bound")
    hashes = {}
    seen = set()
    with zipfile.ZipFile(path) as archive:
        infos = archive.infolist()
        if not infos or len(infos) > 50000 or sum(i.file_size for i in infos) > 2 * 1024 ** 3:
            raise ValueError("Bundle expanded inventory exceeds supported bound")
        for item in infos:
            name = item.filename
            if (not re.fullmatch(r"[!-~]{1,1024}", name) or "\\" in name
                    or any(p in ("", ".", "..") for p in name.rstrip("/").split("/"))
                    or name.casefold() in seen or item.flag_bits & 1
                    or ((item.external_attr >> 16) & 0o170000) not in (0, 0o100000, 0o040000)
                    or (((item.external_attr >> 16) & 0o170000) == 0o040000 and not item.is_dir())
                    or (((item.external_attr >> 16) & 0o170000) == 0o100000 and item.is_dir())
                    or item.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED)):
                raise ValueError("Unsafe or duplicate bundle inventory")
            seen.add(name.casefold())
            if SIGNED_METADATA.fullmatch(name):
                if unsigned:
                    raise ValueError("Godot unsigned export unexpectedly has signature metadata")
                continue
            if item.is_dir():
                if item.file_size:
                    raise ValueError("Bundle directory has payload bytes")
                continue
            with archive.open(item) as stream:
                hashes[name] = hashlib.file_digest(stream, "sha256").hexdigest()
    if not hashes:
        raise ValueError("Bundle has no payload")
    return hashes


def tools_hashes(jdk: Path, bundletool: Path, *, include_billing: bool = True) -> dict[str, str]:
    paths = [jdk / "bin" / n for n in ("java", "keytool", "jarsigner")]
    paths += [bundletool, Path(__file__).resolve(), *[
        Path(__file__).with_name(n) for n in (
            "native_release.py", "build_native.py", "build_android_debug.py",
            "build_android_integration_qa.py", "verify_android_release.py",
            "check_android_artifact.py", "native_release.json")]]
    if include_billing:
        paths.append(Path(__file__).with_name("billing_plugins.lock.json"))
    return {str(p): native.sha256(regular_file(p, "Release tool")) for p in paths}


def check_hashes(hashes: dict) -> None:
    if not hashes:
        raise ValueError("Release input hashes missing")
    for name, digest in hashes.items():
        if native.sha256(regular_file(Path(name), "Release input")) != digest:
            raise ValueError("Release input changed; preserve candidate and prepare again")


def save(candidate: Path, receipt: dict) -> None:
    (candidate / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")


def runtime_unchanged(candidate: Path, receipt: dict) -> None:
    names = receipt.get("source_files")
    if (not isinstance(names, dict) or not names or "project.godot" not in names
            or any(not isinstance(name, str) for name in names)):
        raise ValueError("Original runtime inventory missing")
    edition = native.launch_edition(receipt)
    omitted = receipt.get("omitted_deferred_sdk_files", {})
    prepared = receipt.get("prepared_files")
    if not isinstance(omitted, dict) or not isinstance(prepared, dict):
        raise ValueError("Prepared runtime/omitted SDK inventory missing")
    if edition == "free_offline_mvp":
        expected = {name: digest for name, digest in names.items() if name.startswith(native.DEFERRED_SDK_PREFIXES)}
        if (omitted != expected
                or any(not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest)
                       or name in prepared for name, digest in omitted.items())):
            raise ValueError("Free MVP SDK omissions must match exact original source hashes and permitted SDK prefixes")
    elif omitted:
        raise ValueError("Commerce runtime must not omit native SDK files")
    project = candidate / "project"
    for name in names:
        path = Path(name)
        if (path.is_absolute() or ".." in path.parts or "\\" in name
                or (name != "project.godot" and not any(
                    name.startswith(prefix + "/") for prefix in native.RUNTIME_DIRS))
                or path.suffix.lower() in native.PRIVATE_SUFFIXES):
            raise ValueError("Unsafe runtime inventory path")
        for parent in (project / path, *(project / path).parents):
            if parent.is_symlink():
                raise ValueError("Symlink in runtime inventory")
            if parent == project:
                break
        if name in omitted:
            if (project / path).exists():
                raise ValueError("Free MVP omitted native SDK file is present in prepared runtime")
            continue
        current = regular_file(project / path, "Prepared runtime")
        if native.sha256(current) != receipt["prepared_files"].get(name):
            raise ValueError("Prepared runtime changed during release operation")


def export(candidate: Path, *, version: str, build: int, jdk: Path,
           bundletool: Path, pin: str, sdk: Path, templates: Path, godot: str) -> dict:
    if not candidate.is_absolute() or ".." in candidate.parts:
        raise ValueError("Explicit absolute candidate path required")
    candidate = integration.validate_destination(candidate)
    public = android_verification_inputs(pin, bundletool, jdk)
    config = native.read_config()
    include_billing = native.launch_edition(config) == "commerce"
    inputs = integration.validate_inputs(templates, sdk, jdk, include_billing=include_billing)
    if inputs["config"] != config or inputs["include_billing"] is not include_billing:
        raise ValueError("Release configuration changed during input validation")
    hashes = tools_hashes(jdk, bundletool, include_billing=include_billing)
    receipt = native.prepare(native.ROOT, candidate, inputs["config"], "android", version, build, "", templates)
    receipt.update({"purpose": PURPOSE, "state": "android_unsigned_preparing",
                    "signed": False, "upload_certificate_sha256": public["upload_certificate_sha256"],
                    "tool_sha256": hashes, "pinned_input_hashes": inputs["pinned_input_hashes"],
                    "native_billing_build_inputs_included": include_billing,
                    "host_paths": {"jdk": str(jdk), "bundletool": str(bundletool)},
                    "device_tested": False, "billing_purchases_verified": False})
    try:
        project = candidate / "project"
        presets = project / "export_presets.cfg"
        text = presets.read_text()
        if text.count("package/signed=true") != 1:
            raise ValueError("Reviewed Android signing preset changed")
        presets.write_text(text.replace("package/signed=true", "package/signed=false"))
        properties = project / "android/build/gradle.properties"
        properties.write_text(bounded_properties(properties.read_text()))
        (project / "android/build/assetPackInstallTime/src/main/assets").mkdir(parents=True, exist_ok=True)
        manifest = project / "android/build/src/main/AndroidManifest.xml"
        receipt["android_manifest_policy"] = {"path": str(manifest.relative_to(candidate)),
                                              **apply_android_release_policy(manifest)}
        receipt["prepared_files"] = {str(p.relative_to(project)): native.sha256(p)
                                     for p in native.files_in_project(project)}
        receipt["state"] = "android_unsigned_building"
        save(candidate, receipt)
        verify_snapshot(project, receipt)
        logs = candidate / "logs"
        logs.mkdir()
        env = integration.build_environment(candidate, sdk, jdk)
        version_result = subprocess.run([godot, "--version"], env=env, text=True, capture_output=True, check=False)
        if version_result.returncode or version_result.stdout.strip() != ENGINE:
            raise ValueError("Exact reviewed Godot engine required")
        settings = project / "project.godot"
        original = settings.read_text()
        isolated = native.replace_setting(original, "application", "config/use_custom_user_dir", "true")
        isolated = native.replace_setting(isolated, "application", "config/custom_user_dir_name",
                                         native.godot_string("WaddleWarsUploadImport/" + receipt["source_sha256"][:16]))
        settings.write_text(isolated)
        try:
            run_checked([godot, "--headless", "--editor", "--path", str(project), "--import"], logs / "import.log", env=env)
        finally:
            settings.write_text(original)
        output = candidate / OUTPUT
        output.parent.mkdir(parents=True, exist_ok=True)
        run_checked([godot, "--headless", "--editor", "--path", str(project), "--export-release",
                     receipt["preset_name"], str(output)], logs / "unsigned-export.log", env=env)
        # The signature may add only signature metadata, not replace game bytes.
        receipt["unsigned_payload_sha256"] = artifact_payload(output, unsigned=True)
        receipt["unsigned_artifact_sha256"] = native.sha256(output)
        runtime_unchanged(candidate, receipt)
        check_hashes(hashes)
        check_hashes(inputs["pinned_input_hashes"])
        receipt["state"] = "android_unsigned_awaiting_upload_signature"
        receipt["unsigned_path"] = str(output)
        receipt["game_resources_exported"] = True
        save(candidate, receipt)
        return receipt
    except Exception:
        receipt.update({"state": "android_unsigned_export_failed", "signed": False, "store_ready": False})
        save(candidate, receipt)
        raise


def verify_candidate(candidate: Path, *, jdk: Path, bundletool: Path, pin: str) -> dict:
    if not candidate.is_absolute() or candidate.is_symlink() or not candidate.is_dir():
        raise ValueError("Explicit regular candidate directory required")
    receipt = json.loads(regular_file(candidate / "receipt.json", "Candidate receipt").read_text())
    if (receipt.get("purpose") != PURPOSE or receipt.get("state") != "android_unsigned_awaiting_upload_signature"
            or receipt.get("store_ready") is not False or receipt.get("signed") is not False
            or receipt.get("host_paths") != {"jdk": str(jdk), "bundletool": str(bundletool)}):
        raise ValueError("Only matching unverified external-signing candidates may be verified")
    public = android_verification_inputs(pin, bundletool, jdk)
    if public["upload_certificate_sha256"] != receipt.get("upload_certificate_sha256"):
        raise ValueError("Intended public upload identity changed")
    try:
        runtime_unchanged(candidate, receipt)
        check_hashes(receipt["tool_sha256"])
        check_hashes(receipt["pinned_input_hashes"])
        retained = regular_file(candidate / UNSIGNED, "Retained unsigned bundle")
        if native.sha256(retained) != receipt["unsigned_artifact_sha256"]:
            raise ValueError("Retained unsigned export changed")
        output = regular_file(candidate / OUTPUT, "Signed Android bundle")
        output_hash = native.sha256(output)
        if artifact_payload(output) != receipt["unsigned_payload_sha256"]:
            raise ValueError("Signing changed exported game payload")
        result = verify(output, artifact_sha256=output_hash,
                        upload_certificate_sha256=public["upload_certificate_sha256"],
                        package=receipt["bundle_id"], version=receipt["version"],
                        build_number=receipt["build_number"], bundletool=bundletool, jdk=jdk,
                        launch_edition=native.launch_edition(receipt))
        check_hashes(receipt["tool_sha256"])
        check_hashes(receipt["pinned_input_hashes"])
        runtime_unchanged(candidate, receipt)
        if native.sha256(retained) != receipt["unsigned_artifact_sha256"] or native.sha256(output) != output_hash:
            raise ValueError("Bundle changed during mandatory verification")
        receipt.update({"state": "android_upload_artifact_verified_offline", "signed": True,
                        "android_release_verification": result,
                        "artifact": {"path": str(OUTPUT), "sha256": native.sha256(output),
                                     "bytes": output.stat().st_size}, "store_ready": False})
        save(candidate, receipt)
        return receipt
    except Exception:
        receipt.update({"state": "android_upload_verification_failed", "store_ready": False})
        save(candidate, receipt)
        raise


def main() -> int:
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("export", "verify"))
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--jdk", type=Path, required=True)
    parser.add_argument("--bundletool", type=Path, required=True)
    parser.add_argument("--upload-certificate-sha256", required=True)
    parser.add_argument("--version", default="1.0.0")
    parser.add_argument("--build-number", type=int, default=3)
    parser.add_argument("--godot", default=shutil.which("godot") or "godot")
    parser.add_argument("--android-sdk", type=Path, default=Path.home() / "Library/Android/sdk")
    parser.add_argument("--templates", type=Path, default=Path.home() / "Library/Application Support/Godot/export_templates/4.7.1.stable")
    args = parser.parse_args()
    try:
        if args.mode == "export":
            receipt = export(args.candidate, version=args.version, build=args.build_number, jdk=args.jdk,
                             bundletool=args.bundletool, pin=args.upload_certificate_sha256, sdk=args.android_sdk,
                             templates=args.templates, godot=args.godot)
        else:
            receipt = verify_candidate(args.candidate, jdk=args.jdk, bundletool=args.bundletool,
                                       pin=args.upload_certificate_sha256)
        print(json.dumps({"state": receipt["state"], "store_ready": False,
                          "unsigned_path": receipt.get("unsigned_path"), "artifact": receipt.get("artifact")}))
        return 0
    except Exception as error:
        # No inherited secrets/provider paths/tool output in error messages.
        print("build_android_upload failed: " + type(error).__name__, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
