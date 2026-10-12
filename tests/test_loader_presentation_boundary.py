#!/usr/bin/env python3
"""Source guards for the synchronous-web loader boundary, without Godot.

Companion scene_router_presentation_test.gd checks coroutine ordering against
real process-frame signals. Neither test establishes browser presentation or
uninterrupted animation; root's rendered/browser QA covers that separately.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def function_body(path: str, name: str) -> str:
    source = (ROOT / path).read_text(encoding="utf-8")
    match = re.search(rf"^func {re.escape(name)}\([^\n]*\)[^\n]*:\n(.*?)(?=^func |\Z)",
                      source, re.MULTILINE | re.DOTALL)
    if match is None:
        raise AssertionError(f"missing function {name} in {path}")
    return "\n".join(line for line in match.group(1).splitlines()
                     if not line.lstrip().startswith("#"))


class LoaderPresentationBoundaryTests(unittest.TestCase):
    def test_boot_preparation_outlives_skipped_splash(self):
        body = function_body("scripts/ui/boot.gd", "_ready")
        self.assertIn("BootWarmup.warm(SceneRouter)", body)
        self.assertNotIn("BootWarmup.warm(self)", body)
        body = function_body("scripts/utilities/scene_router.gd", "_begin_threaded_load")
        self.assertLess(body.index("while not BootWarmup.is_finished():"),
                        body.index("_request_threaded_load(scene_path)"))

    def test_runner_results_menu_callback_guards_route_inside_lambda(self):
        # The real callback is connected only with a rendered HUD. Headless
        # runner_platform tests exercise restart; this is the companion source
        # guard, not a claim that a real HUD click was rendered or delivered.
        body = function_body("scripts/runner/runner_game.gd", "_ready")
        callback = re.search(
            r"hud\.menu_pressed\.connect\(func\(\) -> void:\n"
            r"(?P<guard_indent>[ \t]+)if not SceneRouter\.is_busy\(\):\n"
            r"(?P<route_indent>[ \t]+)SceneRouter\.go_to\(Game\.SCENE_MAIN_MENU\)\)",
            body)
        self.assertIsNotNone(callback, "results-menu route must be guarded inside its lambda")
        self.assertTrue(callback.group("route_indent").startswith(callback.group("guard_indent")))
        self.assertGreater(len(callback.group("route_indent")), len(callback.group("guard_indent")))

    def test_race_orchestrator_does_not_census_before_deferred_actor_setup(self):
        body = function_body("scripts/gameplay/race.gd", "_ready")
        self.assertNotIn("ShaderWarmup.warm(", body)

    def test_grid_finalizer_starts_warmup_before_releasing_readiness(self):
        body = function_body("scripts/gameplay/race_manager.gd", "_place_on_grid")
        self.assertIn("_start_visual_warmup()", body)
        self.assertLess(body.index("_start_visual_warmup()"),
                        body.index("_grid_placed = true"))

    def test_tutorial_finalizer_starts_warmup_after_ui_before_readiness(self):
        body = function_body("scripts/gameplay/tutorial_manager.gd", "_after_spawn")
        self.assertIn("_start_visual_warmup()", body)
        self.assertLess(body.index("_define_steps()"), body.index("_start_visual_warmup()"))
        self.assertLess(body.index("_start_visual_warmup()"),
                        body.index("_spawn_ready = true"))

    def test_router_prepares_loader_before_draw_and_yields_before_resource_request(self):
        body = function_body("scripts/utilities/scene_router.gd", "_begin_threaded_load")
        steps = ["_ensure_loading_presentation()", "_set_loading_stage(",
                 "await RenderingServer.frame_post_draw",
                 "await get_tree().process_frame", "_request_threaded_load(scene_path)"]
        positions = [body.index(step) for step in steps]
        self.assertEqual(positions, sorted(positions))
        self.assertNotIn("ResourceLoader.", body)
        self.assertNotIn("_busy = false", body)
        self.assertNotIn("_presenting = false", body)

    def test_router_checks_tree_lifetime_after_both_yields(self):
        body = function_body("scripts/utilities/scene_router.gd", "_begin_threaded_load")
        for boundary in ("RenderingServer.frame_post_draw", "get_tree().process_frame"):
            self.assertIn(f"await {boundary}\n\tif not is_inside_tree():\n\t\treturn", body)

    def test_polling_starts_only_after_resource_request_returns(self):
        body = function_body("scripts/utilities/scene_router.gd", "_request_threaded_load")
        self.assertLess(body.index("_threaded_load_request(scene_path)"),
                        body.index("_pending_scene_path = scene_path"))
        self.assertIn("_change_now(scene_path)", body)
        self.assertNotIn("_set_loading_stage(", body)
        backend = function_body("scripts/utilities/scene_router.gd", "_threaded_load_request")
        self.assertIn('return ResourceLoader.load_threaded_request(scene_path, "PackedScene", true)', backend)

    def test_loader_watchdog_runs_even_without_a_pending_resource_or_draw(self):
        body = function_body("scripts/utilities/scene_router.gd", "_process")
        self.assertLess(body.index("_poll_loading_watchdog()"),
                        body.index("if _pending_scene_path.is_empty():"))
        # Public navigation delegates to the shared forward/back route owner.
        self.assertIn("_route_to(scene_path, false)",
                      function_body("scripts/utilities/scene_router.gd", "go_to"))
        for method in ("_route_to", "_begin_threaded_load", "_restart_under_cover"):
            body = function_body("scripts/utilities/scene_router.gd", method)
            self.assertIn("_start_loading_deadline()", body)

    def test_boot_splash_also_exits_draw_callback_before_sync_asset_work(self):
        body = function_body("scripts/utilities/boot_warmup.gd", "_ready")
        draw = body.index("await RenderingServer.frame_post_draw")
        next_frame = body.index("await get_tree().process_frame")
        probes = body.index("_begin_upload_probes()")
        load = body.index("await _load_front_end_assets()")
        self.assertLess(draw, next_frame)
        self.assertLess(next_frame, probes)
        self.assertLess(probes, load)
        for boundary in ("RenderingServer.frame_post_draw", "get_tree().process_frame"):
            self.assertIn(f"await {boundary}\n\tif not is_inside_tree():\n\t\treturn", body)

    def test_window_capture_keeps_real_router_presentation_and_never_fakes_draw(self):
        source = (ROOT / "tests/scene_router_loader_capture.gd").read_text(encoding="utf-8")
        nested_router = source.split("class CaptureRouter:\n", 1)[1].split("\n\nvar _router:", 1)[0]
        self.assertIn('extends "res://scripts/utilities/scene_router.gd"', nested_router)
        self.assertEqual(re.findall(r"^\tfunc (\w+)\(", nested_router, re.MULTILINE),
                         ["_request_threaded_load"])
        self.assertNotIn("frame_post_draw.emit", source)
        self.assertNotIn("force_draw", source)
        self.assertNotIn("SettingsManager.set_setting", source)
        self.assertIn("[loader-boundary] SKIP:", source)

    def test_window_capture_reads_prior_frame_at_request_entry_without_await(self):
        body = function_body("tests/scene_router_loader_capture.gd", "_capture_request_entry")
        self.assertIn("get_viewport().get_texture().get_image()", body)
        self.assertIn("image.save_png(_out)", body)
        self.assertNotIn("await ", body)
        self.assertNotIn("ResourceLoader.", body)
        self.assertIn("_process_serial > int(_last_rich_draw.get(", body)

    def test_native_diagnostic_requires_fresh_isolated_native_data(self):
        body = function_body("tests/runner_presentation_capture.gd", "_validate_environment")
        self.assertIn('custom_name.begins_with("waddle-wars-frontend-native-")', body)
        self.assertIn('OS.has_feature("android") or OS.has_feature("ios")', body)
        self.assertIn('OS.has_feature("waddle_native_trace_qa")', body)
        self.assertIn("if _cycle or OS.is_debug_build()", body)
        self.assertIn('FileAccess.file_exists(_out.get_basename() + ".json")', body)
        self.assertIn("GameConfig.is_headless()", body)

    def test_native_diagnostic_traces_real_route_without_render_readbacks(self):
        source = (ROOT / "tests/runner_presentation_capture.gd").read_text(encoding="utf-8")
        ready = function_body("tests/runner_presentation_capture.gd", "_ready")
        self.assertLess(ready.index("ShaderWarmup.perf_trace_enabled = true"),
                        ready.index("Game.start_runner()"))
        self.assertLess(ready.index("InitialVisualWarmup.perf_trace_enabled = true"),
                        ready.index("Game.start_runner()"))
        drain = function_body("tests/runner_presentation_capture.gd", "_drain_native_warmup_trace")
        self.assertIn("InitialVisualWarmup.drain_perf_trace_events()", drain)
        self.assertIn("ShaderWarmup.drain_perf_trace_events()", drain)
        draw = function_body("tests/runner_presentation_capture.gd", "_on_frame_post_draw")
        self.assertIn('if _native_trace:\n\t\t_drain_native_warmup_trace()', draw)
        self.assertLess(draw.index('"first_movement"'), draw.index('_capture("loader", row)'))
        native_draw = draw.split("if _native_trace:", 1)[1].split('if not _captures.has("loader")', 1)[0]
        self.assertIn("_first_clear_draw = row.duplicate(true)", native_draw)
        self.assertNotIn("_capture(", native_draw)
        self.assertNotIn("frame_post_draw.emit", source)
        self.assertNotIn("force_draw", source)
        self.assertNotRegex(source, r"SceneRouter\.(?:WARMUP_TIMEOUT_MSEC|_loading_deadline_msec)\s*=")

    def test_native_diagnostic_explicitly_rejects_acceptance_claims_and_cleans_flags(self):
        body = function_body("tests/runner_presentation_capture.gd", "_finish_native_trace")
        self.assertIn('"acceptance": false, "performance_acceptance": false', body)
        self.assertIn('"screenshots": false, "synthetic_input": false', body)
        self.assertIn("QA main scene bypasses boot/menu", body)
        self.assertIn("staging must verify a distinct QA package and fresh app data", body)
        self.assertIn('"violation_count": _violation_count', body)
        self.assertIn("ShaderWarmup.perf_trace_enabled = false", body)
        self.assertIn("InitialVisualWarmup.perf_trace_enabled = false", body)
        exit_body = function_body("tests/runner_presentation_capture.gd", "_exit_tree")
        self.assertIn("if _monitor and _native_trace:", exit_body)
        self.assertIn("ShaderWarmup.clear_perf_trace()", exit_body)
        self.assertIn("InitialVisualWarmup.clear_perf_trace()", exit_body)


if __name__ == "__main__":
    unittest.main()
