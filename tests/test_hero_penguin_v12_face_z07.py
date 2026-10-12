"""Host-only Z07 scope/shape guards; no renderer or visual approval."""
from __future__ import annotations

import ast
import math
from pathlib import Path
import sys
import tempfile
from types import ModuleType, SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/art"))
import hero_penguin_v12_face_z07 as face
import hero_penguin_v12_source_study as study
import hero_penguin_v12_study_provenance as provenance
import render_hero_penguin_v12_source_study as base
import render_hero_penguin_v12_face_z07 as launcher


def materials():
    def material(roughness):
        socket = lambda value: SimpleNamespace(default_value=value, is_linked=False)
        shader = SimpleNamespace(inputs={"Roughness": socket(roughness),
                                          "Specular IOR Level": socket(.5)})
        return SimpleNamespace(node_tree=SimpleNamespace(nodes={"Principled BSDF": shader}))
    return {"iris": material(.32), "pupil": material(.28), "body": material(.74)}


class FaceZ07Tests(unittest.TestCase):
    def test_only_declared_face_constants_change_and_frozen_inputs_stay_identical(self):
        paths = [ROOT / "tools/art" / name for name in base.INPUT_TOOLS]
        before = {str(path): base.sha(path) for path in paths}
        prior, _ = study.fresh_design(face.PARENT_PROFILE)
        selected, record = face.fresh_design()
        changed = {name for name, value in study.constants(selected).items()
                   if value != study.constants(prior)[name]}
        self.assertEqual(changed, {"LIMBAL_RADII", "IRIS_RADII", "PUPIL_RADII", "BILL_UPPER_SECTIONS"})
        self.assertEqual(selected.EYE_CENTER_X, .215)
        self.assertEqual(selected.EYE_RADII, prior.EYE_RADII)
        self.assertEqual(selected.EYE_BURY_DEPTH, prior.EYE_BURY_DEPTH)
        self.assertEqual(selected.EYE_GAZE_TARGET, prior.EYE_GAZE_TARGET)
        self.assertEqual(selected.BILL_LOWER_SECTIONS, prior.BILL_LOWER_SECTIONS)
        self.assertEqual(len(record["z07_constant_changes"]), 7)
        self.assertEqual(before, {str(path): base.sha(path) for path in paths})

    def test_renderer_delta_is_only_two_catchlight_literals(self):
        previous, _ = study.renderer_syntax(face.PARENT_PROFILE, base.RENDERER)
        selected, record = face.renderer_syntax(base.RENDERER)
        compile(selected, str(base.RENDERER), "exec")
        old_nodes, new_nodes = list(ast.walk(previous)), list(ast.walk(selected))
        self.assertEqual(len(old_nodes), len(new_nodes))
        changed = [(old, new) for old, new in zip(old_nodes, new_nodes)
                   if ast.dump(old, include_attributes=False) != ast.dump(new, include_attributes=False)
                   and isinstance(old, ast.Constant)]
        self.assertEqual([(old.value, new.value) for old, new in changed], [(.008, .0055), (.011, .0075)])
        for old, new in changed:
            new.value = old.value
        self.assertEqual(study.ast_digest(previous), study.ast_digest(selected))
        self.assertEqual(len(record["z07_renderer_literal_changes"]), 2)

    def test_fresh_cohort_is_installed_and_restored_without_evaluating_geometry(self):
        previous = sys.modules.get(study.DESIGN_MODULE)
        with face.installed_design() as (selected, _):
            self.assertIs(sys.modules[study.DESIGN_MODULE], selected)
            renderer = ModuleType("fake_renderer")
            for name, value in study.constants(selected).items():
                setattr(renderer, name, value)
            for name in study.SHARED_FUNCTIONS:
                setattr(renderer, name, getattr(selected, name))
            study.require_renderer_cohort(renderer, selected)
            self.assertEqual(selected.eye_surface_frame.cache_info().currsize, 0)
        self.assertIs(sys.modules.get(study.DESIGN_MODULE), previous)

    def test_eye_pigment_and_bill_shape_remain_bounded(self):
        selected, _ = face.fresh_design()
        self.assertEqual(selected.IRIS_RADII, (.066, .085))
        self.assertEqual(selected.LIMBAL_RADII, (.069, .089))
        self.assertEqual(selected.PUPIL_RADII, (.041, .055))
        for axis in (0, 1):
            self.assertLess(selected.PUPIL_RADII[axis], selected.IRIS_RADII[axis])
            self.assertLess(selected.IRIS_RADII[axis], selected.LIMBAL_RADII[axis])
            self.assertLess(selected.LIMBAL_RADII[axis], selected.eye_tangent_aperture_radii()[axis])
        self.assertLessEqual(max(row[1] for row in selected.BILL_UPPER_SECTIONS), .135)
        for y, width, height, center in selected.BILL_UPPER_SECTIONS:
            self.assertTrue(-.572 < y < -.388)
            self.assertGreater(width, 0.)
            for segment in range(96):
                angle = math.tau * segment / 96
                z = selected.bill_section_height(y, width, height, center,
                                                  math.cos(angle), math.sin(angle), "upper")
                self.assertTrue(math.isfinite(z) and 1.30 < z < 1.445)
        # No extra ridge, extent, jaw or mouth-seam edits hidden in proposal.
        self.assertFalse(face.source_only_declarations()["bill_ridge_added"])

    def test_material_callback_changes_only_two_requested_controls(self):
        values = materials()
        receipt = face.apply_material_changes(values)
        self.assertEqual([item["material"] for item in receipt], ["iris", "pupil"])
        for name, roughness in (("iris", .40), ("pupil", .18), ("body", .74)):
            inputs = values[name].node_tree.nodes["Principled BSDF"].inputs
            self.assertEqual(inputs["Roughness"].default_value, roughness)
            self.assertEqual(inputs["Specular IOR Level"].default_value, .5 if name == "body" else .25)
        broken = materials()
        broken["pupil"].node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = .7
        with self.assertRaisesRegex(ValueError, "parent eye roughness changed"):
            face.apply_material_changes(broken)
        self.assertEqual(broken["iris"].node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value, .32)

    def test_source_only_quarantine_and_no_implicit_export_acceptance(self):
        record = face.source_only_declarations()
        self.assertEqual(record["study_profile"], "juvenile-face-z07")
        self.assertTrue(record["source_only"])
        for name in ("source_fidelity_approved", "production_ready", "geometry_approved",
                     "candidate_export_allowed", "runtime_rig_or_glb_created"):
            self.assertIs(record[name], False)
        self.assertNotIn(face.PROFILE, study.PROFILE_OVERRIDES)
        self.assertNotIn(face.PROFILE, provenance.PROFILES)
        text = Path(launcher.__file__).read_text()
        self.assertLess(text.index("face.renderer_syntax("), text.index("with face.installed_design()"))
        self.assertLess(text.index("study.require_renderer_cohort("), text.index("renderer.main()"))
        for forbidden in ("export_scene", "renderer.setup_stage =", "renderer.render_views =",
                          "renderer.body_paint =", "renderer.voxel_fuse_body ="):
            self.assertNotIn(forbidden, text)

    def test_output_quarantine_uses_self_contained_paths(self):
        # The suite snapshot deliberately omits qa_shots. Never depend on an
        # earlier rendered study existing in the developer's working tree.
        with tempfile.TemporaryDirectory(prefix="waddle-z07-quarantine-") as folder:
            root = Path(folder).resolve()
            qa = root / "qa_shots/hero"
            existing = qa / "existing-study"
            existing.mkdir(parents=True)
            fresh = qa / "fresh-study"
            with patch.multiple(base, ROOT=root, QA=qa):
                for rejected in (qa, existing, root / "outside-study"):
                    with self.subTest(path=rejected.name):
                        with self.assertRaisesRegex(ValueError, "fresh dedicated"):
                            base.output_path(rejected)
                with self.assertRaisesRegex(ValueError, "excluded from Godot imports"):
                    base.output_path(fresh)
                (root / "qa_shots/.gdignore").touch()
                self.assertEqual(base.output_path(fresh), fresh)
                with self.assertRaisesRegex(ValueError, "fresh dedicated"):
                    base.output_path(existing)
                self.assertFalse(fresh.exists(), "path validation must not create output")


if __name__ == "__main__":
    unittest.main()
