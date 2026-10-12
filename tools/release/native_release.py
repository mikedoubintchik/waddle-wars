#!/usr/bin/env python3
"""Prepare isolated native release projects; inspect host without changing it.

No automatic upload, certificate discovery, signing-key creation, or deployment.
Preparation deliberately leaves native purchases unavailable until the actual
billing integration is present and verified. A prepared project is not a release.
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

ROOT = Path(__file__).resolve().parents[2]
CONFIG = Path(__file__).with_name("native_release.json")
RUNTIME_DIRS = ("assets", "data", "scenes", "scripts", "addons", "ios/plugins", "android/plugins")
PRIVATE_SUFFIXES = {
    ".key", ".p8", ".pk8", ".pkcs8", ".ppk", ".keystore", ".jks",
    ".p12", ".pfx", ".pem", ".mobileprovision", ".provisionprofile", ".csr",
}
EXCLUDE_FILTER = (
    "tests/*,qa_shots/*,art_src/*,native/*,tools/*,build/*,docs/*,*.blend,"
    ".envrc,.env*,*.key,*.p8,*.pk8,*.pkcs8,*.ppk,*.keystore,*.jks,*.p12,"
    "*.pfx,*.pem,*.mobileprovision,*.provisionprofile,*.csr"
)
DEFERRED_SDK_PREFIXES = ("addons/GodotGooglePlayBilling/", "ios/plugins/WaddleStoreKit/")


def launch_edition(data: dict) -> str:
    # Receipts/configs created before the free-MVP decision describe commerce
    # packages. Never silently reinterpret their original acceptance contract.
    edition = data.get("launch_edition", "commerce")
    if edition not in ("commerce", "free_offline_mvp"):
        raise ValueError("Unsupported native launch edition")
    return edition


def native_accounts_enabled(data: dict, platform: str | None = None) -> bool:
    """Optional iOS accounts are independent of native payment availability."""
    if platform is None:
        return data.get("platform") == "ios" and data.get("native_accounts_enabled") is True
    enabled = data.get(platform, {}).get("accounts_enabled", False)
    if type(enabled) is not bool or (enabled and platform != "ios"):
        raise ValueError("Only iOS currently supports optional native accounts")
    if enabled and data[platform].get("clerk_issuer") != "https://clerk.waddlewars.io":
        raise ValueError("Native release accounts require production Waddle Wars Clerk")
    return enabled


def omitted_sdk_prefixes(data: dict, platform: str | None = None) -> tuple[str, ...]:
    if launch_edition(data) != "free_offline_mvp":
        return ()
    return (DEFERRED_SDK_PREFIXES[0],) if native_accounts_enabled(data, platform) else DEFERRED_SDK_PREFIXES


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read_config(path: Path = CONFIG) -> dict:
    config = json.loads(path.read_text())
    if config.get("schema_version") != 1:
        raise ValueError("Unsupported native release config version")
    validate_app_name(config.get("app_name"))
    launcher_name(config, "ios")
    launch_edition(config)
    native_accounts_enabled(config, "ios")
    if not isinstance(config.get("project_name"), str) or not config["project_name"].strip():
        raise ValueError("Original Godot project/save name must remain explicit")
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]*(?:\.[A-Za-z][A-Za-z0-9_-]*){2,}", config["bundle_id"]):
        raise ValueError("Invalid bundle ID")
    if config["android"]["target_sdk"] < 36:
        raise ValueError("Google Play launch target must be API 36 or newer")
    return config


def validate_app_name(value: object) -> str:
    """Validate the public store/launcher title, never the Godot save identity."""
    if (not isinstance(value, str) or not value or value != value.strip()
            or len(value) > 30 or any(ord(char) < 32 or ord(char) == 127 for char in value)):
        raise ValueError("App display name must be a nonblank 1..30-character title without control characters")
    return value


def launcher_name(config: dict, platform: str) -> str:
    """Resolve the iOS home-screen label separately from the store title."""
    value = config.get("app_name")
    if platform == "ios":
        value = config.get("ios", {}).get("display_name", value)
    return validate_app_name(value)


def godot_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def export_preset(config: dict, platform: str, version: str, build: int, team: str = "") -> str:
    validate_app_name(config.get("app_name"))
    launcher_name(config, platform)
    offline_mvp = launch_edition(config) == "free_offline_mvp"
    accounts = native_accounts_enabled(config, platform)
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Version must have numeric major.minor.patch format")
    if build < 1 or build > 2100000000:
        raise ValueError("Build number must be 1..2100000000 and unused in the store")
    if platform == "ios" and not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise ValueError("iOS preparation requires the real 10-character Apple Team ID")
    options: dict[str, str | int | bool] = {}
    if platform == "android":
        name, engine_platform = config["android"]["preset_name"], "Android"
        output = "build/waddle-wars.aab"
        options = {
            "gradle_build/use_gradle_build": True,
            "gradle_build/export_format": 1,
            "gradle_build/min_sdk": str(config["android"]["min_sdk"]),
            "gradle_build/target_sdk": str(config["android"]["target_sdk"]),
            "gradle_build/compress_native_libraries": False,
            "architectures/arm64-v8a": True,
            "architectures/armeabi-v7a": False,
            "architectures/x86": False,
            "architectures/x86_64": False,
            "package/unique_name": config["bundle_id"],
            "package/name": config["app_name"],
            "package/signed": True,
            "version/code": build,
            "version/name": version,
            "screen/immersive_mode": True,
            "screen/support_small": True,
            "screen/support_normal": True,
            "screen/support_large": True,
            "screen/support_xlarge": True,
            "permissions/internet": True,
            "permissions/record_audio": False,
            "permissions/camera": False,
            "permissions/access_fine_location": False,
            "permissions/access_coarse_location": False,
            "permissions/read_external_storage": False,
            "permissions/write_external_storage": False,
        }
    else:
        name, engine_platform = config["ios"]["preset_name"], "iOS"
        output = "build/ios/waddlewars.zip"
        options = {
            "application/app_store_team_id": team,
            "application/bundle_identifier": config["bundle_id"],
            "application/short_version": version,
            "application/version": str(build),
            "application/min_ios_version": config["ios"]["min_ios_version"],
            "application/targeted_device_family": 2,
            "application/export_project_only": True,
            "application/delete_old_export_files_unconditionally": False,
            "architectures/arm64": True,
            "entitlements/game_center": False,
            "entitlements/increased_memory_limit": False,
            "privacy/tracking_enabled": False,
            # Godot a13da4feb bit masks: app-container metadata C617.1,
            # elapsed in-app timers 35F9.1. No timestamp-display claim.
            # Disk-space eligibility remains an open gate in privacy_review.md;
            # these two reviewed options do not approve inherited disk reasons.
            "privacy/file_timestamp_access_reasons": 2,
            "privacy/system_boot_time_access_reasons": 1,
            "plugins/WaddleStoreKit": not offline_mvp or accounts,
            # Keep the OS launch still aligned with Godot's first frame.
            "storyboard/custom_image@2x": "res://assets/art/ui/menu/launch_screen_portrait_v1.png",
            "storyboard/custom_image@3x": "res://assets/art/ui/menu/launch_screen_portrait_v1.png",
            "storyboard/image_scale_mode": 3,
            "user_data/accessible_from_files_app": False,
            "user_data/accessible_from_itunes_sharing": False,
        }
    header = {
        "name": name, "platform": engine_platform, "runnable": True,
        "advanced_options": True, "dedicated_server": False,
        "custom_features": ",".join(feature for feature, enabled in (
            ("native_accounts", accounts), ("native_commerce", not offline_mvp)) if enabled),
        "export_filter": "all_resources",
        "include_filter": "", "exclude_filter": EXCLUDE_FILTER + "".join(
            "," + prefix + "*" for prefix in omitted_sdk_prefixes(config, platform)),
        "export_path": output, "encrypt_pck": False,
        "encrypt_directory": False, "script_export_mode": 2,
    }
    def encode(value: object) -> str:
        return str(value).lower() if isinstance(value, bool) else str(value) if isinstance(value, int) else godot_string(str(value))
    def section(values: dict) -> str:
        return "\n".join(f"{key}={encode(value)}" for key, value in values.items())
    return f"[preset.0]\n\n{section(header)}\n\n[preset.0.options]\n\n{section(options)}\n"


def runtime_files(source: Path) -> list[Path]:
    files = [source / "project.godot"]
    if files[0].is_symlink():
        raise ValueError("Refusing symlinked project.godot")
    for name in RUNTIME_DIRS:
        directory = source / name
        if directory.is_symlink():
            raise ValueError(f"Refusing symlinked runtime directory: {name}")
        if not directory.exists():
            continue
        for path in sorted(directory.rglob("*")):
            if path.is_symlink():
                raise ValueError(f"Refusing symlink in runtime source: {path.relative_to(source)}")
            if not path.is_file():
                continue
            relative = path.relative_to(source)
            if any(part.startswith(".") and part != ".gdignore" for part in relative.parts):
                continue
            if path.suffix.lower() in PRIVATE_SUFFIXES:
                raise ValueError(f"Signing/private file found under runtime assets: {relative}")
            if path.suffix.lower() in {".blend", ".blend1", ".pyc"}:
                continue
            files.append(path)
    if not files[0].is_file():
        raise ValueError("Source must be the game project directory")
    return files


def replace_setting(text: str, section: str, key: str, encoded: str) -> str:
    match = re.search(rf"(?ms)^\[{re.escape(section)}\]\n(.*?)(?=^\[|\Z)", text)
    if not match:
        return text + f"\n[{section}]\n\n{key}={encoded}\n"
    body = match.group(1)
    pattern = rf"(?m)^{re.escape(key)}=.*$"
    body = re.sub(pattern, f"{key}={encoded}", body) if re.search(pattern, body) else body + f"{key}={encoded}\n"
    return text[:match.start(1)] + body + text[match.end(1):]


def checked_ios_template(path: Path, expected_sha256: str) -> str:
    """Bind a bounded custom template; this is not a capability/privacy audit."""
    if (not path.is_absolute() or ".." in path.parts
            or any(part.is_symlink() for part in (path, *path.parents))
            or not path.is_file() or path.suffix != ".zip"
            or not 0 < path.stat().st_size <= 512 * 1024 ** 2
            or not isinstance(expected_sha256, str)
            or not re.fullmatch(r"[0-9a-f]{64}", expected_sha256)):
        raise ValueError("Custom iOS template requires an explicit regular ZIP and SHA256")
    if sha256(path) != expected_sha256:
        raise ValueError("Custom iOS template SHA256 mismatch")
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        if not entries or len(entries) > 20000 or sum(item.file_size for item in entries) > 2 * 1024 ** 3:
            raise ValueError("Custom iOS template exceeds expanded inventory bounds")
        seen = set()
        kinds = {}
        for item in entries:
            name = item.filename.rstrip("/")
            mode = (item.external_attr >> 16) & 0o170000
            if (item.orig_filename != item.filename or not name or name.startswith("/") or "\\" in name
                    or len(name) > 1024 or any(ord(char) < 32 or ord(char) == 127 for char in name)
                    or any(part in ("", ".", "..") for part in name.split("/"))
                    or name.casefold() in seen or item.flag_bits & 1
                    or mode not in (0, 0o100000, 0o040000)
                    or (mode == 0o040000 and not item.is_dir())
                    or (mode == 0o100000 and item.is_dir())
                    or item.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED)
                    or not 0 <= item.file_size <= 1024 ** 3
                    or (item.is_dir() and item.file_size)):
                raise ValueError("Unsafe custom iOS template entry")
            seen.add(name.casefold())
            kinds[name.casefold()] = item.is_dir()
        for name in kinds:
            parts = name.split("/")
            if any(kinds.get("/".join(parts[:index])) is False for index in range(1, len(parts))):
                raise ValueError("Custom iOS template has file/directory prefix collision")
        if archive.testzip() is not None:
            raise ValueError("Custom iOS template ZIP checksum failed")
    return expected_sha256


def verify_ios_template_binding(candidate: Path, receipt: dict) -> dict | None:
    binding = receipt.get("ios_custom_template")
    capability = receipt.get("ios_engine_capability_policy")
    preset = (candidate / "project/export_presets.cfg").read_text()
    disk_masks = re.findall(r"(?m)^\s*privacy/disk_space_access_reasons\s*=\s*([^\n]*)$", preset)
    if capability is None and any(not re.fullmatch(r"[1-9][0-9]*", mask.strip()) for mask in disk_masks):
        raise ValueError("Zero or noncanonical disk reason mask requires a reviewed engine capability policy")
    if binding is None:
        if capability is not None:
            raise ValueError("Engine capability policy requires a bound custom template")
        return None
    if (receipt.get("platform") != "ios" or not isinstance(binding, dict)
            or set(binding) != {"path", "sha256"} or binding["path"] != "inputs/ios-template.zip"):
        raise ValueError("Unsupported custom iOS template binding")
    path = candidate / binding["path"]
    checked_ios_template(path, binding["sha256"])
    if re.findall(r"(?m)^custom_template/release=.*$", preset) != [
            "custom_template/release=" + godot_string(str(path))]:
        raise ValueError("Custom iOS template preset differs from frozen binding")
    if capability is not None:
        if capability != {"policy": "disk-capacity-disabled-template-v1", "template_sha256": binding["sha256"]}:
            raise ValueError("Unsupported or mismatched iOS engine capability policy")
        if re.findall(r"(?m)^privacy/disk_space_access_reasons=.*$", preset) != [
                "privacy/disk_space_access_reasons=0"]:
            raise ValueError("Reviewed disk-capacity-disabled template requires an empty disk reason mask")
    return dict(binding)


def prepare(source: Path, destination: Path, config: dict, platform: str, version: str, build: int, team: str, templates: Path | None,
            *, ios_template: Path | None = None, ios_template_sha256: str | None = None) -> dict:
    source, destination = source.resolve(), destination.resolve()
    preset = export_preset(config, platform, version, build, team)
    if destination.exists():
        raise ValueError("Destination must not exist; existing work is never overwritten")
    if destination == source or source in destination.parents:
        raise ValueError("Preparation must use a directory outside the source checkout")
    if ios_template is not None or ios_template_sha256 is not None:
        if platform != "ios" or ios_template is None or ios_template_sha256 is None:
            raise ValueError("Custom iOS template path and SHA256 must be supplied together for iOS")
        checked_ios_template(ios_template, ios_template_sha256)
    reviewed_capacity_pin = config.get("ios", {}).get("disk_capacity_disabled_template_sha256")
    if reviewed_capacity_pin is not None and (not isinstance(reviewed_capacity_pin, str)
            or not re.fullmatch(r"[0-9a-f]{64}", reviewed_capacity_pin)):
        raise ValueError("Reviewed disk-capacity-disabled template requires an exact SHA256")
    files = runtime_files(source)
    edition = launch_edition(config)
    project = destination / "project"
    hashes = {str(path.relative_to(source)): sha256(path) for path in files}
    fingerprint = hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest()
    project.mkdir(parents=True)
    ios_binding = None
    ios_capability = None
    if ios_template is not None:
        target_template = destination / "inputs/ios-template.zip"
        target_template.parent.mkdir()
        shutil.copy2(ios_template, target_template)
        checked_ios_template(target_template, ios_template_sha256)
        ios_binding = {"path": "inputs/ios-template.zip", "sha256": ios_template_sha256}
        preset += "custom_template/release=" + godot_string(str(target_template)) + "\n"
        if reviewed_capacity_pin is not None and ios_template_sha256 == reviewed_capacity_pin:
            ios_capability = {"policy": "disk-capacity-disabled-template-v1", "template_sha256": reviewed_capacity_pin}
            preset += "privacy/disk_space_access_reasons=0\n"
    omitted_sdks = {}
    for path in files:
        name = str(path.relative_to(source))
        if name.startswith(omitted_sdk_prefixes(config, platform)):
            omitted_sdks[name] = hashes[name]
            continue
        target = project / path.relative_to(source)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        if sha256(target) != hashes[str(path.relative_to(source))]:
            raise ValueError("Source changed during snapshot; discard candidate and prepare again")
    settings = (project / "project.godot").read_text()
    settings = replace_setting(settings, "application", "config/version", godot_string(version))
    if platform == "android" or edition == "free_offline_mvp":
        plugin = "res://addons/GodotGooglePlayBilling/plugin.cfg"
        current = re.search(r'(?m)^enabled=PackedStringArray\(([^\n]*)\)', settings)
        enabled = re.findall(r'"(?:[^"\\]|\\.)*"', current.group(1)) if current else []
        encoded = godot_string(plugin)
        if edition == "free_offline_mvp":
            enabled = [entry for entry in enabled if entry != encoded]
        elif encoded not in enabled:
            enabled.append(encoded)
        settings = replace_setting(settings, "editor_plugins", "enabled", "PackedStringArray(" + ", ".join(enabled) + ")")
    if native_accounts_enabled(config, platform):
        settings = replace_setting(settings, "account", "deletion_enabled", "true")
        settings = replace_setting(settings, "account", "auth_api_base", godot_string("https://waddlewars.io"))
    (project / "project.godot").write_text(settings)
    (project / "export_presets.cfg").write_text(preset)
    game_config = project / "scripts/utilities/game_config.gd"
    if game_config.exists():
        stamped = re.sub(r'(?m)^const BUILD_ID: String = ".*"$', f'const BUILD_ID: String = "native-{platform}-{build}-{fingerprint[:12]}"', game_config.read_text())
        game_config.write_text(stamped)
    template_hash = None
    if platform == "android" and templates is not None:
        if templates.name != config["godot_version"]:
            raise ValueError("Template directory must match the pinned Godot version")
        archive = templates / "android_source.zip"
        if not archive.is_file():
            raise ValueError("android_source.zip missing from supplied exact-version templates")
        build_dir = project / "android/build"
        build_dir.mkdir(parents=True)
        with zipfile.ZipFile(archive) as zipped:
            for info in zipped.infolist():
                relative = Path(info.filename)
                if relative.is_absolute() or ".." in relative.parts or (info.external_attr >> 16) & 0o170000 == 0o120000:
                    raise ValueError("Unsafe Android template entry")
            zipped.extractall(build_dir)
        wrapper = build_dir / "gradlew"
        if wrapper.exists():
            wrapper.chmod(wrapper.stat().st_mode | 0o100)
        (project / "android/.gdignore").touch()
        (project / "android/.build_version").write_text(config["godot_version"] + "\n")
        template_hash = sha256(archive)
    prepared = {str(path.relative_to(project)): sha256(path) for path in files_in_project(project)}
    receipt = {
        "schema_version": 1, "state": "prepared_unbuilt", "platform": platform,
        "app_name": launcher_name(config, platform), "project_name": config["project_name"],
        "bundle_id": config["bundle_id"], "version": version, "build_number": build,
        "godot_version": config["godot_version"], "source_sha256": fingerprint,
        "launch_edition": edition, "omitted_deferred_sdk_files": omitted_sdks,
        "native_accounts_enabled": native_accounts_enabled(config, platform),
        "native_clerk_issuer": config[platform].get("clerk_issuer") if native_accounts_enabled(config, platform) else None,
        "ios_custom_template": ios_binding,
        "ios_engine_capability_policy": ios_capability,
        "source_files": hashes, "prepared_files": prepared, "android_source_template_sha256": template_hash,
        "preset_name": config[platform]["preset_name"],
        "store_ready": False, "launch_evidence": config["launch_evidence"],
    }
    (destination / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return receipt


def files_in_project(project: Path) -> list[Path]:
    files = []
    for path in project.rglob("*"):
        if ".godot" in path.relative_to(project).parts:
            continue
        if path.is_symlink():
            raise ValueError("Symlink introduced into prepared project")
        if path.is_file():
            files.append(path)
    return sorted(files)


def command_output(command: list[str]) -> dict:
    try:
        result = subprocess.run(command, text=True, capture_output=True, timeout=15, check=False)
        return {"exit_code": result.returncode, "output": (result.stdout + result.stderr).strip()[:2000]}
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"exit_code": None, "error": str(error)}


def inspect_host(config: dict, sdk: Path, templates: Path) -> dict:
    # No signing identities, certificates, secret files, or account details read.
    return {
        "state": "inventory_only", "store_ready": False,
        "godot_executable": shutil.which("godot"),
        "android": {
            "sdk": str(sdk), "target_platform_installed": (sdk / f"platforms/android-{config['android']['target_sdk']}/android.jar").is_file(),
            "required_build_tools_installed": (sdk / "build-tools" / config["android"]["build_tools"] / "apksigner").is_file(),
            "required_ndk_installed": (sdk / "ndk" / config["android"]["ndk_version"] / "source.properties").is_file(),
            "java": command_output(["java", "-version"]),
            "android_source_template_installed": (templates / "android_source.zip").is_file(),
        },
        "ios": {"xcode": command_output(["xcodebuild", "-version"]), "iphoneos_sdk": command_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-version"]), "template_installed": (templates / "ios.zip").is_file()},
        "missing_launch_evidence": [key for key, value in config["launch_evidence"].items() if not value],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=CONFIG)
    commands = parser.add_subparsers(dest="command", required=True)
    inventory = commands.add_parser("inspect", help="Read-only host inventory; never a launch pass")
    inventory.add_argument("--sdk", type=Path, default=Path.home() / "Library/Android/sdk")
    inventory.add_argument("--templates", type=Path)
    candidate = commands.add_parser("prepare", help="Create a new isolated project; never runs Godot")
    candidate.add_argument("platform", choices=("android", "ios"))
    candidate.add_argument("destination", type=Path)
    candidate.add_argument("--source", type=Path, default=ROOT)
    candidate.add_argument("--version", required=True)
    candidate.add_argument("--build-number", type=int, required=True)
    candidate.add_argument("--team-id", default="")
    candidate.add_argument("--templates", type=Path, help="Android exact-version directory; installs template only into candidate")
    candidate.add_argument("--ios-template", type=Path, help="Explicit reviewed iOS template ZIP; copied into candidate inputs")
    candidate.add_argument("--ios-template-sha256", help="Exact custom iOS template SHA256; not privacy/capability approval")
    args = parser.parse_args()
    try:
        config = read_config(args.config)
        templates = args.templates or Path.home() / "Library/Application Support/Godot/export_templates" / config["godot_version"]
        if args.command == "inspect":
            result = inspect_host(config, args.sdk, templates)
        else:
            result = prepare(args.source, args.destination, config, args.platform, args.version, args.build_number, args.team_id, templates if args.platform == "android" else None,
                             ios_template=args.ios_template, ios_template_sha256=args.ios_template_sha256)
            result = {key: value for key, value in result.items() if key not in {"source_files", "prepared_files"}}
        print(json.dumps(result, indent=2))
        return 0
    except (ValueError, OSError, zipfile.BadZipFile, KeyError) as error:
        print(f"native_release: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
