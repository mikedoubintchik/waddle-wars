#!/usr/bin/env python3
"""Verify an existing upload-signed AAB without credentials or store access.

Explicit existing JDK/bundletool paths and independently obtained public upload
certificate/artifact fingerprints are required. No signing, key generation,
build, download, installation, enrollment or upload occurs. JAR coverage parsing
supports the English JDK verbose-all format; unknown formats fail closed.
Base plus asset-only install-time packs are supported, not feature modules.
Public certificate pinning is not Play registration or app-signing continuity.
The free offline launch edition additionally requires absence of the known
native billing permission, provider metadata and DEX class-string markers.
That absence is not purchase, entitlement or privacy acceptance.
"""
from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile
import zlib

from native_release import read_config, sha256

ANDROID = "{http://schemas.android.com/apk/res/android}"
DIST = "{http://schemas.android.com/apk/distribution}"
PROVIDER_KEY = "org.godotengine.plugin.v2.GodotGooglePlayBilling"
PROVIDER_CLASS = "org.godotengine.plugin.googleplaybilling.GodotGooglePlayBilling"
LAUNCH_EDITIONS = ("commerce", "free_offline_mvp")
BILLING_PERMISSION = "com.android.vending.BILLING"
DEX_READ_CHUNK_BYTES = 1024 * 1024
# Match descriptor and reflection-name forms without decoding or extracting DEX.
# Package prefixes include every class beneath the pinned billing API/provider,
# its internal Play Billing implementation and the billing Binder interface.
BILLING_DEX_CLASS_MARKERS = (
    b"com/android/billingclient/", b"com.android.billingclient.",
    b"com/google/android/gms/internal/play_billing/", b"com.google.android.gms.internal.play_billing.",
    b"com/android/vending/billing/", b"com.android.vending.billing.",
    b"org/godotengine/plugin/googleplaybilling/", b"org.godotengine.plugin.googleplaybilling.",
    b"GodotGooglePlayBilling",
)
CHECKER = Path(__file__).with_name("check_android_artifact.py")
MAX_ARTIFACT_BYTES = 1024 * 1024 * 1024
MAX_EXPANDED_BYTES = 2 * MAX_ARTIFACT_BYTES
MAX_OUTPUT_BYTES = 32 * 1024 * 1024
MAX_ASSETS_CONFIG_BYTES = 2 * 1024 * 1024
# bundletool 1.18.3 parses these exact module files into dedicated protobuf fields:
# https://github.com/google/bundletool/blob/1.18.3/src/main/java/com/android/tools/build/bundletool/model/BundleModule.java
SPECIAL_MODULE_FILES = {"manifest/AndroidManifest.xml", "resources.pb", "assets.pb", "native.pb",
                        "apex.pb", "runtime_enabled_sdk_config.pb"}
ENTRY_LINE = re.compile(
    r"^([smk?X ]{0,8})\s+(\d+)\s+"
    r"(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun) (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) "
    r"\d{2} \d{2}:\d{2}:\d{2} UTC \d{4} (\S+)$")
CHAIN_WARNING = (
    "This jar contains entries whose certificate chain is invalid. Reason: "
    "PKIX path building failed: sun.security.provider.certpath.SunCertPathBuilderException: "
    "unable to find valid certification path to requested target")


def fingerprint(value: str, label: str) -> str:
    normalized = value.replace(":", "").lower()
    if not re.fullmatch(r"[0-9a-f]{64}", normalized):
        raise ValueError(f"{label} must contain exactly 64 hexadecimal digits")
    return normalized


def regular_file(path: Path, label: str) -> Path:
    if not path.is_absolute() or path.is_symlink() or not path.is_file():
        raise ValueError(f"{label} must be an explicit absolute regular file")
    return path.resolve()


def zip_inventory(path: Path) -> dict:
    """Read/check ZIP contents without extraction; reject ambiguous JAR names."""
    entries: dict[str, int] = {}
    folded: set[str] = set()
    with zipfile.ZipFile(path) as archive:
        infos = archive.infolist()
        if not infos or len(infos) > 50000 or sum(i.file_size for i in infos) > MAX_EXPANDED_BYTES:
            raise ValueError("AAB ZIP inventory exceeds supported limits")
        for info in infos:
            name = info.filename
            components = name.rstrip("/").split("/")
            kind = (info.external_attr >> 16) & 0o170000
            if (not re.fullmatch(r"[!-~]{1,1024}", name) or "\\" in name
                    or any(part in ("", ".", "..") for part in components)
                    or name in entries or name.casefold() in folded
                    or kind not in (0, 0o100000, 0o040000)
                    or (kind == 0o040000 and not info.is_dir())
                    or (kind == 0o100000 and info.is_dir())
                    or (info.is_dir() and info.file_size != 0)
                    or info.flag_bits & 1
                    or info.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED)):
                raise ValueError("Unsafe, duplicate, encrypted or unsupported AAB ZIP entry")
            entries[name] = info.file_size
            folded.add(name.casefold())
        if archive.testzip() is not None:
            raise ValueError("AAB ZIP CRC integrity failed")
    manifest = "META-INF/MANIFEST.MF"
    signature_files = [n for n in entries if re.fullmatch(r"META-INF/[A-Z0-9_-]{1,8}\.SF", n)]
    blocks = [n for n in entries if re.fullmatch(r"META-INF/[A-Z0-9_-]{1,8}\.(?:RSA|DSA|EC)", n)]
    if (manifest not in entries or len(signature_files) != 1 or len(blocks) != 1
            or signature_files[0].rsplit(".", 1)[0] != blocks[0].rsplit(".", 1)[0]
            or any(not 0 < entries[n] <= 1024 * 1024 for n in (manifest, *signature_files, *blocks))):
        raise ValueError("Exactly one supported JAR signature and manifest are required")
    signature_metadata = {manifest, *signature_files, *blocks}
    for name in entries:
        if name.startswith("META-INF/") and "/" not in name[len("META-INF/"):] and name not in signature_metadata:
            if re.search(r"(?i)\.(?:sf|rsa|dsa|ec)$", name) or name.upper().startswith("META-INF/SIG-"):
                raise ValueError("Unsupported or additional JAR signature metadata")
    modules = {name.split("/")[0] for name in entries
               if name.endswith("/manifest/AndroidManifest.xml")}
    if "base" not in modules or "BundleConfig.pb" not in entries:
        raise ValueError("AAB base manifest and BundleConfig.pb are required")
    if any(not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{0,79}", m) for m in modules):
        raise ValueError("Unsupported AAB module name")
    if any(f"{module}/manifest/AndroidManifest.xml" not in entries for module in modules):
        raise ValueError("AAB module manifest path is ambiguous")
    for name in entries:
        top = name.split("/")[0]
        if top not in modules | {"META-INF", "BUNDLE-METADATA", "BundleConfig.pb"}:
            raise ValueError("Unsupported AAB top-level content")
        if top == "BundleConfig.pb" and name != top:
            raise ValueError("Ambiguous BundleConfig.pb entry")
        if top in modules - {"base"} and not name.endswith("/"):
            if name == f"{top}/assets.pb":
                if not 0 < entries[name] <= MAX_ASSETS_CONFIG_BYTES:
                    raise ValueError("Asset-pack assets.pb must be a bounded nonempty metadata file")
            elif name != f"{top}/manifest/AndroidManifest.xml" and not name.startswith(f"{top}/assets/"):
                raise ValueError("Only asset-only install-time modules are supported")
    libraries = [n for n in entries if n.endswith(".so")]
    if not libraries or any(not n.startswith("base/lib/arm64-v8a/") for n in libraries):
        raise ValueError("Release AAB must contain ARM64-only base native libraries")
    if "base/dex/classes.dex" not in entries:
        raise ValueError("Release AAB base DEX is missing")
    resources = {}
    for relative in ("assets/project.binary", "assets/assets.sparsepck", "assets/_cl_"):
        matches = [f"{m}/{relative}" for m in modules if f"{m}/{relative}" in entries]
        if len(matches) != 1 or not entries[matches[0]]:
            raise ValueError("Expected exported Godot game resource presence is missing or ambiguous")
        resources[relative] = matches[0]
    return {"entries": entries, "signature_metadata": signature_metadata,
            "modules": ["base", *sorted(modules - {"base"})], "libraries": sorted(libraries), "game_resource_presence": resources}


def validate_bundle_summary(output: str, inventory: dict) -> dict:
    """Check the reviewed validate-command summary against signed ZIP inventory.

    A successful bundletool validate invocation parses special protobuf files and
    runs AssetsTargetingValidator/AssetModuleFilesValidator, not just manifest
    dumping. Its complete summary must identify only base plus asset modules.
    https://github.com/google/bundletool/blob/1.18.3/src/main/java/com/android/tools/build/bundletool/commands/ValidateBundleCommand.java
    """
    lines = output.splitlines()
    if lines[:3] != ["App Bundle information", "------------", "Feature modules:"]:
        raise ValueError("Unsupported bundletool validation summary")
    category = "feature"
    current = None
    seen: dict[str, set[str]] = {}
    asset_header = False
    for line in lines[3:]:
        if line == "Asset packs:" and not asset_header:
            asset_header = True
            category = "asset"
            current = None
            continue
        module = re.fullmatch(r"\t(Feature module|Asset pack): ([A-Za-z][A-Za-z0-9_]{0,79})", line)
        if module:
            kind, name = module.groups()
            if (name in seen or name not in inventory["modules"]
                    or kind != ("Feature module" if category == "feature" else "Asset pack")
                    or (category == "feature") != (name == "base")):
                raise ValueError("bundletool validation module inventory/classification mismatch")
            current = name
            seen[name] = set()
            continue
        entry = re.fullmatch(r"\t\tFile: ([!-~]{1,1024})", line)
        if not entry or current is None or entry[1] in seen[current]:
            raise ValueError("Unsupported or duplicate bundletool validation entry")
        seen[current].add(entry[1])
    expected = {module: {name[len(module) + 1:] for name in inventory["entries"]
                         if name.startswith(module + "/") and not name.endswith("/")
                         and name[len(module) + 1:] not in SPECIAL_MODULE_FILES}
                for module in inventory["modules"]}
    if seen != expected or asset_header != (len(expected) > 1):
        raise ValueError("bundletool validation entry inventory differs from AAB ZIP")
    return {"passed": True, "report_sha256": hashlib.sha256(output.encode()).hexdigest(),
            "feature_modules": ["base"], "asset_packs": inventory["modules"][1:]}


def verify_jar_report(output: str, inventory: dict) -> dict:
    if output.splitlines().count("jar verified.") != 1 or output.count("\n- Signed by ") != 1:
        raise ValueError("jarsigner did not report exactly one verified signer")
    if re.search(r"(?i)\b(?:disabled|weak|unsigned|expired|not yet valid)\b", output):
        # The fixed legend contains '? = unsigned entry', so inspect that line
        # separately instead of letting an actual unsigned diagnostic through.
        filtered = "\n".join(line for line in output.splitlines() if line.strip() != "? = unsigned entry")
        if re.search(r"(?i)\b(?:disabled|weak|unsigned|expired|not yet valid)\b", filtered):
            raise ValueError("jarsigner reports unsigned content or unsafe/invalid signing")
    seen = {}
    for line in output.splitlines():
        row = ENTRY_LINE.fullmatch(line)
        if row:
            flags, size, name = row.groups()
            if name in seen or name not in inventory["entries"] or int(size) != inventory["entries"][name]:
                raise ValueError("jarsigner entry inventory differs from AAB ZIP")
            seen[name] = set(flags.replace(" ", ""))
    if set(seen) != set(inventory["entries"]):
        raise ValueError("Unsupported jarsigner format or incomplete entry coverage")
    for name, flags in seen.items():
        if flags - {"s", "m", "k"}:
            raise ValueError("JAR signature coverage includes unsigned or unmatched entries")
        if name == "META-INF/MANIFEST.MF":
            required = {"s"}
        elif name in inventory["signature_metadata"] or name.endswith("/"):
            required = set()
        else:
            required = {"s", "m"}
        if not required <= flags:
            raise ValueError("Every AAB payload must be verified and listed in signed JAR manifest")
    if output.count("Warning:") > 1:
        raise ValueError("Unsupported jarsigner warning format")
    warnings = []
    if "Warning:" in output:
        for line in output.split("Warning:", 1)[1].splitlines():
            line = line.strip()
            if not line:
                continue
            allowed = (line == CHAIN_WARNING
                       or line == "This jar contains entries whose signer certificate is self-signed."
                       or re.fullmatch(r"This jar contains signatures that do not include a timestamp\. Without a timestamp, users may not be able to validate this jar after any of the signer certificates expire \(as early as \d{4}-\d{2}-\d{2}\)\.", line)
                       or re.fullmatch(r"The signer certificate will expire on \d{4}-\d{2}-\d{2}\.", line)
                       or line == "Re-run with the -verbose and -certs options for more details.")
            if not allowed:
                raise ValueError("Unsupported jarsigner warning; no signature acceptance claimed")
            warnings.append(line)
    return {"signature_verified": True, "signed_payload_count": sum(
        not name.endswith("/") and name not in inventory["signature_metadata"] for name in seen),
        "jarsigner_report_sha256": hashlib.sha256(output.encode()).hexdigest(),
        "public_pin_replaces_ca_trust": True, "accepted_jarsigner_warnings": warnings}


def der_children(data: bytes) -> list[tuple[int, bytes]]:
    """Minimal bounded DER reader, used only to recognize the public subject CN."""
    values = []
    offset = 0
    while offset < len(data):
        if offset + 2 > len(data) or data[offset] & 31 == 31:
            raise ValueError("Unsupported public certificate DER")
        tag, length = data[offset:offset + 2]
        offset += 2
        if length & 128:
            count = length & 127
            if not 1 <= count <= 4 or offset + count > len(data) or data[offset] == 0:
                raise ValueError("Unsupported public certificate DER length")
            length = int.from_bytes(data[offset:offset + count], "big")
            offset += count
            if length < 128:
                raise ValueError("Noncanonical public certificate DER length")
        if offset + length > len(data):
            raise ValueError("Truncated public certificate DER")
        values.append((tag, data[offset:offset + length]))
        offset += length
    return values


def subject_common_names(certificate: bytes) -> list[str]:
    outer = der_children(certificate)
    if len(outer) != 1 or outer[0][0] != 0x30:
        raise ValueError("Public signer certificate must be X.509 DER")
    fields = der_children(outer[0][1])
    if len(fields) != 3 or fields[0][0] != 0x30:
        raise ValueError("Unsupported public signer certificate")
    tbs = der_children(fields[0][1])
    subject_index = 5 if tbs and tbs[0][0] == 0xA0 else 4
    if len(tbs) <= subject_index + 1 or tbs[subject_index][0] != 0x30:
        raise ValueError("Public certificate subject missing")
    names = []
    for tag, rdn in der_children(tbs[subject_index][1]):
        if tag != 0x31:
            raise ValueError("Unsupported certificate subject RDN")
        for tag, attribute in der_children(rdn):
            if tag != 0x30:
                raise ValueError("Unsupported certificate subject attribute")
            pair = der_children(attribute)
            if len(pair) != 2 or pair[0][0] != 0x06:
                raise ValueError("Unsupported certificate subject attribute")
            if pair[0][1] == b"\x55\x04\x03":  # commonName
                encoding = {0x0C: "utf-8", 0x13: "ascii", 0x16: "ascii", 0x1E: "utf-16-be", 0x1C: "utf-32-be"}.get(pair[1][0])
                if not encoding:
                    raise ValueError("Unsupported certificate commonName encoding")
                names.append(pair[1][1].decode(encoding))
    return names


def public_signer(output: str, expected: str) -> dict:
    header = re.match(r"\ASigner #1:\s*", output)
    if not header:
        raise ValueError("keytool did not report one embedded public signer")
    remaining = output[header.end():]
    certificates = []
    while remaining.strip():
        # JDK 21's RFC report adds one display-only owner line. It is never
        # identity evidence: the fingerprint and subject below come from DER.
        # https://github.com/openjdk/jdk21u/blob/master/src/java.base/share/classes/sun/security/tools/keytool/Main.java
        block = re.match(r"\s*Certificate #(\d+):\s*"
                         r"(?:Certificate owner: [\x20-\x7e]{1,4096}\r?\n\s*)?"
                         r"-----BEGIN CERTIFICATE-----\s*([A-Za-z0-9+/=\r\n]+)\s*"
                         r"-----END CERTIFICATE-----\s*", remaining)
        if not block or int(block[1]) != len(certificates) + 1 or len(certificates) >= 10:
            raise ValueError("Unsupported or multiple embedded public signer chains")
        decoded = base64.b64decode(block[2].replace("\r", "").replace("\n", ""), validate=True)
        if not 0 < len(decoded) <= 64 * 1024:
            raise ValueError("Public signer certificate exceeds supported bounds")
        certificates.append(decoded)
        remaining = remaining[block.end():]
    if not certificates or len(set(certificates)) != len(certificates):
        raise ValueError("Missing or duplicate public signer certificates")
    actual = hashlib.sha256(certificates[0]).hexdigest()
    if actual != expected:
        raise ValueError("AAB signer does not match expected public upload certificate SHA256")
    names = subject_common_names(certificates[0])
    if not names or any(not name.strip() or re.fullmatch(r"(?i)android\s*debug(?:\s*key)?", name.strip()) for name in names):
        raise ValueError("Debug or unsupported unnamed upload certificate rejected")
    return {"upload_certificate_sha256": actual, "signer_count": 1,
            "certificate_chain_length": len(certificates), "known_debug_certificate_subject": False}


def validate_launch_edition(launch_edition: str) -> None:
    if launch_edition not in LAUNCH_EDITIONS:
        raise ValueError("Unsupported Android launch edition")


def verify_billing_dex_absence(artifact: Path, inventory: dict) -> dict:
    """Scan the validated ZIP in bounded chunks; no file extraction occurs.

    This proves absence of the reviewed class-string markers in every DEX
    payload, not absence of arbitrary obfuscated commerce code. Normal bundle
    validation and signature coverage remain separate mandatory gates.
    """
    dex_files = sorted(name for name in inventory["entries"] if name.lower().endswith(".dex"))
    if (not dex_files or any(inventory["entries"][name] <= 0 for name in dex_files)
            or sum(inventory["entries"][name] for name in dex_files) > MAX_EXPANDED_BYTES):
        raise ValueError("Free offline AAB DEX inventory exceeds supported limits")
    overlap = max(len(marker) for marker in BILLING_DEX_CLASS_MARKERS) - 1
    inspected = {}
    with zipfile.ZipFile(artifact) as archive:
        for name in dex_files:
            digest = hashlib.sha256()
            scanned = 0
            tail = b""
            with archive.open(name) as stream:
                while chunk := stream.read(DEX_READ_CHUNK_BYTES):
                    scanned += len(chunk)
                    if scanned > inventory["entries"][name]:
                        raise ValueError("Free offline AAB DEX size differs from validated ZIP inventory")
                    digest.update(chunk)
                    window = tail + chunk
                    if any(marker in window for marker in BILLING_DEX_CLASS_MARKERS):
                        raise ValueError("Free offline AAB contains native billing/provider DEX class strings")
                    tail = window[-overlap:]
            if scanned != inventory["entries"][name]:
                raise ValueError("Free offline AAB DEX size differs from validated ZIP inventory")
            inspected[name] = {"sha256": digest.hexdigest(), "bytes_scanned": scanned}
    return {"verified": True, "method": "bounded_dex_class_string_scan",
            "dex_files": inspected,
            "forbidden_class_string_markers": [marker.decode("ascii") for marker in BILLING_DEX_CLASS_MARKERS],
            "matched_class_string_markers": [], "arbitrary_obfuscated_code_absence_verified": False}


def validate_manifest(xml: str, module: str, *, package: str, version: str, build: int,
                      min_sdk: int, target_sdk: int, launch_edition: str = "commerce") -> dict:
    validate_launch_edition(launch_edition)
    if len(xml.encode()) > 2 * 1024 * 1024 or re.search(r"<!\s*(?:DOCTYPE|ENTITY)", xml, re.I):
        raise ValueError("Unsupported AAB manifest XML")
    root = ET.fromstring(xml)
    if root.tag != "manifest" or root.get("package") != package:
        raise ValueError("Actual AAB manifest package mismatch")
    for attribute, expected in (("versionCode", str(build)), ("versionName", version)):
        if module == "base" or ANDROID + attribute in root.attrib:
            if root.get(ANDROID + attribute) != expected:
                raise ValueError("Actual AAB manifest version/build mismatch")
    if any(node.get(DIST + "instant", "false") != "false" for node in root.iter()):
        raise ValueError("Instant modules are unsupported")
    if launch_edition == "free_offline_mvp":
        if any(node.tag in ("uses-permission", "uses-permission-sdk-23")
               and node.get(ANDROID + "name") == BILLING_PERMISSION for node in root.iter()):
            raise ValueError("Free offline AAB must not declare native billing permission")
        if any(node.tag == "meta-data" and "GodotGooglePlayBilling" in node.get(ANDROID + key, "")
               for node in root.iter() for key in ("name", "value")):
            raise ValueError("Free offline AAB must not declare native billing singleton metadata")
    if module != "base":
        declarations = root.findall(DIST + "module")
        if (root.get("split") != module or len(declarations) != 1
                or declarations[0].get(DIST + "type") != "asset-pack"
                or root.findall("application") or root.findall("uses-permission")):
            raise ValueError("Non-base module must be an asset-only pack")
        deliveries = declarations[0].findall(DIST + "delivery")
        if (len(deliveries) != 1 or len(list(deliveries[0])) != 1
                or list(deliveries[0])[0].tag != DIST + "install-time"
                or len(list(list(deliveries[0])[0]))):
            raise ValueError("Only unconditional install-time asset packs are supported")
        return {"module": module, "delivery": "install-time", "manifest_sha256": hashlib.sha256(xml.encode()).hexdigest()}
    if root.get("split") not in (None, "base"):
        raise ValueError("Actual base manifest must not identify a feature split")
    sdk = root.findall("uses-sdk")
    applications = root.findall("application")
    if (len(sdk) != 1 or sdk[0].get(ANDROID + "minSdkVersion") != str(min_sdk)
            or sdk[0].get(ANDROID + "targetSdkVersion") != str(target_sdk) or len(applications) != 1):
        raise ValueError("Actual AAB SDK/application manifest mismatch")
    app = applications[0]
    for key in ("debuggable", "testOnly", "profileableByShell"):
        if app.get(ANDROID + key, "false") != "false":
            raise ValueError("Actual AAB must disable debug/test/profileable release flags")
    if any(node.get(ANDROID + "shell", "true") != "false" for node in app.findall("profileable")):
        raise ValueError("Actual AAB must disable shell profiling")
    if launch_edition == "commerce":
        if not any(node.get(ANDROID + "name") == BILLING_PERMISSION for node in root.findall("uses-permission")):
            raise ValueError("Actual AAB billing permission missing")
        providers = [n for n in app.findall("meta-data") if n.get(ANDROID + "name") == PROVIDER_KEY]
        if len(providers) != 1 or providers[0].get(ANDROID + "value") != PROVIDER_CLASS:
            raise ValueError("Actual AAB billing singleton metadata missing or ambiguous")
    return {"module": "base", "package": package, "version": version, "build_number": build,
            "min_sdk": min_sdk, "target_sdk": target_sdk, "release_flags_verified": True,
            "launch_edition": launch_edition, "billing_manifest_verified": launch_edition == "commerce",
            "native_billing_manifest_absence_verified": launch_edition == "free_offline_mvp",
            "manifest_sha256": hashlib.sha256(xml.encode()).hexdigest()}


def run_tool(command: list[str], env: dict[str, str], label: str) -> str:
    result = subprocess.run(command, env=env, text=True, encoding="utf-8", errors="strict",
                            capture_output=True, timeout=120, check=False)
    if result.returncode or len(result.stdout.encode()) + len(result.stderr.encode()) > MAX_OUTPUT_BYTES:
        raise ValueError(f"{label} failed or exceeded output bounds (exit {result.returncode})")
    # Tool stderr is deliberately not included in receipts or error messages.
    if result.stderr.strip():
        raise ValueError(f"{label} produced unsupported stderr")
    return result.stdout


def verify(artifact: Path, *, artifact_sha256: str, upload_certificate_sha256: str,
           package: str, version: str, build_number: int, bundletool: Path, jdk: Path,
           launch_edition: str = "commerce") -> dict:
    validate_launch_edition(launch_edition)
    expected_artifact = fingerprint(artifact_sha256, "Artifact SHA256")
    expected_certificate = fingerprint(upload_certificate_sha256, "Upload certificate SHA256")
    if (not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*){2,}", package)
            or not re.fullmatch(r"\d+\.\d+\.\d+", version)
            or type(build_number) is not int or not 1 <= build_number <= 2100000000):
        raise ValueError("Expected package/version/build identity is invalid")
    artifact = regular_file(artifact, "AAB")
    bundletool = regular_file(bundletool, "Existing bundletool JAR")
    if artifact.suffix != ".aab" or bundletool.suffix != ".jar" or not 0 < artifact.stat().st_size <= MAX_ARTIFACT_BYTES:
        raise ValueError("Only a bounded existing .aab and .jar are supported")
    if not jdk.is_absolute() or jdk.is_symlink() or not jdk.is_dir():
        raise ValueError("Existing JDK must be an explicit absolute directory")
    jdk = jdk.resolve()
    tools = {name: regular_file(jdk / "bin" / name, f"Existing JDK {name}") for name in ("java", "jarsigner", "keytool")}
    if any(not os.access(path, os.X_OK) for path in tools.values()):
        raise ValueError("Existing JDK tools must be executable")
    if sha256(artifact) != expected_artifact:
        raise ValueError("AAB artifact SHA256 mismatch; no tools were run")
    tool_hashes = {str(path): sha256(path) for path in (bundletool, *tools.values())}
    inventory = zip_inventory(artifact)
    billing_absence = verify_billing_dex_absence(artifact, inventory) if launch_edition == "free_offline_mvp" else None
    android = read_config()["android"]
    with tempfile.TemporaryDirectory(prefix="waddle-android-verify-", dir="/tmp") as java_user_dir:
        flags = [f"-Duser.home={java_user_dir}", "-Duser.language=en", "-Duser.country=US",
                 "-Duser.timezone=UTC", "-Dcom.sun.security.enableAIAcaIssuers=false",
                 "-Dcom.sun.security.enableCRLDP=false"]
        env = {"PATH": str(jdk / "bin") + os.pathsep + "/usr/bin:/bin", "LANG": "C", "LC_ALL": "C", "TZ": "UTC"}
        jar_output = run_tool([str(tools["jarsigner"]), *["-J" + f for f in flags], "-verify", "-verbose:all", str(artifact)], env, "jarsigner verification")
        signature = verify_jar_report(jar_output, inventory)
        certificate_output = run_tool([str(tools["keytool"]), *["-J" + f for f in flags], "-printcert", "-jarfile", str(artifact), "-rfc"], env, "Embedded public certificate inspection")
        signer = public_signer(certificate_output, expected_certificate)
        validation_output = run_tool([str(tools["java"]), *flags, "-jar", str(bundletool), "validate",
                                      "--bundle=" + str(artifact)], env, "bundletool format validation")
        format_validation = validate_bundle_summary(validation_output, inventory)
        manifests = []
        for module in inventory["modules"]:
            xml = run_tool([str(tools["java"]), *flags, "-jar", str(bundletool), "dump", "manifest", "--bundle=" + str(artifact), "--module=" + module], env, "bundletool manifest inspection")
            manifests.append(validate_manifest(xml, module, package=package, version=version,
                                              build=build_number, min_sdk=android["min_sdk"], target_sdk=android["target_sdk"],
                                              launch_edition=launch_edition))
        # The existing checker invokes 'java'; this child-only PATH selects the
        # explicit JDK. Constructed options isolate its default user keystore too.
        checker_env = {**env, "JDK_JAVA_OPTIONS": " ".join(flags)}
        checked = run_tool([sys.executable, str(CHECKER), str(artifact), "--bundletool", str(bundletool)], checker_env, "Existing Android structural checker")
        structural = json.loads(checked)
        if (not isinstance(structural, dict) or structural.get("structural_gate_passed") is not True
                or structural.get("store_ready") is not False or structural.get("failures") != []
                or not isinstance(structural.get("libraries"), dict)
                or sorted(structural["libraries"]) != inventory["libraries"]
                or any(findings != [] for findings in structural["libraries"].values())
                or not isinstance(structural.get("packaging"), str)
                or "PAGE_ALIGNMENT_16K" not in structural["packaging"]):
            raise ValueError("Existing Android structural checker did not pass expected AAB inventory")
    if sha256(artifact) != expected_artifact:
        raise ValueError("AAB changed during verification; all acceptance discarded")
    if any(sha256(Path(path)) != digest for path, digest in tool_hashes.items()):
        raise ValueError("Selected verification tool changed during verification")
    if billing_absence is not None:
        billing_absence.update(permission_absence_verified=True, provider_metadata_absence_verified=True)
    remaining_gates = ["Play registered upload-certificate comparison and app-signing identity",
                       "real-device gameplay/lifecycle and 16-KB runtime"]
    if launch_edition == "commerce":
        remaining_gates.append("native billing acceptance")
    remaining_gates.append("privacy, listing and store acceptance")
    return {"schema_version": 1, "state": "android_upload_artifact_verified_offline",
            "launch_edition": launch_edition,
            "artifact": str(artifact), "artifact_sha256": expected_artifact,
            **signature, **signer, "manifests": manifests, "android_16kb": structural,
            "bundletool_validation": format_validation,
            "game_resource_presence": inventory["game_resource_presence"],
            "bundletool_sha256": tool_hashes[str(bundletool)], "jdk": str(jdk), "tool_sha256": tool_hashes,
            "store_ready": False, "play_registration_verified": False,
            "play_app_signing_certificate_verified": False, "device_tested": False,
            "billing_purchases_verified": False, "certificate_revocation_checked": False,
            "native_billing_sdk_absence_verified": billing_absence is not None,
            "native_billing_sdk_absence": billing_absence,
            "billing_acceptance_required": launch_edition == "commerce",
            "billing_purchases_deferred": launch_edition == "free_offline_mvp",
            "remaining_gates": remaining_gates}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=Path)
    parser.add_argument("--artifact-sha256", required=True)
    parser.add_argument("--upload-certificate-sha256", required=True)
    parser.add_argument("--package", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", type=int, required=True)
    parser.add_argument("--bundletool", type=Path, required=True)
    parser.add_argument("--jdk", type=Path, required=True)
    parser.add_argument("--launch-edition", default="commerce", help="commerce (default) or free_offline_mvp")
    args = parser.parse_args(argv)
    try:
        result = verify(args.artifact, artifact_sha256=args.artifact_sha256,
                        upload_certificate_sha256=args.upload_certificate_sha256,
                        package=args.package, version=args.version, build_number=args.build_number,
                        bundletool=args.bundletool, jdk=args.jdk, launch_edition=args.launch_edition)
        print(json.dumps(result, indent=2))
        return 0
    except (ValueError, OSError, UnicodeError, binascii.Error, zipfile.BadZipFile,
            ET.ParseError, subprocess.TimeoutExpired, RuntimeError, zlib.error) as error:
        print(json.dumps({"state": "android_upload_artifact_rejected", "store_ready": False,
                          "signature_verified": False, "error": str(error)}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
