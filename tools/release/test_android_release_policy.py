#!/usr/bin/env python3
"""Pure-host Android release profiling-policy tests. No builds or signing."""
from __future__ import annotations

import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from build_native import apply_android_release_policy


NODE = '<profileable tools:targetApi="29" android:shell="true" android:enabled="true" />'
DISABLED = '<profileable tools:targetApi="29" android:shell="false" android:enabled="false" />'
ORIGINAL = ('''<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools" package="com.blubberandbyte.waddlewars">
    <uses-sdk android:minSdkVersion="24" android:targetSdkVersion="36" />
    <uses-permission android:name="com.android.vending.BILLING" />
    <!-- Unrelated literal android:shell="true" android:enabled="true" stays exact. -->
    <application android:label="Waddle Wars: Penguin Panic" android:debuggable="false">
        ''' + NODE + '''
        <activity android:name=".GodotApp" android:exported="true" />
        <meta-data android:name="synthetic.provider" android:value="synthetic.Class" />
    </application>
</manifest>
''').encode()


class AndroidReleasePolicyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.folder = tempfile.TemporaryDirectory(prefix="ww-android-policy-fixture-")
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name).resolve()
        self.manifest = self.root / "AndroidManifest.xml"
        self.manifest.write_bytes(ORIGINAL)

    def reject_without_write(self, original: bytes) -> None:
        self.manifest.write_bytes(original)
        with patch.object(Path, "write_bytes") as write:
            with self.assertRaises(ValueError):
                apply_android_release_policy(self.manifest)
            write.assert_not_called()
        self.assertEqual(self.manifest.read_bytes(), original)

    def test_only_reviewed_node_values_change_all_other_bytes_preserved(self) -> None:
        result = apply_android_release_policy(self.manifest)
        expected = ORIGINAL.replace(NODE.encode(), DISABLED.encode())
        self.assertEqual(self.manifest.read_bytes(), expected)
        self.assertEqual(result["policy"], "no-release-shell-or-system-profiling-v1")
        self.assertEqual(result["before_sha256"], hashlib.sha256(ORIGINAL).hexdigest())
        self.assertEqual(result["after_sha256"], hashlib.sha256(expected).hexdigest())
        self.assertIs(result["shell_profileable"], False)
        self.assertIs(result["system_profileable"], False)
        self.assertIn(b'Unrelated literal android:shell="true" android:enabled="true"', expected)

    def test_idempotent_second_application_never_writes(self) -> None:
        first = apply_android_release_policy(self.manifest)
        before = self.manifest.read_bytes()
        with patch.object(Path, "write_bytes") as write:
            second = apply_android_release_policy(self.manifest)
            write.assert_not_called()
        self.assertEqual(self.manifest.read_bytes(), before)
        self.assertEqual(second["before_sha256"], first["after_sha256"])
        self.assertEqual(second["after_sha256"], first["after_sha256"])

    def test_api29_shell_false_already_remains_false_while_enabled_disabled(self) -> None:
        original = ORIGINAL.replace(NODE.encode(), NODE.replace('android:shell="true"', 'android:shell="false"').encode())
        self.manifest.write_bytes(original)
        result = apply_android_release_policy(self.manifest)
        self.assertEqual(self.manifest.read_bytes(), ORIGINAL.replace(NODE.encode(), DISABLED.encode()))
        self.assertIs(result["shell_profileable"], False)
        self.assertIn(b'tools:targetApi="29"', self.manifest.read_bytes())

    def test_already_disabled_api29_node_has_no_write(self) -> None:
        original = ORIGINAL.replace(NODE.encode(), DISABLED.encode())
        self.manifest.write_bytes(original)
        with patch.object(Path, "write_bytes") as write:
            result = apply_android_release_policy(self.manifest)
            write.assert_not_called()
        self.assertEqual(result["before_sha256"], result["after_sha256"])

    def test_crlf_bom_and_nonascii_unrelated_bytes_preserved(self) -> None:
        original = b"\xef\xbb\xbf" + ORIGINAL.replace(b"synthetic.provider", "synthetic.pingüino".encode()).replace(b"\n", b"\r\n")
        self.manifest.write_bytes(original)
        apply_android_release_policy(self.manifest)
        self.assertEqual(self.manifest.read_bytes(), original.replace(NODE.encode(), DISABLED.encode()))

    def test_both_mixed_boolean_states_disable_without_unrelated_changes(self) -> None:
        for shell, enabled in (("false", "true"), ("true", "false")):
            with self.subTest(shell=shell, enabled=enabled):
                node = NODE.replace('shell="true"', 'shell="' + shell + '"').replace('enabled="true"', 'enabled="' + enabled + '"')
                self.manifest.write_bytes(ORIGINAL.replace(NODE.encode(), node.encode()))
                apply_android_release_policy(self.manifest)
                self.assertEqual(self.manifest.read_bytes(), ORIGINAL.replace(NODE.encode(), DISABLED.encode()))

    def test_missing_manifest_is_rejected_without_any_write(self) -> None:
        with patch.object(Path, "write_bytes") as write:
            with self.assertRaises(ValueError):
                apply_android_release_policy(self.root / "missing.xml")
            write.assert_not_called()

    def test_relative_manifest_path_rejected_before_reading_or_writing(self) -> None:
        with patch.object(Path, "read_bytes") as read, patch.object(Path, "write_bytes") as write:
            with self.assertRaises(ValueError):
                apply_android_release_policy(Path("relative-AndroidManifest.xml"))
            read.assert_not_called()
            write.assert_not_called()

    def test_directory_instead_of_manifest_is_rejected(self) -> None:
        with patch.object(Path, "write_bytes") as write:
            with self.assertRaises(ValueError):
                apply_android_release_policy(self.root)
            write.assert_not_called()

    def test_direct_symlink_rejected_without_touching_target(self) -> None:
        linked = self.root / "linked.xml"
        linked.symlink_to(self.manifest)
        with patch.object(Path, "write_bytes") as write:
            with self.assertRaises(ValueError):
                apply_android_release_policy(linked)
            write.assert_not_called()
        self.assertEqual(self.manifest.read_bytes(), ORIGINAL)

    def test_symlinked_manifest_parent_rejected_without_touching_target(self) -> None:
        directory = self.root / "real-parent"
        directory.mkdir()
        target = directory / "AndroidManifest.xml"
        target.write_bytes(ORIGINAL)
        linked = self.root / "linked-parent"
        linked.symlink_to(directory, target_is_directory=True)
        with patch.object(Path, "write_bytes") as write:
            with self.assertRaises(ValueError):
                apply_android_release_policy(linked / target.name)
            write.assert_not_called()
        self.assertEqual(target.read_bytes(), ORIGINAL)

    def test_malformed_xml_rejected_without_write(self) -> None:
        self.reject_without_write(ORIGINAL.replace(b"</manifest>", b"</different>"))

    def test_invalid_utf8_rejected_without_write(self) -> None:
        self.reject_without_write(ORIGINAL.replace(b"synthetic.provider", b"invalid-\xff"))

    def test_utf16_manifest_not_silently_reencoded(self) -> None:
        self.reject_without_write(ORIGINAL.decode().encode("utf-16"))

    def test_empty_xml_rejected_without_write(self) -> None:
        self.reject_without_write(b"")

    def test_oversize_manifest_rejected_without_write(self) -> None:
        self.reject_without_write(ORIGINAL.replace(b"</manifest>", b"<!--" + b"x" * (256 * 1024) + b"--></manifest>"))

    def test_doctype_and_entities_rejected_before_xml_parser(self) -> None:
        for directive in (b'<!DOCTYPE manifest SYSTEM "file:///synthetic-do-not-read">',
                          b'<!DOCTYPE manifest [<!ENTITY marker "synthetic">]>',
                          b'<!doctype manifest>', b'<!ENTITY marker "synthetic">'):
            with self.subTest(directive=directive):
                self.manifest.write_bytes(directive + ORIGINAL)
                with patch("build_native.ET.fromstring") as parse, patch.object(Path, "write_bytes") as write:
                    with self.assertRaises(ValueError):
                        apply_android_release_policy(self.manifest)
                    parse.assert_not_called()
                    write.assert_not_called()

    def test_wrong_root_tag_rejected_without_write(self) -> None:
        self.reject_without_write(ORIGINAL.replace(b"<manifest ", b"<not-manifest ").replace(b"</manifest>", b"</not-manifest>"))

    def test_missing_application_rejected_without_write(self) -> None:
        self.reject_without_write(ORIGINAL.replace(b"<application ", b"<not-application ").replace(b"</application>", b"</not-application>"))

    def test_multiple_applications_rejected_without_write(self) -> None:
        self.reject_without_write(ORIGINAL.replace(b"</manifest>", b"<application /></manifest>"))

    def test_missing_profileable_rejected_without_write(self) -> None:
        self.reject_without_write(ORIGINAL.replace(NODE.encode(), b""))

    def test_multiple_profileable_nodes_rejected_without_write(self) -> None:
        self.reject_without_write(ORIGINAL.replace(NODE.encode(), (NODE + NODE).encode()))

    def test_nested_profileable_node_rejected_without_write(self) -> None:
        self.reject_without_write(ORIGINAL.replace(NODE.encode(), ("<wrapper>" + NODE + "</wrapper>").encode()))

    def test_profileable_outside_application_rejected_without_write(self) -> None:
        changed = ORIGINAL.replace(NODE.encode(), b"").replace(b"</manifest>", NODE.encode() + b"</manifest>")
        self.reject_without_write(changed)

    def test_profileable_children_rejected_without_write(self) -> None:
        changed = NODE.replace(" />", "><child /></profileable>")
        self.reject_without_write(ORIGINAL.replace(NODE.encode(), changed.encode()))

    def test_unreviewed_profileable_attributes_rejected_without_write(self) -> None:
        for attribute in ('android:debuggable="false"', 'tools:other="synthetic"', 'unreviewed="value"'):
            with self.subTest(attribute=attribute):
                node = NODE.replace(" />", " " + attribute + " />")
                self.reject_without_write(ORIGINAL.replace(NODE.encode(), node.encode()))

    def test_each_missing_profileable_attribute_rejected_without_write(self) -> None:
        for attribute in (' tools:targetApi="29"', ' android:shell="true"', ' android:enabled="true"'):
            with self.subTest(attribute=attribute):
                self.reject_without_write(ORIGINAL.replace(NODE.encode(), NODE.replace(attribute, "").encode()))

    def test_target_api_change_rejected_without_write(self) -> None:
        for value in ("28", "30", "android29", "029"):
            with self.subTest(value=value):
                self.reject_without_write(ORIGINAL.replace(b'tools:targetApi="29"', ('tools:targetApi="' + value + '"').encode()))

    def test_non_boolean_or_capitalized_flags_rejected_without_write(self) -> None:
        for name in ("shell", "enabled"):
            for value in ("True", "FALSE", "1", "0", "@bool/flag", ""):
                with self.subTest(name=name, value=value):
                    node = NODE.replace(name + '="true"', name + '="' + value + '"')
                    self.reject_without_write(ORIGINAL.replace(NODE.encode(), node.encode()))

    def test_nonselfclosing_node_rejected_without_write(self) -> None:
        node = NODE.replace(" />", "></profileable>")
        self.reject_without_write(ORIGINAL.replace(NODE.encode(), node.encode()))

    def test_single_quote_format_change_rejected_without_write(self) -> None:
        self.reject_without_write(ORIGINAL.replace(NODE.encode(), NODE.replace('"', "'").encode()))

    def test_attribute_spacing_format_change_rejected_without_write(self) -> None:
        self.reject_without_write(ORIGINAL.replace(NODE.encode(), NODE.replace('shell="', 'shell = "').encode()))

    def test_namespace_prefix_remap_not_guessed(self) -> None:
        original = ORIGINAL.replace(b"xmlns:android=", b"xmlns:a=").replace(b"android:", b"a:")
        self.reject_without_write(original)

    def test_comment_duplicate_profileable_block_is_ambiguous(self) -> None:
        self.reject_without_write(ORIGINAL.replace(b"</manifest>", ("<!-- " + NODE + " --></manifest>").encode()))


if __name__ == "__main__":
    unittest.main()
