extends Node3D
## Exact external-buffer raster study, not a performance benchmark. The ID pass
## replaces materials only in this fixture; it does not prove a live shader
## pipeline linked. Counts use resolved production MSAA, not GPU sample queries.

const SIZE := Vector2i(1920, 1080)
const COLOURS: Array[Color] = [Color.RED, Color.GREEN, Color.BLUE,
		Color.CYAN, Color.MAGENTA, Color.YELLOW]
const NAMES: PackedStringArray = ["deck", "seams", "verge_body",
		"verge_crown", "verge_drop", "verge_snow"]
const PROBE_INDICES: PackedInt32Array = [0, 1, 2, 2, 2, 2]
const SURFACE_INDICES: PackedInt32Array = [0, 0, 0, 1, 2, 3]
const CONTROL_SCALE: float = 64.0

class LightingFixture:
	extends RunnerGame

	func _ready() -> void:
		pass

	func _process(_delta: float) -> void:
		pass

	func _add_weather() -> void:
		pass

var _out: String = ""
var _started: int = 0
var _done: bool = false
var _camera: Camera3D
var _lighting: LightingFixture
var _warmup: ShaderWarmup
var _source_chunk: RunnerTrack.RunnerChunk
var _probes: Array[MeshInstance3D] = []
var _original_materials: Array[Dictionary] = []
var _original_transforms: Array[Transform3D] = []
var _report: Dictionary = {"fixture_valid": false, "complete": false,
		"production_surface_coverage_pass": false, "performance_claim": false,
		"cases": [], "errors": []}


func _ready() -> void:
	_started = Time.get_ticks_usec()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("out="):
			_out = argument.trim_prefix("out=")
	if GameConfig.is_headless():
		print("[dusk_warmup_raster] SKIP: real Compatibility renderer required")
		get_tree().quit(0)
		return
	if _out.is_empty() or not _out.is_absolute_path() or not DirAccess.dir_exists_absolute(_out):
		_fail("out must be an existing isolated output directory")
		return
	if not String(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")) \
			.begins_with("waddle-dusk-raster-"):
		_fail("isolated waddle-dusk-raster-* project identity required")
		return
	SettingsManager.settings = SettingsManager.default_settings()
	SettingsManager.settings["display"]["resolution"] = "1920x1080"
	SettingsManager.settings["display"]["window_mode"] = "windowed"
	SettingsManager.apply_all()
	DisplayServer.window_set_size(SIZE)
	DisplayServer.window_set_position(Vector2i(40, 60))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()
	get_viewport().msaa_3d = SettingsManager.msaa_3d_mode() as Viewport.MSAA
	VisualLibrary._detail_level_cache = 1.0
	await get_tree().process_frame
	if not _build_actual_state():
		_fail("production state/resource inventory did not complete")
		return
	await RenderingServer.frame_post_draw
	if not _report.errors.is_empty() or not _probe_resource_rows_complete():
		_report.errors.append("all three probe resource rows must be complete before capture")
		_finish(false)
		return
	_report["renderer"] = RenderingServer.get_current_rendering_method()
	_report["msaa_3d"] = get_viewport().msaa_3d
	var effective_msaa: int = SettingsManager.msaa_3d_mode()
	_report["msaa"] = {"requested": String(SettingsManager.get_setting("display", "msaa")),
			"effective_mode": effective_msaa, "effective_samples": _msaa_samples(effective_msaa),
			"actual_mode": get_viewport().msaa_3d,
			"actual_samples": _msaa_samples(get_viewport().msaa_3d)}
	_report["viewport"] = [get_viewport().get_visible_rect().size.x,
			get_viewport().get_visible_rect().size.y]
	_report["camera"] = {"fov": _camera.fov, "near": _camera.near, "far": _camera.far,
			"transform": str(_camera.global_transform)}
	_report["light_state"] = _light_state()
	_report["coverage_scope"] = "Resolved output pixels under the recorded effective viewport MSAA; " \
			+ "not individual MSAA sample queries, GPU timing or pipeline-link evidence. " \
			+ "Only deck, seams and four verge surfaces; other warmup/world geometry omitted."
	_report["environment_scope"] = "Production DAY profile/environment and light creation, " \
			+ "with startup rim at its original zero position. Actual imported hero supplies " \
			+ "startup camera fit; player hidden, weather/shafts omitted. No gameplay/countdown."
	# Current rear reference uses 54 degrees plus the 8-degree countdown
	# establishing lift. The former high-angle camera started at 74 degrees.
	if _report.renderer != "gl_compatibility" or _camera.fov != 62.0 \
			or get_viewport().msaa_3d != effective_msaa:
		_fail("renderer/FOV/MSAA contract mismatch")
		return
	for probe: MeshInstance3D in _probes:
		probe.visible = false
	var baseline := await _capture("actual_materials_baseline")
	for probe: MeshInstance3D in _probes:
		probe.visible = true
	var actual := await _capture("actual_materials_original")
	if baseline == null or actual == null:
		return
	var actual_bounds := _screen_bounds(_probes[0])
	for probe: MeshInstance3D in _probes:
		actual_bounds = actual_bounds.merge(_screen_bounds(probe))
	_report["actual_material_pass"] = {"unchanged_material_identities": _materials_exact(),
			"changed_resolved_pixels_in_probe_bounds": _different_pixels(baseline, actual, actual_bounds),
			"counted_bounds": str(actual_bounds),
			"scope": "All three production probe instances together, original surface materials. "
					+ "Pixel difference alone does not identify which of the four verge shaders ran."}
	# Diagnostic colors require a controlled transfer function and clear color.
	# Actual materials above were captured BEFORE changing the environment.
	var env := _lighting._world_env.environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.fog_enabled = false
	env.glow_enabled = false
	var valid := true
	var coverage := true
	for index: int in NAMES.size():
		_set_id_case(index)
		var production := await _capture("id_production_%s" % NAMES[index])
		if production == null:
			return
		var production_bounds := _screen_bounds(_probes[PROBE_INDICES[index]])
		var production_count := _count_colour(production, COLOURS[index], production_bounds)
		_set_control(index)
		var control := await _capture("id_control_%s" % NAMES[index])
		if control == null:
			return
		var control_bounds := _screen_bounds(_probes[PROBE_INDICES[index]])
		var control_count := _count_colour(control, COLOURS[index], control_bounds)
		valid = valid and control_count > 0
		coverage = coverage and production_count > 0
		_report.cases.append({"case": NAMES[index], "probe_slot": PROBE_INDICES[index],
				"surface": SURFACE_INDICES[index], "production_resolved_pixels": production_count,
				"production_counted_bounds": str(production_bounds), "control_counted_bounds": str(control_bounds),
				"control_resolved_pixels": control_count, "control_scale_multiplier": CONTROL_SCALE,
				"production_has_coverage": production_count > 0,
				"control_valid": control_count > 0})
		print("[dusk_warmup_raster] %s production_pixels=%d control_pixels=%d" % [
				NAMES[index], production_count, control_count])
	_restore_probes()
	_report["production_surface_coverage_pass"] = coverage
	_report["complete"] = true
	_finish(valid and _materials_exact())


func _build_actual_state() -> bool:
	_lighting = LightingFixture.new()
	_lighting._runner_art_set = load(RunnerGame.RUNNER_ART_SET_PATH) as RunnerArtSet
	add_child(_lighting)
	_lighting._build_environment()
	for child: Node in _lighting.get_children():
		if not child is WorldEnvironment and not child is Light3D:
			_lighting.remove_child(child)
			child.queue_free()
	_lighting.player = RunnerPlayer.new()
	_lighting.add_child(_lighting.player)
	_lighting.player.setup(_lighting._player_visual_config())
	_lighting._camera_hero_height = RunnerCameraComposition.authored_height(_lighting.player._visual)
	if _lighting._camera_hero_height <= 0.0:
		_report.errors.append("Actual authored hero height unavailable")
	_lighting.player.visible = false
	_lighting.player.process_mode = Node.PROCESS_MODE_DISABLED
	_camera = Camera3D.new()
	_camera.far = 900.0
	_lighting.camera = _camera
	_lighting.add_child(_camera)
	_camera.make_current()
	_lighting._place_camera(0.0, true)
	_source_chunk = RunnerTrack.RunnerChunk.new()
	_source_chunk.index = 17
	_source_chunk.biome = RunnerTrack.Biome.DUSK
	var track := RunnerTrack.new()
	track._build_deck(_source_chunk, RunnerTrack.Pattern.OPEN)
	track.free()
	_warmup = ShaderWarmup.new()
	_warmup._anchor = Node3D.new()
	_camera.add_child(_warmup._anchor)
	_warmup._anchor.position = Vector3(0.0, 0.0, -maxf(ShaderWarmup.ANCHOR_DISTANCE, _camera.near * 2.0))
	for name_value: String in ["Deck", "Seams", "Verge"]:
		var original := _source_chunk.get_node(name_value) as MeshInstance3D
		var surfaces: Array[Material] = []
		if original.material_override == null:
			for surface: int in original.mesh.get_surface_count():
				surfaces.append(original.get_active_material(surface))
		_warmup._spawn_external(original.mesh, original.material_override, surfaces)
		var probe := _warmup._anchor.get_child(_probes.size()) as MeshInstance3D
		_probes.append(probe)
		_original_materials.append({"override": original.material_override, "surfaces": surfaces})
		_original_transforms.append(probe.transform)
	_report["source_sha256"] = {}
	for path: String in ["res://scripts/utilities/shader_warmup.gd", "res://scripts/runner/runner_track.gd",
			"res://scripts/runner/runner_game.gd", "res://scripts/runner/runner_camera_composition.gd",
			"res://scripts/save/settings_manager.gd",
			"res://assets/shaders/ice.gdshader", "res://assets/shaders/snow.gdshader",
			"res://assets/art/characters/runner_penguin_v1.glb", "res://tests/dusk_warmup_raster_test.gd"]:
		_report.source_sha256[path] = FileAccess.get_sha256(path)
	_report["probe_resources"] = []
	for index: int in _probes.size():
		var probe := _probes[index]
		var surfaces: Array[Dictionary] = []
		for surface: int in probe.mesh.get_surface_count():
			var metadata := _surface_metadata(probe.mesh, surface)
			if metadata.is_empty() or probe.get_active_material(surface) == null:
				_report.errors.append("incomplete probe %d surface %d metadata" % [index, surface])
				return false
			metadata["material"] = ShaderWarmup._resource_label(probe.get_active_material(surface))
			surfaces.append(metadata)
		_report.probe_resources.append({"slot": index, "mesh": ShaderWarmup._resource_label(probe.mesh),
				"transform": str(probe.transform), "surfaces": surfaces,
				"probe_cast_shadow": probe.cast_shadow,
				"source_cast_shadow": GeometryInstance3D.SHADOW_CASTING_SETTING_OFF})
	return _report.errors.is_empty() and _probe_resource_rows_complete()


func _surface_metadata(mesh: Mesh, surface: int) -> Dictionary:
	# surface_get_format belongs to ArrayMesh, not the Mesh/PrimitiveMesh API.
	# Inspect the original PlaneMesh's arrays without converting, copying or
	# substituting its production vertex buffer. Do not invent compression flags.
	var arrays := mesh.surface_get_arrays(surface)
	if arrays.size() != Mesh.ARRAY_MAX or arrays[Mesh.ARRAY_VERTEX] == null:
		return {}
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if vertices.is_empty():
		return {}
	var slots: Array[Dictionary] = []
	var presence_mask := 0
	for slot: int in arrays.size():
		var value: Variant = arrays[slot]
		var element_count: int = 0 if value == null else value.size()
		if element_count > 0:
			presence_mask |= 1 << slot
		slots.append({"slot": slot, "variant_type": typeof(value), "elements": element_count})
	var metadata := {"index": surface, "vertex_count": vertices.size(),
			"array_slots": slots, "array_presence_mask": presence_mask,
			"array_presence_scope": "Nonempty returned array slots only; not packed GPU format/compression flags."}
	if mesh is ArrayMesh:
		metadata["format"] = (mesh as ArrayMesh).surface_get_format(surface)
		metadata["format_available"] = true
		metadata["format_scope"] = "ArrayMesh.surface_get_format on the original resource"
	elif mesh is PrimitiveMesh:
		metadata["format"] = null
		metadata["format_available"] = false
		metadata["format_scope"] = "PrimitiveMesh does not expose surface_get_format; original surface arrays recorded instead."
	else:
		return {}
	return metadata


func _probe_resource_rows_complete() -> bool:
	var rows: Array = _report.get("probe_resources", [])
	if _probes.size() != 3 or rows.size() != 3:
		return false
	for index: int in 3:
		var row: Dictionary = rows[index]
		var surfaces: Array = row.get("surfaces", [])
		if int(row.get("slot", -1)) != index or String(row.get("mesh", "")).is_empty() \
				or surfaces.size() != _probes[index].mesh.get_surface_count():
			return false
		for surface: int in surfaces.size():
			var metadata: Dictionary = surfaces[surface]
			if int(metadata.get("index", -1)) != surface or int(metadata.get("vertex_count", 0)) <= 0 \
					or metadata.get("array_slots", []).size() != Mesh.ARRAY_MAX \
					or String(metadata.get("material", "")).is_empty() \
					or not metadata.has("format") or not metadata.has("format_available") \
					or String(metadata.get("format_scope", "")).is_empty():
				return false
			if _probes[index].mesh is ArrayMesh:
				if not metadata.format_available or typeof(metadata.format) != TYPE_INT:
					return false
			elif metadata.format_available or metadata.format != null:
				return false
	return true


func _restore_probes() -> void:
	for index: int in _probes.size():
		var probe := _probes[index]
		probe.visible = true
		probe.transform = _original_transforms[index]
		probe.material_override = _original_materials[index].override
		for surface: int in probe.mesh.get_surface_count():
			probe.set_surface_override_material(surface, null if _original_materials[index].surfaces.is_empty()
					else _original_materials[index].surfaces[surface])


func _materials_exact() -> bool:
	for index: int in _probes.size():
		if _probes[index].material_override != _original_materials[index].override:
			return false
		for surface: int in _original_materials[index].surfaces.size():
			if _probes[index].get_active_material(surface) != _original_materials[index].surfaces[surface]:
				return false
	return true


func _id_material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.albedo_color = colour
	return material


func _set_id_case(index: int) -> void:
	_restore_probes()
	var black := _id_material(Color.BLACK)
	for probe: MeshInstance3D in _probes:
		probe.material_override = null
		for surface: int in probe.mesh.get_surface_count():
			probe.set_surface_override_material(surface, black)
	_probes[PROBE_INDICES[index]].set_surface_override_material(SURFACE_INDICES[index],
			_id_material(COLOURS[index]))


func _set_control(index: int) -> void:
	for probe_index: int in _probes.size():
		_probes[probe_index].visible = probe_index == PROBE_INDICES[index]
	var probe := _probes[PROBE_INDICES[index]]
	var arrays := probe.mesh.surface_get_arrays(SURFACE_INDICES[index])
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var rotation := Basis(Quaternion(normals[0].normalized(), Vector3.BACK))
	probe.basis = rotation.scaled(ShaderWarmup._fit_scale(probe.mesh) * CONTROL_SCALE)
	# Camera-facing, enlarged positive control ONLY. Production pass above uses
	# exact unmodified buffer, cell, scale and orientation from _spawn_external.
	probe.position = -(probe.basis * probe.mesh.get_aabb().get_center())


func _capture(stem: String) -> Image:
	for frame: int in 2:
		await RenderingServer.frame_post_draw
	if _done:
		return null
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.get_size() != SIZE:
		_fail("capture missing or not 1920x1080: %s" % stem)
		return null
	if image.save_png(_out.path_join(stem + ".png")) != OK:
		_fail("capture write failed: %s" % stem)
		return null
	return image


func _screen_bounds(probe: MeshInstance3D) -> Rect2i:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for corner: int in 8:
		var point := _camera.unproject_position(probe.global_transform * probe.mesh.get_aabb().get_endpoint(corner))
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return Rect2i(Vector2i(minimum.floor()) - Vector2i(2, 2),
			Vector2i(maximum.ceil() - minimum.floor()) + Vector2i(4, 4)) \
			.intersection(Rect2i(Vector2i.ZERO, SIZE))


func _count_colour(image: Image, colour: Color, bounds: Rect2i) -> int:
	var count := 0
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var pixel := image.get_pixel(x, y)
			var channels := Vector3(pixel.r, pixel.g, pixel.b)
			var desired := Vector3(colour.r, colour.g, colour.b)
			var strength := channels.dot(desired) / maxf(desired.length_squared(), 1.0)
			if strength > 0.02 and (channels - desired * strength).length() < 0.02:
				count += 1
	return count


func _msaa_samples(mode: int) -> int:
	match mode:
		Viewport.MSAA_DISABLED: return 1
		Viewport.MSAA_2X: return 2
		Viewport.MSAA_4X: return 4
		Viewport.MSAA_8X: return 8
	return -1


func _different_pixels(before: Image, after: Image, bounds: Rect2i) -> int:
	var count := 0
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > 1.0 / 255.0:
				count += 1
	return count


func _light_state() -> Array:
	var result: Array = []
	for child: Node in _lighting.get_children():
		if child is Light3D:
			var light := child as Light3D
			var row := {"class": light.get_class(), "transform": str(light.global_transform),
					"energy": light.light_energy, "colour": light.light_color.to_html(),
					"shadow_enabled": light.shadow_enabled, "cull_mask": light.light_cull_mask}
			if light is OmniLight3D:
				row["range"] = (light as OmniLight3D).omni_range
			if light is DirectionalLight3D:
				row["shadow_max_distance"] = (light as DirectionalLight3D).directional_shadow_max_distance
			result.append(row)
	return result


func _process(_delta: float) -> void:
	if not _done and _started > 0 and Time.get_ticks_usec() - _started > 90_000_000:
		_fail("90s diagnostic timeout; no partial capture is a passing result")


func _fail(message: String) -> void:
	_report.errors.append(message)
	push_error("dusk_warmup_raster: " + message)
	_finish(false)


func _finish(valid: bool) -> void:
	if _done:
		return
	_done = true
	# A GDScript runtime error can return from a helper without stopping the
	# caller's coroutine. Never let a partially populated inventory imply valid.
	valid = valid and bool(_report.get("complete", false)) and _report.errors.is_empty() \
			and _probe_resource_rows_complete() and _report.cases.size() == NAMES.size()
	_report["fixture_valid"] = valid
	if not _out.is_empty():
		var file := FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(_report, "\t"))
	print("[dusk_warmup_raster] DONE fixture_valid=%s coverage=%s" % [valid,
			_report.production_surface_coverage_pass])
	get_tree().quit(0 if valid else 1)


func _exit_tree() -> void:
	if _warmup != null:
		_warmup._anchor = null
		_warmup.free()
	if _source_chunk != null:
		_source_chunk.free()
