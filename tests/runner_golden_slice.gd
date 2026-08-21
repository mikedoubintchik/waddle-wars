extends Node
## Deterministic runner presentation contract.
##
##   godot --headless --path . res://tests/runner_golden_slice.tscn

const GOLDEN_SEED: int = 20260818

var _passes: int = 0
var _failures: int = 0
var _events: Array[Dictionary] = []


class TestFish:
	extends Area3D
	var _taken: bool = false

	func collect() -> int:
		if _taken:
			return 0
		_taken = true
		return 1


class TestPowerup:
	extends Area3D
	var id: StringName = RunnerConfig.POWERUP_MAGNET
	var _taken: bool = false

	func collect() -> StringName:
		if _taken:
			return &""
		_taken = true
		return id


func _ready() -> void:
	print("[runner_golden] deterministic contract starting")
	await _test_art_rng_independence()
	await _test_golden_content()
	await _test_presentation_events()
	await _test_layout_and_retry()
	print("[runner_golden] DONE: %d passed, %d failed" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passes += 1
		print("[runner_golden] PASS %s" % label)
		return
	_failures += 1
	print("[runner_golden] FAIL %s%s" % [label,
			": %s" % detail if not detail.is_empty() else ""])


func _fresh_normal_track(logic_only: bool) -> RunnerTrack:
	var track := RunnerTrack.new()
	track.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(track)
	track._headless = logic_only
	track._seed = GOLDEN_SEED
	track._golden_slice = false
	track._clear()
	if not logic_only:
		track._prime_art_cache()
	for index: int in 12:
		track._spawn_chunk(index, 0.72)
	return track


func _test_art_rng_independence() -> void:
	var logic := _fresh_normal_track(true)
	var rendered := _fresh_normal_track(false)
	var logic_signature := _gameplay_signature(logic)
	var rendered_signature := _gameplay_signature(rendered)
	_check("art_rng_does_not_change_gameplay", logic_signature == rendered_signature,
			"logic=%d rendered=%d" % [logic_signature.size(), rendered_signature.size()])
	logic.queue_free()
	rendered.queue_free()
	await get_tree().process_frame


func _gameplay_signature(root: Node) -> PackedStringArray:
	var rows := PackedStringArray()
	for raw: Node in root.find_children("*", "Node3D", true, false):
		var node := raw as Node3D
		if node.is_in_group(RunnerConfig.GROUP_HAZARD):
			rows.append("H|%s|%d|%d|%.3f|%.3f|%.3f" % [
					String(node.get_meta("kind", "")), int(node.get_meta("lane", -1)),
					int(node.get_meta("span", 1)), node.global_position.x,
					node.global_position.y, node.global_position.z])
		elif node.is_in_group(RunnerConfig.GROUP_PICKUP):
			rows.append("F|%.3f|%.3f|%.3f" % [node.global_position.x,
					node.global_position.y, node.global_position.z])
		elif node.is_in_group(RunnerConfig.GROUP_POWERUP):
			rows.append("P|%s|%.3f|%.3f|%.3f" % [
					String(node.get_meta("powerup", &"")), node.global_position.x,
					node.global_position.y, node.global_position.z])
	rows.sort()
	return rows


func _test_golden_content() -> void:
	var track := RunnerTrack.new()
	track.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(track)
	track.setup_golden_slice(GOLDEN_SEED, 0)
	_check("golden_exactly_360m", track._chunks.size() == RunnerTrack.GOLDEN_SLICE_CHUNKS
			and is_equal_approx(RunnerTrack.GOLDEN_SLICE_LENGTH, 360.0))
	var patterns: Dictionary = {}
	var all_day := true
	var safe_rows := true
	for chunk: RunnerTrack.RunnerChunk in track._chunks:
		patterns[int(chunk.get_meta("golden_pattern", -1))] = true
		all_day = all_day and chunk.biome == RunnerTrack.Biome.DAY
		for blocked: Variant in chunk.rows.values():
			safe_rows = safe_rows and int(blocked) < RunnerConfig.LANE_COUNT
	_check("golden_all_patterns", patterns.size() == RunnerTrack.Pattern.size(), str(patterns.keys()))
	_check("golden_day_locked", all_day)
	_check("golden_never_blocks_all_lanes", safe_rows)

	var kinds: Dictionary = {}
	var powerups: Dictionary = {}
	var fish_count := 0
	for raw: Node in track.find_children("*", "Node3D", true, false):
		if raw.is_in_group(RunnerConfig.GROUP_HAZARD):
			kinds[String(raw.get_meta("kind", ""))] = true
		elif raw.is_in_group(RunnerConfig.GROUP_PICKUP):
			fish_count += 1
		elif raw.is_in_group(RunnerConfig.GROUP_POWERUP):
			powerups[String(raw.get_meta("powerup", &""))] = true
	_check("golden_every_obstacle_family",
			kinds.has("block") and kinds.has("bar") and kinds.has("low")
			and kinds.has("seal") and kinds.has("ramp"), str(kinds.keys()))
	_check("golden_has_pickup_lines", fish_count >= 20, "fish=%d" % fish_count)
	_check("golden_all_powerups", powerups.size() == RunnerConfig.POWERUP_IDS.size(),
			str(powerups.keys()))
	var before := track._chunks.size()
	track.update_stream(-2000.0, 1.0)
	_check("golden_stream_is_fixed", track._chunks.size() == before)
	track.queue_free()
	await get_tree().process_frame


func _test_presentation_events() -> void:
	_events.clear()
	var player := RunnerPlayer.new()
	add_child(player)
	player.setup({"species": "gentoo"})
	player.presentation_event.connect(func(event_id: StringName, context: Dictionary) -> void:
		_events.append({"id": event_id, "context": context.duplicate(true)}))

	player.move_lane(-1)
	player.jump()
	for _step: int in 180:
		player._advance_vertical(1.0 / 120.0)
		if player.state == RunnerPlayer.State.RUN:
			break
	player.slide()
	player._advance_slide(RunnerConfig.SLIDE_TIME + 0.01)

	var fish := TestFish.new()
	_make_test_overlap(fish, RunnerConfig.GROUP_PICKUP, player.global_position + Vector3.UP * 0.65)
	var crate := TestPowerup.new()
	_make_test_overlap(crate, RunnerConfig.GROUP_POWERUP, player.global_position + Vector3.UP * 0.65)
	await get_tree().physics_frame
	await get_tree().physics_frame
	player._resolve_overlaps()

	player.powerups[RunnerConfig.POWERUP_MAGNET] = 0.001
	player._advance_powerups(0.01)
	var near := Node3D.new()
	near.add_to_group(RunnerConfig.GROUP_HAZARD)
	add_child(near)
	near.global_position = player.global_position + Vector3(1.5, 0.0, 0.8)
	player._scan_near_miss(0.01)
	player.launch(RunnerConfig.RAMP_LAUNCH)
	player.position.y = 0.01
	player._vertical = -1.0
	player._advance_vertical(0.02)
	player.grant_powerup(RunnerConfig.POWERUP_SHIELD)
	player.take_hit(-1.5, player.global_position + Vector3.LEFT * 1.5)
	player.invulnerable_for = 0.0
	player.take_hit(1.5, player.global_position + Vector3.RIGHT * 1.5)
	player.invulnerable_for = 0.0
	player.hits_left = 1
	player.take_hit(-1.0, player.global_position + Vector3.LEFT)

	var ids: Dictionary = {}
	var canonical := true
	for row: Dictionary in _events:
		ids[row["id"]] = int(ids.get(row["id"], 0)) + 1
		var context: Dictionary = row["context"]
		canonical = canonical and context.get("world_position") is Vector3 \
				and context.get("side") is float and context.get("strength") is float \
				and context.get("shielded") is bool \
				and context.get("item_id") is StringName
	var required: Array[StringName] = [
		RunnerPlayer.PRESENT_LANE_CHANGED, RunnerPlayer.PRESENT_JUMPED,
		RunnerPlayer.PRESENT_LANDED, RunnerPlayer.PRESENT_SLID,
		RunnerPlayer.PRESENT_SLIDE_EXIT, RunnerPlayer.PRESENT_FISH_COLLECTED,
		RunnerPlayer.PRESENT_POWERUP_GAINED, RunnerPlayer.PRESENT_POWERUP_EXPIRED,
		RunnerPlayer.PRESENT_NEAR_MISS, RunnerPlayer.PRESENT_RAMP_LAUNCHED,
		RunnerPlayer.PRESENT_SHIELD_SPENT, RunnerPlayer.PRESENT_HIT_TAKEN,
		RunnerPlayer.PRESENT_DIED,
	]
	var all_events := true
	for id: StringName in required:
		all_events = all_events and ids.has(id)
	_check("presentation_every_runner_verb", all_events, str(ids.keys()))
	_check("presentation_context_canonical", canonical)
	_check("presentation_no_duplicate_landing", int(ids.get(RunnerPlayer.PRESENT_LANDED, 0)) == 2,
			"ordinary+ramp=%d" % int(ids.get(RunnerPlayer.PRESENT_LANDED, 0)))
	_check("runner_uses_character_look_hero", player._visual._look != null
			and player._visual._look.render_role == CharacterLook.RenderRole.HERO)
	near.queue_free()
	fish.queue_free()
	crate.queue_free()
	player.queue_free()
	await get_tree().process_frame


func _make_test_overlap(area: Area3D, group: StringName, at: Vector3) -> void:
	area.collision_layer = RunnerTrack.HAZARD_LAYER
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = true
	area.add_to_group(group)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.6
	shape.shape = sphere
	area.add_child(shape)
	add_child(area)
	area.global_position = at


func _test_layout_and_retry() -> void:
	var game := RunnerGame.new()
	game.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(game)
	while not game.build_finished:
		await get_tree().process_frame
	_check("runner_art_foundation_loaded", game._runner_art_set != null
			and game._art_catalog != null)
	var day_profile := game._runner_art_set.profile_for_biome("day") \
			if game._runner_art_set != null else null
	var day_environment := game._runner_environment(RunnerTrack.Biome.DAY)
	_check("runner_environment_uses_profile", day_profile != null
			and day_environment.get("sky_top") == day_profile.sky_top
			and is_equal_approx(float(day_environment.get("sun_energy", 0.0)),
					day_profile.sun_energy))
	var viewport := get_viewport()
	_check("layout_refresh_connected", viewport != null
			and viewport.size_changed.is_connected(game._refresh_layout))
	game.camera = Camera3D.new()
	game.add_child(game.camera)
	game._layout = LayoutProfile.for_view_size(Vector2(960.0, 540.0))
	game._intro_t = 0.0
	game.player.position = Vector3.ZERO
	game.player.speed = RunnerConfig.START_SPEED
	game._place_camera(0.0, true)
	_check("camera_uses_profile_chase",
			is_equal_approx(game.camera.position.y, game._layout.runner_chase_height)
			and game.camera.position.z > game._layout.runner_chase_distance * 0.5
			and game.camera.position.z <= game._layout.runner_chase_distance
			and is_equal_approx(game.camera.fov, game._layout.runner_base_fov))
	var ground_y := game.camera.position.y
	game.player.position.y = 2.0
	game._place_camera(0.0, true)
	_check("camera_preserves_air_framing", game.camera.position.y > ground_y + 1.0)
	game.player.position.y = 0.0
	game._intro_t = 1.0
	game._place_camera(0.0, true)
	_check("camera_preserves_intro_move",
			game.camera.position.y > game._layout.runner_chase_height
			and game.camera.position.z > game._layout.runner_chase_distance)
	for size: Vector2 in [Vector2(540, 960), Vector2(960, 540), Vector2(1600, 1200)]:
		var profile := LayoutProfile.for_view_size(size)
		_check("hero_target_%dx%d" % [int(size.x), int(size.y)],
				profile.hero_frame_height >= 0.14 and profile.hero_frame_height <= 0.18)

	var old_player := game.player
	game._dead = true
	game.running = false
	game.track.setup_golden_slice(GOLDEN_SEED, 0)
	game.restart()
	_check("retry_replaces_player", game.player != old_player
			and game.player.state == RunnerPlayer.State.RUN)
	_check("retry_resets_run_state", not game._dead and not game.running
			and game.fish == 0 and game.hits_taken == 0)
	_check("retry_reconnects_presentation", game.player.presentation_event.is_connected(
			game._on_presentation_event))
	game.queue_free()
	await get_tree().process_frame
