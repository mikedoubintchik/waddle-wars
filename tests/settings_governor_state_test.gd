extends Node
## Focused deterministic contracts for web governor readiness and recovery.

var _passes: int = 0
var _failures: int = 0
var _saved: Dictionary = {}


func _ready() -> void:
	_saved = _snapshot()
	_test_typed_readiness()
	_test_cached_single_dfs()
	_test_readiness_edges_split_windows()
	await _test_actual_paused_process_edge()
	_test_adapted_floor_timer_survives()
	_test_desktop_render_scale_ladder()
	_test_mobile_render_scale_floor()
	_test_playable_sampling_timing()
	_test_mobile_sampling_policy_unchanged()
	_test_degrade_and_recover()
	_test_explicit_choice_reset()
	_test_msaa_policy()
	_restore()
	print("[settings_governor] DONE: %d passed, %d failed" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("[settings_governor] PASS %s" % label)
		return
	_failures += 1
	print("[settings_governor] FAIL %s%s" % [
		label, ": %s" % detail if not detail.is_empty() else ""])


func _test_typed_readiness() -> void:
	var runner := RunnerGame.new()
	runner.build_finished = true
	runner._presentation_started = true
	runner.running = true
	var state := SettingsManager._quality_governor_target_for(runner, false, false)
	_check("runner_play_ready", bool(state.get("ready", false)))
	_check("runner_pause_excluded",
		not bool(SettingsManager._quality_governor_target_for(
			runner, true, false).get("ready", false)))
	_check("runner_loader_excluded",
		not bool(SettingsManager._quality_governor_target_for(
			runner, false, true).get("ready", false)))
	runner._dead = true
	runner.running = false
	_check("runner_death_excluded",
		not bool(SettingsManager._quality_governor_target_for(
			runner, false, false).get("ready", false)))
	runner.free()

	var race := RaceManager.new()
	race._grid_placed = true
	race._presentation_started = true
	race.started = false
	_check("race_countdown_excluded",
		not bool(SettingsManager._quality_governor_target_for(
			race, false, false).get("ready", false)))
	race.started = true
	_check("race_play_ready",
		bool(SettingsManager._quality_governor_target_for(
			race, false, false).get("ready", false)))
	race._completed = true
	_check("race_results_excluded",
		not bool(SettingsManager._quality_governor_target_for(
			race, false, false).get("ready", false)))
	race.free()

	var endless := EndlessManager.new()
	endless._grid_placed = true
	endless._presentation_started = true
	endless.started = true
	_check("endless_play_ready",
		bool(SettingsManager._quality_governor_target_for(
			endless, false, false).get("ready", false)))
	endless._ended = true
	_check("endless_end_excluded",
		not bool(SettingsManager._quality_governor_target_for(
			endless, false, false).get("ready", false)))
	endless.free()

	var tutorial := TutorialManager.new()
	tutorial._spawn_ready = true
	tutorial._presentation_started = true
	_check("tutorial_play_ready",
		bool(SettingsManager._quality_governor_target_for(
			tutorial, false, false).get("ready", false)))
	tutorial._finished = true
	_check("tutorial_finish_excluded",
		not bool(SettingsManager._quality_governor_target_for(
			tutorial, false, false).get("ready", false)))
	tutorial.free()

	var course := CourseBase.new()
	state = SettingsManager._quality_governor_target_for(course, false, false)
	_check("course_without_manager_not_sampled",
		int(state.get("identity", 0)) != 0 and not bool(state.get("ready", false)))
	course.free()


func _test_cached_single_dfs() -> void:
	var root := Node.new()
	add_child(root)
	_clear_target_cache()
	var scans := SettingsManager._governor_target_scan_count
	_check("empty_scene_resolves_null", SettingsManager._governor_resolve_target(root) == null)
	_check("empty_scene_scanned_once",
		SettingsManager._governor_target_scan_count == scans + 1)
	for _index: int in 12:
		SettingsManager._governor_resolve_target(root)
	_check("stable_empty_scene_cached",
		SettingsManager._governor_target_scan_count == scans + 1)

	var race := RaceManager.new()
	root.add_child(race)
	_check("late_manager_found_on_child_edge",
		SettingsManager._governor_resolve_target(root) == race)
	var manager_scans := SettingsManager._governor_target_scan_count
	for _index: int in 24:
		SettingsManager._governor_resolve_target(root)
	_check("manager_cache_has_no_recursive_rescan",
		SettingsManager._governor_target_scan_count == manager_scans)
	root.remove_child(race)
	_check("removed_manager_invalidates_cache",
		SettingsManager._governor_resolve_target(root) == null)
	race.free()
	_clear_target_cache()
	remove_child(root)
	root.free()

	var priority_root := Node.new()
	var course := CourseBase.new()
	var manager := RaceManager.new()
	priority_root.add_child(course)
	priority_root.add_child(manager)
	_check("single_dfs_manager_beats_course_fallback",
		SettingsManager._find_governed_target(priority_root) == manager)
	priority_root.free()


func _test_readiness_edges_split_windows() -> void:
	_reset_fixture("high")
	SettingsManager._governor_observe_target_state(101, true)
	SettingsManager._governor_warmup = 0
	for _index: int in 2:
		SettingsManager._governor_record_sample(30.0, 0, false)
	_check("partial_window_accumulates",
		SettingsManager._governor_fps_count == 2)
	SettingsManager._governor_observe_target_state(101, false)
	_check("pause_edge_discards_partial_window",
		SettingsManager._governor_fps_count == 0
		and SettingsManager._governor_warmup == SettingsManager.GOVERNOR_DESKTOP_WARMUP_SAMPLES)
	SettingsManager._governor_observe_target_state(101, true)
	SettingsManager._governor_warmup = 0
	for _index: int in SettingsManager.GOVERNOR_DESKTOP_SAMPLE_WINDOW - 1:
		SettingsManager._governor_record_sample(30.0, 0, false)
	_check("resume_requires_fresh_full_window",
		SettingsManager._render_scale_step == 0
		and SettingsManager._governor_fps_count == SettingsManager.GOVERNOR_DESKTOP_SAMPLE_WINDOW - 1)
	SettingsManager._governor_record_sample(30.0, 0, false)
	_check("fresh_window_can_adapt", SettingsManager._render_scale_step == 1)
	SettingsManager._governor_observe_target_state(202, true)
	_check("scene_identity_edge_resets",
		SettingsManager._governor_fps_count == 0
		and SettingsManager._governor_warmup == SettingsManager.GOVERNOR_DESKTOP_WARMUP_SAMPLES)


func _test_actual_paused_process_edge() -> void:
	_reset_fixture("high")
	_clear_target_cache()
	var race := RaceManager.new()
	add_child(race)
	race._grid_placed = true
	race._presentation_started = true
	race.started = true
	SettingsManager._governor_monitoring = true
	SettingsManager.process_mode = Node.PROCESS_MODE_ALWAYS
	process_mode = Node.PROCESS_MODE_ALWAYS
	SettingsManager._governor_refresh_target_state()
	SettingsManager._governor_warmup = 0
	for _index: int in 2:
		SettingsManager._governor_record_sample(60.0, 0, false)
	get_tree().paused = true
	# process_frame is emitted before node _process callbacks. Cross two
	# boundaries so one actual paused callback has finished before inspecting it.
	await get_tree().process_frame
	await get_tree().process_frame
	_check("actual_paused_frame_resets_window",
		not SettingsManager._governor_target_ready
		and SettingsManager._governor_fps_count == 0)
	get_tree().paused = false
	await get_tree().process_frame
	await get_tree().process_frame
	_check("actual_resume_frame_starts_fresh_warmup",
		SettingsManager._governor_target_ready
		and SettingsManager._governor_warmup == SettingsManager.GOVERNOR_DESKTOP_WARMUP_SAMPLES)
	SettingsManager._governor_monitoring = false
	remove_child(race)
	race.free()
	_clear_target_cache()


func _test_adapted_floor_timer_survives() -> void:
	_reset_fixture("high")
	SettingsManager._governor_steps = SettingsManager.GOVERNOR_MAX_STEPS
	SettingsManager._governor_override = "low"
	SettingsManager._render_scale_step = 1
	SettingsManager._governor_has_adapted = true
	SettingsManager._governor_monitoring = true
	var timer := Timer.new()
	add_child(timer)
	SettingsManager._governor_tick(timer)
	_check("adapted_floor_timer_keeps_monitoring",
		not timer.is_queued_for_deletion() and SettingsManager._governor_monitoring)
	remove_child(timer)
	timer.free()
	SettingsManager._governor_monitoring = false


func _test_degrade_and_recover() -> void:
	_reset_fixture("high")
	for _index: int in SettingsManager.GOVERNOR_DESKTOP_RENDER_STEP_FLOOR + 2:
		SettingsManager._governor_apply_average(30.0, 0, false)
	_check("desktop_degrades_to_low",
		SettingsManager._governor_override == "low"
		and SettingsManager._render_scale_step == SettingsManager.GOVERNOR_DESKTOP_RENDER_STEP_FLOOR
		and SettingsManager._governor_steps == 2)
	_check("saved_user_tier_untouched", SettingsManager._saved_quality_preset() == "high")
	_check("desktop_native_base_tier_preserved",
		SettingsManager._governor_render_base_tier(0) == "high")
	_check("mobile_override_may_use_effective_tier",
		SettingsManager._governor_render_base_tier(1) == "low")

	for _index: int in SettingsManager.GOVERNOR_RESTORE_WINDOWS:
		SettingsManager._governor_apply_average(60.0, 0, false)
	_check("recovery_low_to_medium", SettingsManager._governor_override == "medium")
	for _index: int in SettingsManager.GOVERNOR_RESTORE_WINDOWS:
		SettingsManager._governor_apply_average(60.0, 0, false)
	_check("recovery_returns_saved_tier",
		SettingsManager._governor_override.is_empty()
		and SettingsManager.get_setting("display", "quality_preset") == "high")
	for _index: int in SettingsManager.GOVERNOR_RESTORE_WINDOWS \
			* SettingsManager.GOVERNOR_DESKTOP_RENDER_STEP_FLOOR:
		SettingsManager._governor_apply_average(60.0, 0, false)
	_check("recovery_restores_aa_render_step",
		SettingsManager._render_scale_step == 0
		and SettingsManager._governor_steps == 0
		and not SettingsManager._governor_has_adapted)
	SettingsManager._governor_apply_average(30.0, 0, false)
	_check("monitoring_survives_full_recovery", SettingsManager._render_scale_step == 1)


func _test_desktop_render_scale_ladder() -> void:
	_reset_fixture("high")
	SettingsManager._governor_apply_average(60.0, 0, false)
	_check("desktop_starts_native_without_forced_fallback",
		SettingsManager._render_scale_step == 0 and is_equal_approx(_effective_scale(0), 1.0))
	SettingsManager._governor_apply_average(48.0, 0, false)
	_check("desktop_first_slow_window_only_removes_msaa",
		SettingsManager._render_scale_step == 1 and is_equal_approx(_effective_scale(0), 1.0))
	SettingsManager._governor_apply_average(48.0, 0, false)
	_check("desktop_second_slow_window_reduces_3d_buffer",
		SettingsManager._render_scale_step == 2 and is_equal_approx(_effective_scale(0), 0.85)
		and SettingsManager._governor_override.is_empty())
	SettingsManager._governor_apply_average(48.0, 0, false)
	_check("desktop_third_slow_window_reaches_bounded_floor",
		SettingsManager._render_scale_step == SettingsManager.GOVERNOR_DESKTOP_RENDER_STEP_FLOOR
		and is_equal_approx(_effective_scale(0), 0.72))
	_check("desktop_scale_adaptation_keeps_preferred_tier",
		SettingsManager._saved_quality_preset() == "high"
		and SettingsManager.get_setting("display", "quality_preset") == "high")
	SettingsManager._governor_apply_average(60.0, 0, false)
	_check("desktop_one_healthy_window_cannot_restore",
		SettingsManager._render_scale_step == SettingsManager.GOVERNOR_DESKTOP_RENDER_STEP_FLOOR)
	SettingsManager._governor_apply_average(56.0, 0, false)
	_check("desktop_middle_band_breaks_recovery_streak",
		SettingsManager._governor_good_windows == 0
		and is_equal_approx(_effective_scale(0), 0.72))
	for expected_step: int in [2, 1, 0]:
		for _index: int in SettingsManager.GOVERNOR_RESTORE_WINDOWS:
			SettingsManager._governor_apply_average(60.0, 0, false)
		_check("desktop_gradual_restore_step_%d" % expected_step,
			SettingsManager._render_scale_step == expected_step
			and is_equal_approx(_effective_scale(0), SettingsManager.RENDER_SCALE_STEPS[expected_step]))
	_check("desktop_full_recovery_clears_only_session_adaptation",
		not SettingsManager._governor_has_adapted
		and SettingsManager._saved_quality_preset() == "high")
	_check("manual_medium_base_not_raised_by_msaa_step",
		is_equal_approx(SettingsManager.effective_web_render_scale("medium", 1), 0.85))
	_check("manual_low_base_not_raised_by_desktop_floor",
		is_equal_approx(SettingsManager.effective_web_render_scale("low", 3), 0.7))
	_check("native_headless_render_scale_unchanged",
		is_equal_approx(SettingsManager.render_scale_3d(), 1.0))


func _test_mobile_render_scale_floor() -> void:
	_reset_fixture("high")
	for _index: int in SettingsManager.RENDER_SCALE_STEPS.size() - 1:
		SettingsManager._governor_apply_average(35.0, 1, false)
	_check("mobile_retains_deeper_existing_scale_floor",
		SettingsManager._render_scale_step == SettingsManager.RENDER_SCALE_STEPS.size() - 1
		and is_equal_approx(_effective_scale(1), 0.62)
		and SettingsManager._governor_override.is_empty())
	for _index: int in SettingsManager.GOVERNOR_RESTORE_WINDOWS \
			* (SettingsManager.RENDER_SCALE_STEPS.size() - 1):
		SettingsManager._governor_apply_average(60.0, 1, false)
	_check("mobile_restores_entire_existing_ladder",
		SettingsManager._render_scale_step == 0 and is_equal_approx(_effective_scale(1), 1.0)
		and not SettingsManager._governor_has_adapted)


func _effective_scale(mobile_override: int) -> float:
	return SettingsManager.effective_web_render_scale(
		SettingsManager._governor_render_base_tier(mobile_override), SettingsManager._render_scale_step)


func _test_playable_sampling_timing() -> void:
	_reset_fixture("high")
	SettingsManager._governor_observe_target_state(301, true)
	for _index: int in SettingsManager.GOVERNOR_DESKTOP_WARMUP_SAMPLES \
			+ SettingsManager.GOVERNOR_DESKTOP_SAMPLE_WINDOW - 1:
		SettingsManager._governor_record_sample(48.0, 0, false)
	_check("desktop_four_playable_samples_cannot_adapt",
		SettingsManager._render_scale_step == 0)
	SettingsManager._governor_record_sample(48.0, 0, false)
	_check("desktop_fifth_playable_sample_removes_msaa",
		SettingsManager._render_scale_step == 1)
	for expected_step: int in [2, 3]:
		for _index: int in SettingsManager.GOVERNOR_DESKTOP_SAMPLE_WINDOW:
			SettingsManager._governor_record_sample(48.0, 0, false)
		_check("desktop_48fps_reaches_step_%d_at_sample_%d" % [expected_step, 1 + expected_step * 4],
			SettingsManager._render_scale_step == expected_step
			and is_equal_approx(_effective_scale(0), SettingsManager.RENDER_SCALE_STEPS[expected_step]))
	_check("desktop_realistic_feed_keeps_saved_high_preference",
		SettingsManager._saved_quality_preset() == "high")

	_reset_fixture("high")
	SettingsManager._governor_observe_target_state(302, true)
	for _index: int in 5:
		SettingsManager._governor_record_sample(48.0, 0, false)
	for _index: int in 2:
		SettingsManager._governor_record_sample(48.0, 0, false)
	SettingsManager._governor_observe_target_state(302, false)
	for _index: int in 12:
		SettingsManager._governor_record_sample(30.0, 0, false)
	_check("death_discards_partial_samples_but_keeps_attained_scale_step",
		SettingsManager._render_scale_step == 1 and SettingsManager._governor_fps_count == 0)
	SettingsManager._governor_observe_target_state(302, true)
	for _index: int in SettingsManager.GOVERNOR_DESKTOP_WARMUP_SAMPLES \
			+ SettingsManager.GOVERNOR_DESKTOP_SAMPLE_WINDOW - 1:
		SettingsManager._governor_record_sample(48.0, 0, false)
	_check("retry_requires_fresh_warmup_and_full_window",
		SettingsManager._render_scale_step == 1)
	SettingsManager._governor_record_sample(48.0, 0, false)
	_check("retry_slow_window_can_advance_retained_desktop_ladder",
		SettingsManager._render_scale_step == 2 and is_equal_approx(_effective_scale(0), 0.85))


func _test_mobile_sampling_policy_unchanged() -> void:
	_reset_fixture("high", 1)
	SettingsManager._governor_observe_target_state(401, true, 1)
	for _index: int in SettingsManager.GOVERNOR_WARMUP_SAMPLES \
			+ SettingsManager.GOVERNOR_SAMPLE_WINDOW:
		SettingsManager._governor_record_sample(48.0, 1, false)
	_check("mobile_48fps_keeps_existing_45fps_trigger",
		SettingsManager._render_scale_step == 0 and SettingsManager._governor_fps_count == 0)
	SettingsManager._governor_observe_target_state(401, false, 1)
	SettingsManager._governor_observe_target_state(401, true, 1)
	for _index: int in SettingsManager.GOVERNOR_WARMUP_SAMPLES \
			+ SettingsManager.GOVERNOR_SAMPLE_WINDOW - 1:
		SettingsManager._governor_record_sample(40.0, 1, false)
	_check("mobile_retains_ten_sample_initial_delay",
		SettingsManager._render_scale_step == 0)
	SettingsManager._governor_record_sample(40.0, 1, false)
	_check("mobile_retains_eleventh_sample_first_action",
		SettingsManager._render_scale_step == 1)


func _test_explicit_choice_reset() -> void:
	_reset_fixture("medium")
	for _index: int in SettingsManager.GOVERNOR_DESKTOP_RENDER_STEP_FLOOR + 1:
		SettingsManager._governor_apply_average(30.0, 0, false)
	_check("explicit_choice_fixture_has_scale_and_preset_adaptation",
		SettingsManager._render_scale_step == SettingsManager.GOVERNOR_DESKTOP_RENDER_STEP_FLOOR
		and SettingsManager._governor_override == "low")
	SettingsManager._governor_fps_count = 5
	SettingsManager._reset_governor_for_user_quality()
	_check("explicit_choice_clears_session_override",
		SettingsManager._governor_override.is_empty()
		and SettingsManager._governor_steps == 0
		and SettingsManager._render_scale_step == 0)
	_check("explicit_choice_preserves_saved_value",
		SettingsManager._saved_quality_preset() == "medium")
	_check("explicit_choice_restarts_clean_warmup",
		SettingsManager._governor_fps_count == 0
		and SettingsManager._governor_warmup == SettingsManager.GOVERNOR_DESKTOP_WARMUP_SAMPLES)


func _test_msaa_policy() -> void:
	_check("web_explicit_msaa_off_stays_off",
		SettingsManager.effective_msaa_3d(
			"off", "high", 0, "gl_compatibility", 1) == Viewport.MSAA_DISABLED)
	_check("web_high_default_still_two_x",
		SettingsManager.effective_msaa_3d(
			"4x", "high", 0, "gl_compatibility", 1) == Viewport.MSAA_2X)
	_check("web_governor_step_disables_msaa",
		SettingsManager.effective_msaa_3d(
			"4x", "high", 1, "gl_compatibility", 1) == Viewport.MSAA_DISABLED)
	_check("native_forward_honors_four_x",
		SettingsManager.effective_msaa_3d(
			"4x", "high", 0, "mobile", 0) == Viewport.MSAA_4X)


func _reset_fixture(saved_tier: String, mobile_override: int = 0) -> void:
	SettingsManager.settings = SettingsManager.default_settings()
	SettingsManager.settings["display"]["quality_preset"] = saved_tier
	SettingsManager._governor_override = ""
	SettingsManager._governor_steps = 0
	SettingsManager._render_scale_step = 0
	SettingsManager._governor_fps_sum = 0.0
	SettingsManager._governor_fps_count = 0
	SettingsManager._governor_good_windows = 0
	SettingsManager._governor_warmup = SettingsManager.GOVERNOR_WARMUP_SAMPLES \
			if mobile_override == 1 else SettingsManager.GOVERNOR_DESKTOP_WARMUP_SAMPLES
	SettingsManager._governor_target_id = 0
	SettingsManager._governor_target_ready = false
	SettingsManager._governor_has_adapted = false


func _clear_target_cache() -> void:
	SettingsManager._governor_cached_scene_id = 0
	SettingsManager._governor_cached_scene_child_count = -1
	SettingsManager._governor_cached_target = null


func _snapshot() -> Dictionary:
	return {
		"settings": SettingsManager.settings.duplicate(true),
		"override": SettingsManager._governor_override,
		"steps": SettingsManager._governor_steps,
		"render_step": SettingsManager._render_scale_step,
		"sum": SettingsManager._governor_fps_sum,
		"count": SettingsManager._governor_fps_count,
		"good": SettingsManager._governor_good_windows,
		"warmup": SettingsManager._governor_warmup,
		"target_id": SettingsManager._governor_target_id,
		"target_ready": SettingsManager._governor_target_ready,
		"scene_id": SettingsManager._governor_cached_scene_id,
		"scene_children": SettingsManager._governor_cached_scene_child_count,
		"cached_target": SettingsManager._governor_cached_target,
		"scan_count": SettingsManager._governor_target_scan_count,
		"monitoring": SettingsManager._governor_monitoring,
		"adapted": SettingsManager._governor_has_adapted,
		"process_mode": SettingsManager.process_mode,
	}


func _restore() -> void:
	SettingsManager.settings = _saved["settings"]
	SettingsManager._governor_override = _saved["override"]
	SettingsManager._governor_steps = _saved["steps"]
	SettingsManager._render_scale_step = _saved["render_step"]
	SettingsManager._governor_fps_sum = _saved["sum"]
	SettingsManager._governor_fps_count = _saved["count"]
	SettingsManager._governor_good_windows = _saved["good"]
	SettingsManager._governor_warmup = _saved["warmup"]
	SettingsManager._governor_target_id = _saved["target_id"]
	SettingsManager._governor_target_ready = _saved["target_ready"]
	SettingsManager._governor_cached_scene_id = _saved["scene_id"]
	SettingsManager._governor_cached_scene_child_count = _saved["scene_children"]
	SettingsManager._governor_cached_target = _saved["cached_target"]
	SettingsManager._governor_target_scan_count = _saved["scan_count"]
	SettingsManager._governor_monitoring = _saved["monitoring"]
	SettingsManager._governor_has_adapted = _saved["adapted"]
	SettingsManager.process_mode = _saved["process_mode"]
