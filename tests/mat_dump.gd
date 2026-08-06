extends SceneTree
## Debug: prints iceberg MainTrack floor materials near the start.

func _init() -> void:
	var script: GDScript = load("res://scripts/courses/course_iceberg.gd")
	var course: Node3D = script.new()
	root.add_child(course)
	await process_frame
	await process_frame
	var track: Node = course.get_node_or_null("MainTrack")
	if track == null:
		print("no MainTrack")
		quit(1)
		return
	var count := 0
	var children := track.get_children()
	for i: int in children.size():
		var mesh_instance := children[i] as MeshInstance3D
		if mesh_instance == null or mesh_instance.material_override == null:
			continue
		var body := children[i + 1] as StaticBody3D if i + 1 < children.size() else null
		var surface := int(body.get_meta("surface")) if body != null and body.has_meta("surface") else -1
		var aabb := mesh_instance.mesh.get_aabb()
		var mat := mesh_instance.material_override
		var desc := mat.get_class()
		if mat is ShaderMaterial:
			var sm := mat as ShaderMaterial
			desc += " shader=" + sm.shader.resource_path.get_file()
			for param: String in ["tint", "deep_tint", "clarity", "detail_level", "crack_strength"]:
				var v: Variant = sm.get_shader_parameter(param)
				if v != null:
					desc += " %s=%s" % [param, str(v)]
		print("floor[%d] z=%.0f..%.0f surface=%d %s" % [count, aabb.position.z + mesh_instance.position.z, aabb.end.z + mesh_instance.position.z, surface, desc])
		count += 1
		if count > 8:
			break
	quit(0)
