class_name DuskVisibilityDelay
extends Node
## QA-only copied-source counterfactual. Never installed by a live scene.
## No hashing, disk writes, screenshots, geometry walks or GPU reads while timed.

const TARGET := 17
const NODE_NAME := "QADuskVisibilityDelay"
var _track: Variant
var _chunk: Node3D
var _probe: Variant
var _original_visible: bool
var _restored := false
var _complete := false
var _phase := 0
var _hidden_draws := 0
var _started_usec: int
var _out: String
var _insertion_state: Dictionary
var _stable_state: Dictionary
var _report: Dictionary = {"success": false, "qa_counterfactual": true,
		"live_runtime_changed": false, "target_chunk": TARGET, "events": [], "errors": []}


static func before_insert(track: Node, chunk: Node3D) -> void:
	var arguments := OS.get_cmdline_user_args()
	var identity := String(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	if "dusk_visibility_parse_only=true" in arguments:
		if not GameConfig.is_headless() or not identity.begins_with("waddle-dusk-delay-prepare-"):
			push_error("DUSK visibility parser guard requires isolated headless prepare")
			track.get_tree().quit(2)
		elif int(chunk.get("index")) == 0:
			print("[dusk_visibility_delay] real-runner parser hook reached")
			track.get_tree().quit(0)
		return
	if int(chunk.get("index")) != TARGET:
		return
	var output := ""
	for argument: String in arguments:
		if argument.begins_with("dusk_visibility_out="):
			output = argument.trim_prefix("dusk_visibility_out=")
	var probe: Node = track.get_parent().get_parent()
	if GameConfig.is_headless() or not identity.begins_with("waddle-wars-perf-") \
			or not output.is_absolute_path() or not DirAccess.dir_exists_absolute(output) \
			or probe.get_script().resource_path != "res://tests/runner_perf_probe.gd" \
			or probe.get("_stream_trace_requested") != true or chunk.get_parent() != null \
			or chunk.is_inside_tree() or chunk.get_child_count() != 0 or not chunk.visible \
			or track.has_node(NODE_NAME) or int(chunk.get("biome")) != 1:
		push_error("DUSK visibility delay requires isolated ordinary probe and unparented first DUSK17")
		track.get_tree().quit(2)
		return
	var observer := DuskVisibilityDelay.new()
	observer.name = NODE_NAME
	observer._track = track
	observer._chunk = chunk
	observer._probe = probe
	observer._out = output
	observer._original_visible = chunk.visible
	observer._started_usec = Time.get_ticks_usec()
	observer.process_priority = 100 # Observe after the ordinary probe samples.
	# This executes before add_child(chunk), before any target geometry exists.
	chunk.visible = false
	track.add_child(observer)
	observer._record("hidden_before_insert")
	RenderingServer.frame_post_draw.connect(observer._on_draw)


static func after_insert(track: Node, chunk: Node3D) -> void:
	if int(chunk.get("index")) != TARGET:
		return
	var observer := track.get_node_or_null(NODE_NAME) as DuskVisibilityDelay
	if observer == null:
		push_error("DUSK visibility delay observer missing after insertion")
		track.get_tree().quit(2)
		return
	observer._insertion_state = observer._generation_state()
	observer._record("construction_and_insertion_complete")
	observer._phase = 1


func _on_draw() -> void:
	if _phase == 1:
		_hidden_draws += 1
		_record("hidden_post_draw_%d" % _hidden_draws)
		if _hidden_draws == 1:
			# update_stream still retires the oldest normal chunk after _spawn_chunk
			# returns. Baseline after that first full frame, not inside insertion.
			_stable_state = _generation_state()
		if _chunk.visible or _chunk.is_visible_in_tree():
			_fail("target became visible before two confirmed hidden draws")
			return
		if _hidden_draws == 2:
			_restore_visibility()
			_record("original_visibility_restored")
			_phase = 2
	elif _phase == 2:
		_record("first_restored_post_draw")
		_report["target_visibility_restored"] = _chunk.visible == _original_visible
		_report["target_effectively_visible_after_restore"] = _chunk.is_visible_in_tree()
		_report["generation_state_preserved"] = _generation_state() == _stable_state
		_report["hidden_draw_count"] = _hidden_draws
		_phase = 3


func _process(_delta: float) -> void:
	if _phase == 3:
		_record("next_sample_after_restored_draw")
		_complete = _report.target_visibility_restored and _report.generation_state_preserved \
				and _report.target_effectively_visible_after_restore
		_disconnect()
		set_process(false)
		if not _complete:
			_fail("visibility/generation restoration check failed")
	elif Time.get_ticks_usec() - _started_usec > 10_000_000:
		_fail("two confirmed hidden draws/reveal did not finish within 10 seconds")


func _record(event: String) -> void:
	# Seven bounded records. Sample id at event is the probe's latest completed
	# process sample, not a claim that it contains this later renderer interval.
	_report.events.append({"event": event, "monotonic_usec": Time.get_ticks_usec(),
			"process_frame": Engine.get_process_frames(),
			"sample_frame_id_at_event": _probe._frame_ms.size(),
			"sample_time_at_event": _probe._sample_time,
			"last_sample_frame_ms": _probe._frame_ms[-1] if not _probe._frame_ms.is_empty() else null,
			"distance": _track.get_parent().player.distance,
			"local_visible": _chunk.visible, "effectively_visible": _chunk.is_visible_in_tree(),
			"in_tree": _chunk.is_inside_tree(), "parent_is_track": _chunk.get_parent() == _track})


func _generation_state() -> Dictionary:
	var chunks: Array[int] = []
	for chunk: Node in _track._chunks:
		chunks.append(int(chunk.get("index")))
	return {"seed": _track._seed, "game_rng": str(_track.get_parent()._rng.state),
			"first": _track._first_index, "next": _track._next_index, "chunks": chunks,
			"pattern": _track._last_pattern, "tunnel_left": _track._tunnel_left,
			"powerup_cursor": _track._powerup_cursor, "next_powerup_z": _track._next_powerup_z,
			"jump_z": _track._lane_jump_z.duplicate(), "slide_z": _track._lane_slide_z.duplicate(),
			"air_from_z": _track._air_from_z, "air_to_z": _track._air_to_z,
			"target_transform": _chunk.transform, "target_parent": str(_chunk.get_parent().get_instance_id()),
			"target_child_count": _chunk.get_child_count(), "target_process_mode": _chunk.process_mode}


func _restore_visibility() -> void:
	if not _restored and is_instance_valid(_chunk):
		_chunk.visible = _original_visible
	_restored = true


func _disconnect() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_draw):
		RenderingServer.frame_post_draw.disconnect(_on_draw)


func _fail(message: String) -> void:
	_report.errors.append(message)
	_restore_visibility()
	_disconnect()
	push_error("DUSK visibility delay: " + message)
	get_tree().quit(2)


func _exit_tree() -> void:
	_restore_visibility()
	_disconnect()
	# The observer stays inert after its seven records. File/hash work occurs
	# only here, after the ordinary probe has ended its measurement.
	var after_timing := is_instance_valid(_probe) and bool(_probe.get("_finished"))
	_report["written_after_measurement"] = after_timing
	_report["original_local_visible"] = _original_visible
	_report["generation_state_after_insertion"] = _insertion_state
	_report["generation_state_after_first_hidden_draw"] = _stable_state
	_report["generation_guard_scope"] = "First hidden post-draw through first restored post-draw; " \
			+ "ordinary chunk retirement between insertion and the first draw is deliberately allowed."
	_report["success"] = after_timing and _complete and _report.errors.is_empty() \
			and _report.events.size() == 7 and _hidden_draws == 2
	_report["scope"] = "QA copied-source first visibility delay only. Same normal construction/insertion, " \
			+ "materials, colliders, RNG and processing. Seven bounded events; no GPU timestamp query. " \
			+ "An event's sample id is the most recent process sample, not a synchronized renderer interval."
	_report["source_sha256"] = {}
	for path: String in ["res://scripts/runner/runner_track.gd", "res://tests/runner_perf_probe.gd",
			"res://tests/runner_dusk_visibility_delay.gd"]:
		_report.source_sha256[path] = FileAccess.get_sha256(path)
	var file := FileAccess.open(_out.path_join("visibility_delay_report.json"), FileAccess.WRITE)
	if file == null:
		push_error("DUSK visibility delay: could not retain teardown audit")
	else:
		file.store_string(JSON.stringify(_report, "\t"))
	print("[dusk_visibility_delay] audit success=%s" % _report.success)
