extends Node
## Frozen real-race Compatibility probe. Run once with baseline=1, then with
## the printed baseline values and enforce=1; authored p95/draw peak may grow
## no more than 25% and must still meet the release frame budget.
##
## godot --path . --rendering-method gl_compatibility \
##   res://tests/glacier_gauntlet_art_perf.tscn -- \
##   baseline=1 out=user://qa/glacier_baseline.json
## godot --path . --rendering-method gl_compatibility \
##   res://tests/glacier_gauntlet_art_perf.tscn -- \
##   baseline_p95=16.7 baseline_draw=180 enforce=1

var _baseline := false
var _enforce := false
var _baseline_p95 := 0.0
var _baseline_draw := 0
var _warmup := 5.0
var _seconds := 15.0
var _out_path := "user://qa/glacier_gauntlet_art_perf.json"
var _width := 1920
var _height := 1080


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pieces := arg.split("=", false, 1)
		if pieces.size() != 2:
			continue
		match pieces[0]:
			"baseline": _baseline = pieces[1] == "1"
			"enforce": _enforce = pieces[1] == "1"
			"baseline_p95": _baseline_p95 = float(pieces[1])
			"baseline_draw": _baseline_draw = int(pieces[1])
			"warmup": _warmup = float(pieces[1])
			"seconds": _seconds = float(pieces[1])
			"out": _out_path = pieces[1]
			"w": _width = int(pieces[1])
			"h": _height = int(pieces[1])
	if _enforce and (_baseline_p95 <= 0.0 or _baseline_draw <= 0):
		push_error("glacier perf: enforce requires baseline_p95 and baseline_draw")
		get_tree().quit(1)
		return
	CourseGlacier.disable_authored_art_for_tests = _baseline
	DisplayServer.window_set_size(Vector2i(_width, _height))
	DisplayServer.window_set_position(Vector2i(40, 60))
	DisplayServer.window_move_to_foreground()
	SettingsManager.set_setting("display", "particle_quality", "high")
	Game.mode = Game.Mode.QUICK_RACE
	Game.course_id = "glacier"
	Game.difficulty_id = "competitive"
	RaceManager.autopilot_player = true
	var monitor := GlacierPerfMonitor.new()
	monitor.baseline = _baseline
	monitor.enforce = _enforce
	monitor.baseline_p95 = _baseline_p95
	monitor.baseline_draw = _baseline_draw
	monitor.warmup = _warmup
	monitor.seconds = _seconds
	monitor.out_path = _out_path
	get_tree().root.add_child.call_deferred(monitor)
	SceneRouter.go_to.call_deferred(Game.SCENE_RACE)


class GlacierPerfMonitor:
	extends Node

	var baseline := false
	var enforce := false
	var baseline_p95 := 0.0
	var baseline_draw := 0
	var warmup := 5.0
	var seconds := 15.0
	var out_path := ""
	var _staged := false
	var _elapsed := 0.0
	var _samples := PackedFloat64Array()
	var _draws := PackedInt32Array()

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(delta: float) -> void:
		if not _staged:
			var race := get_tree().current_scene
			if race == null or race.get("course") == null or race.get("manager") == null:
				return
			var course := race.get("course") as CourseGlacier
			var manager := race.get("manager") as RaceManager
			if course == null or manager == null or manager.player == null or not course.build_finished:
				return
			var status := course.authored_art_status()
			if baseline and bool(status.get("active", false)):
				_abort("baseline unexpectedly activated authored art")
				return
			if not baseline and not bool(status.get("active", false)):
				_abort("authored art inactive: %s" % status)
				return
			_stage(course, manager)
			_staged = true
			print("[glacier_perf] staged baseline=%s status=%s" % [baseline, status])
			return
		_elapsed += delta
		if _elapsed <= warmup:
			return
		_samples.append(delta * 1000.0)
		_draws.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		if _elapsed < warmup + seconds:
			return
		_finish()

	func _stage(course: CourseGlacier, manager: RaceManager) -> void:
		var offset := float(course.main_guide.nearest(Vector3(8, 49, -460), -1)["offset"]) - 32.0
		var xform := course.main_guide.transform_at(offset)
		for racer: Racer in manager.racers:
			racer.visible = racer == manager.player
			racer.set_process(false)
			racer.set_physics_process(false)
		manager.player.global_position = course.main_guide.point_at(offset, 0.0, 1.0)
		manager.player.global_rotation = Vector3(0.0, course.main_guide.yaw_at(offset), 0.0)
		var camera := Camera3D.new()
		camera.fov = 60.0
		course.add_child(camera)
		camera.global_position = xform.origin + xform.basis.z * 15.0 + xform.basis.y * 4.2
		camera.look_at(xform.origin - xform.basis.z * 30.0 + xform.basis.y * 2.2, Vector3.UP)
		camera.make_current()
		ShaderWarmup.warm(get_tree().current_scene)

	func _finish() -> void:
		set_process(false)
		var frames := Array(_samples)
		frames.sort()
		var draws := Array(_draws)
		draws.sort()
		var sum := 0.0
		for value: float in _samples:
			sum += value
		var average_ms := sum / maxf(1.0, float(_samples.size()))
		var p95_index := clampi(int(ceil(float(frames.size()) * 0.95)) - 1, 0,
			maxi(0, frames.size() - 1))
		var p95 := float(frames[p95_index])
		var maximum := float(frames.back())
		var draw_sum := 0
		for value: int in _draws:
			draw_sum += value
		var draw_average := float(draw_sum) / maxf(1.0, float(_draws.size()))
		var draw_peak := int(draws.back())
		var average_fps := 1000.0 / maxf(average_ms, 0.001)
		var allowed_p95 := baseline_p95 * 1.25 if enforce else 0.0
		var allowed_draw := int(ceil(float(baseline_draw) * 1.25)) if enforce else 0
		var passed := not enforce or (p95 <= minf(20.0, allowed_p95)
			and draw_peak <= allowed_draw and average_fps >= 57.0 and maximum < 100.0)
		var payload := {
			"average_fps": average_fps,
			"average_ms": average_ms,
			"baseline": baseline,
			"baseline_draw_peak": baseline_draw,
			"baseline_p95_ms": baseline_p95,
			"draw_average": draw_average,
			"draw_limit": allowed_draw,
			"draw_peak": draw_peak,
			"frames": _samples.size(),
			"maximum_ms": maximum,
			"p95_limit_ms": minf(20.0, allowed_p95) if enforce else 0.0,
			"p95_ms": p95,
			"passed": passed,
			"renderer": RenderingServer.get_current_rendering_method(),
			"resolution": [get_viewport().size.x, get_viewport().size.y],
		}
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path.get_base_dir()))
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(payload, "  ") + "\n")
			file.close()
		print("GLACIER_GAUNTLET_PERF %s" % JSON.stringify(payload))
		CourseGlacier.disable_authored_art_for_tests = false
		get_tree().quit(0 if passed else 1)

	func _abort(message: String) -> void:
		push_error("glacier perf: %s" % message)
		CourseGlacier.disable_authored_art_for_tests = false
		get_tree().quit(1)
