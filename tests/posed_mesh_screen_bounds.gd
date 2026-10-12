extends RefCounted
## QA-only projected bounds of currently visible, morphed and skinned vertices.
## Not a raster mask: no occlusion, alpha discard, shader displacement, billboard
## rotation, automatic mesh LOD, or visibility-range fading is reconstructed.
## Sample after animation/modifiers and frame_post_draw, without advancing them.
## Morph math follows Godot 4.7.1 MeshInstance3D's CPU blend-shape bake; skin
## math follows the imported production rig's Skeleton3D pose * inverse bind.


static func measure(root: Node, camera: Camera3D) -> Dictionary:
	var result := {"valid": false, "height_fraction": 0.0, "screen_rect": Rect2(),
		"mesh_count": 0, "vertex_count": 0, "skinned_vertices": 0,
		"morphed_vertices": 0, "hidden_meshes": 0, "errors": PackedStringArray(),
		"scope": "Projected posed mesh vertices; not raster silhouette or occlusion coverage."}
	if root == null or camera == null or not camera.is_inside_tree():
		result.errors.append("Missing in-tree root/camera")
		return result
	var height := camera.get_viewport().get_visible_rect().size.y
	if height <= 0.0:
		result.errors.append("Viewport height is zero")
		return result
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.push_front(root)
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	var camera_inverse := camera.get_camera_transform().affine_inverse()
	for raw: Node in meshes:
		var instance := raw as MeshInstance3D
		if instance.mesh == null:
			continue
		if not instance.is_visible_in_tree() or (instance.layers & camera.cull_mask) == 0 \
				or instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY \
				or instance.transparency >= 1.0:
			result.hidden_meshes += 1
			continue
		var posed := world_vertices(instance)
		if not posed.errors.is_empty():
			for error: String in posed.errors:
				result.errors.append("%s: %s" % [instance.get_path(), error])
			continue
		result.mesh_count += 1
		result.skinned_vertices += posed.skinned_vertices
		result.morphed_vertices += posed.morphed_vertices
		for point: Vector3 in posed.vertices:
			if not point.is_finite() or -(camera_inverse * point).z <= camera.near:
				result.errors.append("%s: non-finite vertex or near-plane intersection" % instance.get_path())
				break
			var screen := camera.unproject_position(point)
			low = low.min(screen)
			high = high.max(screen)
			result.vertex_count += 1
	if result.vertex_count == 0:
		result.errors.append("No visible mesh vertices")
	result.valid = result.errors.is_empty()
	if result.valid:
		result.screen_rect = Rect2(low, high - low)
		result.height_fraction = (high.y - low.y) / height
	return result


static func world_vertices(instance: MeshInstance3D) -> Dictionary:
	var result := {"vertices": PackedVector3Array(), "skinned_vertices": 0,
		"morphed_vertices": 0, "errors": PackedStringArray()}
	if instance == null or instance.mesh == null or not instance.is_inside_tree():
		result.errors.append("Missing in-tree mesh")
		return result
	var mesh := instance.mesh
	var shape_count := (mesh as ArrayMesh).get_blend_shape_count() if mesh is ArrayMesh else 0
	var skeleton := instance.get_node_or_null(instance.skeleton) as Skeleton3D \
		if not instance.skeleton.is_empty() else null
	var skin := instance.skin
	if skin == null and instance.get_skin_reference() != null:
		skin = instance.get_skin_reference().get_skin()
	var transforms: Array[Transform3D] = []
	for surface: int in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.size() != Mesh.ARRAY_MAX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
			result.errors.append("Surface has no readable vertex array")
			continue
		var base: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var vertices := base.duplicate()
		var morphed := false
		if shape_count > 0:
			if not mesh is ArrayMesh:
				result.errors.append("Blend shapes require readable ArrayMesh")
				continue
			var shapes := (mesh as ArrayMesh).surface_get_blend_shape_arrays(surface)
			if shapes.size() != shape_count:
				result.errors.append("Blend-shape surface count mismatch")
				continue
			for shape: int in shapes.size():
				var weight := instance.get_blend_shape_value(shape)
				if weight == 0.0:
					continue
				var target: PackedVector3Array = shapes[shape][Mesh.ARRAY_VERTEX]
				if not is_finite(weight) or target.size() != base.size():
					result.errors.append("Invalid blend-shape weight or vertex count")
					continue
				morphed = true
				for index: int in vertices.size():
					var delta := target[index]
					if (mesh as ArrayMesh).blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED:
						delta -= base[index]
					vertices[index] += delta * weight
		var skinned := arrays[Mesh.ARRAY_BONES] is PackedInt32Array \
			and not (arrays[Mesh.ARRAY_BONES] as PackedInt32Array).is_empty()
		var world := instance.global_transform
		if skinned:
			if skeleton == null or skin == null:
				result.errors.append("Weighted mesh lacks resolved skeleton/skin")
				continue
			# Production GLB has mesh and skeleton in the same global frame.
			# Refuse unsupported layouts instead of guessing their bind convention.
			if not instance.global_transform.is_equal_approx(skeleton.global_transform):
				result.errors.append("Skinned mesh/skeleton frames differ; unsupported bind convention")
				continue
			world = skeleton.global_transform
			if transforms.is_empty():
				for bind: int in skin.get_bind_count():
					var name := skin.get_bind_name(bind)
					var bone := skeleton.find_bone(name) if not name.is_empty() else skin.get_bind_bone(bind)
					if bone < 0 or bone >= skeleton.get_bone_count():
						result.errors.append("Invalid skin bind")
						break
					transforms.append(skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(bind))
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var stride := 8 if mesh.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS else 4
			if bones.size() != vertices.size() * stride or weights.size() != bones.size() \
					or transforms.size() != skin.get_bind_count():
				result.errors.append("Invalid skin influence arrays")
				continue
			for index: int in vertices.size():
				var posed := Vector3.ZERO
				var total := 0.0
				for influence: int in stride:
					var offset := index * stride + influence
					var weight := weights[offset]
					if weight == 0.0:
						continue
					if not is_finite(weight) or weight < 0.0 or bones[offset] < 0 or bones[offset] >= transforms.size():
						result.errors.append("Invalid skin influence")
						break
					posed += (transforms[bones[offset]] * vertices[index]) * weight
					total += weight
				if absf(total - 1.0) > 0.001:
					result.errors.append("Skin weights are not normalized")
				vertices[index] = posed
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
			indices = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for index: int in vertices.size():
				indices.append(index)
		var used := {}
		for index: int in indices:
			if index < 0 or index >= vertices.size():
				result.errors.append("Invalid surface index")
				continue
			if used.has(index):
				continue
			used[index] = true
			result.vertices.append(world * vertices[index])
			result.skinned_vertices += 1 if skinned else 0
			result.morphed_vertices += 1 if morphed else 0
	return result
