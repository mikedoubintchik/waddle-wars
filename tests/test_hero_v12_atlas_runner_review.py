"""Host safety contracts for the quarantined atlas/real-runner route."""
from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("atlas_runner", ROOT / "tools/art/run_hero_v12_atlas_runner_review.py")
review = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review)


def document():
    pbr = {"baseColorTexture": {"index": 0}, "metallicRoughnessTexture": {"index": 2}}
    return {"asset": {"version": "2.0"}, "buffers": [{"byteLength": 4}],
        "bufferViews": [{"buffer": 0, "byteLength": 4}],
        "accessors": [{"bufferView": 0, "componentType": 5126, "count": 1, "type": "SCALAR"}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "TEXCOORD_0": 0}, "material": i} for i in range(2)]}],
        "materials": [{"pbrMetallicRoughness": copy.deepcopy(pbr), "normalTexture": {"index": 1},
            "occlusionTexture": {"index": 2}} for _ in range(2)],
        "textures": [{"source": i} for i in range(3)],
        "images": [{"uri": f"hero_penguin_v12_atlas_{kind}.png"} for kind in review.KINDS[:3]]}


def fixture(folder: Path):
    glb = folder / review.GLB_NAME
    glb.write_bytes(review.package.join_glb(document(), bytes(4)))
    textures = {}
    for kind in review.KINDS:
        path = folder / f"hero_penguin_v12_atlas_{kind}.png"
        path.write_bytes(b"synthetic host fixture " + kind.encode())
        textures[kind] = review.sha(path)
    binding = {"schema_version": 1, "uv_contract": "unique-nonoverlapping-v1",
        "texture_layout": "shared-external-v1", "glb_sha256": review.sha(glb),
        "projection_gate": {"passed": True, "missing_pixels": 0}, "textures": textures}
    review.write_json(folder / "atlas_binding.json", binding)
    return binding


class AtlasRunnerTests(unittest.TestCase):
    def test_verified_package_accepted(self):
        with tempfile.TemporaryDirectory() as value:
            folder = Path(value)
            binding = fixture(folder)
            actual, _ = review.validate_package(folder)
            self.assertEqual(actual, binding)

    def test_projection_requires_exact_json_types(self):
        for passed, missing in ((False, 0), (True, 1), (1, 0), (True, False), (True, 0.0), (True, "0"), ("true", 0)):
            self.assertFalse(review.verified_projection({"projection_gate": {"passed": passed, "missing_pixels": missing}}))
        self.assertFalse(review.verified_projection({}))
        self.assertFalse(review.verified_projection({"projection_gate": None}))

    def test_rejected_atlas_does_not_create_project(self):
        with tempfile.TemporaryDirectory() as value:
            folder = Path(value)
            source = folder / "source"
            source.mkdir()
            binding = fixture(source)
            binding["projection_gate"] = {"passed": False, "missing_pixels": 15}
            review.write_json(source / "atlas_binding.json", binding)
            output = folder / "output"
            with mock.patch.object(review.common, "run_engine") as engine:
                with self.assertRaisesRegex(ValueError, "zero-miss"):
                    review.prepare(source, output, "M-rejected-fixture", "atlas")
                engine.assert_not_called()
            self.assertFalse(output.exists())

    def test_all_bound_bytes_checked(self):
        with tempfile.TemporaryDirectory() as value:
            folder = Path(value)
            fixture(folder)
            (folder / "hero_penguin_v12_atlas_normal.png").write_bytes(b"changed")
            with self.assertRaisesRegex(ValueError, "PNG hash mismatch"):
                review.validate_package(folder)
            fixture(folder)
            (folder / review.GLB_NAME).write_bytes(b"changed")
            with self.assertRaisesRegex(ValueError, "GLB hash mismatch"):
                review.validate_package(folder)

    def test_shared_layout_and_binding_schema_required(self):
        with tempfile.TemporaryDirectory() as value:
            folder = Path(value)
            original = fixture(folder)
            for key, val in (("texture_layout", "embedded"), ("schema_version", True), ("uv_contract", "repeat")):
                changed = {**original, key: val}
                review.write_json(folder / "atlas_binding.json", changed)
                with self.assertRaises(ValueError):
                    review.validate_package(folder)

    def test_no_literal_color_or_missing_uv(self):
        for mutate in (lambda p: p["attributes"].update(COLOR_0=0), lambda p: p["attributes"].pop("TEXCOORD_0")):
            doc = document()
            mutate(doc["meshes"][0]["primitives"][0])
            with self.assertRaisesRegex(ValueError, "TEXCOORD_0"):
                review.validate_document(doc, bytes(4))

    def test_no_embedded_duplicate_images(self):
        for mutate in (lambda d: d["images"][0].update(bufferView=0),
                       lambda d: d["images"][0].update(uri="../escape.png"),
                       lambda d: d["images"].append({"uri": "other.png"})):
            doc = document()
            mutate(doc)
            with self.assertRaisesRegex(ValueError, "shared external"):
                review.validate_document(doc, bytes(4))

    def test_pbr_and_shader_use_same_untransformed_uv_zero(self):
        for change in ({"texCoord": 1}, {"extensions": {"KHR_texture_transform": {"scale": [2, 2]}}}):
            doc = document()
            doc["materials"][0]["normalTexture"].update(change)
            with self.assertRaisesRegex(ValueError, "unchanged TEXCOORD_0"):
                review.validate_document(doc, bytes(4))

    def test_extra_binary_payload_rejected(self):
        with self.assertRaisesRegex(ValueError, "trailing"):
            review.validate_document(document(), bytes(8))
        doc = document()
        doc["bufferViews"].append({"byteOffset": 4, "byteLength": 4})
        with self.assertRaisesRegex(ValueError, "Unreferenced bufferViews"):
            review.validate_document(doc, bytes(8))

    def test_pbr_map_swaps_and_tint_rejected(self):
        doc = document()
        doc["materials"][0]["normalTexture"]["index"] = 0
        with self.assertRaisesRegex(ValueError, "map does not match"):
            review.validate_document(doc, bytes(4))
        doc = document()
        doc["materials"][0]["pbrMetallicRoughness"]["baseColorFactor"] = [.5, .5, .5, 1]
        with self.assertRaisesRegex(ValueError, "factors"):
            review.validate_document(doc, bytes(4))

    def test_paths_symlinks_and_labels_rejected(self):
        with tempfile.TemporaryDirectory() as value:
            folder = Path(value)
            (folder / "image.png").write_bytes(b"image")
            (folder / "alias.png").symlink_to(folder / "image.png")
            for filename in ("../image.png", "alias.png", "a/b.png", "https:a.png"):
                with self.assertRaises(ValueError):
                    review.safe_file(folder, filename)
            for label in ("", 'M"\nconfig/use_custom_user_dir=false', "../M"):
                with self.assertRaisesRegex(ValueError, "candidate label"):
                    review.prepare(folder, folder / "out", label, "atlas")

    def test_shader_default_ratio_one_not_source_m_assumption(self):
        text = (ROOT / review.SHADER).read_text()
        review.validate_shader_defaults(text)
        with self.assertRaisesRegex(ValueError, "ratio is not one"):
            review.validate_shader_defaults(text.replace("instance uniform vec3 dorsal_linear = vec3(0.017", "instance uniform vec3 dorsal_linear = vec3(0.018"))
        with self.assertRaisesRegex(ValueError, "COLOR"):
            review.validate_shader_defaults(text + "\nvoid broken() { ALBEDO = COLOR.rgb; }\n")

    def test_no_motion_or_literal_repair_override(self):
        text = (ROOT / "tests/hero_v12_atlas_review_rig.gd").read_text()
        self.assertTrue(text.startswith('extends "res://tests/hero_v12_review_rig.gd"'))
        for name in ("tick", "configure", "_ready", "set_pose", "drive_motion", "play_state", "_play", "_step_motion"):
            self.assertNotIn(f"func {name}(", text)
        self.assertNotIn("super._apply_materials", text)
        self.assertNotIn("vertex_color_use_as_albedo = true", text)
        self.assertNotIn("set_instance_shader_parameter", text)
        self.assertIn("waddle-v12-atlas-runner-review-", text)
        runner = (ROOT / "tests/hero_v12_atlas_runner_capture.gd").read_text()
        self.assertTrue(runner.startswith('extends "res://tests/hero_v12_runner_capture.gd"'))
        self.assertIn("super._ready()", runner)

    def test_rejected_or_mislabeled_report_never_passes(self):
        candidate = {"glb_sha256": "hash", "candidate_label": "M-frozen", "material_mode": "atlas", "shader_sha256": "shader"}
        report = {"passed": True, "projection_gate": {"passed": True, "missing_pixels": 0},
            "candidate_sha256": "hash", "candidate_label": "M-frozen", "material_mode": "atlas", "shader_sha256": "shader",
            "source_pigment_ratio": 1.0, "production_ready": False, "source_fidelity_approved": False,
            "unique_total_texture_instances": 4, "unique_pbr_texture_instances": 3}
        review.validate_report(report, {"candidate": candidate})
        for key, value in (("projection_gate", {"passed": False, "missing_pixels": 15}), ("candidate_label", "Y-approved"),
                           ("production_ready", True), ("unique_total_texture_instances", 7), ("source_pigment_ratio", 1.1)):
            with self.assertRaises(ValueError):
                review.validate_report({**report, key: value}, {"candidate": candidate})


if __name__ == "__main__":
    unittest.main()
