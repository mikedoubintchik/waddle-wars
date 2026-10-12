"""Modest Z10 construction/scope tests; actual appearance remains unapproved."""
from __future__ import annotations

import ast
import math
from pathlib import Path
import sys
from types import ModuleType
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/art"))
import hero_penguin_v12_face_z10 as face
import hero_penguin_v12_source_study as study
import hero_penguin_v12_study_provenance as provenance
import render_hero_penguin_v12_source_study as base

try:
    import numpy as np
except ImportError:
    np = None


class FaceZ10ScopeTests(unittest.TestCase):
    def test_z09_constants_materials_frozen_files_and_cohort_are_preserved(self):
        paths = [ROOT / "tools/art" / name for name in (*base.INPUT_TOOLS,
                 "hero_penguin_v12_face_z07.py", "hero_penguin_v12_face_z08.py",
                 "hero_penguin_v12_face_z09.py", "render_hero_penguin_v12_face_z09.py")]
        before = {str(path): base.sha(path) for path in paths}
        old, _ = face.prior.fresh_design()
        with face.installed_design() as (new, _):
            self.assertEqual(study.constants(new), study.constants(old))
            self.assertIs(face.apply_material_changes, face.prior.apply_material_changes)
            renderer = ModuleType("z10_fake_renderer")
            for name, value in study.constants(new).items():
                setattr(renderer, name, value)
            for name in study.SHARED_FUNCTIONS:
                setattr(renderer, name, getattr(new, name))
            study.require_renderer_cohort(renderer, new)
        self.assertEqual(before, {str(path): base.sha(path) for path in paths})

    def test_renderer_preserves_every_function_except_paint_delegate(self):
        old, _ = face.prior.renderer_syntax(base.RENDERER)
        tree, _ = face.renderer_syntax(base.RENDERER)
        compile(tree, str(base.RENDERER), "exec")
        functions = lambda t: {n.name: ast.dump(n, include_attributes=False)
                               for n in t.body if isinstance(n, ast.FunctionDef)}
        old_functions, new_functions = functions(old), functions(tree)
        self.assertEqual(set(old_functions), set(new_functions))
        self.assertEqual({name for name in old_functions if old_functions[name] != new_functions[name]}, {"body_paint"})

    def test_bib_is_broad_and_round_at_visible_lower_belly(self):
        self.assertGreater(face.chest_mask((.23, -.25, .18)), .9)
        self.assertGreater(face.chest_mask((.15, -.25, .14)), .9)
        self.assertEqual(face.chest_mask((.23, -.25, .18)), face.chest_mask((-.23, -.25, .18)))
        self.assertEqual(face.chest_mask((.10, .25, .30)), 0.)
        self.assertLess(face.chest_mask((.47, -.25, .35)), .2)

    def test_separate_open_arches_and_no_export_or_fidelity_approval(self):
        self.assertGreater(face.FOLDS["upper"]["height_radius"], face.FOLDS["lower"]["height_radius"])
        self.assertGreater(face.FOLDS["upper"]["width"], face.FOLDS["lower"]["width"])
        self.assertGreater(face.FOLDS["upper"]["center_z"], 0.)
        self.assertLess(face.FOLDS["lower"]["center_z"], 0.)
        tree = ast.parse(Path(face.__file__).read_text())
        sculpt = study.function_node(tree, "sculpt_face")
        self.assertNotIn("eye_radii", {n.id for n in ast.walk(sculpt) if isinstance(n, ast.Name)})
        record = face.source_only_declarations()
        self.assertNotIn(face.PROFILE, provenance.PROFILES)
        for key in ("production_ready", "source_fidelity_approved", "geometry_approved",
                    "candidate_export_allowed", "runtime_rig_or_glb_created"):
            self.assertIs(record[key], False)


@unittest.skipIf(np is None, "NumPy required; standalone bundled Python suffices")
class FaceZ10FieldTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.old, _ = face.prior.fresh_design()
        cls.new, _ = face.fresh_design()

    def test_large_iris_and_eye_frame_remain_clear(self):
        d = self.new
        for side in (-1., 1.):
            np.testing.assert_array_equal(d.eye_surface_frame(side), self.old.eye_surface_frame(side))
            np.testing.assert_array_equal(d.eye_gaze_center(side), self.old.eye_gaze_center(side))
            origin, across, normal, up = map(np.asarray, d.eye_surface_frame(side))
            cx, cz = d.eye_gaze_center(side)
            radii = np.asarray(d.EYE_RADII)
            center = np.asarray((cx, radii[1] * math.sqrt(1. - (cx / radii[0]) ** 2 - (cz / radii[2]) ** 2), cz))
            n = center / radii ** 2; n /= np.linalg.norm(n)
            a = np.cross(n, (0., 0., 1.)); a /= np.linalg.norm(a)
            u = np.cross(a, n)
            points = []
            for angle in np.linspace(0., math.tau, 128, endpoint=False):
                tangent = center + a * d.IRIS_RADII[0] * math.cos(angle) + u * d.IRIS_RADII[1] * math.sin(angle)
                x, y, z = d.project_eye_patch(tangent, .0016)
                points.append(origin + across * x + normal * (y - d.EYE_BURY_DEPTH) + up * z)
            values = d.sculpt_body_field(np.asarray(points))
            self.assertTrue(np.all(np.isfinite(values)))
            self.assertGreater(float(values.min()), .001)

    def test_throat_warp_is_stronger_bounded_symmetric_and_keeps_crown_feet(self):
        self.assertEqual(face.THROAT_INWARD_M, .065)
        center = np.asarray((0., -.40, 1.125))
        self.assertAlmostEqual(float(face.warp_points(center)[1] - center[1]), -.065, places=12)
        points = np.asarray([(x, y, z) for x in (-.4, -.2, 0., .2, .4)
                             for y in np.linspace(-.4, 0., 11) for z in (.09, .8, 1.125, 1.335, 1.415, 1.8)])
        moved = face.warp_points(points)
        delta = moved[:, 1] - points[:, 1]
        self.assertTrue(np.all(delta >= -.065 - 1e-12))
        self.assertTrue(np.all(delta <= .0435 + 1e-12))
        np.testing.assert_allclose(face.warp_points(points * (-1., 1., 1.)), moved * (-1., 1., 1.), atol=1e-15)
        epsilon = np.asarray((0., 1e-6, 0.))
        derivative = (face.warp_points(points + epsilon)[:, 1] - face.warp_points(points - epsilon)[:, 1]) / 2e-6
        self.assertGreater(float(derivative.min()), .67)
        outside = (points[:, 2] < .95) | (points[:, 2] > 1.42)
        np.testing.assert_array_equal(moved[outside], points[outside])


if __name__ == "__main__":
    unittest.main()
