extends Node
## Runtime lifecycle/cadence regression. Uses the imported rig, no save writes.
## Manual advancement is test-only; production retains automatic playback.

const HERO_SCENE := preload("res://assets/art/characters/hero_penguin_v1.tscn")

var _passes: int = 0
var _failures: int = 0


func _ready() -> void:
	var previous_qa_backend := PenguinVisual.use_authored_backend_for_qa
	_check(not previous_qa_backend, "production keeps unapproved authored backend disabled")
	# This fixture verifies the retained authored candidate deliberately; enabling
	# it here must never promote that model in gameplay or menu previews.
	PenguinVisual.use_authored_backend_for_qa = true
	_test_pre_tree_requests()
	_test_facade_rebuild()
	_test_legacy_cadence()
	_test_continuous_turn()
	# setup_look retires old children with queue_free. Drain them before exit.
	await get_tree().process_frame
	await get_tree().process_frame
	print("[hero_controller] DONE: %d passed, %d failed" % [_passes, _failures])
	PenguinVisual.use_authored_backend_for_qa = previous_qa_backend
	get_tree().quit(1 if _failures > 0 else 0)


func _test_pre_tree_requests() -> void:
	for request: Dictionary in [
		{"pose": PenguinVisual.Pose.RUN, "clip": &"run"},
		{"pose": PenguinVisual.Pose.CELEBRATE, "clip": &"celebration"},
		{"pose": PenguinVisual.Pose.DEFEAT, "clip": &"defeat"},
	]:
		var hero := HERO_SCENE.instantiate() as HeroPenguinRig
		hero.set_pose(int(request["pose"]))
		add_child(hero)
		var player := _player(hero)
		_check(player.assigned_animation == request["clip"],
				"pre-tree %s survives ready" % request["clip"])
		_check(player.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE,
				"production %s retains automatic idle callback" % request["clip"])
		hero.free()

	var hit_hero := HERO_SCENE.instantiate() as HeroPenguinRig
	hit_hero.set_pose(PenguinVisual.Pose.RUN)
	hit_hero.trigger_event(&"hit", {"side": -1.0})
	add_child(hit_hero)
	_check(_player(hit_hero).assigned_animation == &"hit_left",
			"pre-tree semantic one-shot survives ready")
	hit_hero.free()

	# Exact podium order: setup + celebration precede insertion into the world.
	var podium := PenguinVisual.new()
	podium.setup_look(_hero_look())
	podium.set_pose(PenguinVisual.Pose.CELEBRATE)
	add_child(podium)
	_check(_player(_rig(podium)).assigned_animation == &"celebration",
			"podium facade retains requested celebration after ready")
	podium.free()


func _test_facade_rebuild() -> void:
	var facade := _new_facade()
	facade.transform = Transform3D(Basis.from_euler(Vector3(0.1, 0.4, -0.2)),
			Vector3(12.0, 3.0, -8.0))
	facade.set_pose(PenguinVisual.Pose.RUN)
	facade.tick(0.01, 0.75)
	var transform_before := facade.transform
	var previous := _rig(facade)
	facade.setup_look(_hero_look("gentoo"))
	var replacement := _rig(facade)
	_check(replacement != previous, "look rebuild replaces backend")
	_check(previous.is_queued_for_deletion(), "look rebuild retires old backend")
	_check(facade.pose == PenguinVisual.Pose.RUN
			and _player(replacement).assigned_animation == &"run",
			"look rebuild preserves current facade pose")
	replacement.tick(0.01)
	_check(is_equal_approx(_player(replacement).speed_scale, lerpf(0.82, 1.42, 0.75)),
			"look rebuild preserves last supplied cadence")
	_check(facade.transform.is_equal_approx(transform_before),
			"look rebuild preserves gameplay transform")
	facade.free()


func _test_legacy_cadence() -> void:
	var facade := _new_facade()
	var hero := _rig(facade)
	var player := _player(hero)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	facade.set_pose(PenguinVisual.Pose.RUN)
	facade.transform = Transform3D(Basis.from_euler(Vector3(0.2, -0.3, 0.25)),
			Vector3(3.0, 4.0, 5.0))
	var before := facade.transform
	# This is the race/ghost caller API: set_pose + tick, no drive_motion.
	for ratio: float in [0.0, 0.4, 1.0, 1.5]:
		facade.set_pose(PenguinVisual.Pose.RUN)
		facade.tick(1.0 / 60.0, ratio)
		_check(is_equal_approx(player.speed_scale, lerpf(0.82, 1.42, minf(ratio, 1.0))),
				"legacy tick forwards cadence %.1f" % ratio)
	_check(facade.transform.is_equal_approx(before),
			"cadence forwarding leaves caller-owned banking/root unchanged")
	player.advance(0.0)
	player.advance(0.12)
	var position_before := player.current_animation_position
	for _index: int in 5:
		facade.set_pose(PenguinVisual.Pose.RUN)
	_check(is_equal_approx(position_before, player.current_animation_position),
			"repeated facade pose does not restart run")
	facade.trigger_event(&"hit", {"side": 1.0})
	facade.tick(0.05, 1.5)
	_check(player.assigned_animation == &"hit_right" and is_equal_approx(player.speed_scale, 1.0),
			"cadence update preserves semantic one-shot timing")
	for _index: int in 120:
		player.advance(1.0 / 60.0)
		facade.tick(1.0 / 60.0, 1.0)
	_check(player.assigned_animation == &"run", "semantic one-shot returns to run")
	facade.free()


func _test_continuous_turn() -> void:
	for fps: int in [30, 60]:
		var facade := _new_facade()
		var hero := _rig(facade)
		var player := _player(hero)
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var skeleton := hero.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var foot := -1
		for index: int in skeleton.get_bone_count():
			if skeleton.get_bone_name(index).begins_with("foot"):
				foot = index
				break
		_check(foot >= 0, "%d FPS imported foot exists" % fps)
		if foot < 0:
			facade.free()
			continue
		facade.set_pose(PenguinVisual.Pose.RUN)
		player.advance(0.0)
		# Feet now follow whole-body weight transfer, rather than separate local
		# paddling. Measure their actual global motion through the hierarchy.
		var initial_foot := skeleton.get_bone_global_pose(foot).basis.get_rotation_quaternion()
		var foot_span := 0.0
		var time_advanced := false
		var stayed_running := true
		var before := facade.position
		for frame: int in fps:
			var turn := 1.0 if frame < fps / 2 else -1.0
			facade.set_pose(PenguinVisual.Pose.RUN)
			facade.drive_motion(1.0, turn, 0.0, 0.0, true)
			facade.tick(1.0 / float(fps), 1.0)
			player.advance(1.0 / float(fps))
			stayed_running = stayed_running and player.assigned_animation == &"run"
			time_advanced = time_advanced or player.current_animation_position > 0.05
			foot_span = maxf(foot_span, initial_foot.angle_to(
					skeleton.get_bone_global_pose(foot).basis.get_rotation_quaternion()))
		_check(stayed_running, "%d FPS sustained turn never takes over run clip" % fps)
		_check(time_advanced, "%d FPS sustained turn advances AnimationPlayer" % fps)
		_check(foot_span > deg_to_rad(2.0), "%d FPS sustained turn keeps feet following body" % fps)
		_check(facade.position.is_equal_approx(before), "%d FPS turn does not apply root motion" % fps)
		_check(hero.animation_names().has("lean_left") and hero.animation_names().has("lean_right"),
				"%d FPS authored lean clips remain available" % fps)
		facade.free()


func _hero_look(species: String = "emperor") -> CharacterLook:
	return CharacterLook.from_legacy_config({"species": species}, CharacterLook.RenderRole.HERO)


func _new_facade() -> PenguinVisual:
	var facade := PenguinVisual.new()
	add_child(facade)
	facade.setup_look(_hero_look())
	return facade


func _rig(facade: PenguinVisual) -> HeroPenguinRig:
	return facade.get("_authored_backend") as HeroPenguinRig


func _player(hero: HeroPenguinRig) -> AnimationPlayer:
	return hero.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer


func _check(success: bool, label: String) -> void:
	if success:
		_passes += 1
		print("[hero_controller] PASS %s" % label)
	else:
		_failures += 1
		push_error("[hero_controller] FAIL %s" % label)
