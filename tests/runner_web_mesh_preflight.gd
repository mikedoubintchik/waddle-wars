extends RefCounted
## Real renderer readback probe, before the world or any performance clocks.
## A worker can draw normally while a main-thread TLS lookup silently skips
## filling CPU mesh buffers. Checking only FPS or JavaScript eval misses that.

const REQUIRED_CHECKS: int = 6


static func run_checks() -> Dictionary:
	var result := {"passed": true, "checks": 0, "failures": PackedStringArray(),
		"simultaneously_alive_distinct_meshes": 2,
		"scope": "Two simultaneously alive distinct meshes: real vertex/morph reads and blended bounds before world construction; browser readback witness required separately; not full graphics or performance acceptance"}
	var fixtures: Array[Dictionary] = []
	# Keep both distinct uploads and CPU references alive before any read. A
	# skipped fill must not pass merely because its allocation reuses one upload.
	for pass_index: int in 2:
		var shift := float(pass_index) * 4.0
		var base := PackedVector3Array([
			Vector3(0.25 + shift, 0.5, -0.75),
			Vector3(1.25 + shift, 2.5, 0.25),
			Vector3(-0.75 + shift, 1.5, 1.25),
		])
		var target := PackedVector3Array([
			base[0] + Vector3(0.5, 0.25, -0.5),
			base[1] + Vector3(0.25, 1.0, 0.5),
			base[2] + Vector3(-0.5, 0.5, 0.25),
		])
		var arrays := _arrays(base)
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
		var shape_arrays: Array[Array] = [_arrays(target)]
		var mesh := ArrayMesh.new()
		mesh.set_blend_shape_mode(Mesh.BLEND_SHAPE_MODE_NORMALIZED)
		mesh.add_blend_shape("readback_probe")
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, shape_arrays)
		fixtures.append({"mesh": mesh, "base": base, "target": target})
	for pass_index: int in fixtures.size():
		var mesh: ArrayMesh = fixtures[pass_index].mesh
		var base: PackedVector3Array = fixtures[pass_index].base
		var target: PackedVector3Array = fixtures[pass_index].target
		var read_arrays := mesh.surface_get_arrays(0)
		_record(result, _vertices_match(read_arrays[Mesh.ARRAY_VERTEX], base),
			"mesh_%d_vertex_readback" % pass_index)
		var read_shapes := mesh.surface_get_blend_shape_arrays(0)
		var shape_matches := read_shapes.size() == 1
		if shape_matches:
			shape_matches = _vertices_match(read_shapes[0][Mesh.ARRAY_VERTEX], target)
		_record(result, shape_matches, "mesh_%d_morph_readback" % pass_index)
		# Do not feed uninitialized data into the bake after a failed read.
		if not bool(result["passed"]):
			return result
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.set_blend_shape_value(0, 0.375)
		var baked := instance.bake_mesh_from_current_blend_shape_mix()
		var expected := AABB(base[0].lerp(target[0], 0.375), Vector3.ZERO)
		for index: int in range(1, base.size()):
			expected = expected.expand(base[index].lerp(target[index], 0.375))
		var bounds_match := baked != null
		if bounds_match:
			var actual := baked.get_aabb()
			bounds_match = actual.position.is_finite() and actual.size.is_finite() \
				and actual.position.distance_to(expected.position) < 0.0001 \
				and actual.size.distance_to(expected.size) < 0.0001
		_record(result, bounds_match, "mesh_%d_blended_bounds" % pass_index)
		instance.free()
	return result


static func _arrays(vertices: PackedVector3Array) -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
	arrays[Mesh.ARRAY_TANGENT] = PackedFloat32Array([
		1.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0])
	return arrays


static func _vertices_match(value: Variant, expected: PackedVector3Array) -> bool:
	if not value is PackedVector3Array:
		return false
	var actual: PackedVector3Array = value
	if actual.size() != expected.size():
		return false
	for index: int in expected.size():
		if not actual[index].is_finite() or not expected[index].is_finite() \
				or actual[index].distance_to(expected[index]) > 0.0001:
			return false
	return true


static func _record(result: Dictionary, passed: bool, label: String) -> void:
	result["checks"] = int(result["checks"]) + 1
	if not passed:
		result["passed"] = false
		var failures: PackedStringArray = result["failures"]
		failures.append(label)
		result["failures"] = failures
