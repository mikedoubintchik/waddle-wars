extends Node
## Actual imported bones, including the entire idle-to-run blend, at equal times.
## No source asset replacement, shader changes, automatic-clock workaround, or saves.

const HERO_SCENE := preload("res://assets/art/characters/hero_penguin_v1.tscn")
const TRANSITIONS: Array[Dictionary] = [
	{"name": "idle_to_run", "from": PenguinVisual.Pose.IDLE, "to": PenguinVisual.Pose.RUN, "seconds": 0.3},
	{"name": "slide_to_run", "from": PenguinVisual.Pose.SLIDE, "to": PenguinVisual.Pose.RUN},
	{"name": "run_to_slide", "from": PenguinVisual.Pose.RUN, "event": &"slide_enter"},
	{"name": "run_to_jump", "from": PenguinVisual.Pose.RUN, "event": &"jump_takeoff"},
	{"name": "air_to_land", "from": PenguinVisual.Pose.AIR, "event": &"landed"},
	{"name": "run_to_hit_left", "from": PenguinVisual.Pose.RUN, "event": &"hit", "side": -1.0},
	{"name": "run_to_hit_right", "from": PenguinVisual.Pose.RUN, "event": &"hit", "side": 1.0},
	{"name": "run_to_launch", "from": PenguinVisual.Pose.RUN, "event": &"ramp_launched"},
	{"name": "run_to_defeat", "from": PenguinVisual.Pose.RUN, "event": &"defeat"},
]


func _ready() -> void:
	var passed := true
	for transition: Dictionary in TRANSITIONS:
		passed = _check_transition(transition) and passed
	await get_tree().process_frame
	get_tree().quit(0 if passed else 1)


func _check_transition(transition: Dictionary) -> bool:
	var slow := _sample(30, transition)
	var fast := _sample(60, transition)
	var position_error := 0.0
	var rotation_error := 0.0
	var clip_error := 0.0
	for index: int in slow.size():
		var a: Dictionary = slow[index]
		var b: Dictionary = fast[index * 2]
		clip_error = maxf(clip_error, absf(a.time - b.time))
		for bone: int in a.positions.size():
			position_error = maxf(position_error, a.positions[bone].distance_to(b.positions[bone]))
			var qa: Quaternion = a.rotations[bone]
			var qb: Quaternion = b.rotations[bone]
			if qa.dot(qb) < 0.0:
				qb = -qb
			for difference: float in [qa.x - qb.x, qa.y - qb.y, qa.z - qb.z, qa.w - qb.w]:
				rotation_error = maxf(rotation_error, absf(difference))
	var passed := position_error < 0.00001 and rotation_error < 0.00001 and clip_error < 0.000001
	print("[hero_transition] %s: position_error=%.9fm quaternion_component_error=%.9f clip_time_error=%.9fs" % [transition.name, position_error, rotation_error, clip_error])
	if not passed:
		push_error("[hero_transition] equal-time 30/60 FPS transition poses differ")
	else:
		print("[hero_transition] PASS full transition and unchanged clip timing")
	return passed


func _sample(fps: int, transition: Dictionary) -> Array[Dictionary]:
	var hero := HERO_SCENE.instantiate() as HeroPenguinRig
	add_child(hero)
	var player := hero.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var skeleton := hero.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	hero.set_pose(int(transition.from))
	player.advance(0.0)
	player.advance(0.2)
	if transition.has("event"):
		hero.trigger_event(transition.event, {"side": transition.get("side", 1.0)})
	else:
		hero.set_pose(int(transition.to))
	hero.set_cadence(1.0)
	hero.tick(0.0)
	player.advance(0.0)
	var samples: Array[Dictionary] = []
	for frame: int in roundi(float(fps) * float(transition.get("seconds", 0.1))) + 1:
		if frame > 0:
			hero.tick(1.0 / float(fps))
			player.advance(1.0 / float(fps))
		var positions: Array[Vector3] = []
		var rotations: Array[Quaternion] = []
		for bone: int in skeleton.get_bone_count():
			var pose := skeleton.get_bone_global_pose(bone)
			positions.append(pose.origin)
			rotations.append(pose.basis.get_rotation_quaternion())
		samples.append({"time": player.current_animation_position, "positions": positions, "rotations": rotations})
	hero.free()
	return samples
