"""Synthetic import provenance tests; no engine, signing or network."""
import hashlib
from pathlib import Path
import tempfile
import unittest

from build_native import collect_generated_import_metadata


class ImportMetadataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="waddle-import-metadata-")
        self.addCleanup(self.temp.cleanup)
        self.project = Path(self.temp.name).resolve()
        self.prepared = {"scripts/fixture.gd": self.file("scripts/fixture.gd", b"extends Node\n")}
        self.artifacts = {"project/build/ios/waddlewars.pck": self.file("build/ios/waddlewars.pck", b"frozen pack")}

    def file(self, name, value):
        path = self.project / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(value)
        return hashlib.sha256(value).hexdigest()

    def collect(self):
        return collect_generated_import_metadata(self.project, self.prepared, self.artifacts, "a" * 64)

    def test_new_adjacent_uid_separate_from_source(self):
        digest = self.file("scripts/fixture.gd.uid", b"uid://abc123\n")
        before = dict(self.prepared)
        result = self.collect()
        self.assertEqual(result, {"schema_version": 1, "state": "godot_import_metadata_frozen",
                                  "source_sha256": "a" * 64,
                                  "generated_uid_files": {"scripts/fixture.gd.uid": digest}})
        self.assertEqual(self.prepared, before)

    def test_new_adjacent_shader_uid_separate_from_source(self):
        self.prepared["scripts/fixture.gdshader"] = self.file(
            "scripts/fixture.gdshader", b"shader_type canvas_item;\n")
        digest = self.file("scripts/fixture.gdshader.uid", b"uid://abc123\n")
        self.assertEqual(self.collect()["generated_uid_files"],
                         {"scripts/fixture.gdshader.uid": digest})

    def test_no_new_metadata_valid(self):
        self.assertEqual(self.collect()["generated_uid_files"], {})

    def test_existing_uid_remains_prepared(self):
        self.prepared["scripts/fixture.gd.uid"] = self.file("scripts/fixture.gd.uid", b"uid://abc\n")
        self.assertEqual(self.collect()["generated_uid_files"], {})

    def test_import_cache_ignored(self):
        self.file(".godot/cache.bin", b"transient import cache")
        self.assertEqual(self.collect()["generated_uid_files"], {})

    def test_other_generated_file_rejected(self):
        for name in ("scripts/extra.gd", "scripts/extra.gd.uid", "assets/extra.png.uid"):
            with self.subTest(name=name):
                self.file(name, b"uid://abc\n")
                with self.assertRaises(ValueError):
                    self.collect()
                (self.project / name).unlink()

    def test_malformed_uid_rejected(self):
        for value in (b"", b"uid://UPPER", b"uid://abc\r\n", b"uid://abc\nextra", b"uid://" + b"a" * 128, b"uid://abc\x00"):
            with self.subTest(value=value):
                self.file("scripts/fixture.gd.uid", value)
                with self.assertRaises(ValueError):
                    self.collect()

    def test_changed_prepared_bytes_rejected(self):
        self.file("scripts/fixture.gd", b"changed gameplay code")
        with self.assertRaises(ValueError):
            self.collect()

    def test_missing_prepared_file_rejected(self):
        (self.project / "scripts/fixture.gd").unlink()
        with self.assertRaises(ValueError):
            self.collect()

    def test_changed_export_bytes_rejected(self):
        self.file("build/ios/waddlewars.pck", b"different pack")
        with self.assertRaises(ValueError):
            self.collect()

    def test_source_pin_required(self):
        with self.assertRaises(ValueError):
            collect_generated_import_metadata(self.project, self.prepared, self.artifacts, "bad")

    def test_link_rejected(self):
        (self.project / "scripts/fixture.gd.uid").symlink_to(self.project / "scripts/fixture.gd")
        with self.assertRaises(ValueError):
            self.collect()


if __name__ == "__main__":
    unittest.main()
