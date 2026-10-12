"""Stdlib packaging tests; real Godot reuse has a separate engine gate."""
import hashlib
import importlib.util
import json
import struct
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("shared_package", ROOT / "tools/art/package_hero_v12_shared_textures.py")
PACKAGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACKAGE)
VERIFY_SPEC = importlib.util.spec_from_file_location("shared_verify", ROOT / "tools/art/verify_hero_v12_shared_textures.py")
VERIFY = importlib.util.module_from_spec(VERIFY_SPEC)
VERIFY_SPEC.loader.exec_module(VERIFY)


def fixture():
    binary, views, images, digests = bytearray(), [], [], {}
    for kind in ("albedo", "normal", "orm"):
        data = ("fixture-png-" + kind).encode()
        binary.extend(b"\0" * (-len(binary) % 4))
        views.append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(data)})
        binary.extend(data)
        images.append({"name": kind, "mimeType": "image/png", "bufferView": len(views) - 1})
        digests[kind] = hashlib.sha256(data).hexdigest()
    binary.extend(b"\0" * (-len(binary) % 4))
    payload = struct.pack("<6f", 1, 2, 3, 0.1, 0.2, 0.3)
    views.append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(payload), "byteStride": 12})
    binary.extend(payload)
    views.append({"buffer": 0, "byteOffset": len(binary), "byteLength": 64})
    binary.extend(b"UNUSED!!" * 8)
    document = {"asset": {"version": "2.0"}, "buffers": [{"byteLength": len(binary)}], "bufferViews": views,
                "images": images, "accessors": [{"bufferView": 3, "componentType": 5126, "count": 2, "type": "VEC3"}]}
    return document, bytes(binary), digests, payload


class SharedTexturePackageTests(unittest.TestCase):
    def test_compacts_images_and_unreferenced_payload(self):
        document, binary, hashes, expected = fixture()
        output, audit = PACKAGE.externalize(PACKAGE.join_glb(document, binary), hashes)
        result, compact = PACKAGE.split_glb(output)
        self.assertEqual(compact, expected)
        self.assertEqual(result["accessors"][0]["bufferView"], 0)
        self.assertEqual(result["bufferViews"][0]["byteStride"], 12)
        self.assertEqual(len(result["bufferViews"]), 1)
        self.assertEqual(audit["embedded_image_bytes"], 0)
        self.assertEqual(audit["removed_unreferenced_buffer_views"], [4])
        self.assertTrue(all("uri" in image and "bufferView" not in image for image in result["images"]))

    def test_rejects_unbound_png(self):
        document, binary, hashes, _ = fixture()
        hashes["normal"] = "0" * 64
        with self.assertRaises(ValueError):
            PACKAGE.externalize(PACKAGE.join_glb(document, binary), hashes)

    def test_rejects_image_geometry_alias(self):
        document, binary, hashes, _ = fixture()
        document["accessors"][0]["bufferView"] = 0
        with self.assertRaises(ValueError):
            PACKAGE.externalize(PACKAGE.join_glb(document, binary), hashes)

    def test_rejects_already_external_or_remote_source(self):
        document, binary, hashes, _ = fixture()
        document["images"][0]["uri"] = "https://example.invalid/image.png"
        with self.assertRaises(ValueError):
            PACKAGE.externalize(PACKAGE.join_glb(document, binary), hashes)

    def test_rejects_unknown_structural_extension(self):
        document, binary, hashes, _ = fixture()
        document["extensionsUsed"] = ["KHR_draco_mesh_compression"]
        with self.assertRaises(ValueError):
            PACKAGE.externalize(PACKAGE.join_glb(document, binary), hashes)

    def test_sparse_accessor_views_are_kept_and_remapped(self):
        document, binary, hashes, _ = fixture()
        document["accessors"][0].pop("bufferView")
        document["accessors"][0]["sparse"] = {"count": 1, "indices": {"bufferView": 4, "componentType": 5121}, "values": {"bufferView": 3}}
        output, audit = PACKAGE.externalize(PACKAGE.join_glb(document, binary), hashes)
        result, _ = PACKAGE.split_glb(output)
        self.assertEqual(result["accessors"][0]["sparse"]["values"]["bufferView"], 0)
        self.assertEqual(result["accessors"][0]["sparse"]["indices"]["bufferView"], 1)
        self.assertEqual(audit["removed_unreferenced_buffer_views"], [])

    def test_output_cannot_target_live_assets_or_qa_root(self):
        for path in (ROOT / "assets/art", ROOT, ROOT / "qa_shots/hero"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                PACKAGE.safe_output(path)

    def test_invalid_glb_header_rejected(self):
        with self.assertRaises(ValueError):
            PACKAGE.split_glb(b"not a GLB")

    def test_import_verifier_rejects_changed_glb_and_each_map(self):
        with tempfile.TemporaryDirectory(prefix="hero-shared-binding-") as temporary:
            source = Path(temporary)
            expected = {}
            for name in (PACKAGE.GLB_NAME, *(f"hero_penguin_v12_atlas_{kind}.png" for kind in PACKAGE.KINDS)):
                payload = name.encode()
                (source / name).write_bytes(payload)
                expected[name] = hashlib.sha256(payload).hexdigest()
            binding = {"schema_version": 1, "uv_contract": "unique-nonoverlapping-v1",
                       "texture_layout": "shared-external-v1", "projection_gate": {"passed": True, "missing_pixels": 0},
                       "glb_sha256": expected[PACKAGE.GLB_NAME],
                       "textures": {kind: expected[f"hero_penguin_v12_atlas_{kind}.png"] for kind in PACKAGE.KINDS}}
            (source / "atlas_binding.json").write_text(json.dumps(binding))
            self.assertEqual(VERIFY.bound_inputs(source), expected)
            for name in expected:
                original = (source / name).read_bytes()
                (source / name).write_bytes(original + b"changed")
                with self.subTest(name=name), self.assertRaisesRegex(ValueError, "binding mismatch"):
                    VERIFY.bound_inputs(source)
                (source / name).write_bytes(original)

    def test_import_verifier_rejects_unverified_contract(self):
        binding = {"schema_version": 1, "uv_contract": "unique-nonoverlapping-v1",
                   "texture_layout": "shared-external-v1", "projection_gate": {"passed": True, "missing_pixels": 0}}
        changes = {"schema_version": 99, "uv_contract": "repeating", "texture_layout": "embedded",
                   "projection_gate": {"passed": False, "missing_pixels": 15}}
        with tempfile.TemporaryDirectory(prefix="hero-shared-contract-") as temporary:
            source = Path(temporary)
            for key, value in changes.items():
                invalid = dict(binding, **{key: value})
                (source / "atlas_binding.json").write_text(json.dumps(invalid))
                with self.subTest(key=key), self.assertRaisesRegex(ValueError, "verified shared-external"):
                    VERIFY.bound_inputs(source)


if __name__ == "__main__":
    unittest.main()
