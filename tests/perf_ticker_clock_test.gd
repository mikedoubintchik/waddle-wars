extends Node
## Deterministic monotonic-clock contract for the opt-in console ticker.

class FakeTicker:
	extends PerfTicker

	var fake_now_usec: int = 1_000_000
	var samples: Array[Dictionary] = []
	var render_state_reads: int = 0

	func _clock_now_usec() -> int:
		return fake_now_usec

	func _publish_sample(sample: Dictionary) -> void:
		samples.append(sample.duplicate(true))

	func _render_state_data() -> Dictionary:
		render_state_reads += 1
		return super._render_state_data()


var _passes: int = 0
var _failures: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_test_monotonic_windows()
	_test_profile_render_state_metadata()
	await _test_processes_while_paused()
	print("[perf_ticker_clock] DONE: %d passed, %d failed" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_monotonic_windows() -> void:
	var ticker := FakeTicker.new()
	ticker.set_scene_label("menu")
	ticker._ready()
	_check("always_process_mode", ticker.process_mode == Node.PROCESS_MODE_ALWAYS)

	# Deliberately pass a bogus tiny delta. Wall time, not engine delta, must own
	# every reported value. 119 intervals remain below the two-second boundary.
	for _frame: int in 119:
		ticker.fake_now_usec += 16_667
		ticker._process(0.001)
	_check("first_sample_not_early", ticker.samples.is_empty(),
		"samples=%d" % ticker.samples.size())
	ticker.fake_now_usec += 16_667
	ticker._process(0.001)
	_check("first_sample_boundary", ticker.samples.size() == 1,
		"samples=%d" % ticker.samples.size())
	if ticker.samples.size() == 1:
		var first := ticker.samples[0]
		_check("first_scene_label", first["scene"] == "menu", str(first))
		_check("steady_frame_count", int(first["frames"]) == 120, str(first))
		_check("steady_window_elapsed", is_equal_approx(
			float(first["elapsed_seconds"]), 2.00004), str(first))
		_check("steady_fps", absf(float(first["fps"]) - 59.9988) < 0.001, str(first))
		_check("steady_average_ms", is_equal_approx(
			float(first["average_ms"]), 16.667), str(first))
		_check("steady_worst_ms", is_equal_approx(
			float(first["worst_ms"]), 16.667), str(first))

	# A multi-second blocked frame must survive even when engine delta is clamped.
	ticker.set_scene_label("runner")
	ticker.fake_now_usec += 2_900_000
	ticker._process(0.016667)
	_check("stall_emits_window", ticker.samples.size() == 2,
		"samples=%d" % ticker.samples.size())
	if ticker.samples.size() == 2:
		var stalled := ticker.samples[1]
		_check("stall_scene_label", stalled["scene"] == "runner", str(stalled))
		_check("stall_window_elapsed", is_equal_approx(
			float(stalled["elapsed_seconds"]), 2.9), str(stalled))
		_check("stall_worst_ms", is_equal_approx(
			float(stalled["worst_ms"]), 2900.0), str(stalled))
		_check("stall_fps", is_equal_approx(
			float(stalled["fps"]), 1.0 / 2.9), str(stalled))
	ticker.free()


func _test_profile_render_state_metadata() -> void:
	var saved_profile_enabled := BootProfiler._enabled
	BootProfiler._enabled = 0
	var before := get_child_count()
	_check("normal_release_does_not_attach_ticker",
		PerfTicker.attach(self) == null and get_child_count() == before)
	var ticker := FakeTicker.new()
	add_child(ticker)
	ticker._elapsed_usec = 2_000_000
	ticker._frames = 120
	var normal := ticker._sample_data()
	_check("profile_off_omits_render_metadata",
		not normal.has("render_state") and ticker.render_state_reads == 0)
	BootProfiler._enabled = 1
	var profiled := ticker._sample_data()
	_check("profile_on_reads_render_state_once_per_sample",
		profiled.has("render_state") and ticker.render_state_reads == 1)
	if profiled.has("render_state"):
		var state: Dictionary = profiled["render_state"]
		var viewport := ticker.get_viewport()
		_check("metadata_reports_actual_viewport_scale",
			is_equal_approx(float(state["scale_3d"]), viewport.scaling_3d_scale))
		_check("metadata_reports_actual_viewport_msaa",
			int(state["msaa_3d"]) == int(viewport.msaa_3d))
		_check("metadata_reports_effective_quality",
			state["quality"] == String(SettingsManager.get_setting("display", "quality_preset")))
		_check("metadata_reports_governor_step_and_readiness",
			int(state["render_step"]) == SettingsManager._render_scale_step
			and int(state["quality_steps"]) == SettingsManager._governor_steps
			and bool(state["governor_ready"]) == SettingsManager._governor_target_ready
			and bool(state["governor_monitoring"]) == SettingsManager._governor_monitoring)
		var allowed := ["scale_3d", "msaa_3d", "quality", "render_step",
			"quality_steps", "governor_ready", "governor_monitoring", "objects",
			"nodes", "orphan_nodes", "draw_calls", "texture_bytes"]
		var actual := state.keys()
		actual.sort()
		allowed.sort()
		_check("metadata_allowlist_has_no_extra_fields", actual == allowed)
	_check("metadata_does_not_change_monotonic_clock_values",
		profiled["fps"] == normal["fps"]
		and profiled["elapsed_seconds"] == normal["elapsed_seconds"]
		and profiled["average_ms"] == normal["average_ms"]
		and profiled["worst_ms"] == normal["worst_ms"])
	BootProfiler._enabled = saved_profile_enabled
	remove_child(ticker)
	ticker.free()


func _test_processes_while_paused() -> void:
	var ticker := FakeTicker.new()
	add_child(ticker)
	await get_tree().process_frame
	var before := ticker._frames
	ticker.fake_now_usec += 16_667
	get_tree().paused = true
	await get_tree().process_frame
	get_tree().paused = false
	_check("paused_always_callback", ticker._frames == before + 1,
		"before=%d after=%d" % [before, ticker._frames])
	_check("paused_interval_measured", ticker._worst_usec >= 16_667,
		"worst_usec=%d" % ticker._worst_usec)
	ticker.queue_free()


func _check(label: String, passed: bool, detail: String = "") -> void:
	if passed:
		_passes += 1
		print("[perf_ticker_clock] PASS %s" % label)
		return
	_failures += 1
	print("[perf_ticker_clock] FAIL %s%s" % [
		label, " — " + detail if not detail.is_empty() else ""])
