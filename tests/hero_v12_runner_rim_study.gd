extends "res://tests/hero_v12_atlas_runner_capture.gd"
## Untimed actual-runner pair plus optional hero-only lower/diffuse fill controls.
## Reuses one existing rim; no new light, geometry, material or texture.

const STUDY_BINDING := "res://qa_hero/runner_rim_binding.json"
const HERO_FILL_LAYER: int = 1 << 18
var _rim_binding: Dictionary = {}
var _hero_fill_nodes: Array[GeometryInstance3D] = []
var _rim_controls: Dictionary = {}


func _ready() -> void:
	if DisplayServer.get_name() == "headless" and "parsercheck=true" in OS.get_cmdline_user_args():
		# The inherited capture watchdog has no startup timestamp in parser mode.
		# quit() is deferred, so disable it before another process notification.
		set_process(false)
		set_physics_process(false)
		var identity := String(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
		if not identity.begins_with("waddle-v12-atlas-runner-review-"):
			_reject("Parser check requires the isolated atlas project")
			return
		print("RUNNER RIM PARSER: PASS (no raster/lighting proof)")
		get_tree().quit(0)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STUDY_BINDING))
	if not parsed is Dictionary or parsed.get("route") != "actual-runner-rim-energy-pair-v1" \
			or parsed.get("scene_script_sha256") != FileAccess.get_sha256(get_script().resource_path) \
			or parsed.get("rim_energy") != 2.1 or parsed.get("freeze_after_running_seconds") != 1.0:
		_reject("Runner rim study requires its immutable isolated binding")
		return
	_rim_binding = parsed
	var study: Variant = parsed.get("hero_fill_study", false)
	var diffuse_study: Variant = parsed.get("hero_fill_diffuse_study", false)
	var labels := ["baseline_current_rim", "rim_startup_energy_2_1"]
	if not study is bool or not diffuse_study is bool or (diffuse_study and not study):
		_reject("Hero-fill study flag must be boolean")
		return
	if study:
		labels.append_array(["hero_only_original_rim", "hero_only_low_fill_2_1"])
		if parsed.get("hero_fill_layer") != HERO_FILL_LAYER or parsed.get("hero_fill_y_offset") != 0.9:
			_reject("Hero-fill study requires the exact private layer and .9m offset")
			return
	if diffuse_study:
		labels.append("hero_only_low_diffuse_fill_4_2")
		if parsed.get("hero_fill_diffuse_energy") != 4.2 or parsed.get("hero_fill_specular") != 0.0:
			_reject("Diffuse hero-fill study requires existing-rim energy4.2 and specular0")
			return
	if parsed.get("variants") != labels:
		_reject("Unexpected runner rim variants")
		return
	super._ready()
	if _play or _output != _rim_binding.get("capture_output"):
		_reject("Rim study only supports its bound capture output")
		return
	DisplayServer.window_set_title("Waddle Wars — actual runner rim study (QA only)")
	DisplayServer.window_move_to_foreground()
	get_window().always_on_top = true


func _capture() -> void:
	# Inherited startup generates the normal seed20260907 runner, countdown,
	# autopilot and camera. Preserve that history; do not teleport to a distance.
	var started_at := _game.elapsed
	while _game.running and _game.elapsed - started_at < 1.0:
		await get_tree().process_frame
	if not _game.running:
		_reject("Runner stopped before the chosen ordinary chase frame")
		return
	var rig := _game.player.find_child("AuthoredHeroPenguin", true, false) as HeroPenguinRig
	var rim := _game.get_node_or_null("PlayerRim") as OmniLight3D
	if rig == null or rim == null or not rig.has_method("qa_material_report"):
		_reject("Expected the real authored hero and existing PlayerRim")
		return
	var source_material: Dictionary = rig.call("qa_material_report")
	if source_material.get("passed") != true or source_material.get("material_mode") != "atlas" \
			or source_material.get("candidate_sha256") != _rim_binding.get("candidate_sha256") \
			or source_material.get("shader_sha256") != _rim_binding.get("shader_sha256"):
		_reject("The actual runner must use the bound baseline atlas material")
		return
	var original_energy: float = rim.light_energy
	if original_energy <= 0.0 or original_energy >= 2.1:
		_reject("Expected a positive biome-blended rim below its original2.1 startup energy")
		return
	var original_time_scale := Engine.time_scale
	var original_process_mode := _game.process_mode
	_game.process_mode = Node.PROCESS_MODE_DISABLED
	# Freeze shader TIME and particle simulation too, not just scene scripts.
	# No animation, simulation or performance samples run between these rasters.
	Engine.time_scale = 0.0
	for _settle: int in 2:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var before := _snapshot_runner(rig)
	_rim_controls = {"path": String(rim.get_path()), "energy": original_energy,
		"specular": rim.light_specular,
		"mask": rim.light_cull_mask, "transform": rim.transform, "global_transform": rim.global_transform,
		"target_global_position": Vector3(rim.global_position.x, _game.player.global_position.y + 0.9, rim.global_position.z),
		"hero_layers": {}}
	var layer_audit: Dictionary = {}
	if _rim_binding.get("hero_fill_study", false):
		var inventory: Dictionary = {}
		for node: Node in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
			var geometry := node as GeometryInstance3D
			inventory[String(node.get_path())] = geometry.layers
			if (geometry.layers & HERO_FILL_LAYER) != 0:
				_reject("Private hero-fill layer already occupied in the actual scene")
				return
		for node: Node in rig.find_children("*", "GeometryInstance3D", true, false):
			var geometry := node as GeometryInstance3D
			_hero_fill_nodes.append(geometry)
			_rim_controls.hero_layers[String(node.get_path())] = geometry.layers
		if _hero_fill_nodes.is_empty() or (_game.camera.cull_mask & HERO_FILL_LAYER) == 0:
			_reject("Expected actual authored hero geometry and an unchanged camera that sees the private bit")
			return
		layer_audit = {"private_bit": HERO_FILL_LAYER, "occupied_before": 0,
			"geometry_inventory": inventory, "hero_paths": _rim_controls.hero_layers.keys(),
			"camera_cull_mask": _game.camera.cull_mask, "scope": "Only default authored hero subtree; no production cosmetic/LOD policy"}
	rim.light_energy = 2.1
	var changed := _snapshot_runner(rig)
	var requested_energy: float = rim.light_energy
	rim.light_energy = original_energy
	var states: Array[Dictionary] = [before, changed]
	if _rim_binding.get("hero_fill_study", false):
		for index: int in range(2, _rim_binding.variants.size()):
			_apply_variant(index, rim, requested_energy)
			states.append(_snapshot_runner(rig))
			if _snapshot_runner(rig, true) != before:
				_reject("Hero-fill study changed state outside explicitly normalized controls")
				return
		_apply_variant(0, rim, requested_energy)
	if _snapshot_runner(rig) != before:
		_reject("Rim did not restore before the baseline frame")
		return
	if DirAccess.dir_exists_absolute(_output) or DirAccess.make_dir_recursive_absolute(_output) != OK:
		_reject("Keep earlier evidence; use a fresh runner rim output")
		return
	var frames: Array[Dictionary] = []
	var labels: Array = _rim_binding.variants
	for index: int in labels.size():
		_apply_variant(index, rim, requested_energy)
		var expected: Dictionary = states[index]
		for _wait: int in 2:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var actual := _snapshot_runner(rig)
		if actual != expected:
			_reject("Frozen runner world/pose/material/camera/light state drifted")
			return
		var filename: String = "%02d_%s.png" % [index, labels[index]]
		var shot := get_viewport().get_texture().get_image()
		if shot == null or shot.get_size() != Vector2i(540, 960) \
				or shot.save_png(_output.path_join(filename)) != OK:
			_reject("Expected visible portrait runner raster")
			return
		shot = null
		frames.append({"variant": labels[index], "file": filename,
			"png_sha256": FileAccess.get_sha256(_output.path_join(filename)), "state": actual,
			"normalized_state": _snapshot_runner(rig, true), "controls": _observed_controls(rim)})
	_apply_variant(0, rim, requested_energy)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var restored := _snapshot_runner(rig)
	var final_material: Dictionary = rig.call("qa_material_report")
	var passed: bool = restored == before and final_material.get("passed") == true
	var report := {"schema_version": 1, "route": _rim_binding.route, "passed": passed,
		"production_ready": false, "source_fidelity_approved": false, "performance_measured": false,
		"binding_sha256": FileAccess.get_sha256(STUDY_BINDING),
		"candidate_sha256": _rim_binding.candidate_sha256, "shader_sha256": _rim_binding.shader_sha256,
		"engine": Engine.get_version_info(), "renderer": RenderingServer.get_current_rendering_method(),
		"source_material_report": source_material, "final_material_report": final_material,
		"key_context": {"seed": _game.generation_seed, "distance": _game.player.distance,
			"elapsed": _game.elapsed, "biome": int(_game.track.biome_at_z(_game.player.position.z)),
			"player_state": int(_game.player.state), "motion": rig.call("qa_motion_snapshot")},
		"rim_energy_change": {"light_path": String(rim.get_path()), "before": original_energy,
			"after": requested_energy}, "state_before": before, "state_variant": changed,
		"frames": frames, "state_after_restore": restored, "original_rim_restored": restored == before,
		"layer_audit": layer_audit, "original_controls": _observed_controls(rim),
		"freeze": {"game_process_mode": Node.PROCESS_MODE_DISABLED, "engine_time_scale": 0.0,
			"original_process_mode": original_process_mode, "original_time_scale": original_time_scale},
		"scope": "Untimed actual runner controls; optional hero-only fill changes only authored-hero layer bit and existing rim mask/energy/vertical position/specular. No production cosmetic/LOD policy or performance proof."}
	var file := FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE)
	if file == null:
		_reject("Could not save runner rim report")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file = null
	print("ACTUAL RUNNER RIM STUDY: ", "PASS" if passed else "FAIL")
	# World snapshots retain Mesh/MultiMesh/Material Resources in their human-
	# readable state arrays. Let this entire coroutine unwind before teardown;
	# awaiting _finish_capture here retains those resources through engine quit.
	rim = null
	rig = null
	_hero_fill_nodes.clear()
	_rim_controls.clear()
	call_deferred("_finish_rim_capture", 0 if passed else 2, original_time_scale, original_process_mode)


func _finish_rim_capture(code: int, original_time_scale: float, original_process_mode: int) -> void:
	# Only scalar arguments survive here. The real runner stays frozen until
	# its snapshot coroutine is gone, then inherited teardown immediately
	# queues the owned scene and waits for resource cleanup before quitting.
	_game.process_mode = original_process_mode as Node.ProcessMode
	Engine.time_scale = original_time_scale
	_finish_capture(code)


func _reject(message: String) -> void:
	push_error(message)
	get_tree().quit(2)


func _exact(value: Variant) -> Dictionary:
	var data := var_to_bytes(value)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(data)
	return {"sha256": hash.finish().hex_encode(), "state_bytes_hex": data.hex_encode(), "state": value}


func _storage(object: Object, depth: int = 0) -> Dictionary:
	var result := {"class": object.get_class()}
	for property: Dictionary in object.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var value: Variant = object.get(String(property.name))
		if value is Resource and depth < 4:
			result[property.name] = _storage(value, depth + 1)
		elif value is Object:
			result[property.name] = {"id": value.get_instance_id(), "class": value.get_class()}
		else:
			result[property.name] = value
	return result


func _apply_variant(index: int, rim: OmniLight3D, requested_energy: float) -> void:
	rim.light_energy = 4.2 if index == 4 else (requested_energy if index == 1 or index == 3 else float(_rim_controls.energy))
	rim.light_specular = 0.0 if index == 4 else float(_rim_controls.specular)
	rim.light_cull_mask = HERO_FILL_LAYER if index >= 2 else int(_rim_controls.mask)
	rim.transform = _rim_controls.transform
	for node: GeometryInstance3D in _hero_fill_nodes:
		var original: int = _rim_controls.hero_layers[String(node.get_path())]
		node.layers = original | HERO_FILL_LAYER if index >= 2 else original
	if index >= 3:
		rim.global_position = _rim_controls.target_global_position


func _observed_controls(rim: OmniLight3D) -> Dictionary:
	var layers: Dictionary = {}
	for node: GeometryInstance3D in _hero_fill_nodes:
		layers[String(node.get_path())] = node.layers
	return {"hero_layers": layers, "rim_energy": rim.light_energy, "rim_cull_mask": rim.light_cull_mask,
		"rim_specular": rim.light_specular,
		"rim_local_position": [rim.position.x, rim.position.y, rim.position.z],
		"rim_global_position": [rim.global_position.x, rim.global_position.y, rim.global_position.z],
		"rim_local_basis": _exact(rim.transform.basis), "rim_global_basis": _exact(rim.global_transform.basis),
		"player_global_y": _game.player.global_position.y}


func _snapshot_runner(rig: HeroPenguinRig, normalize_controls: bool = false) -> Dictionary:
	var world: Array = [[_game.get_path(), _game.process_mode]]
	var pose: Array = []
	var lights: Array = []
	var materials: Dictionary = {}
	for node: Node in _game.find_children("*", "Node3D", true, false):
		var spatial := node as Node3D
		var row: Array = [node.get_path(), spatial.transform, spatial.global_transform, spatial.visible]
		var path := String(node.get_path())
		if normalize_controls and path == _rim_controls.path:
			row[1] = _rim_controls.transform
			row[2] = _rim_controls.global_transform
		if node is GeometryInstance3D:
			var layers: int = _rim_controls.hero_layers.get(path, node.layers) if normalize_controls else node.layers
			row.append([layers, node.cast_shadow, node.material_override, node.material_overlay])
		if node is MeshInstance3D:
			row.append(node.mesh)
			var overrides: Array = []
			var surface_count: int = node.mesh.get_surface_count() if node.mesh != null else 0
			for surface: int in surface_count:
				overrides.append(node.get_surface_override_material(surface))
			row.append(overrides)
			if node.mesh != null and rig.is_ancestor_of(node):
				var morphs: Array = []
				for morph: int in node.mesh.get_blend_shape_count():
					morphs.append([node.mesh.get_blend_shape_name(morph), node.get_blend_shape_value(morph)])
				pose.append([node.get_path(), morphs])
				for material: Material in overrides:
					if material != null:
						materials[str(material.get_instance_id())] = _storage(material)
		elif node is MultiMeshInstance3D and node.multimesh != null:
			row.append([node.multimesh, node.multimesh.mesh, node.multimesh.instance_count,
				node.multimesh.visible_instance_count, node.multimesh.buffer])
		elif node is Skeleton3D:
			for bone: int in node.get_bone_count():
				pose.append([node.get_path(), node.get_bone_name(bone), node.get_bone_pose(bone), node.get_bone_global_pose(bone)])
		if node is Light3D:
			var properties := _storage(node)
			var global_pose: Transform3D = node.global_transform
			if normalize_controls and path == _rim_controls.path:
				properties.light_energy = _rim_controls.energy
				properties.light_specular = _rim_controls.specular
				properties.light_cull_mask = _rim_controls.mask
				properties.transform = _rim_controls.transform
				global_pose = _rim_controls.global_transform
			lights.append([node.get_path(), global_pose, properties])
		world.append(row)
	for node: Node in _game.find_children("*", "WorldEnvironment", true, false):
		lights.append([node.get_path(), _storage(node.environment)])
	return {"world": _exact(world), "pose": _exact(pose), "lighting_environment": _exact(lights),
		"material": _exact(materials), "camera": _exact([_game.camera.global_transform,
			_storage(_game.camera), get_viewport().get_visible_rect().size]), "engine_time_scale": Engine.time_scale,
		"world_scope": "Node transforms/visibility, geometry and material resource identities, mesh overrides, MultiMesh buffers; mesh vertex buffers are immutable bound imported resources, not reread here"}
