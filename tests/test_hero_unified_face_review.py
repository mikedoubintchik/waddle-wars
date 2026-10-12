"""Host-only reviewed source handoff; synthetic bytes never approve appearance."""
import builtins
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("unified_review_provenance", ROOT / "tools/art/hero_penguin_v12_study_provenance.py")
P = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(P)


class UnifiedFaceReviewTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name).resolve()
        self.source = self.directory / "hero_penguin_v12_source_proof.blend"
        self.source.write_bytes(b"synthetic saved source; not a Blender scene or visual approval")
        self.tools = self.directory / "tools"
        self.tools.mkdir()
        self.materials = self.directory / "materials"
        self.materials.mkdir()
        for name in P.UNIFIED_CAPTURE_TOOLS:
            # Only the selected construction is byte-pinned. Other synthetic
            # dependencies actively fail if a reader ever executes them.
            raw = ((ROOT / "tools/art" / name).read_bytes() if name == "hero_penguin_face_sculpt.py"
                   else b'raise RuntimeError("source review must never execute dependencies")\n')
            (self.tools / name).write_bytes(raw)
        for name in P.UNIFIED_CAPTURE_TILES:
            (self.materials / name).write_bytes(b"synthetic immutable tile " + name.encode())
        for name in P.UNIFIED_IMAGES:
            (self.directory / name).write_bytes(b"synthetic image fixture " + name.encode())
        self.adapter = self.directory / "adapter.py"
        self.adapter.write_bytes(b"# synthetic adapter; never executed\n")
        self.inputs_path = self.directory / "source_study_inputs.json"
        self.audit_path = self.directory / "source_study_audit.json"
        self.review_path = self.directory / "source_qa_review.json"
        inputs = {str(self.tools / name): P.sha(self.tools / name) for name in P.UNIFIED_CAPTURE_TOOLS}
        inputs.update({str(self.materials / name): P.sha(self.materials / name) for name in P.UNIFIED_CAPTURE_TILES})
        self.record = {
            "schema_version": 1, "study_profile": P.UNIFIED_PROFILE, "parent_profile": "juvenile-socket-z06",
            "source_only": True, "production_ready": False, "source_fidelity_approved": False,
            "geometry_approved": False, "candidate_export_allowed": False, "runtime_rig_or_glb_created": False,
            "renderer_cohort_verified_before_geometry": True, "inputs": inputs,
            "selected_helper": str(self.tools / "hero_penguin_face_sculpt.py"),
            "selected_launcher": str(self.tools / "render_hero_penguin_face_sculpt.py"),
            "source_renderer": str(self.tools / "render_hero_penguin_v12_source_proof.py"),
            "material_dir": str(self.materials), "selected_renderer_ast_sha256": "a" * 64,
            "command": ["synthetic-blender", "--python", str(self.tools / "render_hero_penguin_face_sculpt.py")],
            "selected_design_record": {
                "selected_design_constants": {}, "support_volumes": [], "aperture_landmarks": {},
                "old_orbital_sculpt_and_separate_hood_overlay_retired": True,
                "parent_design_record": {
                    "schema_version": 1, "study_profile": "juvenile-socket-z06", "source_only": True,
                    "production_ready": False, "source_fidelity_approved": False, "runtime_rig_or_glb_created": False,
                    "baseline_design_ast_sha256": "b" * 64, "selected_design_ast_sha256": "c" * 64,
                    "baseline_design_path": str(self.tools / "hero_penguin_v12_design.py"),
                    "baseline_design_sha256": inputs[str(self.tools / "hero_penguin_v12_design.py")]}},
            "parent_renderer_record": {"baseline_renderer_ast_sha256": "d" * 64,
                "selected_renderer_ast_sha256": "e" * 64,
                "baseline_renderer_path": str(self.tools / "render_hero_penguin_v12_source_proof.py"),
                "baseline_renderer_sha256": inputs[str(self.tools / "render_hero_penguin_v12_source_proof.py")]},
            "continuous_paint_input": {"program_sha256": P.UNIFIED_PAINT_PROGRAM_SHA256,
                "visual_approval": False, "geometry_changed": False, "runtime_procedural_shader_added": False,
                "body_vertex_color_dependency": False, "wing_material_and_paint_unchanged": True,
                "material_response_recipe_preserved": True}}
        self.save_record()
        self.review = self.make_review()
        self.save_review()

    def save_record(self, record=None):
        self.record = copy.deepcopy(self.record if record is None else record)
        raw = json.dumps(self.record, sort_keys=True, allow_nan=False)
        self.inputs_path.write_text(raw)
        outputs = {self.source.name: P.sha(self.source)}
        outputs.update({name: P.sha(self.directory / name) for name in P.UNIFIED_IMAGES})
        audit = dict(self.record, inputs_unchanged=True, rendered_views=["front", "threequarter", "true_side"], outputs=outputs)
        self.audit_path.write_text(json.dumps(audit, sort_keys=True, allow_nan=False))
        self.scene = {"source_study_profile": self.record["study_profile"], "source_study_json": raw,
                      "source_study_production_ready": False}

    def make_review(self):
        return {"schema_version": 1, "study_profile": P.UNIFIED_PROFILE, "review_scope": P.UNIFIED_QA_SCOPE,
                "source_only": True, "candidate_only_budgeted_review": True, "production_ready": False,
                "source_fidelity_approved": False, "geometry_approved": False, "runtime_rig_or_glb_created": False,
                "source_blend_filename": self.source.name, "source_blend_sha256": P.sha(self.source),
                "source_study_inputs_sha256": P.sha(self.inputs_path), "source_study_audit_sha256": P.sha(self.audit_path),
                "selected_construction_source_sha256": P.UNIFIED_CONSTRUCTION_SHA256,
                "continuous_paint_program_sha256": P.UNIFIED_PAINT_PROGRAM_SHA256,
                "capture_dependencies": copy.deepcopy(self.record["inputs"]),
                "inspected_image_filenames": list(P.UNIFIED_IMAGES),
                "image_outputs": {name: P.sha(self.directory / name) for name in P.UNIFIED_IMAGES}}

    def save_review(self, review=None):
        self.review_path.write_text(json.dumps(self.review if review is None else review, sort_keys=True, allow_nan=False))

    def read(self):
        return P.read_source_study(self.source, self.scene)

    def test_exact_review_admits_candidate_only_binding_and_all_unchanged_inputs(self):
        before_scene = copy.deepcopy(self.scene)
        paths = [self.source, self.inputs_path, self.audit_path, self.review_path,
                 *map(Path, self.record["inputs"]), *(self.directory / name for name in P.UNIFIED_IMAGES)]
        before = {str(path): P.sha(path) for path in paths}
        binding = self.read()
        self.assertEqual(binding["source_qa_review_sha256"], P.sha(self.review_path))
        self.assertEqual(binding["source_qa_review"], self.review)
        self.assertIs(binding["candidate_only_budgeted_review"], True)
        for field in ("production_ready", "source_fidelity_approved", "geometry_approved"):
            self.assertIs(binding[field], False)
        self.assertIs(binding["source_cover_scope"]["study_source_cover_approved"], False)
        self.assertEqual(P.binding_input_hashes(self.source, binding), before)
        self.assertEqual(self.scene, before_scene)
        self.assertEqual(before, {str(path): P.sha(path) for path in paths})

    def test_absent_contract_and_default_validate_record_stay_closed(self):
        self.assertNotIn(P.UNIFIED_PROFILE, P.PROFILES)
        with self.assertRaisesRegex(RuntimeError, "unknown study profile"):
            P.validate_record(self.record)
        self.review_path.unlink()
        with self.assertRaisesRegex(RuntimeError, "source_qa_review.json"):
            self.read()

    def test_review_cannot_replace_missing_scene_or_original_sidecars(self):
        with self.assertRaisesRegex(RuntimeError, "partial"):
            P.read_source_study(self.source, {})
        raw = self.inputs_path.read_bytes()
        self.inputs_path.unlink()
        with self.assertRaisesRegex(RuntimeError, "partial"):
            self.read()
        self.inputs_path.write_bytes(raw)
        self.audit_path.unlink()
        with self.assertRaisesRegex(RuntimeError, "partial"):
            self.read()

    def test_every_review_field_required_and_extra_claims_rejected(self):
        for field in P.UNIFIED_REVIEW_FIELDS:
            changed = copy.deepcopy(self.review)
            del changed[field]
            self.save_review(changed)
            with self.subTest(field=field), self.assertRaisesRegex(RuntimeError, "contract"):
                self.read()
        self.save_review(dict(self.review, sales_allowed=True))
        with self.assertRaisesRegex(RuntimeError, "contract"):
            self.read()

    def test_review_booleans_and_schema_never_accept_integer_aliases(self):
        for field, values in (("schema_version", (True, 1.0)), ("source_only", (1, False)),
                              ("candidate_only_budgeted_review", (1, False)),
                              *((field, (0, True)) for field in ("production_ready", "source_fidelity_approved",
                                                                 "geometry_approved", "runtime_rig_or_glb_created"))):
            for value in values:
                self.save_review(dict(self.review, **{field: value}))
                with self.subTest(field=field, value=value), self.assertRaises(RuntimeError):
                    self.read()

    def test_source_parent_and_paint_boolean_aliases_stay_closed(self):
        original = copy.deepcopy(self.record)
        for group, field, value in ((None, "source_only", 1), (None, "production_ready", 0),
                                    (None, "source_fidelity_approved", True), (None, "geometry_approved", 0),
                                    (None, "candidate_export_allowed", True),
                                    (None, "renderer_cohort_verified_before_geometry", 1),
                                    ("parent", "source_only", 1), ("parent", "production_ready", True),
                                    ("paint", "visual_approval", 0), ("paint", "geometry_changed", True),
                                    ("paint", "wing_material_and_paint_unchanged", 1)):
            changed = copy.deepcopy(original)
            target = (changed if group is None else changed["continuous_paint_input"] if group == "paint"
                      else changed["selected_design_record"]["parent_design_record"])
            target[field] = value
            self.save_record(changed)
            self.save_review(self.make_review())
            with self.subTest(group=group, field=field), self.assertRaises(RuntimeError):
                self.read()

    def test_profile_scope_filename_and_pinned_hashes_cannot_be_relabelled(self):
        for field, value in (("study_profile", "juvenile-socket-z06"), ("review_scope", "production"),
                             ("source_blend_filename", "different.blend"),
                             *((field, "f" * 64) for field in ("source_blend_sha256", "source_study_inputs_sha256",
                                "source_study_audit_sha256", "selected_construction_source_sha256", "continuous_paint_program_sha256"))):
            self.save_review(dict(self.review, **{field: value}))
            with self.subTest(field=field), self.assertRaises(RuntimeError):
                self.read()
        self.save_review()
        changed = copy.deepcopy(self.record)
        changed["study_profile"] = "juvenile-socket-z06"
        self.save_record(changed)
        with self.assertRaisesRegex(RuntimeError, "relabel"):
            self.read()

    def test_every_capture_dependency_required_including_original_paint_ancestry(self):
        original = copy.deepcopy(self.record)
        for path in original["inputs"]:
            changed = copy.deepcopy(original)
            del changed["inputs"][path]
            self.save_record(changed)
            self.save_review(self.make_review())
            with self.subTest(path=path), self.assertRaisesRegex(RuntimeError, "capture dependencies"):
                self.read()
        changed = copy.deepcopy(original)
        changed["inputs"][str(self.tools / "unexpected.py")] = "f" * 64
        self.save_record(changed)
        self.save_review(self.make_review())
        with self.assertRaisesRegex(RuntimeError, "capture dependencies"):
            self.read()

    def test_changed_dependency_bytes_missing_files_and_path_aliases_rejected(self):
        path = self.tools / "hero_penguin_v12_face_z13.py"
        raw = path.read_bytes()
        path.write_bytes(raw + b"# mutated\n")
        with self.assertRaisesRegex(RuntimeError, "dependency SHA changed"):
            self.read()
        path.unlink()
        with self.assertRaisesRegex(RuntimeError, "QA file"):
            self.read()
        path.write_bytes(raw)
        changed = copy.deepcopy(self.record)
        digest = changed["inputs"].pop(str(path))
        changed["inputs"][str(path.parent) + "/../tools/" + path.name] = digest
        self.save_record(changed)
        self.save_review(self.make_review())
        with self.assertRaisesRegex(RuntimeError, "capture dependencies"):
            self.read()

    def test_program_and_construction_cohorts_fail_closed(self):
        original = copy.deepcopy(self.record)
        for group, field, value in (("paint", "program_sha256", "f" * 64),
                                   (None, "selected_renderer_ast_sha256", "invalid"),
                                   ("design", "old_orbital_sculpt_and_separate_hood_overlay_retired", 1),
                                   ("design", "parent_design_record", {}),
                                   ("parent_renderer", "baseline_renderer_sha256", "f" * 64),
                                   (None, "selected_helper", str(self.tools / "hero_penguin_v12_face_z13.py")),
                                   (None, "selected_launcher", str(self.tools / "render_hero_penguin_v12_face_z13.py")),
                                   (None, "command", ["synthetic", "--python", "wrong.py"])):
            changed = copy.deepcopy(original)
            target = (changed if group is None else changed[{"paint": "continuous_paint_input",
                      "design": "selected_design_record", "parent_renderer": "parent_renderer_record"}[group]])
            target[field] = value
            self.save_record(changed)
            self.save_review(self.make_review())
            with self.subTest(group=group, field=field), self.assertRaises(RuntimeError):
                self.read()

    def test_actual_three_images_must_be_explicitly_inspected_and_rehashed(self):
        for names in (list(P.UNIFIED_IMAGES[:2]), list(reversed(P.UNIFIED_IMAGES)),
                      [*P.UNIFIED_IMAGES, "other.png"]):
            self.save_review(dict(self.review, inspected_image_filenames=names))
            with self.assertRaisesRegex(RuntimeError, "image cohort"):
                self.read()
        changed = copy.deepcopy(self.review)
        changed["image_outputs"][P.UNIFIED_IMAGES[0]] = "f" * 64
        self.save_review(changed)
        with self.assertRaisesRegex(RuntimeError, "image SHA"):
            self.read()
        self.save_review()
        for name in P.UNIFIED_IMAGES:
            path = self.directory / name
            raw = path.read_bytes()
            path.write_bytes(raw + b"changed")
            with self.subTest(name=name), self.assertRaisesRegex(RuntimeError, "image SHA"):
                self.read()
            path.write_bytes(raw)

    def test_original_scene_inputs_audit_and_blend_equality_not_bypassed(self):
        changed_scene = dict(self.scene, source_study_production_ready=0)
        with self.assertRaisesRegex(RuntimeError, "scene profile/status"):
            P.read_source_study(self.source, changed_scene)
        changed_scene = dict(self.scene, source_study_json="{}")
        with self.assertRaisesRegex(RuntimeError, "input sidecar disagree"):
            P.read_source_study(self.source, changed_scene)
        raw_audit = self.audit_path.read_bytes()
        audit = json.loads(raw_audit)
        audit["production_ready"] = True
        self.audit_path.write_text(json.dumps(audit))
        with self.assertRaisesRegex(RuntimeError, "completed audit"):
            self.read()
        self.audit_path.write_bytes(raw_audit)
        self.source.write_bytes(b"changed source")
        with self.assertRaisesRegex(RuntimeError, "blend SHA"):
            self.read()

    def test_duplicate_nonfinite_and_nonobject_review_json_rejected(self):
        for raw in ('{"x":1,"x":2}', '{"x":NaN}', '{"x":1e999}', '[]', 'not-json'):
            self.review_path.write_text(raw)
            with self.subTest(raw=raw), self.assertRaises(RuntimeError):
                self.read()

    def test_candidate_replay_preserves_raw_review_digest_and_rejects_changed_contract(self):
        binding = self.read()
        self.scene[P.BINDING_FIELD] = json.dumps(binding, sort_keys=True)
        audit = {"source_study_binding": binding, "adapter_sha256": P.sha(self.adapter),
                 "production_ready": False, "source_fidelity_approved": False}
        self.assertEqual(P.validate_candidate_study(self.source, self.scene, audit, self.adapter), binding)
        self.review_path.write_bytes(self.review_path.read_bytes() + b"\n")
        with self.assertRaisesRegex(RuntimeError, "binding mismatch"):
            P.validate_candidate_study(self.source, self.scene, audit, self.adapter)

    def test_reader_never_imports_or_executes_renderer_design_or_paint_helpers(self):
        original_import = builtins.__import__

        def guarded_import(name, *args, **kwargs):
            if name.startswith(("hero_penguin", "render_hero_penguin", "bpy")):
                raise AssertionError("reader imported source dependency: " + name)
            return original_import(name, *args, **kwargs)

        with patch.object(builtins, "__import__", guarded_import):
            self.assertEqual(self.read()["study_profile"], P.UNIFIED_PROFILE)


if __name__ == "__main__":
    unittest.main()
