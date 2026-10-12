extends Node
## Incremental streamer contract. Root runs this scene through isolated user://.

const SEED: int = 909177
const DIFFICULTY: float = 0.72
const EPSILON: float = 0.0001

var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	_test_atomic_commit_and_trace()
	_test_bounded_disposal_and_group_isolation()
	_test_sync_staged_layout_through_transitions()
	_test_cancel_reset_isolation()
	_test_max_speed_horizon(30)
	_test_max_speed_horizon(60)
	await _test_mover_reservation_phase()
	RunnerTrack.perf_trace_enabled = false
	print("[runner_stream_staging] %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures else 0)


func _check(ok: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if ok:
		return
	_failures += 1
	print("[runner_stream_staging] FAIL %s%s" % [label,
			": " + detail if not detail.is_empty() else ""])


func _new_rendered_track(name_value: String, in_tree: bool = true) -> RunnerTrack:
	var track := RunnerTrack.new()
	track.name = name_value
	if in_tree:
		add_child(track)
	track.setup(SEED, 1.0, 1)
	return track


func _test_atomic_commit_and_trace() -> void:
	RunnerTrack.perf_trace_enabled = true
	var track := _new_rendered_track("AtomicTrack")
	track.drain_perf_trace_events()
	var before_groups := _runner_group_counts()
	track.update_stream(-RunnerConfig.CHUNK_LENGTH - 0.1, DIFFICULTY)
	var snapshot := track.perf_trace_snapshot(-RunnerConfig.CHUNK_LENGTH - 0.1)
	_check(bool(snapshot["stream_build_pending"]), "rendered stream starts detached job")
	_check(track.get_node_or_null("Chunk7") == null, "partial chunk absent from live children")
	_check(_runner_group_counts() == before_groups, "partial chunk absent from SceneTree groups")
	var job: Variant = track.get("_stream_job")
	var detached: Node = job.get("chunk") if job != null else null
	_check(detached != null and detached.get_parent() == null
			and not detached.is_inside_tree(), "job chunk remains detached")

	var all_events: Array[Dictionary] = []
	all_events.append_array(track.drain_perf_trace_events())
	var updates := 1
	while track.get_node_or_null("Chunk7") == null and updates < 256:
		track.update_stream(-RunnerConfig.CHUNK_LENGTH - 0.1, DIFFICULTY)
		all_events.append_array(track.drain_perf_trace_events())
		updates += 1
	_check(track.get_node_or_null("Chunk7") != null, "staged chunk commits")
	_check(updates > 1, "chunk assembly spans frames", "updates=%d" % updates)
	var stage_events := 0
	var spawn_event: Dictionary = {}
	for event: Dictionary in all_events:
		if event.get("kind") == "stream_stage" and int(event.get("chunk", -1)) == 7:
			stage_events += 1
		elif event.get("kind") == "spawn" and int(event.get("chunk", -1)) == 7:
			spawn_event = event
	_check(stage_events >= RunnerTrack.STREAM_DECK_STAGE_COUNT
			+ RunnerTrack.STREAM_DRESSING_STAGE_COUNT,
			"trace attributes bounded stages", "events=%d" % stage_events)
	_check(not spawn_event.is_empty() and int(spawn_event.get("staged_frames", 0)) > 1
			and int(spawn_event.get("work_units", 0)) + 1 == stage_events,
			"commit trace carries complete staged attribution", str(spawn_event))
	_check(int(spawn_event.get("deck_us", -1)) >= 0
			and int(spawn_event.get("dressing_us", -1)) >= 0
			and int(spawn_event.get("pattern_us", -1)) >= 0
			and int(spawn_event.get("commit_us", -1)) >= 0,
			"trace preserves spawn CPU buckets")
	RunnerTrack.perf_trace_enabled = false
	track.free()


func _test_sync_staged_layout_through_transitions() -> void:
	var sync := _new_rendered_track("SyncReference", false)
	var staged := _new_rendered_track("StagedReference")
	var saw_tunnel := false
	var saw_biome_transition := false
	var first_dusk_index := ceili(RunnerConfig.BIOME_LENGTH / RunnerConfig.CHUNK_LENGTH)
	for index: int in range(RunnerConfig.CHUNKS_AHEAD, first_dusk_index + 3):
		# Derive the real boundary from current progression pacing. Force an
		# owed tunnel in the last DAY chunk, then compare next-biome assembly.
		if index == first_dusk_index - 1:
			sync.set("_tunnel_left", 1)
			staged.set("_tunnel_left", 1)
		var difficulty := clampf(float(index) * RunnerConfig.CHUNK_LENGTH
				/ RunnerTrack.DIFFICULTY_DISTANCE, 0.0, 1.0)
		sync._spawn_chunk(index, difficulty)
		var current := index - RunnerConfig.CHUNKS_AHEAD + 1
		var player_z := -float(current) * RunnerConfig.CHUNK_LENGTH - 0.1
		var guard := 0
		while staged.get_node_or_null("Chunk%d" % index) == null and guard < 256:
			staged.update_stream(player_z, difficulty)
			guard += 1
		var sync_chunk := sync.get_node_or_null("Chunk%d" % index)
		var staged_chunk := staged.get_node_or_null("Chunk%d" % index)
		_check(staged_chunk != null, "chunk %d commits before guard" % index,
				"updates=%d" % guard)
		if sync_chunk == null or staged_chunk == null:
			continue
		var expected := _node_signature(sync_chunk)
		var actual := _node_signature(staged_chunk)
		_check(actual == expected, "chunk %d sync/staged gameplay+visual layout" % index,
				"expected_nodes=%d actual_nodes=%d" % [expected.size(), actual.size()])
		saw_tunnel = saw_tunnel or int(sync_chunk.pattern) == RunnerTrack.Pattern.TUNNEL
		if index > RunnerConfig.CHUNKS_AHEAD:
			var previous := sync.get_node_or_null("Chunk%d" % (index - 1))
			saw_biome_transition = saw_biome_transition \
					or (previous != null and int(previous.biome) != int(sync_chunk.biome))
	_check(saw_tunnel, "parity range includes tunnel")
	_check(saw_biome_transition, "parity range crosses biome boundary")
	sync.free()
	staged.free()


func _test_bounded_disposal_and_group_isolation() -> void:
	RunnerTrack.perf_trace_enabled = true
	var track := _new_rendered_track("DisposalTrack")
	track.drain_perf_trace_events()
	var spent := track.get_node("Chunk0")
	var initial_children := spent.get_child_count()
	var player_z := -RunnerConfig.CHUNK_LENGTH * 3.0 - 0.1
	track.update_stream(player_z, DIFFICULTY)
	var first_events := track.drain_perf_trace_events()
	_check(is_instance_valid(spent) and spent.get_parent() == null
			and not spent.is_inside_tree(), "spent chunk exits live tree atomically")
	_check(spent.get_child_count() == initial_children,
			"retirement update defers all branch destruction")
	_check(_subtree_absent_from_live_groups(spent),
			"retired chunk has no live hazards or pickups")
	var disposed_on_retirement := false
	for event: Dictionary in first_events:
		disposed_on_retirement = disposed_on_retirement or event.get("kind") == "dispose"
	_check(not disposed_on_retirement, "detachment update has no disposal burst")

	var saw_disposal := false
	var saw_commit := false
	var limit_respected := true
	var quiet_commit := true
	var guard := 0
	# Catch up three new chunks, ensuring disposal overlaps ordinary staged work
	# but never the insertion update, and eventually releases its detached root.
	while (is_instance_valid(spent) or track.get_node_or_null("Chunk9") == null) \
			and guard < 512:
		track.update_stream(player_z, DIFFICULTY)
		var events := track.drain_perf_trace_events()
		var committed := false
		var disposed := false
		for event: Dictionary in events:
			if event.get("kind") == "spawn":
				committed = true
			elif event.get("kind") == "dispose":
				disposed = true
				limit_respected = limit_respected \
						and int(event.get("branches", 0)) \
						<= RunnerTrack.STREAM_DISPOSE_MAX_BRANCHES_PER_UPDATE
		saw_disposal = saw_disposal or disposed
		saw_commit = saw_commit or committed
		quiet_commit = quiet_commit and not (committed and disposed)
		guard += 1
	_check(saw_disposal and limit_respected, "disposal releases bounded branches")
	_check(saw_commit and quiet_commit, "commit never shares resource disposal update")
	_check(not is_instance_valid(spent), "bounded disposal eventually frees detached root")
	_check(int(track.perf_trace_snapshot(player_z)["stream_dispose_pending_chunks"]) == 0,
			"disposal queue drains after catch-up")

	# Reset/scene exit remain ownership boundaries even if quiet-frame disposal
	# has not begun. Neither may leave a detached Node tree behind.
	track.update_stream(-RunnerConfig.CHUNK_LENGTH * 4.0 - 0.1, DIFFICULTY)
	var retiring: Array = track.get("_retiring_chunks")
	var reset_spent: Node = retiring[0] if not retiring.is_empty() else null
	_check(reset_spent != null and is_instance_valid(reset_spent),
			"reset fixture retains detached spent chunk")
	track.reset(SEED, 1.0)
	_check(not is_instance_valid(reset_spent) \
			and int(track.perf_trace_snapshot(0.0)["stream_dispose_pending_chunks"]) == 0,
			"reset frees every deferred-disposal root")
	track.setup(SEED, 1.0, 1)
	track.update_stream(player_z, DIFFICULTY)
	retiring = track.get("_retiring_chunks")
	var exit_spent: Node = retiring[0] if not retiring.is_empty() else null
	var had_exit_spent := is_instance_valid(exit_spent)
	_check(had_exit_spent, "scene exit fixture retains detached spent chunk")
	track.free()
	_check(had_exit_spent and not is_instance_valid(exit_spent),
			"scene exit frees every deferred-disposal root")
	RunnerTrack.perf_trace_enabled = false


func _subtree_absent_from_live_groups(root: Node) -> bool:
	for group: StringName in [RunnerConfig.GROUP_HAZARD, RunnerConfig.GROUP_PICKUP,
			RunnerConfig.GROUP_POWERUP]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if node == root or root.is_ancestor_of(node):
				return false
	return true


func _test_cancel_reset_isolation() -> void:
	var track := _new_rendered_track("CancelTrack")
	track.update_stream(-RunnerConfig.CHUNK_LENGTH - 0.1, DIFFICULTY)
	var job: Variant = track.get("_stream_job")
	var abandoned: Node = job.get("chunk") if job != null else null
	_check(abandoned != null and is_instance_valid(abandoned), "cancel fixture owns detached chunk")
	track.reset(SEED, 1.0)
	_check(not is_instance_valid(abandoned), "reset frees detached job immediately")
	var snapshot := track.perf_trace_snapshot(0.0)
	_check(not bool(snapshot["stream_build_pending"]), "reset clears pending state")
	_check(int(snapshot["next_chunk"]) == RunnerConfig.CHUNKS_AHEAD,
			"reset restores synchronous opening horizon")

	var fresh := RunnerTrack.new()
	fresh.name = "FreshResetReference"
	# reset() follows runtime headless detection; compare against same contract,
	# not the explicit rendered fixture used to create the canceled job.
	fresh.setup(SEED, 1.0)
	for index: int in RunnerConfig.CHUNKS_AHEAD:
		var reset_chunk := track.get_node_or_null("Chunk%d" % index)
		var fresh_chunk := fresh.get_node_or_null("Chunk%d" % index)
		_check(reset_chunk != null and fresh_chunk != null
				and _node_signature(reset_chunk) == _node_signature(fresh_chunk),
				"reset chunk %d has no abandoned RNG/state" % index)
	fresh.free()
	# Scene deletion must own and free a pending detached subtree too.
	track.setup(SEED, 1.0, 1)
	track.update_stream(-RunnerConfig.CHUNK_LENGTH - 0.1, DIFFICULTY)
	var exit_job: Variant = track.get("_stream_job")
	var exit_chunk: Node = exit_job.get("chunk") if exit_job != null else null
	track.free()
	_check(not is_instance_valid(exit_chunk), "scene exit frees detached job")


func _test_max_speed_horizon(fps: int) -> void:
	var track := _new_rendered_track("Horizon%d" % fps)
	# Start near NIGHT->DAY wrap at full difficulty: high-density patterns and
	# a biome transition exercise worst-case work, without a multi-minute test.
	var start_index := ceili(RunnerConfig.BIOME_LENGTH * RunnerTrack.BIOME_COUNT / RunnerConfig.CHUNK_LENGTH) - 1
	track._clear()
	track.set("_first_index", start_index)
	track.set("_next_index", start_index)
	for index: int in range(start_index, start_index + RunnerConfig.CHUNKS_AHEAD):
		track._spawn_chunk(index, 1.0)
	var player_z := -float(start_index) * RunnerConfig.CHUNK_LENGTH
	var min_horizon := INF
	var max_disposal_pending := 0
	# One complete current biome cycle plus a chunk past the initial wrap.
	#72s only covered all biomes before the intentional600m->1800m pacing change.
	var seconds := ceili((RunnerConfig.BIOME_LENGTH * RunnerTrack.BIOME_COUNT
			+ RunnerConfig.CHUNK_LENGTH) / RunnerConfig.MAX_SPEED)
	var biomes_seen: Dictionary = {}
	for _frame: int in fps * seconds:
		player_z -= RunnerConfig.MAX_SPEED / float(fps)
		track.update_stream(player_z, 1.0)
		biomes_seen[track.biome_at_z(player_z)] = true
		var next_index := int(track.get("_next_index"))
		var far_edge := -float(next_index) * RunnerConfig.CHUNK_LENGTH
		min_horizon = minf(min_horizon, player_z - far_edge)
		var retiring: Array = track.get("_retiring_chunks")
		max_disposal_pending = maxi(max_disposal_pending, retiring.size())
	_check(min_horizon >= 70.0, "%d FPS max-speed horizon stays readable" % fps,
			"minimum=%.2fm" % min_horizon)
	_check(int(track.get("_next_index")) > start_index + RunnerConfig.CHUNKS_AHEAD + 6,
			"%d FPS simulation exercises sustained churn" % fps)
	_check(biomes_seen.size() == RunnerTrack.BIOME_COUNT,
			"%d FPS full-difficulty horizon crosses all biomes" % fps,
			str(biomes_seen.keys()))
	_check(max_disposal_pending <= 3,
			"%d FPS full-difficulty disposal backlog remains bounded" % fps,
			"maximum=%d detached chunks" % max_disposal_pending)
	track.free()


func _test_mover_reservation_phase() -> void:
	var sync := _new_rendered_track("MoverSync")
	var staged := _new_rendered_track("MoverStaged")
	var index := RunnerConfig.CHUNKS_AHEAD
	sync._spawn_chunk(index, DIFFICULTY)
	var sync_chunk := sync.get_node("Chunk%d" % index)
	sync.set("_air_from_z", 1.0e9)
	sync.set("_air_to_z", 1.0e9)
	sync._add_seal(sync_chunk, -11.0, 0.47, 5.2)
	var sync_probe := sync_chunk.get_child(sync_chunk.get_child_count() - 1)
	sync_probe.name = "PhaseProbe"
	staged.update_stream(-RunnerConfig.CHUNK_LENGTH - 0.1, DIFFICULTY)
	var job: Variant = staged.get("_stream_job")
	var detached: Node = job.get("chunk")
	staged.set("_air_from_z", 1.0e9)
	staged.set("_air_to_z", 1.0e9)
	staged._add_seal(detached, -11.0, 0.47, 5.2)
	var staged_probe := detached.get_child(detached.get_child_count() - 1)
	staged_probe.name = "PhaseProbe"
	var guard := 0
	while staged.get_node_or_null("Chunk%d" % index) == null and guard < 256:
		await get_tree().process_frame
		staged.update_stream(-RunnerConfig.CHUNK_LENGTH - 0.1, DIFFICULTY)
		guard += 1
	await get_tree().process_frame
	var committed_probe := staged.get_node_or_null("Chunk%d/PhaseProbe" % index)
	_check(committed_probe != null, "moving hazard probe commits")
	if committed_probe != null:
		_check(absf(float(committed_probe.get("_time")) - float(sync_probe.get("_time")))
				<= 0.0002, "moving hazard preserves reservation-relative time",
				"sync=%.6f staged=%.6f" % [float(sync_probe.get("_time")),
					float(committed_probe.get("_time"))])
		_check(absf((committed_probe as Node3D).position.x
				- (sync_probe as Node3D).position.x) <= 0.002,
				"moving hazard collision phase preserved")
	sync.free()
	staged.free()


func _runner_group_counts() -> Dictionary:
	return {
		"hazard": get_tree().get_nodes_in_group(RunnerConfig.GROUP_HAZARD).size(),
		"pickup": get_tree().get_nodes_in_group(RunnerConfig.GROUP_PICKUP).size(),
		"powerup": get_tree().get_nodes_in_group(RunnerConfig.GROUP_POWERUP).size(),
	}


## Stable structural signature: no object IDs or autogenerated Node names.
## Includes gameplay metadata/colliders and rendered mesh/material/MM layout.
func _node_signature(root: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	_append_node_signature(root, "0", result)
	return result


func _append_node_signature(node: Node, path: String,
		result: Array[Dictionary]) -> void:
	var node_name := String(node.name)
	if node_name.begins_with("@"):
		node_name = node.get_class()
	var row: Dictionary = {
		"path": path,
		"class": node.get_class(),
		"name": node_name,
	}
	if node is Node3D:
		row["transform"] = (node as Node3D).transform
	var groups := PackedStringArray()
	for group: StringName in node.get_groups():
		groups.append(String(group))
	groups.sort()
	row["groups"] = groups
	for key: String in ["kind", "lane", "span", "powerup", "authored_asset_id",
			"static_light_cues"]:
		if node.has_meta(key):
			row[key] = node.get_meta(key)
	if node is CollisionShape3D:
		var shape := (node as CollisionShape3D).shape
		if shape is BoxShape3D:
			row["shape"] = ["box", (shape as BoxShape3D).size]
		elif shape is SphereShape3D:
			row["shape"] = ["sphere", (shape as SphereShape3D).radius]
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		row["mesh"] = _mesh_signature(mesh_node.mesh)
		row["material"] = _material_signature(mesh_node.material_override)
		var overrides: Array = []
		if mesh_node.mesh != null:
			for surface: int in mesh_node.mesh.get_surface_count():
				overrides.append(_material_signature(
						mesh_node.get_surface_override_material(surface)))
		row["surface_overrides"] = overrides
	elif node is MultiMeshInstance3D:
		var mm_node := node as MultiMeshInstance3D
		row["material"] = _material_signature(mm_node.material_override)
		var mm := mm_node.multimesh
		if mm != null:
			row["mesh"] = _mesh_signature(mm.mesh)
			row["instance_count"] = mm.instance_count
			var transforms: Array[Transform3D] = []
			var colors: PackedColorArray = PackedColorArray()
			for instance: int in mm.instance_count:
				transforms.append(mm.get_instance_transform(instance))
				if mm.use_colors:
					colors.append(mm.get_instance_color(instance))
			row["instances"] = transforms
			row["colors"] = colors
	result.append(row)
	var child_index := 0
	for child: Node in node.get_children():
		_append_node_signature(child, "%s/%d" % [path, child_index], result)
		child_index += 1


func _mesh_signature(mesh: Mesh) -> Variant:
	if mesh == null:
		return null
	return [mesh.get_class(), mesh.resource_path, mesh.get_surface_count(), mesh.get_aabb()]


func _material_signature(material: Material) -> Variant:
	if material == null:
		return null
	var result: Dictionary = {
		"class": material.get_class(),
		"path": material.resource_path,
	}
	if material is BaseMaterial3D:
		var base := material as BaseMaterial3D
		result["albedo"] = base.albedo_color
		result["metallic"] = base.metallic
		result["roughness"] = base.roughness
		result["cull"] = base.cull_mode
	elif material is ShaderMaterial:
		var shader_material := material as ShaderMaterial
		result["shader_path"] = shader_material.shader.resource_path \
				if shader_material.shader != null else ""
		var parameters: Dictionary = {}
		for property: Dictionary in shader_material.get_property_list():
			var property_name := String(property.get("name", ""))
			if property_name.begins_with("shader_parameter/"):
				var value: Variant = shader_material.get(property_name)
				if value == null or value is bool or value is int or value is float \
						or value is String or value is StringName or value is Color \
						or value is Vector2 or value is Vector3 or value is Vector4:
					parameters[property_name] = value
		result["parameters"] = parameters
	return result
