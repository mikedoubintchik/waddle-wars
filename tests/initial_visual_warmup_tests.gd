extends Node
## Real tree/visibility contract checks. Renderer completion is driven manually
## so these run headless; they do not claim GPU compilation or performance.

var _passes: int = 0
var _failures: int = 0


func _ready() -> void:
	_check("headless_skip", InitialVisualWarmup.warm(self) == null)
	await _test_originals_and_completion()
	_test_deferred_probe_inventory()
	_test_cancellation_restores_flags()
	_test_camera_required()
	await _test_recovery_suspension(false)
	await _test_recovery_suspension(true)
	_test_construction_during_recovery()
	print("[initial_visual_warmup] DONE: %d passed, %d failed" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool) -> void:
	if ok:
		_passes += 1
		print("[initial_visual_warmup] PASS %s" % label)
	else:
		_failures += 1
		print("[initial_visual_warmup] FAIL %s" % label)


func _fixture(with_camera: bool = true) -> Node3D:
	var world := Node3D.new()
	world.name = "WarmupFixture"
	add_child(world)
	if with_camera:
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.make_current()
	var parent := MeshInstance3D.new()
	parent.name = "ParentGeometry"
	parent.mesh = BoxMesh.new()
	world.add_child(parent)
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton"
	skeleton.add_bone("body")
	world.add_child(skeleton)
	parent.skeleton = NodePath("../Skeleton")
	parent.skin = Skin.new()
	parent.skin.add_bind(0, Transform3D.IDENTITY)
	parent.position = Vector3(3.0, 2.0, -9.0)
	parent.material_override = StandardMaterial3D.new()
	var child := MultiMeshInstance3D.new()
	child.name = "ChildMultiMesh"
	child.multimesh = MultiMesh.new()
	child.multimesh.mesh = BoxMesh.new()
	parent.add_child(child)
	var hidden := Node3D.new()
	hidden.name = "HiddenLod"
	hidden.visible = false
	world.add_child(hidden)
	var hidden_child := MeshInstance3D.new()
	hidden_child.name = "LocallyVisible"
	hidden_child.mesh = SphereMesh.new()
	hidden.add_child(hidden_child)
	var disabled := MeshInstance3D.new()
	disabled.name = "LocallyHidden"
	disabled.visible = false
	world.add_child(disabled)
	return world


func _begin_manual(world: Node3D) -> InitialVisualWarmup:
	# Direct construction intentionally bypasses warm()'s production headless
	# skip. Disable automatic processing and draw callbacks after synchronous
	# _ready capture, so tests control each distinct process/draw boundary.
	var pass_node := InitialVisualWarmup.new()
	pass_node._world = world
	world.add_child(pass_node)
	pass_node.set_process(false)
	pass_node._disconnect_draw_signal()
	return pass_node


func _test_originals_and_completion() -> void:
	InitialVisualWarmup.perf_trace_enabled = true
	InitialVisualWarmup.clear_perf_trace()
	var world := _fixture()
	var parent := world.get_node("ParentGeometry") as MeshInstance3D
	var child := parent.get_node("ChildMultiMesh") as MultiMeshInstance3D
	var original_multi := child.multimesh
	var original_skin := parent.skin
	var original_material := parent.material_override
	var original_transform := parent.transform
	var hidden := world.get_node("HiddenLod/LocallyVisible") as MeshInstance3D
	var disabled := world.get_node("LocallyHidden") as MeshInstance3D
	var pass_node := _begin_manual(world)
	_check("normal_warmup_priority_follows_router_watchdog", pass_node.process_priority == -100
		and SceneRouter.process_priority == -200 and SceneRouter.process_priority < pass_node.process_priority)
	_check("captures_hidden_and_visible_local_flags", pass_node._originals.size() == 4)
	_check("parent_capture_does_not_hide_child_from_queue", pass_node._visible_queue.size() == 2)
	_check("first_submission_reveals_parent_only", parent.visible and not child.visible)
	_check("hidden_lod_quarantined", not hidden.visible and not disabled.visible)
	_check("real_multimesh_resource_unchanged", child.multimesh == original_multi)
	_check("real_skin_skeleton_material_transform_unchanged", parent.skin == original_skin
		and parent.skeleton == NodePath("../Skeleton")
		and parent.material_override == original_material and parent.transform == original_transform)
	_check("no_second_submission_before_draw", not pass_node._submit_next_visual())
	pass_node._on_frame_post_draw()
	_check("same_process_frame_cannot_reveal_second", not pass_node._submit_next_visual())
	await _next_process_frame(pass_node)
	_check("next_frame_reveals_second_original", pass_node._submit_next_visual() and child.visible)
	pass_node._on_frame_post_draw()
	_check("not_complete_before_full_scene_settle", not pass_node.finished)
	await _next_process_frame(pass_node)
	_check("settle_frame_submitted", pass_node._submit_next_visual() and pass_node._settling)
	_check("exact_hidden_local_flags_restored", hidden.visible and not hidden.is_visible_in_tree()
		and not disabled.visible)
	_check("settle_requires_completed_draw", not pass_node.finished)
	var completion := [0]
	pass_node.completed.connect(func() -> void: completion[0] += 1)
	pass_node._on_frame_post_draw()
	_check("completion_after_settle_only", pass_node.finished and completion[0] == 1)
	pass_node._on_frame_post_draw()
	_check("completion_emitted_once", completion[0] == 1)
	var events := InitialVisualWarmup.drain_perf_trace_events()
	_check("trace_contains_two_visuals_settle_and_summary", events.size() == 4
		and events[0]["phase"] == "visual" and events[2]["phase"] == "settle"
		and events[3]["phase"] == "complete" and events[3]["revealed_total"] == 2)
	world.free()
	InitialVisualWarmup.perf_trace_enabled = false


func _next_process_frame(pass_node: InitialVisualWarmup) -> void:
	# The first process_frame signal after _ready can still carry engine frame
	# zero. Wait for an actual new frame number, not merely a signal emission.
	while Engine.get_process_frames() <= pass_node._last_submit_frame:
		await get_tree().process_frame


func _test_deferred_probe_inventory() -> void:
	var world := _fixture()
	var parent := world.get_node("ParentGeometry") as MeshInstance3D
	var child := parent.get_node("ChildMultiMesh") as MultiMeshInstance3D
	var hidden := world.get_node("HiddenLod/LocallyVisible") as MeshInstance3D
	var pass_node := InitialVisualWarmup.new()
	pass_node._world = world
	pass_node._reveal_started = false
	world.add_child(pass_node)
	pass_node.set_process(false)
	pass_node._disconnect_draw_signal()
	var original_ids := pass_node.originally_visible_ids()
	_check("deferred_capture_hides_every_original", not parent.visible and not child.visible
		and pass_node._cursor == 0 and not pass_node._awaiting_draw)
	_check("deferred_snapshot_excludes_hidden_lod", original_ids.size() == 2
		and original_ids.has(parent.get_instance_id()) and original_ids.has(child.get_instance_id())
		and not original_ids.has(hidden.get_instance_id()))
	var probe_pass := ShaderWarmup.new()
	probe_pass._world = world
	probe_pass._originally_visible_geometry = original_ids
	probe_pass._build_queue()
	_check("hidden_original_mesh_and_material_still_probed",
		probe_pass._queue_keys.has("mesh:%d" % parent.mesh.get_instance_id())
		and probe_pass._queue_keys.has("mesh:%d" % child.multimesh.mesh.get_instance_id())
		and probe_pass._queue_keys.has("material:%d" % parent.material_override.get_instance_id())
		and not probe_pass._queue_keys.has("mesh:%d" % hidden.mesh.get_instance_id()))
	probe_pass.free()
	pass_node.begin_reveal()
	_check("deferred_reveal_starts_only_when_requested", parent.visible and not child.visible
		and pass_node._cursor == 1 and pass_node._awaiting_draw)
	pass_node.free()
	_check("deferred_exit_restores_all_original_flags", child.visible and hidden.visible
		and not hidden.is_visible_in_tree())
	world.free()


func _test_cancellation_restores_flags() -> void:
	var world := _fixture()
	var pass_node := _begin_manual(world)
	var child := world.get_node("ParentGeometry/ChildMultiMesh") as MultiMeshInstance3D
	var hidden := world.get_node("HiddenLod/LocallyVisible") as MeshInstance3D
	var disabled := world.get_node("LocallyHidden") as MeshInstance3D
	_check("cancellation_fixture_has_unrevealed_nodes", not child.visible and not hidden.visible)
	pass_node.free()
	_check("early_exit_restores_unrevealed_originals", child.visible and hidden.visible)
	_check("early_exit_preserves_intentionally_hidden_nodes", not hidden.is_visible_in_tree()
		and not disabled.visible)
	world.free()


func _test_camera_required() -> void:
	var world := _fixture(false)
	var pass_node := _begin_manual(world)
	_check("no_camera_does_not_submit", pass_node._cursor == 0 and not pass_node._awaiting_draw)
	pass_node._on_frame_post_draw()
	_check("canvas_only_frame_does_not_advance", pass_node._cursor == 0 and not pass_node.finished)
	world.free()


func _test_recovery_suspension(during_settle: bool) -> void:
	# This headless fixture controls actual process/draw callbacks. The real
	# autoload signal exercises the helper's production connection, not a mock.
	var saved_recovery := SceneRouter._recovery_active
	var saved_deadline := SceneRouter._loading_deadline_msec
	var saved_back_armed := SceneRouter._recovery_back_armed
	SceneRouter._recovery_active = false
	InitialVisualWarmup.perf_trace_enabled = true
	InitialVisualWarmup.clear_perf_trace()
	var world := _fixture()
	var parent := world.get_node("ParentGeometry") as MeshInstance3D
	var child := parent.get_node("ChildMultiMesh") as MultiMeshInstance3D
	var hidden := world.get_node("HiddenLod/LocallyVisible") as MeshInstance3D
	var disabled := world.get_node("LocallyHidden") as MeshInstance3D
	var original_multi := child.multimesh
	var original_skin := parent.skin
	var original_material := parent.material_override
	var original_transform := parent.transform
	var pass_node := _begin_manual(world)
	var completion := [0]
	pass_node.completed.connect(func() -> void: completion[0] += 1)
	if during_settle:
		pass_node._on_frame_post_draw()
		await _next_process_frame(pass_node)
		pass_node._submit_next_visual()
		pass_node._on_frame_post_draw()
		await _next_process_frame(pass_node)
		pass_node._submit_next_visual()
	var label := "settle_recovery" if during_settle else "visual_recovery"
	var saved_cursor := pass_node._cursor
	var saved_revealed := pass_node._revealed_count
	var saved_settling := pass_node._settling
	var saved_restored := pass_node._restored
	var saved_visibility := [parent.visible, child.visible, hidden.visible, disabled.visible]
	var saved_queue := pass_node._visible_queue.duplicate()
	var saved_originals := pass_node._originals.duplicate()
	_check(label + "_has_pending_draw", pass_node._awaiting_draw and not pass_node.finished)
	_check(label + "_has_expected_staging_boundary", saved_settling == during_settle
		and saved_restored == during_settle and saved_cursor == (2 if during_settle else 1)
		and saved_revealed == (2 if during_settle else 1))
	_check(label + "_has_full_unchanged_workload", saved_originals.size() == 4 and saved_queue.size() == 2)
	pass_node.set_process(true)
	RenderingServer.frame_post_draw.connect(pass_node._on_frame_post_draw)
	SceneRouter._recovery_active = true
	SceneRouter.loading_recovery_started.emit()
	pass_node.suspend_for_recovery()
	_check(label + "_signal_latches_and_disconnects_draw", pass_node._recovery_suspended
		and not pass_node.is_processing()
		and not RenderingServer.frame_post_draw.is_connected(pass_node._on_frame_post_draw))
	pass_node._on_frame_post_draw()
	pass_node._process(0.0)
	_check(label + "_direct_callbacks_cannot_finish_pending_draw", pass_node._awaiting_draw
		and not pass_node.finished and completion[0] == 0)
	_check(label + "_retains_exact_stage_and_visibility", pass_node._cursor == saved_cursor
		and pass_node._revealed_count == saved_revealed and pass_node._settling == saved_settling
		and pass_node._restored == saved_restored
		and [parent.visible, child.visible, hidden.visible, disabled.visible] == saved_visibility
		and pass_node._visible_queue == saved_queue and pass_node._originals == saved_originals
		and not pass_node.is_queued_for_deletion())
	_check(label + "_retains_original_resources", child.multimesh == original_multi
		and parent.skin == original_skin and parent.material_override == original_material
		and parent.transform == original_transform and parent.skeleton == NodePath("../Skeleton"))
	# Clear the other submission guards deliberately: suspended state itself,
	# not awaiting-draw or same-frame coincidence, must refuse new work.
	pass_node._awaiting_draw = false
	pass_node._last_submit_frame = -1
	_check(label + "_direct_submission_refused", not pass_node._submit_next_visual())
	SceneRouter._reset_loading_recovery()
	_check(label + "_retry_reset_does_not_unlatch_old_helper", not SceneRouter.is_loading_recovery_active()
		and pass_node._recovery_suspended and not pass_node.is_processing())
	pass_node._process(0.0)
	pass_node._on_frame_post_draw()
	_check(label + "_retry_cannot_submit_or_complete_old_queue", not pass_node._submit_next_visual()
		and pass_node._cursor == saved_cursor and pass_node._revealed_count == saved_revealed
		and pass_node._settling == saved_settling and pass_node._restored == saved_restored
		and [parent.visible, child.visible, hidden.visible, disabled.visible] == saved_visibility
		and not pass_node.finished and completion[0] == 0)
	var events := InitialVisualWarmup.drain_perf_trace_events()
	var suspended_events := 0
	var completed_events := 0
	for event: Dictionary in events:
		if event["phase"] == "recovery_suspended":
			suspended_events += 1
		if event["phase"] == "complete" or event["phase"] == "settle":
			completed_events += 1
	_check(label + "_suspension_once_without_settle_completion", suspended_events == 1 and completed_events == 0)
	world.remove_child(pass_node)
	_check(label + "_scene_exit_restores_local_hidden_flags", parent.visible and child.visible
		and hidden.visible and not hidden.is_visible_in_tree() and not disabled.visible)
	_check(label + "_scene_exit_releases_references_and_connections", pass_node._originals.is_empty()
		and pass_node._visible_queue.is_empty() and pass_node._world == null
		and not SceneRouter.loading_recovery_started.is_connected(pass_node.suspend_for_recovery)
		and not RenderingServer.frame_post_draw.is_connected(pass_node._on_frame_post_draw)
		and not pass_node.finished and completion[0] == 0)
	pass_node.free()
	world.free()
	InitialVisualWarmup.clear_perf_trace()
	InitialVisualWarmup.perf_trace_enabled = false
	SceneRouter._recovery_active = saved_recovery
	SceneRouter._loading_deadline_msec = saved_deadline
	SceneRouter._recovery_back_armed = saved_back_armed


func _test_construction_during_recovery() -> void:
	var saved_recovery := SceneRouter._recovery_active
	SceneRouter._recovery_active = true
	var world := _fixture()
	var pass_node := _begin_manual(world)
	_check("active_recovery_construction_captures_without_submission", pass_node._recovery_suspended
		and pass_node._cursor == 0 and pass_node._revealed_count == 0
		and pass_node._originals.size() == 4 and pass_node._visible_queue.size() == 2
		and not pass_node._awaiting_draw and not pass_node.finished)
	SceneRouter._recovery_active = false
	pass_node._last_submit_frame = -1
	pass_node._process(0.0)
	pass_node._on_frame_post_draw()
	_check("active_recovery_helper_stays_latched_after_reset", pass_node._recovery_suspended
		and not pass_node._submit_next_visual() and pass_node._cursor == 0
		and not pass_node._settling and not pass_node.finished)
	world.free()
	SceneRouter._recovery_active = saved_recovery
