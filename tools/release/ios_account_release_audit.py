#!/usr/bin/env python3
"""Read-only continuity gate for an optional-account iOS internal TestFlight upload.

Pairs the existing strict signed IPA verifier with explicit, retained account
acceptance evidence. Never runs a game, accesses credentials, uploads, changes
store metadata, or certifies App Review readiness. Offline-only release_audit.py
continues to reject account-enabled builds. Account behavior is tested against
exact frozen Worker bytes in isolated real D1 plus native-client integration;
production scope is native authentication UI and read-only deployment evidence.
No synthetic live accounts/scores or destructive production tests are required.
"""
from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path

from native_release import sha256
from release_audit import read_record, source_snapshot

ISSUER = "https://clerk.waddlewars.io"
CHECKS = (
    "production_backend",
    "native_signin_cancel_refresh_signout",
    "scores_and_private_alias",
    "cloud_save_roundtrip",
    "account_deletion_and_write_fence",
    "offline_guest_and_no_payments",
    "account_data_inventory",
)
POLICIES = ("privacy.html", "support.html", "delete-data.html")
# Observed on all three production policy pages on 2026-10-09. This is one
# exact edge insertion, including its public site token, SRI and trailing LF.
# Do not strip arbitrary scripts, attributes, whitespace, or analytics markup.
CLOUDFLARE_POLICY_BEACON = (
    b'<script type="module" src="https://static.cloudflareinsights.com/beacon.min.js/'
    b'v4bc70e2c01a94c73b74392e4234840661791215815920" '
    b'integrity="sha512-L0ha0OXavK/8okipN9F8BtP84dg9DUhPERbBXzwI6dgTA55d2+yweo3pn5CSFYs45/r8md2+xvUPtTdvTNRfjA==" '
    b'data-cf-beacon=\'{"version":"2024.11.0","token":"b5f02d80056544669aeda735a930efbe","r":1,"spa":2}\' '
    b'crossorigin="anonymous"></script>\n'
)


def policy_body_comparison(source: bytes, raw_https_body: bytes) -> dict:
    """Compare retained raw HTTPS bytes; permit only the pinned edge insertion."""
    method = "mismatch"
    if raw_https_body == source:
        method = "exact_bytes"
    elif (source.count(b"</body>") == 1
          and b"static.cloudflareinsights.com" not in source
          and raw_https_body == source.replace(
              b"</body>", CLOUDFLARE_POLICY_BEACON + b"</body>", 1)):
        method = "exact_source_with_pinned_cloudflare_beacon"
    return {"matches": method != "mismatch", "method": method,
            "source_sha256": hashlib.sha256(source).hexdigest(),
            "raw_https_sha256": hashlib.sha256(raw_https_body).hexdigest(),
            "permitted_edge_script_sha256": hashlib.sha256(CLOUDFLARE_POLICY_BEACON).hexdigest()}


AFTER_UPLOAD = [
    "Verify Apple processing for this exact version/build and export-compliance answer.",
    "Save account-specific What to Test and Test Information; assign the exact build to Waddle Wars Internal (automatic distribution is disabled).",
    "Verify the TestFlight-installed build on iPhone, including production sign-in/cancel UI; inspect deletion entry/status access without submitting a deletion.",
]
BEFORE_APP_REVIEW = [
    "Reconcile and publish App Privacy for optional Clerk identity and synced gameplay, including Name, User ID and Gameplay Content where collected; retain provider/data-flow evidence.",
    "Verify an equivalent login option meeting guideline 4.8 for the configured Google sign-in, or document an applicable exception; existing Google login alone is not acceptance.",
    "Finish account-deletion provider/retention review and verify the in-app path on the selected store build.",
    "Update reviewer access/notes and choose the intended account-enabled build; reconcile screenshots and listing promises against it.",
    "Obtain App Review acceptance (external TestFlight testing may require Beta App Review first).",
]


def _pinned_file(value: object, label: str, errors: list[str]) -> Path | None:
    if not isinstance(value, dict):
        errors.append(f"{label}: missing file evidence")
        return None
    path = Path(value.get("path", "")) if isinstance(value.get("path", ""), str) else Path("")
    if not path.is_absolute() or not path.is_file() or path.is_symlink():
        errors.append(f"{label}: evidence file absent, relative, or symlinked")
        return None
    if value.get("sha256") != sha256(path):
        errors.append(f"{label}: evidence bytes changed")
        return None
    return path


def _timestamp(value: object) -> bool:
    try:
        return isinstance(value, str) and datetime.fromisoformat(value.replace("Z", "+00:00")).tzinfo is not None
    except ValueError:
        return False


def audit(root: Path, ios: Path, ios_run: Path, acceptance_path: Path) -> dict:
    errors: list[str] = []
    source_hash, source_files = source_snapshot(root)
    candidate = read_record(ios / "receipt.json")
    invocation = read_record(ios_run / "ipa-invocation.json")
    verification_path = ios_run / "ipa-verification-receipt.json"
    verification = read_record(verification_path)
    acceptance = read_record(acceptance_path)
    identity = {"source_sha256": source_hash, "version": candidate.get("version"),
                "build_number": candidate.get("build_number")}
    if candidate.get("source_sha256") != source_hash or candidate.get("source_files") != source_files:
        errors.append("iOS candidate source differs from current runtime")
    if (candidate.get("platform") != "ios" or candidate.get("state") != "exported_unverified"
            or candidate.get("launch_edition") != "free_offline_mvp"
            or candidate.get("native_accounts_enabled") is not True
            or candidate.get("native_clerk_issuer") != ISSUER):
        errors.append("Expected iOS optional-production-account export with purchases disabled")
    if not isinstance(identity["version"], str) or not identity["version"] or type(identity["build_number"]) is not int:
        errors.append("Missing iOS version/build identity")
    for label, record in (("IPA invocation", invocation), ("IPA verification", verification), ("Account acceptance", acceptance)):
        if any(record.get(key) != value for key, value in identity.items()):
            errors.append(f"{label} is not bound to current iOS source/version/build")
    if invocation.get("state") != "ios_ipa_verified_offline":
        errors.append("IPA export has not passed strict offline verification")
    if invocation.get("ipa_verification_receipt_sha256") != sha256(verification_path):
        errors.append("IPA verification receipt differs from pinned invocation")
    if (verification.get("state") != "ipa_verified" or verification.get("ipa_verified") is not True
            or verification.get("native_accounts_enabled") is not True
            or verification.get("native_clerk_issuer") != ISSUER
            or verification.get("store_ready") is not False):
        errors.append("Expected strict optional-production-account IPA verification receipt")
    for key in ("zip_path_safety_passed", "runtime_resource_hashes_match_archive",
                "info_plist_semantics_match_archive", "archived_pck_matches_export"):
        if verification.get(key) is not True:
            errors.append(f"IPA verification incomplete: {key}")
    artifact = invocation.get("artifact")
    ipa_path = _pinned_file(artifact, "IPA", errors)
    ipa_sha = artifact.get("sha256") if isinstance(artifact, dict) else None
    if (not ipa_sha or verification.get("ipa_sha256") != ipa_sha
            or acceptance.get("ipa_sha256") != ipa_sha
            or (ipa_path and verification.get("ipa_path") != str(ipa_path))):
        errors.append("IPA verification/acceptance does not identify the verified artifact")
    if invocation.get("archive_receipt_sha256") != verification.get("archive_receipt_sha256") or not verification.get("archive_receipt_sha256"):
        errors.append("IPA invocation and verification archive pins differ")
    if (acceptance.get("schema_version") != 1 or acceptance.get("state") != "ios_account_acceptance_recorded"
            or acceptance.get("native_clerk_issuer") != ISSUER
            or acceptance.get("native_runtime_environment") not in ("ios_simulator", "ios_device")
            or not _timestamp(acceptance.get("observed_at_utc"))):
        errors.append("Account acceptance is missing explicit native runtime/production identity/date")
    checks = acceptance.get("checks")
    checks = checks if isinstance(checks, dict) else {}
    for name in CHECKS:
        check = checks.get(name)
        if not isinstance(check, dict) or check.get("status") != "passed" or not isinstance(check.get("notes"), str) or not check["notes"].strip():
            errors.append(f"Account acceptance pending: {name}")
            continue
        evidence = check.get("evidence")
        if not isinstance(evidence, list) or not evidence:
            errors.append(f"Account acceptance has no retained evidence: {name}")
            continue
        for index, item in enumerate(evidence):
            _pinned_file(item, f"{name}[{index}]", errors)
    policies = acceptance.get("published_policies")
    policies = policies if isinstance(policies, dict) else {}
    policy_comparisons = {}
    for name in POLICIES:
        page = policies.get(name)
        page = page if isinstance(page, dict) else {}
        source = root / "web/native" / name
        if (not source.is_file() or source.is_symlink()
                or page.get("url") != f"https://waddlewars.io/native/{name}"
                or page.get("status") != 200 or not _timestamp(page.get("observed_at_utc"))):
            errors.append(f"Current HTTPS policy publication pending: {name}")
            continue
        body = _pinned_file(page.get("body"), f"Published policy {name}", errors)
        comparison = policy_body_comparison(source.read_bytes(), body.read_bytes()) if body else None
        policy_comparisons[name] = comparison
        if not comparison or not comparison["matches"]:
            errors.append(f"Published policy differs from current source: {name}")
    return {**identity, "native_clerk_issuer": ISSUER, "ios_ipa": str(ipa_path) if ipa_path else None,
            "ipa_sha256": ipa_sha, "account_acceptance_sha256": sha256(acceptance_path),
            "ready_for_internal_testflight_upload": not errors,
            "store_ready": False, "uploaded": False,
            "scope": "Receipt/evidence continuity, not independent runtime or App Store verification",
            "account_behavior_evidence_scope": "Exact frozen Worker in isolated real D1 plus native-client integration",
            "production_evidence_scope": "Native authentication UI and read-only deployment/configuration observations",
            "published_policy_comparisons": policy_comparisons,
            "live_production_deletion_verified_by_gate": False,
            "after_upload": AFTER_UPLOAD, "before_app_review": BEFORE_APP_REVIEW, "errors": errors}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--ios", type=Path, required=True)
    parser.add_argument("--ios-run", type=Path, required=True)
    parser.add_argument("--acceptance", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = audit(args.root.resolve(), args.ios.resolve(), args.ios_run.resolve(), args.acceptance.resolve())
    except (ValueError, OSError, KeyError, TypeError, json.JSONDecodeError) as error:
        result = {"ready_for_internal_testflight_upload": False, "store_ready": False, "errors": [str(error)]}
    print(json.dumps(result, indent=2))
    return 0 if result["ready_for_internal_testflight_upload"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
