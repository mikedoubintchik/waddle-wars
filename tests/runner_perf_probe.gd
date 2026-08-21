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
##     out=user://qa/runner_perf.json enforce=true

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
	_apply_quality_without_persisting()
	# apply_all() includes the saved resolution, so requested benchmark geometry
	# must be applied after the fixed tier is installed. The profile also writes
	# the requested resolution into the in-memory settings copy for consistency.
	DisplayServer.window_set_size(Vector2i(_width, _height))
	DisplayServer.window_set_position(Vector2i(40, 60))
	DisplayServer.window_move_to_foreground()
	var packed := load(Game.SCENE_RUNNER) as PackedScene
	if packed == null:
		push_error("runner_perf_probe: runner scene missing")
		get_tree().quit(2)
		return
	RunnerPlayer.autopilot = true
	_started_at_msec = Time.get_ticks_msec()
	_game = packed.instantiate() as RunnerGame
	add_child(_game)
	print("[runner_perf] %s %dx%d warmup=%.1fs sample=%.1fs" % [
		_tier, _width, _height, _warmup_seconds, _sample_seconds])


func _process(delta: float) -> void:
	if _finished or _game == null:
		return
	var wall_seconds := float(Time.get_ticks_msec() - _started_at_msec) * 0.001
	if not _game.build_finished or not _game.running:
		if _seen_running and not _game.running:
			_abort("runner ended before performance sample completed")
		elif wall_seconds > _warmup_seconds + _sample_seconds + STARTUP_GRACE_SECONDS:
			_abort("runner did not complete performance sample before timeout")
		return
	_seen_running = true
	_run_time += delta
	if _run_time < _warmup_seconds:
		return
	_sample_time += delta
	_frame_ms.append(delta * 1000.0)
	_draw_calls.append(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	_primitives.append(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
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


func _apply_quality_without_persisting() -> void:
	# set_setting() writes settings.json. A benchmark must not alter the
	# player's choice, so change the in-memory copy and run the ordinary apply
	# path. run_tests.sh additionally supplies an isolated user://.
	var display: Dictionary = SettingsManager.settings.get("display", {}).duplicate(true)
	display["quality_preset"] = _tier
	display["shadow_quality"] = _tier
	display["particle_quality"] = _tier
	display["msaa"] = {"high": "4x", "medium": "2x", "low": "off"}[_tier]
	display["window_mode"] = "windowed"
	display["resolution"] = "%dx%d" % [_width, _height]
	display["fps_limit"] = 0
	SettingsManager.settings["display"] = display
	# Fixed-tier probe, not governor probe. Otherwise a requested high/medium run
	# can silently report a pass after measuring a lower effective tier.
	SettingsManager._governor_override = ""
	SettingsManager._governor_steps = SettingsManager.GOVERNOR_MAX_STEPS
	SettingsManager._render_scale_step = 0
	SettingsManager.apply_all()


func _finish() -> void:
	_finished = true
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
	var meets_gate := average_fps >= fps_min and p95_ms <= p95_max \
		and max_ms <= 100.0 and draw_average <= draw_limits.x \
		and draw_peak <= draw_limits.y \
		and primitive_peak <= int(PRIMITIVE_LIMITS[_tier]) \
		and resolution_matches and tier_matches
	var report: Dictionary = {
		"schema_version": 1,
		"mode": "runner",
		"tier": _tier,
		"resolution": [actual_size.x, actual_size.y],
		"requested_resolution": [_width, _height],
		"resolution_matches_request": resolution_matches,
		"renderer": RenderingServer.get_current_rendering_method(),
		"platform": OS.get_name(),
		"quality": {
			"requested_tier": _tier,
			"effective_tier": effective_tier,
			"shadow_quality": SettingsManager.get_setting("display", "shadow_quality"),
			"particle_quality": SettingsManager.get_setting("display", "particle_quality"),
			"msaa": SettingsManager.get_setting("display", "msaa"),
		},
		"warmup_seconds": _warmup_seconds,
		"sample_seconds": _sample_time,
		"sample_frames": _frame_ms.size(),
		"average_fps": snappedf(average_fps, 0.01),
		"average_frame_ms": snappedf(average_ms, 0.01),
		"p95_frame_ms": snappedf(p95_ms, 0.01),
		"max_frame_ms": snappedf(max_ms, 0.01),
		"frames_over_100_ms": over_100,
		"draw_calls_average": snappedf(draw_average, 0.01),
		"draw_calls_peak": draw_peak,
		"primitives_peak": primitive_peak,
		"video_memory_bytes": RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_VIDEO_MEM_USED),
		"gate": {
			"average_fps_min": fps_min,
			"p95_frame_ms_max": p95_max,
			"max_frame_ms": 100.0,
			"draw_calls_average_max": draw_limits.x,
			"draw_calls_peak_max": draw_limits.y,
			"primitives_peak_max": PRIMITIVE_LIMITS[_tier],
			"resolution_must_match_request": true,
			"tier_must_match_request": true,
		},
		"meets_gate": meets_gate,
	}
	var save_error := _write_report(report)
	print("[runner_perf] actual=%dx%d avg=%.1ffps p95=%.1fms max=%.1fms draws=%.0f/%d primitives=%d gate=%s" % [
		actual_size.x, actual_size.y,
		average_fps, p95_ms, max_ms, draw_average, draw_peak,
		primitive_peak, "PASS" if meets_gate else "FAIL"])
	RunnerPlayer.autopilot = false
	get_tree().quit(1 if save_error != OK or (_enforce and not meets_gate) else 0)


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


func _abort(message: String) -> void:
	if _finished:
		return
	_finished = true
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
