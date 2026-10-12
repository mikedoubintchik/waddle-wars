"""Scope/shape checks only; no appearance or export approval."""
import ast
import math
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/art"))
import hero_penguin_v12_face_z14 as face
import hero_penguin_v12_face_z11 as old_shape
import hero_penguin_v12_study_provenance as provenance
import render_hero_penguin_v12_source_study as base
import numpy as np


class FaceZ14Tests(unittest.TestCase):
    def test_changes_only_bill_constants_and_local_front_throat(self):
        old, _ = old_shape.fresh_design()
        new, _ = face.fresh_design()
        a, b = face.study.constants(old), face.study.constants(new)
        self.assertEqual(set(a), set(b))
        self.assertEqual({key for key in a if a[key] != b[key]}, {"BILL_UPPER_SECTIONS", "BILL_LOWER_SECTIONS"})
        points = np.array([(0., -.35, .70), (0., -.35, 1.5), (.50, -.35, 1.125), (0., .30, 1.125)])
        np.testing.assert_allclose(new.base_body_field(points), old.base_body_field(points), atol=1e-14)
        neck = np.array([(0., -.30, 1.125), (.1, -.32, 1.16)])
        self.assertTrue(np.all(new.base_body_field(neck) < old.base_body_field(neck)))
        for side in (-1., 1.):
            np.testing.assert_allclose(new.eye_surface_frame(side), old.eye_surface_frame(side), atol=1e-13)
            np.testing.assert_allclose(new.eye_gaze_center(side), old.eye_gaze_center(side), atol=1e-13)

    def test_bill_is_symmetric_with_raised_mouth_corners(self):
        for section in face.BILL_UPPER:
            y, width, height, seam = section
            for angle in np.linspace(0., math.tau, 49):
                c, s = math.cos(angle), math.sin(angle)
                for lobe in ("upper", "lower", ""):
                    self.assertAlmostEqual(face.bill_height(*section, c, s, lobe),
                                           face.bill_height(*section, -c, s, lobe), places=13)
            self.assertGreaterEqual(face.bill_height(*section, 1., 0.) - seam, 0.)
        self.assertGreater(face.bill_smile(-.424, .150, 1.), .035)
        self.assertLess(max(row[2] for row in face.BILL_UPPER), max(row[2] for row in face.anatomy.BILL_UPPER))
        self.assertGreater(max(row[1] for row in face.BILL_UPPER), max(row[1] for row in face.anatomy.BILL_UPPER))

    def test_renderer_changes_only_nostril_registration(self):
        old, _ = face.prior.renderer_syntax(base.RENDERER)
        new, _ = face.renderer_syntax(base.RENDERER)
        compile(new, str(base.RENDERER), "exec")
        functions = lambda tree: {n.name: ast.dump(n) for n in tree.body if isinstance(n, ast.FunctionDef)}
        a, b = functions(old), functions(new)
        self.assertEqual({key for key in a if a[key] != b[key]}, {"add_bill"})
        left, right = face.nostril_center(-1.), face.nostril_center(1.)
        self.assertEqual(left[0], -right[0])
        self.assertEqual(left[1:], right[1:])
        self.assertLess(right[2], 1.422)

    def test_materials_and_approval_stay_unchanged(self):
        self.assertIs(face.install_continuous_paint, face.prior.install_continuous_paint)
        self.assertIs(face.apply_material_changes, face.prior.apply_material_changes)
        self.assertNotIn(face.PROFILE, provenance.PROFILES)
        for key in ("production_ready", "source_fidelity_approved", "geometry_approved",
                    "candidate_export_allowed", "runtime_rig_or_glb_created"):
            self.assertIs(face.source_only_declarations()[key], False)


if __name__ == "__main__":
    unittest.main()
