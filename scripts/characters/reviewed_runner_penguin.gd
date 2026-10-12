class_name ReviewedRunnerPenguin
extends Node3D
## The reviewed three-clip penguin, inside PenguinVisual's visibility boundary.
## Only bones articulate: RunnerPlayer retains all travel and collision authority.

const MODEL_PATH := "res://assets/art/characters/runner_penguin_v1.glb"
const MODEL_SHA256 := "206632fc655b49dc590caa621b01f2ce83ccd3108ff4a4c82787e0e8a016eef2"
const GAME_SCALE := 0.6201416744371788
const CLIPS := ["jump", "slide", "waddle"]
# Values are the stable PenguinVisual.Pose facade, without a circular preload.
const RUN := 0
const SLIDE := 1
const AIR := 2
const IDLE := 5
const DEFEAT := 7

var model: Node3D
var animation: AnimationPlayer
var skeleton: Skeleton3D
var action := "idle"
var phase := 0.0
var _pose := IDLE
var _vertical_speed := 0.0
var _launch_speed := RunnerConfig.JUMP_SPEED
var _speed_ratio := 0.0
var _rest_sole_y := 0.0
var _look_offset := Vector3.ZERO
var _impact_left := 0.0
var _impact_side := 1.0
var _observed_source_sha256 := ""


static func supports_look(look: CharacterLook) -> bool:
	return look != null and look.render_role == CharacterLook.RenderRole.HERO \
		and look.species_id == "emperor" and look.hat_id.is_empty() \
		and look.scarf_id.is_empty() and look.goggles_id.is_empty()


static func supports_pose(pose_id: int) -> bool:
	return pose_id in [RUN, SLIDE, AIR, IDLE, DEFEAT]


func initialize(look: CharacterLook) -> bool:
	# Exported PCKs normally contain the imported scene, not the raw GLB.
	# Host source identity is separate from actual imported resource evidence.
	if FileAccess.file_exists(MODEL_PATH):
		_observed_source_sha256 = FileAccess.get_sha256(MODEL_PATH)
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		return false
	model = packed.instantiate() as Node3D
	if model == null:
		return false
	add_child(model)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if players.size() != 1 or skeletons.size() != 1:
		return false
	animation = players[0] as AnimationPlayer
	skeleton = skeletons[0] as Skeleton3D
	var names: Array = Array(animation.get_animation_list())
	names.sort()
	if names != CLIPS:
		return false
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_rest_sole_y = INF
	for raw: Node in model.find_children("*", "MeshInstance3D", true, false):
		var instance := raw as MeshInstance3D
		if instance.mesh == null:
			continue
		var local := relative_transform(instance, self)
		for surface: int in instance.mesh.get_surface_count():
			var material := instance.mesh.surface_get_material(surface) as StandardMaterial3D
			if material == null or instance.get_active_material(surface) != material:
				return false
			var vertices: PackedVector3Array = instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				_rest_sole_y = minf(_rest_sole_y, (local * vertex).y)
	if not is_finite(_rest_sole_y):
		return false
	_look_offset = look.visual_offset
	position = _look_offset
	rotation_degrees = look.visual_rotation_degrees
	scale = Vector3.ONE * GAME_SCALE * look.visual_scale
	set_floor_height(0.0)
	_select_action("idle", 0.0)
	return true


func set_floor_height(height: float) -> void:
	# Rest soles are seated once per actual floor change, never per animated pose.
	position.y = _look_offset.y + height - _rest_sole_y * scale.y


func set_pose(pose_id: int) -> void:
	if pose_id == _pose:
		return
	_pose = pose_id
	var next := "idle"
	match pose_id:
		RUN: next = "waddle"
		SLIDE, DEFEAT: next = "slide"
		AIR: next = "jump"
	if next != action:
		_select_action(next, 0.12)


func drive_motion(speed_ratio: float, vertical_speed: float) -> void:
	_speed_ratio = speed_ratio
	_vertical_speed = vertical_speed


func trigger_event(event_id: StringName, context: Dictionary) -> void:
	match event_id:
		&"jumped", &"jump_takeoff":
			_launch_speed = maxf(0.01, float(context.get("vertical_speed", RunnerConfig.JUMP_SPEED)))
			_select_action("jump", 0.10)
		&"ramp_launched", &"ramp_launch":
			_launch_speed = maxf(0.01, float(context.get("launch_power", RunnerConfig.RAMP_LAUNCH)))
			_select_action("jump", 0.10)
		&"hit_taken", &"hit", &"stumble", &"shield_spent", &"shield_hit":
			_impact_left = 0.42 if event_id in [&"shield_spent", &"shield_hit"] else 0.75
			_impact_side = signf(float(context.get("side", 1.0)))
			if is_zero_approx(_impact_side):
				_impact_side = 1.0


func _select_action(next: String, blend: float) -> void:
	if animation == null:
		return
	action = next
	phase = 0.0
	var clip_name := "jump" if next == "idle" else next
	var clip := animation.get_animation(clip_name)
	var rate := clip.length / (2.0 * _launch_speed / RunnerConfig.GRAVITY) if next == "jump" else 1.0
	animation.speed_scale = 1.0
	animation.play(clip_name, blend, rate)
	animation.seek(0.0, true)
	animation.advance(0.0)


func tick(delta: float) -> void:
	if animation == null:
		return
	if action == "idle":
		# Neutral authored rest; no invented idle or podium animation.
		animation.seek(0.0, true)
	elif action == "jump":
		animation.advance(delta)
		# Fast-fall and ramps use actual velocity, not a second ballistic clock.
		phase = clampf((_launch_speed - _vertical_speed) / (2.0 * _launch_speed), 0.0, 1.0)
		var desired_time := phase * animation.get_animation("jump").length
		if absf(animation.current_animation_position - desired_time) > 0.002:
			animation.seek(desired_time, true)
	else:
		animation.speed_scale = lerpf(0.90, 1.15, clampf(_speed_ratio, 0.0, 1.0)) if action == "waddle" else 1.0
		animation.advance(delta)
		phase = animation.current_animation_position / animation.get_animation(action).length
	_impact_left = maxf(0.0, _impact_left - delta)
	var impact := sin(_impact_left * 23.0) * _impact_left
	model.rotation = Vector3(0.0, impact * _impact_side * 0.22, impact * -_impact_side * 0.30)


func snapshot() -> Dictionary:
	var surfaces: Array[Dictionary] = []
	for raw: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := raw as MeshInstance3D
		if mesh.mesh == null:
			continue
		for index: int in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(index) as StandardMaterial3D
			var entry := {"mesh": String(model.get_path_to(mesh)), "visible": mesh.is_visible_in_tree(),
				"surface": index, "imported_material": material == mesh.mesh.surface_get_material(index),
				"override": mesh.material_override != null or mesh.get_surface_override_material(index) != null,
				"overlay": mesh.material_overlay != null}
			if material != null:
				entry["material_class"] = material.get_class()
				entry["specular"] = material.metallic_specular
				entry["normal_scale"] = material.normal_scale
				entry["albedo"] = var_to_str(material.albedo_color)
				var maps: Dictionary = {}
				for slot: int in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ROUGHNESS]:
					var texture := material.get_texture(slot)
					if texture != null:
						maps[str(slot)] = {"class": texture.get_class(), "width": texture.get_width(), "height": texture.get_height()}
				entry["maps"] = maps
			surfaces.append(entry)
	return {"model_path": model.scene_file_path, "declared_source_sha256": MODEL_SHA256,
		"observed_source_sha256": _observed_source_sha256,
		"visible": visible, "visible_in_tree": is_visible_in_tree(), "action": action, "phase": phase,
		"clip": String(animation.assigned_animation), "clip_time": animation.current_animation_position,
		"clip_length": animation.current_animation_length, "transform": var_to_str(transform),
		"scale": var_to_str(scale), "floor_offset": position.y, "rest_sole_y": _rest_sole_y,
		"surfaces": surfaces, "root_motion": "Gameplay-owned; rig articulation only"}


static func relative_transform(node: Node3D, stop: Node = null) -> Transform3D:
	var result := node.transform
	var ancestor := node.get_parent()
	while ancestor != null and ancestor != stop:
		if ancestor is Node3D:
			result = (ancestor as Node3D).transform * result
		ancestor = ancestor.get_parent()
	return result


static func floor_height_at(track: Node3D, point: Vector3) -> float:
	# Match the actual authored ice skin, whose y=.022 covers the collision deck.
	# Procedural/non-DAY chunks retain their actual Deck height. No prop snapping.
	for kind: String in ["GlacialIceSkin", "Deck"]:
		for raw: Node in track.find_children(kind, "MeshInstance3D", true, false):
			var instance := raw as MeshInstance3D
			if not instance.visible or (instance.is_inside_tree() and not instance.is_visible_in_tree()) \
				or not instance.mesh is PlaneMesh:
				continue
			var world := relative_transform(instance)
			var local := world.affine_inverse() * point
			var box := instance.mesh.get_aabb()
			if local.x >= box.position.x and local.x <= box.end.x \
				and local.z >= box.position.z and local.z <= box.end.z:
				return (world * Vector3(local.x, box.position.y, local.z)).y
	return 0.0
