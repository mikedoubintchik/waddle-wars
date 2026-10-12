"""Unified-face construction guards; no render, export or appearance approval."""
from __future__ import annotations

import ast
import math
from pathlib import Path
import sys
from types import ModuleType
import unittest
from unittest.mock import patch

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/art"))
import hero_penguin_face_sculpt as face
import hero_penguin_v12_source_study as study
import hero_penguin_v12_study_provenance as provenance
import render_hero_penguin_v12_source_study as base
import render_hero_penguin_v12_face_z13 as source_renderer


def sample_points():
    return np.asarray([(x, y, z) for x in np.linspace(-.6, .6, 7)
                       for y in np.linspace(-.65, .35, 6)
                       for z in np.linspace(.1, 1.9, 10)])


def reflected(points):
    return np.asarray(points) * np.asarray((-1., 1., 1.))


class UnifiedFaceConstructionTests(unittest.TestCase):
    def test_frozen_inputs_include_imported_paint_helper_without_selected_prior(self):
        self.assertFalse(hasattr(face, "prior"))
        launcher = ROOT / "tools/art/render_hero_penguin_face_sculpt.py"
        paths = source_renderer.frozen_tool_paths(face, launcher)
        self.assertEqual(len(paths), len(set(paths)))
        for path in (Path(face.__file__).resolve(), launcher.resolve(),
                     Path(face.paint_graph.__file__).resolve()):
            self.assertIn(path, paths)
        module = source_renderer.default_face
        while module is not None:
            self.assertIn(Path(module.__file__).resolve(), paths)
            module = getattr(module, "prior", None)
        tree = ast.parse(Path(source_renderer.__file__).read_text())
        main = study.function_node(tree, "main")
        calls = [ast.unparse(node.func) for node in ast.walk(main) if isinstance(node, ast.Call)]
        self.assertIn("frozen_tool_paths", calls)

    def test_frozen_inputs_reject_selected_dependency_cycles(self):
        cyclic = ModuleType("cyclic_source_fixture")
        cyclic.__file__ = face.__file__
        cyclic.prior = cyclic
        with self.assertRaisesRegex(ValueError, "prior chain contains a cycle"):
            source_renderer.frozen_tool_paths(cyclic, source_renderer.__file__)

    def test_support_is_finite_and_mirror_safe_including_volume_centers(self):
        original, _ = study.fresh_design(face.PARENT_PROFILE)
        points = np.concatenate((sample_points(), np.asarray([center for center, _ in face.SUPPORT])))
        field = face.support_field(points, original.base_body_field)
        self.assertEqual(field.shape, (len(points),))
        self.assertTrue(np.all(np.isfinite(field)))
        np.testing.assert_allclose(field, face.support_field(reflected(points), original.base_body_field),
                                   atol=1e-13, rtol=0.)
        self.assertTrue(np.all(field <= original.base_body_field(points) + 1e-13))
        # Support is actual added facial volume, not a no-op on the old skull.
        self.assertLess(float(np.min(field - original.base_body_field(points))), -.01)

    def test_final_sculpt_is_finite_and_bilateral_at_socket_depths(self):
        design, _ = face.fresh_design()
        origin, across, normal, up = map(np.asarray, design.eye_surface_frame(1.))
        orbital = np.asarray([origin + across * x + normal * depth + up * z
                              for x in (-.18, -.105, 0., .105, .18)
                              for depth in (-.12, -.055, -.04, 0., .04)
                              for z in (-.16, 0., .15)])
        points = np.concatenate((sample_points(), orbital, reflected(orbital)))
        field = design.sculpt_body_field(points)
        self.assertTrue(np.all(np.isfinite(field)))
        np.testing.assert_allclose(field, design.sculpt_body_field(reflected(points)),
                                   atol=2e-12, rtol=0.)

    def test_aperture_canthi_and_unequal_arches_share_mirrored_landmarks(self):
        p = face.APERTURE
        for side in (-1., 1.):
            center_x = -side * p["nasal"]
            half_width = p["width"] * math.sqrt(1. - p["corner_rounding"])
            canthi = np.asarray((center_x - half_width, center_x + half_width))
            z = p["center_z"] - p["outer_drop"] * side * canthi
            np.testing.assert_allclose(face.aperture_field(canthi, z, side), 0., atol=1e-14)
            np.testing.assert_allclose(face.aperture_field(-canthi, z, -side), 0., atol=1e-14)
            center_z = p["center_z"] - p["outer_drop"] * side * center_x
            self.assertLess(float(face.aperture_field(center_x, center_z, side)), 0.)
            for direction in (-1., 1.):
                x = center_x + direction * (half_width + .001)
                self.assertGreater(float(face.aperture_field(x, p["center_z"] - p["outer_drop"] * side * x, side)), 0.)
            for direction, radius in ((1., p["upper"]), (-1., p["lower"])):
                arch = center_z + direction * radius * math.sqrt(1. - p["corner_rounding"] ** 2)
                self.assertAlmostEqual(float(face.aperture_field(center_x, arch, side)), 0., places=13)
        x, z = np.meshgrid(np.linspace(-.2, .2, 37), np.linspace(-.2, .2, 31))
        self.assertTrue(np.all(np.isfinite(face.aperture_field(x, z, 1.))))
        np.testing.assert_allclose(face.aperture_field(x, z, 1.), face.aperture_field(-x, z, -1.), atol=1e-14)
        self.assertGreater(p["upper"], p["lower"])

    def test_eye_registration_is_immutable_fresh_and_after_support(self):
        design, record = face.fresh_design()
        original, _ = study.fresh_design(face.PARENT_PROFILE)
        self.assertEqual(design.eye_surface_frame.cache_info().currsize, 0)
        frames = {}
        for side in (-1., 1.):
            frame = design.eye_surface_frame(side)
            frames[side] = frame
            self.assertIsInstance(frame, tuple)
            self.assertTrue(all(isinstance(vector, tuple) for vector in frame))
            with self.assertRaises(TypeError):
                frame[0][0] = 0.
            self.assertIs(design.eye_surface_frame(side), frame)
            origin = np.asarray(frame[0])
            self.assertLess(abs(float(design.base_body_field(origin))), 1e-9)
            self.assertAlmostEqual(float(design.base_body_field(origin)),
                                   float(face.support_field(origin, original.base_body_field)), places=13)
            # The old skull alone cannot seat this new support registration.
            self.assertGreater(abs(float(original.base_body_field(origin))), .005)
            basis = np.asarray(frame[1:])
            np.testing.assert_allclose(basis @ basis.T, np.eye(3), atol=1e-12)
        np.testing.assert_allclose(frames[-1.][0], reflected(frames[1.][0]), atol=1e-12)
        self.assertEqual(design.eye_surface_frame.cache_info().currsize, 2)
        fresh, _ = face.fresh_design()
        self.assertEqual(fresh.eye_surface_frame.cache_info().currsize, 0)
        self.assertIsNot(fresh.eye_surface_frame(1.), frames[1.])
        self.assertIs(record["old_orbital_sculpt_and_separate_hood_overlay_retired"], True)

    def test_pre_evaluated_registration_is_rejected_not_silently_reused(self):
        selected, parent = study.fresh_design(face.PARENT_PROFILE)
        selected.eye_surface_frame(1.)
        with patch.object(face.study, "fresh_design", return_value=(selected, parent)):
            with self.assertRaisesRegex(RuntimeError, "support must precede eye registration"):
                face.fresh_design()

    def test_scalar_paint_is_continuous_mirrored_and_masks_are_exclusive(self):
        design, _ = face.fresh_design()
        points = sample_points()
        paint = np.asarray([face.body_paint(point, design.eye_surface_frame, design.EYE_RADII)
                            for point in points])
        self.assertEqual(paint.shape, (len(points), 2, 4))
        self.assertTrue(np.all(np.isfinite(paint)))
        self.assertTrue(np.all((paint >= 0.) & (paint <= 1.)))
        np.testing.assert_array_equal(paint[:, :, 3], 1.)
        self.assertTrue(np.all(paint[:, 1, :3].sum(axis=1) <= 1. + 1e-12))
        mirror = np.asarray([face.body_paint(point, design.eye_surface_frame, design.EYE_RADII)
                             for point in reflected(points)])
        np.testing.assert_allclose(paint, mirror, atol=1e-12, rtol=0.)
        offset = np.asarray((1e-7, -1e-7, 1e-7))
        nearby = np.asarray([face.body_paint(point + offset, design.eye_surface_frame, design.EYE_RADII)
                             for point in points])
        self.assertLess(float(np.max(np.abs(paint - nearby))), 1e-3)

    def test_batch_uses_exact_scalar_program_and_bounded_attribute_batches(self):
        design, _ = face.fresh_design()
        program = face.full_paint_program({side: design.eye_surface_frame(side) for side in (-1., 1.)},
                                          design.EYE_RADII)
        points = sample_points()
        batch = face.evaluate_paint_batch(program, points)
        scalar = [face.paint_graph.evaluate_program(program, tuple(point)) for point in points]
        for key in ("color", "masks"):
            self.assertEqual(batch[key].shape, (len(points), 4))
            np.testing.assert_allclose(batch[key], [value[key] for value in scalar], atol=2e-13, rtol=0.)
        self.assertNotIn("LESS_THAN", {operation[1] for operation in program["operations"]})
        source = ast.parse(Path(face.__file__).read_text())
        attributes = study.function_node(source, "assign_body_attributes")
        loops = [node for node in ast.walk(attributes) if isinstance(node, ast.For)
                 and isinstance(node.iter, ast.Call) and isinstance(node.iter.func, ast.Name)
                 and node.iter.func.id == "range"]
        self.assertEqual(len(loops), 1)
        self.assertEqual(ast.literal_eval(loops[0].iter.args[2]), 8192)

    def test_batch_rejects_invalid_positions_ops_channels_and_mask_overlap(self):
        design, _ = face.fresh_design()
        program = face.full_paint_program({side: design.eye_surface_frame(side) for side in (-1., 1.)},
                                          design.EYE_RADII)
        for points in ((0., 0., 1.), [[0., 1.]], [[[0., 0., 1.]]],
                       [[math.nan, 0., 1.]], [[0., math.inf, 1.]]):
            with self.subTest(points=points):
                with self.assertRaisesRegex(ValueError, "finite Nx3"):
                    face.evaluate_paint_batch(program, points)
        invalid = {"inputs": ["x", "y", "z"], "operations": [("bad", "LESS_THAN", 0., 1.)],
                   "outputs": {"color": [0., 0., 0., 1.], "masks": [0., 0., 0., 1.]}}
        with self.assertRaisesRegex(ValueError, "Unsupported unified face paint operation"):
            face.evaluate_paint_batch(invalid, [[0., 0., 1.]])
        for outputs, error in (({"color": [1.01, 0., 0., 1.], "masks": [0., 0., 0., 1.]}, "invalid channel"),
                               ({"color": [0., 0., 0., 1.], "masks": [.6, .6, 0., 1.]}, "not exclusive")):
            with self.subTest(error=error):
                with self.assertRaisesRegex(RuntimeError, error):
                    face.evaluate_paint_batch({"inputs": ["x", "y", "z"], "operations": [], "outputs": outputs},
                                              [[0., 0., 1.]])

    def test_single_eye_is_closed_continuous_and_pupil_recedes_total_1_9_mm(self):
        radii = np.asarray(face.EYE_RADII)
        gaze = (.012, .020)
        for theta in (0., .10, face.PUPIL_ANGLE, face.IRIS_ANGLE, .8, math.pi):
            for phi in (0., .7, 2.1, math.tau):
                point, recess = face.eye_surface(theta, phi, gaze)
                with patch.multiple(face, IRIS_RECESS=0., PUPIL_RECESS=0.):
                    original, zero = face.eye_surface(theta, phi, gaze)
                self.assertEqual(zero, 0.)
                np.testing.assert_allclose(np.linalg.norm(np.asarray(point) - original), recess, atol=2e-17)
                self.assertAlmostEqual(float(np.sum((np.asarray(original) / radii) ** 2)), 1., places=13)
                self.assertLessEqual(float(np.sum((np.asarray(point) / radii) ** 2)), 1. + 1e-12)
                self.assertGreaterEqual(recess, 0.)
                self.assertLessEqual(recess, .0019)
                np.testing.assert_allclose(point, face.eye_surface(theta, phi + math.tau, gaze)[0], atol=1e-15)
                pigment = np.asarray(face.eye_pigment(theta, phi))
                self.assertTrue(np.all(np.isfinite(pigment)))
                self.assertTrue(np.all((pigment >= 0.) & (pigment <= 1.)))
        center, recess = face.eye_surface(0., 0., (0., 0.))
        self.assertAlmostEqual(recess, .0019, places=15)
        np.testing.assert_allclose(center, (0., face.EYE_RADII[1] - .0019, 0.), atol=1e-15)
        self.assertAlmostEqual(face.eye_surface(face.PUPIL_ANGLE, 0., gaze)[1], .0012, places=15)
        self.assertEqual(face.eye_surface(face.IRIS_ANGLE, 0., gaze)[1], 0.)
        for pole in (0., math.pi):
            np.testing.assert_allclose(face.eye_surface(pole, .4, gaze)[0], face.eye_surface(pole, 2.3, gaze)[0], atol=1e-15)
        for theta in (.10, face.PUPIL_ANGLE, face.IRIS_ANGLE, face.LIMBAL_ANGLE):
            a, b = face.eye_surface(theta - 1e-7, .7, gaze)[0], face.eye_surface(theta + 1e-7, .7, gaze)[0]
            self.assertLess(float(np.linalg.norm(np.asarray(a) - b)), 1e-6)
            self.assertLess(float(np.max(np.abs(np.asarray(face.eye_pigment(theta - 1e-7, .7))
                                               - face.eye_pigment(theta + 1e-7, .7)))), 1e-4)

    def test_renderer_scope_has_one_eye_mesh_per_side_and_export_stays_quarantined(self):
        old, _ = study.renderer_syntax(face.PARENT_PROFILE, base.RENDERER)
        new, _ = face.renderer_syntax(base.RENDERER)
        compile(new, str(base.RENDERER), "exec")
        functions = lambda tree: {node.name: ast.dump(node, include_attributes=False)
                                  for node in tree.body if isinstance(node, ast.FunctionDef)}
        before, after = functions(old), functions(new)
        self.assertEqual(set(before), set(after))
        self.assertEqual({name for name in before if before[name] != after[name]},
                         {"body_paint", "assign_body_materials", "add_eye_set", "add_bill"})
        eye_delegate = study.function_node(new, "add_eye_set")
        self.assertEqual(len(eye_delegate.body), 1)
        self.assertEqual(eye_delegate.body[0].value.func.id, "_juvenile_eyes")
        source = ast.parse(Path(face.__file__).read_text())
        eyes = study.function_node(source, "add_eye_surfaces")
        calls = [ast.unparse(node.func) for node in ast.walk(eyes) if isinstance(node, ast.Call)]
        self.assertEqual(calls.count("bpy.data.meshes.new"), 1)
        self.assertEqual(calls.count("bpy.data.objects.new"), 1)
        eye_loops = [node for node in ast.walk(eyes) if isinstance(node, ast.For)
                     and isinstance(node.target, ast.Name) and node.target.id == "side"]
        self.assertEqual(len(eye_loops), 1)
        self.assertEqual(ast.literal_eval(eye_loops[0].iter), (-1., 1.))
        self.assertNotIn("eye_paint_disc", calls)
        self.assertNotIn(face.PROFILE, provenance.PROFILES)
        record = face.source_only_declarations()
        self.assertIs(record["source_only"], True)
        for key in ("production_ready", "source_fidelity_approved", "geometry_approved",
                    "candidate_export_allowed", "runtime_rig_or_glb_created"):
            self.assertIs(record[key], False)
        with self.assertRaisesRegex(RuntimeError, "unknown study profile"):
            provenance.validate_record(record)


if __name__ == "__main__":
    unittest.main()
