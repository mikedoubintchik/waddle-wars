#!/usr/bin/env python3
"""Read provisioning metadata, optionally after a pinned Apple CMS verifier.

Decoded-only metadata success exits 2: CMS signature trust remains UNVERIFIED.
Signed mode uses the explicit hash-pinned native helper, never `security cms`.
Neither mode imports certificates, uses private keys, or authorizes signing.
Certificate hashes bind supplied public DER bytes, not their validity or trust.
Do not use `security cms -D` here: Apple's cmsutil imports embedded certificates
with keepcerts=true and does not require signer verification success for output.
Source: https://github.com/apple-oss-distributions/Security/blob/main/SecurityTool/macOS/cmsutil.c
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import uuid
from xml.parsers.expat import ExpatError

MAX_PLIST_BYTES = 8 * 1024 * 1024
BLOCKED = {"cms_signature_trust": "UNVERIFIED", "signing_authorized": False, "store_ready": False}


def certificate_fingerprint(value: str) -> str:
    result = value.replace(":", "").replace(" ", "").upper()
    if not re.fullmatch(r"[0-9A-F]{40}", result):
        raise ValueError("Expected certificate SHA1 must contain exactly 40 hexadecimal digits")
    return result


def utc_date(value: object) -> datetime:
    if not isinstance(value, datetime):
        raise ValueError("Profile dates must be plist dates")
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def validate_metadata(profile: object, *, team_id: str, app_id: str,
                      certificate_sha1: str, profile_name: str,
                      now: datetime | None = None) -> dict:
    """Validate App Store metadata only; every result remains signing-blocked."""
    expected_sha1 = certificate_fingerprint(certificate_sha1)
    if not re.fullmatch(r"[A-Z0-9]{10}", team_id):
        raise ValueError("Expected team ID must be 10 uppercase alphanumeric characters")
    if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", app_id):
        raise ValueError("Expected app ID must be an explicit bundle ID without wildcards")
    if not profile_name or len(profile_name) > 256 or any(ord(c) < 32 for c in profile_name):
        raise ValueError("Expected profile name must be a nonempty printable name")
    if not isinstance(profile, dict) or not isinstance(profile.get("Entitlements"), dict):
        raise ValueError("Decoded plist must contain provisioning profile entitlements")
    entitlements = profile["Entitlements"]
    application_identifier = f"{team_id}.{app_id}"
    if (profile.get("TeamIdentifier") != [team_id]
            or profile.get("ApplicationIdentifierPrefix") != [team_id]
            or entitlements.get("com.apple.developer.team-identifier") != team_id
            or entitlements.get("application-identifier") != application_identifier):
        raise ValueError("Profile team, prefix, or application identifier mismatch")
    if profile.get("Name") != profile_name:
        raise ValueError("Profile name mismatch")
    platforms = profile.get("Platform")
    if not isinstance(platforms, list) or not all(isinstance(p, str) for p in platforms) or "iOS" not in platforms:
        raise ValueError("Profile must target iOS")
    if (entitlements.get("get-task-allow") is not False
            or entitlements.get("beta-reports-active") is not True
            or "ProvisionedDevices" in profile
            or profile.get("ProvisionsAllDevices", False) is not False):
        raise ValueError("Profile is not App Store distribution metadata")
    try:
        profile_uuid = uuid.UUID(profile["UUID"])
        if profile_uuid.int == 0:
            raise ValueError
    except (KeyError, ValueError, TypeError, AttributeError):
        raise ValueError("Profile UUID is missing or invalid") from None
    created = utc_date(profile.get("CreationDate"))
    expires = utc_date(profile.get("ExpirationDate"))
    current = utc_date(now if now is not None else datetime.now(timezone.utc))
    if created > current or expires <= current or expires <= created:
        raise ValueError("Profile is expired, not yet valid, or has invalid date ordering")
    certificates = profile.get("DeveloperCertificates")
    if (not isinstance(certificates, list) or not 1 <= len(certificates) <= 32
            or any(not isinstance(c, bytes) or not 1 <= len(c) <= 1024 * 1024 for c in certificates)):
        raise ValueError("Profile must contain bounded public certificate data")
    matching = next((c for c in certificates if hashlib.sha1(c).hexdigest().upper() == expected_sha1), None)
    if matching is None:
        raise ValueError("Expected public certificate fingerprint is absent")
    return {
        "state": "metadata_valid_signing_blocked", "metadata_valid": True, **BLOCKED,
        "profile_uuid": str(profile_uuid), "profile_name": profile_name,
        "team_id": team_id, "app_id": app_id, "application_identifier": application_identifier,
        "distribution_metadata": "app-store", "creation_date": created.isoformat(),
        "expiration_date": expires.isoformat(), "certificate_count": len(certificates),
        "matched_certificate_sha1": expected_sha1,
        "matched_certificate_sha256": hashlib.sha256(matching).hexdigest(),
        "remaining_gate": "Apple CMS trust and signed archive validation; metadata cannot authorize signing",
    }


def inspect_decoded_plist(path: Path, **expected: object) -> dict:
    if path.is_symlink() or not path.is_file():
        raise ValueError("Decoded plist must be an explicit regular file, not a symlink")
    with path.open("rb") as handle:
        raw = handle.read(MAX_PLIST_BYTES + 1)
    if len(raw) > MAX_PLIST_BYTES:
        raise ValueError("Decoded plist exceeds size limit")
    try:
        profile = plistlib.loads(raw)
    except (plistlib.InvalidFileException, ValueError, TypeError, OverflowError, ExpatError):
        raise ValueError("Input is not an already-decoded plist; CMS profiles are not decoded by this tool") from None
    result = validate_metadata(profile, **expected)
    result["decoded_plist_sha256"] = hashlib.sha256(raw).hexdigest()
    return result


def inspect_signed_profile(path: Path, *, cms_helper: Path, cms_helper_sha256: str,
                           **expected: object) -> dict:
    """Verify with pinned native Apple-policy helper; keep archive gate separate."""
    if not re.fullmatch(r"[0-9a-fA-F]{64}", cms_helper_sha256):
        raise ValueError("Expected native helper SHA256 is required")
    if cms_helper.is_symlink() or not cms_helper.is_file():
        raise ValueError("Native CMS helper must be a regular file")
    if cms_helper.stat().st_size > 16 * 1024 * 1024:
        raise ValueError("Native CMS helper exceeds size limit")
    if hashlib.sha256(cms_helper.read_bytes()).hexdigest() != cms_helper_sha256.lower():
        raise ValueError("Native CMS helper changed after compilation")
    if path.is_symlink() or not path.is_file():
        raise ValueError("Profile must be an explicit regular file")
    with path.open("rb") as handle:
        raw = handle.read(MAX_PLIST_BYTES + 1)
    if not raw or len(raw) > MAX_PLIST_BYTES:
        raise ValueError("Profile exceeds size limit or is empty")
    checked = subprocess.run([str(cms_helper.resolve())], input=raw, capture_output=True,
                             timeout=30, check=False)
    if checked.returncode != 0 or not checked.stdout or len(checked.stdout) > MAX_PLIST_BYTES:
        raise ValueError("Apple CMS signature or offline provisioning trust verification failed")
    try:
        profile = plistlib.loads(checked.stdout)
    except (plistlib.InvalidFileException, ValueError, TypeError, OverflowError, ExpatError):
        raise ValueError("Verified CMS content is not a provisioning plist") from None
    result = validate_metadata(profile, **expected)
    result.update({
        "state": "profile_signature_and_metadata_verified",
        "cms_signature_trust": "APPLE_PROVISIONING_POLICY_VERIFIED_OFFLINE",
        "cms_policy_oid": "1.2.840.113635.100.1.56", "cms_signer_count": 1,
        "revocation_freshness": "NOT_CHECKED_OFFLINE", "profile_eligible_for_archive": True,
        "mobileprovision_sha256": hashlib.sha256(raw).hexdigest(),
        "cms_helper_sha256": cms_helper_sha256.lower(),
        "remaining_gate": "Existing-key signed Xcode archive, embedded profile and code signature validation",
    })
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    inputs = parser.add_mutually_exclusive_group(required=True)
    inputs.add_argument("--decoded-plist", type=Path)
    inputs.add_argument("--mobileprovision", type=Path)
    parser.add_argument("--cms-helper", type=Path)
    parser.add_argument("--cms-helper-sha256")
    parser.add_argument("--team-id", required=True)
    parser.add_argument("--app-id", required=True)
    parser.add_argument("--certificate-sha1", required=True)
    parser.add_argument("--profile-name", required=True)
    args = parser.parse_args(argv)
    try:
        expected = {"team_id": args.team_id, "app_id": args.app_id,
                    "certificate_sha1": args.certificate_sha1, "profile_name": args.profile_name}
        if args.mobileprovision:
            if not args.cms_helper or not args.cms_helper_sha256:
                raise ValueError("Signed mode requires the compiled native helper and its SHA256")
            result = inspect_signed_profile(args.mobileprovision, cms_helper=args.cms_helper,
                                            cms_helper_sha256=args.cms_helper_sha256, **expected)
        else:
            result = inspect_decoded_plist(args.decoded_plist, **expected)
    except (ValueError, OSError, subprocess.TimeoutExpired):
        # Never echo input paths, plist payloads, UDIDs, or arbitrary parser errors.
        print(json.dumps({"state": "profile_rejected" if args.mobileprovision else "metadata_rejected",
                          "metadata_valid": False, **BLOCKED}), file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2))
    return 0 if args.mobileprovision else 2


if __name__ == "__main__":
    raise SystemExit(main())
