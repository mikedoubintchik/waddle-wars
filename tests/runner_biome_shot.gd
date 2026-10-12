extends "res://tests/runner_golden_shot.gd"
## Four normal streamed biomes at fixed distances. Reuses golden-shot window
## setup; run in an isolated project/user directory as with the other captures.
## This is a still review, not a timing or gameplay-autopilot measurement.
##
## godot --path . --rendering-method gl_compatibility \
##     res://tests/runner_biome_shot.tscn -- out=/tmp/biomes.png w=540 h=960 touch=1

const BIOME_DISTANCES: PackedFloat32Array = [180.0, 792.0, 1404.0, 2016.0]
const STREAM_WAIT_FRAME_LIMIT: int = 240

var _biome_checks: Array[Dictionary] = []
var _biome_captures: Array[Dictionary] = []
var _streamed_frames: int = 0
var _finished: bool = false


func _ready() -> void:
	await super._ready()
	# Normal staged builds need several submitted frames per intervening chunk.
	# Still bounded below the wrapper's 85-second process deadline.
	_deadline = Time.get_ticks_msec() * 0.001 + 75.0


func _process(_delta: float) -> void:
	if _finished:
		return
	if Time.get_ticks_msec() * 0.001 > _deadline:
		push_error("runner_biome_shot: capture timed out")
		_record_check(false, "capture completed within 75-second deadline")
		_finish()
		return
	if _capturing or _game == null or not _game.build_finished \
			or is_instance_valid(_game._startup_warmup) or not _game._presentation_started:
		return
	if not _started:
		_started = true
		# The shipped first presentation tick reenables track processing after
		# warmup. Let it happen before this still fixture freezes gameplay.
		_game.set_process(false)
		_game.track.setup(GOLDEN_SEED, _game._runner_dressing_density(RunnerTrack.Biome.DAY), 1)
		_record_check(_game.track.can_process(), "track and child presentation processing remain enabled")
		_game.running = false
		_game._dead = false
		_game._intro_t = 0.0
		_game.player.set_input_enabled(false)
		if _game.hud != null:
			_game.hud.show_message("")
	if _shot >= BIOME_DISTANCES.size():
		_finish()
		return
	_capturing = true
	_capture(_shot)


func _capture(index: int) -> void:
	var distance := BIOME_DISTANCES[index]
	var previous_distance := 0.0 if index == 0 else BIOME_DISTANCES[index - 1]
	# Stream every intervening chunk so normal generator state is preserved,
	# while avoiding the minute-long real-time trip to the final band.
	for chunk_index: int in range(int(previous_distance / RunnerConfig.CHUNK_LENGTH),
			int(distance / RunnerConfig.CHUNK_LENGTH) + 1):
		if not await _await_stream_coverage(-float(chunk_index) * RunnerConfig.CHUNK_LENGTH):
			_finish()
			return
	var player := _game.player
	player.distance = distance
	player.position = Vector3(0.0, 0.0, -distance)
	player.lane = 1
	player.speed = RunnerConfig.MAX_SPEED
	player.state = RunnerPlayer.State.RUN
	player._launched = false
	player._vertical = 0.0
	player._visual.trigger_event(&"recover")
	_game._place_camera(0.0, true)
	_game._update_follow_fx(1.0)
	_game._blend_biome(2.0)
	var biome := _game.track.biome_at_z(player.position.z)
	_record_check(biome == index, "expected biome at synthetic distance", {"biome": biome, "distance": distance})
	if biome != index:
		push_error("runner_biome_shot: unexpected biome %d at %.0fm" % [biome, distance])
		_save_failed = true
	if _game.chaser != null:
		_game.chaser.tick(0.0, distance, 0.0)
	if _game.hud != null:
		_game.hud.set_stats(distance, 24 + index * 11, int(distance * 4.0),
				1 + index, RunnerConfig.MAX_HITS, RunnerConfig.CHASER_BASE_GAP)
	for _frame: int in 24:
		_game.track.update_stream(player.position.z, 0.72)
		player._drive_visual(1.0 / 60.0)
		await get_tree().process_frame
	var coverage := _visible_deck_coverage()
	_record_check(bool(coverage["committed_ahead"]), "full lookahead committed before capture", coverage)
	_record_check(bool(coverage["required_chunks_visible"]), "nearby committed chunks have visible deck meshes", coverage)
	_record_check(bool(coverage["spans_player"]), "visible deck bounds span player distance", coverage)
	_record_check(bool(coverage["forward_in_frustum"]), "forward deck lies inside capture camera frustum", coverage)
	if not bool(coverage["committed_ahead"]) or not bool(coverage["required_chunks_visible"]) \
			or not bool(coverage["spans_player"]) or not bool(coverage["forward_in_frustum"]):
		push_error("runner_biome_shot: committed visible deck coverage missing")
		_finish()
		return
	await RenderingServer.frame_post_draw
	var window_visible := get_window().visible and DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_MINIMIZED
	var focused := get_window().has_focus()
	var allow_unfocused := "raster_background=1" in OS.get_cmdline_user_args()
	_record_check(window_visible and (focused or allow_unfocused), "biome submitted with required visible/focus state",
		{"window_visible":window_visible,"window_focused":focused,"allow_unfocused_raster":allow_unfocused})
	if not window_visible or (not focused and not allow_unfocused):
		_finish()
		return
	var image := get_viewport().get_texture().get_image()
	var path := "%s_%s.png" % [_out_path.get_basename(), RunnerGame.BIOME_IDS[biome]]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var error := image.save_png(path)
	_save_failed = _save_failed or error != OK
	_record_check(error == OK, "biome PNG saved", {"path": path, "error": error})
	_biome_captures.append({"biome": RunnerGame.BIOME_IDS[biome], "distance": distance,
			"path": path, "coverage": coverage, "streamed_frames": _streamed_frames,
			"window_visible":window_visible,"window_focused":focused,"allow_unfocused_raster":allow_unfocused})
	print("[runner_biome_shot] saved %s distance=%.0fm err=%d" % [path, distance, error])
	_shot += 1
	_capturing = false


func _await_stream_coverage(player_z: float) -> bool:
	var required_next := int(floor(-player_z / RunnerConfig.CHUNK_LENGTH)) + RunnerConfig.CHUNKS_AHEAD
	for _frame: int in STREAM_WAIT_FRAME_LIMIT:
		# Use the shipped per-update work budget once per ordinary process frame.
		# A single update per synthetic chunk cannot finish a detached build.
		_game.track.update_stream(player_z, 0.72)
		await get_tree().process_frame
		_streamed_frames += 1
		var state := _game.track.perf_trace_snapshot(player_z)
		if int(state["next_chunk"]) >= required_next and not bool(state["stream_build_pending"]):
			return true
		if _finished or Time.get_ticks_msec() * 0.001 > _deadline:
			break
	_record_check(false, "normal streaming committed within bounded wait",
			_game.track.perf_trace_snapshot(player_z))
	push_error("runner_biome_shot: staged stream did not commit required coverage")
	return false


func _visible_deck_coverage() -> Dictionary:
	var player := _game.player
	var current := int(floor(player.distance / RunnerConfig.CHUNK_LENGTH))
	var state := _game.track.perf_trace_snapshot(player.position.z)
	var entries: Array[Dictionary] = []
	var present: Array[int] = []
	var spans_player := false
	var forward_in_frustum := false
	for chunk: RunnerTrack.RunnerChunk in _game.track._chunks:
		if chunk.index < current - 1 or chunk.index > current + 2:
			continue
		var deck := chunk.get_node_or_null("GlacialIceSkin") as MeshInstance3D
		if deck == null:
			deck = chunk.get_node_or_null("Deck") as MeshInstance3D
		if deck == null or deck.mesh == null or not deck.is_visible_in_tree():
			continue
		var bounds: AABB = deck.global_transform * deck.get_aabb()
		var start_z := -float(chunk.index) * RunnerConfig.CHUNK_LENGTH
		var end_z := start_z - RunnerConfig.CHUNK_LENGTH
		var full_span := bounds.position.z <= end_z + 0.001 and bounds.end.z >= start_z - 0.001
		var lane_span := bounds.position.x <= player.position.x and bounds.end.x >= player.position.x
		var in_frustum := _game.camera.is_position_in_frustum(bounds.get_center())
		if full_span and lane_span:
			present.append(chunk.index)
			spans_player = spans_player or (bounds.position.z <= player.position.z + 0.001 \
					and bounds.end.z >= player.position.z - 0.001)
			forward_in_frustum = forward_in_frustum or (chunk.index >= current and in_frustum)
		entries.append({"chunk": chunk.index, "mesh": String(deck.name), "visible": true,
				"full_chunk_span": full_span, "lane_span": lane_span, "center_in_frustum": in_frustum,
				"min_z": bounds.position.z, "max_z": bounds.end.z})
	var required_visible := true
	for expected: int in range(maxi(0, current - 1), current + 3):
		required_visible = required_visible and expected in present
	return {"player_chunk": current, "player_z": player.position.z,
			"committed_ahead": int(state["next_chunk"]) >= current + RunnerConfig.CHUNKS_AHEAD \
					and not bool(state["stream_build_pending"]),
			"required_chunks_visible": required_visible, "spans_player": spans_player,
			"forward_in_frustum": forward_in_frustum, "decks": entries, "stream": state}


func _record_check(passed: bool, message: String, detail: Dictionary = {}) -> void:
	_biome_checks.append({"passed": passed, "message": message, "detail": detail})
	_save_failed = _save_failed or not passed


func _finish() -> void:
	if _finished:
		return
	_finished = true
	var failed := 0
	for check: Dictionary in _biome_checks:
		if not bool(check["passed"]):
			failed += 1
	var report := {"kind": "runner_biome_committed_coverage", "status": "FAIL" if _save_failed else "PASS",
			"check_count": _biome_checks.size(), "failed_count": failed, "checks": _biome_checks,
			"captures": _biome_captures, "streamed_frames": _streamed_frames,
			"limitations": "Synthetic fixed distances and posed player/HUD. Shipped update_stream work budgets advance once per ordinary process frame, with live child processing. Visible mesh bounds and camera frustum prove committed deck coverage; pixel readability still requires review. No forced draw, physical input, natural playthrough or performance acceptance."}
	var path := _out_path.get_basename() + "_coverage.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("runner_biome_shot: could not write coverage receipt")
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("[runner_biome_shot] %s checks=%d failed=%d coverage=%s" % [report["status"], _biome_checks.size(), failed, path])
	get_tree().quit(1 if _save_failed else 0)
