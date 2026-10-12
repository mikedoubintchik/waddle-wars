"""Small source-cohort guards; no rendered fidelity or rig-fit approval."""
from __future__ import annotations

import ast
import math
from pathlib import Path
import sys
import unittest

try:
    import numpy as np
except ImportError:
    np = None

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/art"))
import hero_penguin_v12_source_study as study
import render_hero_penguin_v12_source_study as launcher


class JuvenileSculptTests(unittest.TestCase):
    def test_complete_cohort_compiles_without_editing_baseline_inputs(self):
        paths = (study.DESIGN_PATH, launcher.RENDERER)
        before = {path: path.read_bytes() for path in paths}
        selected, record = study.fresh_design(study.JUVENILE_PROFILE)
        syntax, renderer = study.renderer_syntax(study.JUVENILE_PROFILE, launcher.RENDERER)
        compile(syntax, str(launcher.RENDERER), "exec")
        self.assertEqual(before, {path: path.read_bytes() for path in paths})
        self.assertTrue({"TORSO_RADII", "BODY_VOLUMES", "CHEEK_VOLUMES", "EYE_CENTER_Z",
                         "EYE_RADII", "EYE_GAZE_TARGET", "BILL_UPPER_SECTIONS",
                         "BILL_LOWER_SECTIONS", "WING_HALF_WIDTH"}
                        <= set(record["parameter_overrides"]))
        self.assertEqual(renderer["renderer_added_imports"], [study.JUVENILE_IMPORT])
        self.assertFalse(record["production_ready"])
        self.assertFalse(record["source_fidelity_approved"])
        self.assertFalse(record["runtime_rig_or_glb_created"])
        self.assertEqual(selected.eye_surface_frame.cache_info().currsize, 0)

    def test_larger_aperture_does_not_use_a_protruding_globe(self):
        prior, _ = study.fresh_design("orbital-saddle-z04")
        selected, _ = study.fresh_design(study.JUVENILE_PROFILE)
        old_aperture = prior.eye_tangent_aperture_radii()
        aperture = selected.eye_tangent_aperture_radii()
        self.assertGreater(aperture[0], old_aperture[0] * 1.25)
        self.assertGreater(aperture[1], old_aperture[1] * 1.10)
        self.assertLessEqual(selected.EYE_RADII[1] - selected.EYE_BURY_DEPTH, .027)
        self.assertLess(selected.EYE_CENTER_Z, prior.EYE_CENTER_Z - .06)
        self.assertLess(selected.EYE_GAZE_TARGET[2], prior.EYE_GAZE_TARGET[2])

    def test_height_envelope_and_feet_remain_future_export_constraints(self):
        baseline, _ = study.fresh_design()
        selected, record = study.fresh_design(study.JUVENILE_PROFILE)
        crown = lambda design: max(center[2] + radii[2] for center, radii in design.BODY_VOLUMES)
        self.assertLess(abs(crown(selected) - crown(baseline)), .005)
        for name in ("TORSO_CENTER", "FOOT_CENTER_X", "FOOT_CENTER_Y", "FOOT_CENTER_Z", "FOOT_RADII"):
            self.assertEqual(getattr(selected, name), getattr(baseline, name))
        self.assertIn("require separate export review", record["future_export_constraints"])

    def test_orbital_paint_opens_into_cheek_instead_of_a_ring(self):
        frame = lambda side: ((side * .215, -.35, 1.48), (1., 0., 0.), (0., -1., 0.), (0., 0., 1.))
        self.assertLess(study.juvenile_orbit_field((.300, -.35, 1.35), frame), 1.0)
        self.assertGreater(study.juvenile_orbit_field((.355, -.35, 1.61), frame), 1.0)
        self.assertGreater(study.juvenile_orbit_field((.215, .35, 1.48), frame), 1.0)
        syntax, _ = study.renderer_syntax(study.JUVENILE_PROFILE, launcher.RENDERER)
        paint = study.function_node(syntax, "body_paint")
        orbit = study.assignment(paint, "orbit")
        self.assertEqual(ast.unparse(orbit.value), study.JUVENILE_ORBIT_EXPRESSION)

    def test_socket_successor_is_opt_in_and_declares_its_scoped_changes(self):
        prior, prior_record = study.fresh_design(study.JUVENILE_PROFILE)
        selected, record = study.fresh_design(study.SOCKET_PROFILE)
        changes = {name for name, value in study.constants(selected).items()
                   if value != study.constants(prior)[name]}
        self.assertEqual(changes, {"EYE_GAZE_TARGET"})
        self.assertEqual(selected.EYE_GAZE_TARGET, (0.0, -3.5, 2.4))
        self.assertNotIn("design_added_imports", prior_record)
        self.assertNotIn("socket_relief_recipe", prior_record)
        self.assertEqual(record["design_added_imports"], [study.SOCKET_IMPORT])
        self.assertEqual(record["socket_relief_recipe"], study.SOCKET_RELIEF_RECIPE)
        self.assertFalse(record["source_fidelity_approved"])
        self.assertEqual(record["design_expression_overrides"][-1]["anchor"],
                         "sculpt_body_field.base")
        syntax, _ = study.renderer_syntax(study.SOCKET_PROFILE, launcher.RENDERER)
        compile(syntax, str(launcher.RENDERER), "exec")


@unittest.skipIf(np is None, "NumPy required for actual field guards; use Blender's standalone Python")
class JuvenileSocketFieldTests(unittest.TestCase):
    """Small numerical shape guards, not a replacement for three-view review."""

    @classmethod
    def setUpClass(cls):
        cls.prior, _ = study.fresh_design(study.JUVENILE_PROFILE)
        cls.selected, _ = study.fresh_design(study.SOCKET_PROFILE)

    @staticmethod
    def iris_perimeter(design, side):
        # Same geodesic projection as eye_paint_disc, without importing bpy.
        origin, across, normal, up = map(np.asarray, design.eye_surface_frame(side))
        cx, cz = design.eye_gaze_center(side)
        radii = np.asarray(design.EYE_RADII)
        center = np.asarray((cx, radii[1] * math.sqrt(
            1.0 - (cx / radii[0]) ** 2 - (cz / radii[2]) ** 2), cz))
        patch_normal = center / radii ** 2
        patch_normal /= np.linalg.norm(patch_normal)
        patch_across = np.cross(patch_normal, (0., 0., 1.))
        patch_across /= np.linalg.norm(patch_across)
        patch_up = np.cross(patch_across, patch_normal)
        points = []
        for angle in np.linspace(0., math.tau, 128, endpoint=False):
            tangent = (center + patch_across * design.IRIS_RADII[0] * math.cos(angle)
                       + patch_up * design.IRIS_RADII[1] * math.sin(angle))
            x, y, z = design.project_eye_patch(tangent, .0016)
            points.append(origin + across * x + normal * (y - design.EYE_BURY_DEPTH) + up * z)
        return np.asarray(points)

    @staticmethod
    def aperture_boundary(design, angle):
        origin, across, normal, up = map(np.asarray, design.eye_surface_frame(1.))
        radius_x, radius_z = design.eye_tangent_aperture_radii()

        def sample(fraction):
            x = radius_x * fraction * math.cos(angle)
            z = radius_z * fraction * math.sin(angle)
            depth = (-design.EYE_BURY_DEPTH + design.EYE_RADII[1] * math.sqrt(max(
                0., 1. - (x / design.EYE_RADII[0]) ** 2 - (z / design.EYE_RADII[2]) ** 2)))
            return origin + across * x + normal * depth + up * z, z

        low, high = 0., 1.48
        for _ in range(40):
            middle = (low + high) * .5
            point, _ = sample(middle)
            if float(design.sculpt_body_field(point)) > 0.:
                low = middle
            else:
                high = middle
        return sample((low + high) * .5)[1]

    def test_local_gaze_and_actual_iris_perimeters_clear_lower_cheek(self):
        for side in (-1., 1.):
            self.assertLess(self.prior.eye_gaze_center(side)[1], -.045)
            self.assertTrue(0. <= self.selected.eye_gaze_center(side)[1] <= .008)
            old = self.prior.sculpt_body_field(self.iris_perimeter(self.prior, side))
            new = self.selected.sculpt_body_field(self.iris_perimeter(self.selected, side))
            self.assertGreater(np.count_nonzero(old < -.001), 40)
            self.assertGreater(float(new.min()), 0.)

    def test_lower_socket_opens_without_moving_upper_aperture_or_globe(self):
        self.assertEqual(self.prior.EYE_RADII, self.selected.EYE_RADII)
        self.assertEqual(self.prior.EYE_BURY_DEPTH, self.selected.EYE_BURY_DEPTH)
        for angle in (math.pi * 1.5, math.pi * 5. / 3.):
            old = self.aperture_boundary(self.prior, angle)
            new = self.aperture_boundary(self.selected, angle)
            self.assertLess(new, old - .020)
            self.assertGreater(new, -.115)
        self.assertAlmostEqual(self.aperture_boundary(self.prior, math.pi * .5),
                               self.aperture_boundary(self.selected, math.pi * .5), places=10)

    def test_relief_is_bounded_continuous_and_absent_above_or_behind_eye(self):
        frame = lambda side: ((side * .215, 0., 0.), (1., 0., 0.),
                              (0., -1., 0.), (0., 0., 1.))
        points = np.asarray([(x, depth, z)
                             for x in np.linspace(-.6, .6, 25)
                             for depth in np.linspace(-.1, .1, 13)
                             for z in np.linspace(-.25, .25, 25)])
        amount = study.juvenile_socket_relief(points, np.zeros(len(points)), frame)
        self.assertGreaterEqual(float(amount.min()), 0.)
        self.assertLessEqual(float(amount.max()), .020)
        self.assertTrue(np.all(amount[points[:, 2] >= .030] == 0.))
        self.assertTrue(np.all(amount[points[:, 1] >= .070] == 0.))
        # Squared compact kernel has no ridge at its outer boundary.
        boundary = np.asarray((.215 + .025 + .150, -.02, -.055))
        samples = np.asarray([boundary + (step, 0., 0.) for step in (-1e-6, 0., 1e-6)])
        edge = study.juvenile_socket_relief(samples, np.zeros(3), frame)
        self.assertLess(float(edge.max()), 1e-10)
        self.assertEqual(float(edge[-1]), 0.)


if __name__ == "__main__":
    unittest.main()
