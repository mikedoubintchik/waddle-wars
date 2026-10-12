extends Node
## Frozen Glacier race benchmark for shared-character cost. Run baseline=true
## first, then pass its average/p95/draw peak into authored enforce run.

var _baseline: bool = false
var _enforce: bool = false
var _tier: String = "high"
var _width: int = 1920
var _height: int = 1080
var _warmup_seconds: float = 5.0
var _sample_seconds: float = 15.0
var _out_path: String = "user://qa/hero_penguin_course_perf.json"
var _baseline_average_ms: float = 0.0
var _baseline_p95_ms: float = 0.0
var _baseline_draw_peak: int = 0
var _baseline_static_bytes: int = 0
var _baseline_vram_bytes: int = 0
var _race: Node3D = null
var _racers: Array[Racer] = []
var _staged: bool = false
var _finished: bool = false
var _started_msec: int = 0
var _warmup_elapsed: float = 0.0
var _sample_elapsed: float = 0.0
var _frame_ms: PackedFloat64Array = PackedFloat64Array()
var _draw_calls: PackedInt32Array = PackedInt32Array()
var _primitives: PackedInt32Array = PackedInt32Array()
var _hero_ticks: int = 0
var _racer_ticks: int = 0
var _material_ids: Dictionary = {}
var _atlas_ids: Dictionary = {}
var _lod_counts: Dictionary = {}
var _stage_elapsed: float = 0.0
var _shader_signatures: Dictionary = {}
var _shader_signatures_after_warmup: PackedStringArray = PackedStringArray()
var _warmup_signature_count: int = 0
var _shader_warmup_complete: bool = false


func _ready() -> void:
	_parse_args()
	if GameConfig.is_headless():
		_abort("requires a rendering window")
		return
	if _tier not in ["high", "medium", "low"]:
		_abort("tier must be high, medium, or low")
		return
	if _enforce and not _baseline and (_baseline_average_ms <= 0.0
			or _baseline_p95_ms <= 0.0 or _baseline_draw_peak <= 0):
		_abort("authored enforce needs baseline_average_ms, baseline_p95_ms, baseline_draw_peak")
		return
	_apply_quality_without_persisting()
	DisplayServer.window_set_size(Vector2i(_width, _height))
	DisplayServer.window_set_position(Vector2i(40, 60))
	DisplayServer.window_move_to_foreground()
	PenguinVisual.disable_authored_backend_for_tests = _baseline
	RaceManager.autopilot_player = true
	Game.mode = Game.Mode.QUICK_RACE
	Game.course_id = "glacier"
	Game.difficulty_id = "competitive"
	var packed := load(Game.SCENE_RACE) as PackedScene
	if packed == null:
		_abort("race scene missing")
		return
	_race = packed.instantiate() as Node3D
	add_child(_race)
	_started_msec = Time.get_ticks_msec()


func _process(delta: float) -> void:
	if _finished:
		return
	if not _staged:
		if float(Time.get_ticks_msec() - _started_msec) * 0.001 > 35.0:
			_abort("race did not stage before timeout")
			return
		if not _race_ready():
			return
		if not _stage_frozen_race():
			return
		_staged = true
		return
	_tick_characters(delta)
	_stage_elapsed += delta
	if Engine.get_process_frames() % 6 == 0:
		_census_material_signatures(_race)
	if _warmup_elapsed < _warmup_seconds:
		_warmup_elapsed += delta
		if _warmup_elapsed >= _warmup_seconds:
			_warmup_signature_count = _shader_signatures.size()
			_shader_warmup_complete = _race.find_child("ShaderWarmup", true, false) == null
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
			"baseline": _baseline = pieces[1].to_lower() in ["1", "true", "yes"]
			"enforce": _enforce = pieces[1].to_lower() in ["1", "true", "yes"]
			"tier": _tier = pieces[1].to_lower()
			"w": _width = maxi(320, int(pieces[1]))
			"h": _height = maxi(320, int(pieces[1]))
			"warmup": _warmup_seconds = maxf(0.0, float(pieces[1]))
			"seconds": _sample_seconds = maxf(1.0, float(pieces[1]))
			"out": _out_path = pieces[1]
			"baseline_average_ms": _baseline_average_ms = float(pieces[1])
			"baseline_p95_ms": _baseline_p95_ms = float(pieces[1])
			"baseline_draw_peak": _baseline_draw_peak = int(pieces[1])
			"baseline_static_bytes": _baseline_static_bytes = int(pieces[1])
			"baseline_vram_bytes": _baseline_vram_bytes = int(pieces[1])


func _apply_quality_without_persisting() -> void:
	var display: Dictionary = SettingsManager.settings.get("display", {}).duplicate(true)
	display["quality_preset"] = _tier
	display["shadow_quality"] = _tier
	display["particle_quality"] = _tier
	display["msaa"] = {"high": "4x", "medium": "2x", "low": "off"}[_tier]
	display["window_mode"] = "windowed"
	display["resolution"] = "%dx%d" % [_width, _height]
	display["fps_limit"] = 0
	SettingsManager.settings["display"] = display
	SettingsManager._governor_override = ""
	SettingsManager._governor_steps = SettingsManager.GOVERNOR_MAX_STEPS
	SettingsManager._render_scale_step = 0
	SettingsManager.apply_all()


func _race_ready() -> bool:
	if _race == null or _race.get("course") == null or _race.get("manager") == null:
		return false
	var course := _race.get("course") as CourseBase
	var manager := _race.get("manager") as RaceManager
	if course == null or manager == null or not course.build_finished \
			or manager.racers.size() != 8:
		return false
	for racer: Racer in manager.racers:
		if not is_instance_valid(racer) or racer.visual == null:
			return false
	return true


func _stage_frozen_race() -> bool:
	var course := _race.get("course") as CourseBase
	var manager := _race.get("manager") as RaceManager
	if course == null or manager == null or course.main_guide == null:
		_abort("race course/manager/guide missing")
		return false
	_racers = manager.racers.duplicate()
	manager.set_process(false)
	manager.set_physics_process(false)
	var offset := float(course.main_guide.nearest(Vector3(8.0, 49.0, -460.0), -1)["offset"])
	offset = clampf(offset - 28.0, 24.0, course.finish_offset - 40.0)
	for index: int in _racers.size():
		var racer := _racers[index]
		var row := float(index / 3) * 2.0
		var column := float(index % 3 - 1) * 2.0
		var racer_offset := offset + row
		racer.global_position = course.main_guide.point_at(racer_offset, column, 1.0)
		racer.global_rotation = Vector3(0.0, course.main_guide.yaw_at(racer_offset), 0.0)
		racer.visible = true
		racer.set_process(false)
		racer.set_physics_process(false)
		racer.visual.set_pose(PenguinVisual.Pose.RUN)
		racer.visual.drive_motion(1.0, 0.0, 0.0, 0.0, true)
	if _race.get("camera_rig") != null:
		var chase := _race.get("camera_rig") as ChaseCamera
		if chase != null:
			chase.set_process(false)
			chase.set_physics_process(false)
	if _race.get("hud") != null:
		(_race.get("hud") as CanvasLayer).visible = false
	var xform := course.main_guide.transform_at(offset + 2.0)
	var camera := Camera3D.new()
	camera.fov = 58.0
	course.add_child(camera)
	camera.global_position = xform.origin + xform.basis.z * 12.5 + xform.basis.y * 4.4
	camera.look_at(xform.origin - xform.basis.z * 5.5 + xform.basis.y * 1.2,
			Vector3.UP)
	camera.make_current()
	# Force a live-camera LOD evaluation now. The ordinary 0.2s update remains
	# active during warmup and sample.
	for racer: Racer in _racers:
		racer.visual.set_render_role(PenguinVisual.RenderRole.HERO if racer.is_player
				else PenguinVisual.RenderRole.RACER)
	if not _inspect_character_contract():
		return false
	ShaderWarmup.warm(_race)
	print("[hero_course_perf] staged baseline=%s tier=%s renderer=%s" % [
		_baseline, _tier, RenderingServer.get_current_rendering_method()])
	return true


func _inspect_character_contract() -> bool:
	_lod_counts = {"lod0": 0, "lod1": 0, "procedural": 0}
	_material_ids.clear()
	_atlas_ids.clear()
	for racer: Racer in _racers:
		var facade := racer.visual
		var rig := facade.find_child("AuthoredHeroPenguin", false, false) as HeroPenguinRig
		if _baseline:
			if rig != null or facade.is_authored_backend_active():
				_abort("procedural baseline instantiated authored backend")
				return false
			_lod_counts["procedural"] = int(_lod_counts["procedural"]) + 1
			continue
		if rig == null or not facade.is_authored_lod_visible():
			_abort("authored near pack missing visible rig")
			return false
		if racer.is_player:
			if rig.is_using_racer_lod():
				_abort("player HERO unexpectedly uses LOD1")
				return false
			_lod_counts["lod0"] = int(_lod_counts["lod0"]) + 1
		else:
			if not rig.is_using_racer_lod():
				_abort("near RACER missing LOD1")
				return false
			_lod_counts["lod1"] = int(_lod_counts["lod1"]) + 1
		var mesh := rig.find_child("HeroPenguinMesh", true, false) as MeshInstance3D
		if mesh == null:
			_abort("authored rig missing skinned mesh")
			return false
		var material := mesh.get_surface_override_material(0) as ShaderMaterial
		if material == null:
			_abort("authored rig missing atlas material")
			return false
		_material_ids[material.get_instance_id()] = true
		for parameter: StringName in [&"feather_albedo", &"feather_normal", &"feather_orm"]:
			var texture := material.get_shader_parameter(parameter) as Texture2D
			if texture == null:
				_abort("shared material missing %s" % parameter)
				return false
			_atlas_ids["%s:%d" % [parameter, texture.get_instance_id()]] = true
	if not _baseline and (int(_lod_counts["lod0"]) != 1
			or int(_lod_counts["lod1"]) != 7 or _material_ids.size() != 1
			or _atlas_ids.size() != 3):
		_abort("LOD/material/atlas sharing contract failed: lod=%s mats=%d atlases=%d" % [
			_lod_counts, _material_ids.size(), _atlas_ids.size()])
		return false
	return true


func _tick_characters(delta: float) -> void:
	for racer: Racer in _racers:
		racer.visual.tick(delta, 1.0)
		if racer.is_player:
			_hero_ticks += 1
		else:
			_racer_ticks += 1


func _census_material_signatures(node: Node) -> void:
	if node == null:
		return
	var geometry := node as GeometryInstance3D
	if geometry != null:
		_note_material_signature(geometry.material_override)
		var mesh_instance := node as MeshInstance3D
		if mesh_instance != null and mesh_instance.mesh != null:
			for surface_index: int in mesh_instance.mesh.get_surface_count():
				_note_material_signature(mesh_instance.get_active_material(surface_index))
	var particles := node as GPUParticles3D
	if particles != null and particles.draw_pass_1 != null:
		for surface_index: int in particles.draw_pass_1.get_surface_count():
			_note_material_signature(particles.draw_pass_1.surface_get_material(surface_index))
	for child: Node in node.get_children():
		_census_material_signatures(child)


func _note_material_signature(material: Material) -> void:
	if material == null:
		return
	var key := ""
	var standard := material as StandardMaterial3D
	if standard != null:
		key = "std|shade=%d|transp=%d|blend=%d|cull=%d|vc=%d|billboard=%d|tex=%d|depth=%d|no_depth=%d" % [
			standard.shading_mode, standard.transparency, standard.blend_mode,
			standard.cull_mode, int(standard.vertex_color_use_as_albedo),
			standard.billboard_mode, int(standard.albedo_texture != null),
			int(standard.disable_receive_shadows), int(standard.no_depth_test)]
	else:
		var shader_material := material as ShaderMaterial
		if shader_material != null and shader_material.shader != null:
			key = "shader|%s" % shader_material.shader.resource_path
		else:
			key = "other|%s" % material.get_class()
	if _shader_signatures.has(key):
		return
	_shader_signatures[key] = _stage_elapsed
	if _warmup_elapsed >= _warmup_seconds:
		_shader_signatures_after_warmup.append(key)


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
	var static_bytes := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var vram_bytes := RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)
	var static_delta := static_bytes - _baseline_static_bytes if _baseline_static_bytes > 0 else 0
	var vram_delta := vram_bytes - _baseline_vram_bytes if _baseline_vram_bytes > 0 else 0
	var resource_delta_ok := (_baseline or not _enforce
			or ((_baseline_static_bytes <= 0 or static_delta <= 25 * 1024 * 1024)
			and (_baseline_vram_bytes <= 0 or vram_delta <= 25 * 1024 * 1024)))
	var fps_min := 29.0 if _tier == "low" else 57.0
	var p95_limit := 36.0 if _tier == "low" else 20.0
	var baseline_frame_ok := (_baseline or not _enforce
			or (average_ms <= _baseline_average_ms * 1.25
			and p95_ms <= _baseline_p95_ms * 1.25
			and draw_peak <= int(ceil(float(_baseline_draw_peak) * 1.25))))
	var shader_gate := _shader_warmup_complete and _shader_signatures_after_warmup.is_empty()
	var gate := average_fps >= fps_min and p95_ms <= p95_limit and max_ms < 100.0 \
			and baseline_frame_ok and resource_delta_ok and shader_gate
	var cadence_hz := float(_frame_ms.size()) / maxf(_sample_elapsed, 0.001)
	var payload := {
		"schema_version": 1,
		"mode": "hero_penguin_frozen_glacier_race",
		"baseline": _baseline,
		"tier": _tier,
		"renderer": RenderingServer.get_current_rendering_method(),
		"resolution": [get_viewport().size.x, get_viewport().size.y],
		"warmup_seconds": _warmup_seconds,
		"sample_seconds": _sample_elapsed,
		"sample_frames": _frame_ms.size(),
		"average_fps": snappedf(average_fps, 0.01),
		"average_frame_ms": snappedf(average_ms, 0.01),
		"p95_frame_ms": snappedf(p95_ms, 0.01),
		"max_frame_ms": snappedf(max_ms, 0.01),
		"draw_calls_average": snappedf(draw_average, 0.01),
		"draw_calls_peak": draw_peak,
		"primitives_peak": primitive_peak,
		"static_memory_bytes": static_bytes,
		"video_memory_bytes": vram_bytes,
		"visible_lod_counts": _lod_counts,
		"shared_material_count": _material_ids.size(),
		"shared_atlas_texture_count": _atlas_ids.size(),
		"animation_cadence": {
			"hero_hz": snappedf(cadence_hz, 0.01),
			"near_racer_hz": snappedf(cadence_hz, 0.01),
			"hero_ticks": _hero_ticks,
			"racer_ticks_total": _racer_ticks,
		},
		"shader_warmup_before_sample": _shader_warmup_complete,
		"shader_signatures": {
			"warmup_count": _warmup_signature_count,
			"total_count": _shader_signatures.size(),
			"first_appearances_after_warmup": _shader_signatures_after_warmup,
		},
		"baseline_comparison": {
			"average_ms": _baseline_average_ms,
			"p95_ms": _baseline_p95_ms,
			"draw_peak": _baseline_draw_peak,
			"static_bytes": _baseline_static_bytes,
			"static_delta_bytes": static_delta,
			"vram_bytes": _baseline_vram_bytes,
			"vram_delta_bytes": vram_delta,
			"within_25_percent": baseline_frame_ok,
			"resource_delta_within_25_mib": resource_delta_ok,
		},
		"gate": {"average_fps_min": fps_min, "p95_frame_ms_max": p95_limit,
			"max_frame_ms_exclusive": 100.0, "baseline_regression_max": 1.25},
		"meets_gate": gate,
	}
	var save_error := _write_report(payload)
	print("HERO_COURSE_PERF %s" % JSON.stringify(payload))
	_reset_hooks()
	get_tree().quit(1 if save_error != OK or (_enforce and not gate) else 0)


func _write_report(payload: Dictionary) -> Error:
	var absolute := ProjectSettings.globalize_path(_out_path)
	var dir_error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if dir_error != OK:
		return dir_error
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload, "\t") + "\n")
	file.close()
	return OK


func _abort(message: String) -> void:
	if _finished:
		return
	_finished = true
	_reset_hooks()
	push_error("hero_penguin_course_perf: %s" % message)
	get_tree().quit(2)


func _reset_hooks() -> void:
	PenguinVisual.disable_authored_backend_for_tests = false
	RaceManager.autopilot_player = false


func _exit_tree() -> void:
	# Also covers window close, parse/runtime aborts after this script entered
	# tree, and harness interruption—not only normal report/abort paths.
	_reset_hooks()


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
