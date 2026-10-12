"""Z11 construction/scope guards. Passing these never approves appearance."""
from __future__ import annotations

import ast
import math
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/art"))
import hero_penguin_v12_face_z11 as face
import hero_penguin_v12_source_study as study
import hero_penguin_v12_study_provenance as provenance
import render_hero_penguin_v12_source_study as base

try:
    import numpy as np
except ImportError:
    np = None


class FaceZ11ScopeTests(unittest.TestCase):
    def test_baseline_and_all_z10_constants_materials_are_unchanged(self):
        paths = [ROOT / "tools/art" / name for name in (*base.INPUT_TOOLS,
                 "hero_penguin_v12_face_z09.py", "hero_penguin_v12_face_z10.py",
                 "render_hero_penguin_v12_face_z10.py")]
        before = {str(path): base.sha(path) for path in paths}
        old, _ = face.prior.fresh_design()
        new, _ = face.fresh_design()
        self.assertEqual(study.constants(new), study.constants(old))
        self.assertIs(face.apply_material_changes, face.prior.apply_material_changes)
        self.assertIs(face.chest_mask, face.prior.chest_mask)
        self.assertIs(face.warp_points, face.prior.warp_points)
        self.assertEqual(before, {str(path): base.sha(path) for path in paths})

    def test_only_renderer_paint_delegate_changes(self):
        old, _ = face.prior.renderer_syntax(base.RENDERER)
        new, _ = face.renderer_syntax(base.RENDERER)
        compile(new, str(base.RENDERER), "exec")
        functions = lambda tree: {n.name: ast.dump(n, include_attributes=False)
                                  for n in tree.body if isinstance(n, ast.FunctionDef)}
        a, b = functions(old), functions(new)
        self.assertEqual(set(a), set(b))
        self.assertEqual({name for name in a if a[name] != b[name]}, {"body_paint"})

    def test_upper_tube_not_reintroduced_and_no_export_approval(self):
        tree = ast.parse(Path(face.__file__).read_text())
        sculpt = study.function_node(tree, "sculpt_face")
        self.assertNotIn('FOLDS["upper"]', ast.get_source_segment(Path(face.__file__).read_text(), sculpt))
        self.assertIn('FOLDS["lower"]', ast.get_source_segment(Path(face.__file__).read_text(), sculpt))
        self.assertNotIn(face.PROFILE, provenance.PROFILES)
        record = face.source_only_declarations()
        for key in ("production_ready", "source_fidelity_approved", "geometry_approved",
                    "candidate_export_allowed", "runtime_rig_or_glb_created"):
            self.assertIs(record[key], False)


@unittest.skipIf(np is None, "NumPy required for source construction guards")
class FaceZ11ConstructionTests(unittest.TestCase):
    RADII = (.147, .100, .176)

    def test_upper_edge_is_actual_existing_aperture_not_second_arch(self):
        p = face.prior.prior.ORBIT
        for side in (-1., 1.):
            x = np.linspace(-.095, .095, 31)
            z = face.upper_aperture_z(x, side)
            np.testing.assert_allclose(face.prior.prior.opening_field(x, z, side), 0., atol=1e-14)
            np.testing.assert_allclose(z, face.upper_aperture_z(-x, -side), atol=1e-14)

    def test_lid_returns_flush_with_zero_slope_and_tapers_only_outside_globe(self):
        x = np.array([-.090, 0., .090])
        edge, outer, _, endpoint, _ = face.lid_coordinates(x, np.zeros(3), 1., self.RADII)
        self.assertTrue(np.all(endpoint == 1.))
        self.assertTrue(np.all(outer - edge >= .045 - 1e-14))
        for z in (outer, outer + .001):
            np.testing.assert_array_equal(face.lid_lift(x, z, 1., self.RADII, .074,
                                                       np.full(3, -.03), np.full(3, -.03)), 0.)
        epsilon = 1e-5
        near = face.lid_lift(x, outer - epsilon, 1., self.RADII, .074, np.full(3, -.03), np.full(3, -.03))
        self.assertLess(float(np.max(np.abs(near))) / epsilon, 1e-4)
        _, _, _, ends, _ = face.lid_coordinates(np.array([-.167, .167]), np.zeros(2), 1., self.RADII)
        np.testing.assert_allclose(ends, 0., atol=1e-14)

    def test_globe_anchoring_and_paint_below_face_preserved(self):
        x = np.array([-.060, 0., .060])
        edge = face.upper_aperture_z(x, 1.)
        head = np.full(3, -.030)
        lift = face.lid_lift(x, edge, 1., self.RADII, .074, head, head)
        globe, valid = face.globe_front_depth(x, edge, self.RADII, .074)
        self.assertTrue(np.all(valid))
        clearance = head + lift - globe
        self.assertTrue(np.all(clearance >= .0025 - 1e-12))
        self.assertTrue(np.all(clearance <= .0028))
        design, _ = face.fresh_design()
        old, _ = face.prior.fresh_design()
        for side in (-1., 1.):
            np.testing.assert_array_equal(design.eye_surface_frame(side), old.eye_surface_frame(side))
            np.testing.assert_array_equal(design.eye_gaze_center(side), old.eye_gaze_center(side))
        for point in ((0., -.3, .70), (.18, -.3, .20), (0., -.35, 1.15)):
            self.assertEqual(face.body_paint(point, design.eye_surface_frame, design.EYE_RADII),
                             face.prior.body_paint(point, old.eye_surface_frame))

    def test_actual_unchanged_iris_perimeter_is_not_covered_by_new_lid(self):
        design, _ = face.fresh_design()
        for side in (-1., 1.):
            origin, across, normal, up = map(np.asarray, design.eye_surface_frame(side))
            cx, cz = design.eye_gaze_center(side)
            radii = np.asarray(design.EYE_RADII)
            center = np.asarray((cx, radii[1] * math.sqrt(1. - (cx / radii[0]) ** 2 - (cz / radii[2]) ** 2), cz))
            n = center / radii ** 2
            n /= np.linalg.norm(n)
            a = np.cross(n, (0., 0., 1.))
            a /= np.linalg.norm(a)
            u = np.cross(a, n)
            points = []
            for angle in np.linspace(0., math.tau, 64, endpoint=False):
                tangent = center + a * design.IRIS_RADII[0] * math.cos(angle) + u * design.IRIS_RADII[1] * math.sin(angle)
                x, y, z = design.project_eye_patch(tangent, .0016)
                points.append(origin + across * x + normal * (y - design.EYE_BURY_DEPTH) + up * z)
            field = design.sculpt_body_field(np.asarray(points))
            self.assertTrue(np.all(np.isfinite(field)))
            self.assertGreater(float(field.min()), .001)


if __name__ == "__main__":
    unittest.main()
