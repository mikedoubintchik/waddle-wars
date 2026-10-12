"""Bounded host guards; actual Blender first-hit/material proof is separate."""
import importlib.util
import math
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location("mouth", Path(__file__).resolve().parents[1] / "tools/art/hero_v12_mouth_projection.py")
M = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)


class MouthProjectionTests(unittest.TestCase):
    def test_mouth_cap_does_not_change_eye_cap(self):
        self.assertEqual(M.P.MAX_SOURCE_DISTANCE_M, .00025)
        M.enforce_distance(.00125)
        with self.assertRaises(ValueError):
            M.P.enforce_distance(.00125)

    def test_distance_rejects_negative_nonfinite_and_excess(self):
        for value in (-1e-12, .001250001, math.nan, math.inf):
            with self.subTest(value=value), self.assertRaises(ValueError):
                M.enforce_distance(value)

    def test_opposite_nearest_sheet_not_selected(self):
        back = ((0, 0, 0), (0, 0, -1), 1, .00001)
        front = ((0, 0, 0), (0, 0, 1), 2, .0012)
        self.assertEqual(M.select_facing_candidate([back, front], (0, 0, 1)), front)

    def test_grazing_positive_alignment_still_rejected(self):
        with self.assertRaises(ValueError):
            M.select_facing_candidate([((0, 0, 0), (1, 0, .1), 1, .00001)], (0, 0, 1))

    def test_facing_candidate_distance_is_bounded(self):
        with self.assertRaises(ValueError):
            M.select_facing_candidate([((0, 0, 0), (0, 0, 1), 1, .001251)], (0, 0, 1))

    def test_selection_stable_nearest_then_face_id(self):
        rows = [((0, 0, 0), (0, 0, 1), i, d) for i, d in ((10, .001), (8, .001), (1, .0011))]
        self.assertEqual(M.select_facing_candidate(rows, (0, 0, 1))[2], 8)

    def test_probe_retains_positive_source_edge_clearance(self):
        clearance = 2e-6
        radius = M.probe_radius(clearance)
        self.assertLessEqual(radius * 2, clearance * .8)
        with self.assertRaises(ValueError):
            M.probe_radius(1e-6)

    def test_scope_only_exact_mouth_name(self):
        M.validate_scope(["BillMouthSeam"] * 15)
        for value in ([], ["BillMouthSeam"] * 33, ["Iris+1"], ["BillMouthSeam.001"], ["UNOWNED"]):
            with self.subTest(value=value), self.assertRaises(ValueError):
                M.validate_scope(value)

    def test_actual_shader_normal_must_match_source(self):
        self.assertEqual(M.normal_error_degrees((0, 0, 1), (0, 0, 2)), 0)
        for wrong in ((0, 0, -1), (0, 1, 0), (.01, 0, 1)):
            with self.assertRaises(ValueError):
                M.normal_error_degrees((0, 0, 1), wrong)

    def test_thin_ribbon_dominant_axis_barycentrics(self):
        # Aspect ratio ~1e8, translated to actual metre-scale head height.
        for axis in range(3):
            for reverse in (False, True):
                points = [(0, 0, 0), (.04, 0, 0), (.039, 4e-10, 0)]
                points = [tuple(p[(i + axis) % 3] + (0.35, 0.1, 1.4)[i] for i in range(3)) for p in points]
                if reverse:
                    points[1], points[2] = points[2], points[1]
                expected = (.65, .02, .33)
                point = tuple(sum(p[i] * w for p, w in zip(points, expected)) for i in range(3))
                actual = M.barycentric(point, *points)
                for left, right in zip(actual, expected):
                    self.assertAlmostEqual(left, right, delta=1e-6)

    def test_barycentric_rejects_collinear_and_nonfinite(self):
        for points in (((0, 0, 0), (1, 1, 1), (2, 2, 2)), ((0, 0, 0), (1, 0, 0), (0, math.nan, 0))):
            with self.assertRaises(ValueError):
                M.barycentric((0, 0, 0), *points)

    def test_orm_uses_actual_ao_and_roughness(self):
        self.assertEqual(M.packed_orm(.42, .72, 0), (.42, .72, 0, 1))
        for args in ((.4, .7, .1), (math.nan, .7, 0), (.4, 1.1, 0)):
            with self.assertRaises(ValueError):
                M.packed_orm(*args)

    def test_reuses_original_mirrored_skewed_tbn_inverse(self):
        tangent, normal, sign = (.8, .1, .05), (.1, 0, .9), -1
        bitangent = tuple(v * sign for v in M.P.cross(normal, tangent))
        expected = M.P.normalized((.2, .3, .8))
        world = tuple(tangent[i] * expected[0] + bitangent[i] * expected[1] + normal[i] * expected[2] for i in range(3))
        actual = M.P.world_to_tangent(world, tangent, normal, sign)
        for left, right in zip(actual, expected):
            self.assertAlmostEqual(left, right, places=12)


if __name__ == "__main__":
    unittest.main()
