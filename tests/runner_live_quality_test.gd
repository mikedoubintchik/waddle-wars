extends Node
## Same-run quality changes, not browser performance or visual approval.
## run_tests.sh supplies an isolated project and user:// directory.

const SEED: int = 909177
const DIFFICULTY: float = 0.72

var _checks: int = 0
var _failures: int = 0


class NoWarmupTrack:
	extends RunnerTrack

	func _register_shader_warmup_probes() -> void:
		pass


func _ready() -> void:
	_test_live_ranges_and_reserved_density()
	await _test_real_runner_setting_signal()
	print("[runner_live_quality] %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("[runner_live_quality] FAIL %s" % label)


func _new_track() -> RunnerTrack:
	var track := NoWarmupTrack.new()
	track.setup(SEED, 1.0, 1)
	return track


func _test_live_ranges_and_reserved_density() -> void:
	var settings_before := SettingsManager.settings.duplicate(true)
	var governor_before := SettingsManager._governor_override
	var track := _new_track()
	var control := _new_track()
	var opening := track._chunks[0]
	var custom_range := MeshInstance3D.new()
	custom_range.name = "AuthoredRangeFixture"
	custom_range.visibility_range_end = 250.0
	custom_range.visibility_range_end_margin = 12.0
	custom_range.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	opening.add_child(custom_range)
	var ids_before := _node_ids(track)
	var gameplay_before := _gameplay_signature(track)
	var player_z := -RunnerConfig.CHUNK_LENGTH - 0.1
	track.update_stream(player_z, DIFFICULTY)
	control.update_stream(player_z, DIFFICULTY)
	var job := track._stream_job
	var rng_before := job.rng.state
	var art_rng_before := job.art_rng.state
	var units_before := job.units
	track.set_dressing_density(0.65)
	_check(track._dressing_density == 0.65, "new density selected immediately")
	_check(track._stream_job == job and job.units == units_before,
			"setting change preserves reserved job and progress")
	_check(job.rng.state == rng_before and job.art_rng.state == art_rng_before,
			"setting change consumes neither gameplay nor art RNG")
	_check(job.chunk.dressing_density == 1.0, "reserved chunk keeps original density")
	_check(_node_ids(track) == ids_before, "resident nodes preserved without rebuild")
	_check(_gameplay_signature(track) == gameplay_before, "resident collisions and pickups preserved")
	_check(custom_range.visibility_range_end == 250.0
			and track._live_range_pending.size() == RunnerConfig.CHUNKS_AHEAD,
			"settings callback queues bounded updates without render setter burst")
	track._process(0.0)
	_check(custom_range.visibility_range_end == RunnerTrack.MEDIUM_VISUAL_RANGE,
			"existing authored range obeys medium cap")
	_check(track._live_range_pending.size() == RunnerConfig.CHUNKS_AHEAD - 1,
			"actual process callback applies only one existing chunk")
	var guard := 0
	while track._stream_job != null and guard < 256:
		track.update_stream(player_z, DIFFICULTY)
		guard += 1
	guard = 0
	while control._stream_job != null and guard < 256:
		control.update_stream(player_z, DIFFICULTY)
		guard += 1
	_check(track._stream_job == null and control._stream_job == null,
			"original reserved chunks commit")
	var finished: RunnerTrack.RunnerChunk = track._chunks.back()
	var reference: RunnerTrack.RunnerChunk = control._chunks.back()
	_check(_gameplay_signature(finished) == _gameplay_signature(reference),
			"mid-job adaptation preserves final gameplay layout")
	_check(_multimesh_signature(finished) == _multimesh_signature(reference),
			"mid-job adaptation preserves original art density and RNG order")
	_check(finished._range_profile_distance == RunnerTrack.MEDIUM_VISUAL_RANGE,
			"reserved chunk commits with latest live range")
	_check(_all_geometry_capped(finished, RunnerTrack.MEDIUM_VISUAL_RANGE),
			"all committed geometry uses live cap")

	# Advance one further chunk. Its generation snapshot must match the new
	# density, while gameplay remains identical to an unchanged high run.
	control._spawn_chunk(RunnerConfig.CHUNKS_AHEAD + 1, DIFFICULTY)
	player_z -= RunnerConfig.CHUNK_LENGTH
	track.update_stream(player_z, DIFFICULTY)
	_check(track._stream_job != null and track._stream_job.chunk.dressing_density == 0.65,
			"future reservation captures updated density")
	guard = 0
	while track._stream_job != null and guard < 256:
		track.update_stream(player_z, DIFFICULTY)
		guard += 1
	var future: RunnerTrack.RunnerChunk = track._chunks.back()
	_check(future.index == RunnerConfig.CHUNKS_AHEAD + 1 and future.dressing_density == 0.65,
			"future chunk built at new density")
	_check(_gameplay_signature(future) == _gameplay_signature(control._chunks.back()),
			"future density leaves gameplay and collision shapes identical")
	_check(_multimesh_signature(future) != _multimesh_signature(control._chunks.back()),
			"future presentation actually changes at new density")
	_check(_all_geometry_capped(future, RunnerTrack.MEDIUM_VISUAL_RANGE),
			"future geometry uses new cap")

	track.set_dressing_density(0.35)
	_drain_live_ranges(track)
	_check(custom_range.visibility_range_end == RunnerTrack.LOW_VISUAL_RANGE,
			"existing range follows low cap")
	track.set_dressing_density(1.0)
	_drain_live_ranges(track)
	_check(custom_range.visibility_range_end == 250.0
			and custom_range.visibility_range_end_margin == 12.0
			and custom_range.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF,
			"recovery restores exact authored range margin and fade")
	_check(future.dressing_density == 0.65 and finished.dressing_density == 1.0,
			"recovery does not rebuild existing density snapshots")
	_check(SettingsManager.settings == settings_before
			and SettingsManager._governor_override == governor_before,
			"track adaptation leaves saved settings and governor untouched")
	track.set_dressing_density(-2.0)
	_check(track._dressing_density == 0.0, "density clamps at lower bound")
	track.set_dressing_density(2.0)
	_check(track._dressing_density == 1.0, "density clamps at upper bound")
	_drain_live_ranges(track)
	track.free()
	control.free()

	# Explicit range inputs exercise dressing recovery independent of headless
	# renderer's disabled culling. No visual resource is uploaded by this check.
	var chunk := RunnerTrack.RunnerChunk.new()
	var dressing := MultiMeshInstance3D.new()
	dressing.set_meta("runner_dressing_base_range", 900.0)
	chunk.add_child(dressing)
	chunk.apply_visual_range(RunnerTrack.MEDIUM_VISUAL_RANGE, 0.65, 1.0)
	_check(dressing.visibility_range_end == RunnerTrack.MEDIUM_VISUAL_RANGE,
			"dressing range combines authored distance with overall cap")
	chunk.apply_visual_range(RunnerTrack.LOW_VISUAL_RANGE, 0.35, 0.7)
	_check(is_equal_approx(dressing.visibility_range_end, 157.5),
			"dressing range recomputes low scale from original base")
	chunk.apply_visual_range(0.0, 1.0, 1.3)
	_check(is_equal_approx(dressing.visibility_range_end, 1170.0)
			and is_equal_approx(dressing.visibility_range_end_margin, 175.5),
			"high recovery restores full authored dressing distance")
	chunk.apply_visual_range(0.0, 1.0, 0.0)
	_check(dressing.visibility_range_end == 0.0
			and dressing.visibility_range_end_margin == 0.0,
			"uncapped desktop recovery removes lower-tier range")
	chunk.free()
	var deck_chunk := RunnerTrack.RunnerChunk.new()
	var deck := MultiMeshInstance3D.new()
	deck.set_meta("runner_dressing_base_range", 220.0)
	deck.set_meta("runner_gameplay_surface", true)
	deck_chunk.add_child(deck)
	deck_chunk.apply_visual_range(RunnerTrack.LOW_VISUAL_RANGE, 0.35, 0.7)
	_check(is_equal_approx(deck.visibility_range_end, 154.0)
			and deck.visibility_range_end > 70.0 + RunnerConfig.CHUNK_LENGTH,
			"authored deck retains full decision horizon on low")
	deck_chunk.free()


func _drain_live_ranges(track: RunnerTrack) -> void:
	var guard := 0
	while not track._live_range_pending.is_empty() and guard < 32:
		track._process(0.0)
		guard += 1
	_check(track._live_range_pending.is_empty(), "bounded range queue drains")


func _test_real_runner_setting_signal() -> void:
	var saved_settings := SettingsManager.settings.duplicate(true)
	var saved_override := SettingsManager._governor_override
	SettingsManager.settings["display"]["quality_preset"] = "high"
	SettingsManager._governor_override = ""
	var game := RunnerGame.new()
	add_child(game)
	var guard := 0
	while not game.build_finished and guard < 128:
		await get_tree().process_frame
		guard += 1
	_check(game.build_finished and game.track != null, "actual runner initialized headlessly")
	if game.track != null:
		var before := _gameplay_signature(game.track)
		SettingsManager._governor_override = "low"
		SettingsManager.setting_changed.emit("display/quality_preset", "low")
		_check(game.track._dressing_density == game._runner_dressing_density(RunnerTrack.Biome.DAY),
				"actual settings signal changes current runner density")
		_check(game.track._dressing_density < 0.5, "low governor tier reaches current runner")
		_check(_gameplay_signature(game.track) == before, "actual settings signal preserves gameplay")
		_check(SettingsManager.settings["display"]["quality_preset"] == "high",
				"governor callback does not overwrite saved explicit tier")
		SettingsManager._governor_override = ""
		SettingsManager.setting_changed.emit("display/quality_preset", "high")
		_check(game.track._dressing_density == 1.0, "actual recovery signal restores future density")
	game.free()
	SettingsManager.settings = saved_settings
	SettingsManager._governor_override = saved_override


func _node_ids(root: Node) -> PackedInt64Array:
	var ids := PackedInt64Array([root.get_instance_id()])
	for child: Node in root.get_children():
		ids.append_array(_node_ids(child))
	return ids


func _gameplay_signature(root: Node) -> Array:
	var rows: Array = []
	_append_gameplay(root, rows)
	return rows


func _append_gameplay(node: Node, rows: Array) -> void:
	if node is Area3D or node is CollisionShape3D:
		# Hazard/pickup nodes intentionally have no authored name. Godot assigns
		# allocation-dependent names, which are not part of replay identity.
		var row: Array = [node.get_class(), (node as Node3D).transform]
		for key: String in ["kind", "lane", "span", "powerup"]:
			row.append(node.get_meta(key) if node.has_meta(key) else null)
		if node is Area3D:
			row.append((node as Area3D).collision_layer)
			row.append((node as Area3D).collision_mask)
		if node is CollisionShape3D:
			var shape := (node as CollisionShape3D).shape
			row.append(shape.get_class())
			if shape is BoxShape3D:
				row.append((shape as BoxShape3D).size)
			elif shape is SphereShape3D:
				row.append((shape as SphereShape3D).radius)
		rows.append(row)
	for child: Node in node.get_children():
		_append_gameplay(child, rows)


func _multimesh_signature(root: Node) -> Array:
	var rows: Array = []
	if root is MultiMeshInstance3D and (root as MultiMeshInstance3D).multimesh != null:
		var mm := (root as MultiMeshInstance3D).multimesh
		var transforms: Array = []
		for index: int in mm.instance_count:
			transforms.append(mm.get_instance_transform(index))
		rows.append([String(root.name), mm.instance_count, transforms])
	for child: Node in root.get_children():
		rows.append_array(_multimesh_signature(child))
	return rows


func _all_geometry_capped(root: Node, cap: float) -> bool:
	if root is GeometryInstance3D:
		var end_distance := (root as GeometryInstance3D).visibility_range_end
		if end_distance <= 0.0 or end_distance > cap:
			return false
	for child: Node in root.get_children():
		if not _all_geometry_capped(child, cap):
			return false
	return true
