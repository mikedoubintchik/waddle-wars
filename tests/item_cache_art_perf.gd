extends Node3D
## Compatibility stress/perf harness for shared authored ItemBox rendering.
## Frozen legacy baseline values are supplied by caller; authored p95 and draw
## peak may grow at most 25% while retaining release frame/memory budgets.
##
## godot --rendering-method gl_compatibility --path . \
##   res://tests/item_cache_art_perf.tscn -- \
##   baseline_p95=16.7 baseline_draw=115 enforce=1 \
##   out=user://qa/item_cache_perf.json

var _enforce := false
var _baseline_p95 := 0.0
var _baseline_draw := 0
var _warmup := 5.0
var _seconds := 15.0
var _out := "user://qa/item_cache_perf.json"
var _count := 36
var _elapsed := 0.0
var _samples := PackedFloat64Array()
var _draws := PackedInt32Array()
var _memory_after_warmup := 0
var _warmup_marked := false


func _ready() -> void:
	var width := 1920
	var height := 1080
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.split("=", false, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"enforce": _enforce = parts[1] == "1"
			"baseline_p95": _baseline_p95 = float(parts[1])
			"baseline_draw": _baseline_draw = int(parts[1])
			"warmup": _warmup = float(parts[1])
			"seconds": _seconds = float(parts[1])
			"out": _out = parts[1]
			"count": _count = int(parts[1])
			"w": width = int(parts[1])
			"h": height = int(parts[1])
	if _enforce and (_baseline_p95 <= 0.0 or _baseline_draw <= 0):
		push_error("item cache perf: enforce requires baseline_p95 and baseline_draw")
		get_tree().quit(1)
		return
	DisplayServer.window_set_size(Vector2i(width, height))
	DisplayServer.window_set_position(Vector2i(40, 60))
	DisplayServer.window_move_to_foreground()
	SettingsManager.set_setting("display", "particle_quality", "high")
	Game.mode = Game.Mode.QUICK_RACE
	_build_set()
	ShaderWarmup.warm(self)


func _build_set() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.07, 0.23, 0.48)
	sky_material.sky_horizon_color = Color(0.60, 0.76, 0.86)
	sky_material.ground_bottom_color = Color(0.31, 0.46, 0.58)
	sky_material.ground_horizon_color = Color(0.61, 0.75, 0.84)
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.78
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 0.92
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.46, 0.62, 0.72)
	environment.fog_density = 0.004
	environment_node.environment = environment
	add_child(environment_node)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.22
	sun.rotation_degrees = Vector3(-45.0, -34.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 95.0
	add_child(sun)

	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(70.0, 180.0)
	floor.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.73, 0.82, 0.88)
	floor_material.roughness = 0.82
	floor.material_override = floor_material
	add_child(floor)

	for index: int in _count:
		var cache := ItemBox.new()
		var lane := index % 6
		var row := index / 6
		cache.position = Vector3(-7.5 + float(lane) * 3.0, 1.1,
			-4.0 - float(row) * 11.0)
		add_child(cache)
	var camera := Camera3D.new()
	camera.fov = 56.0
	camera.position = Vector3(0.0, 4.2, 11.5)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.0, -38.0), Vector3.UP)
	camera.make_current()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed <= _warmup:
		return
	if not _warmup_marked:
		_warmup_marked = true
		_memory_after_warmup = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	_samples.append(delta * 1000.0)
	_draws.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	if _elapsed < _warmup + _seconds:
		return
	_finish()


func _finish() -> void:
	set_process(false)
	var frames := Array(_samples)
	var draws := Array(_draws)
	frames.sort()
	draws.sort()
	var total := 0.0
	for value: float in _samples:
		total += value
	var average_ms := total / maxf(1.0, float(_samples.size()))
	var p95_index := clampi(int(ceil(float(frames.size()) * 0.95)) - 1,
		0, maxi(0, frames.size() - 1))
	var p95 := float(frames[p95_index])
	var maximum := float(frames.back())
	var draw_total := 0
	for value: int in _draws:
		draw_total += value
	var draw_average := float(draw_total) / maxf(1.0, float(_draws.size()))
	var draw_peak := int(draws.back())
	var average_fps := 1000.0 / maxf(average_ms, 0.001)
	var memory_growth := int(Performance.get_monitor(Performance.MEMORY_STATIC)) \
		- _memory_after_warmup
	var p95_limit := minf(20.0, _baseline_p95 * 1.25) if _enforce else 20.0
	var draw_limit := int(ceil(float(_baseline_draw) * 1.25)) if _enforce else 0
	var passed := p95 <= p95_limit and average_fps >= 57.0 and maximum < 100.0 \
		and memory_growth <= 25 * 1024 * 1024 \
		and (not _enforce or draw_peak <= draw_limit)
	var payload := {
		"average_fps": average_fps,
		"average_ms": average_ms,
		"baseline_draw_peak": _baseline_draw,
		"baseline_p95_ms": _baseline_p95,
		"cache_count": _count,
		"draw_average": draw_average,
		"draw_limit": draw_limit,
		"draw_peak": draw_peak,
		"frames": _samples.size(),
		"maximum_ms": maximum,
		"memory_growth_bytes": memory_growth,
		"p95_limit_ms": p95_limit,
		"p95_ms": p95,
		"passed": passed,
		"renderer": RenderingServer.get_current_rendering_method(),
		"resolution": [get_viewport().size.x, get_viewport().size.y],
	}
	var output := ProjectSettings.globalize_path(_out) \
		if _out.begins_with("res://") or _out.begins_with("user://") else _out
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(payload, "  ") + "\n")
		file.close()
	print("ITEM_CACHE_PERF %s" % JSON.stringify(payload))
	get_tree().quit(0 if passed else 1)
