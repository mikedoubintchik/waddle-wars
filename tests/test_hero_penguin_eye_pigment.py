"""Pure iris-pigment math guards; rendered fidelity deliberately not asserted."""

import importlib.util
import math
from pathlib import Path
import random
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("hero_eye_pigment", ROOT / "tools/art/hero_penguin_eye_pigment.py")
PIGMENT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PIGMENT)


def luminance(color):
    return sum(channel * weight for channel, weight in zip(color, (0.2126, 0.7152, 0.0722)))


class HeroEyePigmentTests(unittest.TestCase):
    def test_finite_bounded_opaque_linear_colors_across_disk(self):
        for ring in range(65):
            radius = ring / 64
            for sector in range(96):
                angle = math.tau * sector / 96
                color = PIGMENT.iris_linear_rgba(radius * math.cos(angle), radius * math.sin(angle))
                self.assertEqual(len(color), 4)
                self.assertTrue(all(math.isfinite(value) and 0 <= value <= 1 for value in color))
                self.assertEqual(color[3], 1.0)
                self.assertLess(max(color[:3]), 0.26)
                self.assertLess(color[0], color[1])
                self.assertLess(color[1], color[2])

    def test_center_and_edge_have_explicit_linear_values(self):
        self.assertEqual(PIGMENT.iris_linear_rgba(0, 0), PIGMENT.INNER_LINEAR + (1.0,))
        for sector in range(64):
            angle = math.tau * sector / 64
            for actual, expected in zip(PIGMENT.iris_linear_rgba(math.cos(angle), math.sin(angle))[:3], PIGMENT.OUTER_LINEAR):
                self.assertAlmostEqual(actual, expected, places=14)

    def test_invalid_values_and_outside_disk_rejected(self):
        for x, z in ((float("nan"), 0), (0, float("inf")), (-float("inf"), 0),
                     (1.001, 0), (0, -1.001), (0.8, 0.8)):
            with self.subTest(x=x, z=z), self.assertRaises(ValueError):
                PIGMENT.iris_linear_rgba(x, z)

    def test_only_tiny_boundary_roundoff_is_accepted(self):
        expected = PIGMENT.iris_linear_rgba(1, 0)
        self.assertEqual(PIGMENT.iris_linear_rgba(1 + 1e-10, 0), expected)
        with self.assertRaises(ValueError):
            PIGMENT.iris_linear_rgba(1 + 2e-9, 0)

    def test_seed_independent_and_random_state_unchanged(self):
        original_state = random.getstate()
        try:
            expected = [PIGMENT.iris_linear_rgba(x, z) for x, z in ((0, 0), (0.4, 0.5), (-0.6, 0.3), (0, 1))]
            for seed in (0, 1, 271828, 20260907):
                random.seed(seed)
                before = random.getstate()
                actual = [PIGMENT.iris_linear_rgba(x, z) for x, z in ((0, 0), (0.4, 0.5), (-0.6, 0.3), (0, 1))]
                self.assertEqual(actual, expected)
                self.assertEqual(random.getstate(), before)
        finally:
            random.setstate(original_state)

    def test_continuous_at_center_angular_seam_and_radial_joins(self):
        epsilon = 1e-7
        pairs = [((0, 0), (epsilon, -epsilon)), ((-0.7, epsilon), (-0.7, -epsilon))]
        for radius in (0.20, 0.32, 0.48, 0.74, 0.76):
            pairs.append(((radius - epsilon, 0), (radius + epsilon, 0)))
        for before, after in pairs:
            difference = max(abs(a - b) for a, b in zip(PIGMENT.iris_linear_rgba(*before), PIGMENT.iris_linear_rgba(*after)))
            self.assertLess(difference, 1e-6)

    def test_outer_luminance_falls_for_every_sampled_sector(self):
        for sector in range(96):
            angle = math.tau * sector / 96
            values = [luminance(PIGMENT.iris_linear_rgba(radius * math.cos(angle), radius * math.sin(angle)))
                      for radius in (0.80, 0.85, 0.90, 0.95, 1.0)]
            self.assertTrue(all(a > b for a, b in zip(values, values[1:])))
            self.assertLess(values[-1], values[0] * 0.30)

    def test_sector_variation_is_restrained_and_low_frequency(self):
        values = [luminance(PIGMENT.iris_linear_rgba(0.68 * math.cos(math.tau * i / 360),
                                                  0.68 * math.sin(math.tau * i / 360)))
                  for i in range(360)]
        self.assertGreater(max(values) - min(values), 0.001)
        self.assertLess(max(values) - min(values), 0.012)
        extrema = sum((values[i] - values[i - 1]) * (values[(i + 1) % 360] - values[i]) < 0
                      for i in range(360))
        self.assertLessEqual(extrema, 6)


if __name__ == "__main__":
    unittest.main()
