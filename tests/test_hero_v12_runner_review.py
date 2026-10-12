"""Host safety contracts; capture source gates are not rendered/raster proof."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("runner_review", ROOT / "tools/art/run_hero_v12_runner_review.py")
review = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review)


class CandidateReviewTests(unittest.TestCase):
    def make_glb(self, path: Path, surfaces: int = 2, color: bool = True) -> None:
        attributes = {"POSITION": 0, **({"COLOR_0": 1} if color else {})}
        data = json.dumps({"asset": {"version": "2.0"}, "meshes": [{"primitives": [
            {"attributes": attributes} for _ in range(surfaces)]}]}).encode()
        data += b" " * (-len(data) % 4)
        path.write_bytes(struct.pack("<4sIIII", b"glTF", 2, 20 + len(data), len(data), 0x4E4F534A) + data)

    def test_literal_two_surface_route_only(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "candidate.glb"
            self.make_glb(path)
            self.assertEqual(len(review.candidate_document(path)["meshes"][0]["primitives"]), 2)
            self.make_glb(path, color=False)
            with self.assertRaisesRegex(ValueError, "not an atlas GLB"):
                review.candidate_document(path)
            self.make_glb(path, surfaces=1)
            with self.assertRaises(ValueError):
                review.candidate_document(path)

    def test_corrupt_glb_length_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "candidate.glb"
            self.make_glb(path)
            path.write_bytes(path.read_bytes() + b"bad")
            with self.assertRaises(ValueError):
                review.candidate_document(path)

    def test_external_images_cannot_escape_source(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "candidate.glb"
            image = Path(folder) / "albedo.png"
            image.write_bytes(b"image")
            self.assertEqual(review.local_image(source, "albedo.png"), image)
            for uri in ("../albedo.png", "/tmp/a.png", "https:a", "a\\b.png", "..", ""):
                with self.assertRaises(ValueError, msg=uri):
                    review.local_image(source, uri)
            (Path(folder) / "alias.png").symlink_to(image)
            with self.assertRaises(ValueError):
                review.local_image(source, "alias.png")

    def test_wrapper_targets_qa_only_controller_and_candidate(self):
        self.assertIn('res://qa_hero/candidate.glb', review.WRAPPER)
        self.assertIn('res://tests/hero_v12_review_rig.gd', review.WRAPPER)
        self.assertNotIn('res://assets/art/characters/hero_penguin_v1.glb', review.WRAPPER)

    def test_controller_does_not_replace_motion_implementation(self):
        text = (ROOT / "tests/hero_v12_review_rig.gd").read_text()
        self.assertTrue(text.startswith("extends HeroPenguinRig"))
        for name in ("tick", "set_pose", "drive_motion", "set_cadence", "_play", "configure", "_ready"):
            self.assertNotIn(f"func {name}(", text)
        self.assertIn("explicit_qa_repair", text)
        self.assertIn("waddle-v12-runner-review-", text)

    def test_capture_uses_real_facade_clock_and_runner(self):
        text = (ROOT / "tests/hero_v12_facade_capture.gd").read_text()
        self.assertTrue(text.startswith('extends "res://tests/hero_penguin_capture.gd"'))
        self.assertIn("super._step_motion(delta)", text)
        runner = (ROOT / "tests/hero_v12_runner_capture.gd").read_text()
        self.assertIn("load(Game.SCENE_RUNNER)", runner)
        self.assertIn("RunnerPlayer.autopilot = not _play", runner)
        self.assertIn('"performance_measured": false', runner)

    def test_capture_orientation_sets_fixed_viewport_and_window_dimensions(self):
        text = (ROOT / "tests/hero_penguin_capture.gd").read_text()
        ready = text.split("func _ready(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn('if _orientation_name not in ["landscape", "portrait"]:', ready)
        self.assertIn("get_tree().quit(2)\n\t\treturn", ready)
        self.assertIn('_capture_pixel_size = Vector2i(720, 1280) if _orientation_name == "portrait" else Vector2i(1280, 720)', ready)
        self.assertIn("var window := get_window()", ready)
        for assignment in (
            "window.size = _capture_pixel_size",
            "window.content_scale_size = _capture_pixel_size",
            "window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT",
            "window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP",
        ):
            self.assertIn(assignment, ready)
            self.assertLess(ready.index(assignment), ready.index("_build_stage()"))

    def test_capture_actual_image_size_is_guarded_before_each_frame_save(self):
        text = (ROOT / "tests/hero_penguin_capture.gd").read_text()
        validator = text.split("func _validate_capture_dimensions(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("if image == null or image.is_empty():", validator)
        self.assertIn("if image.get_size() != _capture_pixel_size:", validator)
        self.assertEqual(validator.count("_capture_failed = true"), 2)
        self.assertEqual(validator.count("return false"), 2)
        pose = text.split("func _capture_pose(", 1)[1].split("\nfunc ", 1)[0]
        guard = "if not _validate_capture_dimensions(image):\n\t\treturn"
        self.assertIn(guard, pose)
        self.assertLess(pose.index("get_texture().get_image()"), pose.index(guard))
        self.assertLess(pose.index(guard), pose.index("image.save_png(path)"))
        self.assertIn('print("HERO CAPTURE PIXELS: %s %dx%d" % [path, image.get_width(), image.get_height()])', pose)
        motion = text.split("func _capture_motion(", 1)[1].split("\nfunc ", 1)[0]
        guard = "\t\tif not _validate_capture_dimensions(screenshot):\n\t\t\treturn"
        self.assertIn(guard, motion)
        self.assertLess(motion.index("for frame: int in frame_count:"), motion.index(guard))
        self.assertLess(motion.index("get_texture().get_image()"), motion.index(guard))
        self.assertLess(motion.index(guard), motion.index("screenshot.save_png("))
        self.assertEqual(text.count("get_tree().quit(1 if _capture_failed else 0)"), 2)

    def test_motion_manifest_records_actual_dimensions_and_centered_aspect_fit(self):
        text = (ROOT / "tests/hero_penguin_capture.gd").read_text()
        motion = text.split("func _capture_motion(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("capture_dimensions = screenshot.get_size()", motion)
        for field in (
            '"requested_pixel_dimensions": [_capture_pixel_size.x, _capture_pixel_size.y]',
            '"capture_pixel_dimensions": [capture_dimensions.x, capture_dimensions.y]',
            '"pixel_dimensions": [capture_dimensions.x, capture_dimensions.y]',
            '"contact_sheet_tile_dimensions": [tile.x, tile.y]',
            '"contact_sheet_resize": "aspect_fit_centered"',
        ):
            self.assertIn(field, motion)
        fit = text.split("func _fit_thumbnail_size(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("minf(float(tile.x) / source_size.x, float(tile.y) / source_size.y)", fit)
        self.assertIn("maxi(1, floori(source_size.x * fit))", fit)
        self.assertIn("maxi(1, floori(source_size.y * fit))", fit)
        self.assertIn("var fitted := _fit_thumbnail_size(screenshot.get_size(), tile)", motion)
        self.assertIn("thumbnail.resize(fitted.x, fitted.y, Image.INTERPOLATE_LANCZOS)", motion)
        self.assertNotIn("thumbnail.resize(tile.x, tile.y", motion)
        self.assertIn("var inset := Vector2i((tile.x - fitted.x) / 2, (tile.y - fitted.y) / 2)", motion)
        self.assertIn("contact.blit_rect(thumbnail, Rect2i(Vector2i.ZERO, fitted),", motion)
        self.assertIn("Vector2i(cell % 4, cell / 4) * tile + inset)", motion)

    def test_exit_zero_runtime_errors_are_not_reusable_passes(self):
        with tempfile.TemporaryDirectory() as folder:
            log = Path(folder) / "engine.log"
            log.write_text("Godot\nERROR: resources still in use\n")
            review.write_json(log.with_suffix(".result.json"), {"exit_code": 0, "log_sha256": review.sha(log)})
            with self.assertRaises(RuntimeError):
                review.check_engine_log(log)
            log.write_text("Godot\nPASS\n")
            with self.assertRaises(RuntimeError):
                review.check_engine_log(log)
            review.write_json(log.with_suffix(".result.json"), {"exit_code": 0, "log_sha256": review.sha(log)})
            review.check_engine_log(log)


if __name__ == "__main__":
    unittest.main()
