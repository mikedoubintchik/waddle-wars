"""Host-only provenance regressions; no Blender, geometry rebuild or QA approval."""
import ast
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("v12_study_provenance", ROOT / "tools/art/hero_penguin_v12_study_provenance.py")
P = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(P)


def record_fixture(profile="face-paddles-z02", historical=False):
    baseline = {"EYE_BURY_DEPTH": .069, "EYE_ORBITAL_HEADING_FACTOR": 1.35, "EYE_CENTER_X": .181,
                "UNCHANGED_COLOR": [.1, .2, .3],
                "BILL_UPPER_SECTIONS": [[-.35, .1, .087], [-.397, .125, .090]],
                "BILL_LOWER_SECTIONS": [[-.35, .098], [-.397, .120]]}
    if profile in P.JUVENILE_PROFILES:
        # Read literal baseline assignments only. Never import/execute the
        # design, source-study helper, renderer, or a geometry cache.
        tree = ast.parse((ROOT / "tools/art/hero_penguin_v12_design.py").read_text())
        names = {edit[0] for edit in P._design_edits(profile)}
        for node in tree.body:
            target = node.targets[0] if isinstance(node, ast.Assign) and len(node.targets) == 1 else (
                node.target if isinstance(node, ast.AnnAssign) else None)
            if isinstance(target, ast.Name) and target.id in names:
                baseline[target.id] = json.loads(json.dumps(ast.literal_eval(node.value)))
    selected = copy.deepcopy(baseline)
    edits = P._design_edits(profile)
    literals = []
    for name, indices, old, new in edits:
        parent = selected
        keys = (name, *indices)
        for key in keys[:-1]:
            parent = parent[key]
        parent[keys[-1]] = new
        literals.append({"anchor": name + "".join(f"[{i}]" for i in indices), "baseline": old, "selected": new})
    record = {"schema_version": 1, "study_profile": profile, "source_only": True,
              "production_ready": False, "source_fidelity_approved": False,
              "runtime_rig_or_glb_created": False, "renderer_cohort_verified_before_geometry": True,
              "prediction_only": "Geometry appearance unapproved.", "baseline_design_constants": baseline,
              "selected_design_constants": selected,
              "parameter_overrides": {name: {"baseline": baseline[name], "selected": selected[name]}
                                      for name in {edit[0] for edit in edits}},
              "baseline_design_path": "/p/design.py", "baseline_design_sha256": "a" * 64,
              "source_renderer": "/p/render.py", "profile_helper_sha256": "b" * 64,
              "inputs": {"/p/design.py": "a" * 64, "/p/render.py": "c" * 64,
                         "/p/hero_penguin_v12_source_study.py": "b" * 64},
              "selected_design_ast_sha256": ("a" if profile == "baseline" else "d") * 64,
              "command": ["blender", "--study-profile", profile]}
    if historical:
        record["application"] = "one literal override before fresh design module execution and renderer import"
    else:
        record.update(baseline_design_ast_sha256="a" * 64, design_literal_overrides=literals,
                      baseline_renderer_path="/p/render.py", baseline_renderer_sha256="c" * 64,
                      baseline_renderer_ast_sha256="c" * 64,
                      selected_renderer_ast_sha256=("e" if P._renderer_edits(profile) else "c") * 64,
                      renderer_literal_overrides=P._renderer_edits(profile))
    if profile == "orbital-saddle-z04":
        record.update(P.saddle_declarations(), orbital_saddle_helper_sha256="f" * 64)
        record["inputs"]["/p/hero_penguin_v12_orbital_saddle.py"] = "f" * 64
    if profile in P.JUVENILE_PROFILES:
        record.update(P.juvenile_declarations(profile), juvenile_orbit_helper_sha256="b" * 64)
    return record


class StudyProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.source = Path(self.temp.name) / "hero_penguin_v12_source_proof.blend"
        self.source.write_bytes(b"synthetic immutable saved source, not a Blender fixture")
        self.adapter = Path(self.temp.name) / "adapter.py"
        self.adapter.write_text("# synthetic source only\n")
        self.record = record_fixture()

    def save(self, record=None):
        record = self.record if record is None else record
        raw = json.dumps(record, sort_keys=True)
        self.source.with_name("source_study_inputs.json").write_text(raw)
        outputs = {self.source.name: P.sha(self.source)}
        views = ["front", "threequarter", "true_side"]
        outputs.update({f"hero_penguin_v12_blender_{view}.png": "f" * 64 for view in views})
        audit = dict(record, inputs_unchanged=True, outputs=outputs, rendered_views=views)
        self.source.with_name("source_study_audit.json").write_text(json.dumps(audit))
        return {"source_study_profile": record["study_profile"], "source_study_json": raw,
                "source_study_production_ready": False}

    def test_all_supported_profiles_and_historical_z01(self):
        for profile in P.PROFILES:
            binding = P.read_source_study(self.source, self.save(record_fixture(profile)))
            self.assertEqual(binding["study_profile"], profile)
            self.assertEqual(binding["source_blend_sha256"], P.sha(self.source))
            self.assertFalse(binding["source_fidelity_approved"])
            self.assertFalse(binding["source_cover_scope"]["study_source_cover_approved"])
        binding = P.read_source_study(self.source, self.save(record_fixture("eye-aperture-z01", historical=True)))
        self.assertIn("renderer AST not recorded", binding["ast_evidence"])
        self.assertNotIn("selected_renderer_ast_sha256", binding["record"])

    def test_wholly_absent_legacy_is_unchanged(self):
        self.assertIsNone(P.read_source_study(self.source, {}))
        self.assertIsNone(P.validate_candidate_study(self.source, {}, {}, self.adapter))
        self.assertEqual(P.binding_input_hashes(self.source, None), {})

    def test_partial_metadata_never_downgrades_to_legacy(self):
        for field in P.SCENE_FIELDS + (P.BINDING_FIELD,):
            with self.subTest(field=field), self.assertRaisesRegex(RuntimeError, "partial"):
                P.read_source_study(self.source, {field: ""})
        scene = self.save()
        for field in P.SCENE_FIELDS:
            partial = dict(scene)
            del partial[field]
            with self.assertRaisesRegex(RuntimeError, "partial"):
                P.read_source_study(self.source, partial)
        self.source.with_name("source_study_inputs.json").unlink()
        with self.assertRaisesRegex(RuntimeError, "partial"):
            P.read_source_study(self.source, scene)

    def test_scene_json_profile_status_and_audit_must_agree(self):
        scene = self.save()
        for field, value in (("source_study_json", "{}"), ("source_study_profile", "baseline"),
                             ("source_study_production_ready", 0), ("source_study_production_ready", True)):
            with self.subTest(field=field), self.assertRaises(RuntimeError):
                P.read_source_study(self.source, dict(scene, **{field: value}))
        path = self.source.with_name("source_study_audit.json")
        audit = json.loads(path.read_text())
        audit["selected_renderer_ast_sha256"] = "f" * 64
        path.write_text(json.dumps(audit))
        with self.assertRaisesRegex(RuntimeError, "completed audit"):
            P.read_source_study(self.source, scene)

    def test_changed_blend_and_incomplete_completion_fail(self):
        scene = self.save()
        self.source.write_bytes(b"changed")
        with self.assertRaisesRegex(RuntimeError, "blend SHA"):
            P.read_source_study(self.source, scene)
        for field, value in (("inputs_unchanged", 1), ("rendered_views", ["front"]), ("outputs", {})):
            scene = self.save()
            path = self.source.with_name("source_study_audit.json")
            audit = json.loads(path.read_text())
            audit[field] = value
            path.write_text(json.dumps(audit))
            with self.assertRaises(RuntimeError):
                P.read_source_study(self.source, scene)

    def test_unknown_profile_and_boolean_aliases_fail(self):
        for field, value in (("study_profile", "z03"), ("study_profile", []), ("schema_version", True),
                             ("production_ready", 0), ("source_fidelity_approved", 0),
                             ("source_only", 1), ("runtime_rig_or_glb_created", 0)):
            record = copy.deepcopy(self.record)
            record[field] = value
            with self.subTest(field=field), self.assertRaises(RuntimeError):
                P.validate_record(record)

    def test_undeclared_color_or_literal_change_fails(self):
        for name, value in (("EYE_BURY_DEPTH", .063), ("UNCHANGED_COLOR", [.2, .2, .3])):
            record = copy.deepcopy(self.record)
            record["selected_design_constants"][name] = value
            with self.assertRaisesRegex(RuntimeError, "outside declared"):
                P.validate_record(record)
        for field in ("parameter_overrides", "design_literal_overrides", "renderer_literal_overrides"):
            record = copy.deepcopy(self.record)
            record[field] = {} if field == "parameter_overrides" else []
            with self.assertRaises(RuntimeError):
                P.validate_record(record)

    def test_ast_cohort_cannot_be_partial_or_relabelled(self):
        for field in P.FULL_COHORT_FIELDS:
            record = copy.deepcopy(self.record)
            del record[field]
            with self.assertRaisesRegex(RuntimeError, "partial AST"):
                P.validate_record(record)
        for field, value in (("selected_design_ast_sha256", "a" * 64),
                             ("selected_renderer_ast_sha256", "c" * 64),
                             ("baseline_renderer_sha256", "f" * 64),
                             ("selected_renderer_ast_sha256", "NOT_A_HASH")):
            record = copy.deepcopy(self.record)
            record[field] = value
            with self.assertRaises(RuntimeError):
                P.validate_record(record)
        with self.assertRaisesRegex(RuntimeError, "full AST"):
            P.validate_record(record_fixture("face-paddles-z02", historical=True))

    def test_historical_helper_hash_is_not_compared_to_mutable_current_helper(self):
        self.assertIn("historical-z01", P.validate_record(record_fixture("eye-aperture-z01", historical=True)))
        record = copy.deepcopy(self.record)
        record["inputs"]["/p/hero_penguin_v12_source_study.py"] = "f" * 64
        with self.assertRaisesRegex(RuntimeError, "helper input"):
            P.validate_record(record)

    def test_json_duplicate_nonfinite_and_wrong_root_rejected(self):
        for raw in ('{"x":1,"x":2}', '{"x":NaN}', '{"x":1e999}', '[]', 'not-json', None):
            with self.subTest(raw=raw), self.assertRaises(RuntimeError):
                P.parse_json(raw)

    def test_command_profile_must_be_unique_and_matching(self):
        for command in ([], ["--study-profile"], ["--study-profile", "baseline"],
                        ["--study-profile", "face-paddles-z02", "--study-profile", "face-paddles-z02"], [1]):
            record = dict(self.record, command=command)
            with self.assertRaisesRegex(RuntimeError, "command profile"):
                P.validate_record(record)

    def test_saddle_requires_every_expression_recipe_and_helper_binding(self):
        valid = record_fixture("orbital-saddle-z04")
        P.validate_record(valid)
        for field in (*P.saddle_declarations(), "orbital_saddle_helper_sha256"):
            record = copy.deepcopy(valid)
            del record[field]
            with self.subTest(field=field), self.assertRaises(RuntimeError):
                P.validate_record(record)
        record = copy.deepcopy(valid)
        record["orbital_saddle_recipe"]["lower_nasal_sweep_m"] = .1
        with self.assertRaisesRegex(RuntimeError, "recipe mismatch"):
            P.validate_record(record)
        record = copy.deepcopy(valid)
        record["inputs"]["/p/hero_penguin_v12_orbital_saddle.py"] = "e" * 64
        with self.assertRaisesRegex(RuntimeError, "helper input"):
            P.validate_record(record)

    def test_saddle_cannot_smuggle_expressions_into_old_profile(self):
        for profile in ("baseline", "eye-aperture-z01", "face-paddles-z02", "orbital-heading-z03"):
            record = record_fixture(profile)
            record["design_expression_overrides"] = P.saddle_declarations()["design_expression_overrides"]
            with self.assertRaisesRegex(RuntimeError, "undeclared saddle"):
                P.validate_record(record)

    def test_juvenile_cohorts_preserve_distinct_gaze_and_all_declared_edits(self):
        for profile, gaze in zip(P.JUVENILE_PROFILES, (1.68, 2.40)):
            record = record_fixture(profile)
            self.assertEqual(len(record["design_literal_overrides"]), 106)
            self.assertEqual(len(record["renderer_literal_overrides"]), 3)
            self.assertEqual(record["selected_design_constants"]["EYE_GAZE_TARGET"][2], gaze)
            self.assertIn("full recorded", P.validate_record(record))
            # Updating every repeated declaration must still fail against the
            # independent expected cohort, even when scene/sidecars would agree.
            changed = copy.deepcopy(record)
            changed["selected_design_constants"]["EYE_GAZE_TARGET"][2] = 3.0
            changed["parameter_overrides"]["EYE_GAZE_TARGET"]["selected"][2] = 3.0
            next(item for item in changed["design_literal_overrides"]
                 if item["anchor"] == "EYE_GAZE_TARGET[2]")["selected"] = 3.0
            with self.assertRaisesRegex(RuntimeError, "outside declared"):
                P.validate_record(changed)

    def test_juvenile_requires_exact_expressions_imports_recipes_and_helper_hash(self):
        for profile in P.JUVENILE_PROFILES:
            valid = record_fixture(profile)
            for field in (*P.juvenile_declarations(profile), "juvenile_orbit_helper_sha256"):
                changed = copy.deepcopy(valid)
                del changed[field]
                with self.subTest(profile=profile, field=field), self.assertRaises(RuntimeError):
                    P.validate_record(changed)
            for field in ("design_expression_overrides", "renderer_expression_overrides"):
                changed = copy.deepcopy(valid)
                changed[field][0]["selected"] = "unapproved_expression()"
                with self.assertRaisesRegex(RuntimeError, "juvenile expression"):
                    P.validate_record(changed)
            changed = copy.deepcopy(valid)
            changed["juvenile_orbit_helper_sha256"] = "f" * 64
            with self.assertRaisesRegex(RuntimeError, "juvenile helper input"):
                P.validate_record(changed)
        changed = record_fixture("juvenile-socket-z06")
        changed["socket_relief_recipe"]["maximum_inward_m"] = .1
        with self.assertRaisesRegex(RuntimeError, "juvenile expression/recipe"):
            P.validate_record(changed)

    def test_juvenile_cannot_relabel_legacy_or_smuggle_socket_recipe(self):
        for profile in ("baseline", "eye-aperture-z01", "face-paddles-z02", "orbital-heading-z03"):
            changed = record_fixture(profile)
            changed["juvenile_orbit_helper_sha256"] = "b" * 64
            with self.assertRaisesRegex(RuntimeError, "undeclared"):
                P.validate_record(changed)
        for field in ("design_added_imports", "socket_relief_recipe"):
            changed = record_fixture("juvenile-sculpt-z05")
            changed[field] = P.juvenile_declarations("juvenile-socket-z06")[field]
            with self.assertRaisesRegex(RuntimeError, "undeclared socket"):
                P.validate_record(changed)
        changed = record_fixture("juvenile-socket-z06")
        changed["study_profile"] = "juvenile-sculpt-z05"
        changed["command"][-1] = "juvenile-sculpt-z05"
        with self.assertRaisesRegex(RuntimeError, "outside declared"):
            P.validate_record(changed)

    def test_juvenile_binding_survives_candidate_handoff_without_approval(self):
        for profile in P.JUVENILE_PROFILES:
            scene = self.save(record_fixture(profile))
            binding = P.read_source_study(self.source, scene)
            scene[P.BINDING_FIELD] = json.dumps(binding)
            audit = {"source_study_binding": binding, "adapter_sha256": P.sha(self.adapter),
                     "production_ready": False, "source_fidelity_approved": False}
            self.assertEqual(P.validate_candidate_study(self.source, scene, audit, self.adapter), binding)
            self.assertFalse(binding["source_cover_scope"]["study_source_cover_approved"])
            self.assertEqual(binding["source_cover_scope"]["coordinate_bands_origin"],
                             "X/Y source-space measurements only")
            P.require_component_masks(binding, self.mask_source(values=[(0, 0, 0, 1), (.2, .3, .4, 1)]))
            with self.assertRaisesRegex(RuntimeError, "explicit body/wing source masks"):
                P.require_component_masks(binding, self.mask_source())

    def candidate_fixture(self):
        scene = self.save()
        binding = P.read_source_study(self.source, scene)
        scene[P.BINDING_FIELD] = json.dumps(binding)
        audit = {"source_study_binding": binding, "adapter_sha256": P.sha(self.adapter),
                 "production_ready": False, "source_fidelity_approved": False}
        return scene, binding, audit

    def test_candidate_report_scene_and_current_adapter_all_match(self):
        scene, binding, audit = self.candidate_fixture()
        self.assertEqual(P.validate_candidate_study(self.source, scene, audit, self.adapter), binding)
        self.assertEqual(len(P.binding_input_hashes(self.source, binding)), 3)
        self.adapter.write_text("# changed adapter\n")
        with self.assertRaisesRegex(RuntimeError, "adapter SHA"):
            P.validate_candidate_study(self.source, scene, audit, self.adapter)

    def test_candidate_omitted_altered_or_approved_study_fails(self):
        scene, binding, audit = self.candidate_fixture()
        for field in ("source_study_binding", "adapter_sha256", "source_fidelity_approved"):
            changed = dict(audit)
            del changed[field]
            with self.assertRaises(RuntimeError):
                P.validate_candidate_study(self.source, scene, changed, self.adapter)
        changed = copy.deepcopy(audit)
        changed["source_study_binding"]["record"]["study_profile"] = "baseline"
        with self.assertRaisesRegex(RuntimeError, "binding mismatch"):
            P.validate_candidate_study(self.source, scene, changed, self.adapter)
        del scene[P.BINDING_FIELD]
        with self.assertRaisesRegex(RuntimeError, "binding mismatch"):
            P.validate_candidate_study(self.source, scene, audit, self.adapter)

    def test_legacy_cannot_carry_study_report_without_scene_sidecars(self):
        with self.assertRaisesRegex(RuntimeError, "without source study"):
            P.validate_candidate_study(self.source, {}, {"source_study_binding": None}, self.adapter)

    def mask_source(self, name="HeroBodyTest", values=None, contract="feather-palette-weights-v1"):
        class Source(dict):
            pass
        obj = Source(source_mask_contract=contract) if contract is not None else Source()
        obj.name = name
        obj.data = SimpleNamespace(vertices=[0, 1], color_attributes={})
        if values is not None:
            obj.data.color_attributes["SourceSemanticMasks"] = SimpleNamespace(domain="POINT", data_type="FLOAT_COLOR",
                data=[SimpleNamespace(color=value) for value in values])
        return obj

    def test_study_body_and_wings_require_exact_explicit_masks(self):
        for name in ("HeroBodyTest", "PaddleWing+1", "PaddleWing-1.001"):
            obj = self.mask_source(name, [(0, 0, 0, 1), (.2, .3, .4, 1)])
            P.require_component_masks({}, obj)
            for changed in (self.mask_source(name), self.mask_source(name, [(0, 0, 0, 1)], contract=None),
                            self.mask_source(name, [(0, 0, 0, 0)] * 2),
                            self.mask_source(name, [(float("nan"), 0, 0, 1)] * 2),
                            self.mask_source(name, [(.8, .4, 0, 1)] * 2)):
                with self.assertRaises(RuntimeError):
                    P.require_component_masks({}, changed)
        P.require_component_masks(None, self.mask_source(contract=None))
        P.require_component_masks({}, self.mask_source("Iris+1", contract=None))

    def test_integration_guards_precede_replay_and_copy_bindings(self):
        candidate = (ROOT / "tools/art/build_hero_penguin_v12_candidate.py").read_text()
        baker = (ROOT / "tools/art/bake_hero_penguin_v12_atlas.py").read_text()
        main = candidate[candidate.index("def main()") :]
        self.assertLess(main.index("read_source_study("), main.index("reduce_component("))
        self.assertLess(main.index("require_component_masks("), main.index("reduce_component("))
        main = baker[baker.index("def main()") :]
        self.assertEqual(main.count("validate_candidate_study("), 2)  # candidate and repair checkpoint
        self.assertLess(main.index("validate_candidate_study("), main.index("recover_components("))
        self.assertLess(main.index("require_component_masks("), main.index("source_semantics("))
        self.assertIn('binding["source_study_binding"] = study_binding', main)
        for text in (candidate, baker):
            self.assertIn('report["source_study_binding"] = study_binding', text)
            self.assertIn('"source_fidelity_approved": False', text)
        tree = ast.parse(Path(P.__file__).read_text())
        imported = [node.name for node in ast.walk(tree) if isinstance(node, ast.alias)]
        self.assertFalse(any("bpy" in name or "source_study" in name or "design" in name for name in imported))


if __name__ == "__main__":
    unittest.main()
