extends Node
## Windowed runner performance probe with machine-readable output.
##
## Report-only by default so hardware-specific runs remain evidence rather than
## flaky CI. Pass `enforce=true` to make the documented tier gate affect exit.
## Run from run_tests.sh's isolated project (or another custom user://):
##
##   godot --path . --rendering-method gl_compatibility \
##     res://tests/runner_perf_probe.tscn -- \
##     tier=high w=1920 h=1080 warmup=5 seconds=30 \
##     out=user://qa/runner_perf.json enforce=true census=true
## `census` defaults false and only inventories the final scene after timing.
## `stream_trace=true` is a bounded diagnostic, not an uninstrumented timing run.
## It joins existing CPU stream events with eight-before/eight-after hitch rows.

const DRAW_LIMITS: Dictionary = {
	"high": Vector2i(250, 300),
	"medium": Vector2i(205, 250),
	"low": Vector2i(190, 225),
}
const PRIMITIVE_LIMITS: Dictionary = {
	"high": 100_000,
	"medium": 75_000,
	"low": 50_000,
}
const STARTUP_GRACE_SECONDS: float = 30.0
const STREAM_TRACE_EVENT_LIMIT: int = 256
const STREAM_TRACE_HEAD_EVENT_LIMIT: int = 64
const STREAM_TRACE_FRAME_EVENT_LIMIT: int = 16
const STREAM_TRACE_WINDOW_LIMIT: int = 8
const STREAM_TRACE_NEIGHBOR_FRAMES: int = 8
const STREAM_TRACE_SLOW_ROW_LIMIT: int = 128
const FINGERPRINT_ROOTS: PackedStringArray = [
	"res://scripts/runner", "res://scripts/characters", "res://scripts/art",
	"res://scripts/ui", "res://scripts/utilities", "res://scripts/save",
	"res://assets/art/runner/day", "res://assets/art/characters", "res://data/art",
]
const FINGERPRINT_EXTENSIONS: PackedStringArray = ["gd", "gdshader", "glb", "tres", "tscn", "json"]
const PRIMITIVE_MONITOR_NOTE: String = \
		"Engine aggregate, not exact family attribution. Godot 4.7.1 GLES3's LOD-enabled " \
		+ "MultiMesh accounting does not multiply by instance_count in its LOD branch; " \
		+ "the non-LOD branch does. No guessed correction is applied. " \
		+ "https://github.com/godotengine/godot/blob/4.7.1-stable/drivers/gles3/rasterizer_scene_gles3.cpp#L1445-L1469"

var _tier: String = "high"
var _width: int = 1920
var _height: int = 1080
var _warmup_seconds: float = 5.0
var _sample_seconds: float = 30.0
var _out_path: String = "user://qa/runner_perf.json"
var _enforce: bool = false
var _game: RunnerGame = null
var _run_time: float = 0.0
var _sample_time: float = 0.0
var _frame_ms: PackedFloat64Array = PackedFloat64Array()
var _draw_calls: PackedInt32Array = PackedInt32Array()
var _primitives: PackedInt32Array = PackedInt32Array()
var _finished: bool = false
var _seen_running: bool = false
var _started_at_msec: int = 0
var _last_frame_usec: int = 0
var _seed: int = 20260907
var _slow_frames: Array[Dictionary] = []
var _keep_visible: bool = false
var _census_requested: bool = false
var _build_fingerprint: Dictionary = {}
var _peak_primitive_sample: Dictionary = {}
var _primitive_peak_seen: int = -1
var _startup_msaa: Dictionary = {}
var _stream_trace_requested: bool = false
var _stream_trace: StreamTraceWindow = null
var _stream_trace_armed: bool = false
var _stream_trace_previous: bool = false
var _stream_trace_bookkeeping_total_us: int = 0
var _stream_trace_bookkeeping_max_us: int = 0
## Web production-canvas diagnostics leave page-owned backing dimensions alone.
## Native and fixed-Web probes keep the historical forced-resolution behavior.
var _force_window_size: bool = true
var _fixed_resolution_gate_applicable: bool = true
var _window_size_policy: String = "fixed"
var _workload_validity: WorkloadValidity = WorkloadValidity.new()


func _ready() -> void:
	_parse_args()
	if GameConfig.is_headless():
		push_error("runner_perf_probe requires a rendering window")
		get_tree().quit(2)
		return
	if not DRAW_LIMITS.has(_tier):
		push_error("runner_perf_probe: tier must be high, medium, or low")
		get_tree().quit(2)
		return
	# Hash once before scene construction and before either sampling clock.
	# No file hashing or resource/tree census occurs inside measured frames.
	_build_fingerprint = _capture_build_fingerprint()
	_apply_quality_without_persisting()
	_startup_msaa = _msaa_metadata(String(SettingsManager.get_setting("display", "msaa")),
			SettingsManager.msaa_3d_mode(), get_viewport().msaa_3d)
	if _force_window_size:
		# apply_all() includes the saved resolution, so requested benchmark geometry
		# must be applied after the fixed tier is installed. The profile also writes
		# the requested resolution into the in-memory settings copy for consistency.
		DisplayServer.window_set_size(Vector2i(_width, _height))
		DisplayServer.window_set_position(Vector2i(40, 60))
		DisplayServer.window_move_to_foreground()
	if _keep_visible:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	var packed := load(Game.SCENE_RUNNER) as PackedScene
	if packed == null:
		push_error("runner_perf_probe: runner scene missing")
		get_tree().quit(2)
		return
	RunnerPlayer.autopilot = true
	_started_at_msec = Time.get_ticks_msec()
	_last_frame_usec = Time.get_ticks_usec()
	_game = packed.instantiate() as RunnerGame
	_game.generation_seed = _seed
	if _stream_trace_requested:
		_stream_trace = StreamTraceWindow.new()
		_stream_trace_previous = RunnerTrack.perf_trace_enabled
		RunnerTrack.perf_trace_enabled = true
		_stream_trace_armed = true
	add_child(_game)
	print("[runner_perf] %s %dx%d warmup=%.1fs sample=%.1fs" % [
		_tier, _width, _height, _warmup_seconds, _sample_seconds])


func _process(_delta: float) -> void:
	if _finished or _game == null:
		return
	# Godot's simulation delta can be capped/smoothed after a stall. The player
	# experiences real elapsed time; use the monotonic clock for all FPS gates.
	var now_usec := Time.get_ticks_usec()
	var interval_start_usec := _last_frame_usec
	var frame_seconds := float(now_usec - interval_start_usec) * 0.000001
	_last_frame_usec = now_usec
	var wall_seconds := float(Time.get_ticks_msec() - _started_at_msec) * 0.001
	if not _game.build_finished or not _game.running:
		if _stream_trace_requested:
			_collect_stream_trace({}, now_usec, "startup")
		if _seen_running and not _game.running:
			_abort("runner ended before performance sample completed")
		elif wall_seconds > _warmup_seconds + _sample_seconds + STARTUP_GRACE_SECONDS:
			_abort("runner did not complete performance sample before timeout")
		return
	_seen_running = true
	_run_time += frame_seconds
	_observe_workload_pose("warmup" if _run_time < _warmup_seconds else "sample")
	if _run_time < _warmup_seconds:
		if _stream_trace_requested:
			_collect_stream_trace({}, now_usec, "warmup")
		return
	_sample_time += frame_seconds
	_frame_ms.append(frame_seconds * 1000.0)
	var draws := RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var primitives := RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var viewport_rid := get_viewport().get_viewport_rid()
	_workload_validity.record_visible_3d(
		RenderingServer.viewport_get_render_info(viewport_rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
			RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
		RenderingServer.viewport_get_render_info(viewport_rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
			RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		Engine.get_process_frames())
	if frame_seconds > 0.05 or _stream_trace_requested:
		var frame := _sample_frame_record(_frame_ms.size(), Engine.get_process_frames(),
			interval_start_usec, now_usec, _sample_time, _game.player.distance,
			_game.track.biome_at_z(_game.player.position.z), draws, primitives)
		if frame_seconds > 0.05:
			_slow_frames.append(frame)
		if _stream_trace_requested:
			_collect_stream_trace(frame, now_usec, "sample")
	_draw_calls.append(draws)
	_primitives.append(primitives)
	if primitives > _primitive_peak_seen:
		_primitive_peak_seen = primitives
		# Only scalar/context reads on a new maximum; never walk geometry here.
		_peak_primitive_sample = _capture_peak_sample(primitives, draws)
	if _sample_time >= _sample_seconds:
		_finish()


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.split("=", false, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"tier": _tier = parts[1].to_lower()
			"w": _width = maxi(int(parts[1]), 320)
			"h": _height = maxi(int(parts[1]), 320)
			"warmup": _warmup_seconds = maxf(float(parts[1]), 0.0)
			"seconds": _sample_seconds = maxf(float(parts[1]), 1.0)
			"out": _out_path = parts[1]
			"enforce": _enforce = parts[1].to_lower() in ["1", "true", "yes"]
			"seed": _seed = int(parts[1])
			"keep_visible": _keep_visible = parts[1].to_lower() in ["1", "true", "yes"]
			"census": _census_requested = parts[1].to_lower() in ["1", "true", "yes"]
			"stream_trace": _stream_trace_requested = parts[1].to_lower() in ["1", "true", "yes"]


func _apply_quality_without_persisting() -> void:
	# set_setting() writes settings.json. A benchmark must not alter the
	# player's choice, so change the in-memory copy and run the ordinary apply
	# path. run_tests.sh additionally supplies an isolated user://.
	var display: Dictionary = SettingsManager.settings.get("display", {}).duplicate(true)
	display["quality_preset"] = _tier
	display["shadow_quality"] = _tier
	display["particle_quality"] = _tier
	display["msaa"] = {"high": "4x", "medium": "2x", "low": "off"}[_tier]
	if _force_window_size:
		display["window_mode"] = "windowed"
		display["resolution"] = "%dx%d" % [_width, _height]
	display["fps_limit"] = 0
	SettingsManager.settings["display"] = display
	# Fixed-tier probe, not governor probe. Otherwise a requested high/medium run
	# can silently report a pass after measuring a lower effective tier.
	SettingsManager._governor_override = ""
	SettingsManager._governor_steps = SettingsManager.GOVERNOR_MAX_STEPS
	SettingsManager._render_scale_step = 0
	if _force_window_size:
		SettingsManager.apply_all()
	else:
		# `apply_all()` reapplies window_mode, which recursively writes resolution.
		# Apply only display controls relevant to the controlled initial-high load;
		# production page scripts remain sole owner of CSS/backing dimensions.
		for key: String in ["vsync", "quality_preset", "shadow_quality",
				"particle_quality", "msaa", "fps_limit"]:
			SettingsManager._apply_display(key, display[key])


func _finish() -> void:
	_finished = true
	_restore_stream_trace_flag()
	var sorted_ms: Array[float] = []
	for value: float in _frame_ms:
		sorted_ms.append(value)
	sorted_ms.sort()
	var average_ms := _average_float(_frame_ms)
	var p95_ms := _percentile(sorted_ms, 0.95)
	var max_ms := sorted_ms[-1] if not sorted_ms.is_empty() else 0.0
	var average_fps := 1000.0 / average_ms if average_ms > 0.0 else 0.0
	var draw_average := _average_int(_draw_calls)
	var draw_peak := _max_int(_draw_calls)
	var primitive_peak := _max_int(_primitives)
	var over_100 := 0
	for value: float in _frame_ms:
		if value > 100.0:
			over_100 += 1
	var draw_limits: Vector2i = DRAW_LIMITS[_tier]
	var actual_size := DisplayServer.window_get_size()
	var resolution_matches := actual_size == Vector2i(_width, _height)
	var effective_tier := String(SettingsManager.get_setting("display", "quality_preset"))
	var tier_matches := effective_tier == _tier
	var fps_min := 29.0 if _tier == "low" else 57.0
	var p95_max := 36.0 if _tier == "low" else 20.0
	var performance_thresholds_met := average_fps >= fps_min and p95_ms <= p95_max \
		and max_ms <= 100.0 and draw_average <= draw_limits.x \
		and draw_peak <= draw_limits.y \
		and primitive_peak <= int(PRIMITIVE_LIMITS[_tier]) \
		and tier_matches
	var workload_validation := _workload_validity.report()
	var workload_valid := bool(workload_validation.valid)
	var meets_gate := _fixed_resolution_gate_applicable \
		and performance_thresholds_met and resolution_matches and workload_valid
	var measurement_eligibility := {
		"eligible": meets_gate if _fixed_resolution_gate_applicable else false,
		"native_size_workload_accepted": false,
		"fixed_resolution_gate_applicable": _fixed_resolution_gate_applicable,
		"performance_thresholds_met": performance_thresholds_met,
		"workload_valid": workload_valid,
		"canvas_policy_reconciled": false if not _fixed_resolution_gate_applicable else null,
		"not_complete_production": not _fixed_resolution_gate_applicable,
		"complete_production": false,
		"reason": "runner_workload_invalid" if not workload_valid else (
			"fixed_resolution_gate_result" if _fixed_resolution_gate_applicable
			else "pending_browser_canvas_reconciliation"),
	}
	var report: Dictionary = {
		"schema_version": 3,
		"mode": "runner",
		"seed": _seed,
		"tier": _tier,
		"resolution": [actual_size.x, actual_size.y],
		"requested_resolution": [_width, _height],
		"requested_probe_size": [_width, _height],
		"requested_probe_size_scope": "Fixed backing request when applicable; reference only for page-owned production canvas",
		"actual_window_size": [actual_size.x, actual_size.y],
		"window_size_policy": _window_size_policy,
		"resolution_matches_request": resolution_matches,
		"renderer": RenderingServer.get_current_rendering_method(),
		"platform": OS.get_name(),
		"quality": {
			"requested_tier": _tier,
			"effective_tier": effective_tier,
			"shadow_quality": SettingsManager.get_setting("display", "shadow_quality"),
			"particle_quality": SettingsManager.get_setting("display", "particle_quality"),
			"msaa": SettingsManager.get_setting("display", "msaa"),
			"msaa_legacy_field_scope": "requested setting only; not the effective viewport mode",
			"msaa_before_scene_build": _startup_msaa,
			"msaa_after_measurement": _msaa_metadata(
					String(SettingsManager.get_setting("display", "msaa")),
					SettingsManager.msaa_3d_mode(), get_viewport().msaa_3d),
			"msaa_observation_scope": "Viewport settings before scene construction and after timing; not continuous GPU sample queries",
		},
		"warmup_seconds": _warmup_seconds,
		"sample_seconds": _sample_time,
		"sample_frames": _frame_ms.size(),
		"frame_time_source": "monotonic_wall_clock",
		"slow_frames_over_50_ms": _slow_frames,
		"stream_trace": _stream_trace_report(),
		"average_fps": snappedf(average_fps, 0.01),
		"average_frame_ms": snappedf(average_ms, 0.01),
		"p95_frame_ms": snappedf(p95_ms, 0.01),
		"max_frame_ms": snappedf(max_ms, 0.01),
		"frames_over_100_ms": over_100,
		"draw_calls_average": snappedf(draw_average, 0.01),
		"draw_calls_peak": draw_peak,
		"primitives_peak": primitive_peak,
		"primitive_monitor_note": PRIMITIVE_MONITOR_NOTE,
		"peak_primitive_sample": _peak_primitive_sample,
		"build_fingerprint": _build_fingerprint,
		"geometry_census_requested": _census_requested,
		"geometry_census": _final_census_report(_game, _census_requested,
				_game.player.distance, _sample_time),
		"video_memory_bytes": RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_VIDEO_MEM_USED),
		"gate": {
			"average_fps_min": fps_min,
			"p95_frame_ms_max": p95_max,
			"max_frame_ms": 100.0,
			"draw_calls_average_max": draw_limits.x,
			"draw_calls_peak_max": draw_limits.y,
			"primitives_peak_max": PRIMITIVE_LIMITS[_tier],
			"resolution_must_match_request": _fixed_resolution_gate_applicable,
			"fixed_resolution_gate_applicable": _fixed_resolution_gate_applicable,
			"tier_must_match_request": true,
		},
		"performance_thresholds_met": performance_thresholds_met,
		"workload_valid": workload_valid,
		"workload_validation": workload_validation,
		"measurement_eligibility": measurement_eligibility,
		"meets_gate": meets_gate,
	}
	var save_error := _write_report(report)
	print("[runner_perf] actual=%dx%d avg=%.1ffps p95=%.1fms max=%.1fms draws=%.0f/%d primitives=%d gate=%s" % [
		actual_size.x, actual_size.y,
		average_fps, p95_ms, max_ms, draw_average, draw_peak,
		primitive_peak, "PASS" if meets_gate else "FAIL"])
	RunnerPlayer.autopilot = false
	get_tree().quit(1 if save_error != OK or (_enforce and not meets_gate) else 0)


func _observe_workload_pose(phase: String) -> void:
	if _game.player == null or _game.camera == null:
		_workload_validity.record_missing_pose(phase, Engine.get_process_frames())
		return
	_workload_validity.record_pose(_game.camera.global_transform,
		_game.player.global_position, _game._camera_hero_height, _game.camera.fov,
		_game.camera.near, _game.camera.far, phase, Engine.get_process_frames())


func _write_report(report: Dictionary) -> Error:
	var absolute := ProjectSettings.globalize_path(_out_path)
	var dir_error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if dir_error != OK:
		push_error("runner_perf_probe: cannot create output directory (%d)" % dir_error)
		return dir_error
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	var csv_path := absolute.get_basename() + ".csv"
	var csv := FileAccess.open(csv_path, FileAccess.WRITE)
	if csv == null:
		return FileAccess.get_open_error()
	var columns: PackedStringArray = [
		"tier", "width", "height", "renderer", "sample_frames",
		"average_fps", "average_frame_ms", "p95_frame_ms", "max_frame_ms",
		"frames_over_100_ms", "draw_calls_average", "draw_calls_peak",
		"primitives_peak", "video_memory_bytes", "meets_gate",
	]
	csv.store_csv_line(columns)
	csv.store_csv_line(PackedStringArray([
		String(report["tier"]), str((report["resolution"] as Array)[0]),
		str((report["resolution"] as Array)[1]), String(report["renderer"]),
		str(report["sample_frames"]), str(report["average_fps"]),
		str(report["average_frame_ms"]), str(report["p95_frame_ms"]),
		str(report["max_frame_ms"]), str(report["frames_over_100_ms"]),
		str(report["draw_calls_average"]), str(report["draw_calls_peak"]),
		str(report["primitives_peak"]), str(report["video_memory_bytes"]),
		str(report["meets_gate"]),
	]))
	csv.close()
	print("[runner_perf] wrote %s and %s" % [absolute, csv_path])
	return OK


func _capture_peak_sample(primitives: int, draws: int) -> Dictionary:
	var viewport_rid := get_viewport().get_viewport_rid()
	var snapshot := {
		"sample_time": _sample_time,
		"process_frame": Engine.get_process_frames(),
		"distance": _game.player.distance,
		"biome": _game.track.biome_at_z(_game.player.position.z),
		"total_primitives_monitor": primitives,
		"total_draw_calls_monitor": draws,
		"viewport_visible_primitives_monitor": RenderingServer.viewport_get_render_info(
				viewport_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
				RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		"viewport_shadow_primitives_monitor": RenderingServer.viewport_get_render_info(
				viewport_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW,
				RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		"viewport_visible_objects_monitor": RenderingServer.viewport_get_render_info(
				viewport_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
				RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
		"resolution": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"sampling_note": "Process-time context accompanying engine counters, which may describe the preceding draw; not synchronized GPU attribution.",
	}
	snapshot.merge(_game.track.perf_trace_snapshot(_game.player.position.z))
	if _game.camera != null:
		var camera_transform := _game.camera.global_transform
		snapshot["camera"] = {
			"position": _vector_components(camera_transform.origin),
			"basis_x": _vector_components(camera_transform.basis.x),
			"basis_y": _vector_components(camera_transform.basis.y),
			"basis_z": _vector_components(camera_transform.basis.z),
			"fov": _game.camera.fov,
			"near": _game.camera.near,
			"far": _game.camera.far,
			"viewport_mesh_lod_threshold": get_viewport().mesh_lod_threshold,
		}
	return snapshot


static func _msaa_metadata(requested: String, effective_mode: int, actual_mode: int) -> Dictionary:
	var labels := ["off", "2x", "4x", "8x"]
	var samples := [1, 2, 4, 8]
	var effective_known := effective_mode >= 0 and effective_mode < labels.size()
	var actual_known := actual_mode >= 0 and actual_mode < labels.size()
	return {"requested": requested, "effective_mode": effective_mode, "actual_mode": actual_mode,
		"effective": labels[effective_mode] if effective_known else "unknown",
		"actual": labels[actual_mode] if actual_known else "unknown",
		"effective_samples": samples[effective_mode] if effective_known else null,
		"actual_samples": samples[actual_mode] if actual_known else null,
		"viewport_matches_policy": effective_known and actual_known and effective_mode == actual_mode,
		"viewport_matches_request": actual_known and requested == labels[actual_mode]}


static func _sample_frame_record(sample_id: int, process_frame: int,
		start_usec: int, end_usec: int, sample_time: float, distance: float,
		biome: int, draws: int, primitives: int) -> Dictionary:
	return {"sample_frame_id": sample_id, "process_frame": process_frame,
		"interval_start_usec": start_usec, "interval_end_usec": end_usec,
		"sample_time": sample_time, "frame_ms": float(end_usec - start_usec) * 0.001,
		"distance": distance, "biome": biome, "draws": draws,
		"total_primitives_monitor": primitives}


func _collect_stream_trace(frame: Dictionary, now_usec: int, phase: String) -> void:
	if _stream_trace == null or _game == null or _game.track == null:
		return
	var started := Time.get_ticks_usec()
	var track := _game.track
	var process_frame := Engine.get_process_frames()
	var events := track.drain_perf_trace_events()
	var observed_ids := _stream_trace.record_events(events, process_frame, now_usec,
		int(frame.get("sample_frame_id", 0)), phase)
	if not frame.is_empty():
		# Only scalar fields: no perf_trace_snapshot(), which walks live chunks.
		frame["current_chunk"] = track._chunk_index_at(_game.player.position.z)
		frame["first_chunk"] = track._first_index
		frame["next_chunk"] = track._next_index
		frame["live_chunks"] = track._chunks.size()
		frame["observed_stream_event_ids"] = observed_ids
		_stream_trace.record_frame(frame)
	var bookkeeping_us := Time.get_ticks_usec() - started
	_stream_trace_bookkeeping_total_us += bookkeeping_us
	_stream_trace_bookkeeping_max_us = maxi(_stream_trace_bookkeeping_max_us, bookkeeping_us)


func _stream_trace_report() -> Dictionary:
	var sources: Array[Dictionary] = []
	for entry: Dictionary in _build_fingerprint.get("entries", []):
		if entry.path in ["res://tests/runner_perf_probe.gd", "res://scripts/runner/runner_track.gd",
				"res://scripts/runner/runner_game.gd", "res://scripts/runner/runner_config.gd"]:
			sources.append(entry)
	var report := {"requested": _stream_trace_requested,
		"captured": _stream_trace != null, "source_scripts": sources,
		"source_binding_scope": "Exact pre-run fingerprint entries; no timed-loop hashing.",
		"event_limit": STREAM_TRACE_EVENT_LIMIT, "window_limit": STREAM_TRACE_WINDOW_LIMIT,
		"neighbor_frames_each_side": STREAM_TRACE_NEIGHBOR_FRAMES,
		"over_30_ms_row_limit": STREAM_TRACE_SLOW_ROW_LIMIT,
		"counter_scope": "Process-time reads may describe the preceding draw; no GPU synchronization or timestamp query.",
		"time_scope": "interval_*_usec and observed_usec use the same monotonic process clock. sample_frame_id is one-based after warmup. source_process_frame is the event's original Engine frame; observed_* fields describe its later drain, not event start/end time.",
		"cpu_scope": "Existing spawn stage timings and combined stream CPU time only. Retired indices/counts are recorded; no independent retirement, driver-upload, shader-compile or GPU duration is inferred.",
		"correlation_scope": "Observed events share a collection interval with a frame; correlation does not establish hitch cause.",
		"overhead_scope": "Opt-in dictionary/ring bookkeeping plus existing CPU trace timers. No screenshots, pixel readbacks, geometry walks or timed-loop printing. Bookkeeping timings cover drain/window collection only, excluding sample-row creation, producer trace overhead and rendering stalls; diagnostic timings are instrumented, not baseline-equivalent. Existing FPS/slow-row arrays retain their duration-dependent storage; added event/window storage is bounded.",
		"bookkeeping_total_us": _stream_trace_bookkeeping_total_us,
		"bookkeeping_max_us": _stream_trace_bookkeeping_max_us,
		"events": [], "windows": [], "events_dropped": 0, "windows_dropped": 0}
	if _stream_trace != null:
		report.merge(_stream_trace.report(), true)
	return report


func _restore_stream_trace_flag() -> void:
	if _stream_trace_armed:
		RunnerTrack.perf_trace_enabled = _stream_trace_previous
		_stream_trace_armed = false


func _exit_tree() -> void:
	_restore_stream_trace_flag()


class WorkloadValidity extends RefCounted:
	## QA rejection only: never repair poses or hide an invalid workload.
	## Cached engine counters may describe the preceding draw, not GPU completion.
	## Scalar pose/counter reads add instrumentation cost; no zero-overhead claim.
	var pose_frames_checked: int = 0
	var sample_pose_frames_checked: int = 0
	var sample_3d_frames_checked: int = 0
	var invalid_pose_frames: int = 0
	var missing_visible_3d_frames: int = 0
	var longest_missing_3d_streak: int = 0
	var _missing_3d_streak: int = 0
	var visible_objects_min: int = -1
	var visible_objects_peak: int = 0
	var visible_primitives_min: int = -1
	var visible_primitives_peak: int = 0
	var failure_counts: Dictionary = {}
	var first_failure: Dictionary = {}

	func record_missing_pose(phase: String, process_frame: int) -> void:
		_count_pose(phase)
		invalid_pose_frames += 1
		_record_failure("runner_pose_missing", {"phase": phase,
			"process_frame": process_frame})

	func record_pose(camera_transform: Transform3D, player_position: Vector3,
			hero_height: float, fov: float, near: float, far: float,
			phase: String, process_frame: int) -> void:
		_count_pose(phase)
		var reason := pose_failure(camera_transform, player_position,
			hero_height, fov, near, far)
		if reason.is_empty():
			return
		invalid_pose_frames += 1
		# Allocate detailed context only on the first failure, never each frame.
		var snapshot: Dictionary = {}
		if first_failure.is_empty():
			snapshot = {"phase": phase, "process_frame": process_frame,
				"camera_position": _safe_vector(camera_transform.origin),
				"player_position": _safe_vector(player_position),
				"camera_relative_to_player": _safe_vector(camera_transform.origin - player_position),
				"camera_basis_determinant": _safe_float(camera_transform.basis.determinant()),
				"hero_height": _safe_float(hero_height), "fov": _safe_float(fov),
				"near": _safe_float(near), "far": _safe_float(far)}
		_record_failure(reason, snapshot)

	func record_visible_3d(objects: int, primitives: int, process_frame: int) -> void:
		sample_3d_frames_checked += 1
		visible_objects_min = objects if sample_3d_frames_checked == 1 else mini(visible_objects_min, objects)
		visible_primitives_min = primitives if sample_3d_frames_checked == 1 else mini(visible_primitives_min, primitives)
		visible_objects_peak = maxi(visible_objects_peak, objects)
		visible_primitives_peak = maxi(visible_primitives_peak, primitives)
		if objects > 0 and primitives > 0:
			_missing_3d_streak = 0
			return
		missing_visible_3d_frames += 1
		_missing_3d_streak += 1
		longest_missing_3d_streak = maxi(longest_missing_3d_streak, _missing_3d_streak)
		var reason := "visible_3d_monitor_invalid" if objects < 0 or primitives < 0 else "visible_3d_missing"
		_record_failure(reason, {"phase": "sample", "process_frame": process_frame,
			"viewport_visible_objects_monitor": objects,
			"viewport_visible_primitives_monitor": primitives} if first_failure.is_empty() else {})

	func _count_pose(phase: String) -> void:
		pose_frames_checked += 1
		if phase == "sample":
			sample_pose_frames_checked += 1

	func _record_failure(reason: String, snapshot: Dictionary) -> void:
		failure_counts[reason] = int(failure_counts.get(reason, 0)) + 1
		if first_failure.is_empty():
			first_failure = snapshot
			first_failure["reason"] = reason

	func report() -> Dictionary:
		var complete := sample_3d_frames_checked > 0 \
			and sample_pose_frames_checked == sample_3d_frames_checked
		var valid := complete and invalid_pose_frames == 0 and missing_visible_3d_frames == 0
		return {"captured": sample_3d_frames_checked > 0, "valid": valid,
			"reason": "no_complete_measured_workload" if not complete else (
				"invalid_runner_pose" if invalid_pose_frames > 0 else (
					"missing_visible_3d_workload" if missing_visible_3d_frames > 0 else "valid_runner_workload")),
			"pose_frames_checked": pose_frames_checked,
			"sample_pose_frames_checked": sample_pose_frames_checked,
			"sample_3d_frames_checked": sample_3d_frames_checked,
			"invalid_pose_frames": invalid_pose_frames,
			"missing_visible_3d_frames": missing_visible_3d_frames,
			"longest_missing_3d_streak": longest_missing_3d_streak,
			"visible_objects_min": visible_objects_min if sample_3d_frames_checked > 0 else null,
			"visible_objects_peak": visible_objects_peak,
			"visible_primitives_min": visible_primitives_min if sample_3d_frames_checked > 0 else null,
			"visible_primitives_peak": visible_primitives_peak,
			"failure_counts": failure_counts.duplicate(), "first_failure": first_failure.duplicate(true),
			"scope": "QA-only broad pose sanity on running/warmup and sample frames; nonempty cached viewport visible-3D counters on every measured frame. Counts may describe preceding draw, not GPU completion. Scalar reads/bookkeeping add instrumentation; no tree inventory, mesh bake, GL query, or camera repair.",
			"bounds": {"camera_relative_abs_max": [64.0, 64.0, 256.0],
				"player_abs_x_max": 64.0, "player_abs_y_max": 128.0,
				"authored_hero_height": [0.1, 10.0], "legacy_hero_height": 0.0}}

	static func pose_failure(camera_transform: Transform3D, player_position: Vector3,
			hero_height: float, fov: float, near: float, far: float) -> String:
		var origin := camera_transform.origin
		var basis := camera_transform.basis
		if not origin.is_finite() or not player_position.is_finite():
			return "runner_position_nonfinite"
		if not basis.x.is_finite() or not basis.y.is_finite() or not basis.z.is_finite() \
				or not is_finite(basis.determinant()) or absf(basis.determinant()) < 0.25 \
				or absf(basis.determinant()) > 4.0:
			return "camera_basis_invalid"
		if not is_finite(hero_height) or (hero_height != 0.0 and (hero_height < 0.1 or hero_height > 10.0)):
			return "hero_height_invalid"
		if absf(player_position.x) > 64.0 or absf(player_position.y) > 128.0:
			return "player_position_out_of_bounds"
		var relative := origin - player_position
		if not relative.is_finite() or absf(relative.x) > 64.0 \
				or absf(relative.y) > 64.0 or absf(relative.z) > 256.0:
			return "camera_relative_out_of_bounds"
		if not is_finite(fov) or fov <= 1.0 or fov >= 179.0 \
				or not is_finite(near) or not is_finite(far) or near <= 0.0 or far <= near:
			return "camera_projection_invalid"
		return ""

	static func _safe_float(value: float) -> Variant:
		return value if is_finite(value) else str(value)

	static func _safe_vector(value: Vector3) -> Array:
		return [_safe_float(value.x), _safe_float(value.y), _safe_float(value.z)]


class StreamTraceWindow extends RefCounted:
	## Bounded raw head + rolling tail, plus event rows shared by recent frames
	## and strongest slow neighborhoods. Raw eviction is not total evidence loss:
	## a pinned frame can retain an event after it leaves the raw log.
	var events: Array[Dictionary] = []
	var windows: Array[Dictionary] = []
	var recent: Array[Dictionary] = []
	var events_seen: int = 0
	var events_dropped: int = 0
	var windows_dropped: int = 0
	var windows_seen: int = 0
	var windows_evicted: int = 0
	var frames_over_30_ms: Array[Dictionary] = []
	var over_30_ms_rows_dropped: int = 0
	var _pending_events: Array[Dictionary] = []
	var _pending_ids: PackedInt32Array = PackedInt32Array()
	var _pending_sample_id: int = -1
	var _pending_process_frame: int = -1
	var _pending_rows_dropped: int = 0

	func record_events(incoming: Array[Dictionary], process_frame: int, observed_usec: int,
			sample_id: int, phase: String) -> PackedInt32Array:
		var ids := PackedInt32Array()
		# Replace rather than clear: retained frames own their old bounded array.
		_pending_events = []
		_pending_rows_dropped = 0
		_pending_sample_id = sample_id
		_pending_process_frame = process_frame
		for source: Dictionary in incoming:
			events_seen += 1
			var event := source.duplicate(true)
			event["event_id"] = events_seen
			event["source_process_frame"] = int(source.get("frame", -1))
			event["observed_process_frame"] = process_frame
			event["observed_usec"] = observed_usec
			event["observed_sample_frame_id"] = sample_id
			event["phase"] = phase
			events.append(event)
			if events.size() > STREAM_TRACE_EVENT_LIMIT:
				# Keep first head rows permanently, evict oldest rolling-tail row.
				events.remove_at(STREAM_TRACE_HEAD_EVENT_LIMIT)
				events_dropped += 1
			_pending_events.append(event)
			if _pending_events.size() > STREAM_TRACE_FRAME_EVENT_LIMIT:
				_pending_events.pop_front()
				_pending_rows_dropped += 1
			ids.append(events_seen)
		_pending_ids = ids
		return ids

	func record_frame(frame: Dictionary) -> void:
		# Caller also retains slow rows in its historical duration-dependent array.
		# Never enrich that dictionary with raw objects; only our bounded recent/
		# window storage owns this shallow copy and its bounded event references.
		frame = frame.duplicate()
		var observed := (_pending_sample_id == int(frame.sample_frame_id)
				and _pending_process_frame == int(frame.process_frame))
		frame["stream_event_observation"] = "drained" if observed else "missing_drain"
		frame["observed_stream_event_ids"] = _pending_ids if observed else PackedInt32Array()
		frame["observed_stream_event_rows_dropped"] = _pending_rows_dropped if observed else 0
		# Frame dictionaries become immutable after this seam; overlapping windows
		# share them rather than deep-copying seventeen rows for every hitch.
		if float(frame.frame_ms) > 30.0:
			if frames_over_30_ms.size() < STREAM_TRACE_SLOW_ROW_LIMIT:
				# Scalar diagnostic rows do not independently pin raw event objects.
				var scalar_frame := frame.duplicate()
				scalar_frame.erase("observed_stream_event_rows")
				frames_over_30_ms.append(scalar_frame)
			else:
				over_30_ms_rows_dropped += 1
		frame["observed_stream_event_rows"] = _pending_events if observed else []
		for window: Dictionary in windows:
			if window.frames_after_remaining > 0:
				window.frames.append(frame)
				window.frames_after_remaining -= 1
		if float(frame.frame_ms) > 50.0:
			windows_seen += 1
			var retain := windows.size() < STREAM_TRACE_WINDOW_LIMIT
			if not retain:
				windows_dropped += 1
				var weakest := 0
				for index: int in range(1, windows.size()):
					if float(windows[index].trigger_frame_ms) < float(windows[weakest].trigger_frame_ms):
						weakest = index
				if float(frame.frame_ms) > float(windows[weakest].trigger_frame_ms):
					windows.remove_at(weakest)
					windows_evicted += 1
					retain = true
			if retain:
				var rows := recent.duplicate()
				rows.append(frame)
				windows.append({"trigger_sample_frame_id": frame.sample_frame_id,
					"trigger_process_frame": frame.process_frame,
					"trigger_frame_ms": float(frame.frame_ms),
					"frames_before_recorded": recent.size(),
					"frames_after_remaining": STREAM_TRACE_NEIGHBOR_FRAMES, "frames": rows})
		recent.append(frame)
		if recent.size() > STREAM_TRACE_NEIGHBOR_FRAMES:
			recent.pop_front()

	func report() -> Dictionary:
		var retained_ids: Dictionary = {}
		for event: Dictionary in events:
			retained_ids[int(event.event_id)] = true
		var reported_windows: Array[Dictionary] = []
		for window: Dictionary in windows:
			var row := window.duplicate()
			var observed_ids: Dictionary = {}
			var window_event_ids: Dictionary = {}
			var missing_drains := 0
			for frame: Dictionary in window.frames:
				if frame.get("stream_event_observation", "missing_drain") == "missing_drain":
					missing_drains += 1
				for id: int in frame.get("observed_stream_event_ids", PackedInt32Array()):
					observed_ids[id] = true
				for event: Dictionary in frame.get("observed_stream_event_rows", []):
					window_event_ids[int(event.event_id)] = true
					retained_ids[int(event.event_id)] = true
			row["event_rows_retained_unique"] = window_event_ids.size()
			row["event_rows_inline_missing"] = observed_ids.size() - window_event_ids.size()
			var observed_sorted: Array = observed_ids.keys()
			observed_sorted.sort()
			row["observed_event_ids"] = observed_sorted
			row["frames_missing_drain"] = missing_drains
			reported_windows.append(row)
		# Only count rows actually serialized below. The recent/pending rings can
		# own evicted objects in memory without exporting them as evidence.
		var unique_ids: Array = retained_ids.keys()
		unique_ids.sort()
		for window: Dictionary in reported_windows:
			var missing_ids: Array[int] = []
			for id: int in window.observed_event_ids:
				if not retained_ids.has(id):
					missing_ids.append(id)
			window["event_rows_missing"] = missing_ids.size()
			window["event_rows_missing_ids"] = missing_ids
			window["event_rows_available_unique"] = window.observed_event_ids.size() - missing_ids.size()
		return {"events": events, "windows": reported_windows, "events_seen": events_seen,
			"events_dropped": events_dropped, "windows_dropped": windows_dropped,
			"windows_seen": windows_seen, "windows_evicted": windows_evicted,
			"event_retention": "First64 head + latest192 raw rows; shared bounded frame rows pin strongest8 slow neighborhoods",
			"events_dropped_scope": "Raw-log eviction only; pinned/recent frame rows may still retain evicted IDs",
			"event_rows_retained_unique": retained_ids.size(),
			"event_rows_retained_scope": "Unique rows serialized in raw events and slow windows only; excludes unexported recent/pending buffers",
			"event_rows_retained_ids": unique_ids,
			"event_rows_unavailable": events_seen - retained_ids.size(),
			"frame_event_row_limit": STREAM_TRACE_FRAME_EVENT_LIMIT,
			"head_event_limit": STREAM_TRACE_HEAD_EVENT_LIMIT,
			"raw_event_limit": STREAM_TRACE_EVENT_LIMIT,
			"event_object_upper_bound": STREAM_TRACE_EVENT_LIMIT \
					+ STREAM_TRACE_FRAME_EVENT_LIMIT * (STREAM_TRACE_WINDOW_LIMIT \
							* (2 * STREAM_TRACE_NEIGHBOR_FRAMES + 1) + STREAM_TRACE_NEIGHBOR_FRAMES + 1),
			"frames_over_30_ms": frames_over_30_ms, "over_30_ms_rows_dropped": over_30_ms_rows_dropped,
			"upstream_capacity": RunnerTrack.PERF_TRACE_MAX_EVENTS,
			"upstream_overflow_scope": "RunnerTrack bounds its producer queue independently and exposes no overflow counter; an event missing before drain cannot be ruled out by events_dropped=0."}


static func _vector_components(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


static func _capture_build_fingerprint() -> Dictionary:
	var paths := PackedStringArray([
		"res://project.godot", "res://tests/runner_perf_probe.gd", Game.SCENE_RUNNER,
		ArtCatalog.DEFAULT_MANIFEST_PATH, "res://scripts/shaders/hero_penguin_v1.gdshader",
	])
	for directory: String in FINGERPRINT_ROOTS:
		_collect_fingerprint_paths(directory, paths)
	return _fingerprint_paths(paths)


static func _collect_fingerprint_paths(directory: String, paths: PackedStringArray) -> void:
	if not DirAccess.dir_exists_absolute(directory):
		paths.append(directory) # Missing scope is explicit, never silently omitted.
		return
	for filename: String in DirAccess.get_files_at(directory):
		if filename.get_extension() in FINGERPRINT_EXTENSIONS:
			paths.append(directory.path_join(filename))
	for child: String in DirAccess.get_directories_at(directory):
		_collect_fingerprint_paths(directory.path_join(child), paths)


static func _fingerprint_paths(requested: PackedStringArray) -> Dictionary:
	var unique: Dictionary = {}
	var unsupported_remaps: Array[Dictionary] = []
	for path: String in requested:
		unique[path] = true
		if path.ends_with(".glb"):
			var import_path := path + ".import"
			unique[import_path] = true
			var config := ConfigFile.new()
			if config.load(import_path) == OK:
				var remapped := String(config.get_value("remap", "path", ""))
				if _remap_is_in_scope(remapped):
					unique[remapped] = true
				else:
					unsupported_remaps.append({"source": path, "remap": remapped,
						"reason": "Expected a canonical res://.godot/imported/ file; not read."})
	var paths := PackedStringArray(unique.keys())
	paths.sort()
	var entries: Array[Dictionary] = []
	var missing := PackedStringArray()
	var signature := PackedStringArray()
	var source_signature := PackedStringArray()
	for path: String in paths:
		var digest := FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
		if digest.is_empty():
			missing.append(path)
		entries.append({"path": path, "sha256": digest})
		signature.append(path + "\t" + digest)
		if path != "res://project.godot" and not path.begins_with("res://.godot/") \
				and not path.ends_with(".import"):
			source_signature.append(path + "\t" + digest)
	return {
		"sha256": "\n".join(signature).sha256_text(),
		"source_assets_sha256": "\n".join(source_signature).sha256_text(),
		"source_assets_scope": "Comparable source subset only: excludes project.godot (isolated user identity), .import metadata and remapped .godot caches. Exact excluded file hashes remain in entries and sha256. Not a complete build-equivalence assertion.",
		"entries": entries,
		"missing_or_unreadable": missing,
		"unsupported_remaps": unsupported_remaps,
		"complete": missing.is_empty() and unsupported_remaps.is_empty(),
		"build_id": GameConfig.BUILD_ID,
		"engine": Engine.get_version_info(),
		"timing_scope": "Captured once before scene construction and measured clocks; no per-frame hashing.",
		"coverage": "Runner/shared scripts, DAY/hero GLBs and remapped imported scenes, art contracts and material/scene text. Not a whole-repository or texture-pixel fingerprint.",
	}


static func _remap_is_in_scope(path: String) -> bool:
	return path.begins_with("res://.godot/imported/") and not path.get_file().is_empty() \
			and path.simplify_path() == path


static func _final_census_report(root: Node, requested: bool, distance: float,
		sample_time: float) -> Dictionary:
	var report := {
		"requested": requested,
		"captured": false,
		"scope": "final_scene_after_timing_not_peak",
		"visibility_scope": "Subtree Node3D.visible and MultiMesh enabled-instance limits only; not GPU visibility, frustum, occlusion, visibility-range or selected-LOD attribution.",
		"distance": distance,
		"sample_time": sample_time,
		"families": {},
		"meshes": [],
		"unsupported_geometry_nodes": {},
	}
	if not requested or root == null:
		return report
	var mesh_ids: Dictionary = {}
	_collect_geometry_census(root, true, report, mesh_ids)
	report["captured"] = true
	return report


static func _collect_geometry_census(node: Node, ancestors_visible: bool,
		report: Dictionary, mesh_ids: Dictionary) -> void:
	var subtree_visible := ancestors_visible
	if node is Node3D:
		subtree_visible = subtree_visible and (node as Node3D).visible
	var mesh: Mesh = null
	var instances := 1
	var allocated_instances := 1
	if node is MeshInstance3D:
		mesh = (node as MeshInstance3D).mesh
	elif node is MultiMeshInstance3D:
		var multi := (node as MultiMeshInstance3D).multimesh
		if multi != null:
			mesh = multi.mesh
			allocated_instances = multi.instance_count
			instances = _enabled_multimesh_instances(multi.instance_count, multi.visible_instance_count)
	if mesh != null:
		var mesh_id := mesh.get_instance_id()
		if not mesh_ids.has(mesh_id):
			mesh_ids[mesh_id] = (report["meshes"] as Array).size()
			(report["meshes"] as Array).append(_mesh_census(mesh))
		var mesh_index := int(mesh_ids[mesh_id])
		var summary: Dictionary = report["meshes"][mesh_index]
		var family := String(node.get_meta("authored_asset_id", ""))
		if family.is_empty():
			family = "%s:%s" % [node.get_class(),
					String(node.name) if not String(node.name).begins_with("@") else "unnamed"]
		var families: Dictionary = report["families"]
		if not families.has(family):
			families[family] = {"geometry_nodes": 0, "subtree_visible_nodes": 0,
				"allocated_instances": 0, "enabled_instances": 0,
				"subtree_visible_enabled_instances": 0, "subtree_visible_lod0_instance_triangles": 0,
				"mesh_indices": []}
		var row: Dictionary = families[family]
		row["geometry_nodes"] += 1
		row["allocated_instances"] += allocated_instances
		row["enabled_instances"] += instances
		if mesh_index not in row["mesh_indices"]:
			(row["mesh_indices"] as Array).append(mesh_index)
		if subtree_visible:
			row["subtree_visible_nodes"] += 1
			row["subtree_visible_enabled_instances"] += instances
			row["subtree_visible_lod0_instance_triangles"] += int(summary["lod0_triangles"]) * instances
	elif node is GeometryInstance3D:
		var unsupported: Dictionary = report["unsupported_geometry_nodes"]
		unsupported[node.get_class()] = int(unsupported.get(node.get_class(), 0)) + 1
	for child: Node in node.get_children():
		_collect_geometry_census(child, subtree_visible, report, mesh_ids)


static func _enabled_multimesh_instances(allocated: int, visible_limit: int) -> int:
	return allocated if visible_limit < 0 else mini(allocated, maxi(0, visible_limit))


static func _mesh_census(mesh: Mesh) -> Dictionary:
	var summary := {"resource_path": mesh.resource_path, "resource_name": mesh.resource_name,
		"lod0_triangles": 0, "surfaces": [],
		"lod_scope": "Baked index alternatives only; no claim about selected runtime LOD."}
	var serialized: Array = []
	if mesh is ArrayMesh:
		var value: Variant = mesh.get("_surfaces")
		if value is Array:
			serialized = value
	for surface: int in mesh.get_surface_count():
		var indices: int
		var vertices: int
		var primitive: int = Mesh.PRIMITIVE_TRIANGLES
		if mesh is ArrayMesh:
			var array_mesh := mesh as ArrayMesh
			indices = array_mesh.surface_get_array_index_len(surface)
			vertices = array_mesh.surface_get_array_len(surface)
			primitive = array_mesh.surface_get_primitive_type(surface)
		else:
			# PrimitiveMesh exposes arrays through Mesh, not ArrayMesh's length API.
			# This allocation is confined to the optional post-timing inventory.
			var arrays := mesh.surface_get_arrays(surface)
			indices = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() \
					if arrays[Mesh.ARRAY_INDEX] != null else 0
			vertices = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() \
					if arrays[Mesh.ARRAY_VERTEX] != null else 0
		var triangles: int = (indices if indices > 0 else vertices) / 3 \
				if primitive == Mesh.PRIMITIVE_TRIANGLES else 0
		var row := {"surface": surface, "primitive": primitive, "vertices": vertices,
			"indices": indices, "lod0_triangles": triangles, "baked_lods": []}
		if primitive != Mesh.PRIMITIVE_TRIANGLES:
			row["omission"] = "Non-triangle surface not included in triangle sum."
		if surface < serialized.size():
			var data: Dictionary = serialized[surface]
			row["baked_lods"] = _baked_lod_census(data.get("lods", []), int(data.get("vertex_count", vertices)))
		(summary["surfaces"] as Array).append(row)
		summary["lod0_triangles"] += triangles
	return summary


static func _baked_lod_census(serialized: Array, vertex_count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if serialized.size() % 2 != 0:
		return [{"error": "Unsupported serialized LOD pairs; not counted."}]
	if not serialized.is_empty() and vertex_count <= 0:
		return [{"error": "Missing LOD vertex count; index width not inferred."}]
	var index_bytes := 2 if vertex_count > 0 and vertex_count <= 65_536 else 4
	for index: int in range(0, serialized.size(), 2):
		var buffer: Variant = serialized[index + 1]
		var edge: Variant = serialized[index]
		if not (edge is float or edge is int) or not is_finite(float(edge)):
			result.append({"error": "Unsupported LOD edge length; not counted."})
			continue
		if not buffer is PackedByteArray or buffer.size() % index_bytes != 0:
			result.append({"error": "Unsupported LOD index storage; not counted."})
			continue
		result.append({"edge_length": float(serialized[index]),
			"index_count": buffer.size() / index_bytes, "index_bytes": index_bytes})
	return result


func _abort(message: String) -> void:
	if _finished:
		return
	_finished = true
	_restore_stream_trace_flag()
	RunnerPlayer.autopilot = false
	push_error("runner_perf_probe: %s" % message)
	get_tree().quit(2)


static func _average_float(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value: float in values:
		total += value
	return total / float(values.size())


static func _average_int(values: PackedInt32Array) -> float:
	if values.is_empty():
		return 0.0
	var total: int = 0
	for value: int in values:
		total += value
	return float(total) / float(values.size())


static func _max_int(values: PackedInt32Array) -> int:
	var result := 0
	for value: int in values:
		result = maxi(result, value)
	return result


static func _percentile(sorted_values: Array[float], fraction: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := clampi(ceili(float(sorted_values.size()) * fraction) - 1,
		0, sorted_values.size() - 1)
	return sorted_values[index]
