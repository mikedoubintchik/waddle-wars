extends Node3D
## Samples the imported run animation, skeleton AND skinned torso vertices.
## A clip may contain plenty of keys yet cancel its own upper-body motion.
## This regression deliberately measures global deformation, not key counts.

var _passes: int = 0
var _failures: int = 0


func _ready() -> void:
	var previous_qa_backend := PenguinVisual.use_authored_backend_for_qa
	_check(not previous_qa_backend, "production keeps unapproved authored backend disabled")
	# This fixture verifies the retained authored candidate deliberately; enabling
	# it here must never promote that model in gameplay or menu previews.
	PenguinVisual.use_authored_backend_for_qa = true
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0.0, 1.0, 4.0)
	camera.current = true
	for role: int in [CharacterLook.RenderRole.HERO, CharacterLook.RenderRole.RACER]:
		var facade := PenguinVisual.new()
		add_child(facade)
		facade.setup_look(CharacterLook.from_legacy_config({"species": "emperor"}, role))
		var rig := facade.find_child("AuthoredHeroPenguin", false, false) as HeroPenguinRig
		_check(rig != null, "role %d selects actual authored rig" % role)
		if rig == null:
			facade.free()
			continue
		var player := rig.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var skeleton := rig.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var mesh := rig.find_child("HeroPenguinMesh", true, false) as MeshInstance3D
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		facade.set_pose(PenguinVisual.Pose.RUN)
		facade.drive_motion(1.0, 0.0, 0.0, 0.0, true)
		# Clear the intentional idle-to-run blend: the gate measures a full steady
		# locomotion cycle; transition tests remain separate.
		player.play(&"run", 0.0)
		player.advance(0.0)
		var original_transform := facade.transform
		var original_rig_transform := rig.transform
		var samples_30 := _sample_cycle(player, skeleton, mesh, 30)
		var samples_60 := _sample_cycle(player, skeleton, mesh, 60)
		_check_motion(samples_30, "role %d / 30 FPS" % role)
		_check_motion(samples_60, "role %d / 60 FPS" % role)
		var rate_error := 0.0
		for frame: int in samples_30.size():
			var low: Dictionary = samples_30[frame]
			var high: Dictionary = samples_60[frame * 2]
			rate_error = maxf(rate_error, (low["chest_vertex"] as Vector3).distance_to(
					high["chest_vertex"] as Vector3))
		_check(rate_error < 0.00001, "role %d identical 30/60 FPS poses at shared times" % role)
		_check(facade.transform.is_equal_approx(original_transform)
				and rig.transform.is_equal_approx(original_rig_transform),
				"role %d animation preserves gameplay and wrapper transforms" % role)
		# A seamless loop must close in actual mesh space, not only at pelvis.
		player.seek(0.0, true)
		var start := _deformed_torso_centroid(skeleton, mesh)
		player.seek(player.current_animation_length, true)
		_check(start.distance_to(_deformed_torso_centroid(skeleton, mesh)) < 0.001,
				"role %d torso run loop closes within 1 mm" % role)
		facade.free()
	print("HERO PENGUIN MOTION: %d passed, %d failed" % [_passes, _failures])
	PenguinVisual.use_authored_backend_for_qa = previous_qa_backend
	get_tree().quit(1 if _failures > 0 else 0)


func _sample_cycle(player: AnimationPlayer, skeleton: Skeleton3D,
		mesh: MeshInstance3D, fps: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var frames := ceili(player.current_animation_length * fps)
	for frame: int in frames:
		player.seek(float(frame) / fps, true)
		var pelvis := _deformation(skeleton, "pelvis")
		var chest := _deformation(skeleton, "spine_upper")
		var head := _deformation(skeleton, "head")
		var root := _deformation(skeleton, "root")
		var feet := _deformed_sole_heights(skeleton, mesh)
		result.append({
			"pelvis_roll": _roll(pelvis.basis),
			"chest_roll": _roll(chest.basis),
			"chest_pitch": rad_to_deg(atan2(chest.basis.y.z, chest.basis.y.y)),
			"head_roll": _roll(head.basis),
			"head_relative_roll": _roll(head.basis) - _roll(chest.basis),
			"chest_vertex": _deformed_torso_centroid(skeleton, mesh),
			"left_sole": feet.x,
			"right_sole": feet.y,
			"root_identity": root.is_equal_approx(Transform3D.IDENTITY),
			"feet_follow_body": _feet_follow_body(skeleton),
		})
	return result


func _check_motion(samples: Array[Dictionary], label: String) -> void:
	var chest_span := _span(samples, "chest_roll")
	var pelvis_span := _span(samples, "pelvis_roll")
	var pitch_max := 0.0
	var roots_identity := true
	var feet_follow_body := true
	var chest_x_min := INF
	var chest_x_max := -INF
	var coherent_frames := 0
	var weighted_frames := 0
	var lowest_sole := INF
	var support_height_max := -INF
	var left_swing_frames := 0
	var right_swing_frames := 0
	for sample: Dictionary in samples:
		pitch_max = maxf(pitch_max, absf(float(sample["chest_pitch"])))
		roots_identity = roots_identity and bool(sample["root_identity"])
		feet_follow_body = feet_follow_body and bool(sample["feet_follow_body"])
		var vertex: Vector3 = sample["chest_vertex"]
		chest_x_min = minf(chest_x_min, vertex.x)
		chest_x_max = maxf(chest_x_max, vertex.x)
		var left_sole := float(sample["left_sole"])
		var right_sole := float(sample["right_sole"])
		lowest_sole = minf(lowest_sole, minf(left_sole, right_sole))
		support_height_max = maxf(support_height_max, minf(left_sole, right_sole))
		if left_sole > right_sole + 0.025:
			left_swing_frames += 1
		elif right_sole > left_sole + 0.025:
			right_swing_frames += 1
		if absf(float(sample["pelvis_roll"])) > 3.0:
			weighted_frames += 1
			if float(sample["chest_roll"]) * float(sample["pelvis_roll"]) > 0.0:
				coherent_frames += 1
	var chest_travel := chest_x_max - chest_x_min
	print("[hero_motion] %s: pelvis %.2f°, chest %.2f°, pitch max %.2f°, head %.2f°, torso travel %.4f m" % [
			label, pelvis_span, chest_span, pitch_max, _span(samples, "head_roll"), chest_travel])
	_check(chest_span >= 8.0 and chest_span <= 25.0, label + " chest visibly rocks without cancelling hips")
	_check(pelvis_span >= 12.0 and pelvis_span <= 30.0, label + " hips shift weight without bottom-only thrashing")
	_check(pitch_max <= 20.0, label + " upright waddle, not frozen 40-degree crouch")
	_check(_span(samples, "head_roll") >= 2.0 and _span(samples, "head_roll") <= 25.0,
			label + " head participates in whole-body motion")
	_check(_span(samples, "head_relative_roll") > 1.5, label + " head has secondary counter-motion")
	_check(chest_travel >= 0.04 and chest_travel < 0.40,
			label + " actual weighted upper torso moves, not only bones")
	_check(weighted_frames > 0 and float(coherent_frames) / maxi(1, weighted_frames) > 0.90,
			label + " chest follows support-side weight shift")
	_check(roots_identity, label + " skeleton root stays identity for entire cycle")
	_check(feet_follow_body, label + " feet follow body without independent local paddling")
	print("[hero_motion] %s: sole min %.4f m; support max %.4f m; swing frames L/R %d/%d" % [
			label, lowest_sole, support_height_max, left_swing_frames, right_swing_frames])
	_check(lowest_sole >= -0.006, label + " skinned feet do not penetrate ground")
	_check(support_height_max < 0.035, label + " at least one supporting foot stays near ground")
	_check(left_swing_frames >= 2 and right_swing_frames >= 2,
			label + " whole-body roll naturally alternates supporting feet")


func _feet_follow_body(skeleton: Skeleton3D) -> bool:
	for bone: int in skeleton.get_bone_count():
		var bone_name := String(skeleton.get_bone_name(bone))
		if bone_name.begins_with("foot") or bone_name.begins_with("toe"):
			if not skeleton.get_bone_pose(bone).is_equal_approx(skeleton.get_bone_rest(bone)):
				return false
	return true


func _deformation(skeleton: Skeleton3D, bone_name: String) -> Transform3D:
	var bone := skeleton.find_bone(bone_name)
	return skeleton.get_bone_global_pose(bone) * skeleton.get_bone_global_rest(bone).affine_inverse()


func _roll(basis: Basis) -> float:
	return rad_to_deg(atan2(-basis.y.x, basis.y.y))


func _span(samples: Array[Dictionary], key: String) -> float:
	var low := INF
	var high := -INF
	for sample: Dictionary in samples:
		low = minf(low, float(sample[key]))
		high = maxf(high, float(sample[key]))
	return high - low


func _deformed_torso_centroid(skeleton: Skeleton3D, mesh: MeshInstance3D) -> Vector3:
	# Imported skin bind indices need not equal Skeleton3D indices. Respect the
	# named bind mapping and inverse bind matrices used by real GPU skinning.
	var transforms: Array[Transform3D] = []
	for bind: int in mesh.skin.get_bind_count():
		var bone := mesh.skin.get_bind_bone(bind)
		if bone < 0:
			bone = skeleton.find_bone(mesh.skin.get_bind_name(bind))
		transforms.append(skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind))
	var arrays := mesh.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var total := Vector3.ZERO
	var count := 0
	for index: int in vertices.size():
		var vertex := vertices[index]
		# Central chest only: exclude flippers, hips, eye/bill geometry and neck.
		if vertex.y < 0.96 or vertex.y > 1.20 or absf(vertex.x) > 0.23:
			continue
		var deformed := Vector3.ZERO
		for influence: int in 4:
			var offset := index * 4 + influence
			deformed += (transforms[bones[offset]] * vertex) * weights[offset]
		total += deformed
		count += 1
	assert(count > 20, "Imported mesh must expose enough actual torso samples")
	return total / maxi(1, count)


func _deformed_sole_heights(skeleton: Skeleton3D, mesh: MeshInstance3D) -> Vector2:
	var transforms: Array[Transform3D] = []
	var foot_binds: Array[bool] = []
	for bind: int in mesh.skin.get_bind_count():
		var bone := mesh.skin.get_bind_bone(bind)
		if bone < 0:
			bone = skeleton.find_bone(mesh.skin.get_bind_name(bind))
		var bone_name := String(skeleton.get_bone_name(bone))
		foot_binds.append(bone_name.begins_with("foot") or bone_name.begins_with("toe"))
		transforms.append(skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind))
	var arrays := mesh.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var heights := Vector2(INF, INF)
	for index: int in vertices.size():
		var foot_weight := 0.0
		for influence: int in 4:
			var offset := index * 4 + influence
			if foot_binds[bones[offset]]:
				foot_weight += weights[offset]
		if foot_weight < 0.9:
			continue
		var deformed := Vector3.ZERO
		for influence: int in 4:
			var offset := index * 4 + influence
			deformed += (transforms[bones[offset]] * vertices[index]) * weights[offset]
		if vertices[index].x < 0.0:
			heights.x = minf(heights.x, deformed.y)
		else:
			heights.y = minf(heights.y, deformed.y)
	return heights


func _check(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
	else:
		_failures += 1
		push_error("FAIL: " + label)
