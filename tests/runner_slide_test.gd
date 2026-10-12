extends Node
## Exercise input intent, uninterrupted slides and real production bar colliders.
## Physics shape queries sample the exact player capsule at both 30 and 60 FPS;
## the static course is synchronized once, with no wall-clock replay dependency.

var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	RunnerPlayer.autopilot = false
	_test_single_vfx_owner()
	_test_taps_and_landing()
	await _test_keyboard_hold()
	for run_speed: float in [RunnerConfig.START_SPEED, RunnerConfig.MAX_SPEED]:
		for fps: int in [30, 60]:
			for held: bool in [false, true]:
				await _test_bar_chain(run_speed, fps, held)
	await _test_same_frame_overlap_boundary()
	await _test_dense_transition_contacts()
	Input.action_release(&"slide")
	print("[runner_slide] DONE: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(label: String, success: bool) -> void:
	_checks += 1
	if not success:
		_failures += 1
		push_error("[runner_slide] FAIL " + label)


func _player() -> RunnerPlayer:
	var player := RunnerPlayer.new()
	add_child(player)
	return player


func _events(player: RunnerPlayer) -> Array[StringName]:
	var events: Array[StringName] = []
	player.presentation_event.connect(func(id: StringName, _context: Dictionary) -> void:
		events.append(id))
	return events


func _test_single_vfx_owner() -> void:
	var player_script := load("res://scripts/runner/runner_player.gd") as GDScript
	var game_script := load("res://scripts/runner/runner_game.gd") as GDScript
	_check("one_game_owned_vfx_pool", player_script.source_code.count("RunnerVfx.new()") == 0
		and game_script.source_code.count("RunnerVfx.new()") == 1)


func _test_taps_and_landing() -> void:
	var player := _player()
	var events := _events(player)
	player.slide()
	player._advance_slide(RunnerConfig.SLIDE_TIME - 0.1)
	player.slide()
	player._advance_slide(0.2)
	_check("early_second_swipe_extends_slide", player.state == RunnerPlayer.State.SLIDE)
	_check("retrigger_keeps_low_hitbox", player._height == RunnerConfig.SLIDE_HEIGHT)
	_check("retrigger_has_no_exit_or_duplicate_enter", events == [RunnerPlayer.PRESENT_SLID])
	player._advance_slide(RunnerConfig.SLIDE_TIME)
	_check("unheld_retrigger_still_expires", player.state == RunnerPlayer.State.RUN
		and player._height == RunnerConfig.STAND_HEIGHT)
	player._advance_slide(1.0)
	_check("tap_does_not_restart_automatically", events == [
		RunnerPlayer.PRESENT_SLID, RunnerPlayer.PRESENT_SLIDE_EXIT])

	player.jump()
	player._advance_vertical(0.1)
	player.slide()
	_check("airborne_slide_fast_falls", player._vertical < 0.0)
	player._advance_vertical(0.3)
	_check("airborne_slide_starts_on_landing", player.state == RunnerPlayer.State.SLIDE
		and is_zero_approx(player.position.y) and player._height == RunnerConfig.SLIDE_HEIGHT)
	_check("landing_precedes_slide_entry", events.slice(-2) == [
		RunnerPlayer.PRESENT_LANDED, RunnerPlayer.PRESENT_SLID])
	player._advance_slide(RunnerConfig.SLIDE_TIME + 0.1)
	player.jump()
	player._advance_vertical(1.0)
	_check("landing_request_consumed_once", player.state == RunnerPlayer.State.RUN)

	player.jump()
	player.slide()
	player.launch(RunnerConfig.RAMP_LAUNCH)
	player._advance_vertical(2.0)
	_check("ramp_cancels_pending_slide", player.state == RunnerPlayer.State.RUN)
	player.jump()
	player.slide()
	player.set_input_enabled(false)
	player._advance_vertical(1.0)
	player.slide()
	_check("disabled_input_clears_and_rejects_slide", player.state == RunnerPlayer.State.RUN)
	player.set_input_enabled(true)
	player.slide()
	player.kill()
	player.slide()
	_check("slide_cannot_revive_dead_player", player.state == RunnerPlayer.State.DEAD)
	player.free()


func _test_keyboard_hold() -> void:
	var player := _player()
	Input.action_press(&"slide")
	player._read_input()
	await get_tree().process_frame
	await get_tree().process_frame
	player._advance_slide(RunnerConfig.SLIDE_TIME * 5.0)
	_check("held_action_stays_down_through_long_chain", player.state == RunnerPlayer.State.SLIDE)
	Input.action_release(&"slide")
	player._read_input()
	player._advance_slide(1.0 / 60.0)
	_check("release_after_minimum_exits_immediately", player.state == RunnerPlayer.State.RUN)

	Input.action_press(&"slide")
	player._read_input()
	Input.action_release(&"slide")
	player._read_input()
	player._advance_slide(RunnerConfig.SLIDE_TIME * 0.5)
	_check("quick_release_preserves_tap_window", player.state == RunnerPlayer.State.SLIDE)
	player._advance_slide(RunnerConfig.SLIDE_TIME)
	_check("quick_release_eventually_exits", player.state == RunnerPlayer.State.RUN)

	Input.action_press(&"slide")
	player._read_input()
	await get_tree().process_frame
	await get_tree().process_frame
	player.jump()
	var takeoff := player._vertical
	player._read_input()
	_check("jump_cancels_hold_without_fast_fall", player.state == RunnerPlayer.State.JUMP
		and player._vertical == takeoff)
	player._advance_vertical(1.0)
	player._read_input()
	_check("held_button_does_not_restart_after_jump", player.state == RunnerPlayer.State.RUN)
	player.set_input_enabled(false)
	player.set_input_enabled(true)
	player._read_input()
	_check("held_button_does_not_queue_across_disabled_input", player.state == RunnerPlayer.State.RUN)
	Input.action_release(&"slide")
	player._read_input()
	Input.action_press(&"slide")
	player._read_input()
	_check("fresh_press_rearms_after_jump", player.state == RunnerPlayer.State.SLIDE)
	player.move_lane(1)
	player._advance_lane(RunnerConfig.LANE_CHANGE_TIME)
	_check("lane_changes_remain_available_while_sliding", player.lane == 2
		and is_equal_approx(player.position.x, RunnerConfig.lane_x(2)))
	Input.action_release(&"slide")
	player.free()
	await get_tree().process_frame


func _test_bar_chain(run_speed: float, fps: int, held: bool) -> void:
	var label := "%.0fmps_%dfps_%s" % [run_speed, fps, "hold" if held else "swipes"]
	var track := RunnerTrack.new()
	track._headless = true
	track._lane_jump_z = PackedFloat32Array([1.0e9, 1.0e9, 1.0e9])
	track._lane_slide_z = PackedFloat32Array([1.0e9, 1.0e9, 1.0e9])
	add_child(track)
	var chunk := RunnerTrack.RunnerChunk.new()
	track.add_child(chunk)
	var first_bar := run_speed * 0.35
	var last_bar := first_bar + RunnerTrack.ROW_GAP_HARD * 7.0
	var placed := 0
	for index: int in 8:
		if track._add_obstacle(chunk, RunnerTrack.Kind.BAR, 0,
				RunnerConfig.LANE_COUNT, -first_bar - RunnerTrack.ROW_GAP_HARD * float(index)):
			placed += 1
	_check(label + "_eight_production_bars", placed == 8)
	var player := _player()
	player.setup({})
	var events := _events(player)
	# Synchronize the static production colliders before deterministic queries.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if held:
		# action_press schedules its physics edge for the NEXT physics tick.
		# Inject and consume in process_frame, as RunnerGame does, rather than
		# losing that edge by reading inside the fixture's physics_frame await.
		await get_tree().process_frame
		Input.action_press(&"slide")
		player._read_input()
		_check(label + "_hold_input_started", Input.is_action_pressed(&"slide")
			and player.state == RunnerPlayer.State.SLIDE and player._slide_held)
		await get_tree().process_frame
		await get_tree().process_frame
	else:
		player.slide()
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = player._capsule
	query.collision_mask = RunnerTrack.HAZARD_LAYER
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var space := player.get_world_3d().direct_space_state
	var contacts := 0
	var upright_frames := 0
	var frames := ceili((last_bar + 2.0) / run_speed * float(fps))
	var retrigger_frames := roundi(float(fps) * 0.5)
	for frame: int in frames:
		# A fresh swipe every half second is deliberately EARLIER than expiry.
		if not held and frame > 0 and frame % retrigger_frames == 0:
			player.slide()
		player.tick(1.0 / float(fps), run_speed)
		query.transform = player._shape.global_transform
		contacts += space.intersect_shape(query).size()
		if player.state != RunnerPlayer.State.SLIDE:
			upright_frames += 1
	_check(label + "_all_bars_cleared", contacts == 0)
	_check(label + "_no_upright_frame", upright_frames == 0)
	_check(label + "_one_slide_entry_no_flicker", events.count(RunnerPlayer.PRESENT_SLID) == 1
		and not RunnerPlayer.PRESENT_SLIDE_EXIT in events)
	# Positive control: same real capsule at the final bar must hit upright.
	Input.action_release(&"slide")
	player._read_input()
	player._advance_slide(RunnerConfig.SLIDE_TIME + 0.1)
	player.position.z = -last_bar
	query.transform = player._shape.global_transform
	_check(label + "_upright_collision_preserved", not space.intersect_shape(query).is_empty())
	_check(label + "_release_has_one_exit", events.count(RunnerPlayer.PRESENT_SLIDE_EXIT) == 1)
	player.free()
	track.free()
	await get_tree().process_frame


func _test_same_frame_overlap_boundary() -> void:
	# Keep a real bar and capsule stationary while physics publishes its area
	# cache, then change height and resolve damage BEFORE another physics tick.
	# This covers what a same-frame input must do, independent of query tests.
	var track := RunnerTrack.new()
	track._headless = true
	track._lane_jump_z = PackedFloat32Array([1.0e9, 1.0e9, 1.0e9])
	track._lane_slide_z = PackedFloat32Array([1.0e9, 1.0e9, 1.0e9])
	add_child(track)
	var chunk := RunnerTrack.RunnerChunk.new()
	track.add_child(chunk)
	_check("boundary_production_bar_placed", track._add_obstacle(chunk,
		RunnerTrack.Kind.BAR, 0, RunnerConfig.LANE_COUNT, -10.0))
	var player := _player()
	player.setup({})
	player.position.z = -10.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	var standing_cache := player._area.get_overlapping_areas().size()
	_check("boundary_standing_overlap_published", standing_cache > 0)
	player.slide()
	player._resolve_overlaps()
	var entry_hits := RunnerConfig.MAX_HITS - player.hits_left
	_check("same_frame_slide_avoids_cached_standing_hit", entry_hits == 0)
	player._resolve_overlaps()
	_check("repeated_resolve_before_physics_stays_clear", player.hits_left == RunnerConfig.MAX_HITS)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	var sliding_cache := player._area.get_overlapping_areas().size()
	_check("boundary_sliding_overlap_cleared", sliding_cache == 0)
	_check("settled_slide_returns_to_cached_overlaps",
		player._shape_changed_physics_frame < Engine.get_physics_frames()
		and player._overlapping_areas().is_empty())
	player.hits_left = RunnerConfig.MAX_HITS
	player.invulnerable_for = 0.0
	player._advance_slide(RunnerConfig.SLIDE_TIME + 0.1)
	player._resolve_overlaps()
	var exit_hits := RunnerConfig.MAX_HITS - player.hits_left
	_check("same_frame_slide_exit_hits_overhead_bar", exit_hits == 1)
	print("[runner_slide] boundary standing_cache=%d sliding_cache=%d entry_hits=%d exit_hits=%d" % [
		standing_cache, sliding_cache, entry_hits, exit_hits])
	player.free()
	track.free()
	await get_tree().process_frame


func _test_dense_transition_contacts() -> void:
	var track := RunnerTrack.new()
	track._headless = true
	add_child(track)
	var chunk := RunnerTrack.RunnerChunk.new()
	track.add_child(chunk)
	_check("dense_fixture_block_placed", track._add_obstacle(chunk,
		RunnerTrack.Kind.BLOCK, 1, 1, -10.0))
	for _index: int in 40:
		track._add_fish(chunk, Vector3(0.0, 0.45, -10.0))
	# A collider may expose multiple shapes. Keep the same unique Area3D
	# semantics as the normal overlap cache, even with more than 32 hits.
	var fish := chunk.fish_nodes[0] as Area3D
	fish.add_child(fish.get_child(0).duplicate())
	var body := StaticBody3D.new()
	body.collision_layer = RunnerTrack.HAZARD_LAYER
	body.position = Vector3(0.0, 0.45, -10.0)
	var body_shape := CollisionShape3D.new()
	body_shape.shape = SphereShape3D.new()
	body.add_child(body_shape)
	track.add_child(body)
	var player := _player()
	player.setup({})
	player.position.z = -10.0
	var collected: Array[int] = []
	player.fish_collected.connect(func(value: int) -> void: collected.append(value))
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	player.slide()
	var contacts := player._overlapping_areas()
	_check("dense_transition_keeps_all_unique_areas_excludes_bodies", contacts.size() == 41)
	player._resolve_overlaps()
	_check("dense_transition_collects_every_pickup_once", collected.size() == 40)
	_check("dense_transition_keeps_block_damage", player.hits_left == RunnerConfig.MAX_HITS - 1)
	player.free()
	track.free()
	await get_tree().process_frame
