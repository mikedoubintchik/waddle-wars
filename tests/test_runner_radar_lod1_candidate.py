#!/usr/bin/env python3
"""Small host-side contract tests; no Blender, GPU, or save writes."""

import importlib.util
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/art"))
import build_runner_radar_lod1_candidate as radar


class RadarCandidateTests(unittest.TestCase):
    def test_live_output_rejected(self):
        with self.assertRaises(ValueError):
            radar.safe_output(ROOT / "assets/art/runner/day")

    def test_broad_qa_output_rejected(self):
        with self.assertRaises(ValueError):
            radar.safe_output(ROOT / "qa_shots/runner")

    def test_qa_child_accepted(self):
        self.assertEqual(radar.safe_output(ROOT / "qa_shots/runner/radar_lod1_unit"),
                         ROOT / "qa_shots/runner/radar_lod1_unit")

    def test_operations_silhouette_keeps_three_bevel_segments(self):
        before = {"segments": 5, "bevel": 0.42, "center": (0, 0, 2.65),
                  "size": (8.8, 6.6, 4.0), "colour": (0.865, 0.930, 0.925, 1)}
        after = radar.candidate_parameters("box", "operations_block", before)
        self.assertEqual(after["segments"], 3)
        self.assertEqual({k: v for k, v in before.items() if k != "segments"},
                         {k: v for k, v in after.items() if k != "segments"})
        self.assertEqual(before["segments"], 5, "recipe input mutated")

    def test_windows_keep_full_bounds_and_pigment(self):
        before = {"segments": 3, "bevel": 0.08, "size": (0.78, 0.08, 0.78),
                  "center": (-3.45, -3.34, 3.1), "colour": (1, 0.61, 0.22, 1)}
        after = radar.candidate_parameters("box", "window_-1_0", before)
        self.assertEqual(after, dict(before, segments=1))

    def test_pole_has_endcaps_radius_and_full_height(self):
        before = {"vertices": 12, "bevel": 0.025, "radius": 0.10, "depth": 1.65}
        self.assertEqual(radar.candidate_parameters("cylinder", "perimeter_beacon_0", before),
                         dict(before, vertices=8, bevel=0))

    def test_radome_keeps_scale_and_radius(self):
        before = {"segments": 48, "rings": 24, "radius": 2.75, "scale": (1, 1, 0.86)}
        self.assertEqual(radar.candidate_parameters("sphere", "radome", before),
                         dict(before, segments=32, rings=16))

    def test_thin_radome_band_keeps_six_sided_cross_section(self):
        before = {"major_segments": 48, "minor_segments": 6, "major": 2.5, "minor": 0.045}
        self.assertEqual(radar.candidate_parameters("torus", "radome_band_-0.42", before),
                         dict(before, major_segments=32))

    def test_unknown_primitive_rejected(self):
        with self.assertRaises(ValueError):
            radar.candidate_parameters("decimate", "tower", {})

    def test_oriented_triangle_preserves_winding(self):
        a, b, c = (0, 0, 0), (1, 0, 0), (0, 1, 0)
        self.assertEqual(radar.oriented_key((a, b, c)), radar.oriented_key((b, c, a)))
        self.assertNotEqual(radar.oriented_key((a, b, c)), radar.oriented_key((a, c, b)))

    def test_index_order_canonicalization_preserves_winding_and_multiplicity(self):
        self.assertEqual(radar.canonical_index_order([5, 6, 4, 2, 0, 1, 0, 1, 2]),
                         [0, 1, 2, 0, 1, 2, 4, 5, 6])
        self.assertNotEqual(radar.canonical_index_order([0, 1, 2]),
                            radar.canonical_index_order([0, 2, 1]))

    def test_invalid_index_order_rejected(self):
        for indices in ([0, 1], [0, 1, -1], [0, 1, 2.5]):
            with self.subTest(indices=indices), self.assertRaises(ValueError):
                radar.canonical_index_order(indices)

    def test_face_sort_preserves_corner_colors_and_winding(self):
        records = [([2, 0, 1], True, ["blue", "red", "green"])]
        self.assertEqual(radar.canonical_face_records(records),
                         [((0, 1, 2), True, ("red", "green", "blue"))])
        self.assertNotEqual(radar.canonical_face_records(records),
                            radar.canonical_face_records([([2, 1, 0], True, ["blue", "green", "red"])]))

    def test_nonfinite_position_rejected(self):
        with self.assertRaises(ValueError):
            radar.oriented_key(((0, 0, 0), (1, 0, 0), (0, float("nan"), 0)))

    def test_component_support_fit_preserves_center_and_bounds(self):
        fitted, scales = radar.fit_component_points([(-1.1, -2, -3), (1.1, 2, 3), (0, 0, 0)],
                                                    [-1, -2, -3], [1, 2, 3])
        self.assertEqual(fitted, [(-1, -2, -3), (1, 2, 3), (0, 0, 0)])
        self.assertAlmostEqual(scales[0], 1 / 1.1)

    def test_excessive_support_fit_rejected(self):
        with self.assertRaises(ValueError):
            radar.fit_component_points([(-1, -1, -1), (1, 1, 1)], [-1, -1, -2], [1, 1, 2])

    def test_degenerate_support_fit_rejected(self):
        with self.assertRaises(ValueError):
            radar.fit_component_points([(0, 0, 0)], [0, 0, 0], [1, 1, 1])

    def region(self, **kwargs):
        return dict({"triangles": 12, "area": 6, "bounds_min": [0, 0, 0],
                     "bounds_max": [1, 1, 1]}, **kwargs)

    def test_all_named_regions_required(self):
        with self.assertRaises(ValueError):
            radar.validate_regions({"tower": self.region(), "radome": self.region()},
                                   {"radome": self.region()})

    def test_collapsed_area_rejected_even_when_bounds_match(self):
        with self.assertRaises(ValueError):
            radar.validate_regions({"tower": self.region()}, {"tower": self.region(area=1)})

    def test_component_bounds_change_rejected(self):
        with self.assertRaises(ValueError):
            radar.validate_regions({"tower": self.region()},
                                   {"tower": self.region(bounds_max=[1, 1, 0.99])})

    def test_reduced_triangles_with_retained_bounds_and_area_accepted(self):
        result = radar.validate_regions({"tower": self.region(triangles=100)},
                                        {"tower": self.region(triangles=12, area=5.8)})
        self.assertEqual(result[0]["candidate_triangles"], 12)
        self.assertAlmostEqual(result[0]["surface_area_ratio"], 5.8 / 6)

    def test_existing_recipe_components_remain_unique(self):
        spec = importlib.util.spec_from_file_location("day_duplicate_tests", ROOT / "tests/test_runner_day_duplicate_geometry.py")
        helpers = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helpers)
        calls = helpers.primitive_calls(radar.BUILDER, "build_radar_landmark")
        names = [name for name, _ in calls]
        self.assertEqual(len(names), len(set(names)))
        self.assertTrue({"foundation", "operations_block", "tower", "radome"} <= set(names))
        self.assertEqual(sum(name.startswith("window_") for name in names), 14)
        self.assertEqual(sum(name.startswith("perimeter_beacon_") for name in names), 16)
        self.assertEqual(sum(name.startswith("perimeter_lamp_") for name in names), 16)
        self.assertEqual(sum(name.startswith("tower_brace_") for name in names), 4)


if __name__ == "__main__":
    unittest.main()
