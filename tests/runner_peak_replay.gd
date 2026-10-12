extends "res://tests/runner_perf_probe.gd"
## UNTIMED sequential replay around a previously recorded primitive peak.
## No gameplay seeking, manual chunk construction, FPS or performance gate.

const FAMILY_ASSETS: Dictionary = {
	"deck": RunnerTrack.DAY_DECK_ASSETS,
	"radar": [RunnerTrack.DAY_RADAR_ASSET],
	"icebreaker": [RunnerTrack.DAY_ICEBREAKER_ASSET],
}
const MAX_DISTANCE_ERROR: float = 1.0
const COUNTER_SAMPLES: int = 4
const RADAR_LIVE_GLB: String = "res://assets/art/runner/day/runner_day_radar_landmark_v1.glb"
const RADAR_FAR_ENTER_PX: float = 80.0
const RADAR_FAR_EXIT_PX: float = 96.0
const RADAR_MOTION_FPS: int = 30
const RADAR_MOTION_FRAMES: int = 90
const REPLAY_TIMEOUT_MSEC: int = 90_000
const EXTENDED_INSPECTION_TIMEOUT_MSEC: int = 120_000

var _reference_path: String = ""
var _reference: Dictionary = {}
var _target_distance: float = 0.0
var _replay_started_msec: int = 0
var _freeze_started: bool = false
var _report: Dictionary = {}
var _lod_sweep: bool = false
var _radar_candidate_path: String = ""
var _radar_binding_path: String = ""
var _radar_authoring_path: String = ""
var _radar_candidate_mesh: ArrayMesh
var _radar_candidate_evidence: Dictionary = {}
var _radar_swap_states: Array[Dictionary] = []
var _radar_extended: bool = false
var _inspection_started_msec: int = 0


func _ready() -> void:
	_out_path = "user://qa/runner_peak_replay.json"
	_parse_args()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("reference="):
			_reference_path = arg.trim_prefix("reference=")
		elif arg == "lod_sweep=true":
			_lod_sweep = true
		elif arg.begins_with("radar_candidate="):
			_radar_candidate_path = arg.trim_prefix("radar_candidate=")
		elif arg.begins_with("radar_binding="):
			_radar_binding_path = arg.trim_prefix("radar_binding=")
		elif arg.begins_with("radar_authoring="):
			_radar_authoring_path = arg.trim_prefix("radar_authoring=")
		elif arg == "radar_extended=true":
			_radar_extended = true
	if GameConfig.is_headless():
		_abort("runner_peak_replay requires a rendering window")
		return
	var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(_reference_path))
	if not decoded is Dictionary or not decoded.has("peak_primitive_sample"):
		_abort("runner_peak_replay requires a valid reference report")
		return
	_reference = decoded
	_tier = String(_reference.get("tier", ""))
	var resolution: Array = _reference.get("requested_resolution", [])
	if _tier != "high" or not _resolution_matches(resolution) \
			or int(_reference.get("seed", 0)) != 20260907:
		_abort("runner_peak_replay is scoped to seed20260907 high1920x1080")
		return
	_width = 1920
	_height = 1080
	_seed = 20260907
	_target_distance = float(_reference.peak_primitive_sample.distance)
	_build_fingerprint = _capture_build_fingerprint()
	_report = {
		"schema_version": 1,
		"mode": "untimed_peak_equivalent_sequential_replay",
		"scope": "Separate normal run from zero; not a historical frame replay or FPS benchmark. No gameplay teleport or chunk reconstruction.",
		"reference_path": _reference_path,
		"reference_sha256": FileAccess.get_sha256(_reference_path),
		"reference_peak": _reference.peak_primitive_sample,
		"build_fingerprint": _build_fingerprint,
		"diagnostic_script_sha256": FileAccess.get_sha256("res://tests/runner_peak_replay.gd"),
		"primitive_monitor_note": PRIMITIVE_MONITOR_NOTE,
		"counter_scope": "Frozen-family hide/restore engine-counter differences only; no FPS, GPU-time or corrected MultiMesh cost claim. Shader TIME may still advance.",
	}
	if not _build_fingerprint.complete or _build_fingerprint.source_assets_sha256 \
			!= _reference.build_fingerprint.source_assets_sha256:
		_fail_report("Comparable source/asset fingerprint differs from reference")
		return
	if not _radar_candidate_path.is_empty():
		if not _load_radar_candidate():
			_fail_report("QA radar candidate binding/import validation failed")
			return
	_apply_quality_without_persisting()
	DisplayServer.window_set_size(Vector2i(_width, _height))
	DisplayServer.window_set_position(Vector2i(40, 60))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()
	var packed := load(Game.SCENE_RUNNER) as PackedScene
	if packed == null:
		_fail_report("Runner scene could not load")
		return
	RunnerPlayer.autopilot = true
	_replay_started_msec = Time.get_ticks_msec()
	_game = packed.instantiate() as RunnerGame
	_game.generation_seed = _seed
	add_child(_game)
	print("[runner_peak_replay] UNTIMED sequential target=%.9fm seed=%d" % [_target_distance, _seed])


func _process(_delta: float) -> void:
	if _finished or _game == null:
		return
	var timeout := _diagnostic_timeout_reason(Time.get_ticks_msec() - _replay_started_msec,
		Time.get_ticks_msec() - _inspection_started_msec, _freeze_started, _radar_extended)
	if not timeout.is_empty():
		_fail_report(timeout)
		return
	if _freeze_started:
		return
	if not _game.build_finished or not _game.running:
		if _seen_running:
			_fail_report("Runner stopped before target")
		return
	_seen_running = true
	if _game.player.distance >= _target_distance:
		_freeze_started = true
		_freeze_and_inspect()


func _freeze_and_inspect() -> void:
	# Parent _process observes the completed preceding RunnerGame tick. Disable
	# the whole subtree before this frame can advance normal gameplay again.
	_inspection_started_msec = Time.get_ticks_msec()
	_game.process_mode = Node.PROCESS_MODE_DISABLED
	_game.player.set_input_enabled(false)
	RunnerPlayer.autopilot = false
	_freeze_particles(_game)
	var context := _game.track.perf_trace_snapshot(_game.player.position.z)
	context["distance"] = _game.player.distance
	context["distance_error"] = _game.player.distance - _target_distance
	context["resolution"] = [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]
	context["effective_tier"] = SettingsManager.get_setting("display", "quality_preset")
	context["chunks"] = []
	for chunk: RunnerTrack.RunnerChunk in _game.track._chunks:
		(context.chunks as Array).append({"index": chunk.index,
			"pattern": chunk.pattern, "difficulty": chunk.difficulty, "biome": chunk.biome})
	_report["replay_context"] = context
	var checks := _context_checks(context)
	_report["context_checks"] = checks
	if false in checks.values():
		_fail_report("Peak-equivalent context validation failed")
		return
	var camera: Dictionary = _reference.peak_primitive_sample.camera
	_game.camera.global_transform = Transform3D(Basis(_from_array(camera.basis_x),
			_from_array(camera.basis_y), _from_array(camera.basis_z)), _from_array(camera.position))
	_game.camera.fov = float(camera.fov)
	_game.camera.near = float(camera.near)
	_game.camera.far = float(camera.far)
	get_viewport().mesh_lod_threshold = float(camera.viewport_mesh_lod_threshold)
	_report["camera_pinned_from_reference"] = camera
	_report["census"] = _final_census_report(_game, true, _game.player.distance, 0.0)
	_report["census_note"] = "Helper's final-scene inventory is captured once at this untimed replay's frozen endpoint. Local visibility/LOD0 inventory, not historical peak or GPU visibility."
	var families: Dictionary = {}
	_find_families(_game, families)
	var experiments: Array[Dictionary] = []
	for family: String in FAMILY_ASSETS:
		var nodes: Array = families.get(family, [])
		if nodes.is_empty():
			_fail_report("Expected authored family missing: " + family)
			return
		var before: Array[Dictionary] = await _counter_window()
		var original_visibility: Array[bool] = []
		for node: Node3D in nodes:
			original_visibility.append(node.visible)
			node.visible = false
		var hidden: Array[Dictionary] = await _counter_window()
		for index: int in nodes.size():
			(nodes[index] as Node3D).visible = original_visibility[index]
		var restored: Array[Dictionary] = await _counter_window()
		experiments.append({"family": family, "node_count": nodes.size(),
			"before": before, "hidden": hidden, "restored": restored,
			"before_stable": _counters_stable(before), "hidden_stable": _counters_stable(hidden),
			"restored_stable": _counters_stable(restored),
			"before_minus_hidden": _counter_difference(before[-1], hidden[-1]),
			"restored_minus_before": _counter_difference(restored[-1], before[-1]),
			"visibility_restored": true})
	_report["family_experiments"] = experiments
	if _lod_sweep:
		_report["landmark_lod_sweep"] = await _inspect_landmark_lods(families)
	if _radar_candidate_mesh != null:
		_report["radar_candidate_comparison"] = await _inspect_radar_candidate()
		if _finished:
			return
		if not bool(_report.radar_candidate_comparison.success):
			_fail_report("QA radar candidate comparison/restoration failed")
			return
	_report["success"] = true
	await _write_and_exit(0)


static func _context_checks(context: Dictionary) -> Dictionary:
	return {
		"day_chunk7": int(context.get("current_biome", -1)) == 0 \
			and int(context.get("current_chunk", -1)) == 7,
		"resident_chunks5_through13": int(context.get("first_chunk", -1)) == 5 \
			and int(context.get("next_chunk", -1)) == 14 and int(context.get("live_chunks", -1)) == 9,
		"no_tunnels": int(context.get("tunnel_chunks", -1)) == 0,
		"distance_error_within_one_metre": float(context.get("distance_error", INF)) >= 0.0 \
			and float(context.get("distance_error", INF)) <= MAX_DISTANCE_ERROR,
		"resolution_and_tier": _resolution_matches(context.get("resolution", [])) \
			and context.get("effective_tier", "") == "high",
	}


static func _diagnostic_timeout_reason(replay_elapsed: int, inspection_elapsed: int,
		inspection_started: bool, extended: bool) -> String:
	if extended and inspection_started:
		return "Extended inspection exceeded 120-second capture timeout" \
			if inspection_elapsed > EXTENDED_INSPECTION_TIMEOUT_MSEC else ""
	return "Replay exceeded 90-second diagnostic timeout" \
		if replay_elapsed > REPLAY_TIMEOUT_MSEC else ""


static func _resolution_matches(value: Variant) -> bool:
	# JSON parses numbers as floats; Array equality also compares element types.
	return value is Array and value.size() == 2 \
			and (value[0] is int or value[0] is float) \
			and (value[1] is int or value[1] is float) \
			and float(value[0]) == 1920.0 and float(value[1]) == 1080.0


static func _from_array(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


static func _freeze_particles(node: Node) -> void:
	if node is GPUParticles3D:
		(node as GPUParticles3D).speed_scale = 0.0
	elif node is CPUParticles3D:
		(node as CPUParticles3D).speed_scale = 0.0
	for child: Node in node.get_children():
		_freeze_particles(child)


static func _find_families(node: Node, result: Dictionary) -> void:
	if node is Node3D:
		var asset_id := String(node.get_meta("authored_asset_id", ""))
		for family: String in FAMILY_ASSETS:
			if asset_id in FAMILY_ASSETS[family]:
				if not result.has(family):
					result[family] = []
				(result[family] as Array).append(node)
	for child: Node in node.get_children():
		_find_families(child, result)


func _counter_window() -> Array[Dictionary]:
	# Visibility updates are submitted before two complete draw boundaries.
	for _settle: int in 2:
		await RenderingServer.frame_post_draw
	var samples: Array[Dictionary] = []
	for _sample: int in COUNTER_SAMPLES:
		await RenderingServer.frame_post_draw
		var rid := get_viewport().get_viewport_rid()
		samples.append({
			"total_primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			"total_draws": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			"visible_primitives": RenderingServer.viewport_get_render_info(rid,
				RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
			"shadow_primitives": RenderingServer.viewport_get_render_info(rid,
				RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		})
	return samples


static func _counters_stable(samples: Array[Dictionary]) -> bool:
	if samples.is_empty():
		return false
	for sample: Dictionary in samples:
		if sample != samples[0]:
			return false
	return true


static func _counter_difference(first: Dictionary, second: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in first:
		result[key] = int(first[key]) - int(second[key])
	return result


static func _sha256_shape(value: Variant) -> bool:
	if not value is String or value.length() != 64:
		return false
	for character: String in value:
		if not character in "0123456789abcdef":
			return false
	return true


static func _candidate_binding_checks(binding: Dictionary, authoring: Dictionary,
		candidate_hash: String, candidate_exists: bool, live_hash: String) -> Dictionary:
	var input_hashes: Dictionary = binding.get("input_sha256", {}) \
		if binding.get("input_sha256", {}) is Dictionary else {}
	var inputs_valid: bool = not input_hashes.is_empty()
	if inputs_valid:
		for path: Variant in input_hashes:
			inputs_valid = inputs_valid and path is String and _sha256_shape(input_hashes[path])
	var import_contract: Dictionary = authoring.get("qa_import_contract", {})
	return {
		"candidate_exists": candidate_exists,
		"candidate_hash_bound": _sha256_shape(candidate_hash) \
			and candidate_hash == binding.get("candidate_sha256", ""),
		"qa_only_unapproved": binding.get("qa_only") == true \
			and binding.get("production_ready") == false \
			and binding.get("visual_quality_approved") == false \
			and binding.get("runtime_changed") == false,
		"deterministic_build": binding.get("independent_rebuild_byte_identical") == true,
		"source_hashes_present": inputs_valid,
		"live_source_bound": _sha256_shape(live_hash) \
			and authoring.get("live_glb_sha256", "") == live_hash \
			and input_hashes.get(RADAR_LIVE_GLB.trim_prefix("res://"), "") == live_hash,
		"authored_bounds_and_surface": authoring.get("global_bounds_exact") == true \
			and int(authoring.get("material_contract", {}).get("surface_count", 0)) == 1,
		"automatic_lods_forbidden": import_contract.get("meshes/generate_lods") == false \
			and int(import_contract.get("require_actual_imported_lod_count", -1)) == 0,
	}


func _load_radar_candidate() -> bool:
	var binding: Variant = JSON.parse_string(FileAccess.get_file_as_string(_radar_binding_path))
	var authoring: Variant = JSON.parse_string(FileAccess.get_file_as_string(_radar_authoring_path))
	if not binding is Dictionary or not authoring is Dictionary:
		return false
	var checks := _candidate_binding_checks(binding, authoring,
		FileAccess.get_sha256(_radar_candidate_path), FileAccess.file_exists(_radar_candidate_path),
		FileAccess.get_sha256(RADAR_LIVE_GLB))
	_radar_candidate_evidence = {"candidate_res": _radar_candidate_path,
		"candidate_sha256": FileAccess.get_sha256(_radar_candidate_path),
		"binding_sha256": FileAccess.get_sha256(_radar_binding_path),
		"authoring_sha256": FileAccess.get_sha256(_radar_authoring_path),
		"binding": binding, "authoring": authoring, "checks": checks,
		"scope": "Explicit different-asset QA experiment. Live build fingerprint describes baseline only; it does not approve the override, fidelity, performance or production use."}
	_report["radar_candidate_binding"] = _radar_candidate_evidence
	if false in checks.values():
		return false
	var config := ConfigFile.new()
	checks["normal_import_config"] = config.load(_radar_candidate_path + ".import") == OK \
		and config.get_value("remap", "importer", "") == "scene" \
		and config.get_value("params", "meshes/generate_lods", true) == false \
		and config.get_value("params", "_subresources", {}) == {}
	var packed := load(_radar_candidate_path) as PackedScene
	checks["normal_packed_scene"] = packed != null
	if packed == null:
		return false
	var root := packed.instantiate()
	var parts: Array[Dictionary] = []
	_collect_candidate_parts(root, Transform3D.IDENTITY, parts)
	checks["one_identity_mesh"] = parts.size() == 1 \
		and (parts[0].transform as Transform3D).is_equal_approx(Transform3D.IDENTITY)
	if checks.one_identity_mesh:
		_radar_candidate_mesh = parts[0].mesh as ArrayMesh
	root.free()
	checks["array_mesh_one_surface"] = _radar_candidate_mesh != null \
		and _radar_candidate_mesh.get_surface_count() == 1
	if checks.array_mesh_one_surface:
		var census := _mesh_census(_radar_candidate_mesh)
		_radar_candidate_evidence["actual_imported_mesh"] = census
		checks["actual_imported_zero_lods"] = census.surfaces[0].baked_lods.is_empty()
		checks["triangle_count_bound"] = int(census.lod0_triangles) \
			== int(authoring.get("triangles", {}).get("candidate", -1))
	return not false in checks.values()


static func _collect_candidate_parts(node: Node, parent_transform: Transform3D,
		parts: Array[Dictionary]) -> void:
	var transform := parent_transform
	if node is Node3D:
		transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		parts.append({"mesh": (node as MeshInstance3D).mesh, "transform": transform})
	for child: Node in node.get_children():
		_collect_candidate_parts(child, transform, parts)


static func _capture_multimesh_states(node: Node, states: Array[Dictionary]) -> void:
	if node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
		var visual := node as MultiMeshInstance3D
		states.append({"node": visual, "multimesh": visual.multimesh, "mesh": visual.multimesh.mesh,
			"radar": String(visual.get_meta("authored_asset_id", "")) == RunnerTrack.DAY_RADAR_ASSET,
			"transform": visual.transform, "global_transform": visual.global_transform,
			"buffer": visual.multimesh.buffer.duplicate(), "count": visual.multimesh.instance_count,
			"visible_count": visual.multimesh.visible_instance_count,
			"material": visual.material_override, "overlay": visual.material_overlay,
			"lod_bias": visual.lod_bias, "visible": visual.visible,
			"layers": visual.layers, "shadow": visual.cast_shadow})
	for child: Node in node.get_children():
		_capture_multimesh_states(child, states)


static func _swap_radar_mesh(states: Array[Dictionary], candidate: Mesh) -> bool:
	if candidate == null or not _mesh_swap_invariants(states):
		return false
	var radar_count := 0
	for state: Dictionary in states:
		if not state.radar:
			continue
		radar_count += 1
		# A shared MultiMesh outside radar would turn one assignment into an
		# unintended family change. Reject the entire transaction before writing.
		for other: Dictionary in states:
			if not other.radar and other.multimesh == state.multimesh:
				return false
	if radar_count == 0:
		return false
	for state: Dictionary in states:
		if state.radar:
			(state.multimesh as MultiMesh).mesh = candidate
	return true


static func _restore_radar_meshes(states: Array[Dictionary]) -> void:
	for state: Dictionary in states:
		if state.radar:
			(state.multimesh as MultiMesh).mesh = state.mesh


static func _mesh_swap_invariants(states: Array[Dictionary], candidate: Mesh = null) -> bool:
	for state: Dictionary in states:
		if not is_instance_valid(state.node):
			return false
		var node := state.node as MultiMeshInstance3D
		var expected: Mesh = candidate if state.radar and candidate != null else state.mesh
		if node.multimesh != state.multimesh or node.multimesh.mesh != expected \
				or node.transform != state.transform or node.global_transform != state.global_transform \
				or node.multimesh.buffer != state.buffer or node.multimesh.instance_count != state.count \
				or node.multimesh.visible_instance_count != state.visible_count \
				or node.material_override != state.material or node.material_overlay != state.overlay \
				or node.lod_bias != state.lod_bias or node.visible != state.visible \
				or node.layers != state.layers or node.cast_shadow != state.shadow:
			return false
	return true


func _inspect_radar_candidate() -> Dictionary:
	var result := {"success": false, "cases": [], "scope": "Only radar MultiMesh.mesh changes. Instance buffers/transforms, material overrides, visibility and every non-radar MultiMesh remain exact. Counters are not FPS or GPU-time evidence."}
	# Keep the same dictionaries visible to failure reporting while awaits run.
	_report["radar_candidate_comparison"] = result
	_capture_multimesh_states(_game, _radar_swap_states)
	var radar: MultiMeshInstance3D
	var radar_count := 0
	for state: Dictionary in _radar_swap_states:
		if state.radar:
			radar = state.node
			radar_count += 1
	result["radar_node_count"] = radar_count
	result["guarded_multimesh_nodes"] = _radar_swap_states.size()
	if radar == null or not radar.multimesh.mesh.get_aabb().is_equal_approx(_radar_candidate_mesh.get_aabb()):
		result["error"] = "Missing radar or imported candidate bounds/pivot mismatch"
		_radar_swap_states.clear()
		return result
	result["actual_imported_bounds_match"] = true
	var camera := _game.camera
	var original_transform := camera.global_transform
	var original_fov := camera.fov
	var bounds: AABB = radar.global_transform * radar.multimesh.get_aabb()
	var directory := ProjectSettings.globalize_path(_out_path).get_base_dir()
	var okay := true
	var views: Array[String] = ["recorded_gameplay", "framed_close_inspection"]
	if _radar_extended:
		views.append_array(["window_wall_plus_z", "window_wall_minus_z",
			"window_threequarter_plus_z", "window_threequarter_minus_z"])
	for view: String in views:
		camera.global_transform = original_transform
		camera.fov = original_fov
		if view == "framed_close_inspection":
			var center := bounds.get_center()
			var direction := (original_transform.origin - center).normalized()
			camera.fov = 45.0
			camera.global_position = center + direction * bounds.size.length() * 0.5 / sin(deg_to_rad(22.5)) * 1.15
			camera.look_at(center, Vector3.UP)
		elif view.begins_with("window_"):
			# Authored Blender +/-Y window walls become imported local +/-Z.
			# Follow the actual instance basis; never rotate/rebuild the landmark.
			var sign_z := -1.0 if view.ends_with("minus_z") else 1.0
			var local_direction := Vector3(0.7 if "threequarter" in view else 0.0, 0.0, sign_z)
			var instance_basis := radar.global_basis * radar.multimesh.get_instance_transform(0).basis
			var direction := ((instance_basis * local_direction).normalized() + Vector3.UP * 0.16).normalized()
			camera.fov = 45.0
			_fit_radar_camera_height(bounds, direction, 760.0)
		var baseline: Array[Dictionary] = await _counter_window()
		if _finished:
			return result
		var baseline_footprint := _landmark_footprint(radar)
		var baseline_image := "radar_candidate_%s_baseline.png" % view
		var baseline_error := get_viewport().get_texture().get_image().save_png(directory.path_join(baseline_image))
		var swapped := _swap_radar_mesh(_radar_swap_states, _radar_candidate_mesh)
		var candidate: Array[Dictionary] = await _counter_window()
		if _finished:
			return result
		var swap_exact := _mesh_swap_invariants(_radar_swap_states, _radar_candidate_mesh)
		var candidate_footprint := _landmark_footprint(radar)
		var candidate_image := "radar_candidate_%s_authored_lod1.png" % view
		var candidate_error := get_viewport().get_texture().get_image().save_png(directory.path_join(candidate_image))
		_restore_radar_meshes(_radar_swap_states)
		var restored: Array[Dictionary] = await _counter_window()
		if _finished:
			return result
		var restore_exact := _mesh_swap_invariants(_radar_swap_states)
		okay = okay and swapped and swap_exact and restore_exact and baseline_error == OK and candidate_error == OK
		result.cases.append({"view": view, "baseline": baseline, "candidate": candidate, "restored": restored,
			"baseline_image": baseline_image, "candidate_image": candidate_image,
			"baseline_image_error": baseline_error, "candidate_image_error": candidate_error,
			"baseline_footprint": baseline_footprint, "candidate_footprint": candidate_footprint,
			"swap_exact_only_radar_mesh": swap_exact, "restored_exact": restore_exact,
			"baseline_stable": _counters_stable(baseline), "candidate_stable": _counters_stable(candidate),
			"restored_stable": _counters_stable(restored),
			"baseline_minus_candidate": _counter_difference(baseline[-1], candidate[-1]),
			"restored_minus_baseline": _counter_difference(restored[-1], baseline[-1])})
		if not okay:
			break
	if okay and _radar_extended:
		camera.global_transform = original_transform
		camera.fov = original_fov
		result["distance_transition"] = await _capture_radar_distance_transition(radar, bounds, directory)
		if _finished:
			return result
		okay = bool(result.distance_transition.success)
	_restore_radar_meshes(_radar_swap_states)
	_radar_swap_states.clear()
	camera.global_transform = original_transform
	camera.fov = original_fov
	result["success"] = okay
	return result


static func _radar_far_lod_state(was_candidate: bool, projected_height: float) -> bool:
	if not is_finite(projected_height) or projected_height <= 0.0:
		return false
	return projected_height < RADAR_FAR_EXIT_PX if was_candidate else projected_height <= RADAR_FAR_ENTER_PX


static func _radar_motion_target_height(frame: int) -> float:
	var half := RADAR_MOTION_FRAMES / 2
	var step := frame if frame < half else RADAR_MOTION_FRAMES - 1 - frame
	var alpha := smoothstep(0.0, 1.0, float(step) / float(half - 1))
	return lerpf(60.0, 120.0, alpha)


static func _projected_bounds_height(camera: Camera3D, bounds: AABB) -> float:
	var low := INF
	var high := -INF
	for corner: int in 8:
		var point := bounds.get_endpoint(corner)
		if camera.is_position_behind(point):
			return INF
		var screen_y := camera.unproject_position(point).y
		low = minf(low, screen_y)
		high = maxf(high, screen_y)
	return high - low


func _fit_radar_camera_height(bounds: AABB, direction: Vector3, target_height: float,
		aim_offset: Vector3 = Vector3.ZERO) -> float:
	var camera := _game.camera
	var center := bounds.get_center()
	var low := bounds.size.length() * 0.55
	var high := bounds.size.length() * 100.0
	for iteration: int in 24:
		var distance := (low + high) * 0.5
		camera.global_position = center + direction * distance
		camera.look_at(center + aim_offset, Vector3.UP)
		if _projected_bounds_height(camera, bounds) > target_height:
			low = distance
		else:
			high = distance
	return _projected_bounds_height(camera, bounds)


func _capture_radar_distance_transition(radar: MultiMeshInstance3D, bounds: AABB,
		directory: String) -> Dictionary:
	var result := {"success": false, "fps": RADAR_MOTION_FPS, "frames_per_sequence": RADAR_MOTION_FRAMES,
		"enter_candidate_at_or_below_px": RADAR_FAR_ENTER_PX, "exit_candidate_at_or_above_px": RADAR_FAR_EXIT_PX,
		"height_scope": "Conservative projected world-AABB height at1920x1080, not silhouette height or a live LOD policy.",
		"timing_scope": "Fixed camera sample timeline30fps; wall-clock rendering/capture rate is not measured. Frozen gameplay/world; shader TIME may advance.",
		"sequences": [], "source_window_walls": "Blender +/-Y -> imported +/-Z; seven windows on each wall."}
	_report.radar_candidate_comparison["distance_transition"] = result
	var camera := _game.camera
	# Backing up the chase bearing crosses the existing avalanche. Orbit to
	# the actual window-wall three-quarter bearing without hiding any world
	# object, and frame above unchanged center HUD/contact text.
	var instance_basis := radar.global_basis * radar.multimesh.get_instance_transform(0).basis
	var direction := ((instance_basis * Vector3(0.6, 0.0, -1.0)).normalized() + Vector3.UP * 0.16).normalized()
	var aim_offset := Vector3.DOWN * bounds.size.y * 1.5
	result["camera_path_scope"] = "Window-wall three-quarter inspection bearing; not chase gameplay. Chase-backtrack is occluded by existing avalanche. World and HUD unchanged; target framed above center contact text."
	result["world_camera_bearing"] = _vector_components(direction)
	result["world_aim_offset"] = _vector_components(aim_offset)
	var timeline: Array[Transform3D] = []
	var baseline_global_poses: Array[Transform3D] = []
	var maximum_height_error := 0.0
	result["camera_scale_disabled"] = camera.is_scale_disabled()
	result["camera_assignment"] = "Canonical local transforms avoid Camera3D global disable-scale recanonicalization. Exact local timeline and paired actual global transforms are both checked; no approximate-equality gate."
	for frame: int in RADAR_MOTION_FRAMES:
		var target_height := _radar_motion_target_height(frame)
		var actual_height := _fit_radar_camera_height(bounds, direction, target_height, aim_offset)
		maximum_height_error = maxf(maximum_height_error, absf(actual_height - target_height))
		var canonical_local := camera.transform
		if frame == 0:
			var before := camera.global_transform
			camera.global_transform = before
			result["global_reassignment_max_component_delta"] = _transform_component_delta(before, camera.global_transform)
			camera.transform = canonical_local
			result["local_reassignment_max_component_delta"] = _transform_component_delta(before, camera.global_transform)
		timeline.append(canonical_local)
	result["maximum_height_fit_error_px"] = maximum_height_error
	if maximum_height_error > 0.05:
		result["error"] = "Projected-height camera fit did not converge"
		return result
	var okay := true
	for mode: String in ["baseline", "far_lod_policy"]:
		_restore_radar_meshes(_radar_swap_states)
		var candidate_active := false
		var rows: Array[Dictionary] = []
		var switches: Array[int] = []
		var sequence := {"mode": mode, "frames": rows,
			"switch_frames_including_initial_selection": switches, "restored_exact": false}
		result.sequences.append(sequence)
		var subdirectory := "radar_motion_" + mode
		if DirAccess.make_dir_recursive_absolute(directory.path_join(subdirectory)) != OK:
			okay = false
			break
		for frame: int in RADAR_MOTION_FRAMES:
			camera.transform = timeline[frame]
			var measured_height := _projected_bounds_height(camera, bounds)
			var wanted := mode == "far_lod_policy" and _radar_far_lod_state(candidate_active, measured_height)
			if wanted != candidate_active:
				if wanted:
					okay = okay and _swap_radar_mesh(_radar_swap_states, _radar_candidate_mesh)
				else:
					_restore_radar_meshes(_radar_swap_states)
				candidate_active = wanted
				switches.append(frame)
			var samples: Array[Dictionary] = await _counter_window()
			if _finished:
				return result
			var exact := _mesh_swap_invariants(_radar_swap_states, _radar_candidate_mesh if candidate_active else null)
			var image := "%s/frame_%04d.png" % [subdirectory, frame]
			var save_error := get_viewport().get_texture().get_image().save_png(directory.path_join(image))
			var rendered_global := camera.global_transform
			if mode == "baseline":
				baseline_global_poses.append(rendered_global)
			var camera_exact := camera.transform == timeline[frame] \
				and rendered_global == baseline_global_poses[frame]
			okay = okay and exact and camera_exact and save_error == OK
			rows.append({"frame": frame, "time_seconds": float(frame) / RADAR_MOTION_FPS,
				"projected_height_px": measured_height, "candidate_active": candidate_active,
				"image": image, "image_save_error": save_error, "only_expected_mesh_state": exact,
				"camera_exact": camera_exact, "camera_position": _vector_components(camera.global_position),
				"camera_basis_x": _vector_components(camera.global_basis.x),
				"camera_basis_y": _vector_components(camera.global_basis.y),
				"camera_basis_z": _vector_components(camera.global_basis.z), "camera_fov": camera.fov,
				"counters": samples[-1], "counters_stable": _counters_stable(samples)})
			if not okay:
				break
		_restore_radar_meshes(_radar_swap_states)
		var restored := _mesh_swap_invariants(_radar_swap_states)
		okay = okay and restored and rows.size() == RADAR_MOTION_FRAMES
		if mode == "far_lod_policy":
			# One initial selection, one approach exit, one retreat entry.
			okay = okay and switches.size() == 3 and switches[0] == 0
		sequence["restored_exact"] = restored
		if not okay:
			break
	result["success"] = okay
	return result


static func _transform_component_delta(first: Transform3D, second: Transform3D) -> float:
	var delta := (first.origin - second.origin).abs()
	var maximum := maxf(delta.x, maxf(delta.y, delta.z))
	for column: int in 3:
		delta = (first.basis[column] - second.basis[column]).abs()
		maximum = maxf(maximum, maxf(delta.x, maxf(delta.y, delta.z)))
	return maximum


func _inspect_landmark_lods(families: Dictionary) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var camera := _game.camera
	var original_transform := camera.global_transform
	var original_fov := camera.fov
	var original_threshold := get_viewport().mesh_lod_threshold
	var output_directory := ProjectSettings.globalize_path(_out_path).get_base_dir()
	_report["lod_selection_sources"] = [
		"https://github.com/godotengine/godot/blob/4.7.1-stable/drivers/gles3/rasterizer_scene_gles3.cpp#L1429-L1447",
		"https://github.com/godotengine/godot/blob/4.7.1-stable/drivers/gles3/storage/mesh_storage.h#L386-L405",
		"https://github.com/godotengine/godot/blob/4.7.1-stable/servers/rendering/renderer_viewport.cpp#L331",
	]
	for family: String in ["radar", "icebreaker"]:
		var node := families[family][0] as MultiMeshInstance3D
		var original_bias := node.lod_bias
		var world_bounds: AABB = node.global_transform * node.multimesh.get_aabb()
		for view: String in ["recorded_gameplay", "framed_close_inspection"]:
			camera.global_transform = original_transform
			camera.fov = original_fov
			if view == "framed_close_inspection":
				var center := world_bounds.get_center()
				var direction := (original_transform.origin - center).normalized()
				var radius := world_bounds.size.length() * 0.5
				camera.fov = 45.0
				camera.global_position = center + direction * radius / sin(deg_to_rad(22.5)) * 1.15
				camera.look_at(center, Vector3.UP)
			var cases: Array[Dictionary] = []
			for bias: float in [1.0, 0.125, 0.0625, 0.03125, 0.015625, 0.0078125]:
				node.lod_bias = bias
				var counters: Array[Dictionary] = await _counter_window()
				var footprint := _landmark_footprint(node)
				var filename := "%s_%s_bias_%s.png" % [family, view, str(bias).replace(".", "_")]
				var screenshot := get_viewport().get_texture().get_image()
				var image_error := screenshot.save_png(output_directory.path_join(filename))
				cases.append({"bias": bias, "footprint_and_predicted_lod": footprint,
					"counter_samples": counters, "counters_stable": _counters_stable(counters),
					"image": filename, "image_save_error": image_error})
			results.append({"family": family, "view": view, "cases": cases,
				"scope": "QA-only instance lod_bias; same geometry/material/colliders. Framed close view is inspection, not a gameplay composition."})
		node.lod_bias = original_bias
		camera.global_transform = original_transform
		camera.fov = original_fov
	get_viewport().mesh_lod_threshold = original_threshold
	_report["lod_sweep_restored_counters"] = await _counter_window()
	return results


func _landmark_footprint(node: MultiMeshInstance3D) -> Dictionary:
	var camera := _game.camera
	var bounds: AABB = node.global_transform * node.multimesh.get_aabb()
	var closest := Vector3.ZERO.max(bounds.position - camera.global_position).max(
			camera.global_position - bounds.end)
	var distance := closest.length()
	var scale_vector := node.global_basis.get_scale().abs()
	var model_scale := maxf(scale_vector.x, maxf(scale_vector.y, scale_vector.z))
	var projection := camera.get_camera_projection()
	var lod_multiplier := 2.0 / projection.x.x
	var threshold := get_viewport().mesh_lod_threshold / float(get_viewport().get_visible_rect().size.x)
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	var behind := 0
	for corner: int in 8:
		var world_point := bounds.get_endpoint(corner)
		if camera.is_position_behind(world_point):
			behind += 1
		else:
			var screen := camera.unproject_position(world_point)
			low = low.min(screen)
			high = high.max(screen)
	var mesh_data := _mesh_census(node.multimesh.mesh)
	var lods: Array = mesh_data.surfaces[0].baked_lods
	var predicted := 0
	var predicted_triangles := int(mesh_data.lod0_triangles)
	var first_transition_bias := 0.0
	for index: int in lods.size():
		var edge := float(lods[index].edge_length)
		if index == 0:
			first_transition_bias = threshold * distance * lod_multiplier / (edge * model_scale)
		if distance <= 0.0 or edge * model_scale * node.lod_bias / (distance * lod_multiplier) > threshold:
			break
		predicted = index + 1
		predicted_triangles = int(lods[index].index_count) / 3
	return {"world_aabb_position": _vector_components(bounds.position),
		"world_aabb_size": _vector_components(bounds.size),
		"camera_position": _vector_components(camera.global_position), "fov": camera.fov,
		"aabb_distance": distance, "node_lod_model_scale": model_scale,
		"multimesh_internal_scale": _vector_components(node.multimesh.get_instance_transform(0).basis.get_scale()),
		"projection_lod_multiplier": lod_multiplier, "normalized_lod_threshold": threshold,
		"first_lod_transition_bias": first_transition_bias,
		"projected_aabb_rect": [low.x, low.y, high.x - low.x, high.y - low.y],
		"corners_behind_camera": behind,
		"predicted_lod": predicted, "predicted_triangle_count": predicted_triangles,
		"prediction_scope": "Pinned GLES3 CPU selector formula; projected rectangle bounds are conservative, not rendered silhouette area. Engine node-scale excludes MultiMesh internal instance scale."}


func _fail_report(reason: String) -> void:
	if _finished:
		return
	_finished = true
	_report["success"] = false
	_report["error"] = reason
	push_error("runner_peak_replay: " + reason)
	_write_and_exit(2)


func _write_and_exit(code: int) -> void:
	_finished = true
	RunnerPlayer.autopilot = false
	if not _radar_swap_states.is_empty():
		_restore_radar_meshes(_radar_swap_states)
		_report["early_exit_radar_restored"] = _mesh_swap_invariants(_radar_swap_states)
		_radar_swap_states.clear()
	_radar_candidate_mesh = null
	var absolute := ProjectSettings.globalize_path(_out_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var output := FileAccess.open(absolute, FileAccess.WRITE)
	if output == null:
		push_error("runner_peak_replay cannot write " + absolute)
		code = 2
	else:
		output.store_string(JSON.stringify(_report, "\t"))
		output.close()
	print("[runner_peak_replay] wrote %s success=%s" % [absolute, _report.get("success", false)])
	if is_instance_valid(_game):
		_game.queue_free()
		_game = null
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(code)
