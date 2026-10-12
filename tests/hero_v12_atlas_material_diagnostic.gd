extends "res://tests/hero_penguin_capture.gd"
## QA-only three-frame material isolation, plus an optional receiver-shadow frame.
## Reuses the actual facade, camera,
## stage and idle-to-run transition; no animation/light/geometry substitutions.

const BINDING := "res://qa_hero/material_diagnostic_binding.json"
const NORMAL_ANCHOR := "NORMAL_MAP_DEPTH = normal_strength;"
const NORMAL_DIAGNOSTIC := "NORMAL_MAP_DEPTH = normal_strength * feather;"
const RENDER_ANCHOR := "render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;"
const RENDER_DIAGNOSTIC := "render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx, shadows_disabled;"
var _diagnostic_meshes: Array[MeshInstance3D] = []
var _diagnostic_materials: Array[ShaderMaterial] = []
var _diagnostic_output := ""


func _ready() -> void:
	if DisplayServer.get_name() == "headless" and "parsercheck=true" in OS.get_cmdline_user_args():
		var identity := String(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
		if not identity.begins_with("waddle-v12-atlas-runner-review-"):
			_abort("Parser check requires the isolated atlas review project")
			return
		print("V12 MATERIAL DIAGNOSTIC PARSER: PASS (no raster/material test)")
		get_tree().quit(0)
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("output="):
			_diagnostic_output = arg.trim_prefix("output=")
	var binding: Variant = JSON.parse_string(FileAccess.get_file_as_string(BINDING))
	if DisplayServer.get_name() == "headless" or not binding is Dictionary \
			or binding.get("route") != "frozen-atlas-material-three-frame-v1" \
			or _diagnostic_output != binding.get("capture_output") \
			or FileAccess.get_sha256(get_script().resource_path) != binding.get("scene_script_sha256"):
		_abort("Diagnostic requires its bound isolated windowed fixture")
		return
	var study: Variant = binding.get("receiver_shadow_study", false)
	var key_study: Variant = binding.get("key_energy_study", false)
	var labels := ["baseline", "hard_normal_zero", "hard_specular_zero"]
	if not study is bool or not key_study is bool:
		_abort("Optional study flags must be boolean")
		return
	if study:
		labels.append("receiver_shadows_disabled")
	if key_study:
		labels.append_array(["half_key_shadows_received", "half_key_receiver_shadows_disabled"])
		if binding.get("key_energy_values") != {"before": 0.54, "after": 0.27}:
			_abort("Key-energy study requires the bound .54 to .27 recipe")
			return
	if binding.get("variants") != labels:
		_abort("Only the default frames and explicitly bound optional studies are allowed")
		return
	if DirAccess.dir_exists_absolute(_diagnostic_output):
		_abort("Keep previous diagnostic evidence; choose a fresh output")
		return
	if DirAccess.make_dir_recursive_absolute(_diagnostic_output) != OK:
		_abort("Could not create diagnostic output")
		return
	_motion_name = "run"
	_capture_fps = 30
	_view_name = "front"
	_orientation_name = "landscape"
	get_window().size = Vector2i(1280, 720)
	get_window().always_on_top = true
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_set_title("Waddle Wars — frozen Y03 material diagnostic (QA only)")
	_build_stage()
	_configure_camera()
	if not _prepare_motion_clock():
		_abort("Could not prepare actual facade motion clock")
		return
	# Original front_30/frame_0024: initial frame0, then24 actual30Hz steps.
	for _frame: int in 24:
		_step_motion(1.0 / 30.0)
	for _settle: int in 3:
		await get_tree().process_frame
	var material_report: Dictionary = _hero.call("qa_material_report")
	if material_report.get("passed") != true or material_report.get("material_mode") != "atlas" \
			or material_report.get("shader_sha256") != binding.get("baseline_shader_sha256") \
			or material_report.get("candidate_sha256") != binding.get("candidate_sha256"):
		_abort("Actual atlas controller/material binding rejected")
		return
	for child: Node in _hero.find_children("*", "MeshInstance3D", true, false):
		_diagnostic_meshes.append(child as MeshInstance3D)
	if _diagnostic_meshes.size() != 1 or _diagnostic_meshes[0].mesh.get_surface_count() != 2:
		_abort("Expected one actual two-surface hero")
		return
	var baseline := _diagnostic_meshes[0].get_surface_override_material(0) as ShaderMaterial
	if baseline == null or baseline.shader.code.sha256_text() != binding.get("baseline_shader_sha256") \
			or baseline.shader.code.count(NORMAL_ANCHOR) != 1 \
			or _diagnostic_meshes[0].get_surface_override_material(1) != baseline:
		_abort("Baseline must be the actual shared atlas shader/material")
		return
	var normal_off := baseline.duplicate(false) as ShaderMaterial
	var normal_shader := Shader.new()
	normal_shader.code = baseline.shader.code.replace(NORMAL_ANCHOR, NORMAL_DIAGNOSTIC)
	normal_off.shader = normal_shader
	if normal_shader.code.sha256_text() != binding.get("hard_normal_zero_shader_sha256"):
		_abort("Hard-normal shader differs beyond its one allowed expression")
		return
	var specular_off := baseline.duplicate(false) as ShaderMaterial
	specular_off.set_shader_parameter("hard_specular", 0.0)
	_diagnostic_materials.assign([baseline, normal_off, specular_off])
	var receiver_off: ShaderMaterial = null
	var receiver_shader: Shader = null
	if study or key_study:
		if baseline.shader.code.count(RENDER_ANCHOR) != 1 or baseline.shader.code.count("render_mode ") != 1:
			_abort("Receiver-shadow study requires the exact baseline render-mode declaration")
			return
		receiver_off = baseline.duplicate(false) as ShaderMaterial
		receiver_shader = Shader.new()
		receiver_shader.code = baseline.shader.code.replace(RENDER_ANCHOR, RENDER_DIAGNOSTIC)
		receiver_off.shader = receiver_shader
		if receiver_shader.code.sha256_text() != binding.get("receiver_shadows_disabled_shader_sha256"):
			_abort("Receiver-shadow shader differs beyond its one allowed render mode")
			return
		# Do not alter light.shadow_enabled or the mesh casting mode. This only
		# disables shadow reception; the hero remains a ground-shadow caster.
		if study:
			_diagnostic_materials.append(receiver_off)
	if key_study:
		_diagnostic_materials.append(baseline)
		_diagnostic_materials.append(receiver_off)
	var before := _snapshot()
	var original_material_state := _material_state(baseline)
	var key: DirectionalLight3D = null
	var original_key_energy: float = 0.0
	var half_key_state: Dictionary = {}
	var key_energy_change: Dictionary = {}
	if key_study:
		for child: Node in get_children():
			if child is DirectionalLight3D and child.shadow_enabled:
				if key != null:
					_abort("Expected one original shadow-casting directional key")
					return
				key = child as DirectionalLight3D
		if key == null or not is_equal_approx(key.light_energy, 0.54):
			_abort("Half-key study requires the unmodified original .54 key")
			return
		original_key_energy = key.light_energy
		key.light_energy = 0.27
		half_key_state = _snapshot()
		key_energy_change = {"light_path": String(key.get_path()), "before": original_key_energy,
			"after": key.light_energy, "scope": "Only key light_energy; shadow reception remains a separate shader control"}
		key.light_energy = original_key_energy
		if _snapshot() != before:
			_abort("Key energy did not restore exactly before original control frames")
			return
	var frames: Array[Dictionary] = []
	for index: int in labels.size():
		var is_half_key: bool = String(labels[index]).begins_with("half_key_")
		if key_study:
			key.light_energy = 0.27 if is_half_key else original_key_energy
		var expected: Dictionary = half_key_state if is_half_key else before
		var material := _diagnostic_materials[index]
		for surface: int in 2:
			_diagnostic_meshes[0].set_surface_override_material(surface, material)
		for _wait: int in 2:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var current := _snapshot()
		if current != expected:
			_abort("Geometry/camera/light/environment/pose changed between diagnostic frames")
			return
		var filename: String = "%02d_%s.png" % [index, labels[index]]
		var shot := get_viewport().get_texture().get_image()
		if shot == null or shot.is_empty() or shot.get_size() != Vector2i(1280, 720) \
				or shot.save_png(_diagnostic_output.path_join(filename)) != OK:
			_abort("Expected visible full-resolution raster frame was not saved")
			return
		shot = null
		frames.append({"variant": labels[index], "file": filename,
			"png_sha256": FileAccess.get_sha256(_diagnostic_output.path_join(filename)),
			"state": current, "material": _material_state(material)})
	for surface: int in 2:
		_diagnostic_meshes[0].set_surface_override_material(surface, baseline)
	if key_study:
		key.light_energy = original_key_energy
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var restored := _snapshot()
	var final_material: Dictionary = _hero.call("qa_material_report")
	var passed: bool = restored == before and _material_state(baseline) == original_material_state \
		and final_material.get("passed") == true
	var report := {"schema_version": 1, "route": binding.route, "passed": passed,
		"production_ready": false, "source_fidelity_approved": false, "performance_measured": false,
		"renderer": RenderingServer.get_current_rendering_method(), "engine": Engine.get_version_info(),
		"binding_sha256": FileAccess.get_sha256(BINDING), "candidate_sha256": binding.candidate_sha256,
		"source_material_report": material_report, "final_material_report": final_material,
		"frozen_pose": {"motion": "run", "fps": 30, "frame": 24, "fixed_steps_after_frame_zero": 24,
			"automatic_animation_processing": false, "controller_snapshot": _hero.call("qa_motion_snapshot")},
		"state_hash_encoding": "Godot var_to_bytes; exact bytes retained as hex, human-readable state also retained",
		"state_before": before, "frames": frames, "state_after_restore": restored,
		"half_key_state": half_key_state, "key_energy_change": key_energy_change,
		"geometry_lighting_camera_pose_unchanged": not key_study and restored == before,
		"geometry_camera_pose_unchanged": restored == before,
		"original_material_restored": _material_state(baseline) == original_material_state,
		"scope": "%d untimed real rasters; original controls unchanged, optional half-key pair changes only key energy .54 to .27; receiver shader changes reception, not casting; not art acceptance or a production fix" % labels.size()}
	var file := FileAccess.open(_diagnostic_output.path_join("report.json"), FileAccess.WRITE)
	if file == null:
		_abort("Could not save diagnostic report")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file = null
	print("V12 ", labels.size(), "-FRAME MATERIAL DIAGNOSTIC: ", "PASS" if passed else "FAIL")
	# Release owned variants before quitting; no shader/material cache additions.
	_diagnostic_materials.clear()
	_diagnostic_meshes.clear()
	_motion_players.clear()
	normal_off = null
	normal_shader = null
	specular_off = null
	receiver_off = null
	receiver_shader = null
	key = null
	baseline = null
	_hero = null
	_facade = null
	_camera = null
	for child: Node in get_children():
		child.queue_free()
	for _cleanup: int in 3:
		await get_tree().process_frame
	get_tree().quit(0 if passed else 2)


func _abort(message: String) -> void:
	push_error(message)
	get_tree().quit(2)


func _exact(value: Variant) -> Dictionary:
	var bytes := var_to_bytes(value)
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return {"sha256": hashing.finish().hex_encode(), "state_bytes_hex": bytes.hex_encode(), "state": value}


func _storage(object: Object, depth: int = 0) -> Dictionary:
	var result := {"class": object.get_class()}
	for property: Dictionary in object.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var name := String(property.name)
		var value: Variant = object.get(name)
		if value is Resource:
			if depth >= 4:
				result[name] = {"resource_path": value.resource_path, "id": value.get_instance_id()}
			else:
				result[name] = _storage(value, depth + 1)
		elif value is Object:
			result[name] = {"class": value.get_class(), "id": value.get_instance_id()}
		else:
			result[name] = value
	return result


func _snapshot() -> Dictionary:
	var geometry: Array = []
	var pose: Array = []
	for mesh: MeshInstance3D in _diagnostic_meshes:
		var data: Array = []
		for surface: int in mesh.mesh.get_surface_count():
			data.append([mesh.mesh.surface_get_arrays(surface), mesh.mesh.surface_get_blend_shape_arrays(surface)])
		var skin: Array = []
		for bind: int in mesh.skin.get_bind_count():
			skin.append([mesh.skin.get_bind_name(bind), mesh.skin.get_bind_bone(bind), mesh.skin.get_bind_pose(bind)])
		geometry.append([mesh.get_path(), mesh.mesh.get_instance_id(), data, skin,
			{"cast_shadow": mesh.cast_shadow, "layers": mesh.layers}])
		var shapes: Array = []
		for shape: int in mesh.mesh.get_blend_shape_count():
			shapes.append([mesh.mesh.get_blend_shape_name(shape), mesh.get_blend_shape_value(shape)])
		pose.append([mesh.get_path(), mesh.global_transform, shapes])
	for node: Node in _facade.find_children("*", "Node3D", true, false):
		pose.append([node.get_path(), (node as Node3D).transform, (node as Node3D).global_transform])
	for node: Node in _hero.find_children("*", "Skeleton3D", true, false):
		var skeleton := node as Skeleton3D
		for bone: int in skeleton.get_bone_count():
			pose.append([skeleton.get_bone_name(bone), skeleton.get_bone_parent(bone),
				skeleton.get_bone_rest(bone), skeleton.get_bone_pose(bone), skeleton.get_bone_global_pose(bone)])
	for player: AnimationPlayer in _motion_players:
		pose.append([player.current_animation, player.current_animation_position, player.speed_scale, player.callback_mode_process])
	var lights: Array = []
	for child: Node in get_children():
		if child is Light3D:
			lights.append([child.get_path(), child.global_transform, _storage(child)])
		elif child is WorldEnvironment:
			lights.append([child.get_path(), _storage(child.environment)])
	var geometry_bytes := var_to_bytes(geometry)
	var geometry_hash := HashingContext.new()
	geometry_hash.start(HashingContext.HASH_SHA256)
	geometry_hash.update(geometry_bytes)
	return {"geometry_sha256": geometry_hash.finish().hex_encode(),
		"geometry_scope": "Original mesh buffers, index/normal/tangent/UV/skin/weight data and all morph buffers, mesh casting mode and layers; no material object IDs",
		"pose": _exact(pose), "lighting_environment": _exact(lights),
		"camera": _exact({"global_transform": _camera.global_transform, "properties": _storage(_camera),
			"viewport_size": get_viewport().get_visible_rect().size})}


func _material_state(material: ShaderMaterial) -> Dictionary:
	var uniforms: Dictionary = {}
	for uniform: Dictionary in material.shader.get_shader_uniform_list():
		var name := String(uniform.name)
		var value: Variant = material.get_shader_parameter(name)
		if value is Texture2D:
			uniforms[name] = {"instance_id": value.get_instance_id(), "resource_path": value.resource_path,
				"file_sha256": FileAccess.get_sha256(value.resource_path)}
		else:
			uniforms[name] = value
	return {"shader_sha256": material.shader.code.sha256_text(), "uniforms": _exact(uniforms)}
