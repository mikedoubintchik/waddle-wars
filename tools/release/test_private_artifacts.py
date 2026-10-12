"""Synthetic signing/environment exclusion checks; never read real key files."""
from __future__ import annotations

from pathlib import Path
import subprocess
import tempfile
import unittest

from native_release import EXCLUDE_FILTER, PRIVATE_SUFFIXES, prepare, read_config, runtime_files


ROOT = Path(__file__).resolve().parents[2]
SIGNING_SUFFIXES = {
    ".key", ".p8", ".pk8", ".pkcs8", ".ppk", ".keystore", ".jks",
    ".p12", ".pfx", ".mobileprovision", ".provisionprofile", ".csr",
}
PUBLIC_SUFFIXES = {".cer", ".crt", ".der"}


class PrivateArtifactTests(unittest.TestCase):
    def ignored_paths(self, paths: list[str]) -> set[str]:
        with tempfile.TemporaryDirectory(prefix="ww-ignore-fixture-") as temporary:
            directory = Path(temporary)
            # Only the committed exclusion policy is read. No local .envrc,
            # credentials, keys, provisioning profiles or keychain are opened.
            (directory / ".gitignore").write_text((ROOT / ".gitignore").read_text())
            subprocess.run(["git", "init", "--quiet", str(directory)], check=True,
                           capture_output=True, text=True)
            result = subprocess.run(
                ["git", "-C", str(directory), "-c", "core.excludesFile=/dev/null",
                 "check-ignore", "--no-index", "--stdin", "-z"],
                input="\0".join(paths) + "\0", capture_output=True, text=True)
            self.assertIn(result.returncode, (0, 1), result.stderr)
            return {value for value in result.stdout.split("\0") if value}

    def runtime_fixture(self, directory: Path) -> Path:
        source = directory / "source"
        (source / "assets").mkdir(parents=True)
        (source / "project.godot").write_text(
            'config_version=5\n[application]\nconfig/name="Synthetic artifact fixture"\n')
        return source

    def test_environment_secrets_ignored_at_root_and_nested(self) -> None:
        names = [".envrc", ".env", ".env.local", ".env.production",
                 ".env.android-signing", "native/signing/.envrc", "tools/private/.env.local"]
        self.assertEqual(set(names), self.ignored_paths(names))

    def test_environment_examples_remain_trackable(self) -> None:
        names = [".env.example", ".env.sample", ".env.template", ".envrc.example",
                 ".envrc.sample", ".envrc.template", ".env.production.example",
                 "tools/release/.env.signing.template", "leaderboard/.env.sample"]
        self.assertEqual(set(), self.ignored_paths(names))

    def test_signing_outputs_ignored_case_insensitively_everywhere(self) -> None:
        names = []
        for suffix in sorted(SIGNING_SUFFIXES):
            for variant in (suffix, suffix.upper(), suffix.title()):
                names.extend(["fixture" + variant, "native/signing/fixture" + variant,
                              "assets/accidental/fixture" + variant])
        self.assertEqual(set(names), self.ignored_paths(names))

    def test_public_verifier_certificates_not_blanket_ignored(self) -> None:
        names = ["leaderboard/certs/public-root.pem", "public-root.pem"]
        names.extend("data/trust/public-root" + suffix for suffix in sorted(PUBLIC_SUFFIXES))
        self.assertEqual(set(), self.ignored_paths(names))

    def test_private_suffixes_and_export_filter_cover_every_signing_output(self) -> None:
        self.assertTrue(SIGNING_SUFFIXES <= PRIVATE_SUFFIXES)
        patterns = set(EXCLUDE_FILTER.split(","))
        for suffix in PRIVATE_SUFFIXES:
            with self.subTest(suffix=suffix):
                self.assertIn("*" + suffix, patterns)
        self.assertTrue({".envrc", ".env*"} <= patterns)
        self.assertFalse(PUBLIC_SUFFIXES & PRIVATE_SUFFIXES)
        self.assertFalse({"*" + suffix for suffix in PUBLIC_SUFFIXES} & patterns)

    def test_runtime_snapshot_rejects_private_suffixes_before_read_or_copy(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ww-runtime-private-fixture-") as temporary:
            source = self.runtime_fixture(Path(temporary))
            for suffix in sorted(PRIVATE_SUFFIXES):
                for variant in (suffix, suffix.upper(), suffix.title()):
                    with self.subTest(suffix=variant):
                        artifact = source / "assets" / ("synthetic" + variant)
                        artifact.write_bytes(b"SYNTHETIC SIGNING FIXTURE ONLY")
                        with self.assertRaisesRegex(ValueError, "Signing/private file found"):
                            runtime_files(source)
                        artifact.unlink()

    def test_prepare_rejects_private_artifact_without_partial_destination(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ww-prepare-private-fixture-") as temporary:
            directory = Path(temporary)
            source = self.runtime_fixture(directory)
            (source / "assets" / "synthetic.p8").write_bytes(b"SYNTHETIC KEY ONLY")
            destination = directory / "candidate"
            with self.assertRaisesRegex(ValueError, "Signing/private file found"):
                prepare(source, destination, read_config(), "android", "1.0.0", 1, "", None)
            self.assertFalse(destination.exists())

    def test_public_runtime_certificates_allowed_and_backend_pem_stays_outside_snapshot(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ww-public-cert-fixture-") as temporary:
            source = self.runtime_fixture(Path(temporary))
            expected = {"project.godot"}
            for suffix in sorted(PUBLIC_SUFFIXES):
                artifact = source / "assets" / ("public-root" + suffix)
                artifact.write_bytes(b"SYNTHETIC PUBLIC CERTIFICATE ONLY")
                expected.add(artifact.relative_to(source).as_posix())
            backend = source / "leaderboard" / "certs"
            backend.mkdir(parents=True)
            (backend / "public-root.pem").write_bytes(b"SYNTHETIC PUBLIC CERTIFICATE ONLY")
            actual = {path.relative_to(source).as_posix() for path in runtime_files(source)}
            self.assertEqual(expected, actual)


if __name__ == "__main__":
    unittest.main()
