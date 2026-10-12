#!/usr/bin/env python3
"""Pixel metric and source-preservation contract tests; no engine required."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("ui_texture_imports", Path(__file__).with_name("ui_texture_imports.py"))
tool = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(tool)


class QualityTests(unittest.TestCase):
    def test_quality_change_preserves_every_other_setting(self):
        text = "compress/mode=0\ncompress/lossy_quality=0.7\nmipmaps/generate=false\nprocess/size_limit=0\nuid=original\n"
        after = tool.set_quality(text, 0.98)
        self.assertEqual(tool.non_quality_settings(text), tool.non_quality_settings(after))
        self.assertIn("compress/mode=1", after)
        for quality in [0.89, 1.1]:
            with self.assertRaises(ValueError):
                tool.set_quality(text, quality)

    def test_only_audited_webp_scopes(self):
        self.assertTrue(tool.allowed("assets/art/ui/menu/nested/a.webp"))
        self.assertTrue(tool.allowed("assets/art/ui/wardrobe_outfits_v1/a.webp"))
        for path in ["assets/art/ui/menu/a.png", "assets/art/ui/menu/../a.webp", "/assets/art/ui/menu/a.webp", "assets/art/runner/a.webp"]:
            self.assertFalse(tool.allowed(path))

    def test_exact_pixels_score_one_and_alpha_error_is_not_hidden(self):
        from PIL import Image
        with tempfile.TemporaryDirectory() as directory:
            a, b = Path(directory) / "a.png", Path(directory) / "b.png"
            image = Image.new("RGBA", (32, 32), (70, 100, 130, 160))
            image.save(a)
            image.save(b)
            metrics = tool.pixel_metrics(a, b)
            self.assertEqual(metrics["alpha_max_error"], 0)
            self.assertAlmostEqual(metrics["ssim_black"], 1)
            self.assertAlmostEqual(metrics["ssim_white"], 1)
            image.putpixel((12, 12), (70, 100, 130, 159))
            image.save(b)
            self.assertEqual(tool.pixel_metrics(a, b)["alpha_max_error"], 1)

    def test_rgb_error_and_dimensions_are_checked(self):
        from PIL import Image
        with tempfile.TemporaryDirectory() as directory:
            a, b = Path(directory) / "a.png", Path(directory) / "b.png"
            Image.new("RGBA", (32, 32), (30, 50, 70, 255)).save(a)
            Image.new("RGBA", (32, 32), (100, 50, 70, 255)).save(b)
            metrics = tool.pixel_metrics(a, b)
            self.assertEqual(metrics["visible_rgb_max_error"], 70)
            self.assertLess(metrics["visible_rgb_psnr_db"], 35)
            Image.new("RGBA", (16, 16)).save(b)
            with self.assertRaisesRegex(ValueError, "dimensions"):
                tool.pixel_metrics(a, b)


if __name__ == "__main__":
    unittest.main()
