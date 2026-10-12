class_name DuskRealSurfacePrewarm
extends Node3D
## QA counterfactual only. A validated launcher injects its await into a COPIED
## RunnerGame. No live scene, gameplay, shader or warmup transform is changed.

const VIEWS := [Vector3.ZERO, Vector3(14.0, 7.0, 6.0), Vector3(-14.0, 7.0, 6.0)]
const NAMES := ["deck", "seams", "verge_body", "verge_crown", "verge_drop", "verge_snow"]
const MESH_INDICES := [0, 1, 2, 2, 2, 2]
const SURFACE_INDICES := [0, 0, 0, 1, 2, 3]
const ID_COLOURS := [Color.RED, Color.GREEN, Color.BLUE, Color.CYAN, Color.MAGENTA, Color.YELLOW]
const ID_LAYER: int = 1 << 19
const ENV_FIELDS := ["background_mode", "background_color", "tonemap_mode",
		"tonemap_exposure", "fog_enabled", "glow_enabled"]
const SOURCES := ["res://scripts/runner/runner_game.gd", "res://scripts/runner/runner_track.gd",
		"res://scripts/utilities/shader_warmup.gd", "res://scripts/utilities/visual_library.gd",
		"res://scripts/save/settings_manager.gd",
		"res://scripts/runner/runner_camera_composition.gd", "res://tests/runner_dusk_real_prewarm.gd",
		"res://assets/shaders/ice.gdshader", "res://assets/shaders/snow.gdshader",
		"res://data/art/runner_art_set_foundation.tres", "res://assets/art/characters/hero_penguin_v1.glb"]

# Keep the caller dynamic: copied RunnerGame preloads this helper, so a typed
# RunnerGame dependency here would create a circular script-load relationship.
var _game: Variant
var _chunk: RunnerTrack.RunnerChunk
var _overlay: CanvasLayer
var _camera_transform: Transform3D
var _camera_mask: int
var _track_visible: bool
var _env_state: Dictionary = {}
var _canvas_originals: Array[Dictionary] = []
var _originals: Array[Dictionary] = []
var _meshes: Array[MeshInstance3D] = []
var _multis: Array[MultiMeshInstance3D] = []
var _multi_originals: Array[Dictionary] = []
var _multi_views: Array[Dictionary] = []
var _restored: bool = false
var _started: int = 0
var _out: String
var _proof: bool = false
var _art_scope := "deck"
var _report: Dictionary = {"success": false, "qa_counterfactual": true,
		"live_runtime_changed": false, "surface_coverage_pass": false, "views": [], "errors": []}


static func warm(game: Node) -> bool:
	# The prepare launcher actually instantiates RunnerGame headlessly. Import
	# alone does not reliably expose every inherited-scene parser failure.
	if "dusk_real_prewarm_parse_only=true" in OS.get_cmdline_user_args():
		var isolated := String(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")) \
				.begins_with("waddle-dusk-prewarm-prepare-")
		if not GameConfig.is_headless() or not isolated:
			push_error("DUSK parser-only hook requires isolated headless prepare")
			game.get_tree().quit(2)
		else:
			print("[dusk_real_prewarm] parser-only hook reached")
			game.get_tree().quit(0)
		return false
	var instance := DuskRealSurfacePrewarm.new()
	instance.name = "QARealDuskPrewarm"
	instance._game = game
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("dusk_real_prewarm_out="):
			instance._out = argument.trim_prefix("dusk_real_prewarm_out=")
		elif argument == "dusk_real_prewarm_proof=true":
			instance._proof = true
		elif argument.begins_with("dusk_real_prewarm_scope="):
			instance._art_scope = argument.trim_prefix("dusk_real_prewarm_scope=")
	if instance._out.is_empty() or not instance._out.is_absolute_path() \
			or instance._art_scope not in ["deck", "dressing"] \
			or not DirAccess.dir_exists_absolute(instance._out) or GameConfig.is_headless() \
			or not String(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")) \
					.begins_with("waddle-wars-perf-"):
		push_error("real DUSK prewarm requires isolated windowed launcher/output")
		instance.free()
		game.get_tree().quit(2)
		return false
	game.add_child(instance)
	var passed: bool = await instance._run()
	var report: Dictionary = instance._report
	var output: String = instance._out
	var proof: bool = instance._proof
	instance.free()
	report["residual_qa_node_count"] = game.find_children("QARealDuskPrewarm", "", true, false).size()
	passed = passed and report.residual_qa_node_count == 0
	report["success"] = passed
	var file := FileAccess.open(output.path_join("prewarm_report.json"), FileAccess.WRITE)
	if file == null:
		passed = false
	else:
		file.store_string(JSON.stringify(report, "\t"))
	print("[dusk_real_prewarm] complete success=%s proof=%s residual=%d" % [
			passed, proof, report.residual_qa_node_count])
	if not passed or proof:
		game.get_tree().quit(0 if passed else 2)
		return false
	return true


func _run() -> bool:
	_started = Time.get_ticks_usec()
	if _game.camera == null or _game.track == null or _game.player == null \
			or _game.build_finished or _game.running or _game._presentation_started:
		_report.errors.append("hook is not before initial presentation/countdown")
		return false
	_camera_transform = _game.camera.transform
	_camera_mask = _game.camera.cull_mask
	_track_visible = _game.track.visible
	for field: String in ENV_FIELDS:
		_env_state[field] = _game._world_env.environment.get(field)
	if _proof:
		# A 3D cull mask does not exclude CanvasLayers. Suppress their original
		# local visibility only for this untimed proof, or HUD colours could be
		# falsely counted as covered surface pixels. Performance never does this.
		for node: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
			var layer := node as CanvasLayer
			_canvas_originals.append({"node": layer, "visible": layer.visible})
			layer.visible = false
	var before := _gameplay_state()
	_report["proof"] = _proof
	_report["art_scope"] = _art_scope
	_report["renderer"] = RenderingServer.get_current_rendering_method()
	_report["viewport_msaa_3d"] = get_viewport().msaa_3d
	var effective_msaa: int = SettingsManager.msaa_3d_mode()
	_report["msaa"] = {"requested": String(SettingsManager.get_setting("display", "msaa")),
			"effective_mode": effective_msaa, "effective_samples": _msaa_samples(effective_msaa),
			"actual_mode": get_viewport().msaa_3d,
			"actual_samples": _msaa_samples(get_viewport().msaa_3d)}
	_report["camera_fov"] = _game.camera.fov
	var viewport_size := get_viewport().get_visible_rect().size
	_report["viewport"] = [viewport_size.x, viewport_size.y]
	if _report.renderer != "gl_compatibility" or _game.camera.fov != 74.0 \
			or get_viewport().msaa_3d != effective_msaa or viewport_size != Vector2(1920, 1080):
		_report.errors.append("Compatibility/74-degree/resolved-MSAA/1920x1080 contract mismatch")
	_report["state_before"] = before
	_report["camera_before"] = str(_camera_transform)
	_report["track_visible_before"] = _track_visible
	_report["source_sha256"] = {}
	for path: String in SOURCES:
		_report.source_sha256[path] = FileAccess.get_sha256(path)
	_game.track.visible = false
	_overlay = CanvasLayer.new()
	_overlay.layer = 200
	_overlay.visible = not _proof
	add_child(_overlay)
	var curtain := ColorRect.new()
	curtain.color = Color(0.025, 0.045, 0.075, 1.0)
	_overlay.add_child(curtain)
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_chunk = RunnerTrack.RunnerChunk.new()
	_chunk.name = "QAFullScaleDusk"
	_chunk.index = 17
	_chunk.biome = RunnerTrack.Biome.DUSK
	_chunk.process_mode = Node.PROCESS_MODE_DISABLED
	_game.track._build_deck(_chunk, RunnerTrack.Pattern.OPEN)
	if _art_scope == "dressing":
		# Exact independent production art stream, not the live gameplay RNG.
		var art_rng: RandomNumberGenerator = _game.track._chunk_rng(17, 60493)
		_report["art_rng"] = {"source": "RunnerTrack._chunk_rng(17, 60493)",
				"seed": str(art_rng.seed), "state_before": str(art_rng.state)}
		_game.track._build_dressing(_chunk, art_rng)
		_report.art_rng["state_after"] = str(art_rng.state)
		_report["cache_scope"] = "Production cache lookups and real MultiMesh buffer creation intentionally " \
				+ "warm global/renderer resources; freeing QA nodes does not undo cache effects. " \
				+ "No run_pattern, add_obstacle or finish call; no fish/contact/mark flush or LOW ridge bundled."
	add_child(_chunk)
	_chunk.global_transform = _game.track.global_transform
	_report["source_nodes"] = []
	for mesh_name: String in ["Deck", "Seams", "Verge"]:
		var mesh := _chunk.get_node(mesh_name) as MeshInstance3D
		var surfaces: Array[Material] = []
		for surface: int in mesh.mesh.get_surface_count():
			surfaces.append(mesh.get_surface_override_material(surface))
		_meshes.append(mesh)
		_originals.append({"mesh": mesh.mesh, "override": mesh.material_override,
				"surfaces": surfaces, "layers": mesh.layers})
		var materials: Array[String] = []
		for surface: int in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface)
			materials.append(str(material.get_instance_id()) if material != null else "missing")
		_report.source_nodes.append({"name": mesh_name, "mesh_class": mesh.mesh.get_class(),
				"surface_count": mesh.mesh.get_surface_count(), "mesh_identity": str(mesh.mesh.get_instance_id()),
				"active_material_identities": materials, "local_transform": str(mesh.transform),
				"shadow_mode": mesh.cast_shadow})
		if mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF or mesh.scale != Vector3.ONE:
			_report.errors.append("source shadow/scale contract changed")
	if not _inventory_dressing():
		_report.errors.append("actual dressing resource inventory incomplete")
		_restore()
		return false
	var coverage := PackedInt32Array()
	coverage.resize(NAMES.size() + _multis.size())
	coverage.fill(0)
	var expected_views := VIEWS.size() + _multi_views.size()
	_report["expected_views"] = expected_views
	for view_index: int in expected_views:
		var cases: Array[int] = []
		if view_index < VIEWS.size():
			for case_index: int in NAMES.size():
				cases.append(case_index)
		else:
			cases.append(NAMES.size() + view_index - VIEWS.size())
		if view_index == 0:
			_game.camera.transform = _camera_transform
		elif view_index < VIEWS.size():
			_game.camera.global_position = _game.track.to_global(VIEWS[view_index])
			_game.camera.look_at(_game.track.to_global(Vector3(0.0, 0.0, -14.0)), Vector3.UP)
		else:
			var framed: Dictionary = _multi_views[view_index - VIEWS.size()]
			_game.camera.global_position = framed.position
			_game.camera.look_at(framed.target, Vector3.UP)
		await _two_draws()
		var view := {"index": view_index, "camera_transform": str(_game.camera.global_transform),
				"actual_material_draws": 2, "coverage_pixels": [],
				"kind": "deck" if view_index < VIEWS.size() else "framed_dressing_family"}
		if _proof:
			if _save_image("actual_view_%d" % view_index) == null:
				_report.errors.append("actual-material image missing")
			for case_index: int in cases:
				_set_id_case(case_index)
				await _two_draws()
				var image := _save_image("id_view_%d_%s" % [view_index, _case_name(case_index)])
				if image == null:
					_report.errors.append("ID image missing")
					continue
				var pixels := _id_pixels(image, _case_colour(case_index))
				coverage[case_index] = maxi(coverage[case_index], pixels)
				view.coverage_pixels.append({"surface": _case_name(case_index), "pixels": pixels})
			_restore_id_state()
		_report.views.append(view)
	_report["surface_max_resolved_pixels"] = Array(coverage)
	_report["coverage_names"] = []
	for case_index: int in coverage.size():
		_report.coverage_names.append(_case_name(case_index))
	_report["surface_coverage_pass"] = _proof and coverage.count(0) == 0
	var originals_exact := true
	for index: int in _meshes.size():
		originals_exact = originals_exact and _meshes[index].mesh == _originals[index].mesh \
				and _meshes[index].material_override == _originals[index].override \
				and _meshes[index].layers == _originals[index].layers
		for surface: int in _originals[index].surfaces.size():
			originals_exact = originals_exact and _meshes[index].get_surface_override_material(surface) \
					== _originals[index].surfaces[surface]
	_report["original_mesh_material_layer_state_exact"] = originals_exact
	var multis_exact := true
	for index: int in _multis.size():
		var multi := _multis[index]
		var original: Dictionary = _multi_originals[index]
		multis_exact = multis_exact and multi.multimesh == original.multimesh \
				and multi.multimesh.mesh == original.mesh and multi.multimesh.buffer == original.buffer \
				and multi.material_override == original.material and multi.layers == original.layers \
				and multi.cast_shadow == original.shadow and multi.transform == original.transform
	_report["original_multimesh_buffer_material_state_exact"] = multis_exact
	_restore()
	# A restored full-scene draw and queued-free flush happen before returning
	# to build_finished/ordinary shader warmup, never inside the timed sample.
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var after := _gameplay_state()
	_report["state_after"] = after
	_report["state_unchanged"] = before == after
	_report["camera_restored"] = _game.camera.transform == _camera_transform \
			and _game.camera.cull_mask == _camera_mask
	_report["track_visibility_restored"] = _game.track.visible == _track_visible
	var environment_restored := true
	for field: String in _env_state:
		environment_restored = environment_restored and _game._world_env.environment.get(field) == _env_state[field]
	_report["environment_restored"] = environment_restored
	var canvas_restored := true
	for original: Dictionary in _canvas_originals:
		canvas_restored = canvas_restored and is_instance_valid(original.node) \
				and original.node.visible == original.visible
	_report["proof_canvas_layers_hidden"] = _canvas_originals.size()
	_report["canvas_visibility_restored"] = canvas_restored
	_report["scope"] = "QA-only full-scale real deck, seams and verge at three views; " \
			+ "optional seeded dressing retains actual MultiMeshes with separately framed family views. " \
			+ "original materials/shadowsOFF. Proof ID proxies are separate, resolved pixels " \
			+ "under viewport MSAA, not program-link or GPU timing queries. No proof readbacks in performance mode. " \
			+ "Resource identities record reuse, not proof of submission or resident GPU memory."
	return _report.errors.is_empty() and _report.views.size() == expected_views and before == after \
			and originals_exact and multis_exact \
			and _report.camera_restored and _report.track_visibility_restored \
			and environment_restored and canvas_restored \
			and (not _proof or _report.surface_coverage_pass)


func _inventory_dressing() -> bool:
	_report["dressing_inventory"] = []
	var expected := 0
	for child: Node in _chunk.get_children():
		if not child is MultiMeshInstance3D:
			continue
		expected += 1
		var multi := child as MultiMeshInstance3D
		var mm := multi.multimesh
		if mm == null or mm.mesh == null or mm.mesh.get_surface_count() != 1 \
				or mm.instance_count <= 0 or multi.material_override == null:
			_report.errors.append("dressing inventory requires real nonempty single-surface MultiMesh")
			continue
		var transforms: Array[String] = []
		var bounds := AABB()
		for index: int in mm.instance_count:
			var instance_transform := mm.get_instance_transform(index)
			transforms.append(str(instance_transform))
			var instance_bounds: AABB = multi.global_transform * instance_transform * mm.mesh.get_aabb()
			bounds = instance_bounds if index == 0 else bounds.merge(instance_bounds)
		var buffer := mm.buffer
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		digest.update(buffer.to_byte_array())
		var mesh_format: Variant = (mm.mesh as ArrayMesh).surface_get_format(0) \
				if mm.mesh is ArrayMesh else null
		var arrays: Array = mm.mesh.surface_get_arrays(0)
		var slot_counts: Array[int] = []
		for slot: Variant in arrays:
			slot_counts.append(0 if slot == null else slot.size())
		var material := multi.material_override as BaseMaterial3D
		var flags := {}
		if material != null:
			flags = {"vertex_color_albedo": material.vertex_color_use_as_albedo,
					"shading": material.shading_mode, "transparency": material.transparency,
					"cull": material.cull_mode, "albedo": material.albedo_color.to_html(),
					"roughness": material.roughness, "metallic": material.metallic,
					"emission_enabled": material.emission_enabled}
		_multis.append(multi)
		_multi_originals.append({"multimesh": mm, "mesh": mm.mesh, "buffer": buffer.duplicate(),
				"material": multi.material_override, "layers": multi.layers,
				"shadow": multi.cast_shadow, "transform": multi.transform})
		_report.dressing_inventory.append({"name": String(multi.name), "node_class": multi.get_class(),
				"instance_count": mm.instance_count, "visible_instance_count": mm.visible_instance_count,
				"transform_format": mm.transform_format, "use_colors": mm.use_colors,
				"use_custom_data": mm.use_custom_data, "buffer_floats": buffer.size(),
				"buffer_sha256": digest.finish().hex_encode(), "instance_transforms": transforms,
				"mesh_class": mm.mesh.get_class(), "mesh_identity": str(mm.mesh.get_instance_id()),
				"surface_format": mesh_format, "surface_array_slot_counts": slot_counts,
				"material_identity": str(multi.material_override.get_instance_id()),
				"material_class": multi.material_override.get_class(), "material_flags": flags,
				"shadow": multi.cast_shadow, "visibility_range_end": multi.visibility_range_end,
				"world_bounds": str(bounds)})
		# Camera-only framing: leave real geometry/instance buffers at full scale.
		var aspect := get_viewport().get_visible_rect().size.aspect()
		var half_extent := maxf(bounds.size.y, bounds.size.x / aspect) * 0.5
		var distance := half_extent / tan(deg_to_rad(_game.camera.fov * 0.5)) * 1.5 \
				+ bounds.size.z * 0.6 + 10.0
		var target := bounds.get_center()
		_multi_views.append({"target": target,
				"position": target + Vector3(0.0, maxf(10.0, distance * 0.45), distance)})
	if _art_scope == "dressing" and _multis.is_empty():
		_report.errors.append("actual dressing builder produced no MultiMeshes")
	var complete: bool = _multis.size() == expected and _multi_views.size() == expected \
			and _report.dressing_inventory.size() == expected
	_report["dressing_inventory_complete"] = complete
	return complete and _report.errors.is_empty()


func _case_name(index: int) -> String:
	return NAMES[index] if index < NAMES.size() else "multimesh_" + String(_multis[index - NAMES.size()].name)


func _case_colour(index: int) -> Color:
	return ID_COLOURS[index] if index < NAMES.size() else Color.WHITE


func _gameplay_state() -> Dictionary:
	var track: RunnerTrack = _game.track
	var ids: Array[String] = []
	for node: Node in track.find_children("*", "", true, false):
		ids.append(str(node.get_instance_id()))
	return {"rng_state": str(_game._rng.state), "seed": track._seed,
			"countdown": _game._countdown, "elapsed": _game.elapsed,
			"build_finished": _game.build_finished, "presentation_started": _game._presentation_started,
			"running": _game.running, "distance": _game.player.distance,
			"player_position": _game.player.position, "speed": _game.player.speed,
			"track_process_mode": track.process_mode, "track_node_ids": ids,
			"first": track._first_index, "next": track._next_index, "chunks": track._chunks.size(),
			"pattern": track._last_pattern, "tunnel_left": track._tunnel_left,
			"powerup_cursor": track._powerup_cursor, "next_powerup_z": track._next_powerup_z,
			"jump_z": track._lane_jump_z.duplicate(), "slide_z": track._lane_slide_z.duplicate(),
			"air_from_z": track._air_from_z, "air_to_z": track._air_to_z}


func _two_draws() -> void:
	for frame: int in 2:
		await RenderingServer.frame_post_draw


func _msaa_samples(mode: int) -> int:
	match mode:
		Viewport.MSAA_DISABLED: return 1
		Viewport.MSAA_2X: return 2
		Viewport.MSAA_4X: return 4
		Viewport.MSAA_8X: return 8
	return -1


func _set_id_case(index: int) -> void:
	var env: Environment = _game._world_env.environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.fog_enabled = false
	env.glow_enabled = false
	_game.camera.cull_mask = ID_LAYER
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color.BLACK
	for mesh: MeshInstance3D in _meshes:
		mesh.layers = ID_LAYER
		mesh.material_override = null
		for surface: int in mesh.mesh.get_surface_count():
			mesh.set_surface_override_material(surface, black)
	for multi: MultiMeshInstance3D in _multis:
		multi.layers = ID_LAYER
		multi.material_override = black
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = _case_colour(index)
	if index < NAMES.size():
		_meshes[MESH_INDICES[index]].set_surface_override_material(SURFACE_INDICES[index], material)
	else:
		_multis[index - NAMES.size()].material_override = material


func _restore_id_state() -> void:
	_game.camera.cull_mask = _camera_mask
	for field: String in _env_state:
		_game._world_env.environment.set(field, _env_state[field])
	for index: int in _meshes.size():
		_meshes[index].layers = _originals[index].layers
		_meshes[index].material_override = _originals[index].override
		for surface: int in _originals[index].surfaces.size():
			_meshes[index].set_surface_override_material(surface, _originals[index].surfaces[surface])
	for index: int in _multis.size():
		_multis[index].layers = _multi_originals[index].layers
		_multis[index].material_override = _multi_originals[index].material


func _save_image(stem: String) -> Image:
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(_out.path_join(stem + ".png")) != OK:
		return null
	return image


func _id_pixels(image: Image, colour: Color) -> int:
	# Copy only packed bytes for this untimed proof, avoiding per-pixel engine
	# calls. The camera's QA-only render layer excludes every non-study mesh.
	image.convert(Image.FORMAT_RGBA8)
	var data := image.get_data()
	var count := 0
	var red := colour.r > 0.5
	var green := colour.g > 0.5
	var blue := colour.b > 0.5
	for offset: int in range(0, data.size(), 4):
		var strength: int = data[offset] if red else (data[offset + 1] if green else data[offset + 2])
		if strength > 5 \
				and (absi(data[offset] - strength) <= 5 if red else data[offset] <= 5) \
				and (absi(data[offset + 1] - strength) <= 5 if green else data[offset + 1] <= 5) \
				and (absi(data[offset + 2] - strength) <= 5 if blue else data[offset + 2] <= 5):
			count += 1
	return count


func _restore() -> void:
	if _restored or _env_state.is_empty():
		return
	_restored = true
	_restore_id_state()
	_game.camera.transform = _camera_transform
	_game.track.visible = _track_visible
	for original: Dictionary in _canvas_originals:
		if is_instance_valid(original.node):
			original.node.visible = original.visible
	if is_instance_valid(_chunk):
		_chunk.free()
	_chunk = null
	_meshes.clear()
	_multis.clear()
	if is_instance_valid(_overlay):
		_overlay.free()
	_overlay = null


func _process(_delta: float) -> void:
	if _started > 0 and Time.get_ticks_usec() - _started > 90_000_000:
		_restore()
		push_error("real DUSK prewarm timed out before completion")
		get_tree().quit(2)


func _exit_tree() -> void:
	_restore()
