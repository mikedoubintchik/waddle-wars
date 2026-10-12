#!/usr/bin/env python3
"""Pure recipe math/contracts. No Blender, renderer, maps or user-save writes."""

import math
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/art"))
import hero_penguin_v12_feather_detail_recipe as recipe


class FeatherDetailRecipeTests(unittest.TestCase):
    def test_calibration_covers_exact_existing_six_maps(self):
        expected = {f"hero_penguin_v11_{region}_{kind}_tile.png"
                    for region in ("dark", "cream") for kind in ("albedo", "normal", "orm")}
        self.assertEqual(set(recipe.TILE_SHA256), expected)
        self.assertTrue(all(len(value) == 64 for value in recipe.TILE_SHA256.values()))

    def test_measured_rgb_means_match_luminance_calibration(self):
        for region, values in recipe.REGIONS.items():
            with self.subTest(region=region):
                self.assertAlmostEqual(sum(a * b for a, b in zip(values["albedo_rgb_mean"], recipe.LUMA)),
                                       values["luma_mean"], places=11)

    def test_mean_sample_is_neutral_not_brighter(self):
        for region, values in recipe.REGIONS.items():
            with self.subTest(region=region):
                self.assertAlmostEqual(recipe.neutral_detail(values["albedo_rgb_mean"], region), 1.0, places=10)

    def test_detail_gain_keeps_linear_mean_for_asymmetric_samples(self):
        for region, values in recipe.REGIONS.items():
            mean = values["albedo_rgb_mean"]
            samples = [tuple(value * scale for value in mean) for scale in (0.98, 0.99, 1.03)]
            self.assertAlmostEqual(sum(recipe.neutral_detail(sample, region) for sample in samples) / 3, 1.0, places=10)

    def test_original_mean_tint_is_preserved_per_channel(self):
        for region, values in recipe.REGIONS.items():
            actual = recipe.baseline_mean_multiplier(region)
            expected = tuple(0.28 + 0.72 * value for value in values["albedo_rgb_mean"])
            for a, b in zip(actual, expected):
                self.assertAlmostEqual(a, b)

    def test_no_log_power_or_clamp_mean_drift(self):
        for region, values in recipe.REGIONS.items():
            mean = values["albedo_rgb_mean"]
            plus = recipe.neutral_detail(tuple(v * 1.02 for v in mean), region)
            minus = recipe.neutral_detail(tuple(v * 0.98 for v in mean), region)
            self.assertAlmostEqual((plus + minus) / 2, 1.0, places=10)

    def test_roughness_mean_is_authored_center(self):
        for region, values in recipe.REGIONS.items():
            self.assertAlmostEqual(recipe.roughness_response(values["orm_g_mean"], region),
                                   values["roughness_center"])

    def test_real_map_roughness_ranges_need_no_clipping(self):
        expected = {"dark": (0.52, 0.64), "cream": (0.65, 0.83)}
        for region, values in recipe.REGIONS.items():
            limits = [recipe.roughness_response(g, region) for g in values["measured_orm_g_range"]]
            self.assertGreater(limits[0], expected[region][0])
            self.assertLess(limits[1], expected[region][1])

    def test_directional_response_not_blanket_dark_normal_gain(self):
        self.assertEqual(recipe.REGIONS["dark"]["normal_strength"], 0.50)
        self.assertEqual(recipe.REGIONS["cream"]["normal_strength"], 0.90)
        self.assertLess(recipe.SHEEN_WEIGHT, 0.12)

    def test_nonfinite_inputs_rejected(self):
        with self.assertRaises(ValueError):
            recipe.neutral_detail((math.nan, 0, 0), "dark")
        with self.assertRaises(ValueError):
            recipe.roughness_response(math.inf, "cream")


if __name__ == "__main__":
    unittest.main()
