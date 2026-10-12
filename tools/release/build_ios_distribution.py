#!/usr/bin/env python3
"""Local manual archive/IPA using existing signing identity; never upload.

Input receipt, profile and public certificate pins are explicit. Fresh outputs
are retained. No provisioning updates, profile/key generation, account login,
Keychain password reads or private-key export are implemented. Xcode performs
ordinary authorized code signing; separate read-only artifact gates accept it.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import stat
import subprocess
import sys

import native_release as native
from verify_ios_profile import inspect_signed_profile
from verify_ios_artifact import verify_archive, verify_ipa, _candidate as verify_candidate

ROOT = native.ROOT
PROFILE_NAME = "Waddle Wars App Store"
IDENTITY_TOOL = Path("/usr/bin/security")
OWN_SOURCE = Path(__file__).absolute()
SENSITIVE_DIAGNOSTIC = re.compile(r"account|credential|token|password|secret|cookie|authorization|session", re.I)
MAX_RECEIPT_BYTES = 8 * 1024 * 1024


def read_json(path: Path) -> dict:
    regular(path)
    if path.stat().st_size > MAX_RECEIPT_BYTES:
        raise ValueError("Receipt exceeds metadata size bound")
    def unique(pairs: list) -> dict:
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("Duplicate receipt JSON key")
            result[key] = value
        return result
    result = json.loads(path.read_bytes(), object_pairs_hook=unique)
    if not isinstance(result, dict):
        raise ValueError("Receipt object required")
    return result


def relative_files(mapping: dict) -> dict:
    if not isinstance(mapping, dict) or not mapping or len(mapping) > 16384:
        raise ValueError("Bounded immutable file inventory required")
    for name, value in mapping.items():
        if (not isinstance(name, str) or not name or name.startswith("/") or "\\" in name
                or len(name) > 1024 or any(part in ("", ".", "..") for part in name.split("/"))):
            raise ValueError("Unsafe relative file inventory path")
        pin(value)
    return mapping


def safe(path: Path) -> Path:
    if not path.is_absolute() or ".." in path.parts or any(p.is_symlink() for p in (path, *path.parents)):
        raise ValueError("Explicit absolute nonsymlink path required")
    return path


def regular(path: Path, *, executable: bool = False) -> Path:
    safe(path)
    if not path.is_file() or not stat.S_ISREG(path.stat().st_mode) or (executable and not os.access(path, os.X_OK)):
        raise ValueError("Required regular file/executable absent")
    return path


def digest(path: Path) -> str:
    return native.sha256(regular(path))


def pin(value: str, length: int = 64) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"[0-9a-fA-F]{" + str(length) + "}", value):
        raise ValueError("Explicit public hash pin required")
    return value.lower()


def owned_run(run: Path) -> Path:
    safe(run)
    if run == ROOT or ROOT in run.parents or not run.is_dir():
        raise ValueError("Existing outside-checkout run directory required")
    info = run.stat()
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise ValueError("Run directory must be owned and mode0700")
    return run


def environment() -> dict[str, str]:
    # Preserve actual HOME/TMPDIR; no unrelated credentials or tool-option injection.
    env = {k: os.environ[k] for k in ("HOME", "USER", "LOGNAME", "TMPDIR") if k in os.environ}
    env.update(PATH="/usr/bin:/bin:/usr/sbin:/sbin", LANG="C", LC_ALL="C", TZ="UTC")
    return env


def write_json(path: Path, value: dict, *, first: bool = False) -> None:
    safe(path)
    flags = os.O_WRONLY | os.O_NOFOLLOW | (os.O_CREAT | os.O_EXCL if first else os.O_TRUNC)
    if not first:
        regular(path)
    with os.fdopen(os.open(path, flags, 0o600), "w") as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())


def snapshot(paths: list[Path]) -> dict[str, str]:
    return {str(p): digest(p) for p in paths}


def unchanged(hashes: dict[str, str]) -> None:
    if not isinstance(hashes, dict) or not hashes or len(hashes) > 20000:
        raise ValueError("Nonempty bounded pinned input inventory required")
    for name, value in hashes.items():
        if not isinstance(name, str):
            raise ValueError("Pinned input path required")
        safe(Path(name))
        pin(value)
    if snapshot([Path(p) for p in hashes]) != hashes:
        raise ValueError("Pinned release input changed during operation")


def candidate_hashes(candidate: Path, receipt_sha256: str, source_sha256: str) -> tuple[dict, dict[str, str]]:
    safe(candidate)
    if candidate == ROOT or ROOT in candidate.parents:
        raise ValueError("Candidate must be outside checkout")
    receipt_path = candidate / "receipt.json"
    if digest(receipt_path) != pin(receipt_sha256):
        raise ValueError("Export receipt public pin changed")
    receipt = read_json(receipt_path)
    config = native.read_config()
    if (not isinstance(receipt, dict) or receipt.get("state") != "exported_unverified"
            or receipt.get("platform") != "ios" or receipt.get("store_ready") is not False
            or receipt.get("source_sha256") != pin(source_sha256)
            or receipt.get("bundle_id") != config["bundle_id"] or receipt.get("app_name") != native.launcher_name(config, "ios")
            or not re.fullmatch(r"\d+\.\d+\.\d+", str(receipt.get("version", "")))
            or type(receipt.get("build_number")) is not int or not 1 <= receipt["build_number"] <= 2100000000):
        raise ValueError("Expected current iOS export identity/state required")
    hashes = {str(receipt_path): receipt_sha256.lower()}
    verified = verify_candidate(candidate)
    if verified["receipt"] != receipt or verified["receipt_sha256"] != receipt_sha256.lower():
        raise ValueError("Candidate verification identity mismatch")
    supplement = candidate / "import-metadata.json"
    if supplement.exists():
        hashes[str(supplement)] = digest(supplement)
    for field, base in (("prepared_files", candidate / "project"), ("artifacts", candidate)):
        inventory = relative_files(receipt.get(field))
        for name, expected in inventory.items():
            if (not isinstance(name, str) or "\\" in name or not name or name.startswith("/")
                    or any(part in ("", ".", "..") for part in name.split("/"))
                    or (field == "artifacts" and not name.startswith("project/build/ios/"))):
                raise ValueError("Unsafe export inventory path")
            path = base / name
            if digest(path) != pin(expected):
                raise ValueError("Export snapshot changed")
            hashes[str(path)] = expected.lower()
    for name, value in verified["project_files"].items():
        hashes[str(candidate / "project" / name)] = value
    info = candidate / "project/build/ios/waddlewars/waddlewars-Info.plist"
    values = plistlib.loads(regular(info).read_bytes())
    if values.get("CFBundleDisplayName") != receipt["app_name"]:
        raise ValueError("Exported display title mismatch")
    return receipt, hashes


def checked_public(command: list[str]) -> str:
    result = subprocess.run(command, env=environment(), capture_output=True, text=True, timeout=60, check=False)
    if result.returncode or len(result.stdout.encode()) + len(result.stderr.encode()) > 1024 ** 2:
        raise ValueError("Public preflight command failed; raw diagnostics discarded")
    return result.stdout


def signing_identity_available(certificate_sha1: str) -> None:
    # Metadata only. Do not request a password or extract a private key.
    output = checked_public([str(IDENTITY_TOOL), "find-identity", "-v", "-p", "codesigning"])
    pattern = r'^\s*\d+\)\s+' + re.escape(pin(certificate_sha1, 40).upper()) + r'\s+"[^\r\n]+"\s*$'
    if len(re.findall(pattern, output, re.M)) != 1:
        raise ValueError("Exact existing valid signing identity unavailable")


def build_step(command: list[str], log: Path, success_marker: str) -> dict:
    """One bounded local Xcode child group; all raw output stays out of model."""
    safe(log)
    if log.exists():
        raise ValueError("Existing build log refused")
    started = datetime.now(timezone.utc).isoformat()
    child = subprocess.Popen(command, env=environment(), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True, start_new_session=True)
    print("Local Xcode process PID: " + str(child.pid), flush=True)
    timed_out = False
    try:
        output, _ = child.communicate(timeout=1200)
    except subprocess.TimeoutExpired:
        timed_out = True
        try:
            os.killpg(child.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            output, _ = child.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            output, _ = child.communicate(timeout=10)
    # Xcode can consult its normally configured account during local export.
    # Suppress account/token diagnostics completely, not only email fragments.
    redacted = sum(bool(SENSITIVE_DIAGNOSTIC.search(line)) for line in output.splitlines())
    clean = "\n".join("<redacted-xcode-account-diagnostic>" if SENSITIVE_DIAGNOSTIC.search(line) else line
                      for line in output.splitlines()) + "\n"
    with os.fdopen(os.open(log, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600), "w") as stream:
        stream.write(clean)
    result = {"started_at_utc": started, "ended_at_utc": datetime.now(timezone.utc).isoformat(),
              "exit_code": child.returncode, "timed_out": timed_out,
              "success_marker_seen": any(line.strip() == success_marker for line in output.splitlines()),
              "redacted_account_diagnostic_lines": redacted, "log_sha256": digest(log)}
    if child.returncode or timed_out or not result["success_marker_seen"]:
        raise ValueError("Local Xcode step failed; outputs/log preserved")
    return result


def tools(xcodebuild: Path, cms_helper: Path) -> list[Path]:
    regular(xcodebuild, executable=True)
    regular(cms_helper, executable=True)
    paths = [OWN_SOURCE, xcodebuild, cms_helper, IDENTITY_TOOL, Path(sys.executable).resolve()]
    paths += [OWN_SOURCE.with_name(name) for name in (
        "verify_ios_artifact.py", "verify_ios_profile.py", "native_release.py", "native_release.json")]
    paths += [Path("/usr/bin") / name for name in ("codesign", "lipo", "otool", "strings")]
    return paths


def archive(candidate: Path, run: Path, *, receipt_sha256: str, source_sha256: str, team_id: str,
            certificate_sha1: str, certificate_sha256: str, installed_profile: Path, profile_sha256: str,
            cms_helper: Path, cms_helper_sha256: str, xcodebuild: Path) -> dict:
    owned_run(run)
    if not re.fullmatch(r"[A-Z0-9]{10}", team_id):
        raise ValueError("Explicit real Apple team required")
    certificate_sha1 = pin(certificate_sha1, 40).upper()
    certificate_sha256 = pin(certificate_sha256)
    if digest(installed_profile) != pin(profile_sha256) or digest(cms_helper) != pin(cms_helper_sha256):
        raise ValueError("Pinned existing profile/helper changed")
    exported, frozen = candidate_hashes(candidate, receipt_sha256, source_sha256)
    frozen.update(snapshot([*tools(xcodebuild, cms_helper), installed_profile]))
    profile = inspect_signed_profile(installed_profile, cms_helper=cms_helper, cms_helper_sha256=cms_helper_sha256,
                                     team_id=team_id, app_id=exported["bundle_id"],
                                     certificate_sha1=certificate_sha1, profile_name=PROFILE_NAME)
    expected_profile = {"state": "profile_signature_and_metadata_verified", "profile_eligible_for_archive": True,
                        "team_id": team_id, "app_id": exported["bundle_id"], "profile_name": PROFILE_NAME,
                        "matched_certificate_sha1": certificate_sha1, "matched_certificate_sha256": certificate_sha256,
                        "mobileprovision_sha256": profile_sha256.lower()}
    if (not isinstance(profile, dict) or any(type(profile.get(key)) is not type(value) or profile.get(key) != value
                                            for key, value in expected_profile.items())
            or not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", str(profile.get("profile_uuid", "")))):
        raise ValueError("Verified existing profile/signer identity mismatch")
    signing_identity_available(certificate_sha1)
    version = checked_public([str(xcodebuild), "-version"])
    if not re.match(r"\AXcode 26\.\d+(?:\.\d+)?\nBuild version [A-Za-z0-9]+\s*\Z", version):
        raise ValueError("Reviewed Xcode26 toolchain required")
    build = exported["build_number"]
    archive_path = run / f"WaddleWars-build{build}.xcarchive"
    result_path = run / f"Archive-build{build}.xcresult"
    derived = run / "DerivedData"
    record_path = run / "archive-invocation.json"
    gate_path = run / "archive-verification-receipt.json"
    log = run / "archive.log"
    for destination in (archive_path, result_path, derived, record_path, gate_path, log, run / "archive-verification"):
        safe(destination)
        if destination.exists():
            raise ValueError("Fresh archive destinations required; previous attempt preserved")
    command = [str(xcodebuild), "-project", str(candidate / "project/build/ios/waddlewars.xcodeproj"),
               "-scheme", "waddlewars", "-configuration", "Release", "-destination", "generic/platform=iOS",
               "-jobs", "2", "-archivePath", str(archive_path), "-derivedDataPath", str(derived),
               "-resultBundlePath", str(result_path), "archive", "CODE_SIGN_STYLE=Manual",
               "DEVELOPMENT_TEAM=" + team_id, "CODE_SIGN_IDENTITY=" + certificate_sha1,
               "PROVISIONING_PROFILE_SPECIFIER=" + profile["profile_uuid"]]
    record = {"state": "archiving", "command": command, "source_sha256": exported["source_sha256"],
              "app_name": exported["app_name"], "version": exported["version"], "build_number": build,
              "candidate": str(candidate), "candidate_receipt_sha256": receipt_sha256.lower(),
              "archive_path": str(archive_path), "profile": profile, "input_sha256": frozen,
              "cms_helper": str(cms_helper), "cms_helper_sha256": cms_helper_sha256.lower(),
              "store_ready": False, "uploaded": False, "automatic_provisioning": False,
              "new_key_or_profile_created": False, "private_key_read_or_export_requested": False}
    write_json(record_path, record, first=True)
    try:
        unchanged(frozen)
        record["xcode_archive"] = build_step(command, log, "** ARCHIVE SUCCEEDED **")
        unchanged(frozen)
        gate = verify_archive(candidate, archive_path, run / "archive-verification", team_id=team_id,
                              certificate_sha1=certificate_sha1, certificate_sha256=certificate_sha256,
                              installed_profile=installed_profile, profile_sha256=profile_sha256,
                              cms_helper=cms_helper, cms_helper_sha256=cms_helper_sha256)
        if gate.get("signed_archive_verified") is not True or gate.get("store_ready") is not False:
            raise ValueError("Archive artifact gate did not accept")
        unchanged(frozen)
        write_json(gate_path, gate, first=True)
        record.update(state="ios_archive_verified_offline", archive_verification_receipt_sha256=digest(gate_path))
        write_json(record_path, record)
        return record
    except Exception as error:
        record.update(state="ios_archive_failed_preserved", error_type=type(error).__name__, store_ready=False)
        write_json(record_path, record)
        raise


def ipa(run: Path, *, archive_receipt_sha256: str, cms_helper: Path, cms_helper_sha256: str,
        xcodebuild: Path) -> dict:
    owned_run(run)
    archive_receipt = run / "archive-verification-receipt.json"
    if digest(archive_receipt) != pin(archive_receipt_sha256):
        raise ValueError("Verified archive receipt pin changed")
    source = read_json(archive_receipt)
    invocation_path = run / "archive-invocation.json"
    invocation = read_json(invocation_path)
    if (not isinstance(source, dict) or source.get("signed_archive_verified") is not True
            or source.get("store_ready") is not False or invocation.get("state") != "ios_archive_verified_offline"
            or invocation.get("archive_verification_receipt_sha256") != archive_receipt_sha256.lower()
            or invocation.get("cms_helper") != str(cms_helper)
            or invocation.get("cms_helper_sha256") != pin(cms_helper_sha256)):
        raise ValueError("Only the matching verified archive may be exported")
    config = native.read_config()
    if (source.get("state") != "signed_archive_verified"
            or source.get("app_name") != native.launcher_name(config, "ios") or source.get("bundle_id") != config["bundle_id"]
            or not re.fullmatch(r"\d+\.\d+\.\d+", str(source.get("version", "")))
            or type(source.get("build_number")) is not int or not 1 <= source["build_number"] <= 2100000000
            or not re.fullmatch(r"[A-Z0-9]{10}", str(source.get("team_id", "")))
            or not isinstance(source.get("profile"), dict)
            or not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", str(source["profile"].get("profile_uuid", "")))
            or any(source.get(key) != invocation.get(key) for key in ("source_sha256", "app_name", "version", "build_number"))):
        raise ValueError("Verified archive identity/recipe mismatch")
    pin(source["source_sha256"])
    pin(source.get("signer_certificate_sha1"), 40)
    pin(source.get("signer_certificate_sha256"))
    previous_profile = invocation.get("profile")
    if (not isinstance(previous_profile, dict)
            or source["profile"].get("profile_uuid") != previous_profile.get("profile_uuid")
            or source["team_id"] != previous_profile.get("team_id")
            or source["bundle_id"] != previous_profile.get("app_id")
            or source["signer_certificate_sha1"] != previous_profile.get("matched_certificate_sha1")
            or source["signer_certificate_sha256"] != previous_profile.get("matched_certificate_sha256")):
        raise ValueError("Archive signer/team/profile differs from pinned invocation")
    archive_path = safe(Path(source["archive_path"]))
    if archive_path != run / f"WaddleWars-build{source['build_number']}.xcarchive" or archive_path != Path(invocation["archive_path"]):
        raise ValueError("Archive paths mismatch")
    export_path = run / "ipa-export"
    options_path = run / "export-options.plist"
    record_path = run / "ipa-invocation.json"
    gate_path = run / "ipa-verification-receipt.json"
    log = run / "ipa-export.log"
    for destination in (export_path, options_path, record_path, gate_path, log, run / "ipa-verification"):
        safe(destination)
        if destination.exists():
            raise ValueError("Fresh IPA destinations required; previous attempt preserved")
    frozen = snapshot([*tools(xcodebuild, cms_helper), archive_receipt, invocation_path])
    unchanged(invocation["input_sha256"])
    for name, expected in relative_files(source.get("archive_app_file_sha256")).items():
        path = archive_path / "Products/Applications/waddlewars.app" / name
        if digest(path) != pin(expected):
            raise ValueError("Verified archive app changed before export")
        frozen[str(path)] = expected
    options = {"destination": "export", "method": "app-store-connect", "signingStyle": "manual",
               "teamID": source["team_id"], "signingCertificate": source["signer_certificate_sha1"],
               "provisioningProfiles": {source["bundle_id"]: source["profile"]["profile_uuid"]},
               "manageAppVersionAndBuildNumber": False, "generateAppStoreInformation": False, "uploadSymbols": False}
    with os.fdopen(os.open(options_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600), "wb") as stream:
        stream.write(plistlib.dumps(options, fmt=plistlib.FMT_XML, sort_keys=True))
    frozen[str(options_path)] = digest(options_path)
    command = [str(xcodebuild), "-exportArchive", "-archivePath", str(archive_path),
               "-exportPath", str(export_path), "-exportOptionsPlist", str(options_path)]
    record = {"state": "exporting_ipa", "command": command, "source_sha256": source["source_sha256"],
              "version": source["version"], "build_number": source["build_number"],
              "archive_receipt_sha256": archive_receipt_sha256.lower(), "input_sha256": frozen,
              "destination": "export", "store_ready": False, "uploaded": False,
              "automatic_provisioning": False, "new_key_or_profile_created": False}
    write_json(record_path, record, first=True)
    try:
        unchanged(frozen)
        record["xcode_export"] = build_step(command, log, "** EXPORT SUCCEEDED **")
        unchanged(frozen)
        output = regular(export_path / "waddlewars.ipa")
        output_sha256 = digest(output)
        gate = verify_ipa(output, archive_path, archive_receipt, run / "ipa-verification",
                          ipa_sha256=output_sha256, archive_receipt_sha256=archive_receipt_sha256,
                          cms_helper=cms_helper, cms_helper_sha256=cms_helper_sha256)
        if gate.get("ipa_verified") is not True or gate.get("store_ready") is not False:
            raise ValueError("IPA artifact gate did not accept")
        unchanged(frozen)
        unchanged(invocation["input_sha256"])
        if digest(output) != output_sha256:
            raise ValueError("IPA changed during verification")
        write_json(gate_path, gate, first=True)
        record.update(state="ios_ipa_verified_offline", artifact={"path": str(output), "sha256": output_sha256,
                      "bytes": output.stat().st_size}, ipa_verification_receipt_sha256=digest(gate_path))
        write_json(record_path, record)
        return record
    except Exception as error:
        record.update(state="ios_ipa_failed_preserved", error_type=type(error).__name__, store_ready=False)
        write_json(record_path, record)
        raise


def main() -> int:
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest="mode", required=True)
    first = modes.add_parser("archive")
    first.add_argument("candidate", type=Path)
    first.add_argument("run", type=Path)
    for name in ("receipt-sha256", "source-sha256", "team-id", "certificate-sha1", "certificate-sha256", "profile-sha256"):
        first.add_argument("--" + name, required=True)
    first.add_argument("--installed-profile", type=Path, required=True)
    second = modes.add_parser("ipa")
    second.add_argument("run", type=Path)
    second.add_argument("--archive-receipt-sha256", required=True)
    for mode in (first, second):
        mode.add_argument("--cms-helper", type=Path, required=True)
        mode.add_argument("--cms-helper-sha256", required=True)
        mode.add_argument("--xcodebuild", type=Path, required=True)
    args = vars(parser.parse_args())
    mode = args.pop("mode")
    try:
        result = archive(**args) if mode == "archive" else ipa(**args)
        print(json.dumps({k: result.get(k) for k in ("state", "source_sha256", "build_number", "artifact", "store_ready", "uploaded")}, indent=2))
        return 0
    except Exception as error:
        print("build_ios_distribution failed: " + type(error).__name__ + "; outputs preserved", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
