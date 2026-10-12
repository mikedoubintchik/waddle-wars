"""Z12 paint math/scope guards, not Blender execution or visual approval."""
from __future__ import annotations

import ast
import math
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/art"))
import hero_penguin_v12_face_z12 as face
import hero_penguin_v12_source_study as study
import hero_penguin_v12_study_provenance as provenance
import render_hero_penguin_v12_source_study as base


class FaceZ12Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Fixed local frames require no Blender/NumPy or geometry evaluation.
        cls.frames = {side: ((side * .215, -.35, 1.48), (1., 0., 0.), (0., -1., 0.), (0., 0., 1.))
                      for side in (-1., 1.)}
        cls.radii = (.147, .100, .176)
        cls.program = face.hood_program(cls.frames, cls.radii)

    def test_exact_z11_geometry_and_all_old_source_files_unchanged(self):
        paths = [ROOT / "tools/art" / name for name in (*base.INPUT_TOOLS,
                 "hero_penguin_v12_face_z09.py", "hero_penguin_v12_face_z10.py",
                 "hero_penguin_v12_face_z11.py", "render_hero_penguin_v12_face_z11.py")]
        before = {str(path): base.sha(path) for path in paths}
        self.assertIs(face.fresh_design, face.prior.fresh_design)
        self.assertIs(face.installed_design, face.prior.installed_design)
        self.assertIs(face.apply_material_changes, face.prior.apply_material_changes)
        old, _ = face.prior.fresh_design()
        new, _ = face.fresh_design()
        self.assertEqual(study.constants(old), study.constants(new))
        self.assertEqual(before, {str(path): base.sha(path) for path in paths})

    def test_renderer_only_changes_vertex_pigment_assignment_not_geometry_or_stage(self):
        old, _ = face.prior.renderer_syntax(base.RENDERER)
        new, _ = face.renderer_syntax(base.RENDERER)
        compile(new, str(base.RENDERER), "exec")
        functions = lambda tree: {n.name: ast.dump(n, include_attributes=False)
                                  for n in tree.body if isinstance(n, ast.FunctionDef)}
        a, b = functions(old), functions(new)
        self.assertEqual(set(a), set(b))
        self.assertEqual({name for name in a if a[name] != b[name]}, {"assign_body_materials"})

    def test_node_program_equals_original_z11_analytic_pigment(self):
        frame = lambda side: self.frames[side]
        for x in (-.4, -.32, -.24, -.16, -.06, 0., .06, .16, .24, .32, .4):
            for z in (1.35, 1.43, 1.48, 1.50, 1.53, 1.56, 1.579, 1.580, 1.581, 1.62, 1.69):
                point = (x, -.39, z)
                under, semantics = face.vertex_underpaint(point, frame, self.radii)
                actual = face.composite_underpaint(under, face.evaluate_program(self.program, point))
                expected, expected_semantics = face.prior.body_paint(point, frame, self.radii)
                for value, wanted in zip(actual, expected):
                    self.assertAlmostEqual(value, wanted, places=12)
                self.assertEqual(semantics, expected_semantics)

    def test_continuous_three_mm_edge_not_quantized_to_mesh_spacing(self):
        p = face.prior.prior.prior.ORBIT
        local_x = -p["nasal_offset"]
        edge = p["center_z"] - p["outer_corner_drop"] * local_x + p["opening_upper"]
        origin = self.frames[1.][0]
        values = [face.evaluate_program(self.program, (origin[0] + local_x, -.39, origin[2] + edge + offset * .00005))
                  for offset in range(-30, 31)]
        self.assertAlmostEqual(values[0], 0., places=12)
        self.assertAlmostEqual(values[-1], 1., places=12)
        self.assertGreater(len(set(round(value, 9) for value in values)), 50)
        self.assertTrue(all(a <= b + 1e-12 for a, b in zip(values, values[1:])))

    def test_body_and_wing_zone_unaffected_and_values_finite_bounded(self):
        for point in ((0., -.3, .7), (.5, .1, .8), (-.5, .1, .8), (.345, -.08, 1.2), (-.345, -.08, 1.2)):
            self.assertEqual(face.evaluate_program(self.program, point), 0.)
        for x in (-.5, -.215, 0., .215, .5):
            for z in (0., 1., 1.4, 1.5, 1.6, 1.7, 2.):
                value = face.evaluate_program(self.program, (x, -.4, z))
                self.assertTrue(math.isfinite(value) and -1e-12 <= value <= 1. + 1e-12)

    def test_no_approval_no_runtime_shader_and_graph_change_explicit(self):
        record = face.source_only_declarations()
        self.assertNotIn(face.PROFILE, provenance.PROFILES)
        self.assertTrue(record["paint_input_graph_changed"])
        self.assertFalse(record["entire_material_graph_unchanged"])
        for key in ("production_ready", "source_fidelity_approved", "geometry_approved",
                    "candidate_export_allowed", "runtime_rig_or_glb_created"):
            self.assertIs(record[key], False)


if __name__ == "__main__":
    unittest.main()
