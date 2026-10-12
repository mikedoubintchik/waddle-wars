"""Synthetic continuity tests. Fixture bytes are never real signed artifacts."""
import json
from pathlib import Path
import tempfile
import unittest

from ios_account_release_audit import CHECKS, POLICIES, ISSUER, CLOUDFLARE_POLICY_BEACON, audit
from native_release import sha256
from release_audit import audit as offline_audit, source_snapshot


class AccountReleaseAuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="waddle-account-audit-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root, self.ios, self.run = [self.base / name for name in ("project", "ios", "run")]
        for directory in (self.root / "web/native", self.ios, self.run):
            directory.mkdir(parents=True)
        (self.root / "project.godot").write_text("[application]\nconfig/name=\"Waddle Wars\"\n")
        source, files = source_snapshot(self.root)
        self.identity = {"source_sha256": source, "version": "1.0.0", "build_number": 41}
        self.ipa = self.run / "fixture.ipa"
        self.ipa.write_bytes(b"Synthetic test fixture, not a signed app")
        self.proof = self.base / "synthetic-observation.txt"
        self.proof.write_text("Synthetic acceptance evidence for unit testing only")
        self.save(self.ios / "receipt.json", {**self.identity, "source_files": files,
            "platform": "ios", "state": "exported_unverified", "launch_edition": "free_offline_mvp",
            "native_accounts_enabled": True, "native_clerk_issuer": ISSUER})
        self.save(self.run / "ipa-verification-receipt.json", {**self.identity,
            "state": "ipa_verified", "ipa_verified": True, "store_ready": False,
            "native_accounts_enabled": True, "native_clerk_issuer": ISSUER,
            "ipa_path": str(self.ipa), "ipa_sha256": sha256(self.ipa), "archive_receipt_sha256": "a" * 64,
            "zip_path_safety_passed": True, "runtime_resource_hashes_match_archive": True,
            "info_plist_semantics_match_archive": True, "archived_pck_matches_export": True})
        self.save(self.run / "ipa-invocation.json", {**self.identity,
            "state": "ios_ipa_verified_offline", "artifact": self.pin(self.ipa),
            "archive_receipt_sha256": "a" * 64,
            "ipa_verification_receipt_sha256": sha256(self.run / "ipa-verification-receipt.json")})
        self.acceptance = self.base / "acceptance.json"
        pages = {}
        for name in POLICIES:
            page = self.root / "web/native" / name
            page.write_text("<!doctype html><title>Synthetic " + name + "</title><body>Policy</body>\n")
            captured = self.base / name
            captured.write_bytes(page.read_bytes())
            pages[name] = {"url": "https://waddlewars.io/native/" + name, "status": 200,
                "observed_at_utc": "2026-10-09T12:00:00Z", "body": self.pin(captured)}
        self.save(self.acceptance, {**self.identity, "schema_version": 1,
            "state": "ios_account_acceptance_recorded", "native_clerk_issuer": ISSUER,
            "ipa_sha256": sha256(self.ipa), "native_runtime_environment": "ios_simulator",
            "observed_at_utc": "2026-10-09T12:00:00Z",
            "checks": {name: {"status": "passed", "notes": "Synthetic fixture", "evidence": [self.pin(self.proof)]}
                       for name in CHECKS}, "published_policies": pages})

    @staticmethod
    def save(path, value):
        path.write_text(json.dumps(value))

    @staticmethod
    def pin(path):
        return {"path": str(path), "sha256": sha256(path)}

    def change(self, path, fn):
        value = json.loads(path.read_text())
        fn(value)
        self.save(path, value)

    def check(self):
        return audit(self.root, self.ios, self.run, self.acceptance)

    def rejected(self, fragment):
        result = self.check()
        self.assertFalse(result["ready_for_internal_testflight_upload"])
        self.assertTrue(any(fragment in error for error in result["errors"]), result["errors"])

    def test_complete_continuity_only_allows_internal_upload(self):
        result = self.check()
        self.assertEqual(result["errors"], [])
        self.assertTrue(result["ready_for_internal_testflight_upload"])
        self.assertFalse(result["store_ready"])
        self.assertFalse(result["uploaded"])
        self.assertFalse(result["live_production_deletion_verified_by_gate"])
        self.assertIn("isolated real D1", result["account_behavior_evidence_scope"])
        self.assertIn("read-only deployment", result["production_evidence_scope"])
        self.assertTrue(result["before_app_review"])
        self.assertTrue(result["after_upload"])

    def test_source_edit_invalidates_all_bound_acceptance(self):
        (self.root / "project.godot").write_text("changed runtime")
        self.rejected("source differs")

    def test_wrong_platform_and_disabled_or_nonproduction_accounts_rejected(self):
        path = self.ios / "receipt.json"
        original = path.read_text()
        for key, value in (("platform", "android"), ("native_accounts_enabled", False),
                           ("native_clerk_issuer", "https://test.clerk.accounts.dev"),
                           ("launch_edition", "commerce")):
            with self.subTest(key=key):
                path.write_text(original)
                self.change(path, lambda d: d.update({key: value}))
                self.rejected("production-account export")

    def test_old_build_acceptance_rejected(self):
        self.change(self.acceptance, lambda d: d.update(build_number=40))
        self.rejected("source/version/build")

    def test_wrong_ipa_acceptance_rejected(self):
        self.change(self.acceptance, lambda d: d.update(ipa_sha256="0" * 64))
        self.rejected("verified artifact")

    def test_ipa_mutation_rejected(self):
        self.ipa.write_bytes(b"different artifact")
        self.rejected("IPA: evidence bytes changed")

    def test_ipa_receipt_mutation_rejected(self):
        self.change(self.run / "ipa-verification-receipt.json", lambda d: d.update(ipa_verified=False))
        self.rejected("receipt differs")

    def test_archive_pin_mismatch_rejected(self):
        self.change(self.run / "ipa-invocation.json", lambda d: d.update(archive_receipt_sha256="b" * 64))
        self.rejected("archive pins differ")

    def test_each_pending_check_rejected(self):
        original = self.acceptance.read_text()
        for name in CHECKS:
            with self.subTest(check=name):
                self.acceptance.write_text(original)
                self.change(self.acceptance, lambda d: d["checks"][name].update(status="pending"))
                self.rejected("pending: " + name)

    def test_unretained_checks_rejected(self):
        self.change(self.acceptance, lambda d: d["checks"][CHECKS[0]].update(evidence=[]))
        self.rejected("no retained evidence")

    def test_evidence_mutation_rejected(self):
        self.proof.write_text("changed observation")
        self.rejected("evidence bytes changed")

    def test_missing_or_symlinked_evidence_rejected(self):
        self.proof.unlink()
        self.rejected("evidence file absent")
        target = self.base / "other.txt"
        target.write_text("different")
        self.proof.symlink_to(target)
        self.rejected("symlinked")

    def test_browser_runtime_cannot_stand_in_for_native_auth(self):
        self.change(self.acceptance, lambda d: d.update(native_runtime_environment="chrome"))
        self.rejected("native runtime")

    def test_missing_or_unzoned_observation_date_rejected(self):
        self.change(self.acceptance, lambda d: d.update(observed_at_utc="2026-10-09T12:00:00"))
        self.rejected("identity/date")

    def test_policy_source_changes_need_new_public_readback(self):
        (self.root / "web/native/privacy.html").write_text("new source policy")
        self.rejected("Published policy differs")

    def set_public_policy_body(self, body):
        captured = self.base / "privacy.html"
        captured.write_bytes(body)
        self.change(self.acceptance, lambda d: d["published_policies"]["privacy.html"].update(body=self.pin(captured)))

    def test_exact_known_edge_beacon_accepted_with_raw_evidence_preserved(self):
        source = (self.root / "web/native/privacy.html").read_bytes()
        raw = source.replace(b"</body>", CLOUDFLARE_POLICY_BEACON + b"</body>")
        self.set_public_policy_body(raw)
        result = self.check()
        self.assertTrue(result["ready_for_internal_testflight_upload"], result["errors"])
        compared = result["published_policy_comparisons"]["privacy.html"]
        self.assertEqual(compared["method"], "exact_source_with_pinned_cloudflare_beacon")
        self.assertEqual(compared["permitted_edge_script_sha256"], "6038e14ab937a6870fd9fb62160854c1c8b5046318627dede731e2d52a7bb3e1")
        self.assertEqual(compared["raw_https_sha256"], sha256(self.base / "privacy.html"))
        self.assertNotEqual(compared["raw_https_sha256"], compared["source_sha256"])
        self.assertEqual((self.base / "privacy.html").read_bytes(), raw)

    def test_unknown_edge_changes_fail_even_with_known_beacon(self):
        source = (self.root / "web/native/privacy.html").read_bytes()
        raw = source.replace(b"</body>", CLOUDFLARE_POLICY_BEACON + b"</body>")
        cases = {
            "policy text": raw.replace(b">Policy<", b">Changed policy<"),
            "script source": raw.replace(b"static.cloudflareinsights.com", b"example.com"),
            "site token": raw.replace(b"b5f02d80056544669aeda735a930efbe", b"a5f02d80056544669aeda735a930efbe"),
            "SRI": raw.replace(b"L0ha0OX", b"L1ha0OX"),
            "extra script": raw.replace(b"</body>", b"<script>alert(1)</script></body>"),
            "duplicate beacon": raw.replace(b"</body>", CLOUDFLARE_POLICY_BEACON + b"</body>"),
            "moved beacon": CLOUDFLARE_POLICY_BEACON + source,
            "whitespace": raw + b" ",
        }
        for name, body in cases.items():
            with self.subTest(change=name):
                self.set_public_policy_body(body)
                self.rejected("Published policy differs")

    def test_known_beacon_does_not_allow_stale_raw_body_pin(self):
        source = (self.root / "web/native/privacy.html").read_bytes()
        (self.base / "privacy.html").write_bytes(source.replace(b"</body>", CLOUDFLARE_POLICY_BEACON + b"</body>"))
        self.rejected("evidence bytes changed")

    def test_nonproduction_policy_or_error_response_rejected(self):
        original = self.acceptance.read_text()
        for key, value in (("url", "http://localhost/native/privacy.html"), ("status", 404)):
            self.acceptance.write_text(original)
            self.change(self.acceptance, lambda d: d["published_policies"]["privacy.html"].update({key: value}))
            self.rejected("HTTPS policy publication pending")

    def test_no_published_pages_cannot_pass(self):
        self.change(self.acceptance, lambda d: d.update(published_policies={}))
        self.rejected("HTTPS policy publication pending")

    def test_old_offline_gate_still_rejects_accounts(self):
        android = self.base / "android"
        (android / "project/build").mkdir(parents=True)
        record = json.loads((self.ios / "receipt.json").read_text())
        record.update(platform="android", native_accounts_enabled=False, state="android_upload_artifact_verified_offline")
        self.save(android / "receipt.json", record)
        aab = android / "project/build/waddle-wars.aab"
        aab.write_bytes(b"Synthetic Android fixture")
        self.save(android.with_name("android-signing-launch.json"), {
            "state": "android_upload_artifact_verified_offline", "unsigned_sha256": "a" * 64,
            "signed_aab_sha256": sha256(aab)})
        result = offline_audit(self.root, self.ios, self.run, android)
        self.assertFalse(result["ready_for_upload_offline"])
        self.assertTrue(any("requires separate account/privacy/runtime acceptance" in e for e in result["errors"]))


if __name__ == "__main__":
    unittest.main()
