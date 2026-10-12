"""Read-only source/artifact continuity checks for the upload gate."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from release_audit import audit, source_snapshot


class ReleaseAuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="waddle-release-audit-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "project"
        self.root.mkdir()
        (self.root / "project.godot").write_text("[application]\nconfig/name=\"Waddle Wars\"\n")
        self.ios = Path(self.temp.name) / "ios"
        self.run = Path(self.temp.name) / "ios-run"
        self.android = Path(self.temp.name) / "android"
        for path in (self.ios, self.run, self.android / "project/build"):
            path.mkdir(parents=True)
        fingerprint, files = source_snapshot(self.root)
        base = {"source_sha256": fingerprint, "source_files": files,
                "version": "1.0.0", "build_number": 40,
                "launch_edition": "free_offline_mvp"}
        self.save(self.ios / "receipt.json", {**base, "state": "exported_unverified"})
        self.save(self.android / "receipt.json", {**base, "state": "android_upload_artifact_verified_offline"})
        ipa = self.run / "waddlewars.ipa"
        ipa.write_bytes(b"fixture ipa")
        self.save(self.run / "ipa-invocation.json", {
            "state": "ios_ipa_verified_offline", "source_sha256": fingerprint,
            "artifact": {"path": str(ipa), "sha256": self.digest(ipa)}})
        aab = self.android / "project/build/waddle-wars.aab"
        aab.write_bytes(b"fixture aab")
        self.save(self.android.with_name("android-signing-launch.json"), {
            "state": "android_upload_artifact_verified_offline",
            "unsigned_sha256": "a" * 64, "signed_aab_sha256": self.digest(aab)})

    @staticmethod
    def digest(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    @staticmethod
    def save(path, value):
        path.write_text(json.dumps(value))

    def check(self):
        return audit(self.root, self.ios, self.run, self.android)

    def test_matching_receipts_and_artifacts_pass_offline_continuity(self):
        result = self.check()
        self.assertTrue(result["ready_for_upload_offline"])
        self.assertEqual(result["errors"], [])

    def test_runtime_change_blocks_upload(self):
        (self.root / "project.godot").write_text("changed")
        result = self.check()
        self.assertFalse(result["ready_for_upload_offline"])
        self.assertIn("iOS candidate source differs from current runtime", result["errors"])

    def test_artifact_change_blocks_upload(self):
        (self.android / "project/build/waddle-wars.aab").write_bytes(b"tampered")
        result = self.check()
        self.assertFalse(result["ready_for_upload_offline"])
        self.assertIn("Android AAB is absent or differs from verified bytes", result["errors"])

    def test_missing_ipa_blocks_upload(self):
        (self.run / "waddlewars.ipa").unlink()
        result = self.check()
        self.assertFalse(result["ready_for_upload_offline"])
        self.assertIn("iOS IPA is absent or differs from verified bytes", result["errors"])


if __name__ == "__main__":
    unittest.main()
