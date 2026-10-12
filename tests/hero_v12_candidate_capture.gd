extends SceneTree
## Isolated GLB review. No game scene or facade. Atlas override is explicit QA.
## Run from a dedicated minimal QA project, never the player's project identity.

var _args: Dictionary = {}
var _stage: Node3D
var _model: Node3D
var _camera: Camera3D
var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _mesh: MeshInstance3D
var _output: String
var _contact_markers: Array[MeshInstance3D] = []


func _initialize() -> void:
	for value: String in OS.get_cmdline_user_args():
		var pieces := value.trim_prefix("--").split("=", true, 1)
		if pieces.size() == 2:
			_args[pieces[0]] = pieces[1]
	call_deferred("_run")


func _run() -> void:
	var source := String(_args.get("glb", ""))
	_output = String(_args.get("out", ""))
	var fps := int(_args.get("fps", "60"))
	var seconds := float(_args.get("seconds", "0.8"))
	var view := String(_args.get("view", "threequarter"))
	var lighting := String(_args.get("lighting", "legacy"))
	var normal_strength := String(_args.get("normal-strength", "1"))
	var verify_only := String(_args.get("verify-only", "false")) == "true"
	if not source.is_absolute_path() or not FileAccess.file_exists(source) \
			or not _output.is_absolute_path() or "/qa_shots/hero/" not in _output \
			or fps not in [30, 60] or seconds <= 0.0 or seconds > 3.0 \
			or view not in ["front", "threequarter", "side", "chase"] \
			or lighting not in ["legacy", "soft-review", "balanced-review"] \
			or normal_strength not in ["0", "0.35", "1"]:
		_fail("Use absolute glb/out paths (out below qa_shots/hero), fps=30|60, seconds=0..3, valid view")
		return
	if normal_strength != "1" and String(_args.get("atlas-res", "")).is_empty():
		_fail("Normal-strength diagnostics require explicit atlas shader mode")
		return
	if not String(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("waddle-v12-candidate-"):
		_fail("Run only from a minimal isolated waddle-v12-candidate-* project identity")
		return
	if DirAccess.dir_exists_absolute(_output) and not DirAccess.get_files_at(_output).is_empty():
		_fail("Output contains earlier evidence; choose another capture directory")
		return
	if DirAccess.make_dir_recursive_absolute(_output) != OK:
		_fail("Could not create capture output")
		return
	root.size = Vector2i(768, 960)
	root.content_scale_size = Vector2i(768, 960)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	_stage = Node3D.new()
	root.add_child(_stage)
	var imported_res := String(_args.get("imported-res", ""))
	if not imported_res.is_empty():
		if not imported_res.begins_with("res://") or FileAccess.get_sha256(imported_res) != FileAccess.get_sha256(source):
			_fail("Imported QA resource must be a byte-identical copy of source GLB")
			return
		var packed := load(imported_res) as PackedScene
		if packed != null:
			_model = packed.instantiate() as Node3D
	else:
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		if document.append_from_file(source, state) != OK:
			_fail("Direct GLB import failed")
			return
		_model = document.generate_scene(state) as Node3D
	if _model == null:
		_fail("Direct GLB scene generation failed")
		return
	_stage.add_child(_model)
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	var skeletons := _model.find_children("*", "Skeleton3D", true, false)
	var meshes := _model.find_children("*", "MeshInstance3D", true, false)
	if players.size() != 1 or skeletons.size() != 1 or meshes.size() != 1:
		_fail("Candidate must have one animation player, skeleton and mesh")
		return
	_player = players[0] as AnimationPlayer
	_skeleton = skeletons[0] as Skeleton3D
	_mesh = meshes[0] as MeshInstance3D
	if not _player.has_animation(&"run") or _mesh.skin == null:
		_fail("Candidate missing actual run animation or skin")
		return
	var species := String(_args.get("species", "emperor"))
	for index: int in _mesh.mesh.get_blend_shape_count():
		_mesh.set_blend_shape_value(index, 1.0 if String(_mesh.mesh.get_blend_shape_name(index)) == "species_" + species else 0.0)
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_player.play(&"run", 0.0)
	_player.advance(0.0)
	var report := _motion_report()
	report["source_glb"] = source
	report["source_sha256"] = FileAccess.get_sha256(source)
	var source_binding := source.get_base_dir().path_join("atlas_binding.json")
	if FileAccess.file_exists(source_binding):
		var parsed_binding: Variant = JSON.parse_string(FileAccess.get_file_as_string(source_binding))
		if not parsed_binding is Dictionary or String(parsed_binding.get("glb_sha256", "")) != String(report["source_sha256"]) \
				or not parsed_binding.get("projection_gate") is Dictionary:
			_fail("Atlas binding must match GLB and explicitly report projection gate")
			return
		report["projection_gate"] = parsed_binding["projection_gate"]
		if not bool(report["projection_gate"].get("passed", false)):
			print("V12 REJECTED PROJECTION DIAGNOSTIC: captures retained, overall result will FAIL")
	report["material_override"] = false
	report["import_path"] = "PackedScene" if not imported_res.is_empty() else "GLTFDocument"
	report["facade_used"] = false
	report["species"] = species
	report["view"] = view
	report["fps"] = fps
	report["engine"] = Engine.get_version_info()
	report["display_server"] = DisplayServer.get_name()
	report["renderer_setting"] = ProjectSettings.get_setting("rendering/renderer/rendering_method", "")
	report["renderer"] = RenderingServer.get_current_rendering_method()
	report["stage_lighting"] = "neutral front-left key with nonshadowing front-right fill; orthographic review, not gameplay lighting"
	report["lighting_profile"] = lighting
	if lighting == "soft-review":
		report["stage_lighting"] = "QA soft-review: ACES exposure0.75, ambient0.60, key0.65, fill0.40; shadowed key; unchanged atlas maps. Normal strength recorded separately. Not full gameplay lighting."
	elif lighting == "balanced-review":
		report["stage_lighting"] = "QA balanced-review: linear tonemap exposure1, ambient0.35, key0.28, fill0.12; shadowed key. Not full gameplay lighting."
	report["contact_markers"] = String(_args.get("contact-markers", "false")) == "true"
	var material_audit: Array[Dictionary] = []
	for surface: int in _mesh.mesh.get_surface_count():
		var material := _mesh.mesh.surface_get_material(surface) as BaseMaterial3D
		var arrays := _mesh.mesh.surface_get_arrays(surface)
		var colors := PackedColorArray()
		if arrays[Mesh.ARRAY_COLOR] is PackedColorArray:
			colors = arrays[Mesh.ARRAY_COLOR]
		var imported_vertex_color := material.vertex_color_use_as_albedo if material else false
		var repair := String(_args.get("repair-vertex-color", "false")) == "true"
		if material != null and repair and not colors.is_empty():
			material.vertex_color_use_as_albedo = true
		material_audit.append({"surface": surface, "material": material.resource_name if material else "missing",
				"imported_vertex_color_use_as_albedo": imported_vertex_color,
				"vertex_color_use_as_albedo": material.vertex_color_use_as_albedo if material else false,
				"explicit_vertex_color_flag_repair": repair and not imported_vertex_color,
				"albedo_color": str(material.albedo_color) if material else "missing",
				"vertex_color_is_srgb": material.vertex_color_is_srgb if material else false,
				"first_vertex_color": str(colors[0]) if not colors.is_empty() else "missing"})
	report["materials"] = material_audit
	var atlas_res := String(_args.get("atlas-res", ""))
	if not atlas_res.is_empty():
		if not _apply_atlas_review(atlas_res, report):
			return
	report["transform_alignment"] = {"model": str(_model.global_transform),
			"skeleton": str(_skeleton.global_transform), "mesh": str(_mesh.global_transform),
			"mesh_skeleton_path": str(_mesh.skeleton), "resolved_skeleton": str(_mesh.get_node_or_null(_mesh.skeleton)),
			"expected_skeleton": str(_skeleton), "contact_coordinate_space": "world"}
	print("V12 CANDIDATE MATERIALS: " + JSON.stringify(material_audit))
	if verify_only:
		_write_report(report)
		quit(0 if _review_passes(report) else 1)
		return
	if DisplayServer.get_name() == "headless":
		_fail("Visual capture requires a real Compatibility viewport")
		return
	_build_stage(view)
	for _warmup: int in 6:
		await process_frame
	var frame_count := roundi(seconds * fps)
	var samples: Array[Dictionary] = []
	for frame: int in frame_count:
		var clip_time := fmod(float(frame) / fps, _player.current_animation_length)
		_player.seek(clip_time, true)
		var contact := _sole_points()
		for marker: int in _contact_markers.size():
			_contact_markers[marker].global_position = contact[marker]
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var filename := "frame_%04d.png" % frame
		if image == null or image.is_empty() or image.save_png(_output.path_join(filename)) != OK:
			_fail("Could not capture a rendered frame")
			return
		samples.append({"frame": frame, "clip_time": clip_time, "file": filename,
				"cpu_left_sole_world": str(contact[0]), "cpu_right_sole_world": str(contact[1])})
	report["rendered_frames"] = samples
	_write_report(report)
	print("V12 CANDIDATE CAPTURE: %s" % _output)
	quit(0 if _review_passes(report) else 1)


func _apply_atlas_review(atlas_res: String, report: Dictionary) -> bool:
	# Normal resource imports only. Never silently decode external textures or
	# assign unique-atlas images to the legacy repeating-UV candidate.
	var shader_res := String(_args.get("atlas-shader-res", "res://hero_v12_atlas_review.gdshader"))
	if not atlas_res.begins_with("res://") or not shader_res.begins_with("res://"):
		_fail("Atlas review requires normal imported res:// textures and shader")
		return false
	if String(_args.get("repair-vertex-color", "false")) == "true":
		_fail("Atlas review must not enable the old vertex-color repair")
		return false
	var binding_path := atlas_res.path_join("atlas_binding.json")
	if not FileAccess.file_exists(binding_path):
		_fail("Atlas binding missing; cannot prove textures belong to candidate UVs")
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(binding_path))
	if not parsed is Dictionary:
		_fail("Atlas binding must be a JSON object")
		return false
	var binding: Dictionary = parsed
	if int(binding.get("schema_version", 0)) != 1 \
			or String(binding.get("uv_contract", "")) != "unique-nonoverlapping-v1" \
			or String(binding.get("glb_sha256", "")) != String(report["source_sha256"]) \
			or not binding.get("textures") is Dictionary \
			or binding.get("projection_gate") != report.get("projection_gate"):
		_fail("Atlas binding does not match the exact unique-UV candidate GLB")
		return false
	var shader := load(shader_res) as Shader
	if shader == null:
		_fail("Atlas review shader missing")
		return false
	var material := ShaderMaterial.new()
	material.shader = shader
	var normal_strength := float(String(_args.get("normal-strength", "1")))
	material.set_shader_parameter(&"normal_strength", normal_strength)
	var texture_audit: Array[Dictionary] = []
	var texture_payload_bytes := 0
	for kind: String in ["albedo", "normal", "orm", "masks"]:
		var path := atlas_res.path_join("hero_penguin_v12_atlas_%s.png" % kind)
		if not FileAccess.file_exists(path) \
				or FileAccess.get_sha256(path) != String(binding["textures"].get(kind, "")):
			_fail("Atlas texture hash does not match binding: " + path)
			return false
		var texture := load(path) as Texture2D
		if texture == null or texture.get_width() != texture.get_height() \
				or texture.get_width() not in [512, 1024, 2048]:
			_fail("Missing or invalid normally imported atlas: " + path)
			return false
		material.set_shader_parameter("atlas_" + kind, texture)
		var stored_image := texture.get_image()
		if stored_image == null or stored_image.is_empty():
			_fail("Imported atlas has no inspectable stored image: " + path)
			return false
		var payload_bytes := stored_image.get_data().size()
		texture_payload_bytes += payload_bytes
		texture_audit.append({"kind": kind, "resource": path,
				"sha256": FileAccess.get_sha256(path), "size": texture.get_width(),
				"stored_format": stored_image.get_format(), "compressed": stored_image.is_compressed(),
				"mipmap_count": stored_image.get_mipmap_count(), "stored_payload_bytes": payload_bytes,
				"encoding": "sRGB" if kind == "albedo" else "linear data"})
	for surface: int in _mesh.mesh.get_surface_count():
		_mesh.set_surface_override_material(surface, material)
	report["material_override"] = true
	report["atlas_review"] = {"shader": shader_res,
			"shader_sha256": FileAccess.get_sha256(shader_res), "textures": texture_audit,
			"binding_sha256": FileAccess.get_sha256(binding_path),
			"four_map_stored_payload_bytes": texture_payload_bytes,
			"memory_note": "Stored texture data including mips; not total driver VRAM or a runner budget pass. Original imported PBR resources also remain loaded in this comparison harness.",
			"palette": "source M linear pigment, unchanged", "live_material_changed": false,
			"specular": {"feather": 0.40, "hard": 0.50},
			"normal_strength": normal_strength, "vertex_color_used": false,
			"normal_strength_note": "Diagnostic scales the complete baked tangent normal, including geometry correction; a source-feather-only rebake is needed for final tuning."}
	return true


func _build_stage(view: String) -> void:
	var soft_review := String(_args.get("lighting", "legacy")) == "soft-review"
	var balanced_review := String(_args.get("lighting", "legacy")) == "balanced-review"
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("566471")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c1d0db")
	settings.ambient_light_energy = 0.60 if soft_review else 0.55
	if balanced_review:
		settings.ambient_light_energy = 0.35
	settings.ambient_light_sky_contribution = 0.0
	if soft_review:
		settings.tonemap_mode = Environment.TONE_MAPPER_ACES
		settings.tonemap_exposure = 0.75
	environment.environment = settings
	_stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.65 if soft_review else 1.25
	if balanced_review:
		sun.light_energy = 0.28
	sun.light_color = Color("fff3df")
	sun.shadow_enabled = true
	_stage.add_child(sun)
	sun.look_at_from_position(Vector3(-3.0, 5.0, -4.0), Vector3(0.0, 0.8, 0.0))
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.40 if soft_review else 0.35
	if balanced_review:
		fill.light_energy = 0.12
	fill.light_color = Color("d1e7ff")
	fill.shadow_enabled = false
	_stage.add_child(fill)
	fill.look_at_from_position(Vector3(4.0, 2.0, -1.0), Vector3(0.0, 0.8, 0.0))
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200.0, 200.0) if soft_review or balanced_review else Vector2(20.0, 20.0)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("6e7b86")
	floor_material.roughness = 0.94
	floor_mesh.material_override = floor_material
	_stage.add_child(floor_mesh)
	if String(_args.get("contact-markers", "false")) == "true":
		var grid := MeshInstance3D.new()
		var lines := ImmediateMesh.new()
		var line_material := StandardMaterial3D.new()
		line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		line_material.albedo_color = Color("4b6474")
		lines.surface_begin(Mesh.PRIMITIVE_LINES, line_material)
		for index: int in range(-10, 11):
			var coordinate := float(index) * 0.1
			lines.surface_add_vertex(Vector3(coordinate, 0.002, -1.0))
			lines.surface_add_vertex(Vector3(coordinate, 0.002, 1.0))
			lines.surface_add_vertex(Vector3(-1.0, 0.002, coordinate))
			lines.surface_add_vertex(Vector3(1.0, 0.002, coordinate))
		lines.surface_end()
		grid.mesh = lines
		grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_stage.add_child(grid)
		for tint: Color in [Color.MAGENTA, Color.CYAN]:
			var marker := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.012
			sphere.height = 0.024
			marker.mesh = sphere
			var material := StandardMaterial3D.new()
			material.albedo_color = tint
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			marker.material_override = material
			marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_stage.add_child(marker)
			_contact_markers.append(marker)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.05
	_camera.far = 50.0
	_camera.size = 2.65
	_camera.current = true
	_stage.add_child(_camera)
	var position := Vector3(3.2, 1.55, -4.2)
	match view:
		"front": position = Vector3(0.0, 1.08, -5.0)
		"side": position = Vector3(5.0, 1.15, -0.04)
		"chase": position = Vector3(0.0, 1.15, 5.0)
	_camera.look_at_from_position(position, Vector3(0.0, 0.94, 0.0), Vector3.UP)


func _motion_report() -> Dictionary:
	var rates: Dictionary = {}
	var original := _model.transform
	var fixed := true
	for fps: int in [30, 60]:
		var samples: Array[Dictionary] = []
		for frame: int in ceili(_player.current_animation_length * fps):
			_player.seek(float(frame) / fps, true)
			var heights := _sole_heights()
			for bone: int in _skeleton.get_bone_count():
				var name := String(_skeleton.get_bone_name(bone))
				if name == "root" or name.begins_with("foot") or name.begins_with("toe"):
					fixed = fixed and _skeleton.get_bone_pose(bone).is_equal_approx(_skeleton.get_bone_rest(bone))
			samples.append({"left_sole_m": heights.x, "right_sole_m": heights.y})
		var minimum := INF
		var support_max := -INF
		for row: Dictionary in samples:
			minimum = minf(minimum, minf(row["left_sole_m"], row["right_sole_m"]))
			support_max = maxf(support_max, minf(row["left_sole_m"], row["right_sole_m"]))
		rates[str(fps)] = {"samples": samples, "minimum_sole_m": minimum, "maximum_support_sole_m": support_max}
	var parity := 0.0
	for index: int in rates["30"]["samples"].size():
		for side: String in ["left_sole_m", "right_sole_m"]:
			parity = maxf(parity, absf(rates["30"]["samples"][index][side] - rates["60"]["samples"][index * 2][side]))
	var triangles := 0
	for surface: int in _mesh.mesh.get_surface_count():
		var arrays := _mesh.mesh.surface_get_arrays(surface)
		triangles += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	var contact_fit := true
	for data: Dictionary in rates.values():
		contact_fit = contact_fit and is_finite(data["minimum_sole_m"]) \
				and data["minimum_sole_m"] >= 0.0 and data["maximum_support_sole_m"] <= 0.012
	var structure: bool = _skeleton.get_bone_count() == 15 and _mesh.mesh.get_surface_count() in [1, 2] \
			and _mesh.mesh.get_blend_shape_count() == 8 and fixed \
			and original.is_equal_approx(_model.transform) and parity < 0.00001 \
			and _player.get_animation_list().size() == 23
	return {"structural_pass": structure, "bones": _skeleton.get_bone_count(),
			"constant_sole_fit_pass": contact_fit,
			"contact_scope": "emperor basis shape only; other species morph deformation requires separate review",
			"triangles": triangles, "surfaces": _mesh.mesh.get_surface_count(),
			"species_shapes": _mesh.mesh.get_blend_shape_count(), "clips": _player.get_animation_list(),
			"attached_feet_and_root_fixed": fixed, "shared_time_30_60_error_m": parity,
			"motion": rates, "production_ready": false}


func _sole_heights() -> Vector2:
	var points := _sole_points()
	return Vector2(points[0].y, points[1].y)


func _sole_points() -> Array[Vector3]:
	var transforms: Array[Transform3D] = []
	var foot_binds: Array[bool] = []
	for bind: int in _mesh.skin.get_bind_count():
		var bone := _mesh.skin.get_bind_bone(bind)
		if bone < 0:
			bone = _skeleton.find_bone(_mesh.skin.get_bind_name(bind))
		var name := String(_skeleton.get_bone_name(bone))
		foot_binds.append(name.begins_with("foot") or name.begins_with("toe"))
		transforms.append(_skeleton.get_bone_global_pose(bone) * _mesh.skin.get_bind_pose(bind))
	var result: Array[Vector3] = [Vector3(0.0, INF, 0.0), Vector3(0.0, INF, 0.0)]
	for surface: int in _mesh.mesh.get_surface_count():
		var arrays := _mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for index: int in vertices.size():
			var foot_weight := 0.0
			for influence: int in 4:
				var offset := index * 4 + influence
				if foot_binds[bones[offset]]:
					foot_weight += weights[offset]
			if foot_weight < 0.98:
				continue
			var point := Vector3.ZERO
			for influence: int in 4:
				var offset := index * 4 + influence
				point += (transforms[bones[offset]] * vertices[index]) * weights[offset]
			point = _skeleton.global_transform * point
			var side := 0 if vertices[index].x < 0.0 else 1
			if point.y < result[side].y:
				result[side] = point
	return result


func _write_report(report: Dictionary) -> void:
	report["overall_gate_pass"] = _review_passes(report)
	var file := FileAccess.open(_output.path_join("capture_audit.json"), FileAccess.WRITE)
	if file == null:
		_fail("Could not write capture audit")
		return
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	print("V12 CANDIDATE DIRECT-GLB: structural_pass=%s" % report["structural_pass"])


func _review_passes(report: Dictionary) -> bool:
	return bool(report["structural_pass"]) and bool(report["constant_sole_fit_pass"]) \
			and (not report.has("projection_gate") or bool(report["projection_gate"].get("passed", false)))


func _fail(message: String) -> void:
	push_error(message)
	quit(2)
