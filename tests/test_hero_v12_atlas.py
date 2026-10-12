"""Host-only safety and exact semantic/UV math for the quarantined atlas bake."""
import importlib.util
import math
import struct
import unittest
from unittest.mock import Mock, patch
from types import SimpleNamespace
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("hero_v12_atlas", ROOT / "tools/art/bake_hero_penguin_v12_atlas.py")
ATLAS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ATLAS)
PROBE_SPEC = importlib.util.spec_from_file_location("hero_v12_probes", ROOT / "tools/art/hero_v12_projection_probes.py")
PROBES = importlib.util.module_from_spec(PROBE_SPEC)
PROBE_SPEC.loader.exec_module(PROBES)


class HeroV12AtlasTests(unittest.TestCase):
    def test_geometry_replay_defaults_only_absent_policy_to_frozen_legacy(self):
        self.assertEqual(ATLAS.candidate_geometry_policy({}), "legacy")
        self.assertEqual(ATLAS.candidate_geometry_policy({"geometry_policy": "legacy"}), "legacy")

    def test_geometry_replay_keeps_both_source_cover_versions_distinct(self):
        for policy in ("source-cover-v1", "source-cover-v2"):
            self.assertEqual(ATLAS.candidate_geometry_policy({"geometry_policy": policy}), policy)

    def test_geometry_replay_rejects_unknown_or_malformed_policy(self):
        for policy in ("source-cover-v3", "default", "", None, False, 1, [], {}):
            with self.subTest(policy=policy), self.assertRaisesRegex(RuntimeError, "geometry_policy"):
                ATLAS.candidate_geometry_policy({"geometry_policy": policy})
        with self.assertRaises(RuntimeError):
            ATLAS.candidate_geometry_policy([])

    def test_component_replay_passes_recorded_policy_explicitly(self):
        # Assert keyword forwarding even for an absent/legacy policy: replay
        # must never rely on whichever default the current builder prefers.
        vertices = [SimpleNamespace(index=i, co=point) for i, point in enumerate(
            ((0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)))]
        mesh = SimpleNamespace(data=SimpleNamespace(vertices=vertices,
            polygons=[SimpleNamespace(vertices=(0, 1, 2))]))
        source = SimpleNamespace(name="HeroBodyTest")
        reduced = SimpleNamespace(data=SimpleNamespace(vertices=vertices))
        reducer = Mock(return_value=(reduced, 3, 1))
        adapter = SimpleNamespace(reduce_component=reducer, component_spec=lambda _name: ("body", 12500),
                                  canonical_position=tuple)
        bpy = SimpleNamespace(data=SimpleNamespace(objects=SimpleNamespace(remove=Mock())))
        for policy in (None, "legacy", "source-cover-v1", "source-cover-v2"):
            audit = {"components": [{"lod": 0, "source": source.name, "target": 14000, "after": 1}],
                     "lods": [{"sole_fit": {"constant_foot_toe_offset_z_m": 0.0}}]}
            if policy is not None:
                audit["geometry_policy"] = policy
            with patch.object(ATLAS, "adapter", adapter, create=True), patch.object(ATLAS, "bpy", bpy, create=True):
                self.assertEqual(ATLAS.recover_components(mesh, [source], 0, audit, "scratch"), ([0, 0, 0], [0]))
            reducer.assert_called_with(source, 14000, "scratch", geometry_policy=policy or "legacy")

    def mask_source(self, values=None, contract="feather-palette-weights-v1", domain="POINT", data_type="FLOAT_COLOR"):
        source = {"source_mask_contract": contract} if contract is not None else {}
        class Source(dict):
            pass
        source = Source(source)
        source.name = "HeroBodyTest"
        attribute = SimpleNamespace(domain=domain, data_type=data_type,
                                    data=[SimpleNamespace(color=value) for value in values or []])
        source.data = SimpleNamespace(vertices=[0, 1], color_attributes={} if values is None else {"SourceSemanticMasks": attribute})
        return source

    def test_explicit_semantics_preserve_authoritative_values_exactly(self):
        values = [(0.2, 0.3, 0.1, 1.0), (0.0, 0.0, 0.0, 1.0)]
        self.assertEqual(ATLAS.saved_semantic_values(self.mask_source(values)), values)

    def test_absent_explicit_contract_keeps_legacy_analytic_path(self):
        self.assertIsNone(ATLAS.saved_semantic_values(self.mask_source(contract=None)))

    def test_partial_or_wrong_source_mask_contract_fails(self):
        values = [(0, 0, 0, 1)] * 2
        for source in (self.mask_source(), self.mask_source(values, contract=None),
                       self.mask_source(values, contract="unknown"), self.mask_source(values, domain="CORNER"),
                       self.mask_source(values, data_type="BYTE_COLOR"), self.mask_source(values[:1])):
            with self.assertRaises(RuntimeError):
                ATLAS.saved_semantic_values(source)

    def test_explicit_semantics_reject_nonphysical_or_nonfeather_weights(self):
        for value in ((0.8, 0.4, 0, 1), (-0.1, 0, 0, 1), (float("nan"), 0, 0, 1),
                      (0, 0, float("inf"), 1), (0, 0, 0, 0), (0, 0, 0)):
            with self.assertRaises(RuntimeError):
                ATLAS.saved_semantic_values(self.mask_source([value, value]))

    def test_probe_tbn_handles_mirrored_uv(self):
        for sign in (-1, 1):
            target = PROBES.world_to_tangent((0.2, 0.5, 0.8), (1, 0, 0), (0, 0, 1), sign)
            expected = PROBES.normalized((0.2, 0.5 * sign, 0.8))
            for actual, desired in zip(target, expected):
                self.assertAlmostEqual(actual, desired)

    def test_probe_tbn_inverts_nonorthonormal_interpolation(self):
        # Forward transform known tangent normal through a skewed interpolated
        # basis; inverse must recover it, unlike naive dot-product conversion.
        tangent, normal, sign = (0.8, 0.1, 0.05), (0.1, 0, 0.9), -1
        bitangent = tuple(x * sign for x in PROBES.cross(normal, tangent))
        expected = PROBES.normalized((0.2, 0.3, 0.8))
        world = tuple(tangent[i] * expected[0] + bitangent[i] * expected[1] + normal[i] * expected[2] for i in range(3))
        for actual, desired in zip(PROBES.world_to_tangent(world, tangent, normal, sign), expected):
            self.assertAlmostEqual(actual, desired)

    def test_probe_rejects_degenerate_tbn_and_bad_handedness(self):
        for tangent, normal, sign in (((0, 0, 1), (0, 0, 1), 1), ((1, 0, 0), (0, 0, 1), 0)):
            with self.assertRaises(ValueError):
                PROBES.world_to_tangent((0, 0, 1), tangent, normal, sign)

    def test_probe_has_strict_physical_source_distance_cap(self):
        PROBES.enforce_distance(0.00025)
        for distance in (-1, 0.000251, float("inf"), float("nan")):
            with self.assertRaises(ValueError):
                PROBES.enforce_distance(distance)

    def test_mouth_scratch_normal_has_explicit_angular_limit(self):
        normal = (0, 0, 1)
        angle = math.radians(0.08)
        audit = ATLAS.scratch_normal_roundtrip([normal], [(math.sin(angle), 0, math.cos(angle))])
        self.assertAlmostEqual(audit["maximum_degrees"], 0.08)
        self.assertAlmostEqual(audit["rms_degrees"], 0.08)
        self.assertFalse(audit["exact"])
        self.assertEqual(audit["limit_degrees"], 0.1)
        angle = math.radians(0.11)
        with self.assertRaises(RuntimeError):
            ATLAS.scratch_normal_roundtrip([normal], [(math.sin(angle), 0, math.cos(angle))])
        with self.assertRaises(RuntimeError):
            ATLAS.scratch_normal_roundtrip([normal], [(0, 0, 0)])

    def test_projection_failure_stays_rejected_in_diagnostic_binding(self):
        gate = ATLAS.projection_gate(41, rejection_hash="a" * 64)
        self.assertEqual(gate, {"passed": False, "missing_pixels": 41, "source_rejection_sha256": "a" * 64})
        self.assertEqual(ATLAS.projection_gate(0), {"passed": True, "missing_pixels": 0})
        with self.assertRaises(ValueError):
            ATLAS.projection_gate(0, rejection_hash="a" * 64)

    def test_projection_gate_rejects_invalid_count_or_unbound_rejection(self):
        for count in (-1, True, 0.0, "0"):
            with self.subTest(count=count), self.assertRaises(ValueError):
                ATLAS.projection_gate(count)
        with self.assertRaises(ValueError):
            ATLAS.projection_gate(41, rejection_hash="not-a-hash")

    def test_output_cannot_target_live_art_or_parent(self):
        for path in (ROOT, ROOT / "qa_shots/hero", ROOT / "assets/art/characters", ROOT / "art_src/characters"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                ATLAS.safe_output(str(path))

    def test_hard_regions_are_not_semantic_feathers(self):
        self.assertEqual(ATLAS.analytic_masks((0.0, -0.4, 0.9), feather=False), (0, 0, 0, 0))

    def test_ventral_palette_reconstructs_from_explicit_weights(self):
        mask = ATLAS.analytic_masks((0.0, -0.4, 0.9))
        self.assertEqual(mask, (1, 0, 0, 1))
        self.assertEqual(ATLAS.recompose(mask), ATLAS.PALETTE["ventral"])

    def test_mask_weights_stay_exclusive(self):
        for x in (-0.42, -0.2, 0, 0.2, 0.42):
            for y in (-0.4, -0.2, 0.2, 0.4):
                for z in (0.2, 0.8, 1.232, 1.411, 1.557, 1.7):
                    mask = ATLAS.analytic_masks((x, y, z))
                    self.assertTrue(all(0 <= channel <= 1 for channel in mask))
                    self.assertLessEqual(sum(mask[:3]), 1.0000001)

    def test_waterline_retains_feather_membership(self):
        self.assertEqual(ATLAS.analytic_masks((0.2, -0.3, 1.55), waterline=1), (0, 0, 0, 1))

    def test_wing_cream_uses_authored_ring_and_blade_direction(self):
        self.assertGreater(ATLAS.wing_cream(22, 18, -1), 0.1)
        self.assertEqual(ATLAS.wing_cream(22, 18, 1), 0)
        self.assertEqual(ATLAS.wing_cream(0, 18, -1), 0)
        self.assertEqual(ATLAS.wing_cream(44, 18, -1), 0)

    def test_uv_triangle_overlap_distinguishes_shared_edge(self):
        first = [(0, 0), (1, 0), (0, 1)]
        self.assertAlmostEqual(ATLAS.triangle_overlap_area(first, first), 0.5)
        self.assertEqual(ATLAS.triangle_overlap_area(first, [(1, 0), (1, 1), (0, 1)]), 0)
        self.assertEqual(ATLAS.triangle_overlap_area(first, [(2, 0), (3, 0), (2, 1)]), 0)
        self.assertAlmostEqual(ATLAS.triangle_overlap_area(first, [(0, 0), (0.5, 0), (0, 0.5)]), 0.125)

    def test_fold_staging_preserves_tiny_charts_old_far_translation_collapsed(self):
        tiny = [(0.0, 0.0), (1e-5, 0.0), (2e-6, 3e-6)]
        thin = [(0.0, 0.0), (.01, 0.0), (.003, 1e-8)]
        def old_staging(points, chart):
            return [struct.unpack("<2f", struct.pack("<2f", 10 + chart + u, 10 + v)) for u, v in points]
        self.assertEqual(ATLAS.cross(*old_staging(tiny, 500)), 0.0)
        self.assertEqual(ATLAS.cross(*old_staging(thin, 500)), 0.0)
        triangles = [[(0.0, 0.0), (.0002, 0.0), (.0001, .0001)]] * 500 + [tiny, thin]
        staged = ATLAS.compact_uv_triangle_staging(triangles)
        bounds = []
        for before, after in zip(triangles, staged):
            before_area, after_area = ATLAS.cross(*before) * .5, ATLAS.cross(*after) * .5
            self.assertGreaterEqual(abs(after_area), 1e-15)
            # Staging enforces <=0.01% relative float32 area error, separate
            # from the unchanged 1e-15 degeneracy/1e-12 overlap gates.
            self.assertTrue(math.isclose(after_area, before_area, rel_tol=1e-4))
            self.assertTrue(all(u < 0 for u, _v in after))
            bounds.append((min(u for u, _v in after), max(u for u, _v in after)))
        ordered = sorted(bounds)
        self.assertTrue(all(first[1] < second[0] for first, second in zip(ordered, ordered[1:])))

    def test_fold_staging_is_rigid_preserves_winding_and_density(self):
        triangles = [[(.03, .02), (.0301, .021), (.031, .0204)],
                     [(.03, .02), (.031, .0204), (.0301, .021)],
                     [(0.0, 0.0), (.02, .0), (.007, .011)]]
        staged = ATLAS.compact_uv_triangle_staging(triangles)
        for before, after in zip(triangles, staged):
            for first, second in ((0, 1), (1, 2), (2, 0)):
                self.assertTrue(math.isclose(math.dist(before[first], before[second]),
                                            math.dist(after[first], after[second]), rel_tol=1e-6))
            self.assertTrue(math.isclose(ATLAS.cross(*before), ATLAS.cross(*after), rel_tol=1e-6))
        old_ratio = abs(ATLAS.cross(*triangles[2]) / ATLAS.cross(*triangles[0]))
        new_ratio = abs(ATLAS.cross(*staged[2]) / ATLAS.cross(*staged[0]))
        self.assertTrue(math.isclose(old_ratio, new_ratio, rel_tol=1e-6))

    def test_fold_staging_keeps_degenerate_and_nonfinite_rejections(self):
        for points in ([(0, 0), (1, 1), (2, 2)], [(0, 0), (1e-8, 0), (0, 1e-8)],
                       [(0, 0), (1, 0), (0, float("nan"))], [(0, 0), (float("inf"), 0), (0, 1)]):
            with self.subTest(points=points), self.assertRaises(RuntimeError):
                ATLAS.compact_uv_triangle_staging([points])

    def test_face_receives_more_texels_per_surface_area(self):
        self.assertEqual(set(ATLAS.UV_WEIGHTS), {"face", "head_back", "torso", "wing", "foot", "tail"})
        self.assertGreaterEqual(ATLAS.UV_WEIGHTS["face"] / ATLAS.UV_WEIGHTS["torso"], 4)

    def test_front_face_has_explicit_priority_region(self):
        self.assertEqual(ATLAS.uv_region("body", (0.0, 0.3, 1.5)), "face")
        self.assertEqual(ATLAS.uv_region("body", (0.0, -0.3, 1.5)), "head_back")
        self.assertEqual(ATLAS.uv_region("eye", (0, 0, 0)), "face")
        with self.assertRaises(ValueError):
            ATLAS.uv_region("unclassified", (0, 0, 0))


if __name__ == "__main__":
    unittest.main()
