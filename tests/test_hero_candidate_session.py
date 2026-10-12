"""Guard the entrypoint wiring that previously let candidate reviews use fallback."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def function(text, name):
    return text.split(f"func {name}(", 1)[1].split("\nfunc ", 1)[0]


class CandidateSessionWiringTests(unittest.TestCase):
    def test_facade_selects_only_during_construction_and_checks_actual_backend(self):
        source = (ROOT / "tests/hero_v12_facade_capture.gd").read_text()
        build = function(source, "_build_stage")
        self.assertLess(build.index("_candidate_session.begin()"), build.index("super._build_stage()"))
        self.assertLess(build.index("super._build_stage()"), build.index("_candidate_session.restore()"))
        self.assertLess(build.index("_candidate_session.restore()"), build.index("_candidate_session.inspect("))
        self.assertIn("_candidate_session.restore()", function(source, "_exit_tree"))

    def test_runner_scopes_selection_around_actual_player_setup_and_retry(self):
        source = (ROOT / "tests/hero_v12_runner_capture.gd").read_text()
        ready = function(source, "_ready")
        self.assertLess(ready.index("child_entered_tree.connect(_on_game_child_entered)"), ready.index("add_child(_game)"))
        self.assertIn("if not child is RunnerPlayer:", function(source, "_on_game_child_entered"))
        self.assertIn("_candidate_session.begin()", function(source, "_on_game_child_entered"))
        player = function(source, "_on_player_child_entered")
        self.assertIn("if not child is PenguinVisual:", player)
        self.assertIn("_candidate_session.restore()", player)
        self.assertNotIn("_candidate_session.inspect(", player)
        process = function(source, "_process")
        self.assertIn("_candidate_facade != null and _game.running", process)
        self.assertLess(process.index("_candidate_session.inspect("), process.index("if _candidate_ready and _play:"))
        self.assertIn("_reject_candidate(", process)

    def test_play_cannot_bypass_initial_candidate_check(self):
        source = (ROOT / "tests/hero_v12_runner_capture.gd").read_text()
        process = function(source, "_process")
        self.assertNotIn("if _play:\n\t\treturn", process)
        self.assertIn("if _candidate_ready and _play:", process)
        self.assertIn("if _candidate_session.is_active():", process)
        self.assertIn("_candidate_session.restore()", function(source, "_exit_tree"))

    def test_session_checks_loaded_model_in_addition_to_file_hash(self):
        source = (ROOT / "tests/hero_candidate_session.gd").read_text()
        inspect = function(source, "inspect")
        for guard in ("is_authored_backend_active()", 'get_node_or_null("AuthoredHeroPenguin")',
                      'get_node_or_null("Model")', "model.scene_file_path", "model_path != CANDIDATE_PATH",
                      "missing_contract_items()", 'report.get("candidate_sha256")'):
            self.assertIn(guard, inspect)

    def test_material_contracts_reject_overrides_and_inspect_active_material(self):
        for filename in ("hero_v12_review_rig.gd", "hero_v12_atlas_review_rig.gd", "hero_runtime_review_rig.gd"):
            with self.subTest(filename=filename):
                report = function((ROOT / "tests" / filename).read_text(), "qa_material_report")
                self.assertIn("mesh.material_override != null", report)
                self.assertIn("mesh.material_overlay != null", report)
                self.assertIn("active.next_pass != null", report)
                self.assertIn("mesh.get_active_material(surface)", report)
                self.assertIn("active !=", report)
                self.assertIn('"passed": errors.is_empty()', report)

    def test_production_default_stays_procedural(self):
        source = (ROOT / "scripts/characters/penguin_visual.gd").read_text()
        self.assertIn("static var use_authored_backend_for_qa: bool = false", source)


if __name__ == "__main__":
    unittest.main()
