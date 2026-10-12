"""Admission/readiness boundaries; never writes real art or manifests."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "wardrobe_library", Path(__file__).with_name("wardrobe_outfit_library.py"))
LIBRARY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(LIBRARY)


def job(key, status):
    return {"key": key, "status": status, "body": "body_classic",
            "hat": "none", "goggles": "none", "scarf": "none",
            "source": f"art_src/{key}.png", "runtime": f"res://assets/{key}.webp",
            "source_sha256": "a" * 64, "runtime_sha256": "b" * 64,
            "dimensions": [512, 768]}


class WardrobeAdmissionTests(unittest.TestCase):
    def test_only_reviewed_output_is_production_ready(self):
        with patch.object(LIBRARY, "save_json") as save:
            LIBRARY.register_art({"jobs": [job("accepted", "reviewed"), job("waiting", "generated")]})
        assets = {entry["id"]: entry for entry in save.call_args.args[1]["runtime_assets"]}
        self.assertTrue(assets["wardrobe_v1_accepted"]["production_ready"])
        self.assertFalse(assets["wardrobe_v1_waiting"]["production_ready"])

    def test_queued_jobs_do_not_create_manifest_assets(self):
        with patch.object(LIBRARY, "save_json") as save:
            counts = LIBRARY.register_art({"jobs": [job("queued", "queued")]})
        self.assertEqual(counts, {"concepts": 0, "generated_assets": 0, "runtime_assets": 0, "source_exports": 0})
        self.assertEqual(save.call_args.args[1]["runtime_assets"], [])

    def test_runtime_catalog_admits_reviewed_output_only(self):
        with patch.object(LIBRARY, "save_json") as save:
            LIBRARY.rebuild_catalog({"jobs": [job("accepted", "reviewed"), job("waiting", "generated"), job("queued", "queued")]})
        catalog = save.call_args.args[1]
        self.assertEqual(catalog["expected"], 480)
        self.assertEqual(set(catalog["entries"]), {"accepted"})
        self.assertEqual(catalog["entries"]["accepted"]["runtime_sha256"], "b" * 64)


if __name__ == "__main__":
    unittest.main()
