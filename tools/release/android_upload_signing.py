#!/usr/bin/env python3
"""First app-specific Android upload key and secret-free local release launcher.

No upload, browser, credential discovery, installation, or Play registration.
Only the Swift bridge touches the exact Waddle Keychain password. Godot exports
unsigned; jarsigner receives its password through a child-only environment.
"""
from __future__ import annotations

import argparse
import getpass
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys

APP = "Waddle Wars: Penguin Panic"
BUNDLE = "com.blubberandbyte.waddlewars"
SERVICE = BUNDLE + ".android.upload"
ACCOUNT = ALIAS = "waddlewars-upload-v1"
ROOT = Path(__file__).absolute().parents[2]
SWIFT_SOURCE = Path(__file__).with_name("android_upload_keychain.swift").absolute()
BUILD_SCRIPT = Path(__file__).with_name("build_android_upload.py").absolute()
OWN_SOURCE = Path(__file__).absolute()
STAGES = {"validating", "checking_keychain", "creating_keychain_password", "generating_upload_key",
          "copying_encrypted_backup", "exporting_public_certificate", "reading_app_specific_keychain_password",
          "signing_aab", "complete"}
HELPER_STATES = {"item_exists", "item_absent", "bootstrap_complete", "sign_complete", "operation_failed"}


class SigningError(ValueError):
    """Only fixed public messages; never raw tool output or exception text."""


def signing_directory() -> Path:
    return Path.home() / "Library/Application Support/WaddleWarsSigning" / BUNDLE / "android-upload-v1"


def safe_path(path: Path) -> Path:
    if not path.is_absolute() or ".." in path.parts:
        raise SigningError("Absolute paths without traversal required")
    for component in (path, *path.parents):
        if component.is_symlink():
            raise SigningError("Symlinks are not allowed")
    return path


def regular(path: Path, *, executable: bool = False, private: bool = False) -> Path:
    safe_path(path)
    if not path.is_file() or not stat.S_ISREG(path.stat().st_mode):
        raise SigningError("Required regular file missing")
    info = path.stat()
    if executable and not os.access(path, os.X_OK):
        raise SigningError("Required executable is not executable")
    if private and (info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600):
        raise SigningError("Private signing files require owner and mode 0600")
    return path


def private_directory(path: Path, *, create: bool = False) -> Path:
    safe_path(path)
    if create and not path.exists():
        path.mkdir(mode=0o700)
    info = path.stat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise SigningError("App-owned signing directories require owner and mode 0700")
    return path


def outside_checkout(path: Path) -> Path:
    safe_path(path)
    if path == ROOT or ROOT in path.parents:
        raise SigningError("Signing and candidates must remain outside checkout")
    return path


def digest(path: Path) -> str:
    regular(path)
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def snapshot(paths: list[Path]) -> dict[str, str]:
    return {str(path): digest(path) for path in paths}


def unchanged(before: dict[str, str]) -> None:
    if snapshot([Path(path) for path in before]) != before:
        raise SigningError("Signing tool/source changed during operation")


def write_receipt(path: Path, value: dict, *, first: bool = False) -> None:
    safe_path(path)
    if first:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    else:
        regular(path, private=True)
        descriptor = os.open(path, os.O_WRONLY | os.O_TRUNC | os.O_NOFOLLOW)
    with os.fdopen(descriptor, "w") as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())


def clean_environment(jdk: Path, *, cache: Path | None = None, sdk: Path | None = None) -> dict[str, str]:
    # No signing variables, Java option injection, unrelated service tokens, or
    # inherited Gradle configuration. HOME preserves normal installed tools.
    result = {key: os.environ[key] for key in ("HOME", "USER", "LOGNAME", "TMPDIR") if key in os.environ}
    result.update(PATH=str(jdk / "bin") + ":/usr/bin:/bin", LANG="C", LC_ALL="C", TZ="UTC", JAVA_HOME=str(jdk))
    if cache is not None:
        result.update(GRADLE_USER_HOME=str(cache), GRADLE_OPTS="-Dorg.gradle.daemon=false -Dorg.gradle.workers.max=2 -Dorg.gradle.jvmargs=-Xmx2048m -Dorg.gradle.configuration-cache=false")
    if sdk is not None:
        result.update(ANDROID_HOME=str(sdk), ANDROID_SDK_ROOT=str(sdk))
    return result


def run_public(command: list[str], environment: dict[str, str], label: str) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(command, env=environment, capture_output=True, text=True, check=False)
    except (OSError, subprocess.SubprocessError):
        raise SigningError(label + " could not run; raw diagnostics discarded") from None


def helper_call(helper: Path, arguments: list[str], environment: dict[str, str]) -> dict:
    result = run_public([str(helper), *arguments], environment, "App-specific Keychain helper")
    try:
        response = json.loads(result.stdout)
        if (not isinstance(response, dict) or set(response) != {"state", "stage", "keychain_password_created", "key_generated", "backup_verified"}
                or response["state"] not in HELPER_STATES or response["stage"] not in STAGES
                or any(type(response[key]) is not bool for key in ("keychain_password_created", "key_generated", "backup_verified"))
                or bool(result.returncode) != (response["state"] == "operation_failed")):
            raise ValueError()
        return response
    except (ValueError, TypeError, KeyError):
        raise SigningError("Invalid Keychain helper response; raw diagnostics discarded") from None


def jdk_tools(jdk: Path) -> list[Path]:
    safe_path(jdk)
    if not jdk.is_dir():
        raise SigningError("Explicit existing JDK directory required")
    return [regular(jdk / "bin" / name, executable=True) for name in ("java", "keytool", "jarsigner")]


def setup(jdk: Path, swiftc: Path) -> dict:
    destination = outside_checkout(signing_directory())
    # First-key-only. Existing failed or completed outputs are never reused.
    if destination.exists():
        raise SigningError("Signing destination already exists; preserve it and review manually")
    tools = jdk_tools(jdk)
    regular(swiftc, executable=True)
    before = snapshot([SWIFT_SOURCE, OWN_SOURCE, swiftc, *tools])
    # Only exact app-owned subdirectories are created/checked. Existing broad
    # Library/Application Support permissions are never changed.
    private_directory(destination.parent.parent, create=True)
    private_directory(destination.parent, create=True)
    destination.mkdir(mode=0o700)
    private_directory(destination)
    for name in ("primary", "backup"):
        private_directory(destination / name, create=True)
    receipt_path = destination / "receipt.json"
    receipt = {"schema_version": 1, "app_name": APP, "bundle_id": BUNDLE,
               "service": SERVICE, "account": ACCOUNT, "alias": ALIAS, "state": "setup_started",
               "play_registered": False, "off_device_recovery": False,
               "backup_warning": "Two encrypted local copies share this Mac. Keychain password and local backup alone are not independent off-device recovery.",
               "tool_sha256": before}
    write_receipt(receipt_path, receipt, first=True)
    helper = destination / "keychain-helper"
    try:
        compiled = run_public([str(swiftc), str(SWIFT_SOURCE), "-framework", "Security", "-framework", "LocalAuthentication", "-o", str(helper)], clean_environment(jdk), "Swift compilation")
        if compiled.returncode:
            raise SigningError("Swift compilation failed; raw diagnostics discarded")
        regular(helper, executable=True)
        helper.chmod(0o700)
        unchanged(before)
        response = helper_call(helper, ["probe"], clean_environment(jdk))
        if response["state"] != "item_absent":
            raise SigningError("Exact app-specific Keychain item exists or could not be checked; nothing overwritten")
        unchanged(before)
        response = helper_call(helper, ["bootstrap", str(jdk / "bin/keytool"), str(destination / "primary/upload.p12"),
                                       str(destination / "backup/upload.p12"), str(destination / "upload-cert.der")], clean_environment(jdk))
        receipt["helper_result"] = response
        if response["state"] != "bootstrap_complete" or not all(response[key] for key in ("keychain_password_created", "key_generated", "backup_verified")):
            raise SigningError("Signing bootstrap failed; preserve outputs and exact Keychain item for manual recovery")
        key = regular(destination / "primary/upload.p12", private=True)
        backup = regular(destination / "backup/upload.p12", private=True)
        certificate = regular(destination / "upload-cert.der", private=True)
        if not key.stat().st_size or key.read_bytes() != backup.read_bytes():
            raise SigningError("Encrypted key backup mismatch")
        data = certificate.read_bytes()
        if not 128 <= len(data) <= 16384 or data[0] != 0x30:
            raise SigningError("Public DER certificate missing or invalid")
        unchanged(before)
        receipt.update(state="intended_not_registered", setup_state="complete", encrypted_key_sha256=digest(key),
                       encrypted_backup_sha256=digest(backup), upload_certificate_sha256=digest(certificate),
                       helper_sha256=digest(helper))
        write_receipt(receipt_path, receipt)
        return receipt
    except (SigningError, OSError):
        receipt["state"] = "setup_failed"
        receipt["setup_state"] = "failed_preserved_no_automatic_retry"
        write_receipt(receipt_path, receipt)
        raise


def load_signing_receipt() -> tuple[Path, dict]:
    destination = outside_checkout(signing_directory())
    private_directory(destination)
    regular(destination / "receipt.json", private=True)
    try:
        receipt = json.loads((destination / "receipt.json").read_text())
    except (ValueError, OSError):
        raise SigningError("Signing receipt unreadable") from None
    if (not isinstance(receipt, dict) or not isinstance(receipt.get("tool_sha256"), dict)
            or receipt.get("state") != "intended_not_registered" or receipt.get("setup_state") != "complete"
            or any(receipt.get(key) != value for key, value in {"app_name": APP, "bundle_id": BUNDLE, "service": SERVICE,
                                                              "account": ACCOUNT, "alias": ALIAS}.items())
            or receipt.get("play_registered") is not False):
        raise SigningError("Exact app-specific first-key receipt required")
    for path, field in ((destination / "primary/upload.p12", "encrypted_key_sha256"),
                        (destination / "backup/upload.p12", "encrypted_backup_sha256"),
                        (destination / "upload-cert.der", "upload_certificate_sha256")):
        regular(path, private=True)
        if digest(path) != receipt.get(field):
            raise SigningError("Retained signing material changed")
    helper = regular(destination / "keychain-helper", executable=True)
    if helper.stat().st_uid != os.getuid() or stat.S_IMODE(helper.stat().st_mode) != 0o700 or digest(helper) != receipt.get("helper_sha256"):
        raise SigningError("Retained Keychain helper changed or permissions unsafe")
    if digest(SWIFT_SOURCE) != receipt.get("tool_sha256", {}).get(str(SWIFT_SOURCE)):
        raise SigningError("Keychain helper source changed; review signing workflow before reuse")
    return destination, receipt


def build(candidate: Path, *, jdk: Path, bundletool: Path, godot: Path, sdk: Path,
          python: Path, version: str, build_number: int,
          vault_passphrase: str | None = None) -> dict:
    outside_checkout(candidate)
    destination, signing = load_signing_receipt()
    if candidate.exists() or candidate == destination or destination in candidate.parents:
        raise SigningError("Fresh outside-checkout candidate required")
    if not re.fullmatch(r"\d+\.\d+\.\d+", version) or type(build_number) is not int or not 1 <= build_number <= 2100000000:
        raise SigningError("Explicit valid version and unused build number required")
    tools = jdk_tools(jdk)
    for path in (bundletool, godot, python, BUILD_SCRIPT):
        regular(path, executable=path in (godot, python))
    if bundletool.suffix != ".jar" or not safe_path(sdk).is_dir():
        raise SigningError("Explicit installed bundletool JAR and Android SDK required")
    sources = [OWN_SOURCE, SWIFT_SOURCE, BUILD_SCRIPT, Path(__file__).with_name("native_release.py").absolute(),
               Path(__file__).with_name("verify_android_release.py").absolute(),
               Path(__file__).with_name("check_android_artifact.py").absolute()]
    vault = None
    vault_password = None
    vault_sha256 = None
    if vault_passphrase is not None:
        import android_password_vault as vault
        sources.append(vault.OWN_SOURCE)
        vault_password, vault_sha256 = vault.unlock(destination, signing, vault_passphrase)
        vault.validate_password(jdk, vault_password, destination, signing)
    before = snapshot([*sources, *tools, bundletool, godot, python])
    # The credential-free exporter creates/uses this exact owned cache. Do not
    # precreate candidate (prepare requires it absent) or an unused sibling.
    cache = candidate / "gradle-user"
    launcher_receipt_path = candidate.with_name(candidate.name + "-signing-launch.json")
    outside_checkout(cache)
    if launcher_receipt_path.exists():
        raise SigningError("Existing release launch state refused; preserve previous attempt")
    safe_path(candidate.parent)
    if not candidate.parent.is_dir():
        raise SigningError("Candidate parent must already exist")
    receipt = {"schema_version": 1, "state": "exporting_unsigned", "app_name": APP, "bundle_id": BUNDLE,
               "version": version, "build_number": build_number, "candidate": str(candidate),
               "upload_certificate_sha256": signing["upload_certificate_sha256"], "tool_sha256": before,
               "store_ready": False, "play_registered": False,
               "signing_password_transport": ("encrypted_local_vault_to_jarsigner_child_environment"
                                              if vault is not None else "jarsigner_child_environment_only"),
               "gradle_user_home": str(cache), "off_device_recovery": False}
    if vault_sha256 is not None:
        receipt["encrypted_vault_sha256"] = vault_sha256
    write_receipt(launcher_receipt_path, receipt, first=True)
    environment = clean_environment(jdk, cache=cache, sdk=sdk)
    common = [str(python), str(BUILD_SCRIPT)]
    proof = ["--jdk", str(jdk), "--bundletool", str(bundletool), "--upload-certificate-sha256", signing["upload_certificate_sha256"]]
    try:
        export = run_public([*common, "export", str(candidate), "--version", version, "--build-number", str(build_number),
                             "--godot", str(godot), "--android-sdk", str(sdk), *proof], environment, "Unsigned Android export")
        if export.returncode:
            raise SigningError("Unsigned Android export failed; preserve candidate logs")
        build_receipt = json.loads(regular(candidate / "receipt.json").read_text())
        if (not isinstance(build_receipt, dict)
                or build_receipt.get("state") != "android_unsigned_awaiting_upload_signature"
                or build_receipt.get("bundle_id") != BUNDLE or build_receipt.get("app_name") != APP):
            raise SigningError("Unsigned candidate identity/state mismatch")
        private_directory(cache)
        unsigned = regular(candidate / "project/build/waddle-wars.aab")
        retained_unsigned = unsigned.with_name("waddle-wars-unsigned.aab")
        if retained_unsigned.exists():
            raise SigningError("Retained unsigned output already exists")
        private_directory(unsigned.parent)
        unsigned.rename(retained_unsigned)
        receipt.update(state="signing_upload_candidate", unsigned_sha256=digest(retained_unsigned))
        write_receipt(launcher_receipt_path, receipt)
        unchanged(before)
        load_signing_receipt()
        if vault is None:
            response = helper_call(destination / "keychain-helper", ["sign", str(jdk / "bin/jarsigner"), str(retained_unsigned),
                                      str(unsigned), str(destination / "primary/upload.p12")], clean_environment(jdk))
        else:
            if digest(vault.vault_path(destination)) != vault_sha256:
                raise SigningError("Encrypted password file changed during export")
            response = vault.sign_aab(jdk, destination, retained_unsigned, unsigned, vault_password)
        receipt["helper_result"] = response
        if response["state"] != "sign_complete":
            raise SigningError("Upload signing failed; preserve unsigned and partial signed outputs")
        if digest(retained_unsigned) != receipt["unsigned_sha256"]:
            raise SigningError("Unsigned payload changed during signing")
        receipt["state"] = "verifying_signed_candidate"
        write_receipt(launcher_receipt_path, receipt)
        verified = run_public([*common, "verify", str(candidate), *proof], environment, "Android offline release verification")
        if verified.returncode:
            raise SigningError("Offline Android release verification failed; preserve candidate logs")
        final = json.loads(regular(candidate / "receipt.json").read_text())
        if (not isinstance(final, dict) or final.get("state") != "android_upload_artifact_verified_offline"
                or final.get("store_ready") is not False):
            raise SigningError("Android final verification state mismatch")
        unchanged(before)
        load_signing_receipt()
        receipt.update(state="android_upload_artifact_verified_offline", signed_aab_sha256=digest(unsigned))
        write_receipt(launcher_receipt_path, receipt)
        return receipt
    except (SigningError, OSError, ValueError):
        receipt["state"] = "launch_failed_preserved_no_automatic_retry"
        write_receipt(launcher_receipt_path, receipt)
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest="mode", required=True)
    first = modes.add_parser("setup", help="Create first app-specific upload key, never overwrite existing state")
    first.add_argument("--jdk", type=Path, required=True)
    first.add_argument("--swiftc", type=Path, required=True)
    release = modes.add_parser("build", help="Unsigned export, existing-key jarsigner, mandatory offline verifier")
    release.add_argument("candidate", type=Path)
    for name in ("jdk", "bundletool", "godot", "android-sdk", "python"):
        release.add_argument("--" + name, type=Path, required=True)
    release.add_argument("--version", required=True)
    release.add_argument("--build-number", type=int, required=True)
    release.add_argument("--direct-p12-vault", action="store_true",
                         help="Prompt for local encrypted vault passphrase; no Keychain password read")
    args = parser.parse_args()
    os.umask(0o077)
    try:
        if args.mode == "setup":
            receipt = setup(args.jdk, args.swiftc)
        else:
            vault_passphrase = (getpass.getpass("Android signing vault passphrase: ")
                                if args.direct_p12_vault else None)
            receipt = build(args.candidate, jdk=args.jdk, bundletool=args.bundletool, godot=args.godot,
                            sdk=args.android_sdk, python=args.python, version=args.version,
                            build_number=args.build_number, vault_passphrase=vault_passphrase)
        print(json.dumps({key: receipt[key] for key in ("state", "app_name", "bundle_id", "play_registered", "off_device_recovery")}, indent=2))
        return 0
    except SigningError as error:
        print("android_upload_signing: " + str(error), file=sys.stderr)
    except (OSError, ValueError, KeyError, TypeError):
        print("android_upload_signing: operation failed; outputs preserved, raw diagnostics discarded", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
