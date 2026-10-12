extends SceneTree
## Resource-only imported motion verification. No runner, camera or rendered capture.
var failures := 0
var passes := 0
var _source_expectations: Dictionary = {}
var _source_vertex_matches: Array[PackedInt32Array] = []
var _parity: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var review := load("res://_qa_local/motion_candidate_browser.gd")
	var helper: Node = review.new()
	var binding: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://qa_motion/candidate_binding.json"))
	helper.set("_binding", binding)
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1 or not FileAccess.file_exists(arguments[0]):
		check(false, "pass absolute source-pose-expectations.json after --")
		helper.free()
		quit(1)
		return
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(arguments[0]))
	if not expected is Dictionary or expected.get("candidate_sha256") != binding.glb_sha256:
		check(false, "independent source-pose receipt must bind actual candidate SHA")
		helper.free()
		quit(1)
		return
	_source_expectations = expected

	var packed := ResourceLoader.load("res://qa_motion/candidate.glb", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	check(packed != null, "persisted candidate imports as PackedScene")
	if packed == null:
		helper.free()
		quit(1)
		return
	var model := packed.instantiate() as Node3D
	root.add_child(model)
	var skeletons: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
	var players: Array[Node] = model.find_children("*", "AnimationPlayer", true, false)
	var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
	check(skeletons.size() == 1 and players.size() == 1 and meshes.size() == 1, "one real skeleton, AnimationPlayer and skinned mesh")
	if skeletons.size() != 1 or players.size() != 1 or meshes.size() != 1:
		model.free()
		helper.free()
		quit(1)
		return
	var skeleton := skeletons[0] as Skeleton3D
	var animation := players[0] as AnimationPlayer
	var instance := meshes[0] as MeshInstance3D
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	helper.set("_model", model)
	helper.set("_skeleton", skeleton)
	helper.set("_animation", animation)
	var rig: Dictionary = helper.call("_rig_resources")
	check(rig.errors.is_empty(), "actual imported bones and clips match binding: " + str(rig.errors))
	check(instance.skin != null and instance.mesh.get_surface_count() == 1, "imported skin and single surface retained")
	var material := instance.get_active_material(0) as StandardMaterial3D
	check(material != null and instance.material_override == null and instance.material_overlay == null \
		and instance.get_surface_override_material(0) == null, "actual imported PBR without substitute")
	check(helper.call("_surface_material_error", material) == "", "imported PBR settings preserved")
	var expected_specular: float = binding.materials[0].get("specular", 0.5)
	check(is_equal_approx(material.metallic_specular, expected_specular)
		and material.get_meta("motion_surface_revision", "") == binding.get("material_revision", {}).get("id", ""),
		"persisted source-authored specular and revision match binding")
	material.metallic_specular = expected_specular + 0.1
	check(helper.call("_surface_material_error", material) != "", "unbound specular change rejected")
	material.metallic_specular = expected_specular
	var maps: Dictionary = helper.call("_surface_map_receipts", material)
	check(maps.errors.is_empty(), "three imported base maps and mipmaps match source: " + str(maps.errors))
	for slot: int in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ROUGHNESS]:
		var texture := material.get_texture(slot) as PortableCompressedTexture2D
		var exact := texture != null
		if exact:
			var persisted := texture.get_image()
			var regenerated: Image = persisted.duplicate()
			regenerated.clear_mipmaps()
			exact = texture.get_compression_mode() == PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS \
				and regenerated.generate_mipmaps(slot == BaseMaterial3D.TEXTURE_NORMAL) == OK \
				and regenerated.get_format() == persisted.get_format() \
				and regenerated.get_mipmap_count() == persisted.get_mipmap_count() \
				and regenerated.get_data() == persisted.get_data()
		check(exact, "persisted lossless map and every mip identical, slot " + str(slot))
	var arrays: Array = instance.mesh.surface_get_arrays(0)
	var rest: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	check(arrays[Mesh.ARRAY_BONES] is PackedInt32Array and arrays[Mesh.ARRAY_WEIGHTS] is PackedFloat32Array \
		and arrays[Mesh.ARRAY_BONES].size() == rest.size() * 4 and arrays[Mesh.ARRAY_WEIGHTS].size() == rest.size() * 4,
		"four actual skin influences for every imported vertex")
	_source_vertex_matches = match_source_vertices(arrays)
	check(_source_vertex_matches.size() == _source_expectations.rest_vertices.size(),
		"all source rest vertices matched imported positions/normals/UV independently of order")
	if _source_vertex_matches.size() != _source_expectations.rest_vertices.size():
		model.free()
		helper.free()
		quit(1)
		return
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	var rest_error := max_distance(rest, posed_vertices(instance, skeleton))
	check(rest_error < 0.0001, "actual inverse binds preserve accepted rest mesh, max error " + str(rest_error))
	var poses: Dictionary = {}
	for clip_name: String in ["waddle", "jump", "slide"]:
		var clip := animation.get_animation(clip_name)
		var samples: Array[PackedVector3Array] = []
		var finite := true
		var sample_index := 0
		var parity_samples: Array = []
		for phase: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
			animation.play(clip_name, 0.0)
			animation.advance(0.0)
			animation.seek(phase * clip.length, true)
			skeleton.force_update_all_bone_transforms()
			var points := posed_vertices(instance, skeleton)
			for point: Vector3 in points:
				finite = finite and point.is_finite()
			samples.append(points)
			var source_sample: Dictionary = _source_expectations.clips[clip_name].samples[sample_index]
			var parity := compare_source_pose(points, source_sample.positions)
			check(absf(float(source_sample.phase) - phase) < 0.000001 				and parity.max_error_m <= float(_source_expectations.pose_tolerance_m),
				"source GLB vs imported skin parity " + clip_name + " phase " + str(phase) + ", error " + str(parity.max_error_m))
			parity["phase"] = phase
			parity_samples.append(parity)
			sample_index += 1
		var moved := 0.0
		for index: int in range(1, samples.size()):
			moved = maxf(moved, max_distance(samples[0], samples[index]))
		check(finite and moved > 0.0001, "actual weighted mesh deforms in " + clip_name + ", max displacement " + str(moved))
		var endpoint_error := max_distance(samples[0], samples[-1])
		if binding.clips[clip_name].loop:
			check(endpoint_error < 0.0001, "loop deformed endpoints continuous: " + clip_name)
		_parity[clip_name] = parity_samples
		poses[clip_name] = {"max_displacement_m": moved, "endpoint_distance_m": endpoint_error,
			"sample_hashes": samples.map(func(points: PackedVector3Array) -> String: return review._hash(points))}
	var after: Dictionary = helper.call("_rig_resources")
	check(after.signature == rig.signature, "animation playback leaves actual rest, binds and clip resources unchanged")
	check(helper.call("_surface_map_receipts", material) == maps, "all sampled clips retain identical material maps")
	print("MOTION_IMPORT_RECEIPT " + JSON.stringify({"candidate_sha256": binding.glb_sha256,
		"passes": passes, "failures": failures, "rig": rig, "maps": maps, "rest_error_m": rest_error,
		"clips": poses, "source_pose_parity": _parity, "source_pose_tolerance_m": _source_expectations.pose_tolerance_m, "scope": "Imported resources and CPU skin evaluation; no animation art or frame acceptance"}))
	model.free()
	helper.free()
	quit(1 if failures else 0)

func posed_vertices(instance: MeshInstance3D, skeleton: Skeleton3D) -> PackedVector3Array:
	var arrays: Array = instance.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var transforms: Array[Transform3D] = []
	for bind: int in instance.skin.get_bind_count():
		var bone: int = instance.skin.get_bind_bone(bind)
		if not instance.skin.get_bind_name(bind).is_empty():
			bone = skeleton.find_bone(instance.skin.get_bind_name(bind))
		transforms.append(instance.global_transform.affine_inverse() * skeleton.global_transform \
			* skeleton.get_bone_global_pose(bone) * instance.skin.get_bind_pose(bind))
	var result := PackedVector3Array()
	for index: int in vertices.size():
		var point := Vector3.ZERO
		for influence: int in 4:
			var weight: float = weights[index * 4 + influence]
			if weight > 0.0:
				point += (transforms[bones[index * 4 + influence]] * vertices[index]) * weight
		result.append(point)
	return result

func max_distance(a: PackedVector3Array, b: PackedVector3Array) -> float:
	if a.size() != b.size():
		return INF
	var result := 0.0
	for index: int in a.size():
		result = maxf(result, a[index].distance_to(b[index]))
	return result

func check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
	else:
		failures += 1
		push_error("[motion_candidate_import] " + label)


func match_source_vertices(arrays: Array) -> Array[PackedInt32Array]:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var epsilon: float = _source_expectations.vertex_match_tolerance_m
	var buckets: Dictionary = {}
	for index: int in vertices.size():
		var cell := Vector3i((vertices[index] / epsilon).floor())
		if not buckets.has(cell):
			buckets[cell] = []
		buckets[cell].append(index)
	var matches: Array[PackedInt32Array] = []
	var used: Dictionary = {}
	var diagnostic := {"source_vertices": _source_expectations.rest_vertices.size(),
		"imported_vertices": vertices.size(), "unmatched": 0, "position_candidates_missing": 0,
		"max_position_error": 0.0, "max_normal_error": 0.0, "max_uv_error": 0.0,
		"failures_first16": [], "limits_unchanged": true}
	for row: Array in _source_expectations.rest_vertices:
		var source_index: int = matches.size()
		var point := Vector3(row[0], row[1], row[2])
		var normal := Vector3(row[3], row[4], row[5])
		var uv := Vector2(row[6], row[7])
		var cell := Vector3i((point / epsilon).floor())
		var found := PackedInt32Array()
		var best: Dictionary = {}
		var best_score := INF
		for x: int in range(-1, 2):
			for y: int in range(-1, 2):
				for z: int in range(-1, 2):
					for index: int in buckets.get(cell + Vector3i(x, y, z), []):
						var position_error := vertices[index].distance_to(point)
						if position_error > epsilon:
							continue
						var normal_error := normals[index].distance_to(normal)
						var uv_error := uvs[index].distance_to(uv)
						var score: float = normal_error / float(_source_expectations.normal_match_tolerance) + uv_error / float(_source_expectations.uv_match_tolerance)
						if score < best_score:
							best_score = score
							best = {"source_index": source_index, "imported_index": index,
								"position_error": position_error, "normal_error": normal_error, "uv_error": uv_error,
								"source_position": var_to_str(point), "imported_position": var_to_str(vertices[index]),
								"source_normal": var_to_str(normal), "imported_normal": var_to_str(normals[index]),
								"source_uv": var_to_str(uv), "imported_uv": var_to_str(uvs[index])}
						if normal_error <= float(_source_expectations.normal_match_tolerance) and uv_error <= float(_source_expectations.uv_match_tolerance):
							found.append(index)
							used[index] = true
		if best.is_empty():
			diagnostic.position_candidates_missing += 1
			var nearest := INF
			for index: int in vertices.size():
				var distance := vertices[index].distance_to(point)
				if distance < nearest:
					nearest = distance
					best = {"source_index": source_index, "imported_index": index,
						"position_error": distance, "normal_error": normals[index].distance_to(normal),
						"uv_error": uvs[index].distance_to(uv), "source_position": var_to_str(point),
						"imported_position": var_to_str(vertices[index])}
		for field: String in ["position_error", "normal_error", "uv_error"]:
			if float(best[field]) > float(diagnostic["max_" + field]):
				diagnostic["max_" + field] = best[field]
				diagnostic["worst_" + field] = best.duplicate()
		if found.is_empty():
			diagnostic.unmatched += 1
			if diagnostic.failures_first16.size() < 16:
				diagnostic.failures_first16.append(best)
		matches.append(found)
	diagnostic["covered_imported_vertices"] = used.size()
	print("MOTION_VERTEX_MATCH_DIAGNOSTIC " + JSON.stringify(diagnostic))
	if diagnostic.unmatched > 0 or used.size() != vertices.size():
		push_error("Source/imported rest mapping rejected; see complete position/normal/UV diagnostic")
		return []
	return matches

func compare_source_pose(actual: PackedVector3Array, expected: Array) -> Dictionary:
	if expected.size() != _source_vertex_matches.size():
		return {"max_error_m": INF, "source_vertex": -1, "imported_vertex": -1}
	var result := {"max_error_m": 0.0, "source_vertex": -1, "imported_vertex": -1,
		"source_vertices": expected.size(), "imported_vertices": actual.size()}
	for source_index: int in expected.size():
		var row: Array = expected[source_index]
		var point := Vector3(row[0], row[1], row[2])
		for imported_index: int in _source_vertex_matches[source_index]:
			var error := actual[imported_index].distance_to(point)
			if error > float(result.max_error_m):
				result.max_error_m = error
				result.source_vertex = source_index
				result.imported_vertex = imported_index
	return result
