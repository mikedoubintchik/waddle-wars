"""Small host-only Z04 paint-field tests; no source mesh or rendering."""
import importlib.util
import math
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("orbital_saddle", ROOT / "tools/art/hero_penguin_v12_orbital_saddle.py")
S = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(S)


def frame(side):
    angle = side * .55
    return ((side * .225, -.30, 1.548),
            (math.cos(angle), math.sin(angle), 0),
            (math.sin(angle), -math.cos(angle), 0), (0, 0, 1))


def world(local, side):
    origin, *axes = frame(side)
    return tuple(origin[i] + sum(local[j] * axes[j][i] for j in range(3)) for i in range(3))


class OrbitalSaddleTests(unittest.TestCase):
    def test_field_is_mirrored_by_anatomical_side(self):
        for x in (-.12, -.04, 0, .06, .12):
            for z in (-.17, -.07, 0, .08):
                self.assertEqual(S.local_field(x, 0, z, 1), S.local_field(-x, 0, z, -1))

    def test_continuity_at_piecewise_boundaries(self):
        for point in ((.04, 0, -.026), (.04, 0, -.035), (.04, 0, -.185),
                      (.04, -.085, -.04), (.04, -.040, -.04), (0, 0, 0)):
            for axis in range(3):
                left, right = list(point), list(point)
                left[axis] -= 1e-7
                right[axis] += 1e-7
                self.assertLess(abs(S.local_field(*left, 1) - S.local_field(*right, 1)), 1e-4)

    def test_lower_surround_sweeps_nasally_into_cheek(self):
        for side in (-1, 1):
            nasal = S.local_field(-side * .025, 0, -.13, side)
            temporal = S.local_field(side * .025, 0, -.13, side)
            self.assertLess(nasal, temporal)
            self.assertLess(nasal, .94)
        for z in (-.13, -.10, -.06, -.02):
            self.assertLess(S.local_field(0, 0, z, 1), .94)

    def test_back_projection_is_excluded_without_camera_dependency(self):
        self.assertLess(S.local_field(0, 0, 0, 1), .94)
        self.assertGreater(S.local_field(0, -.20, 0, 1), 1.045)
        self.assertGreater(S.saddle_orbit_field(world((0, -.20, 0), 1), frame), 1.045)

    def test_world_field_uses_supplied_complete_frame(self):
        for local in ((.02, 0, -.06), (0, .01, .04), (-.04, -.01, -.12)):
            actual = S.saddle_orbit_field(world(local, 1), frame)
            self.assertAlmostEqual(actual, S.local_field(*local, 1), places=10)
            mirrored = world((-local[0], local[1], local[2]), -1)
            self.assertAlmostEqual(S.saddle_orbit_field(mirrored, frame), actual, places=10)

    def test_outside_face_does_not_evaluate_frames(self):
        def unexpected(_side):
            self.fail("body point evaluated eye-frame paint")
        for point in ((0, -.3, .7), (0, -.3, 1.8), (.6, -.3, 1.5), (0, .3, 1.5)):
            self.assertEqual(S.saddle_orbit_field(point, unexpected), 8.0)

    def test_finite_bounded_field_and_invalid_inputs(self):
        for x in (-1., -.1, 0., .1, 1.):
            value = S.local_field(x, -.01, -.05, 1)
            self.assertTrue(math.isfinite(value))
            self.assertGreaterEqual(value, 0)
            self.assertLessEqual(value, 8)
        for coordinates in ((float("nan"), 0, 0, 1), (0, float("inf"), 0, 1), (0, 0, 0, 0)):
            with self.assertRaises(ValueError):
                S.local_field(*coordinates)
        for point in ((0, 0), (float("nan"), 0, 0)):
            with self.assertRaises(ValueError):
                S.saddle_orbit_field(point, frame)

    def test_recipe_remains_source_only_and_matches_metadata_contract(self):
        spec = importlib.util.spec_from_file_location("saddle_provenance", ROOT / "tools/art/hero_penguin_v12_study_provenance.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertEqual(S.RECIPE, module.saddle_declarations()["orbital_saddle_recipe"])
        self.assertFalse(S.RECIPE["geometry_created"])
        self.assertFalse(S.RECIPE["source_fidelity_approved"])


if __name__ == "__main__":
    unittest.main()
