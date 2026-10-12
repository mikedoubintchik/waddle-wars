extends Node

const Bounds = preload("res://tests/posed_mesh_screen_bounds.gd")
var _passed := 0
var _failed := 0
var _stage: Node3D
var _camera: Camera3D


func _ready() -> void:
	_stage = Node3D.new()
	add_child(_stage)
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 0, 10)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.size = 10.0
	_stage.add_child(_camera)
	_visible_contracts()
	_morph_contracts()
	_skin_contracts(4, false)
	_skin_contracts(8, true)
	_stage.free()
	print("[posed_mesh_screen_bounds] DONE: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed else 0)


func _visible_contracts() -> void:
	var visible := _instance(_triangle())
	var expected := Bounds.measure(visible, _camera)
	_check("actual_triangle_height", expected.valid and is_equal_approx(expected.height_fraction, 0.2)
		and expected.vertex_count == 3)
	var hidden_parent := Node3D.new()
	_stage.add_child(hidden_parent)
	var hidden := _instance(_triangle())
	hidden.reparent(hidden_parent)
	hidden.scale = Vector3.ONE * 100.0
	hidden_parent.hide()
	var result := Bounds.measure(_stage, _camera)
	_check("hidden_parent_excludes_locally_visible_mesh", hidden.visible and not hidden.is_visible_in_tree()
		and result.valid and result.hidden_meshes == 1 and result.mesh_count == 1
		and is_equal_approx(result.height_fraction, expected.height_fraction))
	hidden_parent.free()
	visible.layers = 2
	_camera.cull_mask = 1
	_check("camera_layer_excluded", not Bounds.measure(visible, _camera).valid)
	visible.layers = 1
	visible.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_check("shadow_only_excluded", not Bounds.measure(visible, _camera).valid)
	visible.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	visible.transparency = 1.0
	_check("fully_transparent_excluded", not Bounds.measure(visible, _camera).valid)
	visible.transparency = 0.0
	visible.position.z = 11.0
	_check("behind_camera_rejected", not Bounds.measure(visible, _camera).valid)
	visible.free()
	var indexed := _triangle()
	var arrays := indexed.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	vertices.append(Vector3(0, 100, 0))
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	indexed.clear_surfaces()
	indexed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var indexed_instance := _instance(indexed)
	result = Bounds.measure(indexed_instance, _camera)
	_check("unreferenced_vertex_does_not_inflate_bounds", result.valid and result.vertex_count == 3
		and is_equal_approx(result.height_fraction, 0.2))
	indexed_instance.free()
	var multiple := _triangle()
	var upper := multiple.surface_get_arrays(0)
	upper[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-1, 3, 0), Vector3(1, 3, 0), Vector3(0, 4, 0)])
	multiple.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, upper)
	var multiple_instance := _instance(multiple)
	result = Bounds.measure(multiple_instance, _camera)
	_check("all_material_surfaces_contribute", result.valid and result.vertex_count == 6
		and is_equal_approx(result.height_fraction, 0.4))
	multiple_instance.free()


func _morph_contracts() -> void:
	for mode: int in [Mesh.BLEND_SHAPE_MODE_RELATIVE, Mesh.BLEND_SHAPE_MODE_NORMALIZED]:
		var mesh := _triangle(mode)
		var instance := _instance(mesh)
		instance.set_blend_shape_value(0, 0.5)
		var result := Bounds.world_vertices(instance)
		var baked := instance.bake_mesh_from_current_blend_shape_mix()
		var baked_vertices: PackedVector3Array = baked.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		_check("morph_mode_%d_matches_engine_bake" % mode, result.errors.is_empty()
			and result.morphed_vertices == 3 and _points_equal(result.vertices, baked_vertices))
		var measured := Bounds.measure(instance, _camera)
		_check("morph_mode_%d_changes_projected_height" % mode,
			measured.valid and is_equal_approx(measured.height_fraction, 0.3))
		instance.free()


func _skin_contracts(stride: int, named: bool) -> void:
	var skeleton := Skeleton3D.new()
	_stage.add_child(skeleton)
	skeleton.position = Vector3(2, 1, 0)
	skeleton.add_bone("root")
	skeleton.add_bone("stretch")
	skeleton.set_bone_parent(1, 0)
	skeleton.set_bone_rest(0, Transform3D.IDENTITY)
	skeleton.set_bone_rest(1, Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)))
	skeleton.reset_bone_poses()
	skeleton.set_bone_pose_position(1, Vector3(0, 3, 0))
	var skin := Skin.new()
	# Bind order deliberately differs from bone order; named and numeric paths.
	if named:
		skin.add_named_bind("stretch", Transform3D(Basis.IDENTITY, Vector3(0, -1, 0)))
		skin.add_named_bind("root", Transform3D.IDENTITY)
	else:
		skin.add_bind(1, Transform3D(Basis.IDENTITY, Vector3(0, -1, 0)))
		skin.add_bind(0, Transform3D.IDENTITY)
	var instance := MeshInstance3D.new()
	instance.mesh = _triangle(Mesh.BLEND_SHAPE_MODE_RELATIVE, stride)
	instance.skin = skin
	instance.skeleton = NodePath("..")
	skeleton.add_child(instance)
	instance.set_blend_shape_value(0, 0.5)
	var result := Bounds.world_vertices(instance)
	# Godot stores weights as UNORM16, so requested0.5 reads back0.49999237.
	# Test the actual weights without renormalizing or widening point tolerance.
	# Morph gives y=3; stretch bind gives y=5; skeleton world translation adds1.
	var stored: PackedFloat32Array = instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_WEIGHTS]
	var stretch_offset := 7 if stride == 8 else 1
	var top_y := 1.0 + 3.0 * stored[2 * stride] + 5.0 * stored[2 * stride + stretch_offset]
	var expected := PackedVector3Array([Vector3(1, 1, 0), Vector3(3, 1, 0), Vector3(2, top_y, 0)])
	_check("skin_%d_morph_before_pose_inverse_bind_world" % stride, result.errors.is_empty()
		and result.skinned_vertices == 3 and result.morphed_vertices == 3
		and _points_equal(result.vertices, expected))
	var measured := Bounds.measure(instance, _camera)
	_check("skin_%d_uses_deformed_not_rest_height" % stride,
		measured.valid and is_equal_approx(measured.height_fraction, 0.4))
	instance.position.x = 1.0
	_check("skin_%d_different_frame_rejected" % stride, not Bounds.world_vertices(instance).errors.is_empty())
	instance.position = Vector3.ZERO
	instance.skeleton = NodePath("")
	_check("skin_%d_missing_skeleton_rejected" % stride, not Bounds.world_vertices(instance).errors.is_empty())
	skeleton.free()


func _triangle(morph_mode: int = -1, stride: int = 0) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, 2, 0)])
	var shapes: Array[Array] = []
	if morph_mode >= 0:
		mesh.blend_shape_mode = morph_mode
		mesh.add_blend_shape("taller")
		var shape := []
		shape.resize(Mesh.ARRAY_MAX)
		shape[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3(0, 2, 0)]) \
			if morph_mode == Mesh.BLEND_SHAPE_MODE_RELATIVE else \
			PackedVector3Array([Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, 4, 0)])
		shapes.append(shape)
	if stride > 0:
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		bones.resize(3 * stride)
		weights.resize(3 * stride)
		for index: int in 3:
			bones[index * stride] = 1
			weights[index * stride] = 1.0
		weights[2 * stride] = 0.5
		var other := 7 if stride == 8 else 1
		bones[2 * stride + other] = 0
		weights[2 * stride + other] = 0.5
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, shapes, {},
		Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if stride == 8 else 0)
	return mesh


func _instance(mesh: Mesh) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	_stage.add_child(instance)
	return instance


func _points_equal(actual: PackedVector3Array, expected: PackedVector3Array) -> bool:
	if actual.size() != expected.size():
		return false
	for index: int in actual.size():
		if not actual[index].is_equal_approx(expected[index]):
			print("[posed_mesh_screen_bounds] point %d actual=%s expected=%s delta=%s" % [
				index, actual[index], expected[index], actual[index] - expected[index]])
			return false
	return true


func _check(label: String, okay: bool) -> void:
	_passed += 1 if okay else 0
	_failed += 0 if okay else 1
	print("[posed_mesh_screen_bounds] %s %s" % ["PASS" if okay else "FAIL", label])
