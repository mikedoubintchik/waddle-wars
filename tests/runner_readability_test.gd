extends Node
## Focused semantic and optical bounds, not raster/performance acceptance.

class ContactPlayer:
	extends RunnerPlayer
	var contacts: Array[Area3D] = []
	func _overlapping_areas() -> Array[Area3D]:
		return contacts

var _passes := 0
var _failures := 0

func _ready() -> void:
	for entry: Dictionary in [
		{"name":"adjacent_lane_is_routine", "x":3.1, "y":0.0, "top":2.0, "bottom":0.0, "state":RunnerPlayer.State.RUN, "expected":0},
		{"name":"side_brush_is_close", "x":1.70, "y":0.0, "top":2.0, "bottom":0.0, "state":RunnerPlayer.State.RUN, "expected":1},
		{"name":"clear_jump_is_routine", "x":0.0, "y":1.4, "top":0.8, "bottom":0.0, "state":RunnerPlayer.State.JUMP, "expected":0},
		{"name":"tight_jump_is_close", "x":0.0, "y":0.84, "top":0.8, "bottom":0.0, "state":RunnerPlayer.State.JUMP, "expected":1},
		{"name":"normal_slide_is_routine", "x":0.0, "y":0.0, "top":1.6, "bottom":0.95, "state":RunnerPlayer.State.SLIDE, "expected":0},
		{"name":"tight_slide_is_close", "x":0.0, "y":0.04, "top":1.6, "bottom":0.95, "state":RunnerPlayer.State.SLIDE, "expected":1},
		{"name":"overlapping_geometry_is_not_a_miss", "x":1.4, "y":0.0, "top":2.0, "bottom":0.0, "state":RunnerPlayer.State.RUN, "expected":0},
		{"name":"ramp_is_not_a_near_miss", "x":1.7, "y":0.0, "top":2.0, "bottom":0.0, "state":RunnerPlayer.State.RUN, "expected":0, "kind":"ramp"},
	]:
		_test_pass(entry)
	_test_contact_rejection(false)
	_test_contact_rejection(true)
	_test_cooldown()
	_test_unobserved_pass()
	_test_powder_and_danger()
	await get_tree().process_frame
	print("[runner_readability] DONE: %d passed, %d failed" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _player(parent: Node) -> ContactPlayer:
	var player := ContactPlayer.new()
	parent.add_child(player)
	player.setup({})
	player.set_input_enabled(false)
	return player

func _hazard(parent: Node, x: float, bottom: float, top: float, kind: String = "block") -> Area3D:
	var area := Area3D.new()
	area.position.x = x
	parent.add_child(area)
	area.add_to_group(RunnerConfig.GROUP_HAZARD)
	area.set_meta("kind", kind)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.3, top - bottom, 1.6)
	shape.shape = box
	shape.position.y = (top + bottom) * 0.5
	area.add_child(shape)
	return area

func _test_pass(entry: Dictionary) -> void:
	var fixture := Node3D.new()
	add_child(fixture)
	var player := _player(fixture)
	player.state = int(entry["state"])
	if player.state == RunnerPlayer.State.SLIDE:
		player._set_height(RunnerConfig.SLIDE_HEIGHT)
	player.position.y = float(entry["y"])
	_hazard(fixture, float(entry["x"]), float(entry["bottom"]), float(entry["top"]), String(entry.get("kind", "block")))
	var count := {"misses":0}
	player.near_miss.connect(func() -> void: count["misses"] += 1)
	player.position.z = 2.0
	player._scan_near_miss(0.01)
	player.position.z = 0.0
	player._scan_near_miss(0.01)
	_check(count["misses"] == 0, String(entry["name"]) + "_never_announced_before_clear")
	player.position.z = -1.4
	player._scan_near_miss(0.01)
	_check(count["misses"] == int(entry["expected"]), String(entry["name"]))
	player._scan_near_miss(2.0)
	_check(count["misses"] == int(entry["expected"]), String(entry["name"]) + "_consumed_once")
	fixture.free()

func _test_contact_rejection(shielded: bool) -> void:
	var fixture := Node3D.new()
	add_child(fixture)
	var player := _player(fixture)
	var hazard := _hazard(fixture, 1.7, 0.0, 2.0)
	var count := {"misses":0}
	player.near_miss.connect(func() -> void: count["misses"] += 1)
	player._scan_near_miss(0.01)
	if shielded:
		player.powerups[RunnerConfig.POWERUP_SHIELD] = 5.0
	player.contacts.assign([hazard])
	player._resolve_overlaps()
	player.invulnerable_for = 0.0
	player.position.z = -1.4
	player._scan_near_miss(2.0)
	_check(count["misses"] == 0 and player.hits_left == (3 if shielded else 2),
		"shielded_contact_never_becomes_close" if shielded else "real_hit_never_becomes_close")
	fixture.free()

func _test_cooldown() -> void:
	var fixture := Node3D.new()
	add_child(fixture)
	var player := _player(fixture)
	var first := _hazard(fixture, 1.7, 0.0, 2.0)
	var count := {"misses":0}
	player.near_miss.connect(func() -> void: count["misses"] += 1)
	player._scan_near_miss(0.01)
	player.position.z = -1.4
	player._scan_near_miss(0.01)
	first.free()
	var second := _hazard(fixture, 1.7, 0.0, 2.0)
	second.position.z = -3.0
	player.position.z = -3.0
	player._scan_near_miss(0.05)
	player.position.z = -4.4
	player._scan_near_miss(0.05)
	_check(count["misses"] == 1, "closely_spaced_hazards_do_not_spam")
	player._scan_near_miss(2.0)
	_check(count["misses"] == 1, "suppressed_pass_does_not_arrive_later")
	fixture.free()

func _test_unobserved_pass() -> void:
	var fixture := Node3D.new()
	add_child(fixture)
	var player := _player(fixture)
	_hazard(fixture, 1.7, 0.0, 2.0)
	player.position.z = -1.4
	var count := {"misses":0}
	player.near_miss.connect(func() -> void: count["misses"] += 1)
	player._scan_near_miss(0.01)
	_check(count["misses"] == 0, "spawned_or_teleported_behind_is_not_a_miss")
	fixture.free()

func _test_powder_and_danger() -> void:
	for shape: Vector2i in [Vector2i(960, 540), Vector2i(540, 960)]:
		var viewport := SubViewport.new()
		viewport.size = shape
		viewport.own_world_3d = true
		add_child(viewport)
		var camera := Camera3D.new()
		viewport.add_child(camera)
		camera.position = Vector3(0.0, 3.1, 5.678635)
		camera.fov = 72.0
		camera.look_at(Vector3(0.0, 1.35, -12.0), Vector3.UP)
		camera.make_current()
		var chaser := RunnerChaser.new()
		viewport.add_child(chaser)
		chaser._build_intro_wave()
		# Real visual nodes, without a headless GPU setup dependency.
		chaser._face = MeshInstance3D.new()
		chaser.add_child(chaser._face)
		chaser._puffs = MultiMeshInstance3D.new()
		chaser.add_child(chaser._puffs)
		chaser._time = 120.0
		for gap: float in [34.0, 4.0]:
			chaser.gap = gap
			chaser.position.z = gap
			chaser._update_wall_visibility()
			_check(chaser._face.visible == (gap > 10.0) and chaser._puffs.visible == (gap > 10.0),
				"distant_wall_cannot_cross_camera_%s_gap%s" % [shape, gap])
			chaser.set_intro_preview(chaser.chase_preview_strength(120.0), 0.0, 0.016)
			var lip := chaser._intro_front
			var height := lip.texture.get_height() * lip.pixel_size * lip.scale.y
			var crest := camera.unproject_position(lip.global_position + Vector3.UP * height * 0.13)
			_check(crest.y >= float(shape.y) * 0.90, "powder_crest_stays_below_action_%s_gap%s" % [shape, gap])
			var opacity := 1.0 - (1.0 - lip.modulate.a) * (1.0 - chaser._intro_back.modulate.a)
			_check(opacity <= 0.56 and opacity >= 0.3, "powder_is_readable_translucent_threat_%s_gap%s" % [shape, gap])
		chaser.overrun()
		chaser.present_overrun(0.45)
		_check(not chaser._face.visible and not chaser._puffs.visible,
			"catch_uses_timed_snow_not_instant_camera_wall_%s" % shape)
		viewport.free()
	var hud := RunnerHUD.new()
	add_child(hud)
	hud.setup()
	hud._danger_veil = TextureRect.new()
	hud.add_child(hud._danger_veil)
	hud.set_stats(300.0, 0, 0, 1, 1, 0.0)
	var peak := 0.0
	for step: int in 180:
		hud._tick_danger(1.0 / 60.0)
		peak = maxf(peak, hud._danger_veil.modulate.a)
	_check(peak <= 0.27 and peak > 0.1, "worst_danger_edge_wash_capped_below_27_percent")
	_check(hud._gauge_tag.text == "AVALANCHE CLOSE!", "urgent_gap_warning_remains_explicit")
	hud._reduced = true
	hud._tick_danger(0.016)
	var steady := hud._danger_veil.modulate.a
	hud._tick_danger(0.9)
	_check(is_equal_approx(steady, hud._danger_veil.modulate.a) and steady <= 0.22,
		"reduced_motion_danger_is_steady_and_low_opacity")
	hud.free()

func _check(passed: bool, label: String) -> void:
	if passed: _passes += 1
	else: _failures += 1
	print("[runner_readability] %s %s" % ["PASS" if passed else "FAIL", label])
