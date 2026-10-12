#!/usr/bin/env python3
"""No-engine regression tests for audited, isolated Web import application."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("web_import_profile", Path(__file__).with_name("web_import_profile.py"))
profile_tool = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(profile_tool)


class ProfileTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="waddle-web-import-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = self.root / "copy"
        self.project.mkdir()
        (self.project / "project.godot").write_text("config_version=5\n")
        self.path = "assets/art/ui/menu/example.webp"
        self.source = self.project / self.path
        self.source.parent.mkdir(parents=True)
        self.source.write_bytes(b"test-source-bytes")
        self.sidecar = self.source.with_name(self.source.name + ".import")
        self.original = 'path="res://.godot/imported/example.ctex"\ncompress/mode=0\ncompress/lossy_quality=0.7\nmipmaps/generate=true\nprocess/size_limit=0\n'
        self.sidecar.write_text(self.original)
        self.payload = b"exact-admitted-import"
        self.profile = {"schema_version": 1,
                        "helper_sha256": profile_tool.sha(Path(profile_tool.__file__)),
                        "pack_memory_helper_sha256": profile_tool.sha(profile_tool.ROOT / "tools/release/web_pack_memory.py"),
                        "quality_gate": {"min_ssim": 0.995, "min_psnr_db": 35.0, "max_alpha_error": 0},
                        "max_pack_bytes": 220_000_000,
                        "assets": [{"path": self.path, "source_sha256": profile_tool.sha(self.source),
                                    "sampler_settings_sha256": hashlib.sha256(profile_tool.non_quality_settings(self.original).encode()).hexdigest(),
                                    "quality": 0.95, "mipmaps": True,
                                    "imported_path": ".godot/imported/example.ctex",
                                    "imported_sha256": hashlib.sha256(self.payload).hexdigest()}]}
        self.profile_path = self.root / "profile.json"
        self.save_profile()

    def save_profile(self):
        self.profile_path.write_text(json.dumps(self.profile))

    def apply(self):
        return profile_tool.apply_to_project(self.project, self.profile_path, self.root / "source")

    def pack(self, payload=None, name=".godot/imported/example.ctex"):
        payload = self.payload if payload is None else payload
        directory = 40 + len(payload)
        data = struct.pack("<6I2Q", 0x43504447, 4, 4, 7, 1, 2, 40, directory) + payload
        name = name.encode()
        data += struct.pack("<II", 1, len(name)) + name + struct.pack("<QQ", 0, len(payload)) + hashlib.md5(payload).digest() + struct.pack("<I", 0)
        pack = self.root / "sample.pck"
        pack.write_bytes(data)
        return pack

    def test_only_two_compression_fields_change_and_reapply_is_idempotent(self):
        receipt = self.apply()
        after = self.sidecar.read_bytes()
        self.assertIn(b"compress/mode=1", after)
        self.assertIn(b"compress/lossy_quality=0.95", after)
        self.assertEqual(profile_tool.non_quality_settings(after.decode()), profile_tool.non_quality_settings(self.original))
        self.assertEqual(self.source.read_bytes(), b"test-source-bytes")
        self.assertEqual(self.apply(), receipt)
        self.assertEqual(self.sidecar.read_bytes(), after)

    def test_primary_project_is_never_mutated(self):
        with self.assertRaisesRegex(ValueError, "isolated"):
            profile_tool.apply_to_project(self.project, self.profile_path, self.project)
        self.assertEqual(self.sidecar.read_text(), self.original)

    def test_source_change_fails_before_any_mutation(self):
        self.source.write_bytes(b"new art")
        with self.assertRaisesRegex(ValueError, "source changed"):
            self.apply()
        self.assertEqual(self.sidecar.read_text(), self.original)

    def test_mipmap_or_size_change_rejected(self):
        for before, after in [("generate=true", "generate=false"), ("size_limit=0", "size_limit=256")]:
            self.sidecar.write_text(self.original.replace(before, after))
            with self.assertRaisesRegex(ValueError, "sampler/import"):
                self.apply()

    def test_new_asset_requires_new_audit(self):
        self.source.with_name("new.webp").write_bytes(b"new")
        with self.assertRaisesRegex(ValueError, "inventory changed"):
            self.apply()

    def test_scope_and_helper_and_quality_cannot_be_relaxed(self):
        base = copy.deepcopy(self.profile)
        for change in [lambda p: p.update(helper_sha256="0" * 64),
                       lambda p: p.update(pack_memory_helper_sha256="0" * 64),
                       lambda p: p["quality_gate"].update(min_ssim=0.9),
                       lambda p: p["assets"][0].update(path="assets/art/ui/menu/../bad.webp"),
                       lambda p: p["assets"][0].update(path="assets/art/ui/menu/not-webp.png"),
                       lambda p: p["assets"][0].update(quality=0.5),
                       lambda p: p["assets"][0].update(quality=True),
                       lambda p: p.update(max_pack_bytes=451_000_000)]:
            self.profile = copy.deepcopy(base)
            change(self.profile)
            self.save_profile()
            with self.assertRaises(ValueError):
                self.apply()
        self.assertEqual(self.sidecar.read_text(), self.original)

    def test_export_symlink_cannot_escape(self):
        outside = self.root / "outside.webp"
        outside.write_bytes(self.source.read_bytes())
        self.source.unlink()
        self.source.symlink_to(outside)
        with self.assertRaisesRegex(ValueError, "inside isolated"):
            self.apply()

    def test_actual_pack_payload_matches_profile(self):
        result = profile_tool.verify_pack(self.pack(), self.profile_path)
        self.assertEqual(result["verified_textures"], 1)
        self.assertEqual(result["pack_entries"], 1)

    def test_changed_import_payload_rejected(self):
        with self.assertRaisesRegex(ValueError, "differs"):
            profile_tool.verify_pack(self.pack(b"wrong"), self.profile_path)

    def test_missing_import_rejected(self):
        with self.assertRaisesRegex(ValueError, "missing"):
            profile_tool.verify_pack(self.pack(name="another.ctex"), self.profile_path)

    def test_pack_budget_rejects_before_reading(self):
        self.profile["max_pack_bytes"] = 1
        self.save_profile()
        with self.assertRaisesRegex(ValueError, "exceeds audited budget"):
            profile_tool.verify_pack(self.pack(), self.profile_path)

    def test_partial_directory_rejected(self):
        pack = self.pack()
        pack.write_bytes(pack.read_bytes()[:39])
        with self.assertRaises((ValueError, struct.error)):
            profile_tool.verify_pack(pack, self.profile_path)


if __name__ == "__main__":
    unittest.main()
