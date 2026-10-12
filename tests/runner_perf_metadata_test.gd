extends Node
## Pure report-helper regression checks. No runner scene, window or save writes.
## The ordinary test harness still supplies an isolated user:// for autoloads.

const Probe = preload("res://tests/runner_perf_probe.gd")
const MeshReadback = preload("res://tests/runner_web_mesh_preflight.gd")

var _passes: int = 0
var _failures: int = 0


func _ready() -> void:
	_test_fingerprint()
	_test_census_scope_and_visibility()
	_test_multimesh_limits()
	_test_baked_lod_storage()
	_test_stream_trace()
	_test_msaa_metadata()
	_test_workload_validity()
	_test_mesh_readback_preflight()
	print("[runner_perf_metadata] DONE: %d passed, %d failed" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(label: String, success: bool) -> void:
	if success:
		_passes += 1
		print("[runner_perf_metadata] PASS %s" % label)
	else:
		_failures += 1
		print("[runner_perf_metadata] FAIL %s" % label)


func _test_msaa_metadata() -> void:
	var capped: Dictionary = Probe._msaa_metadata("4x", Viewport.MSAA_2X, Viewport.MSAA_2X)
	_check("msaa_requested_does_not_masquerade_as_actual", capped.requested == "4x"
		and capped.effective == "2x" and capped.actual == "2x" and capped.actual_samples == 2
		and not capped.viewport_matches_request and capped.viewport_matches_policy)
	var mismatch: Dictionary = Probe._msaa_metadata("4x", Viewport.MSAA_2X, Viewport.MSAA_4X)
	_check("msaa_viewport_override_is_explicit", not mismatch.viewport_matches_policy
		and mismatch.viewport_matches_request and mismatch.actual_samples == 4)
	var disabled: Dictionary = Probe._msaa_metadata("off", Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED)
	_check("msaa_off_still_has_one_raster_sample", disabled.actual == "off"
		and disabled.actual_samples == 1 and disabled.viewport_matches_policy)
	var invalid: Dictionary = Probe._msaa_metadata("4x", -1, 99)
	_check("msaa_unknown_is_not_zero_or_matching", invalid.actual == "unknown"
		and invalid.effective_samples == null and invalid.actual_samples == null
		and not invalid.viewport_matches_policy and not invalid.viewport_matches_request)


func _test_workload_validity() -> void:
	var untouched := Probe.WorkloadValidity.new()
	_check("unchecked_workload_cannot_pass", not untouched.report().valid
		and untouched.report().reason == "no_complete_measured_workload")
	var valid := Probe.WorkloadValidity.new()
	_record_valid_workload_sample(valid, 1)
	_check("normal_authored_runner_workload_valid", valid.report().valid
		and valid.report().sample_pose_frames_checked == 1
		and valid.report().sample_3d_frames_checked == 1
		and valid.report().visible_objects_min == 129
		and valid.report().visible_primitives_peak == 37547)
	for height: float in [0.0, 0.1, 10.0]:
		_check("legacy_and_broad_hero_height_bounds_%s" % str(height),
			Probe.WorkloadValidity.pose_failure(Transform3D(Basis.IDENTITY, Vector3(0, 7, -92)),
				Vector3(0, 0, -100), height, 68.0, 0.05, 900.0).is_empty())
	_check("broad_relative_camera_boundary_accepted", Probe.WorkloadValidity.pose_failure(
		Transform3D(Basis.IDENTITY, Vector3(64, 64, 256)), Vector3.ZERO,
		1.0, 68.0, 0.05, 900.0).is_empty())
	var runaway := Probe.WorkloadValidity.new()
	var corrupt_camera := Transform3D(Basis.IDENTITY,
		Vector3(0, 1.1044764599608313e37, 1.3037546837383896e37))
	runaway.record_pose(corrupt_camera, Vector3(0, 0, -202),
		1.0, 67.1, 0.05, 900.0, "warmup", 12)
	_record_valid_workload_sample(runaway, 13)
	var runaway_report: Dictionary = runaway.report()
	_check("T6_finite_but_huge_camera_invalid_even_after_recovery",
		not runaway_report.valid and runaway_report.invalid_pose_frames == 1
		and runaway_report.first_failure.reason == "camera_relative_out_of_bounds"
		and runaway_report.first_failure.phase == "warmup"
		and runaway_report.first_failure.camera_position[1] > 1e30)
	for index: int in 1000:
		runaway.record_pose(corrupt_camera, Vector3(0, 0, -202),
			1.0, 67.1, 0.05, 900.0, "sample", index + 14)
	_check("failure_details_stay_bounded_and_keep_first_snapshot", runaway.first_failure.process_frame == 12
		and runaway.failure_counts.size() == 1 and runaway.invalid_pose_frames == 1001)
	var empty_world := Probe.WorkloadValidity.new()
	empty_world.record_pose(Transform3D(Basis.IDENTITY, Vector3(0, 7, -92)),
		Vector3(0, 0, -100), 1.0, 68.0, 0.05, 900.0, "sample", 1)
	empty_world.record_visible_3d(0, 0, 1)
	_check("HUD_only_world_rejected_independent_of_FPS", not empty_world.report().valid
		and empty_world.report().reason == "missing_visible_3d_workload"
		and empty_world.report().first_failure.reason == "visible_3d_missing")
	empty_world.record_visible_3d(129, 0, 2)
	empty_world.record_visible_3d(0, 100, 3)
	empty_world.record_visible_3d(129, 100, 4)
	_check("either_missing_3D_counter_invalid_and_streak_recovery_exact",
		empty_world.missing_visible_3d_frames == 3 and empty_world.longest_missing_3d_streak == 3
		and empty_world._missing_3d_streak == 0)
	var unpaired := Probe.WorkloadValidity.new()
	unpaired.record_visible_3d(129, 37547, 1)
	_check("monitor_only_sample_cannot_claim_valid_pose", not unpaired.report().valid
		and unpaired.report().reason == "no_complete_measured_workload")
	var nonfinite := Probe.WorkloadValidity.new()
	nonfinite.record_pose(Transform3D(Basis.IDENTITY, Vector3(NAN, 7, -92)),
		Vector3(0, 0, -100), 1.0, 68.0, 0.05, 900.0, "sample", 1)
	nonfinite.record_visible_3d(129, 37547, 1)
	var decoded: Variant = JSON.parse_string(JSON.stringify(nonfinite.report()))
	_check("nonfinite_pose_rejected_and_first_snapshot_JSON_safe", not nonfinite.report().valid
		and nonfinite.first_failure.reason == "runner_position_nonfinite"
		and decoded is Dictionary and decoded.first_failure.camera_position[0] is String)
	_check("degenerate_camera_basis_rejected", Probe.WorkloadValidity.pose_failure(
		Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3(0, 7, -92)),
		Vector3(0, 0, -100), 1.0, 68.0, 0.05, 900.0) == "camera_basis_invalid")
	_check("invalid_hero_height_rejected", Probe.WorkloadValidity.pose_failure(
		Transform3D(Basis.IDENTITY, Vector3(0, 7, -92)), Vector3(0, 0, -100),
		1e37, 68.0, 0.05, 900.0) == "hero_height_invalid")
	_check("invalid_projection_rejected", Probe.WorkloadValidity.pose_failure(
		Transform3D(Basis.IDENTITY, Vector3(0, 7, -92)), Vector3(0, 0, -100),
		1.0, 180.0, 0.05, 900.0) == "camera_projection_invalid")
	var missing_pose := Probe.WorkloadValidity.new()
	missing_pose.record_missing_pose("sample", 1)
	missing_pose.record_visible_3d(129, 37547, 1)
	_check("missing_player_or_camera_rejected", not missing_pose.report().valid
		and missing_pose.first_failure.reason == "runner_pose_missing")
	_check("workload_guard_discloses_cached_counter_and_instrumentation_scope",
		"not GPU completion" in valid.report().scope
		and "instrumentation" in valid.report().scope and "camera repair" in valid.report().scope)


func _record_valid_workload_sample(guard, process_frame: int) -> void:
	guard.record_pose(Transform3D(Basis.IDENTITY, Vector3(0, 7, -92)),
		Vector3(0, 0, -100), 1.0, 68.0, 0.05, 900.0, "sample", process_frame)
	guard.record_visible_3d(129, 37547, process_frame)


func _test_mesh_readback_preflight() -> void:
	var actual: Dictionary = MeshReadback.run_checks()
	_check("headless_mesh_readback_and_blended_bounds_fixture_six_checks_not_WebGL_proof",
		bool(actual.passed) and int(actual.checks) == MeshReadback.REQUIRED_CHECKS
		and actual.failures.is_empty() and actual.simultaneously_alive_distinct_meshes == 2)
	var expected := PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6)])
	_check("mesh_vertices_match_exact_valid_type", MeshReadback._vertices_match(expected, expected))
	_check("mesh_vertices_reject_array_instead_of_packed_type",
		not MeshReadback._vertices_match([Vector3(1, 2, 3), Vector3(4, 5, 6)], expected))
	_check("mesh_vertices_reject_bad_length", not MeshReadback._vertices_match(
		PackedVector3Array([Vector3(1, 2, 3)]), expected))
	_check("mesh_vertices_reject_nonfinite", not MeshReadback._vertices_match(
		PackedVector3Array([Vector3(NAN, 2, 3), Vector3(4, 5, 6)]), expected))


func _test_fingerprint() -> void:
	var script_path := "res://tests/runner_perf_probe.gd"
	var scene_path := "res://tests/runner_perf_probe.tscn"
	var paths := PackedStringArray([script_path, scene_path])
	var first: Dictionary = Probe._fingerprint_paths(paths)
	var reordered: Dictionary = Probe._fingerprint_paths(
			PackedStringArray([scene_path, script_path, scene_path]))
	_check("fingerprint_sorted_deduplicated", first.sha256 == reordered.sha256 \
			and first.entries.size() == 2)
	_check("fingerprint_exact_file_digest", first.entries[0].sha256 \
			== FileAccess.get_sha256(first.entries[0].path) and first.complete)
	var fewer: Dictionary = Probe._fingerprint_paths(PackedStringArray([script_path]))
	_check("source_subset_changes_digest", fewer.source_assets_sha256 != first.source_assets_sha256)
	paths.append("res://project.godot")
	var with_project: Dictionary = Probe._fingerprint_paths(paths)
	_check("exact_hash_retains_project_config", with_project.sha256 != first.sha256 \
			and with_project.entries.size() == 3)
	_check("comparable_subset_excludes_project_identity", with_project.source_assets_sha256 \
			== first.source_assets_sha256)
	var missing: Dictionary = Probe._fingerprint_paths(
			PackedStringArray(["res://tests/never_exists_perf_metadata_fixture.gd"]))
	_check("missing_is_explicit_not_clean", not missing.complete \
			and missing.missing_or_unreadable.size() == 1 and missing.entries[0].sha256 == "")
	var collected := PackedStringArray()
	Probe._collect_fingerprint_paths("res://scripts/save", collected)
	_check("recursive_path_collection_mutates_shared_array", collected.size() > 0 \
			and not collected.has("res://scripts/save"))
	var controller := Probe.new()
	_check("census_default_is_opt_out", not controller._census_requested)
	controller.free()
	_check("monitor_caveat_is_version_pinned", "4.7.1-stable" in Probe.PRIMITIVE_MONITOR_NOTE \
			and "No guessed correction" in Probe.PRIMITIVE_MONITOR_NOTE)
	_check("remap_accepts_only_canonical_import_cache", Probe._remap_is_in_scope(
			"res://.godot/imported/fixture.glb-0123.scn"))
	_check("remap_rejects_outside_scope", not Probe._remap_is_in_scope("/tmp/fixture.scn") \
			and not Probe._remap_is_in_scope("user://fixture.scn") \
			and not Probe._remap_is_in_scope("res://assets/fixture.scn"))
	_check("remap_rejects_traversal_and_directory", not Probe._remap_is_in_scope(
			"res://.godot/imported/../../assets/fixture.scn") \
			and not Probe._remap_is_in_scope("res://.godot/imported/") \
			and not Probe._remap_is_in_scope(""))


func _test_census_scope_and_visibility() -> void:
	# Unparented fixture deliberately prevents accidental is_visible_in_tree()
	# claims. This census is local visibility intent, never GPU draw visibility.
	var root := Node3D.new()
	var box := BoxMesh.new()
	var visible_mesh := MeshInstance3D.new()
	visible_mesh.mesh = box
	visible_mesh.set_meta("authored_asset_id", "fixture.box")
	root.add_child(visible_mesh)
	var hidden := Node3D.new()
	hidden.visible = false
	root.add_child(hidden)
	var hidden_mesh := MeshInstance3D.new()
	hidden_mesh.mesh = box
	hidden_mesh.set_meta("authored_asset_id", "fixture.box")
	hidden.add_child(hidden_mesh)
	var disabled: Dictionary = Probe._final_census_report(root, false, 432.0, 60.0)
	_check("disabled_census_does_not_inventory_geometry", not disabled.captured \
			and disabled.families.is_empty() and disabled.meshes.is_empty())
	var report: Dictionary = Probe._final_census_report(root, true, 432.0, 60.0)
	_check("census_explicitly_final_not_peak", report.scope == "final_scene_after_timing_not_peak" \
			and report.distance == 432.0 and report.sample_time == 60.0)
	_check("census_explicitly_not_gpu_visibility", "not GPU visibility" in report.visibility_scope \
			and "selected-LOD" in report.visibility_scope)
	var family: Dictionary = report.families["fixture.box"]
	_check("hidden_branch_stays_resident_but_not_locally_visible", family.geometry_nodes == 2 \
			and family.subtree_visible_nodes == 1 and family.enabled_instances == 2 \
			and family.subtree_visible_enabled_instances == 1)
	_check("shared_mesh_counted_once", report.meshes.size() == 1 \
			and family.mesh_indices == [0])
	_check("box_lod0_is_twelve_triangles", report.meshes[0].lod0_triangles == 12 \
			and family.subtree_visible_lod0_instance_triangles == 12)
	_check("baked_lod_not_runtime_selection", "no claim about selected runtime LOD" \
			in report.meshes[0].lod_scope)
	root.free()


func _test_multimesh_limits() -> void:
	_check("multimesh_minus_one_means_all", Probe._enabled_multimesh_instances(4, -1) == 4)
	_check("multimesh_zero_means_none", Probe._enabled_multimesh_instances(4, 0) == 0)
	_check("multimesh_limit_clamped", Probe._enabled_multimesh_instances(4, 9) == 4 \
			and Probe._enabled_multimesh_instances(4, 2) == 2)
	var root := Node3D.new()
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = BoxMesh.new()
	multi.instance_count = 4
	multi.visible_instance_count = 2
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	instance.set_meta("authored_asset_id", "fixture.multibox")
	root.add_child(instance)
	var report: Dictionary = Probe._final_census_report(root, true, 0.0, 1.0)
	var family: Dictionary = report.families["fixture.multibox"]
	_check("multimesh_allocation_distinct_from_enabled", family.allocated_instances == 4 \
			and family.enabled_instances == 2 and family.subtree_visible_enabled_instances == 2)
	_check("multimesh_lod0_inventory_applies_enabled_count", \
			family.subtree_visible_lod0_instance_triangles == 24)
	root.visible = false
	report = Probe._final_census_report(root, true, 0.0, 1.0)
	family = report.families["fixture.multibox"]
	_check("hidden_multimesh_no_locally_visible_instances", family.enabled_instances == 2 \
			and family.subtree_visible_enabled_instances == 0 \
			and family.subtree_visible_lod0_instance_triangles == 0)
	root.free()


func _test_baked_lod_storage() -> void:
	var bytes := PackedByteArray()
	bytes.resize(12)
	var small: Array = Probe._baked_lod_census([0.5, bytes], 65_536)
	_check("lod_16_bit_indices_not_bytes", small[0].index_bytes == 2 \
			and small[0].index_count == 6 and small[0].edge_length == 0.5)
	var large: Array = Probe._baked_lod_census([0.5, bytes], 65_537)
	_check("lod_32_bit_indices_not_bytes", large[0].index_bytes == 4 \
			and large[0].index_count == 3)
	_check("lod_bad_pairs_fail_closed", Probe._baked_lod_census([0.5], 4)[0].has("error"))
	_check("lod_bad_storage_fail_closed", Probe._baked_lod_census([0.5, [0, 1, 2]], 4)[0].has("error"))
	_check("lod_bad_alignment_fail_closed", Probe._baked_lod_census(
			[0.5, PackedByteArray([0, 1, 2])], 4)[0].has("error"))
	_check("lod_unknown_vertex_count_fail_closed", Probe._baked_lod_census([0.5, bytes], 0)[0].has("error"))
	_check("lod_bad_edge_fail_closed", Probe._baked_lod_census(["not a number", bytes], 4)[0].has("error"))


func _test_stream_trace() -> void:
	var controller := Probe.new()
	var disabled: Dictionary = controller._stream_trace_report()
	_check("stream_trace_opt_in_default", not controller._stream_trace_requested
		and controller._stream_trace == null and not disabled.captured and disabled.events.is_empty())
	_check("stream_trace_cpu_not_gpu_claim", "no independent retirement" in disabled.cpu_scope
		and "no GPU synchronization" in disabled.counter_scope
		and "does not establish hitch cause" in disabled.correlation_scope)
	controller._build_fingerprint = {"entries": [
		{"path": "res://scripts/runner/runner_track.gd", "sha256": "track-before-run"},
		{"path": "res://tests/runner_perf_probe.gd", "sha256": "probe-before-run"},
		{"path": "res://assets/not_a_trace_source.glb", "sha256": "unrelated"}]}
	var binding: Dictionary = controller._stream_trace_report()
	_check("stream_trace_reuses_exact_prerun_source_binding", binding.source_scripts.size() == 2
		and binding.source_scripts[0].sha256 == "track-before-run")
	var previous: bool = RunnerTrack.perf_trace_enabled
	controller._stream_trace_previous = true
	controller._stream_trace_armed = true
	RunnerTrack.perf_trace_enabled = false
	controller._restore_stream_trace_flag()
	_check("stream_trace_restores_previous_true_exactly", RunnerTrack.perf_trace_enabled
		and not controller._stream_trace_armed)
	controller._stream_trace_previous = false
	controller._stream_trace_armed = true
	controller._restore_stream_trace_flag()
	_check("stream_trace_restores_previous_false_exactly", not RunnerTrack.perf_trace_enabled)
	RunnerTrack.perf_trace_enabled = previous
	controller.free()
	var frame: Dictionary = Probe._sample_frame_record(7, 103, 1_000_000, 1_098_133,
		22.249406, 396.264445, 0, 177, 123456)
	_check("slow_row_monotonic_interval_and_ids", frame.sample_frame_id == 7
		and frame.process_frame == 103 and frame.interval_start_usec == 1_000_000
		and frame.interval_end_usec == 1_098_133 and is_equal_approx(frame.frame_ms, 98.133))
	_check("slow_row_retains_primitives_not_draws_only", frame.total_primitives_monitor == 123456
		and frame.draws == 177 and frame.distance == 396.264445)
	var trace := Probe.StreamTraceWindow.new()
	var source := {"kind": "stream", "frame": 102, "cpu_us": 2345,
		"spawned_indices": PackedInt32Array([17]), "retired_indices": PackedInt32Array([8])}
	var ids: PackedInt32Array = trace.record_events([source], 103, 1_098_133, 7, "sample")
	var event: Dictionary = trace.events[0]
	_check("event_original_frame_distinct_from_observation", event.source_process_frame == 102
		and event.observed_process_frame == 103 and event.observed_usec == 1_098_133
		and event.observed_sample_frame_id == 7 and event.event_id == ids[0])
	_check("event_cpu_and_chunk_ids_preserved", event.cpu_us == 2345
		and event.spawned_indices == PackedInt32Array([17]) and event.retired_indices == PackedInt32Array([8]))
	source.spawned_indices[0] = 99
	_check("event_storage_does_not_mutate_or_alias_source", not source.has("event_id")
		and event.spawned_indices[0] == 17)
	trace.record_events([{"kind": "unknown"}], 104, 1_114_800, 8, "sample")
	_check("missing_source_frame_stays_unknown", trace.events[1].source_process_frame == -1)
	var many: Array[Dictionary] = []
	for index: int in Probe.STREAM_TRACE_EVENT_LIMIT + 5:
		many.append({"kind": "spawn", "frame": index, "chunk": index})
	var capped := Probe.StreamTraceWindow.new()
	var capped_ids: PackedInt32Array = capped.record_events(many, 999, 2_000_000, 60, "sample")
	_check("stream_events_bounded_with_explicit_overflow", capped.events.size() == Probe.STREAM_TRACE_EVENT_LIMIT
		and capped.events_seen == Probe.STREAM_TRACE_EVENT_LIMIT + 5 and capped.events_dropped == 5
		and capped_ids.size() == Probe.STREAM_TRACE_EVENT_LIMIT + 5
		and capped.events[0].event_id == 1 and capped.events[63].event_id == 64
		and capped.events[64].event_id == 70 and capped.events[-1].event_id == 261)
	_check("upstream_queue_loss_not_silently_claimed_zero", "exposes no overflow counter" in capped.report().upstream_overflow_scope)
	var window := Probe.StreamTraceWindow.new()
	for index: int in range(1, 20):
		window.record_frame(_trace_frame(index, 98.133 if index == 11 else 16.667))
	var capture: Dictionary = window.windows[0]
	_check("hitch_window_eight_before_trigger_eight_after", capture.frames.size() == 17
		and capture.frames_before_recorded == 8 and capture.frames_after_remaining == 0
		and capture.trigger_sample_frame_id == 11 and capture.frames[0].sample_frame_id == 3
		and capture.frames[-1].sample_frame_id == 19 and window.recent.size() == 8)
	var partial := Probe.StreamTraceWindow.new()
	partial.record_frame(_trace_frame(1, 98.133))
	partial.record_frame(_trace_frame(2, 16.667))
	_check("end_of_run_window_remains_explicitly_partial", partial.windows[0].frames_before_recorded == 0
		and partial.windows[0].frames_after_remaining == 7 and partial.windows[0].frames.size() == 2)
	var overlap := Probe.StreamTraceWindow.new()
	for index: int in range(1, 20):
		overlap.record_frame(_trace_frame(index, 70.0 if index in [10, 11] else 16.667))
	_check("overlapping_hitches_keep_independent_exact_windows", overlap.windows.size() == 2
		and overlap.windows[0].frames.size() == 17 and overlap.windows[1].frames.size() == 17
		and overlap.windows[0].frames[-1].sample_frame_id == 18
		and overlap.windows[1].frames[-1].sample_frame_id == 19)
	var storm := Probe.StreamTraceWindow.new()
	for index: int in range(1, 33):
		storm.record_frame(_trace_frame(index, 98.133))
	var bounded := storm.windows.size() == Probe.STREAM_TRACE_WINDOW_LIMIT and storm.windows_dropped == 24
	for row: Dictionary in storm.windows:
		bounded = bounded and row.frames.size() <= 17
	_check("hitch_storm_window_storage_bounded", bounded and storm.recent.size() == 8)
	var thirty := Probe.StreamTraceWindow.new()
	thirty.record_frame(_trace_frame(1, 30.0))
	thirty.record_frame(_trace_frame(2, 30.001))
	_check("over30_diagnostic_row_strict_boundary", thirty.frames_over_30_ms.size() == 1
		and thirty.frames_over_30_ms[0].sample_frame_id == 2 and thirty.windows.is_empty())
	for index: int in range(3, 3 + Probe.STREAM_TRACE_SLOW_ROW_LIMIT):
		thirty.record_frame(_trace_frame(index, 35.0))
	_check("over30_diagnostic_rows_bounded", thirty.frames_over_30_ms.size() == Probe.STREAM_TRACE_SLOW_ROW_LIMIT
		and thirty.over_30_ms_rows_dropped == 1)
	_test_late_stream_trace_retention()


func _record_trace_sample(trace: Probe.StreamTraceWindow, index: int, duration_ms: float,
		event_count: int = 1) -> void:
	var events: Array[Dictionary] = []
	for ordinal: int in event_count:
		events.append({"kind": "stream", "frame": index + 99, "ordinal": ordinal,
				"cpu_us": index, "chunk": floori(float(index) / 100.0)})
	trace.record_events(events, index + 100, index * 100000, index, "sample")
	trace.record_frame(_trace_frame(index, duration_ms))


func _test_late_stream_trace_retention() -> void:
	var late := Probe.StreamTraceWindow.new()
	for index: int in range(1, 530):
		_record_trace_sample(late, index, 134.0 if index == 520 else 16.667)
	var report := late.report()
	var capture: Dictionary = report.windows[0]
	_check("late_hitch_beyond_raw_cap_has_complete_adjacent_events",
		capture.frames.size() == 17 and capture.trigger_sample_frame_id == 520
		and capture.frames[0].sample_frame_id == 512 and capture.frames[-1].sample_frame_id == 528
		and capture.event_rows_retained_unique == 17 and capture.event_rows_missing == 0
		and capture.frames_missing_drain == 0)
	var exact := true
	for frame: Dictionary in capture.frames:
		var event: Dictionary = frame.observed_stream_event_rows[0]
		exact = (exact and event.event_id == frame.sample_frame_id
			and event.source_process_frame == frame.process_frame - 1
			and event.observed_process_frame == frame.process_frame
			and event.observed_sample_frame_id == frame.sample_frame_id)
	_check("late_neighborhood_preserves_exact_source_and_observed_adjacency", exact)
	for index: int in range(530, 830):
		_record_trace_sample(late, index, 16.667)
	report = late.report()
	var retained: Array = report.event_rows_retained_ids
	var expected: Array[int] = []
	for id: int in range(1, 65):
		expected.append(id)
	for id: int in range(512, 529):
		expected.append(id)
	for id: int in range(638, 830):
		expected.append(id)
	_check("pinned_window_retains_evicted_raw_events_exactly", retained == expected
		and report.events_seen == 829 and report.events_dropped == 573
		and report.event_rows_retained_unique == 273 and report.event_rows_unavailable == 556)
	_check("raw_eviction_distinct_from_total_evidence_loss",
		report.events_dropped > report.event_rows_unavailable
		and report.windows[0].event_rows_missing == 0)
	var burst := Probe.StreamTraceWindow.new()
	_record_trace_sample(burst, 1, 100.0, 261)
	for index: int in range(2, 400):
		_record_trace_sample(burst, index, 16.667, 0)
	var burst_report := burst.report()
	var first: Dictionary = burst_report.windows[0]
	_check("per_frame_event_rows_and_loss_counts_are_explicit", first.frames[0].observed_stream_event_rows.size() == 16
		and first.frames[0].observed_stream_event_rows_dropped == 245
		and first.event_rows_inline_missing == 245 and first.event_rows_missing == 5
		and first.event_rows_missing_ids == [65, 66, 67, 68, 69]
		and burst_report.event_rows_unavailable == 5)
	var missing := Probe.StreamTraceWindow.new()
	missing.record_frame(_trace_frame(1, 100.0))
	_check("missing_drain_not_misreported_as_no_stream_work",
		missing.report().windows[0].frames_missing_drain == 1)
	var storm := Probe.StreamTraceWindow.new()
	for index: int in range(1, 501):
		_record_trace_sample(storm, index, 51.0 if index <= 16 else (150.0 if index == 490 else 16.667), 20)
	var storm_report := storm.report()
	var found_late := false
	var bounded := storm.events.size() == Probe.STREAM_TRACE_EVENT_LIMIT
	for window: Dictionary in storm_report.windows:
		found_late = found_late or window.trigger_sample_frame_id == 490
		bounded = bounded and window.frames.size() <= 17
		for frame: Dictionary in window.frames:
			bounded = bounded and frame.observed_stream_event_rows.size() <= Probe.STREAM_TRACE_FRAME_EVENT_LIMIT
	_check("late_severe_hitch_replaces_weak_window_without_unbounded_growth", found_late and bounded
		and storm_report.windows_seen == 17 and storm_report.windows_dropped == 9
		and storm_report.windows_evicted == 1 and storm_report.windows.size() == 8)
	var union: Dictionary = {}
	for event: Dictionary in storm_report.events:
		union[int(event.event_id)] = true
	for window: Dictionary in storm_report.windows:
		for frame: Dictionary in window.frames:
			for event: Dictionary in frame.observed_stream_event_rows:
				union[int(event.event_id)] = true
	var union_ids: Array = union.keys()
	union_ids.sort()
	_check("overlapping_windows_unique_union_and_unavailable_counts_exact",
		storm_report.event_rows_retained_ids == union_ids
		and storm_report.event_rows_retained_unique == union.size()
		and storm_report.event_rows_unavailable == 10000 - union.size()
		and union.size() <= storm_report.event_object_upper_bound)
	var no_raw_pins := true
	for frame: Dictionary in storm.frames_over_30_ms:
		no_raw_pins = no_raw_pins and not frame.has("observed_stream_event_rows")
	_check("bounded_scalar_slow_rows_do_not_pin_extra_raw_event_objects", no_raw_pins)
	var detached := Probe.StreamTraceWindow.new()
	var caller_row := _trace_frame(1, 100.0)
	detached.record_events([{"frame": 100, "kind": "stream"}], 101, 100000, 1, "sample")
	detached.record_frame(caller_row)
	_check("caller_duration_dependent_slow_array_cannot_pin_raw_objects",
		not caller_row.has("observed_stream_event_rows")
		and detached.windows[0].frames[0].observed_stream_event_rows.size() == 1)
	var unexported := Probe.StreamTraceWindow.new()
	for index: int in range(1, 14):
		_record_trace_sample(unexported, index, 16.667, 16)
	_record_trace_sample(unexported, 14, 16.667, 300)
	var serialized := unexported.report()
	var serialized_ids: Array[int] = []
	for event: Dictionary in serialized.events:
		serialized_ids.append(int(event.event_id))
	_check("unexported_recent_rows_do_not_claim_available_evidence",
		serialized.windows.is_empty() and serialized.events_seen == 508
		and serialized.event_rows_retained_unique == 256 and serialized.event_rows_unavailable == 252
		and serialized.event_rows_retained_ids == serialized_ids)


func _trace_frame(index: int, duration_ms: float) -> Dictionary:
	return Probe._sample_frame_record(index, index + 100, index * 100000,
		index * 100000 + roundi(duration_ms * 1000.0), float(index) / 60.0,
		float(index), 0, 177, 123456)
