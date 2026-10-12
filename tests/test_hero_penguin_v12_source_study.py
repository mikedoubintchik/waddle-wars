"""Host-only study/cohort guards; no Blender, renderer, or art approval."""
from __future__ import annotations

import ast
import builtins
import contextlib
import copy
import importlib.util
import io
from pathlib import Path
import sys
import tempfile
from types import ModuleType
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/art"))
import hero_penguin_v12_source_study as study
import render_hero_penguin_v12_source_study as launcher


def renderer_for(design):
    renderer = ModuleType("fake_source_renderer")
    for name, value in study.constants(design).items():
        setattr(renderer, name, value)
    for name in study.SHARED_FUNCTIONS:
        setattr(renderer, name, getattr(design, name))
    return renderer


class SourceStudyTests(unittest.TestCase):
    def test_default_baseline_is_unchanged(self):
        before = study.DESIGN_PATH.read_bytes()
        baseline, record = study.fresh_design()
        self.assertEqual(baseline.EYE_BURY_DEPTH, .069)
        self.assertEqual(record["parameter_overrides"], {})
        self.assertEqual(record["analytical_linear_aperture_ratio"], 1)
        self.assertEqual(study.DESIGN_PATH.read_bytes(), before)

    def test_z01_changes_exactly_one_literal_constant(self):
        baseline, _ = study.fresh_design("baseline")
        selected, record = study.fresh_design("eye-aperture-z01")
        changed = {name for name, value in study.constants(baseline).items()
                   if study.constants(selected)[name] != value}
        self.assertEqual(changed, {"EYE_BURY_DEPTH"})
        self.assertEqual(selected.EYE_BURY_DEPTH, .064)
        self.assertEqual(record["parameter_overrides"], {"EYE_BURY_DEPTH": {"baseline": .069, "selected": .064}})
        self.assertFalse(record["source_fidelity_approved"])
        self.assertFalse(record["production_ready"])

    def test_defaults_and_all_shared_functions_use_selected_globals(self):
        selected, _ = study.fresh_design("eye-aperture-z01")
        self.assertEqual(selected.eye_tangent_aperture_radii.__defaults__, (selected.EYE_RADII, .064))
        self.assertEqual(selected.eye_tangent_aperture_radii(),
                         selected.eye_tangent_aperture_radii(selected.EYE_RADII, .064))
        for name in study.SHARED_FUNCTIONS:
            function = getattr(selected, name)
            self.assertIs(getattr(function, "__wrapped__", function).__globals__, selected.__dict__)
        self.assertEqual(selected.eye_surface_frame.cache_info().currsize, 0)

    def test_aperture_prediction_explicitly_not_visual_acceptance(self):
        _, record = study.fresh_design("eye-aperture-z01")
        self.assertGreater(record["analytical_linear_aperture_ratio"], 1.09)
        self.assertLess(record["analytical_linear_aperture_ratio"], 1.11)
        self.assertIn("unapproved", record["prediction_only"])
        self.assertFalse(record["runtime_rig_or_glb_created"])

    def test_unknown_profile_rejected_before_module_publication(self):
        sentinel = ModuleType("existing_design")
        previous = sys.modules.get(study.DESIGN_MODULE)
        sys.modules[study.DESIGN_MODULE] = sentinel
        try:
            with self.assertRaisesRegex(ValueError, "unknown source study"):
                with study.installed_design("typo-z01"):
                    self.fail("invalid profile entered context")
            self.assertIs(sys.modules[study.DESIGN_MODULE], sentinel)
        finally:
            if previous is None:
                sys.modules.pop(study.DESIGN_MODULE, None)
            else:
                sys.modules[study.DESIGN_MODULE] = previous

    def test_atomic_restore_on_renderer_failure(self):
        prior, _ = study.fresh_design()
        previous = sys.modules.get(study.DESIGN_MODULE)
        sys.modules[study.DESIGN_MODULE] = prior
        try:
            with self.assertRaisesRegex(RuntimeError, "simulated"):
                with study.installed_design("eye-aperture-z01") as (selected, _):
                    self.assertIs(sys.modules[study.DESIGN_MODULE], selected)
                    self.assertIsNot(selected, prior)
                    self.assertEqual(prior.EYE_BURY_DEPTH, .069)
                    raise RuntimeError("simulated source renderer failure")
            self.assertIs(sys.modules[study.DESIGN_MODULE], prior)
            self.assertEqual(prior.EYE_BURY_DEPTH, .069)
            self.assertEqual(prior.eye_surface_frame.cache_info().currsize, 0)
        finally:
            if previous is None:
                sys.modules.pop(study.DESIGN_MODULE, None)
            else:
                sys.modules[study.DESIGN_MODULE] = previous

    def test_changed_or_duplicate_baseline_literal_fails_closed(self):
        original = study.DESIGN_PATH.read_text()
        for text in (original.replace("EYE_BURY_DEPTH = 0.069", "EYE_BURY_DEPTH = 0.070"),
                     original + "\nEYE_BURY_DEPTH = 0.069\n",
                     original.replace("EYE_BURY_DEPTH = 0.069", "EYE_BURY_DEPTH = float('0.069')")):
            with tempfile.TemporaryDirectory() as folder:
                path = Path(folder) / "design.py"
                path.write_text(text)
                with self.assertRaisesRegex(ValueError, "baseline eye-depth literal changed"):
                    study.fresh_design("eye-aperture-z01", path)
                self.assertEqual(path.read_text(), text)

    def test_stale_renderer_constants_and_functions_rejected(self):
        selected, _ = study.fresh_design("eye-aperture-z01")
        baseline, _ = study.fresh_design()
        renderer = renderer_for(selected)
        study.require_renderer_cohort(renderer, selected)
        renderer.EYE_BURY_DEPTH = .069
        with self.assertRaisesRegex(RuntimeError, "disagree"):
            study.require_renderer_cohort(renderer, selected)
        renderer = renderer_for(selected)
        renderer.sculpt_body_field = baseline.sculpt_body_field
        with self.assertRaisesRegex(RuntimeError, "stale design function"):
            study.require_renderer_cohort(renderer, selected)

    def test_independent_fresh_cohorts_do_not_share_cache(self):
        first, _ = study.fresh_design("eye-aperture-z01")
        second, _ = study.fresh_design("eye-aperture-z01")
        self.assertIsNot(first.eye_surface_frame, second.eye_surface_frame)
        self.assertIsNot(first.eye_surface_frame.__wrapped__.__globals__, second.eye_surface_frame.__wrapped__.__globals__)

    def test_source_and_transformed_ast_hashes_are_recorded(self):
        _, baseline = study.fresh_design()
        _, selected = study.fresh_design("eye-aperture-z01")
        self.assertEqual(selected["baseline_design_sha256"], study.sha_bytes(study.DESIGN_PATH.read_bytes()))
        self.assertEqual(selected["baseline_design_sha256"], baseline["baseline_design_sha256"])
        self.assertNotEqual(selected["selected_design_ast_sha256"], baseline["selected_design_ast_sha256"])
        self.assertEqual(len(selected["profile_helper_sha256"]), 64)

    def test_launcher_profile_opt_in_and_output_quarantine(self):
        args = launcher.parse_args(["--output-dir", "qa_shots/hero/fresh-host-example"])
        self.assertEqual(args.study_profile, "baseline")
        self.assertEqual(args.feather_recipe, "baseline")
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            launcher.parse_args(["--study-profile", "typo", "--output-dir", "qa_shots/hero/fresh-host-example"])
        for path in (ROOT, launcher.QA, ROOT / "art_src/characters"):
            with self.assertRaisesRegex(ValueError, "fresh dedicated"):
                launcher.output_path(path)

    def test_launcher_does_not_replace_geometry_or_export_runtime(self):
        text = Path(launcher.__file__).read_text()
        self.assertIn("with study.installed_design(args.study_profile)", text)
        self.assertLess(text.index("study.renderer_syntax(args.study_profile"), text.index("with study.installed_design(args.study_profile)"))
        self.assertLess(text.index("with study.installed_design(args.study_profile)"), text.index('exec(compile(renderer_tree'))
        self.assertLess(text.index("study.require_renderer_cohort(renderer, design)"), text.index("renderer.main()"))
        self.assertIn("source_study_inputs.json", text)
        self.assertIn("source_study_audit.json", text)
        for forbidden in ("renderer.voxel_fuse_body =", "renderer.body_paint =", "renderer.add_eye_set =",
                          "export_scene.gltf", "subprocess", "bpy.ops.wm.open_mainfile"):
            self.assertNotIn(forbidden, text)

    def test_baseline_and_z01_design_semantic_asts_unchanged(self):
        # Independent reconstruction of the frozen Z01 literal-only transform.
        for profile, depth in (("baseline", .069), ("eye-aperture-z01", .064)):
            tree = ast.parse(study.DESIGN_PATH.read_bytes())
            node = next(node for node in tree.body if isinstance(node, ast.Assign)
                        and any(isinstance(target, ast.Name) and target.id == "EYE_BURY_DEPTH" for target in node.targets))
            node.value = ast.copy_location(ast.Constant(depth), node.value)
            _, record = study.fresh_design(profile)
            self.assertEqual(record["selected_design_ast_sha256"], study.ast_digest(tree))

    def test_baseline_and_z01_renderer_ast_unchanged(self):
        original = ast.parse(launcher.RENDERER.read_bytes())
        for profile in ("baseline", "eye-aperture-z01"):
            actual, record = study.renderer_syntax(profile, launcher.RENDERER)
            self.assertEqual(study.ast_digest(actual), study.ast_digest(original))
            self.assertEqual(record["renderer_literal_overrides"], [])

    def test_z02_only_declared_design_cells(self):
        baseline, _ = study.fresh_design()
        selected, record = study.fresh_design("face-paddles-z02")
        expected = study.constants(baseline)
        expected["EYE_BURY_DEPTH"] = .064
        upper = [list(row) for row in expected["BILL_UPPER_SECTIONS"]]
        lower = [list(row) for row in expected["BILL_LOWER_SECTIONS"]]
        upper[0][2], upper[1][2], lower[1][1] = .105, .108, .108
        expected["BILL_UPPER_SECTIONS"] = tuple(tuple(row) for row in upper)
        expected["BILL_LOWER_SECTIONS"] = tuple(tuple(row) for row in lower)
        self.assertEqual(study.constants(selected), expected)
        self.assertEqual(len(record["design_literal_overrides"]), 4)
        self.assertEqual(selected.eye_tangent_aperture_radii.__defaults__, (selected.EYE_RADII, .064))

    def test_z02_renderer_changes_exactly_seven_scoped_float_leaves(self):
        before = ast.parse(launcher.RENDERER.read_bytes())
        after, record = study.renderer_syntax("face-paddles-z02", launcher.RENDERER)

        def differences(first, second):
            self.assertIs(type(first), type(second))
            if isinstance(first, ast.AST):
                left, right = dict(ast.iter_fields(first)), dict(ast.iter_fields(second))
                self.assertEqual(left.keys(), right.keys())
                return [pair for name in left for pair in differences(left[name], right[name])]
            if isinstance(first, list):
                self.assertEqual(len(first), len(second))
                return [pair for left, right in zip(first, second) for pair in differences(left, right)]
            return [(first, second)] if first != second else []

        changes = differences(before, after)
        self.assertCountEqual(changes, [(.120, .108), (.125, .118)] * 2
                              + [(.039, .050), (.026, .036), (.017, .025)])
        self.assertEqual(len(record["renderer_literal_overrides"]), 7)
        self.assertNotEqual(record["baseline_renderer_ast_sha256"], record["selected_renderer_ast_sha256"])
        self.assertEqual(record["baseline_renderer_sha256"], study.sha_bytes(launcher.RENDERER.read_bytes()))

    def test_z02_unknown_or_duplicate_renderer_anchors_fail(self):
        original = launcher.RENDERER.read_text()
        variants = (
            original.replace("def body_paint(point: Vector):", "def body_paint_renamed(point: Vector):"),
            original + "\ndef body_paint(point):\n    return point\n",
            original.replace("    orbit = min(", "    orbit = None\n    orbit = min(", 1),
            original.replace("0.120, 0.125", "0.121, 0.125", 1),
            original.replace("        width_keys = ((0.0, 0.055)", "        width_keys = ()\n        width_keys = ((0.0, 0.055)", 1),
            original.replace("(0.84, 0.039)", "(0.84, 0.040)", 1),
        )
        for text in variants:
            self.assertNotEqual(text, original)
            with tempfile.TemporaryDirectory() as folder:
                path = Path(folder) / "renderer.py"
                path.write_text(text)
                with self.assertRaises(ValueError):
                    study.renderer_syntax("face-paddles-z02", path)
                self.assertEqual(path.read_text(), text)
        with self.assertRaisesRegex(ValueError, "unknown source study"):
            study.renderer_syntax("face-paddles-z999", launcher.RENDERER)

    def test_z02_changed_bill_and_annotated_duplicate_anchors_fail(self):
        original = study.DESIGN_PATH.read_text()
        for text in (original.replace("(-0.351, 0.100, 0.087, 1.389)", "(-0.351, 0.100, 0.088, 1.389)"),
                     original + "\nBILL_LOWER_SECTIONS: tuple = ()\n"):
            self.assertNotEqual(text, original)
            with tempfile.TemporaryDirectory() as folder:
                path = Path(folder) / "design.py"
                path.write_text(text)
                with self.assertRaises(ValueError):
                    study.fresh_design("face-paddles-z02", path)
                self.assertEqual(path.read_text(), text)

    def test_profile_parsing_accepts_z02_without_changing_default(self):
        args = launcher.parse_args(["--study-profile", "face-paddles-z02", "--output-dir", "qa_shots/hero/example-z02"])
        self.assertEqual(args.study_profile, "face-paddles-z02")
        self.assertEqual(launcher.parse_args(["--output-dir", "qa_shots/hero/example-baseline"]).study_profile, "baseline")

    def test_z03_changes_only_heading_beyond_current_z02(self):
        syntax = []

        def record_compile(tree, *args, **kwargs):
            # Snapshot before execution/mutation: compare the complete actual
            # compiled cohorts, not just their exported constant dictionaries.
            syntax.append(copy.deepcopy(tree))
            return builtins.compile(tree, *args, **kwargs)

        with patch.object(study, "compile", side_effect=record_compile, create=True):
            z02, prior = study.fresh_design("face-paddles-z02")
            z03, selected = study.fresh_design("orbital-heading-z03")
        self.assertEqual(len(syntax), 4)  # baseline + selected for each profile
        self.assertEqual(study.ast_digest(syntax[0]), study.ast_digest(syntax[2]))
        self.assertEqual(prior["selected_design_ast_sha256"], study.ast_digest(syntax[1]))
        self.assertEqual(selected["selected_design_ast_sha256"], study.ast_digest(syntax[3]))
        heading = study.assignment(syntax[3], "EYE_ORBITAL_HEADING_FACTOR", top_level=True)
        self.assertEqual(ast.literal_eval(heading.value), 2.0)
        heading.value = ast.Constant(value=1.35)
        self.assertEqual(study.ast_digest(syntax[3]), study.ast_digest(syntax[1]))
        expected = study.constants(z02)
        expected["EYE_ORBITAL_HEADING_FACTOR"] = 2.0
        self.assertEqual(study.constants(z03), expected)
        self.assertEqual(len(selected["design_literal_overrides"]), 5)
        self.assertEqual(selected["design_literal_overrides"][:-1], prior["design_literal_overrides"])
        self.assertEqual(selected["design_literal_overrides"][-1],
            {"anchor": "EYE_ORBITAL_HEADING_FACTOR", "baseline": 1.35, "selected": 2.0})
        # Identical raw sources serialize differently with host Python 3.12
        # and pinned Blender Python 3.13. Keep the capture-runtime golden pin
        # exact; every runtime still checks the complete compiled AST delta.
        if sys.version_info[:2] == (3, 13):
            self.assertEqual(prior["selected_design_ast_sha256"],
                             "6465aa042eddb93db2fa1d14b7d3126db9b85748e0d21598c608858450883dbb")
        self.assertFalse(selected["source_fidelity_approved"])
        self.assertFalse(selected["production_ready"])

    def test_z03_renderer_ast_exactly_equals_z02(self):
        z02, prior = study.renderer_syntax("face-paddles-z02", launcher.RENDERER)
        z03, selected = study.renderer_syntax("orbital-heading-z03", launcher.RENDERER)
        self.assertEqual(study.ast_digest(z03), study.ast_digest(z02))
        self.assertEqual(selected["renderer_literal_overrides"], prior["renderer_literal_overrides"])
        self.assertEqual(prior["selected_renderer_ast_sha256"], study.ast_digest(z02))
        self.assertEqual(selected["selected_renderer_ast_sha256"], study.ast_digest(z03))
        self.assertEqual(prior["baseline_renderer_sha256"],
                         study.sha_bytes(launcher.RENDERER.read_bytes()))
        if sys.version_info[:2] == (3, 13):
            self.assertEqual(prior["selected_renderer_ast_sha256"],
                             "2e46a7e329885cb8ef7f10fcb9edbca490c30975c17830b2053bf2e5de69c441")

    def test_z03_complete_frame_cohort_and_cache_remain_fresh(self):
        selected, _ = study.fresh_design("orbital-heading-z03")
        renderer = renderer_for(selected)
        study.require_renderer_cohort(renderer, selected)
        for name in ("eye_surface_frame", "sculpt_body_field", "eye_gaze_center", "upper_lid_pigment_weight"):
            function = getattr(renderer, name)
            self.assertIs(getattr(function, "__wrapped__", function).__globals__, selected.__dict__)
        self.assertEqual(selected.eye_surface_frame.cache_info().currsize, 0)
        renderer.EYE_ORBITAL_HEADING_FACTOR = 1.35
        with self.assertRaisesRegex(RuntimeError, "disagree"):
            study.require_renderer_cohort(renderer, selected)

    def test_z03_invalid_or_duplicate_heading_anchor_fails(self):
        original = study.DESIGN_PATH.read_text()
        for text in (original.replace("EYE_ORBITAL_HEADING_FACTOR = 1.35", "EYE_ORBITAL_HEADING_FACTOR = 1.36"),
                     original + "\nEYE_ORBITAL_HEADING_FACTOR = 1.35\n"):
            with tempfile.TemporaryDirectory() as folder:
                path = Path(folder) / "design.py"
                path.write_text(text)
                with self.assertRaises(ValueError):
                    study.fresh_design("orbital-heading-z03", path)
                self.assertEqual(path.read_text(), text)

    def test_z03_cli_opt_in_keeps_baseline_default(self):
        args = launcher.parse_args(["--study-profile", "orbital-heading-z03",
                                    "--output-dir", "qa_shots/hero/example-z03"])
        self.assertEqual(args.study_profile, "orbital-heading-z03")
        self.assertEqual(launcher.parse_args(["--output-dir", "qa_shots/hero/example-default"]).study_profile, "baseline")

    def test_real_source_validator_is_read_only_and_disables_scripts(self):
        text = (ROOT / "tests/hero_v12_source_study_blender_test.py").read_text()
        tree = ast.parse(text)
        calls = [ast.unparse(node.func) for node in ast.walk(tree) if isinstance(node, ast.Call)]
        for forbidden in ("write_text", "write_bytes", "save_as_mainfile", "render.render", "export_scene", "reduce_component"):
            self.assertFalse(any(forbidden in call for call in calls))
        self.assertIn("use_scripts=False", text)
        self.assertIn('"--disable-autoexec" not in sys.argv', text)
        self.assertIn("read_source_study(source, bpy.context.scene)", text)
        self.assertIn("require_component_masks(binding, obj)", text)

    def test_z04_constants_change_only_anchor_beyond_z02(self):
        z02, _ = study.fresh_design("face-paddles-z02")
        z04, record = study.fresh_design("orbital-saddle-z04")
        expected = study.constants(z02)
        expected["EYE_CENTER_X"] = .225
        self.assertEqual(study.constants(z04), expected)
        self.assertEqual(z04.EYE_ORBITAL_HEADING_FACTOR, 1.35)
        self.assertEqual(len(record["design_literal_overrides"]), 5)
        self.assertEqual(record["design_expression_overrides"], [{
            "anchor": "upper_lid_pigment_weight.upper", "baseline": study.BASELINE_LID_EXPRESSION,
            "selected": study.SADDLE_LID_EXPRESSION}])
        self.assertEqual(z04.eye_surface_frame.cache_info().currsize, 0)
        study.require_renderer_cohort(renderer_for(z04), z04)

    def test_z04_dark_lid_connects_to_hood_without_returning_to_cream(self):
        z02, _ = study.fresh_design("face-paddles-z02")
        z04, _ = study.fresh_design("orbital-saddle-z04")
        # Synthetic frame, not a mesh/NumPy geometry evaluation. Exercise each
        # real compiled pigment function while keeping the same local samples.
        frame = lambda side: ((side * .225, -.30, 1.548), (1, 0, 0), (0, -1, 0), (0, 0, 1))
        z02.eye_surface_frame = frame
        z04.eye_surface_frame = frame
        for extra in (.004, .012, .025, .045):
            point = (.225, -.30, 1.548 + z04.UPPER_FOLD_APERTURE_HEIGHT + extra)
            self.assertAlmostEqual(z04.upper_lid_pigment_weight(point), 1.0)
        point = (.225, -.30, 1.548 + z04.UPPER_FOLD_APERTURE_HEIGHT + .030)
        self.assertEqual(z02.upper_lid_pigment_weight(point), 0)
        self.assertEqual(z04.upper_lid_pigment_weight(point), 1)

    def test_z04_renderer_replaces_only_orbit_expression_and_keeps_z02_paddles(self):
        tree, record = study.renderer_syntax("orbital-saddle-z04", launcher.RENDERER)
        body = study.function_node(tree, "body_paint")
        orbit = study.assignment(body, "orbit")
        self.assertEqual(ast.unparse(orbit.value), study.SADDLE_ORBIT_EXPRESSION)
        self.assertEqual(record["renderer_expression_overrides"], [{"anchor": "body_paint.orbit",
            "baseline": study.BASELINE_ORBIT_EXPRESSION, "selected": study.SADDLE_ORBIT_EXPRESSION}])
        self.assertEqual(len(record["renderer_literal_overrides"]), 3)
        z02_tree, prior = study.renderer_syntax("face-paddles-z02", launcher.RENDERER)
        self.assertEqual(record["renderer_literal_overrides"], prior["renderer_literal_overrides"][-3:])
        # Remove exactly the new import and restore the orbit expression; then
        # the whole renderer must equal frozen Z02, not just selected functions.
        tree.body = [node for node in tree.body if not (isinstance(node, ast.ImportFrom)
                     and node.module == "hero_penguin_v12_orbital_saddle")]
        orbit.value = study.assignment(study.function_node(z02_tree, "body_paint"), "orbit").value
        self.assertEqual(study.ast_digest(tree), study.ast_digest(z02_tree))

    def test_z04_wrong_or_duplicate_expression_anchors_fail_closed(self):
        original = study.DESIGN_PATH.read_text()
        for text in (original.replace("smooth(0.010, 0.025, edge)", "smooth(0.011, 0.025, edge)"),
                     original.replace("        upper = smooth(-0.002", "        upper = 0.0\n        upper = smooth(-0.002")):
            self.assertNotEqual(text, original)
            with tempfile.TemporaryDirectory() as folder:
                path = Path(folder) / "design.py"
                path.write_text(text)
                with self.assertRaises(ValueError):
                    study.fresh_design("orbital-saddle-z04", path)
                self.assertEqual(path.read_text(), text)
        original = launcher.RENDERER.read_text()
        for text in (original + "\nsaddle_orbit_field = None\n",
                     original.replace("0.120, 0.125", "0.121, 0.125", 1)):
            with tempfile.TemporaryDirectory() as folder:
                path = Path(folder) / "renderer.py"
                path.write_text(text)
                with self.assertRaises(ValueError):
                    study.renderer_syntax("orbital-saddle-z04", path)

    def test_z04_helper_input_hash_and_cli_are_explicit(self):
        _, record = study.renderer_syntax("orbital-saddle-z04", launcher.RENDERER)
        helper = ROOT / "tools/art/hero_penguin_v12_orbital_saddle.py"
        self.assertEqual(record["orbital_saddle_helper_sha256"], study.sha_bytes(helper.read_bytes()))
        self.assertIn('if args.study_profile == "orbital-saddle-z04":', Path(launcher.__file__).read_text())
        args = launcher.parse_args(["--study-profile", "orbital-saddle-z04",
                                    "--output-dir", "qa_shots/hero/example-z04"])
        self.assertEqual(args.study_profile, "orbital-saddle-z04")

    def test_z04_metadata_matches_independent_reader_contract(self):
        import hero_penguin_v12_study_provenance as provenance
        _, design = study.fresh_design("orbital-saddle-z04")
        _, renderer = study.renderer_syntax("orbital-saddle-z04", launcher.RENDERER)
        record = {**design, **renderer}
        for field, expected in provenance.saddle_declarations().items():
            self.assertEqual(record[field], expected)


if __name__ == "__main__":
    unittest.main()
