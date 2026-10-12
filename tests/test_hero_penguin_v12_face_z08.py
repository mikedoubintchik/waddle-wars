"""Small Z08 scope/continuous-field guards, never rendered fidelity approval."""
from __future__ import annotations

import ast
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/art"))
import hero_penguin_v12_face_z08 as face
import hero_penguin_v12_source_study as study
import hero_penguin_v12_study_provenance as provenance
import render_hero_penguin_v12_source_study as base

try:
    import numpy as np
except ImportError:
    np = None


class FaceZ08ScopeTests(unittest.TestCase):
    def test_new_cohort_preserves_z06_eyes_bill_and_all_old_inputs(self):
        paths = [ROOT / "tools/art" / name for name in (*base.INPUT_TOOLS,
                 "hero_penguin_v12_face_z07.py", "render_hero_penguin_v12_face_z07.py")]
        hashes = {str(path): base.sha(path) for path in paths}
        old, _ = study.fresh_design(face.PARENT_PROFILE)
        new, record = face.fresh_design()
        changes = {key for key, value in study.constants(new).items()
                   if value != study.constants(old)[key]}
        self.assertEqual(changes, {"UPPER_FOLD_RADIAL_MARGIN", "UPPER_FOLD_BLEND"})
        self.assertEqual(new.IRIS_RADII, (.073, .093))
        self.assertEqual(new.EYE_CENTER_X, old.EYE_CENTER_X)
        self.assertEqual(new.EYE_BURY_DEPTH, old.EYE_BURY_DEPTH)
        self.assertEqual(new.BILL_UPPER_SECTIONS, old.BILL_UPPER_SECTIONS)
        self.assertEqual(new.BILL_LOWER_SECTIONS, old.BILL_LOWER_SECTIONS)
        self.assertEqual(new.eye_surface_frame.cache_info().currsize, 0)
        self.assertEqual(record["shape_parameters"], face.SHAPE)
        self.assertEqual(hashes, {str(path): base.sha(path) for path in paths})

    def test_renderer_only_changes_five_declared_face_paint_expressions(self):
        prior, _ = study.renderer_syntax(face.PARENT_PROFILE, base.RENDERER)
        tree, record = face.renderer_syntax(base.RENDERER)
        compile(tree, str(base.RENDERER), "exec")
        self.assertEqual(len(record["z08_renderer_expression_changes"]), 5)
        paint = study.function_node(tree, "body_paint")
        for name, old, new in face.PAINT_CHANGES:
            value = study.assignment(paint, name)
            self.assertEqual(ast.dump(value.value), ast.dump(ast.parse(new, mode="eval").body))
            value.value = ast.parse(old, mode="eval").body
        self.assertEqual(study.ast_digest(tree), study.ast_digest(prior))
        self.assertIn("* (1.0 - face)", face.PAINT_CHANGES[-1][2])

    def test_unknown_source_only_profile_cannot_be_exported_as_z06(self):
        record = face.source_only_declarations()
        self.assertEqual(record["study_profile"], "juvenile-cheeks-z08")
        self.assertNotIn(face.PROFILE, study.PROFILE_OVERRIDES)
        self.assertNotIn(face.PROFILE, provenance.PROFILES)
        for flag in ("production_ready", "source_fidelity_approved", "geometry_approved",
                     "candidate_export_allowed", "runtime_rig_or_glb_created"):
            self.assertIs(record[flag], False)
        self.assertGreater(record["field_warp_minimum_jacobian_bound"], .75)


@unittest.skipIf(np is None, "NumPy required; use Blender's standalone Python, not Blender engine")
class FaceZ08FieldTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.old, _ = study.fresh_design(face.PARENT_PROFILE)
        cls.new, _ = face.fresh_design()

    @staticmethod
    def front_y(design, x, z):
        low, high = -.70, -.10
        for _ in range(30):
            middle = (low + high) * .5
            if float(design.sculpt_body_field((x, middle, z))) > 0.:
                low = middle
            else:
                high = middle
        return (low + high) * .5

    def test_actual_cheek_surface_moves_forward_20_to_30_mm_and_waist_inward(self):
        for side in (-1., 1.):
            for z in (1.30, 1.315, 1.34):
                forward = self.front_y(self.old, side * .205, z) - self.front_y(self.new, side * .205, z)
                self.assertGreater(forward, .020)
                self.assertLess(forward, .030)
        waist = self.front_y(self.new, 0., 1.115) - self.front_y(self.old, 0., 1.115)
        self.assertAlmostEqual(waist, .016, places=7)

    def test_eye_frame_and_unmodified_body_regions_are_exactly_preserved(self):
        for side in (-1., 1.):
            np.testing.assert_array_equal(self.new.eye_surface_frame(side), self.old.eye_surface_frame(side))
            np.testing.assert_array_equal(self.new.eye_gaze_center(side), self.old.eye_gaze_center(side))
        points = np.asarray([[0., .01, 1.802], [.1, -.4, .80], [.2, .25, 1.32], [0., -.2, .09]])
        np.testing.assert_array_equal(face.warp_points(points), points)
        np.testing.assert_array_equal(self.new.base_body_field(points), self.old.base_body_field(points))
        np.testing.assert_array_equal(self.new.sculpt_body_field(points), self.old.sculpt_body_field(points))

    def test_compact_warp_is_symmetric_bounded_monotonic_and_zero_slope_at_bounds(self):
        points = np.asarray([(x, y, z) for x in (-.43, -.205, 0., .205, .43)
                             for y in np.linspace(-.4, 0., 21)
                             for z in (.95, 1.115, 1.30, 1.315, 1.35, 1.405, 1.5)])
        warped = face.warp_points(points)
        shift = warped[:, 1] - points[:, 1]
        self.assertTrue(np.all(shift >= -.016 - 1e-12))
        self.assertTrue(np.all(shift <= .033 + 1e-12))
        mirrored = points * (-1., 1., 1.)
        np.testing.assert_allclose(face.warp_points(mirrored), warped * (-1., 1., 1.), atol=1e-15)
        epsilon = np.asarray((0., 1e-6, 0.))
        slope = (face.warp_points(points + epsilon)[:, 1] -
                 face.warp_points(points - epsilon)[:, 1]) / 2e-6
        self.assertGreater(float(slope.min()), .7524)
        for edge in (.960, 1.405):
            points = np.asarray([[.205, -.4, edge + offset] for offset in (-1e-6, 0., 1e-6)])
            shift = face.warp_points(points) - points
            self.assertLess(float(np.abs(shift).max()), 1e-10)


if __name__ == "__main__":
    unittest.main()
