"""Bounded construction checks for Z09, not a visual-fidelity approval gate."""
from __future__ import annotations

import ast
import math
from pathlib import Path
import sys
from types import ModuleType, SimpleNamespace
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/art"))
import hero_penguin_v12_face_z09 as face
import hero_penguin_v12_source_study as study
import hero_penguin_v12_study_provenance as provenance
import render_hero_penguin_v12_source_study as base

try:
    import numpy as np
except ImportError:
    np = None


class FaceZ09ScopeTests(unittest.TestCase):
    def test_frozen_inputs_and_z06_eye_constants_preserved(self):
        names = (*base.INPUT_TOOLS, "hero_penguin_v12_face_z07.py", "render_hero_penguin_v12_face_z07.py",
                 "hero_penguin_v12_face_z08.py", "render_hero_penguin_v12_face_z08.py")
        paths = [ROOT / "tools/art" / name for name in names]
        before = {str(path): base.sha(path) for path in paths}
        old, _ = study.fresh_design(face.PARENT_PROFILE)
        new, record = face.fresh_design()
        changed = {name for name, value in study.constants(new).items() if value != study.constants(old)[name]}
        self.assertEqual(changed, {"BILL_UPPER_SECTIONS", "BILL_LOWER_SECTIONS"})
        self.assertEqual(new.IRIS_RADII, (.073, .093))
        self.assertEqual(new.EYE_BURY_DEPTH, old.EYE_BURY_DEPTH)
        self.assertEqual(new.EYE_RADII, old.EYE_RADII)
        self.assertEqual(new.eye_surface_frame.cache_info().currsize, 0)
        self.assertIn("sculpt_body_field", record["z09_function_replacements"])
        self.assertEqual(before, {str(path): base.sha(path) for path in paths})

    def test_new_renderer_only_changes_face_eye_and_bill_functions(self):
        old, _ = study.renderer_syntax(face.PARENT_PROFILE, base.RENDERER)
        new, record = face.renderer_syntax(base.RENDERER)
        compile(new, str(base.RENDERER), "exec")
        functions = lambda tree: {node.name: ast.dump(node, include_attributes=False)
                                  for node in tree.body if isinstance(node, ast.FunctionDef)}
        old_functions, new_functions = functions(old), functions(new)
        self.assertEqual(set(old_functions), set(new_functions))
        self.assertEqual({name for name in old_functions if old_functions[name] != new_functions[name]},
                         {"body_paint", "add_eye_set", "add_bill"})
        self.assertEqual(len(record["z09_renderer_literal_changes"]), 5)
        self.assertEqual(record["z09_body_paint_helper"], "hero_penguin_v12_face_z09.body_paint")

    def test_replacement_functions_share_fresh_design_cohort(self):
        prior = sys.modules.get(study.DESIGN_MODULE)
        with face.installed_design() as (selected, _):
            renderer = ModuleType("z09_fake_renderer")
            for name, value in study.constants(selected).items():
                setattr(renderer, name, value)
            for name in study.SHARED_FUNCTIONS:
                function = getattr(selected, name)
                self.assertIs(getattr(function, "__wrapped__", function).__globals__, selected.__dict__)
                setattr(renderer, name, function)
            study.require_renderer_cohort(renderer, selected)
        self.assertIs(sys.modules.get(study.DESIGN_MODULE), prior)

    def test_bill_has_forward_dome_shaped_corners_and_bounded_lobes(self):
        self.assertLess(max(row[1] for row in face.BILL_UPPER), .147)
        for rows, lobe in ((face.BILL_UPPER, "upper"), (face.BILL_LOWER, "lower")):
            self.assertTrue(all(rows[index][0] > rows[index + 1][0] for index in range(len(rows) - 1)))
            for y, width, height, seam in rows:
                self.assertGreater(width, 0.)
                self.assertGreater(height, 0.)
                for index in range(64):
                    angle = math.tau * index / 64
                    z = face.bill_height(y, width, height, seam, math.cos(angle), math.sin(angle), lobe)
                    self.assertTrue(math.isfinite(z) and 1.25 < z < 1.45)
        roofs = [face.bill_height(*row, 0., 1., "upper") for row in face.BILL_UPPER]
        self.assertEqual(roofs.index(max(roofs)), 2)
        self.assertGreater(face.bill_smile(-.438, .137, 1.), .025)
        self.assertEqual(face.bill_smile(-.438, .137, 0.), 0.)

    def test_material_callback_retains_lit_bsdf_and_only_declared_controls(self):
        materials = {}
        for name, recipe in face.MATERIALS.items():
            socket = lambda value: SimpleNamespace(default_value=value, is_linked=False)
            inputs = {"Roughness": socket(recipe["old_roughness"]), "Specular IOR Level": socket(.5),
                      "IOR": socket(1.5), "Base Color": socket((.005, .01, .017, 1.)),
                      "Emission Strength": socket(0.)}
            materials[name] = SimpleNamespace(node_tree=SimpleNamespace(nodes={"Principled BSDF": SimpleNamespace(inputs=inputs)}))
        receipt = face.apply_material_changes(materials)
        self.assertEqual(len(receipt), 16)
        pupil = materials["pupil"].node_tree.nodes["Principled BSDF"].inputs
        self.assertEqual(pupil["Specular IOR Level"].default_value, .045)
        self.assertEqual(pupil["IOR"].default_value, 1.33)
        self.assertEqual(pupil["Emission Strength"].default_value, 0.)
        self.assertEqual(pupil["Base Color"].default_value, (.0015, .003, .005, 1.))

    def test_no_implicit_acceptance_or_candidate_registration(self):
        record = face.source_only_declarations()
        self.assertEqual(record["study_profile"], "integrated-face-z09")
        self.assertNotIn(face.PROFILE, study.PROFILE_OVERRIDES)
        self.assertNotIn(face.PROFILE, provenance.PROFILES)
        for key in ("production_ready", "source_fidelity_approved", "geometry_approved",
                    "candidate_export_allowed", "runtime_rig_or_glb_created"):
            self.assertIs(record[key], False)


@unittest.skipIf(np is None, "NumPy required; run standalone bundled Python, not Blender engine")
class FaceZ09FieldTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.old, _ = study.fresh_design(face.PARENT_PROFILE)
        cls.new, _ = face.fresh_design()

    def iris_perimeter(self, side):
        d = self.new
        origin, across, normal, up = map(np.asarray, d.eye_surface_frame(side))
        cx, cz = d.eye_gaze_center(side)
        radii = np.asarray(d.EYE_RADII)
        center = np.asarray((cx, radii[1] * math.sqrt(1. - (cx / radii[0]) ** 2 - (cz / radii[2]) ** 2), cz))
        n = center / radii ** 2
        n /= np.linalg.norm(n)
        a = np.cross(n, (0., 0., 1.)); a /= np.linalg.norm(a)
        u = np.cross(a, n)
        points = []
        for angle in np.linspace(0., math.tau, 128, endpoint=False):
            tangent = center + a * d.IRIS_RADII[0] * math.cos(angle) + u * d.IRIS_RADII[1] * math.sin(angle)
            x, y, z = d.project_eye_patch(tangent, .0016)
            points.append(origin + across * x + normal * (y - d.EYE_BURY_DEPTH) + up * z)
        return np.asarray(points)

    def test_large_iris_remains_clear_and_eye_frame_stays_z06(self):
        for side in (-1., 1.):
            np.testing.assert_array_equal(self.new.eye_surface_frame(side), self.old.eye_surface_frame(side))
            np.testing.assert_array_equal(self.new.eye_gaze_center(side), self.old.eye_gaze_center(side))
            values = self.new.sculpt_body_field(self.iris_perimeter(side))
            self.assertTrue(np.all(np.isfinite(values)))
            self.assertGreater(float(values.min()), .0005)

    def test_both_lids_cover_globe_and_socket_has_a_closed_back(self):
        d = self.new
        origin, across, normal, up = map(np.asarray, d.eye_surface_frame(1.))
        for z in (-.112, .115):
            x = -.009
            depth = d.EYE_RADII[1] * math.sqrt(1. - (x / d.EYE_RADII[0]) ** 2 - (z / d.EYE_RADII[2]) ** 2) - d.EYE_BURY_DEPTH
            self.assertLess(float(d.sculpt_body_field(origin + across * x + normal * depth + up * z)), 0.)
        self.assertLess(float(d.sculpt_body_field(origin - normal * .080)), 0.)
        self.assertGreater(float(d.sculpt_body_field(origin)), 0.)

    def test_body_warp_is_bounded_symmetric_and_does_not_fold_or_move_crown_feet(self):
        points = np.asarray([(x, y, z) for x in (-.4, -.2, 0., .2, .4)
                             for y in np.linspace(-.4, 0., 11) for z in (.09, .8, 1.125, 1.315, 1.335, 1.415, 1.8)])
        moved = face.warp_points(points)
        displacement = moved[:, 1] - points[:, 1]
        self.assertTrue(np.all(displacement <= .0435 + 1e-12))
        self.assertTrue(np.all(displacement >= -.020 - 1e-12))
        np.testing.assert_allclose(face.warp_points(points * (-1., 1., 1.)), moved * (-1., 1., 1.), atol=1e-15)
        epsilon = np.asarray((0., 1e-6, 0.))
        derivative = (face.warp_points(points + epsilon)[:, 1] - face.warp_points(points - epsilon)[:, 1]) / 2e-6
        self.assertGreater(float(derivative.min()), 1. - .0435 * 7.5 - 1e-6)
        outside = (points[:, 2] < .95) | (points[:, 2] > 1.42)
        np.testing.assert_array_equal(moved[outside], points[outside])

    def test_cheek_paint_profile_is_curved_and_semantic_masks_remain_valid(self):
        curves = []
        for z in (1.22, 1.34, 1.46):
            samples = []
            for angle in np.linspace(.9, 1.9, 101):
                point = (.43 * math.sin(angle), -.43 * math.cos(angle), z)
                color, masks = face.body_paint(point, self.new.eye_surface_frame)
                self.assertTrue(all(math.isfinite(v) and 0. <= v <= 1. for v in (*color, *masks)))
                samples.append((angle, masks[0]))
            curves.append(max(angle for angle, cream in samples if cream >= .5))
        # A vertical front cutoff would put these boundaries at one angle.
        self.assertGreater(max(curves) - min(curves), .20)


if __name__ == "__main__":
    unittest.main()
