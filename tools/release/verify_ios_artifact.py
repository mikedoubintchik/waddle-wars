#!/usr/bin/env python3
"""Read-only, offline gates for existing iOS archives and exported IPAs.

No build, signing, credential discovery, private-key/profile writes, device
access, network, or upload. Public codesign certificate extraction and retained
verification evidence are the only writes. Artifact verification never proves
that an xcodebuild session succeeded or that a store/device accepted a build.
"""
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import resource
import shutil
import stat
import struct
import subprocess
import sys
import unicodedata
import zipfile
from xml.parsers.expat import ExpatError

from native_release import native_accounts_enabled, omitted_sdk_prefixes, validate_app_name, launch_edition, DEFERRED_SDK_PREFIXES, verify_ios_template_binding
from verify_ios_profile import certificate_fingerprint

PROFILE_VERIFIER = Path(__file__).with_name("verify_ios_profile.py").resolve()
XCODE_TOOLCHAIN_BIN = Path("/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin")
PROFILE_NAME = "Waddle Wars App Store"
APP_DIRECTORY = "waddlewars.app"
EXECUTABLE = "waddlewars"
PCK = "waddlewars.pck"
UNUSED_PURPOSE_KEYS = (
    "NSCameraUsageDescription", "NSPhotoLibraryUsageDescription", "NSMicrophoneUsageDescription",
)
BRIDGE_TOKENS = ("WaddleStoreKit", "WWStoreKitBridge", "WWAuthenticationBridge")
CAPACITY_SYMBOL = re.compile(rb"^_?(?:statvfs|fstatvfs|statfs|fstatfs|getattrlist|fgetattrlist|getattrlistat|getattrlistbulk)(?:\$[A-Za-z0-9_]+)*$")
CAPACITY_KEYS = (b"NSFileSystemFreeSize", b"NSFileSystemSize", b"NSURLVolumeAvailableCapacity",
                 b"NSURLVolumeTotalCapacity", b"kCFURLVolumeAvailableCapacity", b"kCFURLVolumeTotalCapacity",
                 b"volumeAvailableCapacity", b"volumeTotalCapacity", b"attributesOfFileSystemForPath")
# Godot's neutral template contains only a comment, no localized key/value.
# Xcode26 compiles that exact source to the canonical 42-byte empty binary
# dictionary. Permit those bytes only at the corresponding frozen export path;
# no localized title/permission keys or arbitrary plist encodings are allowed.
LOCALIZED_INFO_TEMPLATE_SHA256 = "623d303462a92eac978f506e55443b8546e320d4bdccdd5e946049ff27a86cb6"
COMPILED_EMPTY_LOCALIZATION_SHA256 = "9261ecceda608ef174256e5fdc774c1e6e3dcf533409c1bc393d490d01c713f1"
MAX_ENTRIES = 20000
MAX_FILE_BYTES = 1024 ** 3
MAX_TREE_BYTES = 2 * MAX_FILE_BYTES
MAX_METADATA_BYTES = 8 * 1024 ** 2
MAX_OUTPUT_BYTES = 64 * 1024 ** 2
PLIST_ERRORS = (plistlib.InvalidFileException, ValueError, TypeError, OverflowError, ExpatError)
BLOCKED = {
    "store_ready": False, "device_acceptance_passed": False, "store_upload_performed": False,
    "direct_device_installation_proven": False, "testflight_or_app_store_acceptance_proven": False,
    "private_key_read_or_export_requested": False, "automatic_provisioning_enabled": False,
    "new_key_or_profile_created": False,
}


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def _pin(value: object, label: str) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", value):
        raise ValueError(label + " requires exactly 64 hexadecimal digits")
    return value.lower()


def _certificate_pin(value: object) -> str:
    if not isinstance(value, str):
        raise ValueError("Public certificate SHA1 must be a string")
    return certificate_fingerprint(value)


def _explicit(path: Path) -> Path:
    path = Path(path)
    if (not path.is_absolute() or ".." in path.parts or path.is_symlink()
            or path.resolve() != path):
        raise ValueError("Inputs/evidence must use explicit absolute paths without symlink components")
    return path


def _regular(path: Path, *, limit: int = MAX_FILE_BYTES) -> Path:
    path = _explicit(path)
    observed = path.lstat()
    if (not stat.S_ISREG(observed.st_mode) or observed.st_nlink != 1
            or observed.st_mode & 0o7000 or not 0 < observed.st_size <= limit):
        raise ValueError("Expected a bounded nonempty regular file without links or special permission bits")
    return path


def _directory(path: Path) -> Path:
    path = _explicit(path)
    if not path.is_dir() or path.stat().st_mode & 0o7000:
        raise ValueError("Expected an explicit ordinary directory")
    return path


def _relative(value: object) -> str:
    if not isinstance(value, str) or not 1 <= len(value) <= 1024:
        raise ValueError("Invalid inventory path")
    parts = value.split("/")
    if (PurePosixPath(value).is_absolute() or "\\" in value or ":" in value
            or any(ord(c) < 32 or ord(c) == 127 for c in value)
            or any(p in ("", ".", "..") or len(p) > 255 for p in parts)
            or len(parts) > 64 or unicodedata.normalize("NFC", value) != value):
        raise ValueError("Unsafe or noncanonical inventory path")
    return value


def _fold(value: str) -> str:
    return unicodedata.normalize("NFC", value).casefold()


def app_inventory(root: Path, *, ignore_imports: bool = False,
                  compiled_localizations: dict[str, str] | None = None) -> dict:
    """Bounded, exact files/directories/modes/hashes; never follow links."""
    root = _directory(root)
    inventory: dict[str, dict] = {}
    aliases: set[str] = set()
    total = 0
    pending = [root]
    while pending:
        folder = pending.pop()
        with os.scandir(folder) as entries:
            for entry in entries:
                relative = _relative(str(Path(entry.path).relative_to(root)))
                if ignore_imports and relative == ".godot":
                    if not entry.is_dir(follow_symlinks=False) or entry.is_symlink():
                        raise ValueError("Import cache may not be a link or special file")
                    continue
                folded = _fold(relative)
                if folded in aliases or len(inventory) >= MAX_ENTRIES:
                    raise ValueError("Ambiguous or excessive app/runtime inventory")
                aliases.add(folded)
                observed = entry.stat(follow_symlinks=False)
                mode = stat.S_IMODE(observed.st_mode)
                if mode & 0o7000 or entry.is_symlink():
                    raise ValueError("Links or special permission bits in app/runtime inventory")
                if stat.S_ISDIR(observed.st_mode):
                    inventory[relative] = {"kind": "directory", "mode": mode}
                    pending.append(Path(entry.path))
                elif stat.S_ISREG(observed.st_mode):
                    if observed.st_nlink != 1 or not 0 <= observed.st_size <= MAX_FILE_BYTES:
                        raise ValueError("Linked or oversized app/runtime file")
                    total += observed.st_size
                    if total > MAX_TREE_BYTES:
                        raise ValueError("App/runtime expanded bytes exceed limit")
                    digest = sha256(Path(entry.path))
                    if (Path(relative).name.casefold() == "infoplist.strings"
                            and digest != LOCALIZED_INFO_TEMPLATE_SHA256
                            and not (digest == COMPILED_EMPTY_LOCALIZATION_SHA256
                                     and compiled_localizations is not None
                                     and compiled_localizations.get(relative) == digest)):
                        raise ValueError("Localized InfoPlist.strings requires a reviewed title policy")
                    inventory[relative] = {"kind": "file", "mode": mode,
                                           "size": observed.st_size, "sha256": digest}
                else:
                    raise ValueError("Special filesystem object in app/runtime inventory")
    if not inventory:
        raise ValueError("Empty app/runtime inventory")
    return dict(sorted(inventory.items()))


def _files(inventory: dict) -> dict[str, str]:
    return {name: row["sha256"] for name, row in inventory.items() if row["kind"] == "file"}


def _compiled_localizations(frozen: dict) -> dict[str, str]:
    """Only exact neutral sources in the already-verified export may compile."""
    prefix = "project/build/ios/waddlewars/"
    result = {}
    for name, digest in frozen["receipt"]["artifacts"].items():
        if (digest == LOCALIZED_INFO_TEMPLATE_SHA256
                and re.fullmatch(re.escape(prefix) + r"[A-Za-z0-9_-]{1,64}\.lproj/InfoPlist\.strings", name)):
            result[name[len(prefix):]] = COMPILED_EMPTY_LOCALIZATION_SHA256
    return result


def _mapping(value: object) -> dict[str, str]:
    if not isinstance(value, dict) or not value or len(value) > MAX_ENTRIES:
        raise ValueError("Missing or excessive frozen hash inventory")
    result: dict[str, str] = {}
    folded: set[str] = set()
    for name, digest in value.items():
        name = _relative(name)
        if _fold(name) in folded:
            raise ValueError("Ambiguous frozen inventory")
        folded.add(_fold(name))
        result[name] = _pin(digest, "Frozen file SHA256")
    return result


def _unique_json_pairs(pairs: list) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON key")
        result[key] = value
    return result


def _json(path: Path) -> dict:
    path = _regular(path, limit=MAX_METADATA_BYTES)
    result = json.loads(path.read_bytes(), object_pairs_hook=_unique_json_pairs)
    if not isinstance(result, dict):
        raise ValueError("Receipt must be a JSON object")
    return result


def _import_metadata(candidate: Path, receipt: dict, receipt_sha256: str,
                     prepared: dict[str, str], expected: dict[str, str]) -> tuple[dict, str | None]:
    """Only explicitly frozen new Godot UID sidecars may extend a snapshot."""
    supplement = candidate / "import-metadata.json"
    has_supplement = supplement.exists() or supplement.is_symlink()
    canonical = receipt.get("import_metadata")
    if has_supplement and "import_metadata" in receipt:
        raise ValueError("Canonical and supplemental import metadata are mutually exclusive")
    metadata = _json(supplement) if has_supplement else canonical
    if metadata is None and not has_supplement and "import_metadata" not in receipt:
        return {}, None
    keys = {"schema_version", "state", "source_sha256", "generated_uid_files"}
    if has_supplement:
        keys.add("candidate_receipt_sha256")
    if (not isinstance(metadata, dict) or set(metadata) != keys
            or type(metadata.get("schema_version")) is not int or metadata["schema_version"] != 1
            or metadata.get("state") != "godot_import_metadata_frozen"
            or metadata.get("source_sha256") != receipt["source_sha256"]
            or (has_supplement and metadata.get("candidate_receipt_sha256") != receipt_sha256)):
        raise ValueError("Generated import metadata is not bound to the frozen source/receipt")
    generated = metadata.get("generated_uid_files")
    if not isinstance(generated, dict) or len(generated) > MAX_ENTRIES:
        raise ValueError("Generated UID inventory must be a bounded hash object")
    generated = _mapping(generated) if generated else {}
    known = {_fold(name) for name in expected}
    for name, digest in generated.items():
        if (not name.endswith((".gd.uid", ".gdshader.uid")) or name[:-4] not in prepared
                or _fold(name) in known or name.startswith("build/")):
            raise ValueError("Only new UID sidecars adjacent to frozen prepared scripts or shaders are allowed")
        raw = _regular(candidate / "project" / name, limit=128).read_bytes()
        if not re.fullmatch(rb"uid://[a-z0-9]+\n?", raw) or hashlib.sha256(raw).hexdigest() != digest:
            raise ValueError("Generated UID sidecar content/hash changed or is invalid")
        known.add(_fold(name))
    return generated, sha256(supplement) if has_supplement else None


def _plist(path: Path) -> dict:
    path = _regular(path, limit=MAX_METADATA_BYTES)
    try:
        result = plistlib.loads(path.read_bytes())
    except PLIST_ERRORS as error:
        raise ValueError("Invalid app/archive plist") from error
    if not isinstance(result, dict):
        raise ValueError("App/archive plist must contain a dictionary")
    return result


def _identity(data: dict) -> None:
    validate_app_name(data.get("app_name"))
    launch_edition(data)
    if "native_accounts_enabled" in data and type(data["native_accounts_enabled"]) is not bool:
        raise ValueError("Native accounts capability must be boolean")
    if data.get("native_accounts_enabled") is True and data.get("platform") != "ios":
        raise ValueError("Native account artifact platform must be iOS")
    if native_accounts_enabled(data) and data.get("native_clerk_issuer") != "https://clerk.waddlewars.io":
        raise ValueError("Native account artifact must bind production Clerk")
    if (not isinstance(data.get("bundle_id"), str)
            or not re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]*(?:\.[A-Za-z][A-Za-z0-9_-]*){2,}", data["bundle_id"])
            or not isinstance(data.get("version"), str)
            or not re.fullmatch(r"\d+\.\d+\.\d+", data["version"])
            or type(data.get("build_number")) is not int
            or not 1 <= data["build_number"] <= 2100000000):
        raise ValueError("Invalid frozen app/bundle/version/build identity")
    _pin(data.get("source_sha256"), "Source SHA256")


def _native_account_configuration(receipt: dict, project: Path) -> None:
    if not native_accounts_enabled(receipt):
        return
    preset = (project / "export_presets.cfg").read_text()
    settings = (project / "project.godot").read_text()
    required = ['custom_features="native_accounts"', 'plugins/WaddleStoreKit=true',
                'storyboard/custom_image@2x="res://assets/art/ui/menu/launch_screen_portrait_v1.png"',
                'storyboard/custom_image@3x="res://assets/art/ui/menu/launch_screen_portrait_v1.png"',
                'storyboard/image_scale_mode=3']
    if any(preset.splitlines().count(line) != 1 for line in required):
        raise ValueError("Native account feature, plugin or branded launch screen missing")
    section = re.search(r"(?ms)^\[account\]\n(.*?)(?=^\[|\Z)", settings)
    if not section or any(section.group(1).splitlines().count(line) != 1 for line in
            ['deletion_enabled=true', 'auth_api_base="https://waddlewars.io"']):
        raise ValueError("Native account deletion and production auth origin must be enabled")


def _candidate(candidate: Path) -> dict:
    candidate = _directory(candidate)
    receipt_path = candidate / "receipt.json"
    receipt = _json(receipt_path)
    receipt_sha256 = sha256(receipt_path)
    if (type(receipt.get("schema_version")) is not int or receipt["schema_version"] != 1
            or receipt.get("state") != "exported_unverified" or receipt.get("platform") != "ios"):
        raise ValueError("Expected a frozen exported_unverified iOS candidate")
    _identity(receipt)
    source = _mapping(receipt.get("source_files"))
    if "project.godot" not in source or hashlib.sha256(json.dumps(source, sort_keys=True).encode()).hexdigest() != receipt["source_sha256"]:
        raise ValueError("Frozen source inventory fingerprint mismatch")
    prepared = _mapping(receipt.get("prepared_files"))
    artifacts = _mapping(receipt.get("artifacts"))
    if not {"project.godot", "export_presets.cfg"}.issubset(prepared):
        raise ValueError("Required prepared runtime/preset inventory is absent")
    if any(not name.startswith("project/build/") for name in artifacts):
        raise ValueError("Unsupported export artifact path")
    project_files = _files(app_inventory(candidate / "project", ignore_imports=True))
    expected = dict(prepared)
    for name, digest in artifacts.items():
        relative = name.removeprefix("project/")
        if relative in expected and expected[relative] != digest:
            raise ValueError("Prepared/export inventories disagree")
        expected[relative] = digest
    generated_uids, supplement_pin = _import_metadata(candidate, receipt, receipt_sha256, prepared, expected)
    expected.update(generated_uids)
    if project_files != expected:
        raise ValueError("Prepared runtime/export file inventory or bytes changed")
    ios_template = verify_ios_template_binding(candidate, receipt)
    if launch_edition(receipt) == "free_offline_mvp":
        if any(name.startswith(omitted_sdk_prefixes(receipt)) for name in prepared):
            raise ValueError("Free MVP snapshot contains deferred native billing/auth SDKs")
        preset = (candidate / "project/export_presets.cfg").read_text()
        if re.findall(r"(?m)^plugins/WaddleStoreKit=.*$", preset) != ["plugins/WaddleStoreKit=" + str(native_accounts_enabled(receipt)).lower()]:
            raise ValueError("Free MVP preset must explicitly disable WaddleStoreKit")
    _native_account_configuration(receipt, candidate / "project")
    pcks = [name for name in artifacts if Path(name).name == PCK]
    if len(pcks) != 1:
        raise ValueError("Expected exactly one exported waddlewars.pck")
    permission = receipt.get("ios_plist_policy")
    title = receipt.get("ios_display_name_policy")
    if (not isinstance(permission, dict) or permission.get("policy") != "no-camera-microphone-photo-library-v1"
            or not isinstance(permission.get("removed_keys"), list)
            or any(key not in UNUSED_PURPOSE_KEYS for key in permission["removed_keys"])
            or not isinstance(title, dict) or title.get("policy") != "launcher-title-without-project-rename-v1"
            or title.get("app_name") != receipt["app_name"]):
        raise ValueError("Missing or unsupported exported permission/title policy")
    policy_path = _relative(title.get("path"))
    if permission.get("path") != policy_path or policy_path not in artifacts:
        raise ValueError("Title/permission policy must identify the frozen exported plist")
    if _pin(title.get("after_sha256"), "Display policy SHA256") != artifacts[policy_path]:
        raise ValueError("Display policy hash does not match final exported plist")
    # Permission removal precedes display-title serialization; its after hash
    # binds that intermediate stage, not the later final plist bytes.
    _pin(permission.get("after_sha256"), "Permission policy SHA256")
    exported_info = _plist(candidate / policy_path)
    if exported_info.get("CFBundleDisplayName") != receipt["app_name"] or any(key in exported_info for key in UNUSED_PURPOSE_KEYS):
        raise ValueError("Exported launcher title or permission policy differs from receipt")
    return {"receipt": receipt, "receipt_sha256": receipt_sha256,
            "project_files": project_files, "pck_sha256": artifacts[pcks[0]], "pck_path": pcks[0],
            "ios_custom_template": ios_template,
            "generated_uid_files": generated_uids, "supplemental_import_metadata_sha256": supplement_pin}


def _archive_app(archive: Path) -> tuple[Path, dict]:
    archive = _directory(archive)
    info = _plist(archive / "Info.plist")
    properties = info.get("ApplicationProperties")
    if not isinstance(properties, dict) or properties.get("ApplicationPath") != "Applications/" + APP_DIRECTORY:
        raise ValueError("Archive app metadata path is missing or ambiguous")
    applications = _directory(archive / "Products/Applications")
    with os.scandir(applications) as entries:
        names = [entry.name for entry in entries]
    if names != [APP_DIRECTORY]:
        raise ValueError("Archive must contain exactly one expected application")
    return _directory(applications / APP_DIRECTORY), info


def _app_info(app: Path, identity: dict) -> dict:
    info = _plist(app / "Info.plist")
    expected = {"CFBundleIdentifier": identity["bundle_id"], "CFBundleShortVersionString": identity["version"],
                "CFBundleVersion": str(identity["build_number"]), "CFBundleDisplayName": identity["app_name"],
                "CFBundleExecutable": EXECUTABLE, "MinimumOSVersion": "15.0"}
    if any(info.get(key) != value for key, value in expected.items()) or any(key in info for key in UNUSED_PURPOSE_KEYS):
        raise ValueError("Signed app title/identity/minimum OS/permission policy mismatch")
    _regular(app / EXECUTABLE)
    if not os.access(app / EXECUTABLE, os.X_OK):
        raise ValueError("Signed application executable lacks execute permissions")
    return info


def code_without_signature(path: Path) -> str:
    """Hash every thin ARM64 executable byte except signature tail/datasize."""
    raw = bytearray(_regular(path).read_bytes())
    if len(raw) < 32:
        raise ValueError("Truncated Mach-O")
    magic, cpu, _, kind, count, command_bytes, _, _ = struct.unpack_from("<8I", raw)
    if magic != 0xFEEDFACF or cpu != 0x0100000C or kind != 2 or not 1 <= count <= 4096 or command_bytes > 1024 ** 2:
        raise ValueError("Expected a bounded thin ARM64 executable Mach-O")
    end = 32 + command_bytes
    if end > len(raw):
        raise ValueError("Mach-O load commands exceed file")
    cursor, signature = 32, None
    for _ in range(count):
        if cursor + 8 > end:
            raise ValueError("Truncated Mach-O load command")
        command, length = struct.unpack_from("<2I", raw, cursor)
        if length < 8 or length % 8 or cursor + length > end:
            raise ValueError("Invalid Mach-O load command size")
        if command == 0x1D:
            if signature is not None or length != 16:
                raise ValueError("Expected exactly one LC_CODE_SIGNATURE command")
            offset, size = struct.unpack_from("<2I", raw, cursor + 8)
            if offset < end or size == 0 or offset + size != len(raw):
                raise ValueError("Code signature must be a bounded file tail")
            signature = offset
            struct.pack_into("<I", raw, cursor + 12, 0)
        cursor += length
    if cursor != end or signature is None:
        raise ValueError("Missing signature or inconsistent command table")
    return hashlib.sha256(raw[:signature]).hexdigest()


def _xcode_inspection_tool(name: str) -> Path:
    if name not in ("lipo", "otool", "strings", "nm"):
        raise ValueError("Unknown Xcode inspection tool")
    folder = _directory(XCODE_TOOLCHAIN_BIN)
    path = (folder / name).resolve(strict=True)
    # Xcode's otool is an in-toolchain symlink to llvm-otool. Resolve that exact
    # configured tool once; never permit an escape or relax artifact/link rules.
    if path.parent != folder:
        raise ValueError("Inspection tool escaped the reviewed Xcode toolchain")
    path = _regular(path)
    if not os.access(path, os.X_OK):
        raise ValueError("Xcode inspection tool is not executable")
    return path


def resolve_tools() -> dict[str, Path]:
    # /usr/bin inspection launchers are multiply hard-linked on macOS. Use the
    # concrete installed Xcode binaries, pin/recheck them, and retain the strict
    # single-link input/artifact boundary rather than exempting system aliases.
    tools = {name: _xcode_inspection_tool(name) for name in ("lipo", "otool", "strings", "nm")}
    tools["codesign"] = _regular(Path("/usr/bin/codesign"))
    tools["python"] = _regular(Path(sys.executable).resolve())
    if any(not os.access(path, os.X_OK) for path in tools.values()):
        raise ValueError("Verification tools must be existing executable regular files")
    return tools


def _limit_output() -> None:
    resource.setrlimit(resource.RLIMIT_FSIZE, (MAX_OUTPUT_BYTES, MAX_OUTPUT_BYTES))


class _Evidence:
    def __init__(self, path: Path, inputs: tuple[Path, ...]) -> None:
        self.path = _explicit(path)
        inputs = tuple(_explicit(item) for item in inputs)
        if any(self.path == item or item in self.path.parents for item in inputs):
            raise ValueError("Evidence must not modify an input tree")
        _directory(self.path.parent)
        try:
            self.path.mkdir(mode=0o700)
        except OSError as error:
            raise ValueError("Verification evidence must be a fresh directory; existing evidence is preserved") from error
        self.env = {"PATH": "/usr/bin:/bin", "LANG": "C", "LC_ALL": "C", "TZ": "UTC"}
        self.env.update({key: os.environ[key] for key in ("HOME", "TMPDIR") if key in os.environ})

    def json(self, name: str, result: dict) -> None:
        with (self.path / name).open("x", encoding="utf-8") as output:
            json.dump(result, output, indent=2, sort_keys=True)
            output.write("\n")

    def run(self, name: str, command: list[str]) -> tuple[bytes, bytes]:
        stdout, stderr = self.path / (name + ".stdout"), self.path / (name + ".stderr")
        with stdout.open("xb") as out, stderr.open("xb") as err:
            try:
                result = subprocess.run(command, stdout=out, stderr=err, env=self.env,
                                        cwd=self.path, timeout=60, check=False, preexec_fn=_limit_output)
            except (OSError, subprocess.TimeoutExpired) as error:
                raise ValueError(name + " failed; diagnostic files retained") from error
        if stdout.stat().st_size > MAX_OUTPUT_BYTES or stderr.stat().st_size > MAX_OUTPUT_BYTES:
            raise ValueError(name + " output exceeds bounds")
        if result.returncode:
            raise ValueError(name + " rejected artifact; diagnostic files retained")
        return stdout.read_bytes(), stderr.read_bytes()


def _tool_hashes(tools: dict[str, Path], helper: Path, helper_pin: str) -> dict[str, str]:
    helper = _regular(helper, limit=16 * 1024 ** 2)
    if not os.access(helper, os.X_OK) or sha256(helper) != _pin(helper_pin, "CMS helper SHA256"):
        raise ValueError("Pinned CMS helper is missing, changed, or not executable")
    paths = [*tools.values(), helper, PROFILE_VERIFIER, Path(__file__).resolve(), Path(__file__).with_name("native_release.py").resolve()]
    return {str(_regular(path)): sha256(path) for path in paths}


def _unchanged_tools(before: dict[str, str]) -> None:
    if any(sha256(_regular(Path(path))) != digest for path, digest in before.items()):
        raise ValueError("Verification tool/source/helper changed; acceptance discarded")


def _signed_app(app: Path, identity: dict, evidence: _Evidence, tools: dict[str, Path], *,
                team_id: str, certificate_sha1: str, certificate_sha256: str,
                profile_sha256: str, cms_helper: Path, cms_helper_sha256: str) -> dict:
    if not isinstance(team_id, str) or not re.fullmatch(r"[A-Z0-9]{10}", team_id):
        raise ValueError("Expected explicit Apple team ID")
    certificate_sha1 = _certificate_pin(certificate_sha1)
    certificate_sha256 = _pin(certificate_sha256, "Public certificate SHA256")
    profile_sha256 = _pin(profile_sha256, "Embedded profile SHA256")
    executable = app / EXECUTABLE
    normalized = code_without_signature(executable)
    architectures, _ = evidence.run("architectures", [str(tools["lipo"]), "-archs", str(executable)])
    if architectures.strip() != b"arm64":
        raise ValueError("Signed app must contain only ARM64")
    evidence.run("codesign-verify", [str(tools["codesign"]), "--verify", "--deep", "--strict", "--verbose=2", str(app)])
    _, display = evidence.run("codesign-display", [str(tools["codesign"]), "-d", "--verbose=4", str(app)])
    lines = display.decode("utf-8", errors="strict").splitlines()
    for expected in ("TeamIdentifier=" + team_id, "Identifier=" + identity["bundle_id"]):
        if lines.count(expected) != 1:
            raise ValueError("Code signature team/bundle identity mismatch")
    if not any(line.startswith("Authority=Apple Distribution: ") and line.endswith(" (" + team_id + ")") for line in lines):
        raise ValueError("Expected an Apple Distribution signing authority")
    payload, _ = evidence.run("codesign-entitlements", [str(tools["codesign"]), "--display", "--entitlements", "-", "--xml", str(app)])
    if len(payload) > MAX_METADATA_BYTES:
        raise ValueError("Entitlement output exceeds bounds")
    try:
        entitlements = plistlib.loads(payload)
    except PLIST_ERRORS as error:
        raise ValueError("Invalid signed entitlements") from error
    if (not isinstance(entitlements, dict)
            or entitlements.get("application-identifier") != team_id + "." + identity["bundle_id"]
            or entitlements.get("com.apple.developer.team-identifier") != team_id
            or entitlements.get("get-task-allow") is not False
            or entitlements.get("beta-reports-active") is not True):
        raise ValueError("Signed app has unexpected distribution entitlements")
    prefix = evidence.path / "public-certificate-"
    evidence.run("codesign-public-certificates", [str(tools["codesign"]), "-d", "--extract-certificates=" + str(prefix), str(app)])
    leaf = _regular(Path(str(prefix) + "0"), limit=1024 ** 2)
    if hashlib.sha1(leaf.read_bytes()).hexdigest().upper() != certificate_sha1 or sha256(leaf) != certificate_sha256:
        raise ValueError("Public signing certificate pin mismatch")
    embedded = _regular(app / "embedded.mobileprovision", limit=MAX_METADATA_BYTES)
    if sha256(embedded) != profile_sha256:
        raise ValueError("Embedded profile differs from independently pinned profile")
    profile_payload, _ = evidence.run("embedded-profile", [str(tools["python"]), "-I", "-S", str(PROFILE_VERIFIER),
        "--mobileprovision", str(embedded), "--cms-helper", str(cms_helper), "--cms-helper-sha256", cms_helper_sha256,
        "--team-id", team_id, "--app-id", identity["bundle_id"], "--certificate-sha1", certificate_sha1, "--profile-name", PROFILE_NAME])
    if len(profile_payload) > MAX_METADATA_BYTES:
        raise ValueError("Profile verifier output exceeds bounds")
    profile = json.loads(profile_payload, object_pairs_hook=_unique_json_pairs)
    required = {"state": "profile_signature_and_metadata_verified",
                "cms_signature_trust": "APPLE_PROVISIONING_POLICY_VERIFIED_OFFLINE",
                "profile_eligible_for_archive": True, "mobileprovision_sha256": profile_sha256,
                "cms_helper_sha256": cms_helper_sha256.lower(), "matched_certificate_sha1": certificate_sha1,
                "matched_certificate_sha256": certificate_sha256, "team_id": team_id,
                "app_id": identity["bundle_id"], "profile_name": PROFILE_NAME}
    if not isinstance(profile, dict) or any(type(profile.get(key)) is not type(value) or profile.get(key) != value for key, value in required.items()):
        raise ValueError("Trusted embedded profile verification result mismatch")
    linked, _ = evidence.run("linked-frameworks", [str(tools["otool"]), "-L", str(executable)])
    linked_paths = {line.strip().split()[0] for line in linked.splitlines() if line.strip()}
    commerce_frameworks = (
        b"/System/Library/Frameworks/StoreKit.framework/StoreKit",
        b"/System/Library/Frameworks/AuthenticationServices.framework/AuthenticationServices")
    strings, _ = evidence.run("native-bridge-tokens", [str(tools["strings"]), str(executable)])
    string_lines = set(strings.splitlines())
    tokens = {token: token.encode() in string_lines for token in BRIDGE_TOKENS}
    offline_mvp = launch_edition(identity) == "free_offline_mvp"
    if offline_mvp and not native_accounts_enabled(identity):
        if any(path.endswith(framework.split(b"/Frameworks/")[-1])
               for path in linked_paths for framework in commerce_frameworks) or any(
                token.encode() in line for token in BRIDGE_TOKENS for line in string_lines):
            raise ValueError("Free MVP executable contains deferred native billing/auth linkage")
    else:
        if any(path not in linked_paths for path in commerce_frameworks):
            raise ValueError("StoreKit/AuthenticationServices frameworks are not linked")
        if not all(tokens.values()):
            raise ValueError("Required native billing/auth bridge tokens are missing")
    capacity_policy = identity.get("ios_engine_capability_policy")
    capacity_checked = False
    if capacity_policy is not None:
        manifest = _plist(app / "PrivacyInfo.xcprivacy")
        expected_apis = {
            "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"],
            "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1"],
        }
        entries = manifest.get("NSPrivacyAccessedAPITypes")
        if (not isinstance(entries, list) or len(entries) != len(expected_apis)
                or any(not isinstance(entry, dict) or set(entry) != {
                    "NSPrivacyAccessedAPIType", "NSPrivacyAccessedAPITypeReasons"} for entry in entries)
                or {entry["NSPrivacyAccessedAPIType"]: entry["NSPrivacyAccessedAPITypeReasons"]
                    for entry in entries} != expected_apis):
            raise ValueError("Reviewed engine requires exact file/timer reasons and no disk category")
        binaries = [executable]
        frameworks = app / "Frameworks"
        if frameworks.exists() and any(frameworks.iterdir()):
            for name, row in app_inventory(frameworks).items():
                if row["kind"] == "file":
                    path = frameworks / name
                    with path.open("rb") as stream:
                        magic = stream.read(4)
                    if magic in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xce",
                                 b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"):
                        binaries.append(path)
        for index, binary in enumerate(binaries):
            imports, _ = evidence.run(f"capacity-imports-{index}", [str(tools["nm"]), "-u", str(binary)])
            strings_for_binary = strings if binary == executable else evidence.run(
                f"capacity-keys-{index}", [str(tools["strings"]), str(binary)])[0]
            if (any(CAPACITY_SYMBOL.fullmatch(line.split()[-1]) for line in imports.splitlines() if line.split())
                    or any(key in strings_for_binary for key in CAPACITY_KEYS)):
                raise ValueError("Disk-capacity API remains in reviewed engine app or embedded framework")
        capacity_checked = True
    return {"entitlements": entitlements, "profile": profile, "architecture": "arm64",
            "minimum_ios_version": "15.0", "native_bridge_tokens_present": tokens,
            "launch_edition": launch_edition(identity),
            "native_accounts_enabled": native_accounts_enabled(identity),
            "native_clerk_issuer": identity.get("native_clerk_issuer"),
            "storekit_auth_frameworks_linked": not offline_mvp or native_accounts_enabled(identity),
            "deferred_native_sdks_absent": offline_mvp and not native_accounts_enabled(identity),
            "ios_engine_capability_policy": capacity_policy,
            "reviewed_capacity_imports_absent": capacity_checked,
            "normalized_unsigned_executable_sha256": normalized}


def _logs(evidence: _Evidence) -> dict[str, str]:
    return {path.name: sha256(path) for path in sorted(evidence.path.iterdir()) if path.is_file()}


def _failed(evidence: _Evidence, error: Exception) -> None:
    evidence.json("failure.json", {"state": "verification_rejected", "error_type": type(error).__name__,
                                   "reason": str(error), **BLOCKED})


def verify_archive(candidate: Path, archive: Path, evidence: Path, *, team_id: str,
                   certificate_sha1: str, certificate_sha256: str, installed_profile: Path,
                   profile_sha256: str, cms_helper: Path, cms_helper_sha256: str) -> dict:
    evidence_run = _Evidence(evidence, (Path(candidate), Path(archive)))
    try:
        candidate, archive = _directory(candidate), _directory(archive)
        frozen = _candidate(candidate)
        identity = frozen["receipt"]
        localizations = _compiled_localizations(frozen)
        app, archive_info = _archive_app(archive)
        props = archive_info["ApplicationProperties"]
        for key, expected in (("CFBundleIdentifier", identity["bundle_id"]),
                              ("CFBundleShortVersionString", identity["version"]),
                              ("CFBundleVersion", str(identity["build_number"]))):
            if props.get(key) != expected:
                raise ValueError("Archive metadata identity mismatch")
        info = _app_info(app, identity)
        app_root_mode = stat.S_IMODE(app.stat().st_mode)
        before = app_inventory(app, compiled_localizations=localizations)
        files = _files(before)
        if files.get(PCK) != frozen["pck_sha256"]:
            raise ValueError("Archived waddlewars.pck differs from frozen exported runtime")
        installed_profile = _regular(installed_profile, limit=MAX_METADATA_BYTES)
        profile_sha256 = _pin(profile_sha256, "Installed profile SHA256")
        if sha256(installed_profile) != profile_sha256:
            raise ValueError("Installed provisioning profile pin mismatch")
        archive_info_pin = sha256(archive / "Info.plist")
        tools = resolve_tools()
        pins = _tool_hashes(tools, cms_helper, cms_helper_sha256)
        result = _signed_app(app, identity, evidence_run, tools, team_id=team_id,
                             certificate_sha1=certificate_sha1, certificate_sha256=certificate_sha256,
                             profile_sha256=profile_sha256, cms_helper=cms_helper, cms_helper_sha256=cms_helper_sha256)
        if (_candidate(candidate) != frozen or app_inventory(app, compiled_localizations=localizations) != before
                or stat.S_IMODE(app.stat().st_mode) != app_root_mode
                or sha256(archive / "Info.plist") != archive_info_pin
                or sha256(_regular(installed_profile)) != profile_sha256):
            raise ValueError("Archive/candidate/profile changed during verification; acceptance discarded")
        _unchanged_tools(pins)
        return {"schema_version": 1, "state": "signed_archive_verified", "platform": "ios", "signed_archive_verified": True,
                "observed_at_utc": datetime.now(timezone.utc).isoformat(), "candidate_path": str(candidate),
                "candidate_receipt_sha256": frozen["receipt_sha256"], "source_sha256": identity["source_sha256"],
                "ios_custom_template": frozen["ios_custom_template"],
                "generated_uid_files": frozen["generated_uid_files"],
                "compiled_neutral_localizations": localizations,
                "supplemental_import_metadata_sha256": frozen["supplemental_import_metadata_sha256"],
                "source_files": identity["source_files"], "version": identity["version"], "build_number": identity["build_number"],
                "app_name": identity["app_name"], "team_id": team_id, "bundle_id": identity["bundle_id"],
                "archive_path": str(archive), "archive_info_sha256": archive_info_pin,
                "archive_app_inventory": before, "archive_app_file_sha256": files,
                "archive_app_root_mode": app_root_mode, "exported_pck_path": frozen["pck_path"],
                "exported_pck_sha256": frozen["pck_sha256"], "archived_pck_matches_export": True,
                "signer_certificate_sha1": _certificate_pin(certificate_sha1),
                "signer_certificate_sha256": _pin(certificate_sha256, "Certificate SHA256"),
                "ios_plist_policy": identity["ios_plist_policy"], "ios_display_name_policy": identity["ios_display_name_policy"],
                "sdk_name": info.get("DTSDKName"), "tool_sha256": pins, **result, **BLOCKED,
                "ipa_exported": False, "verification_logs_path": str(evidence_run.path), "log_sha256": _logs(evidence_run)}
    except (ValueError, OSError, KeyError, TypeError, subprocess.SubprocessError) as error:
        _failed(evidence_run, error)
        raise ValueError("Archive verification rejected; fresh evidence retained") from error


def extract_safe(ipa: Path, destination: Path) -> tuple[Path, int]:
    """Extract a bounded IPA with canonical paths and each entry's own mode."""
    _regular(ipa)
    destination = _explicit(destination)
    destination.mkdir(mode=0o700)
    with zipfile.ZipFile(ipa) as zipped:
        entries = zipped.infolist()
        if not entries or len(entries) > MAX_ENTRIES or sum(item.file_size for item in entries) > MAX_TREE_BYTES:
            raise ValueError("IPA ZIP inventory exceeds bounds")
        seen: dict[str, str] = {}
        kinds: dict[str, bool] = {}
        plan = []
        for item in entries:
            name = _relative(item.filename[:-1] if item.is_dir() else item.filename)
            mode = item.external_attr >> 16
            kind = stat.S_IFMT(mode)
            if (item.orig_filename != item.filename or _fold(name) in kinds
                    or kind not in (0, stat.S_IFREG, stat.S_IFDIR)
                    or (kind == stat.S_IFDIR and not item.is_dir())
                    or (kind == stat.S_IFREG and item.is_dir())
                    or mode & 0o7000 or item.flag_bits & 1
                    or item.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED)
                    or not 0 <= item.file_size <= MAX_FILE_BYTES
                    or (item.is_dir() and item.file_size != 0)):
                raise ValueError("Unsafe, ambiguous, encrypted or unsupported IPA ZIP member")
            kinds[_fold(name)] = item.is_dir()
            for i in range(1, len(name.split("/")) + 1):
                prefix = "/".join(name.split("/")[:i])
                prior = seen.setdefault(_fold(prefix), prefix)
                if prior != prefix:
                    raise ValueError("IPA ZIP contains case/Unicode path aliases")
            permissions = stat.S_IMODE(mode) if item.create_system == 3 and mode else (0o755 if item.is_dir() else 0o644)
            plan.append((item, name, permissions))
        for _, name, _ in plan:
            for parent in PurePosixPath(name).parents:
                if str(parent) != "." and kinds.get(_fold(str(parent))) is False:
                    raise ValueError("IPA ZIP file/directory prefix collision")
        directories = {}
        for item, name, permissions in plan:
            target = destination.joinpath(*PurePosixPath(name).parts)
            if item.is_dir():
                target.mkdir(parents=True, exist_ok=True, mode=0o755)
                directories[target] = permissions
            else:
                target.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
                with zipped.open(item) as source, target.open("xb") as output:
                    shutil.copyfileobj(source, output, length=1024 * 1024)
                if target.stat().st_size != item.file_size:
                    raise ValueError("Extracted IPA file size differs from ZIP inventory")
                target.chmod(permissions)
        for path in sorted(directories, key=lambda p: len(p.parts), reverse=True):
            path.chmod(directories[path])
    payload = _directory(destination / "Payload")
    with os.scandir(payload) as rows:
        names = [row.name for row in rows]
    if names != [APP_DIRECTORY]:
        raise ValueError("Expected exactly one Waddle Wars app payload")
    return _directory(payload / APP_DIRECTORY), len(entries)


def verify_ipa(ipa: Path, archive: Path, archive_receipt: Path, evidence: Path, *,
               ipa_sha256: str, archive_receipt_sha256: str, cms_helper: Path, cms_helper_sha256: str) -> dict:
    # Recover the candidate boundary before any evidence writes. A caller may
    # not put logs/extraction into the read-only candidate, even on failure.
    try:
        preliminary = _json(archive_receipt)
        candidate = _explicit(Path(preliminary["candidate_path"]))
    except (ValueError, OSError, KeyError, TypeError) as error:
        raise ValueError("Cannot establish frozen candidate boundary before writing IPA evidence") from error
    evidence_run = _Evidence(evidence, (Path(archive), Path(ipa), Path(archive_receipt), candidate))
    try:
        ipa = _regular(ipa)
        if sha256(ipa) != _pin(ipa_sha256, "IPA SHA256"):
            raise ValueError("IPA artifact pin mismatch")
        archive_receipt = _regular(archive_receipt, limit=MAX_METADATA_BYTES)
        receipt_pin = _pin(archive_receipt_sha256, "Archive receipt SHA256")
        if sha256(archive_receipt) != receipt_pin:
            raise ValueError("Verified archive receipt pin mismatch")
        source = _json(archive_receipt)
        _identity(source)
        if (type(source.get("schema_version")) is not int or source["schema_version"] != 1
                or source.get("state") != "signed_archive_verified" or source.get("signed_archive_verified") is not True):
            raise ValueError("Expected a verified signed archive receipt")
        archive = _directory(archive)
        if source.get("archive_path") != str(archive):
            raise ValueError("Verified archive path mismatch")
        if source.get("candidate_path") != str(candidate):
            raise ValueError("Archive receipt candidate path changed during boundary preflight")
        frozen = _candidate(candidate)
        localizations = _compiled_localizations(frozen)
        if (frozen["receipt_sha256"] != source.get("candidate_receipt_sha256")
                or launch_edition(frozen["receipt"]) != launch_edition(source)
                or native_accounts_enabled(frozen["receipt"]) != native_accounts_enabled(source)
                or frozen["receipt"].get("native_clerk_issuer") != source.get("native_clerk_issuer")
                or frozen["supplemental_import_metadata_sha256"] != source.get("supplemental_import_metadata_sha256")
                or frozen["generated_uid_files"] != source.get("generated_uid_files", {})
                or any(frozen["receipt"].get(key) != source.get(key) for key in ("source_sha256", "source_files", "version", "build_number", "bundle_id", "app_name", "ios_engine_capability_policy"))):
            raise ValueError("Verified candidate identity/receipt changed")
        if source.get("compiled_neutral_localizations", {}) != localizations:
            raise ValueError("Verified compiled localization source binding changed")
        original, _ = _archive_app(archive)
        archive_info_pin = sha256(archive / "Info.plist")
        before = app_inventory(original, compiled_localizations=localizations)
        if (archive_info_pin != source.get("archive_info_sha256") or before != source.get("archive_app_inventory")
                or _files(before) != source.get("archive_app_file_sha256")
                or stat.S_IMODE(original.stat().st_mode) != source.get("archive_app_root_mode")):
            raise ValueError("Verified archive metadata/inventory changed")
        if _files(before).get(PCK) != frozen["pck_sha256"]:
            raise ValueError("Verified archive pack differs from frozen export")
        app, entries = extract_safe(ipa, evidence_run.path / "unpacked")
        info, original_info = _app_info(app, source), _app_info(original, source)
        if info != original_info:
            raise ValueError("IPA Info.plist semantics differ from verified archive")
        exported = app_inventory(app, compiled_localizations=localizations)
        if set(exported) != set(before) or stat.S_IMODE(app.stat().st_mode) != source["archive_app_root_mode"]:
            raise ValueError("IPA app inventory differs from archive")
        for name, row in exported.items():
            prior = before[name]
            # Xcode export makes the same public CMS profile owner-only. Permit
            # this exact tightening, never a widening or another resource mode.
            profile_tightening = (name == "embedded.mobileprovision"
                                  and row["kind"] == prior["kind"] == "file"
                                  and prior["mode"] == 0o644 and row["mode"] == 0o600)
            if row["kind"] != prior["kind"] or (row["mode"] != prior["mode"] and not profile_tightening):
                raise ValueError("IPA app file types/modes differ from archive")
            if (row["kind"] == "file" and name not in (EXECUTABLE, "Info.plist")
                    and not name.startswith("_CodeSignature/")
                    and (row["size"] != prior["size"] or row["sha256"] != prior["sha256"])):
                raise ValueError("IPA runtime resource bytes differ from archive")
        normalized = code_without_signature(app / EXECUTABLE)
        if normalized != code_without_signature(original / EXECUTABLE):
            raise ValueError("IPA executable differs beyond signature tail/datasize")
        tools = resolve_tools()
        pins = _tool_hashes(tools, cms_helper, cms_helper_sha256)
        result = _signed_app(app, source, evidence_run, tools, team_id=source["team_id"],
                             certificate_sha1=source["signer_certificate_sha1"], certificate_sha256=source["signer_certificate_sha256"],
                             profile_sha256=source["profile"]["mobileprovision_sha256"], cms_helper=cms_helper, cms_helper_sha256=cms_helper_sha256)
        if result["entitlements"] != source.get("entitlements"):
            raise ValueError("IPA entitlements differ from verified archive")
        if (_candidate(candidate) != frozen
                or app_inventory(original, compiled_localizations=localizations) != before
                or app_inventory(app, compiled_localizations=localizations) != exported
                or stat.S_IMODE(original.stat().st_mode) != source["archive_app_root_mode"]
                or stat.S_IMODE(app.stat().st_mode) != source["archive_app_root_mode"]
                or sha256(archive / "Info.plist") != archive_info_pin or sha256(archive_receipt) != receipt_pin
                or sha256(ipa) != ipa_sha256.lower()):
            raise ValueError("IPA/archive/candidate/receipt changed during verification")
        _unchanged_tools(pins)
        return {"schema_version": 1, "state": "ipa_verified", "platform": "ios", "ipa_verified": True,
                "observed_at_utc": datetime.now(timezone.utc).isoformat(), "ipa_path": str(ipa), "ipa_sha256": ipa_sha256.lower(),
                "archive_path": str(archive), "archive_receipt_sha256": receipt_pin,
                "source_sha256": source["source_sha256"], "version": source["version"], "build_number": source["build_number"],
                "ios_custom_template": frozen["ios_custom_template"],
                "generated_uid_files": frozen["generated_uid_files"],
                "compiled_neutral_localizations": localizations,
                "supplemental_import_metadata_sha256": frozen["supplemental_import_metadata_sha256"],
                "bundle_id": source["bundle_id"], "app_name": source["app_name"], "team_id": source["team_id"],
                "app_file_hashes": _files(exported), "app_inventory": exported, "zip_entry_count": entries,
                "zip_path_safety_passed": True, "runtime_resource_hashes_match_archive": True,
                "info_plist_semantics_match_archive": True, "archived_pck_matches_export": True,
                "embedded_profile_mode_policy": "unchanged-or-644-to-600-only-v1",
                "executable_diff_limit": "Only trailing LC_CODE_SIGNATURE payload and datasize word excluded",
                "tool_sha256": pins, **result, **BLOCKED, "verification_logs_path": str(evidence_run.path), "log_sha256": _logs(evidence_run)}
    except (ValueError, OSError, KeyError, TypeError, zipfile.BadZipFile, subprocess.SubprocessError) as error:
        _failed(evidence_run, error)
        raise ValueError("IPA verification rejected; fresh evidence retained") from error
