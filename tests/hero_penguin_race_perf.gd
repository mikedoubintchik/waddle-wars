extends Node3D
## Focused eight-racer rendering/LOD probe for the shared authored penguin.
## HERO keeps LOD0, seven near RACER roles keep generated 8–12k LOD1, and
## facade distance hysteresis hands far racers to its synchronized cheap mesh.
## Report-only unless enforce=true so hardware-specific evidence stays useful.

const SPECIES: PackedStringArray = [
	"emperor", "king", "adelie", "gentoo",
	"chinstrap", "rockhopper", "macaroni", "little_blue",
]
const RACER_POSITIONS: Array[Vector3] = [
	Vector3(0.0, 0.0, 0.0),
	Vector3(-2.1, 0.0, -2.5), Vector3(0.0, 0.0, -2.5),
	Vector3(2.1, 0.0, -2.5), Vector3(-2.1, 0.0, -5.0),
	Vector3(0.0, 0.0, -5.0), Vector3(2.1, 0.0, -5.0),
	Vector3(0.0, 0.0, -7.5),
]

var _width: int = 1920
var _height: int = 1080
var _warmup_seconds: float = 5.0
var _sample_seconds: float = 15.0
var _out_path: String = "user://qa/hero_penguin_race_perf.json"
var _enforce: bool = false
var _racers: Array[PenguinVisual] = []
var _sample_started: bool = false
var _finished: bool = false
var _warmup_elapsed: float = 0.0
var _sample_elapsed: float = 0.0
var _frame_ms: PackedFloat64Array = PackedFloat64Array()
var _draw_calls: PackedInt32Array = PackedInt32Array()
var _primitives: PackedInt32Array = PackedInt32Array()
var _logical_visible_triangles: int = 0


func _ready() -> void:
	_parse_args()
	if GameConfig.is_headless():
		_abort("requires a rendering window")
		return
	DisplayServer.window_set_size(Vector2i(_width, _height))
	DisplayServer.window_set_position(Vector2i(40, 60))
	DisplayServer.window_move_to_foreground()
	_build_stage()
	_build_racers()
	await get_tree().process_frame
	await get_tree().process_frame
	var contract_ok: bool = await _verify_lod_contract()
	if not contract_ok:
		return
	ShaderWarmup.warm(self)
	_sample_started = true
	print("[hero_perf] staged renderer=%s racers=%d resolution=%dx%d" % [
		RenderingServer.get_current_rendering_method(), _racers.size(), _width, _height])


func _process(delta: float) -> void:
	for racer: PenguinVisual in _racers:
		racer.tick(delta, 1.0)
	if not _sample_started or _finished:
		return
	if _warmup_elapsed < _warmup_seconds:
		_warmup_elapsed += delta
		return
	_sample_elapsed += delta
	_frame_ms.append(delta * 1000.0)
	_draw_calls.append(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	_primitives.append(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	if _sample_elapsed >= _sample_seconds:
		_finish()


func _parse_args() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pieces := argument.trim_prefix("--").split("=", false, 1)
		if pieces.size() != 2:
			continue
		match pieces[0]:
			"w": _width = maxi(320, int(pieces[1]))
			"h": _height = maxi(320, int(pieces[1]))
			"warmup": _warmup_seconds = maxf(0.0, float(pieces[1]))
			"seconds": _sample_seconds = maxf(1.0, float(pieces[1]))
			"out": _out_path = pieces[1]
			"enforce": _enforce = pieces[1].to_lower() in ["1", "true", "yes"]


func _build_stage() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("18283a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c6d8e5")
	env.ambient_light_energy = 0.52
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 35.0)
	ground.mesh = plane
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color("aebdc2")
	snow.roughness = 0.86
	ground.material_override = snow
	add_child(ground)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	key.light_color = Color("ffe7c0")
	key.light_energy = 0.92
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-28.0, 145.0, 8.0)
	fill.light_color = Color("9fd8ff")
	fill.light_energy = 0.20
	add_child(fill)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 4.2, 8.0)
	camera.fov = 55.0
	add_child(camera)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.72, -3.6), Vector3.UP)
	camera.make_current()


func _build_racers() -> void:
	for index: int in RACER_POSITIONS.size():
		var facade := PenguinVisual.new()
		facade.name = "Hero" if index == 0 else "Racer%d" % index
		facade.position = RACER_POSITIONS[index]
		add_child(facade)
		var role := (CharacterLook.RenderRole.HERO if index == 0
				else CharacterLook.RenderRole.RACER)
		facade.setup_look(CharacterLook.from_legacy_config({
			"species": SPECIES[index],
			"accent_color": Color.from_hsv(float(index) / 8.0, 0.55, 0.95),
		}, role))
		facade.set_pose(PenguinVisual.Pose.RUN)
		facade.drive_motion(1.0, 0.0, 0.0, 0.0, true)
		_racers.append(facade)


func _verify_lod_contract() -> bool:
	if _racers.size() != 8:
		_abort("expected eight racers, got %d" % _racers.size())
		return false
	for index: int in _racers.size():
		var facade := _racers[index]
		var rig := facade.find_child("AuthoredHeroPenguin", false, false) as HeroPenguinRig
		if rig == null:
			_abort("racer %d missing authored rig" % index)
			return false
		if index == 0:
			if rig.is_using_racer_lod() or not facade.is_authored_lod_visible():
				_abort("HERO did not retain visible LOD0")
				return false
		elif not rig.is_using_racer_lod() \
				or rig.racer_lod_triangle_count() < HeroPenguinRig.RACER_LOD_TRIANGLES_MIN \
				or rig.racer_lod_triangle_count() > HeroPenguinRig.RACER_LOD_TRIANGLES_MAX \
				or not facade.is_authored_lod_visible():
			_abort("near racer %d failed visible 8–12k LOD1 contract" % index)
			return false
		elif facade.is_authored_racer_shadow_enabled():
			_abort("mid-pack racer %d retained expensive authored shadow pass" % index)
			return false
		_logical_visible_triangles += _mesh_triangle_count(rig)
	if _logical_visible_triangles < 88_000 or _logical_visible_triangles > 100_000:
		_abort("logical visible character triangles outside 88–100k contract: %d" %
				_logical_visible_triangles)
		return false

	# Prove both hysteresis transitions on a live racer without recreating its
	# skeleton. This catches pop/disappearance regressions before timing begins.
	var probe := _racers[-1]
	var near_position := probe.position
	probe.position = Vector3(0.0, 0.0, -40.0)
	for _frame: int in 16:
		await get_tree().process_frame
	if probe.is_authored_lod_visible():
		_abort("far racer did not hand off to cheap facade backend")
		return false
	probe.position = near_position
	for _frame: int in 16:
		await get_tree().process_frame
	if not probe.is_authored_lod_visible():
		_abort("returning racer did not restore authored LOD1")
		return false
	var probe_rig := probe.find_child("AuthoredHeroPenguin", false, false) as HeroPenguinRig
	if probe_rig == null or not probe_rig.is_using_racer_lod():
		_abort("distance handoff lost stable RACER LOD1 role")
		return false
	# Immediate contact-pack racers regain full authored shadow. Receding through
	# exit threshold drops only that extra pass; LOD1 silhouette/material stays.
	probe.position = Vector3(0.0, 0.0, 2.0)
	for _frame: int in 16:
		await get_tree().process_frame
	if not probe.is_authored_racer_shadow_enabled():
		_abort("contact-pack racer did not restore authored shadow")
		return false
	probe.position = near_position
	for _frame: int in 16:
		await get_tree().process_frame
	if probe.is_authored_racer_shadow_enabled() or not probe.is_authored_lod_visible():
		_abort("receding racer did not retain LOD1 while dropping authored shadow")
		return false
	return true


## Logical character geometry is a separate budget from RenderingServer's
## pass-expanded primitive count. The latter includes shadow/depth passes and
## therefore must not be compared to the one-LOD-per-racer mesh contract.
static func _mesh_triangle_count(root: Node) -> int:
	var triangles := 0
	for child: Node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		var mesh := instance.mesh
		if mesh == null:
			continue
		for surface_index: int in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays := mesh.surface_get_arrays(surface_index)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if not indices.is_empty():
				triangles += indices.size() / 3
			else:
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				triangles += vertices.size() / 3
	return triangles


func _finish() -> void:
	_finished = true
	var sorted_ms: Array[float] = []
	for value: float in _frame_ms:
		sorted_ms.append(value)
	sorted_ms.sort()
	var average_ms := _average_float(_frame_ms)
	var average_fps := 1000.0 / average_ms if average_ms > 0.0 else 0.0
	var p95_ms := _percentile(sorted_ms, 0.95)
	var max_ms := sorted_ms[-1] if not sorted_ms.is_empty() else 0.0
	var draw_average := _average_int(_draw_calls)
	var draw_peak := _max_int(_draw_calls)
	var primitive_peak := _max_int(_primitives)
	var actual_size := DisplayServer.window_get_size()
	var renderer := RenderingServer.get_current_rendering_method()
	var meets_gate := average_fps >= 57.0 and p95_ms <= 20.0 and max_ms <= 100.0 \
			and draw_peak <= 100 and primitive_peak <= 160_000 \
			and _logical_visible_triangles >= 88_000 \
			and _logical_visible_triangles <= 100_000 \
			and actual_size == Vector2i(_width, _height) \
			and renderer in ["gl_compatibility", "mobile"]
	var report := {
		"schema_version": 1,
		"mode": "hero_penguin_eight_racers",
		"renderer": renderer,
		"resolution": [actual_size.x, actual_size.y],
		"sample_frames": _frame_ms.size(),
		"average_fps": snappedf(average_fps, 0.01),
		"average_frame_ms": snappedf(average_ms, 0.01),
		"p95_frame_ms": snappedf(p95_ms, 0.01),
		"max_frame_ms": snappedf(max_ms, 0.01),
		"draw_calls_average": snappedf(draw_average, 0.01),
		"draw_calls_peak": draw_peak,
		"logical_visible_character_triangles": _logical_visible_triangles,
		"primitives_peak": primitive_peak,
		"video_memory_bytes": RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_VIDEO_MEM_USED),
		"lod": {"hero_lod0": 1, "near_racer_lod1": 7, "far_backend": "procedural"},
		"gate": {
			"average_fps_min": 57.0, "p95_frame_ms_max": 20.0,
			"max_frame_ms": 100.0, "draw_calls_peak_max": 100,
			"logical_visible_character_triangles_min": 88_000,
			"logical_visible_character_triangles_max": 100_000,
			"render_pass_primitives_peak_max": 160_000,
		},
		"meets_gate": meets_gate,
	}
	var save_error := _write_report(report)
	print("[hero_perf] avg=%.1ffps p95=%.1fms max=%.1fms draws=%.1f/%d triangles=%d pass_primitives=%d gate=%s" % [
		average_fps, p95_ms, max_ms, draw_average, draw_peak,
		_logical_visible_triangles, primitive_peak,
		"PASS" if meets_gate else "FAIL"])
	get_tree().quit(1 if save_error != OK or (_enforce and not meets_gate) else 0)


func _write_report(report: Dictionary) -> Error:
	var absolute := ProjectSettings.globalize_path(_out_path)
	var dir_error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if dir_error != OK:
		return dir_error
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("[hero_perf] wrote %s" % absolute)
	return OK


func _abort(message: String) -> void:
	if _finished:
		return
	_finished = true
	push_error("hero_penguin_race_perf: %s" % message)
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
	var total := 0
	for value: int in values:
		total += value
	return float(total) / float(values.size())


static func _max_int(values: PackedInt32Array) -> int:
	var maximum := 0
	for value: int in values:
		maximum = maxi(maximum, value)
	return maximum


static func _percentile(sorted_values: Array[float], fraction: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := clampi(ceili(float(sorted_values.size()) * fraction) - 1,
			0, sorted_values.size() - 1)
	return sorted_values[index]
