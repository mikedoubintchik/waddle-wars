extends Node
## Real production player, persisted GLB and materials; no QA replacement rig.

var passed := 0
var failed := 0


func _ready() -> void:
	RunnerPlayer.autopilot = false
	_test_floor_selection()
	_test_countdown_floor()
	_test_runtime_player()
	_test_supported_looks()
	print("[reviewed_runner_penguin] %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)


func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error("[reviewed_runner_penguin] " + label)


func _player(config: Dictionary = {}) -> RunnerPlayer:
	var player := RunnerPlayer.new()
	add_child(player)
	player.setup(config)
	player.set_input_enabled(false)
	return player


func _visible_meshes(root: Node3D) -> int:
	var count := 0
	for raw: Node in root.find_children("*", "MeshInstance3D", true, false):
		if (raw as MeshInstance3D).is_visible_in_tree():
			count += 1
	return count


func _test_runtime_player() -> void:
	var player := _player()
	var visual := player._visual
	_check(visual.has_reviewed_runner_backend(), "default classic runner selects reviewed model")
	if not visual.has_reviewed_runner_backend():
		player.free()
		return
	var rig := visual._runner_backend
	var reviewed_height := RunnerCameraComposition.authored_height(visual)
	_check(is_equal_approx(reviewed_height, 1.05), "camera measures reviewed rest height instead of legacy fallback")
	var fallback_scale := visual._scale_root.scale
	visual._scale_root.scale *= 10.0
	_check(is_equal_approx(RunnerCameraComposition.authored_height(visual), reviewed_height),
		"hidden procedural fallback cannot inflate reviewed camera height")
	visual._scale_root.scale = fallback_scale
	_check(FileAccess.get_sha256(ReviewedRunnerPenguin.MODEL_PATH) == ReviewedRunnerPenguin.MODEL_SHA256,
		"runtime GLB equals reviewed source bytes")
	_check(rig.scale.is_equal_approx(Vector3.ONE * ReviewedRunnerPenguin.GAME_SCALE), "reviewed physical scale")
	_check(_visible_meshes(visual) == 1 and not visual._scale_root.visible,
		"one visible skinned mesh, hidden procedural fallback")
	var mesh := rig.model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var material := mesh.get_active_material(0) as StandardMaterial3D
	_check(mesh.material_override == null and mesh.material_overlay == null
		and mesh.get_surface_override_material(0) == null, "no material substitution or overlay")
	_check(material != null and is_equal_approx(material.metallic_specular, 0.15)
		and is_equal_approx(material.normal_scale, 0.65), "reviewed specular and normal scale")
	for slot: int in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ROUGHNESS]:
		var texture := material.get_texture(slot) as PortableCompressedTexture2D
		var exact := texture != null
		if exact:
			var persisted := texture.get_image()
			var regenerated: Image = persisted.duplicate()
			regenerated.clear_mipmaps()
			exact = persisted.get_size() == Vector2i(1024, 1024) and persisted.has_mipmaps() \
				and texture.get_compression_mode() == PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS \
				and regenerated.generate_mipmaps(slot == BaseMaterial3D.TEXTURE_NORMAL) == OK \
				and regenerated.get_data() == persisted.get_data()
		_check(exact, "source-preserving normal-aware lossless mip chain, slot " + str(slot))
	var binding: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/characters/runner_penguin_v1.json"))
	_check(rig.skeleton.get_bone_count() == 15, "fresh fifteen-bone skeleton")
	for name: String in ReviewedRunnerPenguin.CLIPS:
		var clip := rig.animation.get_animation(name)
		var expected: Dictionary = binding.clips[name]
		var tracks_exact: bool = clip.get_track_count() == expected.tracks.size()
		for track: int in clip.get_track_count():
			var property: String = {Animation.TYPE_POSITION_3D: "translation", Animation.TYPE_ROTATION_3D: "rotation", Animation.TYPE_SCALE_3D: "scale"}.get(clip.track_get_type(track), "")
			var bone := String(clip.track_get_path(track).get_subname(0))
			for source: Dictionary in expected.tracks:
				if source.joint == bone and source.path == property and not source.constant:
					tracks_exact = tracks_exact and clip.track_get_key_count(track) == source.keys
		_check(tracks_exact and is_equal_approx(clip.length, expected.duration)
			and clip.loop_mode == (Animation.LOOP_LINEAR if expected.loop else Animation.LOOP_NONE),
			"unoptimized source keys and clip contract " + name)
	visual.set_runner_floor_height(0.022)
	var seated := rig.position
	var physics_origin := player.position
	visual.set_pose(PenguinVisual.Pose.RUN)
	for frame: int in 12:
		player._drive_visual(1.0 / 60.0)
		_check(_visible_meshes(visual) == 1, "ordinary live tick cannot reveal original, frame " + str(frame))
	_check(rig.action == "waddle" and rig.animation.current_animation_position > 0.0,
		"live player advances strong authored waddle")
	_check(player.position == physics_origin, "articulation never moves physics root")
	player.jump()
	player._vertical = 0.0
	player.position.y = 1.0
	player._drive_visual(0.20)
	rig.skeleton.force_update_all_bone_transforms()
	var torso := rig.skeleton.find_bone("torso")
	var deformation := rig.skeleton.get_bone_global_pose(torso) * rig.skeleton.get_bone_global_rest(torso).affine_inverse()
	_check(rig.action == "jump" and is_equal_approx(rig.phase, 0.5), "jump phase follows gameplay apex velocity")
	_check(deformation.basis.get_euler().x < deg_to_rad(-20.0), "authored forward lean survives live jump adapter")
	_check(rig.position.is_equal_approx(seated) and is_equal_approx(player.position.y, 1.0),
		"jump adds no second ballistic height")
	_check(is_zero_approx(visual.rotation.x), "facade does not counter-tilt authored airborne lean")
	player.set_input_enabled(true)
	player.slide()
	player._drive_visual(1.0 / 60.0)
	_check(rig.phase > 0.7 and player.state == RunnerPlayer.State.JUMP, "fast-fall updates actual airborne articulation")
	player.position.y = 0.001
	player._advance_vertical(0.05)
	player._drive_visual(0.20)
	var expected_slide_capsule := maxf(RunnerConfig.SLIDE_HEIGHT, player._capsule.radius * 2.0 + 0.01)
	_check(player.state == RunnerPlayer.State.SLIDE and rig.action == "slide"
		and is_equal_approx(player._height, RunnerConfig.SLIDE_HEIGHT)
		and is_equal_approx(player._capsule.height, expected_slide_capsule), "queued slide enters with unchanged collider")
	var first_slide_time := rig.animation.current_animation_position
	player.slide()
	player._drive_visual(0.05)
	_check(rig.animation.current_animation_position > first_slide_time, "repeated slide extends state without restarting feet")
	var moving_bones: Dictionary = {}
	for bone: String in ["foot_L", "foot_R", "flipper_L", "flipper_R"]:
		moving_bones[bone] = rig.skeleton.get_bone_global_pose(rig.skeleton.find_bone(bone))
	player._drive_visual(0.30)
	rig.skeleton.force_update_all_bone_transforms()
	for bone: String in moving_bones:
		_check(not rig.skeleton.get_bone_global_pose(rig.skeleton.find_bone(bone)).is_equal_approx(moving_bones[bone]),
			"slide preserves independent moving " + bone)
	player.launch(RunnerConfig.RAMP_LAUNCH)
	_check(is_equal_approx(rig.animation.get_playing_speed(), RunnerConfig.GRAVITY / (2.0 * RunnerConfig.RAMP_LAUNCH)),
		"ramp selects actual flight playback rate once")
	player._vertical = 0.0
	player._drive_visual(0.2)
	_check(rig.action == "jump" and is_equal_approx(rig.phase, 0.5) and visual.is_reviewed_runner_visible(),
		"ramp uses same penguin and normalized actual flight")
	_check(absf(player.rotation.x) > 0.0 and rig.position.is_equal_approx(seated), "ramp roll remains player-owned")
	player._launched = false
	player.state = RunnerPlayer.State.RUN
	player.position.y = 0.0
	player._emit_presentation(RunnerPlayer.PRESENT_LANDED)
	player._drive_visual(0.12)
	_check(rig.action == "waddle", "landing returns to waddle")
	player.take_hit(1.0)
	player._drive_visual(0.05)
	_check(visual.is_reviewed_runner_visible() and rig.model.rotation.length() > 0.001,
		"ordinary impact retains model with visible response")
	_check(mesh.get_active_material(0) == material, "every live action preserves imported material identity")
	player.kill()
	player._drive_visual(0.20)
	_check(rig.action == "slide" and visual.is_reviewed_runner_visible(), "rear death remains reviewed penguin")
	visual.present_catch_face(1.0)
	visual.set_pose(PenguinVisual.Pose.SLIDE)
	player._drive_visual(0.10)
	_check(not visual.is_reviewed_runner_visible() and visual._scale_root.visible,
		"explicit front catch uses finished face fallback without duplicate")
	_check(is_zero_approx(RunnerCameraComposition.authored_height(visual)),
		"hidden reviewed model cannot claim active front fallback camera height")
	var report := visual.reviewed_runner_snapshot()
	_check(report.active and report.front_fallback and report.procedural_visible_meshes > 0
		and report.renderer.model_path == ReviewedRunnerPenguin.MODEL_PATH, "snapshot reports actual renderer and fallback")
	player.free()


func _test_supported_looks() -> void:
	for config: Dictionary in [{"species": "king"}, {"hat": "hat_beanie"}, {"scarf": "scarf_red"}, {"goggles": "goggles_ski"}]:
		var player := _player(config)
		_check(not player._visual.has_reviewed_runner_backend() and _visible_meshes(player._visual) > 0,
			"unsupported species/accessory remains visible " + str(config))
		player.free()
	var race := PenguinVisual.new()
	add_child(race)
	race.setup_look(CharacterLook.from_legacy_config({}, CharacterLook.RenderRole.HERO))
	_check(not race.has_reviewed_runner_backend(), "race and podium setup does not silently change model")
	race.free()


func _test_floor_selection() -> void:
	var track := Node3D.new()
	var deck := MeshInstance3D.new()
	deck.name = "Deck"
	deck.mesh = PlaneMesh.new()
	track.add_child(deck)
	var ice := MeshInstance3D.new()
	ice.name = "GlacialIceSkin"
	ice.mesh = PlaneMesh.new()
	ice.position.y = 0.022
	track.add_child(ice)
	_check(is_equal_approx(ReviewedRunnerPenguin.floor_height_at(track, Vector3.ZERO), 0.022), "visible authored ice wins over collision-height deck")
	ice.visible = false
	_check(is_zero_approx(ReviewedRunnerPenguin.floor_height_at(track, Vector3.ZERO)), "procedural deck keeps actual zero height")
	ice.visible = true
	ice.position.x = 20.0
	_check(is_zero_approx(ReviewedRunnerPenguin.floor_height_at(track, Vector3.ZERO)), "nearby raised floor cannot offset player")
	track.free()


func _test_countdown_floor() -> void:
	# Detached game avoids startup/save/render work, but uses the real setup
	# order and countdown branch. Neither calls player.tick() before GO.
	for floor_y: float in [0.022, 0.0]:
		var game := RunnerGame.new()
		game.track = RunnerTrack.new()
		game.add_child(game.track)
		var floor_mesh := MeshInstance3D.new()
		floor_mesh.name = "GlacialIceSkin" if floor_y > 0.0 else "Deck"
		floor_mesh.mesh = PlaneMesh.new()
		floor_mesh.position.y = floor_y
		game.track.add_child(floor_mesh)
		game.player = RunnerPlayer.new()
		game.add_child(game.player)
		game.player.setup({})
		game.player.set_input_enabled(false)
		var rig := game.player._visual._runner_backend
		_check(rig != null, "countdown selects reviewed model at floor " + str(floor_y))
		if rig == null:
			game.free()
			continue
		var sole_y := rig.position.y + rig._rest_sole_y * rig.scale.y
		_check(is_equal_approx(sole_y, floor_y) and is_zero_approx(game.player.position.y),
			"setup seats soles before first tick without lifting physics, floor " + str(floor_y))
		var player_transform := game.player.transform
		var capsule_height := game.player._capsule.height
		var initial_rig_position := rig.position
		game._presentation_started = true
		game._countdown = RunnerGame.COUNTDOWN_TIME
		for frame: int in 3:
			game._process(0.1)
		_check(game._countdown < RunnerGame.COUNTDOWN_TIME and not game.running
			and rig.action == "idle" and is_zero_approx(rig.animation.current_animation_position)
			and rig.position == initial_rig_position and is_equal_approx(sole_y, floor_y)
			and game.player.transform == player_transform and is_equal_approx(game.player._capsule.height, capsule_height),
			"countdown preserves seated idle and unchanged physics, floor " + str(floor_y))
		game.free()
