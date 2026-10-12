"""Fastlane DSL/argv regressions. No helper, build, keychain or network calls.

Ruby evaluates the actual Fastfile against a tiny mock DSL. The subprocess can
only register lanes and capture sh arguments; it cannot invoke release helpers.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
FASTFILE = ROOT / "fastlane/Fastfile"
RUBY = shutil.which("ruby")
SIGNING = (
    "GODOT_ANDROID_KEYSTORE_RELEASE_PATH",
    "GODOT_ANDROID_KEYSTORE_RELEASE_USER",
    "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD",
)
DSL = r'''
require "json"
module UI
  def self.user_error!(message)
    raise ArgumentError, message
  end
end
$lanes = {}
$platform = nil
$calls = []
def fastlane_version(value)
  $fastlane_version = value
end
def desc(_value); end
def platform(value)
  previous = $platform
  $platform = value.to_s
  yield
ensure
  $platform = previous
end
def lane(name, &block)
  $lanes[[$platform, name.to_s]] = block
end
def sh(*command)
  $calls << command
  status = Struct.new(:exitstatus) do
    def success?; exitstatus.zero?; end
  end.new($request.fetch("helper_exit_code", 0))
  yield status, "Mocked public helper output", "Mocked variadic command"
end
load ARGV.fetch(0)
$request = JSON.parse(STDIN.read)
options = $request.fetch("options", {}).transform_keys(&:to_sym)
result = {}
begin
  if $request["direct_legacy_android"]
    waddle_build(options, "android")
  elsif $request["lane"]
    $lanes.fetch([$request["platform"], $request["lane"]]).call(options)
  end
rescue StandardError => error
  result["error"] = { "class" => error.class.name, "message" => error.message }
end
result["calls"] = $calls
result["lanes"] = $lanes.keys
result["fastlane_version"] = $fastlane_version
puts JSON.generate(result)
'''


@unittest.skipUnless(RUBY, "Ruby required for actual Fastfile DSL coverage")
class FastlaneAndroidTests(unittest.TestCase):
    def setUp(self) -> None:
        self.folder = tempfile.TemporaryDirectory(prefix="ww-fastlane-dsl-")
        self.addCleanup(self.folder.cleanup)
        # The signing helper rejects symlink ancestors; /var on macOS is one.
        self.root = Path(self.folder.name).resolve()
        self.candidate = self.root / "new candidate"
        self.options = {
            "candidate": str(self.candidate), "python": str(self.root / "Python executable"),
            "jdk": str(self.root / "Installed JDK"), "bundletool": str(self.root / "bundletool.jar"),
            "godot": str(self.root / "Godot executable"), "android_sdk": str(self.root / "Android SDK"),
            "version": "1.2.3", "build_number": "17",
        }

    def evaluate(self, options: dict | None = None, *, platform: str | None = "android",
                 lane: str | None = "build", **extra) -> dict:
        request = {"platform": platform, "lane": lane,
                   "options": self.options if options is None else options, **extra}
        # No real inherited signing values enter this test process. Sentinels
        # prove the captured child overrides them without reading key files.
        environment = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "LANG": "en_US.UTF-8"}
        environment.update({name: "SYNTHETIC_PARENT_SECRET" for name in SIGNING})
        result = subprocess.run([RUBY, "-e", DSL, str(FASTFILE)],
                                input=json.dumps(request), text=True, capture_output=True,
                                env=environment, check=False, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertNotIn("SYNTHETIC_PARENT_SECRET", result.stdout)
        return json.loads(result.stdout)

    def reject(self, options: dict, message: str) -> dict:
        result = self.evaluate(options)
        self.assertEqual(result["calls"], [])
        self.assertEqual(result["error"]["class"], "ArgumentError")
        self.assertIn(message, result["error"]["message"])
        return result

    def test_build_uses_only_safe_existing_signer_and_explicit_python(self) -> None:
        result = self.evaluate()
        self.assertNotIn("error", result)
        expected = [
            dict.fromkeys(SIGNING, ""), self.options["python"], "-I",
            str(ROOT / "tools/release/android_upload_signing.py"), "build", str(self.candidate),
            "--jdk", self.options["jdk"], "--bundletool", self.options["bundletool"],
            "--godot", self.options["godot"], "--android-sdk", self.options["android_sdk"],
            "--python", self.options["python"], "--version", "1.2.3", "--build-number", "17",
        ]
        self.assertEqual(result["calls"], [expected])
        self.assertNotIn("setup", expected)
        self.assertFalse(self.candidate.exists())
        self.assertFalse(self.candidate.with_name(self.candidate.name + "-signing-launch.json").exists())

    def test_every_tool_and_version_option_is_explicit(self) -> None:
        for name in self.options:
            with self.subTest(name=name):
                options = {key: value for key, value in self.options.items() if key != name}
                self.reject(options, "Missing required option " + name)

    def test_tools_must_be_absolute_without_path_search_fallback(self) -> None:
        for name in ("candidate", "python", "jdk", "bundletool", "godot", "android_sdk"):
            with self.subTest(name=name):
                self.reject({**self.options, name: "relative-tool"}, "must be an absolute path")

    def test_unknown_secret_and_legacy_options_are_not_echoed_or_forwarded(self) -> None:
        for name in ("password", "release_password", "keystore", "release_keystore", "keychain_password",
                     "upload_certificate_sha256", "templates", "setup", "bootstrap", "unknown",
                     "SYNTHETIC_SECRET_KEY"):
            with self.subTest(name=name):
                result = self.reject({**self.options, name: "SYNTHETIC_SECRET_VALUE"}, "not allowed")
                self.assertNotIn("SYNTHETIC_SECRET_VALUE", json.dumps(result))
                self.assertNotIn("SYNTHETIC_SECRET_KEY", json.dumps(result))

    def test_existing_prepared_candidate_is_rejected_without_reading_receipt(self) -> None:
        self.candidate.mkdir()
        # Deliberately invalid receipt; lane must not parse a stale candidate.
        (self.candidate / "receipt.json").write_text("NOT A RECEIPT")
        self.reject(self.options, "already exists")
        self.assertEqual((self.candidate / "receipt.json").read_text(), "NOT A RECEIPT")

    def test_existing_candidate_file_is_rejected(self) -> None:
        self.candidate.write_bytes(b"Preserved fixture")
        self.reject(self.options, "already exists")
        self.assertEqual(self.candidate.read_bytes(), b"Preserved fixture")

    def test_existing_signing_launch_receipt_is_rejected_without_overwrite(self) -> None:
        launch = self.candidate.with_name(self.candidate.name + "-signing-launch.json")
        launch.write_bytes(b"Preserved signing attempt")
        self.reject(self.options, "already exists")
        self.assertEqual(launch.read_bytes(), b"Preserved signing attempt")

    def test_broken_candidate_and_launch_symlinks_are_rejected(self) -> None:
        self.candidate.symlink_to(self.root / "missing-target")
        self.reject(self.options, "symlinks")
        self.candidate.unlink()
        launch = self.candidate.with_name(self.candidate.name + "-signing-launch.json")
        launch.symlink_to(self.root / "missing-target")
        self.reject(self.options, "already exists")

    def test_symlink_parent_is_rejected(self) -> None:
        parent = self.root / "linked-parent"
        parent.symlink_to(self.root, target_is_directory=True)
        self.reject({**self.options, "candidate": str(parent / "fresh")}, "symlinks")

    def test_checkout_traversal_and_missing_parent_are_rejected(self) -> None:
        for candidate in (str(ROOT), str(ROOT / "fresh"), str(ROOT.parent / "." / ROOT.name / "fresh")):
            with self.subTest(candidate=candidate):
                self.reject({**self.options, "candidate": candidate}, "outside the checkout")
        self.reject({**self.options, "candidate": str(self.root / "unused" / ".." / "fresh")}, "without traversal")
        self.reject({**self.options, "candidate": str(self.root / "missing-parent" / "fresh")}, "parent must already exist")

    def test_invalid_version_or_build_number_fails_before_dispatch(self) -> None:
        for version in ("1.0-beta", "1.0", "1.2.3\n", "", "--setup"):
            with self.subTest(version=version):
                self.reject({**self.options, "version": version}, "Missing required option" if not version else "numeric major.minor.patch")
        for build in ("0", "-1", "1.5", "2100000001", "17\n", "--setup"):
            with self.subTest(build=build):
                self.reject({**self.options, "build_number": build}, "unused build number")

    def test_argument_metacharacters_remain_separate_argv_not_shell_code(self) -> None:
        tool = str(self.root / 'Godot "quoted"; $(never-run)')
        result = self.evaluate({**self.options, "godot": tool})
        self.assertNotIn("error", result)
        command = result["calls"][0]
        self.assertEqual(command[command.index("--godot") + 1], tool)
        self.assertEqual(len(result["calls"]), 1)

    def test_nonzero_signing_helper_status_fails_without_fallback_or_bootstrap(self) -> None:
        result = self.evaluate(helper_exit_code=9)
        self.assertEqual(len(result["calls"]), 1)
        self.assertIn("android_upload_signing.py failed (exit 9)", result["error"]["message"])
        self.assertNotIn("build_native.py", json.dumps(result["calls"]))
        self.assertNotIn("setup", result["calls"][0])

    def test_legacy_android_prepared_build_method_cannot_be_called(self) -> None:
        result = self.evaluate(direct_legacy_android=True)
        self.assertEqual(result["calls"], [])
        self.assertIn("Prepared-candidate builds are iOS only", result["error"]["message"])

    def test_lane_registration_and_pinned_fastlane_are_preserved(self) -> None:
        result = self.evaluate(lane=None)
        self.assertEqual(result["fastlane_version"], "2.236.1")
        self.assertEqual(result["lanes"], [
            [None, "inspect"], ["ios", "prepare"], ["ios", "build"], ["ios", "verify_profile"],
            ["android", "prepare"], ["android", "build"], ["android", "verify_artifact"], ["android", "verify_release"],
        ])

    def test_android_prepare_remains_snapshot_only_not_signing_or_building(self) -> None:
        options = {"destination": str(self.candidate), "version": "1.2.3", "build_number": "17",
                   "templates": str(self.root / "4.7.1.stable")}
        result = self.evaluate(options, lane="prepare")
        self.assertNotIn("error", result)
        self.assertEqual(result["calls"], [["python3", str(ROOT / "tools/release/native_release.py"),
                                           "prepare", "android", str(self.candidate), "--version", "1.2.3",
                                           "--build-number", "17", "--templates", options["templates"]]])
        self.assertFalse(self.candidate.exists())

    def test_ios_prepare_and_build_keep_existing_helpers(self) -> None:
        prepared = self.evaluate({"destination": str(self.candidate), "version": "1.2.3", "build_number": "17",
                                  "team_id": "ABCDE12345"}, platform="ios", lane="prepare")
        self.assertNotIn("error", prepared)
        self.assertEqual(prepared["calls"][0][:4], ["python3", str(ROOT / "tools/release/native_release.py"), "prepare", "ios"])
        self.assertEqual(prepared["calls"][0][-2:], ["--team-id", "ABCDE12345"])
        self.candidate.mkdir()
        (self.candidate / "receipt.json").write_text(json.dumps({"platform": "ios"}))
        built = self.evaluate({"candidate": str(self.candidate), "godot": self.options["godot"]}, platform="ios")
        self.assertNotIn("error", built)
        self.assertEqual(built["calls"], [["python3", str(ROOT / "tools/release/build_native.py"), str(self.candidate),
                                         "--godot", self.options["godot"]]])

    def test_existing_android_and_ios_verification_helpers_are_preserved(self) -> None:
        structural = self.evaluate({"artifact": str(self.root / "synthetic.apk"), "zipalign": str(self.root / "zipalign")},
                                   lane="verify_artifact")
        self.assertNotIn("error", structural)
        self.assertEqual(structural["calls"][0][1], str(ROOT / "tools/release/check_android_artifact.py"))
        self.assertEqual(structural["calls"][0][-2:], ["--zipalign", str(self.root / "zipalign")])
        release = self.evaluate({"artifact": str(self.root / "synthetic.aab"), "artifact_sha256": "a" * 64,
                                "upload_certificate_sha256": "b" * 64, "version": "1.2.3", "build_number": "17",
                                "bundletool": self.options["bundletool"], "jdk": self.options["jdk"]}, lane="verify_release")
        self.assertNotIn("error", release)
        self.assertEqual(release["calls"][0][1], str(ROOT / "tools/release/verify_android_release.py"))
        self.assertEqual(release["calls"][0][release["calls"][0].index("--package") + 1], "com.blubberandbyte.waddlewars")
        profile = self.evaluate({"profile": str(self.root / "synthetic.mobileprovision"), "cms_helper": str(self.root / "cms-helper"),
                                "cms_helper_sha256": "a" * 64, "team_id": "ABCDE12345", "certificate_sha1": "b" * 40,
                                "profile_name": "Synthetic App Store"}, platform="ios", lane="verify_profile")
        self.assertNotIn("error", profile)
        self.assertEqual(profile["calls"][0][1], str(ROOT / "tools/release/verify_ios_profile.py"))
        self.assertEqual(profile["calls"][0][-2:], ["--profile-name", "Synthetic App Store"])


if __name__ == "__main__":
    unittest.main()
