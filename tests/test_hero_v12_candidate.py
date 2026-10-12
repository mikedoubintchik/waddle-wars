"""Standard-library safety/math tests for the isolated V12 candidate adapter."""

import importlib.util
import json
import struct
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("hero_v12_candidate", ROOT / "tools/art/build_hero_penguin_v12_candidate.py")
ADAPTER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ADAPTER)


class HeroV12CandidateTests(unittest.TestCase):
    def test_source_cover_bands_pin_bilateral_real_failures(self):
        for x in (-0.12358394, -0.13591115, -0.14833419, 0.12358394, 0.13591115, 0.14833419):
            self.assertTrue(ADAPTER.orbital_source_pin((x, -.288, 1.64844), near_lod=True))
            self.assertTrue(ADAPTER.orbital_source_pin((x, -.288, 1.64844), near_lod=False))
        self.assertTrue(ADAPTER.orbital_source_pin((-.095, -.309, 1.600), near_lod=True))
        self.assertFalse(ADAPTER.orbital_source_pin((-.095, -.309, 1.600), near_lod=False))
        for point in ((.1, .30, 1.648), (.1, -.30, .8), (.65, -.30, 1.648)):
            self.assertFalse(ADAPTER.orbital_source_pin(point, near_lod=True))
        with self.assertRaises(ValueError):
            ADAPTER.orbital_source_pin((float("nan"), 0, 0), near_lod=True)

    def test_collapse_permission_is_lower_at_orbit_not_higher(self):
        orbit = ADAPTER.orbital_collapse_weight((.17, -.30, 1.60))
        belly = ADAPTER.orbital_collapse_weight((.17, -.30, .80))
        self.assertLess(orbit, belly)
        self.assertAlmostEqual(orbit, .01)
        self.assertEqual(orbit, ADAPTER.orbital_collapse_weight((-.17, -.30, 1.60)))

    def test_geometry_policy_is_explicit_and_legacy_targets_remain(self):
        self.assertEqual(ADAPTER.component_target("HeroBodyV12SmoothField", 0, "legacy"), 12500)
        self.assertEqual(ADAPTER.component_target("HeroBodyV12SmoothField", 0, "source-cover-v1"), 14000)
        self.assertEqual(ADAPTER.component_target("BillMouthSeam", 0, "source-cover-v1"), 800)
        self.assertEqual(ADAPTER.component_target("BillMouthSeam", 1, "source-cover-v1"), 800)
        for lod in (0, 1):
            self.assertEqual(ADAPTER.component_target("BillMouthSeam", lod, "source-cover-v2"),
                             ADAPTER.component_target("BillMouthSeam", lod, "legacy"))
        self.assertEqual(ADAPTER.component_target("HeroBodyV12SmoothField", 0, "source-cover-v2"), 14000)
        with self.assertRaises(ValueError):
            ADAPTER.component_target("HeroBodyV12SmoothField", 0, "guess")

    def test_source_face_identity_preserves_winding_not_just_points(self):
        face = ((0, 0, 0), (1, 0, 0), (0, 1, 0))
        key = ADAPTER.oriented_face_key(face)
        self.assertEqual(key, ADAPTER.oriented_face_key(face[1:] + face[:1]))
        self.assertNotEqual(key, ADAPTER.oriented_face_key(tuple(reversed(face))))

    def _iris_source(self, name="Iris+1", material_name="BlueGrayIris"):
        colors = [(0.095, 0.150, 0.172, 1.0), (0.075, 0.175, 0.232, 1.0), (0.016, 0.032, 0.048, 1.0)]
        pigment = SimpleNamespace(domain="POINT", data_type="FLOAT_COLOR",
                                  data=[SimpleNamespace(color=color) for color in colors])
        vertex_node = SimpleNamespace(type="VERTEX_COLOR", layer_name="IrisPigment")
        link = SimpleNamespace(from_node=vertex_node, from_socket=SimpleNamespace(name="Color"))
        bsdf = SimpleNamespace(type="BSDF_PRINCIPLED", inputs={"Base Color": SimpleNamespace(links=[link])})
        output = SimpleNamespace(type="OUTPUT_MATERIAL", is_active_output=True,
                                 inputs={"Surface": SimpleNamespace(links=[SimpleNamespace(from_node=bsdf)])})
        material = SimpleNamespace(name=material_name, use_nodes=True,
                                   diffuse_color=(0.9, 0.8, 0.7, 1.0),
                                   node_tree=SimpleNamespace(nodes=[vertex_node, bsdf, output]))
        obj = SimpleNamespace(name=name, data=SimpleNamespace(color_attributes={"IrisPigment": pigment},
                              vertices=[SimpleNamespace(index=i) for i in range(3)], materials=[material], loops=[]))
        return obj, colors

    def test_iris_source_returns_exact_linear_paint_not_diffuse(self):
        for name, material in (("Iris+1", "BlueGrayIris"), ("Iris-1.001", "BlueGrayIris.002")):
            obj, colors = self._iris_source(name, material)
            self.assertEqual(ADAPTER.source_colors(obj), colors)

    def test_preview_point_and_corner_keep_precedence_over_iris(self):
        obj, _ = self._iris_source()
        colors = [(0.1, 0.2, 0.3, 1), (0.4, 0.5, 0.6, 1), (0.7, 0.8, 0.9, 1)]
        preview = SimpleNamespace(domain="POINT", data=[SimpleNamespace(color=color) for color in colors])
        obj.data.color_attributes["PreviewColor"] = preview
        self.assertEqual(ADAPTER.source_colors(obj), colors)
        preview.domain = "CORNER"
        obj.data.loops = [SimpleNamespace(index=index, vertex_index=2 - index) for index in range(3)]
        self.assertEqual(ADAPTER.source_colors(obj), list(reversed(colors)))

    def test_iris_source_rejects_wrong_component_material_domain_or_count(self):
        for defect in ("component", "material", "domain", "storage", "count", "layer", "socket", "output", "indirect"):
            obj, _ = self._iris_source()
            pigment = obj.data.color_attributes["IrisPigment"]
            vertex, bsdf, output = obj.data.materials[0].node_tree.nodes
            if defect == "component":
                obj.name = "EmbeddedSclera+1"
            elif defect == "material":
                obj.data.materials[0].name = "WarmSclera"
            elif defect == "domain":
                pigment.domain = "CORNER"
            elif defect == "storage":
                pigment.data_type = "BYTE_COLOR"
            elif defect == "count":
                pigment.data.pop()
            elif defect == "layer":
                vertex.layer_name = "UnrelatedMask"
            elif defect == "socket":
                bsdf.inputs["Base Color"].links[0].from_socket.name = "Alpha"
            elif defect == "output":
                output.is_active_output = False
            else:
                vertex.type = "MIX_RGB"
            with self.subTest(defect=defect), self.assertRaises(RuntimeError):
                ADAPTER.source_colors(obj)

    def test_legacy_diffuse_and_default_sources_are_unchanged(self):
        obj, _ = self._iris_source()
        obj.data.color_attributes.clear()
        self.assertEqual(ADAPTER.source_colors(obj), [(0.9, 0.8, 0.7, 1.0)] * 3)
        obj.data.materials.clear()
        self.assertEqual(ADAPTER.source_colors(obj), [(0.1, 0.1, 0.1, 1.0)] * 3)

    def _color_fixture(self, directory):
        points = [(0.1, 0.2, 0.3), (0.2, 0.2, 0.3), (0.1, 0.3, 0.3)]
        paint = [(0.02, 0.04, 0.06, 1.0), (0.7, 0.6, 0.5, 1.0), (0.9, 0.3, 0.02, 1.0)]
        position_bytes = b"".join(struct.pack("<3f", x, z, -y) for x, y, z in points)
        binary = position_bytes + b"\xff" * 24
        document = {"asset": {"version": "2.0"}, "buffers": [{"byteLength": len(binary)}],
                    "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": 36},
                                    {"buffer": 0, "byteOffset": 36, "byteLength": 24}],
                    "accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"},
                                  {"bufferView": 1, "componentType": 5123, "count": 3, "type": "VEC4", "normalized": True}],
                    "materials": [{"name": "candidate"}],
                    "meshes": [{"primitives": [{"material": 0, "attributes": {"POSITION": 0, "COLOR_0": 1}}]}]}
        encoded = json.dumps(document).encode()
        encoded += b" " * (-len(encoded) % 4)
        raw = (struct.pack("<III", 0x46546C67, 2, 28 + len(encoded) + len(binary))
               + struct.pack("<II", len(encoded), 0x4E4F534A) + encoded
               + struct.pack("<II", len(binary), 0x004E4942) + binary)
        path = Path(directory) / "candidate.glb"
        path.write_bytes(raw)
        mesh = SimpleNamespace(data=SimpleNamespace(
            polygons=[SimpleNamespace(material_index=0, loop_indices=range(3))],
            materials=[SimpleNamespace(name="candidate")],
            vertices=[SimpleNamespace(co=SimpleNamespace(x=x, y=y, z=z)) for x, y, z in points],
            loops=[SimpleNamespace(vertex_index=index) for index in range(3)],
            color_attributes={"COLOR_0": SimpleNamespace(data=[SimpleNamespace(color=value) for value in paint])}))
        return path, mesh, raw, paint

    def test_color_serialization_restores_exact_source_only(self):
        with tempfile.TemporaryDirectory(prefix="waddle-v12-color-test-") as directory:
            path, mesh, before, colors = self._color_fixture(directory)
            report = ADAPTER.restore_authored_vertex_colors(path, mesh)
            after = path.read_bytes()
            self.assertEqual(report["exact_source_vertices_matched"], 3)
            self.assertEqual(report["changed_exported_colors"], 3)
            self.assertEqual(before[:-24], after[:-24])
            expected = tuple(round(value * 65535) for color in colors for value in color)
            self.assertEqual(struct.unpack("<12H", after[-24:]), expected)

    def test_color_serialization_rejects_unmatched_source_without_writing(self):
        with tempfile.TemporaryDirectory(prefix="waddle-v12-color-test-") as directory:
            path, mesh, before, _colors = self._color_fixture(directory)
            mesh.data.vertices[2].co.x = 0.5
            with self.assertRaisesRegex(RuntimeError, "no exact source"):
                ADAPTER.restore_authored_vertex_colors(path, mesh)
            self.assertEqual(path.read_bytes(), before)

    def test_paint_sentinels_distinguish_authored_dark_from_export_white(self):
        dark = ADAPTER.paint_summary([(0.017, 0.027, 0.040, 1.0)] * 3)
        white = ADAPTER.paint_summary([(1.0, 1.0, 1.0, 1.0)] * 3)
        self.assertEqual(dark["samples"], 3)
        self.assertEqual(dark["minimum"], [0.017, 0.027, 0.040, 1.0])
        self.assertNotEqual(dark["linear_float_sha256"], white["linear_float_sha256"])
        with self.assertRaises(ValueError):
            ADAPTER.paint_summary([])

    def test_candidate_cannot_write_live_or_source_paths(self):
        for target in (ROOT, ROOT / "assets/art/characters/replacement", ROOT / "art_src/characters/replacement",
                       ROOT / "qa_shots/hero", ROOT / "qa_shots/hero/../../assets/replacement"):
            with self.subTest(target=target), self.assertRaises(ValueError):
                ADAPTER.safe_output_dir(str(target))

    def test_candidate_accepts_dedicated_qa_child(self):
        target = ROOT / "qa_shots/hero/not_yet_created_candidate_test"
        self.assertEqual(ADAPTER.safe_output_dir(str(target)), target)

    def test_component_allocation_is_explicit(self):
        self.assertEqual(ADAPTER.component_spec("HeroBodyV12SmoothField"), ("body", 12500))
        self.assertEqual(ADAPTER.component_spec("FusedWebbedFoot+1"), ("foot", 1050))
        self.assertEqual(ADAPTER.component_spec("IntegratedOrbitalRim-1"), ("brow", 420))
        with self.assertRaisesRegex(ValueError, "unclassified"):
            ADAPTER.component_spec("NewUnbudgetedGeometry")

    def test_handedness_is_one_reflection(self):
        self.assertEqual(ADAPTER.canonical_position((0.2, -0.4, 1.5)), (0.2, 0.4, 1.5))
        self.assertEqual(ADAPTER.canonical_position(ADAPTER.canonical_position((0.2, -0.4, 1.5))),
                         (0.2, -0.4, 1.5))

    def test_sole_fit_is_explicit_constant_mesh_translation(self):
        self.assertEqual(ADAPTER.sole_fit_offset("none", 0.007, 0.034), 0.0)
        self.assertAlmostEqual(ADAPTER.sole_fit_offset("canonical-rest", 0.007, 0.034), -0.027)
        with self.assertRaises(ValueError):
            ADAPTER.sole_fit_offset("per-frame-ik", 0.007, 0.034)

    def test_horizontal_cap_receives_non_degenerate_uvs(self):
        coords, fallback = ADAPTER.stable_face_uvs([(0.1, -0.2, 1.8), (0.12, -0.2, 1.8),
                                                  (0.1, -0.22, 1.8)], False)
        self.assertTrue(fallback)
        self.assertGreater(ADAPTER.uv_double_area(coords), 1e-8)

    def test_cylinder_seam_remains_local(self):
        coords, _fallback = ADAPTER.stable_face_uvs([(0.001, 0.3, 1.0), (-0.001, 0.3, 1.0),
                                                   (0.001, 0.3, 1.02)], False)
        self.assertLess(max(uv[0] for uv in coords) - min(uv[0] for uv in coords), 0.01)

    def test_paint_is_not_silently_treated_as_semantic_mask(self):
        dark = ADAPTER.estimate_semantic_mask((0.017, 0.027, 0.040, 1.0), "body")
        cream = ADAPTER.estimate_semantic_mask((0.76, 0.665, 0.49, 1.0), "body")
        self.assertEqual(dark[:3], (0.0, 0.0, 0.0))
        self.assertGreater(cream[0], 0.95)
        self.assertGreater(dark[3], 0.5)
        self.assertLess(ADAPTER.estimate_semantic_mask((0.2, 0.3, 0.4, 1.0), "eye")[3], 0.5)
        self.assertTrue(any("provisional" in value.lower() for value in ADAPTER.LIMITATIONS))


if __name__ == "__main__":
    unittest.main()
