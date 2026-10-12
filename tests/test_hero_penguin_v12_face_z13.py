"""Full analytic Z13 color/mask math and scope; never visual acceptance."""
from __future__ import annotations

import ast
import math
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/art"))
import hero_penguin_v12_face_z13 as face
import hero_penguin_v12_source_study as study
import hero_penguin_v12_study_provenance as provenance
import render_hero_penguin_v12_source_study as base

# Exact frozen Z12 frames, not newly evaluated geometry/camera values.
FRAMES = {
    -1.: ((-.215, -.3606855224272294, 1.48), (.871319999706771, -.4907152515573493, 0.),
          (-.4655497990400291, -.8266359145669195, .3161272676658894),
          (.1551284716768044, .2754480107699451, .9487167915864559)),
    1.: ((.215, -.3606855224272294, 1.48), (.871319999706771, .4907152515573493, 0.),
         (.4655497990400291, -.8266359145669195, .3161272676658894),
         (-.1551284716768044, .2754480107699451, .9487167915864559)),
}
RADII = (.147, .100, .176)
FAILED_HITS = (
    ((-.38285940885543823, -.18041610717773438, 1.4986591339111328),
     (.15693528838038195, .15299403922072496, .13671741599376255, 1.)),
    ((-.4096094071865082, -.1206369400024414, 1.4836050271987915),
     (.050393119051281486, .057066282771262196, .06307992659847113, 1.)),
)


class FaceZ13Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.program = face.full_paint_program(FRAMES, RADII)

    def test_same_geometry_renderer_and_original_inputs(self):
        paths = [ROOT / "tools/art" / name for name in (*base.INPUT_TOOLS,
                 "hero_penguin_v12_face_z09.py", "hero_penguin_v12_face_z10.py",
                 "hero_penguin_v12_face_z11.py", "hero_penguin_v12_face_z12.py",
                 "render_hero_penguin_v12_face_z12.py")]
        before = {str(path): base.sha(path) for path in paths}
        for name in ("fresh_design", "installed_design", "renderer_syntax", "apply_material_changes"):
            self.assertIs(getattr(face, name), getattr(face.prior, name))
        old, _ = face.prior.fresh_design()
        new, _ = face.fresh_design()
        self.assertEqual(study.constants(old), study.constants(new))
        tree, _ = face.renderer_syntax(base.RENDERER)
        compile(tree, str(base.RENDERER), "exec")
        self.assertEqual(before, {str(path): base.sha(path) for path in paths})

    def test_full_color_and_masks_match_frozen_scalar_design(self):
        for x in (-.55, -.40, -.22, -.06, 0., .06, .22, .40, .55):
            for y in (-.45, -.18, .12, .42):
                for z in (.12, .55, .90, 1.18, 1.35, 1.48, 1.54, 1.62, 1.79):
                    point = (x, y, z)
                    expected_color, expected_masks = face.prior.prior.body_paint(point, lambda side: FRAMES[side], RADII)
                    actual = face.evaluate_program(self.program, point)
                    for name, expected in (("color", expected_color), ("masks", expected_masks)):
                        for a, b in zip(actual[name], expected):
                            self.assertAlmostEqual(a, b, places=12, msg=f"{name} at {point}")

    def test_real_failed_pixels_no_longer_depend_on_interpolated_underpaint(self):
        for point, expected in FAILED_HITS:
            actual = face.evaluate_program(self.program, point)
            self.assertEqual(actual["hood"], 0.)
            for a, b in zip(actual["color"], expected):
                self.assertAlmostEqual(a, b, places=12)
        red = [face.evaluate_program(self.program, point)["color"][0] for point, _ in FAILED_HITS]
        self.assertGreater(abs(red[0] - .2763738149734284), .11)
        self.assertGreater(abs(red[1] - .1548861665467933), .10)

    def test_program_has_position_only_inputs_and_separate_rgba_masks(self):
        self.assertEqual(self.program["inputs"], ["x", "y", "z"])
        self.assertEqual(set(self.program["outputs"]), {"color", "masks", "hood"})
        self.assertEqual(self.program["outputs"]["masks"][3], 1.)
        self.assertNotIn("PreviewColor", repr(self.program))
        hood = face.prior.hood_program(FRAMES, RADII)
        self.assertEqual(self.program["operations"][:len(hood["operations"])], hood["operations"])

    def test_continuous_failed_boundary_and_finite_exclusive_masks(self):
        point = FAILED_HITS[0][0]
        values = [face.evaluate_program(self.program, (point[0], point[1], point[2] + step * .00005))
                  for step in range(-30, 31)]
        self.assertGreater(len(set(round(value["color"][0], 9) for value in values)), 50)
        for result in values:
            self.assertTrue(all(math.isfinite(v) and -1e-12 <= v <= 1. + 1e-12 for v in (*result["color"], *result["masks"])))
            self.assertLessEqual(sum(result["masks"][:3]), 1. + 1e-12)
            self.assertEqual(result["masks"][3], 1.)

    def test_installer_is_body_only_material_copy_not_wing_repaint(self):
        tree = ast.parse(Path(face.__file__).read_text())
        install = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == "install_continuous_paint")
        text = ast.get_source_segment(Path(face.__file__).read_text(), install)
        self.assertIn("original_material.copy()", text)
        self.assertIn("body.data.materials[0] = material", text)
        self.assertIn("or source.links", text)
        self.assertNotIn('links.new(source,', text)

    def test_no_runtime_or_visual_approval(self):
        record = face.source_only_declarations()
        self.assertNotIn(face.PROFILE, provenance.PROFILES)
        self.assertTrue(record["paint_input_graph_changed"])
        self.assertFalse(record["entire_material_graph_unchanged"])
        for key in ("production_ready", "source_fidelity_approved", "geometry_approved",
                    "candidate_export_allowed", "runtime_rig_or_glb_created"):
            self.assertIs(record[key], False)


if __name__ == "__main__":
    unittest.main()
