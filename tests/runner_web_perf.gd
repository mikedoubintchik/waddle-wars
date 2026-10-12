extends "res://tests/runner_perf_probe.gd"
## Web-only transport adapter. Timing, fixed quality tier, report and gates are
## inherited unchanged; configuration and report transport live in the QA shell.

const WEB_CLOCK := preload("res://tests/runner_web_clock.gd")
const WEB_MESH_PREFLIGHT := preload("res://tests/runner_web_mesh_preflight.gd")

var _web_seen_running: bool = false
var _web_clock_anchors: Array[Dictionary] = []
var _web_phase_start_us: int = 0
var _web_phase_pre_us: int = 0
var _web_phase_post_us: int = 0
var _web_phase_pre_count: int = 0
var _web_phase_post_count: int = 0
var _web_phase_process_frame: int = 0
var _web_phase_running: bool = false
var _web_phase_stats: Dictionary = {
	"captured": false, "startup_cycles_excluded": 0, "running_cycles": 0,
	"valid_running_cycles": 0, "invalid_running_cycles": 0,
	"missing_pre_draw_cycles": 0, "missing_post_draw_cycles": 0,
	"duplicate_marker_cycles": 0, "invalid_order_cycles": 0,
	"totals_us": {"scene_process_us": 0, "render_submission_us": 0, "between_frames_us": 0, "total_us": 0},
	"maxima_us": {"scene_process_us": 0, "render_submission_us": 0, "between_frames_us": 0, "total_us": 0},
	"slow_cycles_seen": 0, "slow_cycles_dropped": 0, "slow_cycles": [],
}
var _canvas_policy: String = "fixed"
var _msaa_override: String = "default"
var _render_scale_override: Variant = null
var _startup_render_scale: float = 1.0
var _web_bridge_checks: int = 0
var _web_mesh_preflight: Dictionary = {}
var _web_readback_witness: Dictionary = {}


func _parse_args() -> void:
	super._parse_args()
	var config: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://tests/runner_web_perf_config.json"))
	_tier = String(config["tier"])
	_width = int(config["width"])
	_height = int(config["height"])
	_warmup_seconds = float(config["warmup"])
	_sample_seconds = float(config["seconds"])
	_seed = int(config["seed"])
	_stream_trace_requested = bool(config["stream_trace"])
	_census_requested = bool(config["census"])
	_canvas_policy = String(config.get("canvas_policy", "fixed"))
	_msaa_override = String(config.get("msaa_override", "default"))
	_render_scale_override = config.get("render_scale_override", null)
	if _canvas_policy == "production":
		_force_window_size = false
		_fixed_resolution_gate_applicable = false
		_window_size_policy = "production_canvas_controlled_tier"
	_out_path = "user://qa/runner_web_perf.json"


func _apply_quality_without_persisting() -> void:
	super._apply_quality_without_persisting()
	# These QA-only controls preserve tier, geometry, shadows and particles.
	# Apply before inherited startup metadata and scene/warmup construction; no
	# saved player setting is written and the production governor stays disabled.
	if _msaa_override == "off":
		SettingsManager.settings["display"]["msaa"] = "off"
		SettingsManager._apply_display("msaa", "off")
	if _render_scale_override != null:
		get_viewport().scaling_3d_scale = float(_render_scale_override)
	_startup_render_scale = get_viewport().scaling_3d_scale


func _ready() -> void:
	# A custom worker template must preserve the page-facing bridge, including
	# shared-memory byte-array callbacks. Validate before constructing the world
	# or starting inherited clocks; this is never per-frame instrumentation.
	if not _web_bridge_preflight():
		get_tree().quit(1)
		return
	var witness_begin: Variant = JavaScriptBridge.eval("window.__wwRunnerReadbackBegin()", true)
	var begin_result: Variant = JSON.parse_string(witness_begin) if witness_begin is String else null
	var mesh_result: Variant = null
	if begin_result is Dictionary and bool(begin_result.get("begun", false)):
		mesh_result = WEB_MESH_PREFLIGHT.run_checks()
	# End unconditionally, even when begin/data checks fail. Restore before
	# constructing the world, reading timing clocks, or interpreting the result.
	var witness_end: Variant = JavaScriptBridge.eval("window.__wwRunnerReadbackEnd()", true)
	var end_result: Variant = JSON.parse_string(witness_end) if witness_end is String else null
	_web_readback_witness = end_result if end_result is Dictionary else {
		"passed": false, "restored": false, "reason": "invalid_browser_witness_result"}
	_web_mesh_preflight = mesh_result if mesh_result is Dictionary else {
		"passed": false, "checks": 0, "failures": ["mesh_checks_not_completed"],
		"scope": "Preflight did not produce a complete mesh result; no world constructed"}
	print("[runner_web_perf] Mesh readback preflight: %s" % JSON.stringify(_web_mesh_preflight))
	print("[runner_web_perf] Browser readback witness: %s" % JSON.stringify(_web_readback_witness))
	if not bool(_web_mesh_preflight.get("passed", false)) \
			or int(_web_mesh_preflight.get("checks", 0)) != WEB_MESH_PREFLIGHT.REQUIRED_CHECKS \
			or not bool(_web_readback_witness.get("passed", false)) \
			or not bool(_web_readback_witness.get("restored", false)):
		push_error("[runner_web_perf] Mesh readback preflight failed before world construction")
		JavaScriptBridge.eval("window.__wwRunnerFail('Mesh readback preflight failed before world construction','mesh_readback_preflight',%s)" %
			JSON.stringify({"mesh_checks": _web_mesh_preflight,
				"readback_witness": _web_readback_witness}), true)
		get_tree().quit(1)
		return
	JavaScriptBridge.eval("window.__wwRunnerMark('probe_ready')", true)
	super._ready()
	if _stream_trace_requested:
		get_tree().process_frame.connect(_web_phase_process_start)
		RenderingServer.frame_pre_draw.connect(_web_phase_pre_draw)
		RenderingServer.frame_post_draw.connect(_web_phase_post_draw)
		_web_phase_stats["captured"] = true


func _web_bridge_preflight() -> bool:
	# Pinned Godot 4.7.1's BOOL eval branch returns uint32_t js_data.b, which
	# constructs an INT Variant (0/1), not a BOOL Variant. Preserve that existing
	# bridge contract; do not mistake its C++ conversion for a worker defect.
	var cases: Array[Dictionary] = [
		{"code": "globalThis === window", "expected": 1},
		{"code": "document.getElementById('canvas') !== null", "expected": 1},
		{"code": "typeof window.__wwRunnerMark === 'function'", "expected": 1},
		{"code": "false", "expected": 0},
		{"code": "1.5", "expected": 1.5},
		{"code": "'waddle-🐧'", "expected": "waddle-🐧"},
		{"code": "new Uint8Array([3,1,4,1,5])", "expected": PackedByteArray([3, 1, 4, 1, 5])},
		{"code": "undefined", "expected": null},
	]
	for item: Dictionary in cases:
		var actual: Variant = JavaScriptBridge.eval(item.code, true)
		if typeof(actual) != typeof(item.expected) or actual != item.expected:
			push_error("[runner_web_perf] Page bridge preflight failed at check %d: actual type=%d value=%s; expected type=%d value=%s" % [
				_web_bridge_checks + 1, typeof(actual), var_to_str(actual),
				typeof(item.expected), var_to_str(item.expected)])
			# An incompatible bridge may also fail to send this message. The
			# nonzero engine exit remains the shell's independent failure channel.
			JavaScriptBridge.eval("window.__wwRunnerFail('Page bridge preflight failed', 'bridge_preflight')", true)
			return false
		_web_bridge_checks += 1
	print("[runner_web_perf] Browser bridge preflight passed: %d checks" % _web_bridge_checks)
	return true


func _process(delta: float) -> void:
	# GO mark plus one optional bracketed clock read, never per-frame bridge work.
	# Their small cost is included in this diagnostic's first frame.
	if not _web_seen_running and _game != null and _game.build_finished and _game.running:
		_web_seen_running = true
		JavaScriptBridge.eval("window.__wwRunnerMark('first_running')", true)
		_web_capture_clock("first_running")
	super._process(delta)


func _write_report(report: Dictionary) -> Error:
	_web_capture_clock("report")
	var catalog := _game._art_catalog
	var quality: Dictionary = report["quality"]
	quality["render_scale_3d"] = _web_render_scale_report()
	report["web_fixture"] = {
		"mesh_readback_preflight": _web_mesh_preflight,
		"browser_readback_witness": _web_readback_witness,
		"workload_valid": bool(report.get("workload_valid", false)),
		"bridge_preflight": {"passed": _web_bridge_checks == 8, "checks": _web_bridge_checks,
			"scope": "One-time page-window/DOM/scalar/UTF-8/byte-array/NIL checks before world construction; not a complete bridge or native-store validation"},
		"scope": "Post-measurement metadata; no scene inventory inside sampled frames",
		"canvas_policy": _canvas_policy,
		"canvas_policy_scope": "Reviewed production sizing/DPR IIFEs only" \
				if _canvas_policy == "production" else "QA-owned fixed backing buffer",
		"quality_governor": "disabled; controlled requested-tier workload",
		"msaa_override": _msaa_override,
		"render_scale_override": _render_scale_override,
		"complete_production": false,
		"debug_build": OS.is_debug_build(),
		"preview_overlay_allowed": ArtCatalog.preview_overlay_allowed(
				OS.is_debug_build(), OS.has_feature("editor")),
		"preview_overlay_active": catalog != null and catalog.preview_overlay_active(),
		"preview_asset_ids": catalog.preview_asset_ids() if catalog != null else PackedStringArray(),
		"authored_day_kit": _game.track.authored_day_kit_status(),
		"runner_vfx_nodes": _count_runner_vfx(_game),
		"frame_phases": _web_phase_report(),
		"clock_alignment": _web_clock_report(),
	}
	var result := super._write_report(report)
	if result != OK:
		JavaScriptBridge.eval("window.__wwRunnerFail('Godot report write failed')", true)
		return result
	var csv := FileAccess.get_file_as_string(_out_path.get_basename() + ".csv")
	JavaScriptBridge.eval("window.__wwRunnerFinish(%s,%s)" % [
			JSON.stringify(report), JSON.stringify(csv)], true)
	return result


func _web_render_scale_report() -> Dictionary:
	var actual_at_report := get_viewport().scaling_3d_scale
	var requested: Variant = null
	var startup_matches: Variant = null
	var report_matches: Variant = null
	if _render_scale_override != null:
		var requested_value := float(_render_scale_override)
		requested = requested_value
		startup_matches = is_equal_approx(_startup_render_scale, requested_value)
		report_matches = is_equal_approx(actual_at_report, requested_value)
	return {
		"requested_override": requested,
		"actual_before_scene_build": _startup_render_scale,
		"actual_after_measurement": actual_at_report,
		"override_matches_before_scene_build": startup_matches,
		"override_matches_after_measurement": report_matches,
		"scope": "Main viewport scaling_3d_scale set once before runner scene and warmup; null request preserves tier policy",
	}


func _web_capture_clock(label: String) -> void:
	# Two bounded bridge samples, never per-frame. Disabled for untraced runs.
	if not _stream_trace_requested or _web_clock_anchors.size() >= 2:
		return
	var before_us := Time.get_ticks_usec()
	var browser_ms: Variant = JavaScriptBridge.eval("performance.now()", true)
	var after_us := Time.get_ticks_usec()
	_web_clock_anchors.append(WEB_CLOCK.bracket(label, before_us, browser_ms, after_us))


func _web_clock_report() -> Dictionary:
	return {"requested": _stream_trace_requested, "samples": _web_clock_anchors.duplicate(true),
		"limit": 2, "offset_direction": "browser performance.now microseconds minus Godot get_ticks_usec",
		"scope": "Browser read is bracketed by two Godot reads at GO and report; offset lies inside each valid interval. This is not a GPU timer. No midpoint is asserted exact; compare both anchors for clock drift. GO bridge cost is included in the first diagnostic frame, report bridge is after measurement."}


func _count_runner_vfx(node: Node) -> int:
	var total := 1 if node is RunnerVfx else 0
	for child: Node in node.get_children():
		total += _count_runner_vfx(child)
	return total


func _abort(message: String) -> void:
	if _finished:
		return
	JavaScriptBridge.eval("window.__wwRunnerFail(%s,'godot_abort',%s)" % [
			JSON.stringify(message), JSON.stringify(_incomplete_sample_diagnostics())], true)
	super._abort(message)


func _incomplete_sample_diagnostics() -> Dictionary:
	# Abort-only reduction. Preserve useful evidence without creating a normal
	# performance report or evaluating a gate for an incomplete sample.
	var sorted_ms: Array[float] = []
	var over_100 := 0
	for value: float in _frame_ms:
		sorted_ms.append(value)
		if value > 100.0:
			over_100 += 1
	sorted_ms.sort()
	var average_ms := _average_float(_frame_ms)
	var retained_from := maxi(0, _slow_frames.size() - STREAM_TRACE_SLOW_ROW_LIMIT)
	var diagnostic := {
		"schema_version": 1,
		"incomplete_sample": true,
		"gate_evaluated": false,
		"scope": "Fatal abort evidence only; not a completed performance result. Current abort interval is not added to the inherited recorded sample.",
		"requested_sample_seconds": _sample_seconds,
		"sample_seconds": _sample_time,
		"sample_frames": _frame_ms.size(),
		"warmup_seconds": _warmup_seconds,
		"observed_usec": Time.get_ticks_usec(),
		"process_frame": Engine.get_process_frames(),
		"frame_time_source": "monotonic_wall_clock",
		"average_fps": 1000.0 / average_ms if average_ms > 0.0 else 0.0,
		"average_frame_ms": average_ms,
		"p95_frame_ms": _percentile(sorted_ms, 0.95),
		"max_frame_ms": sorted_ms[-1] if not sorted_ms.is_empty() else 0.0,
		"frames_over_100_ms": over_100,
		"slow_frames_over_50_ms": _slow_frames.slice(retained_from),
		"slow_frames_rows_total": _slow_frames.size(),
		"slow_frames_rows_dropped": retained_from,
		"slow_frames_row_limit": STREAM_TRACE_SLOW_ROW_LIMIT,
		"slow_frames_retention": "Latest rows; older rows dropped when over limit",
		"stream_trace": _stream_trace_report(),
		"frame_phases": _web_phase_report(),
		"clock_alignment": _web_clock_report(),
		"runner_state": {},
	}
	if is_instance_valid(_game):
		var state := {"build_finished": _game.build_finished, "running": _game.running,
			"seen_running": _seen_running, "hits_taken": _game.hits_taken,
			"run_time": _run_time, "simulation_elapsed": _game.elapsed}
		if is_instance_valid(_game.player):
			var player := _game.player
			state.merge({"distance": player.distance, "position": _vector_components(player.position),
				"state": int(player.state), "state_name": RunnerPlayer.State.keys()[int(player.state)],
				"hits_left": player.hits_left, "lane": player.lane, "speed": player.speed})
			if is_instance_valid(_game.track):
				state["biome"] = _game.track.biome_at_z(player.position.z)
				state["biome_name"] = RunnerGame.BIOME_IDS[int(state["biome"])]
		diagnostic["runner_state"] = state
	return diagnostic


func _web_phase_process_start() -> void:
	if _finished:
		return
	var now := Time.get_ticks_usec()
	if _web_phase_start_us > 0:
		_web_phase_close(now)
	_web_phase_start_us = now
	_web_phase_pre_us = 0
	_web_phase_post_us = 0
	_web_phase_pre_count = 0
	_web_phase_post_count = 0
	_web_phase_process_frame = Engine.get_process_frames()
	_web_phase_running = is_instance_valid(_game) and _game.build_finished and _game.running


func _web_phase_pre_draw() -> void:
	if _finished or _web_phase_start_us == 0:
		return
	_web_phase_pre_count += 1
	if _web_phase_pre_count == 1:
		_web_phase_pre_us = Time.get_ticks_usec()


func _web_phase_post_draw() -> void:
	if _finished or _web_phase_start_us == 0:
		return
	_web_phase_post_count += 1
	if _web_phase_post_count == 1:
		_web_phase_post_us = Time.get_ticks_usec()


func _web_phase_close(next_start_us: int) -> void:
	if not _web_phase_running:
		_web_phase_stats["startup_cycles_excluded"] += 1
		return
	_web_phase_stats["running_cycles"] += 1
	var missing_pre := _web_phase_pre_count == 0
	var missing_post := _web_phase_post_count == 0
	var duplicate := _web_phase_pre_count > 1 or _web_phase_post_count > 1
	var ordered := not missing_pre and not missing_post \
			and _web_phase_start_us <= _web_phase_pre_us \
			and _web_phase_pre_us <= _web_phase_post_us and _web_phase_post_us <= next_start_us
	var valid := ordered and not duplicate
	var total_us := next_start_us - _web_phase_start_us
	var durations := {"scene_process_us": _web_phase_pre_us - _web_phase_start_us,
		"render_submission_us": _web_phase_post_us - _web_phase_pre_us,
		"between_frames_us": next_start_us - _web_phase_post_us, "total_us": total_us}
	if valid:
		_web_phase_stats["valid_running_cycles"] += 1
		for key: String in durations:
			_web_phase_stats["totals_us"][key] += durations[key]
			_web_phase_stats["maxima_us"][key] = maxi(_web_phase_stats["maxima_us"][key], durations[key])
	else:
		_web_phase_stats["invalid_running_cycles"] += 1
		_web_phase_stats["missing_pre_draw_cycles"] += int(missing_pre)
		_web_phase_stats["missing_post_draw_cycles"] += int(missing_post)
		_web_phase_stats["duplicate_marker_cycles"] += int(duplicate)
		_web_phase_stats["invalid_order_cycles"] += int(not missing_pre and not missing_post and not ordered)
	if total_us < 50_000:
		return
	_web_phase_stats["slow_cycles_seen"] += 1
	var row := {"process_frame": _web_phase_process_frame,
		"next_process_frame": Engine.get_process_frames(), "game_running_at_start": _web_phase_running,
		"start_us": _web_phase_start_us, "pre_draw_us": _web_phase_pre_us if not missing_pre else null,
		"post_draw_us": _web_phase_post_us if not missing_post else null, "next_start_us": next_start_us,
		"valid": valid, "pre_draw_count": _web_phase_pre_count, "post_draw_count": _web_phase_post_count,
		"missing_pre_draw": missing_pre, "missing_post_draw": missing_post,
		"duplicate_markers": duplicate, "ordered_markers": ordered, "total_us": total_us,
		"scene_process_us": durations["scene_process_us"] if valid else null,
		"render_submission_us": durations["render_submission_us"] if valid else null,
		"between_frames_us": durations["between_frames_us"] if valid else null}
	var rows: Array = _web_phase_stats["slow_cycles"]
	if rows.size() == STREAM_TRACE_SLOW_ROW_LIMIT:
		rows.pop_front()
		_web_phase_stats["slow_cycles_dropped"] += 1
	rows.append(row)


func _web_phase_report() -> Dictionary:
	var report := _web_phase_stats.duplicate(true)
	report["requested"] = _stream_trace_requested
	report["slow_cycle_threshold_us"] = 50_000
	report["slow_cycle_row_limit"] = STREAM_TRACE_SLOW_ROW_LIMIT
	report["retention"] = "Latest slow cycles whose game was running at process_frame start; startup rows omitted"
	report["clock"] = "Time.get_ticks_usec monotonic process clock; same origin as inherited stream trace"
	report["aggregation_scope"] = "Totals/maxima include valid completed running cycles only, including warmup. Invalid cycles counted explicitly. Open final cycle excluded."
	report["measurement_scope"] = "Signal-to-signal elapsed wall time, not a CPU profiler or GPU timestamps. scene_process_us=pre_draw-start; render_submission_us=post_draw-pre_draw; between_frames_us=next_start-post_draw; total_us=next_start-start."
	report["limitations"] = "Scene interval includes engine/main-thread work before draw; draw interval includes synchronous submission and waits; between-frame interval includes scheduling and work outside these signals. No individual subsystem or GPU completion attribution. Opt-in signal/timing/bookkeeping overhead is included."
	report["open_cycle_excluded"] = {"present": _web_phase_start_us > 0,
		"process_frame": _web_phase_process_frame, "start_us": _web_phase_start_us,
		"game_running_at_start": _web_phase_running,
		"pre_draw_count": _web_phase_pre_count, "post_draw_count": _web_phase_post_count}
	return report
