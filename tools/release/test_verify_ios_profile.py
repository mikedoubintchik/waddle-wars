"""Synthetic metadata tests only: no real profiles, keys, CMS tools, or SDKs."""
from datetime import datetime, timedelta, timezone
import hashlib
import io
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace

import verify_ios_profile as verifier

NOW = datetime(2026, 10, 1, tzinfo=timezone.utc)
PUBLIC_BYTES = b"synthetic-public-certificate-not-an-x509-certificate"
EXPECTED = {"team_id": "ABCDE12345", "app_id": "com.example.game",
            "certificate_sha1": hashlib.sha1(PUBLIC_BYTES).hexdigest(), "profile_name": "Synthetic App Store"}


def synthetic_profile():
    return {"Name": EXPECTED["profile_name"], "UUID": "88e2491b-2c5e-4f0e-b0d2-392a099bec93",
            "TeamIdentifier": [EXPECTED["team_id"]], "ApplicationIdentifierPrefix": [EXPECTED["team_id"]],
            "Platform": ["iOS"], "CreationDate": NOW - timedelta(days=1),
            "ExpirationDate": NOW + timedelta(days=365), "DeveloperCertificates": [PUBLIC_BYTES],
            "Entitlements": {"application-identifier": "ABCDE12345.com.example.game",
                             "com.apple.developer.team-identifier": "ABCDE12345",
                             "get-task-allow": False, "beta-reports-active": True}}


class ProfileMetadataTests(unittest.TestCase):
    def validate(self, profile):
        return verifier.validate_metadata(profile, **EXPECTED, now=NOW)

    def test_valid_metadata_never_authorizes_signing(self):
        result = self.validate(synthetic_profile())
        self.assertTrue(result["metadata_valid"])
        self.assertEqual(result["cms_signature_trust"], "UNVERIFIED")
        self.assertFalse(result["signing_authorized"])
        self.assertFalse(result["store_ready"])

    def test_wrong_identity_fields_rejected(self):
        replacements = {"TeamIdentifier": ["ZZZZZ12345"], "ApplicationIdentifierPrefix": ["ZZZZZ12345"],
                        "Name": "Other", "UUID": "invalid", "Platform": ["macOS"],
                        "DeveloperCertificates": [b"wrong-public-certificate"]}
        for key, value in replacements.items():
            with self.subTest(field=key):
                profile = synthetic_profile()
                profile[key] = value
                with self.assertRaises(ValueError):
                    self.validate(profile)

    def test_wrong_entitlement_identity_rejected(self):
        for key, value in (("application-identifier", "ABCDE12345.com.example.*"),
                           ("com.apple.developer.team-identifier", "ZZZZZ12345")):
            with self.subTest(field=key):
                profile = synthetic_profile()
                profile["Entitlements"][key] = value
                with self.assertRaises(ValueError):
                    self.validate(profile)

    def test_development_adhoc_enterprise_rejected(self):
        for key, value in (("ProvisionedDevices", []), ("ProvisionedDevices", ["synthetic-udid"]),
                           ("ProvisionsAllDevices", True), ("ProvisionsAllDevices", 0)):
            with self.subTest(field=key, value=value):
                profile = synthetic_profile()
                profile[key] = value
                with self.assertRaises(ValueError):
                    self.validate(profile)

    def test_distribution_flags_require_exact_booleans(self):
        for key, value in (("get-task-allow", True), ("get-task-allow", 0),
                           ("beta-reports-active", False), ("beta-reports-active", 1)):
            with self.subTest(field=key, value=value):
                profile = synthetic_profile()
                profile["Entitlements"][key] = value
                with self.assertRaises(ValueError):
                    self.validate(profile)

    def test_invalid_dates_rejected(self):
        for key, value in (("ExpirationDate", NOW), ("ExpirationDate", NOW - timedelta(days=2)),
                           ("CreationDate", NOW + timedelta(days=1)), ("ExpirationDate", "tomorrow")):
            with self.subTest(field=key):
                profile = synthetic_profile()
                profile[key] = value
                with self.assertRaises(ValueError):
                    self.validate(profile)

    def test_naive_plist_dates_treated_as_utc(self):
        profile = synthetic_profile()
        for key in ("CreationDate", "ExpirationDate"):
            profile[key] = profile[key].replace(tzinfo=None)
        self.assertTrue(self.validate(profile)["metadata_valid"])

    def test_malformed_profile_rejected(self):
        for profile in ([], {}, {"Entitlements": []}):
            with self.subTest(profile=profile), self.assertRaises(ValueError):
                self.validate(profile)

    def test_missing_required_metadata_rejected(self):
        for key in synthetic_profile():
            with self.subTest(field=key):
                profile = synthetic_profile()
                del profile[key]
                with self.assertRaises(ValueError):
                    self.validate(profile)

    def test_certificate_shape_and_expectation_rejected(self):
        for value in ([], ["not-bytes"], [b""], [PUBLIC_BYTES] * 33):
            with self.subTest(value=value):
                profile = synthetic_profile()
                profile["DeveloperCertificates"] = value
                with self.assertRaises(ValueError):
                    self.validate(profile)
        with self.assertRaises(ValueError):
            verifier.validate_metadata(synthetic_profile(), **{**EXPECTED, "certificate_sha1": "short"}, now=NOW)

    def test_result_does_not_dump_payload(self):
        profile = synthetic_profile()
        profile["PrivatePayload"] = "synthetic-private-marker"
        output = json.dumps(self.validate(profile))
        self.assertNotIn("synthetic-private-marker", output)
        self.assertNotIn(PUBLIC_BYTES.decode(), output)
        self.assertNotIn("Entitlements", output)

    def test_decoded_input_only_with_hash_and_no_mutation(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "synthetic.plist"
            profile = synthetic_profile()
            for key in ("CreationDate", "ExpirationDate"):
                profile[key] = profile[key].replace(tzinfo=None)
            raw = plistlib.dumps(profile)
            path.write_bytes(raw)
            result = verifier.inspect_decoded_plist(path, **EXPECTED, now=NOW)
            self.assertEqual(result["decoded_plist_sha256"], hashlib.sha256(raw).hexdigest())
            self.assertEqual(path.read_bytes(), raw)
            for invalid in (b"synthetic CMS data, not a decoded plist", b"<?xml version='1.0'?><plist><dict>"):
                path.write_bytes(invalid)
                with self.assertRaises(ValueError):
                    verifier.inspect_decoded_plist(path, **EXPECTED, now=NOW)

    def test_symlink_missing_and_oversize_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            missing = Path(folder) / "missing.plist"
            with self.assertRaises(ValueError):
                verifier.inspect_decoded_plist(missing, **EXPECTED, now=NOW)
            target = Path(folder) / "target.plist"
            target.write_bytes(b"x")
            linked = Path(folder) / "linked.plist"
            linked.symlink_to(target)
            with self.assertRaises(ValueError):
                verifier.inspect_decoded_plist(linked, **EXPECTED, now=NOW)
            with patch.object(verifier, "MAX_PLIST_BYTES", 0), self.assertRaises(ValueError):
                verifier.inspect_decoded_plist(target, **EXPECTED, now=NOW)

    def test_cli_metadata_success_exits_blocked(self):
        argv = ["--decoded-plist", "synthetic.plist", "--team-id", EXPECTED["team_id"],
                "--app-id", EXPECTED["app_id"], "--certificate-sha1", EXPECTED["certificate_sha1"],
                "--profile-name", EXPECTED["profile_name"]]
        with patch.object(verifier, "inspect_decoded_plist", return_value=self.validate(synthetic_profile())), \
                patch("sys.stdout", new_callable=io.StringIO) as output:
            self.assertEqual(verifier.main(argv), 2)
            self.assertFalse(json.loads(output.getvalue())["signing_authorized"])
        with patch.object(verifier, "inspect_decoded_plist", side_effect=ValueError("synthetic-private-marker")), \
                patch("sys.stderr", new_callable=io.StringIO) as error:
            self.assertEqual(verifier.main(argv), 1)
            self.assertNotIn("synthetic-private-marker", error.getvalue())


class SignedProfileTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.profile = Path(self.folder.name) / "synthetic.mobileprovision"
        self.profile.write_bytes(b"synthetic-signed-profile-input")
        self.helper = Path(self.folder.name) / "synthetic-helper"
        self.helper.write_bytes(b"synthetic-helper-binary-placeholder")
        self.helper_hash = hashlib.sha256(self.helper.read_bytes()).hexdigest()
        profile = synthetic_profile()
        for key in ("CreationDate", "ExpirationDate"):
            profile[key] = profile[key].replace(tzinfo=None)
        self.payload = plistlib.dumps(profile)

    def inspect(self):
        return verifier.inspect_signed_profile(self.profile, cms_helper=self.helper,
                                               cms_helper_sha256=self.helper_hash, **EXPECTED, now=NOW)

    def test_native_success_plus_metadata_keeps_archive_gate(self):
        with patch.object(verifier.subprocess, "run", return_value=SimpleNamespace(returncode=0, stdout=self.payload)) as run:
            result = self.inspect()
        self.assertEqual(result["cms_signature_trust"], "APPLE_PROVISIONING_POLICY_VERIFIED_OFFLINE")
        self.assertEqual(result["revocation_freshness"], "NOT_CHECKED_OFFLINE")
        self.assertTrue(result["profile_eligible_for_archive"])
        self.assertFalse(result["signing_authorized"])
        self.assertFalse(result["store_ready"])
        run.assert_called_once_with([str(self.helper.resolve())], input=self.profile.read_bytes(),
                                    capture_output=True, timeout=30, check=False)
        self.assertNotIn(PUBLIC_BYTES.decode(), json.dumps(result))

    def test_changed_helper_rejected_before_execution(self):
        self.helper.write_bytes(b"changed")
        with patch.object(verifier.subprocess, "run") as run, self.assertRaises(ValueError):
            self.inspect()
        run.assert_not_called()

    def test_native_failure_never_parses_payload(self):
        with patch.object(verifier.subprocess, "run", return_value=SimpleNamespace(returncode=1, stdout=self.payload)), \
                patch.object(verifier.plistlib, "loads") as loads, self.assertRaises(ValueError):
            self.inspect()
        loads.assert_not_called()

    def test_missing_or_invalid_verified_payload_rejected(self):
        for payload in (b"", b"not-a-plist", b"<?xml version='1.0'?><plist><dict>"):
            with self.subTest(payload=payload), \
                    patch.object(verifier.subprocess, "run", return_value=SimpleNamespace(returncode=0, stdout=payload)), \
                    self.assertRaises(ValueError):
                self.inspect()

    def test_valid_signature_does_not_bypass_expected_metadata(self):
        profile = synthetic_profile()
        profile["Name"] = "Wrong app profile"
        for key in ("CreationDate", "ExpirationDate"):
            profile[key] = profile[key].replace(tzinfo=None)
        with patch.object(verifier.subprocess, "run", return_value=SimpleNamespace(returncode=0, stdout=plistlib.dumps(profile))), \
                self.assertRaises(ValueError):
            self.inspect()

    def test_cli_signed_mode_requires_helper_hash_and_handles_timeout(self):
        argv = ["--mobileprovision", str(self.profile), "--team-id", EXPECTED["team_id"],
                "--app-id", EXPECTED["app_id"], "--certificate-sha1", EXPECTED["certificate_sha1"],
                "--profile-name", EXPECTED["profile_name"]]
        with patch("sys.stderr", new_callable=io.StringIO), patch.object(verifier, "inspect_signed_profile") as inspect:
            self.assertEqual(verifier.main(argv), 1)
            inspect.assert_not_called()
        argv.extend(["--cms-helper", str(self.helper), "--cms-helper-sha256", self.helper_hash])
        with patch("sys.stderr", new_callable=io.StringIO), \
                patch.object(verifier, "inspect_signed_profile", side_effect=subprocess.TimeoutExpired("synthetic", 30)):
            self.assertEqual(verifier.main(argv), 1)


if __name__ == "__main__":
    unittest.main()
