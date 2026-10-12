extends RefCounted
## Read-only motion diagnostics shared by every candidate material contract.


static func snapshot(rig: HeroPenguinRig) -> Dictionary:
	var skeleton := rig.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var root_bone := skeleton.find_bone("root")
	var root_identity := skeleton.get_bone_pose(root_bone).is_equal_approx(skeleton.get_bone_rest(root_bone))
	var attached_feet := true
	for bone: int in skeleton.get_bone_count():
		var label := String(skeleton.get_bone_name(bone))
		if label.begins_with("foot") or label.begins_with("toe"):
			attached_feet = attached_feet and skeleton.get_bone_pose(bone).is_equal_approx(skeleton.get_bone_rest(bone))
	var soles := Vector2(INF, INF)
	for mesh: MeshInstance3D in rig._meshes:
		var skin := mesh.skin
		if skin == null:
			continue
		var transforms: Array[Transform3D] = []
		var foot_binds: Array[bool] = []
		for bind: int in skin.get_bind_count():
			var bone := skin.get_bind_bone(bind)
			if bone < 0:
				bone = skeleton.find_bone(skin.get_bind_name(bind))
			var label := String(skeleton.get_bone_name(bone))
			foot_binds.append(label.begins_with("foot") or label.begins_with("toe"))
			transforms.append(skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(bind))
		for surface: int in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			for vertex: int in vertices.size():
				if vertices[vertex].y > 0.30:
					continue
				var foot_weight := 0.0
				var deformed := Vector3.ZERO
				for influence: int in 4:
					var offset := vertex * 4 + influence
					if foot_binds[bones[offset]]:
						foot_weight += weights[offset]
					deformed += (transforms[bones[offset]] * vertices[vertex]) * weights[offset]
				if foot_weight >= 0.98:
					var side := 0 if vertices[vertex].x < 0.0 else 1
					soles[side] = minf(soles[side], (skeleton.global_transform * deformed).y)
	var rolls: Dictionary = {}
	for label: String in ["pelvis", "spine_upper", "head"]:
		var bone := skeleton.find_bone(label)
		var deformation := skeleton.get_bone_global_pose(bone) * skeleton.get_bone_global_rest(bone).affine_inverse()
		rolls[label] = rad_to_deg(atan2(-deformation.basis.y.x, deformation.basis.y.y))
	return {"clip": String(rig._animation_player.current_animation), "clip_time": rig._animation_player.current_animation_position,
		"skeleton_root_identity": root_identity, "feet_local_follow_body": attached_feet,
		"left_sole_world_y": soles.x, "right_sole_world_y": soles.y,
		"pelvis_roll": rolls.pelvis, "chest_roll": rolls.spine_upper, "head_roll": rolls.head}
