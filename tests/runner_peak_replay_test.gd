extends Node

const Replay = preload("res://tests/runner_peak_replay.gd")
var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	var good := {"current_biome": 0, "current_chunk": 7, "first_chunk": 5,
		"next_chunk": 14, "live_chunks": 9, "tunnel_chunks": 0,
		"distance_error": 0.2, "resolution": [1920, 1080], "effective_tier": "high"}
	_check("expected_context", not false in Replay._context_checks(good).values())
	_check("json_float_resolution_accepted", Replay._resolution_matches(JSON.parse_string("[1920,1080]")))
	_check("fractional_or_string_resolution_rejected", not Replay._resolution_matches([1920.5, 1080]) \
			and not Replay._resolution_matches(["1920", "1080"]))
	for key: String in good:
		var wrong: Dictionary = good.duplicate(true)
		wrong.erase(key)
		_check("missing_" + key + "_rejected", false in Replay._context_checks(wrong).values())
	var overshot: Dictionary = good.duplicate(true)
	overshot.distance_error = 1.01
	_check("overshoot_rejected", false in Replay._context_checks(overshot).values())
	_check("empty_counter_sample_unstable", not Replay._counters_stable([]))
	_check("identical_samples_stable", Replay._counters_stable([{"total_draws": 10}, {"total_draws": 10}]))
	_check("changed_samples_unstable", not Replay._counters_stable([{"total_draws": 10}, {"total_draws": 11}]))
	_check("counter_delta_signed", Replay._counter_difference({"total_draws": 8}, {"total_draws": 10}).total_draws == -2)
	_candidate_contracts()
	_swap_contracts()
	_check("far_lod_enter_boundary", Replay._radar_far_lod_state(false, 80.0) and not Replay._radar_far_lod_state(false, 80.01))
	_check("far_lod_exit_boundary", Replay._radar_far_lod_state(true, 95.99) and not Replay._radar_far_lod_state(true, 96.0))
	_check("far_lod_hysteresis", Replay._radar_far_lod_state(true, 88.0) and not Replay._radar_far_lod_state(false, 88.0))
	_check("far_lod_invalid_projection_rejected", not Replay._radar_far_lod_state(true, INF) \
		and not Replay._radar_far_lod_state(true, NAN) and not Replay._radar_far_lod_state(true, 0.0))
	_check("motion_path_endpoints", Replay._radar_motion_target_height(0) == 60.0 \
		and Replay._radar_motion_target_height(89) == 60.0 and Replay._radar_motion_target_height(44) == 120.0 \
		and Replay._radar_motion_target_height(45) == 120.0)
	_check("camera_delta_diagnostic_exact", Replay._transform_component_delta(Transform3D.IDENTITY, Transform3D.IDENTITY) == 0.0 \
		and Replay._transform_component_delta(Transform3D.IDENTITY, Transform3D(Basis.IDENTITY, Vector3(0.25, 0, 0))) == 0.25)
	_check("original_approach_timeout_unchanged", not Replay._diagnostic_timeout_reason(90_001, 0, false, true).is_empty())
	_check("original_nonextended_timeout_unchanged", not Replay._diagnostic_timeout_reason(90_001, 1, true, false).is_empty())
	_check("extended_capture_has_separate_bounded_budget", Replay._diagnostic_timeout_reason(180_000, 119_999, true, true).is_empty())
	_check("extended_capture_timeout_enforced", not Replay._diagnostic_timeout_reason(180_001, 120_001, true, true).is_empty())
	print("[runner_peak_replay] DONE: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed else 0)


func _candidate_contracts() -> void:
	var digest := "a".repeat(64)
	var live_digest := "b".repeat(64)
	var binding := {"qa_only": true, "production_ready": false, "runtime_changed": false,
		"visual_quality_approved": false, "independent_rebuild_byte_identical": true,
		"candidate_sha256": digest, "input_sha256": {Replay.RADAR_LIVE_GLB.trim_prefix("res://"): live_digest}}
	var authoring := {"live_glb_sha256": live_digest, "global_bounds_exact": true,
		"material_contract": {"surface_count": 1},
		"qa_import_contract": {"meshes/generate_lods": false, "require_actual_imported_lod_count": 0}}
	_check("candidate_valid_source_binding", not false in Replay._candidate_binding_checks(binding, authoring, digest, true, live_digest).values())
	_check("candidate_missing_rejected", false in Replay._candidate_binding_checks(binding, authoring, digest, false, live_digest).values())
	_check("candidate_wrong_hash_rejected", false in Replay._candidate_binding_checks(binding, authoring, live_digest, true, live_digest).values())
	_check("candidate_missing_hash_rejected", false in Replay._candidate_binding_checks(binding, authoring, "", true, live_digest).values())
	_check("candidate_stale_live_source_rejected", false in Replay._candidate_binding_checks(binding, authoring, digest, true, digest).values())
	for key: String in binding:
		var missing := binding.duplicate(true)
		missing.erase(key)
		_check("candidate_missing_%s_rejected" % key, false in Replay._candidate_binding_checks(missing, authoring, digest, true, live_digest).values())
	var automatic := authoring.duplicate(true)
	automatic.qa_import_contract["meshes/generate_lods"] = true
	_check("candidate_automatic_lods_rejected", false in Replay._candidate_binding_checks(binding, automatic, digest, true, live_digest).values())


func _swap_contracts() -> void:
	var root := Node3D.new()
	add_child(root)
	var original := BoxMesh.new()
	var candidate := SphereMesh.new()
	var radar := MultiMeshInstance3D.new()
	radar.set_meta("authored_asset_id", RunnerTrack.DAY_RADAR_ASSET)
	radar.multimesh = MultiMesh.new()
	radar.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	radar.multimesh.mesh = original
	radar.multimesh.instance_count = 1
	radar.multimesh.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(3, 4, 5)))
	radar.material_override = StandardMaterial3D.new()
	radar.position = Vector3(8, 9, 10)
	root.add_child(radar)
	var other := MultiMeshInstance3D.new()
	other.set_meta("authored_asset_id", RunnerTrack.DAY_ICEBREAKER_ASSET)
	other.multimesh = MultiMesh.new()
	other.multimesh.mesh = original
	root.add_child(other)
	var states: Array[Dictionary] = []
	Replay._capture_multimesh_states(root, states)
	_check("candidate_null_swap_rejected", not Replay._swap_radar_mesh(states, null) and Replay._mesh_swap_invariants(states))
	_check("candidate_swap_only_radar", Replay._swap_radar_mesh(states, candidate) \
		and radar.multimesh.mesh == candidate and other.multimesh.mesh == original \
		and Replay._mesh_swap_invariants(states, candidate))
	Replay._restore_radar_meshes(states)
	_check("candidate_restore_exact", radar.multimesh.mesh == original and Replay._mesh_swap_invariants(states))
	states.clear()
	other.multimesh = radar.multimesh
	Replay._capture_multimesh_states(root, states)
	_check("candidate_cross_family_alias_rejected_before_write", not Replay._swap_radar_mesh(states, candidate) \
		and radar.multimesh.mesh == original and Replay._mesh_swap_invariants(states))
	states.clear()
	radar.set_meta("authored_asset_id", "not_radar")
	Replay._capture_multimesh_states(root, states)
	_check("candidate_no_radar_rejected", not Replay._swap_radar_mesh(states, candidate) and Replay._mesh_swap_invariants(states))
	states.clear()
	root.free()


func _check(label: String, okay: bool) -> void:
	if okay:
		_passed += 1
	else:
		_failed += 1
	print("[runner_peak_replay] %s %s" % ["PASS" if okay else "FAIL", label])
