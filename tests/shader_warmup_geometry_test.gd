extends Node
## Geometric and recovery-ownership checks. No renderer, save writes or course
## builds: these assert actual probe bounds, not merely spawned node counts.

var _passes: int = 0
var _failures: int = 0


func _ready() -> void:
	_test_material_footprints()
	_test_real_mesh_displacement_and_cells()
	_test_hidden_scene_resources()
	_test_owned_inventory_and_exact_buffer_reuse()
	_test_waits_for_camera()
	await _test_recovery_suspension()
	_test_recovery_active_at_construction()
	_test_instanced_pair_properties()
	await _test_instanced_pair_guards()
	print("[shader_warmup_geometry] DONE: %d passed, %d failed" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(label: String, success: bool, detail: String = "") -> void:
	if success:
		_passes += 1
		print("[shader_warmup_geometry] PASS %s" % label)
	else:
		_failures += 1
		print("[shader_warmup_geometry] FAIL %s %s" % [label, detail])


func _test_material_footprints() -> void:
	var warmup := ShaderWarmup.new()
	var anchor := Node3D.new()
	warmup._anchor = anchor
	var cases: Array[Material] = [StandardMaterial3D.new(), ShaderMaterial.new()]
	cases.append_array(ShaderWarmup.probe_materials())
	for index: int in cases.size():
		var material := cases[index]
		warmup._spawn_material(material)
		var probe := anchor.get_child(index) as MeshInstance3D
		var standard := material as BaseMaterial3D
		var ignores_scale := standard != null \
				and standard.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED \
				and not standard.billboard_keep_scale
		# Model scale is explicitly discarded by the non-keep-scale billboard
		# shader. Measuring vertices alone for this case catches a large or
		# microscopic probe that an apparently correct instance scale disguises.
		var span := probe.mesh.get_aabb().size.x \
				* (1.0 if ignores_scale else probe.scale.x)
		_check("material_%d_real_span" % index,
				is_equal_approx(span, ShaderWarmup.PROBE_WORLD_SIZE), "span=%.8f" % span)
		var required := Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TANGENT \
				| Mesh.ARRAY_FORMAT_TEX_UV | Mesh.ARRAY_FORMAT_COLOR
		_check("material_%d_full_attributes" % index,
				(probe.mesh.surface_get_format(0) & required) == required)
		var vertices: PackedVector3Array = probe.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var geometric_normal := (vertices[1] - vertices[0]).cross(vertices[2] - vertices[0])
		_check("material_%d_clockwise_toward_camera" % index,
				geometric_normal.z < 0.0,
				"cross_z=%.8f (clockwise front toward +Z requires negative)" % geometric_normal.z)
		if material is ShaderMaterial:
			var displaced_span := probe.custom_aabb.size.x * probe.scale.x
			_check("shader_displacement_fits_cell",
					displaced_span < ShaderWarmup.PROBE_GRID_SPACING,
					"span=%.8f spacing=%.8f" % [displaced_span, ShaderWarmup.PROBE_GRID_SPACING])
	warmup._anchor = null
	anchor.free()
	warmup.free()


func _test_real_mesh_displacement_and_cells() -> void:
	var warmup := ShaderWarmup.new()
	var anchor := Node3D.new()
	warmup._anchor = anchor
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# An off-origin authored pivot must remain centered inside its assigned cell.
	for point: Vector3 in [Vector3(10.0, 4.0, -8.0), Vector3(12.0, 4.0, -8.0),
			Vector3(10.0, 5.0, -8.0)]:
		st.add_vertex(point)
	var mesh := st.commit()
	var material := StandardMaterial3D.new()
	var centres: Array[Vector3] = []
	var separated := true
	var centred := true
	var bounded := true
	for index: int in ShaderWarmup.MAX_INSTANCES:
		warmup._spawn_external(mesh, material)
		var probe := anchor.get_child(index) as MeshInstance3D
		var centre := probe.position + mesh.get_aabb().get_center() * probe.scale
		centred = centred and centre.is_equal_approx(ShaderWarmup._probe_cell(index))
		for previous: Vector3 in centres:
			separated = separated and centre.distance_to(previous) \
					>= ShaderWarmup.PROBE_GRID_SPACING * 0.999
		centres.append(centre)
		var safe_extent := (mesh.get_aabb().size.length() \
				+ 2.0 * ShaderWarmup.MAX_VERTEX_DISPLACEMENT) * probe.scale.x
		bounded = bounded and safe_extent <= ShaderWarmup.PROBE_WORLD_SIZE * 1.001
	_check("all_retained_probes_have_separate_cells", separated)
	_check("off_origin_authored_meshes_are_centered", centred)
	_check("actual_mesh_displacement_fit_preserved", bounded)
	warmup._anchor = null
	anchor.free()
	warmup.free()


func _test_hidden_scene_resources() -> void:
	# Fixture intentionally stays outside the tree. is_visible_in_tree() would
	# reject its visible branch too, hiding a production-only regression.
	var fixture := Node3D.new()
	var visible_mesh := MeshInstance3D.new()
	visible_mesh.mesh = BoxMesh.new()
	visible_mesh.material_override = StandardMaterial3D.new()
	fixture.add_child(visible_mesh)
	var hidden_branch := Node3D.new()
	hidden_branch.visible = false
	fixture.add_child(hidden_branch)
	var hidden_mesh := MeshInstance3D.new()
	hidden_mesh.mesh = SphereMesh.new()
	hidden_mesh.material_override = StandardMaterial3D.new()
	hidden_branch.add_child(hidden_mesh)
	var hidden_particles := GPUParticles3D.new()
	hidden_particles.process_material = ParticleProcessMaterial.new()
	hidden_branch.add_child(hidden_particles)
	var hidden_leaf := MeshInstance3D.new()
	hidden_leaf.mesh = CylinderMesh.new()
	hidden_leaf.visible = false
	fixture.add_child(hidden_leaf)
	var warmup := ShaderWarmup.new()
	warmup._world = fixture
	warmup._collect_queue(fixture)
	warmup._collect_particle_queue(fixture)
	_check("unparented_visible_mesh_is_collected", warmup._queue_keys.has(
			"mesh:%d" % visible_mesh.mesh.get_instance_id()))
	_check("hidden_branch_mesh_and_material_are_skipped",
			not warmup._queue_keys.has("mesh:%d" % hidden_mesh.mesh.get_instance_id()) \
			and not warmup._queue_keys.has("material:%d" % hidden_mesh.material_override.get_instance_id()))
	_check("hidden_leaf_is_skipped", not warmup._queue_keys.has(
			"mesh:%d" % hidden_leaf.mesh.get_instance_id()))
	_check("hidden_particle_process_is_skipped", not warmup._queue_keys.has(
			"particle:%d" % hidden_particles.process_material.get_instance_id()))
	ShaderWarmup.register_external_probe(hidden_mesh.mesh, hidden_mesh.material_override)
	warmup._build_queue()
	_check("hidden_future_external_probe_is_preserved", warmup._queue_keys.has(
			"external:%d:%d" % [hidden_mesh.mesh.get_instance_id(),
				hidden_mesh.material_override.get_instance_id()]))
	warmup.free()
	fixture.free()


func _test_waits_for_camera() -> void:
	var viewport := SubViewport.new()
	add_child(viewport)
	var warmup := ShaderWarmup.new()
	viewport.add_child(warmup)
	warmup._enqueue_material(StandardMaterial3D.new())
	warmup._submit_next_item()
	# A Canvas frame finishing without a camera must not consume a queued 3D
	# resource. This is the exact signal which previously advanced falsely.
	warmup._on_frame_post_draw()
	warmup._process(0.0)
	_check("no_camera_keeps_queue_unsubmitted",
			warmup._queue_cursor == 0 and not warmup._awaiting_draw \
			and warmup._anchor.get_child_count() == 0)
	viewport.free()


func _test_recovery_suspension() -> void:
	var recovery_before: bool = SceneRouter._recovery_active
	var deadline_before: int = SceneRouter._loading_deadline_msec
	var back_armed_before: bool = SceneRouter._recovery_back_armed
	var recovery_connections_before := SceneRouter.loading_recovery_started.get_connections().size()
	SceneRouter._recovery_active = false
	var viewport := SubViewport.new()
	add_child(viewport)
	var mesh: Mesh = BoxMesh.new()
	var material: Material = StandardMaterial3D.new()
	var warmup := ShaderWarmup.new()
	warmup._inventory = {
		"external_probes": [{"mesh": mesh, "material": material}],
		"materials": [material],
		"meshes": [],
	}
	viewport.add_child(warmup)
	# No camera exists during _ready(), so nothing has been submitted. Bypass
	# placement for one deterministic in-flight probe, without claiming a draw.
	var submitted := warmup._submit_next_item(false)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.make_current()
	var placed := warmup._place_anchor()
	var anchor := warmup._anchor
	var probe: MeshInstance3D = null
	if submitted:
		probe = anchor.get_child(0) as MeshInstance3D
	var mesh_ref: WeakRef = weakref(mesh)
	var material_ref: WeakRef = weakref(material)
	var queue_before := warmup._queue.duplicate(true)
	var keys_before := warmup._queue_keys.duplicate(true)
	var cursor_before := warmup._queue_cursor
	var serial_before := warmup._render_serial
	var submit_frame_before := warmup._last_submit_frame
	var instances_before := warmup._instances
	_check("recovery_fixture_has_inflight_camera_owned_probe",
			submitted and placed and warmup._awaiting_draw \
			and anchor.get_parent() == camera and probe != null \
			and warmup._queue.size() > cursor_before)
	_check("recovery_fixture_listens_to_router_and_draw",
			warmup.is_processing() \
			and SceneRouter.loading_recovery_started.is_connected(warmup.suspend_for_recovery) \
			and RenderingServer.frame_post_draw.is_connected(warmup._on_frame_post_draw))
	SceneRouter._recovery_active = true
	SceneRouter.loading_recovery_started.emit()
	_check("recovery_signal_latches_and_stops_shader_callbacks",
			warmup._recovery_suspended and not warmup.is_processing() \
			and not RenderingServer.frame_post_draw.is_connected(warmup._on_frame_post_draw))
	_check("recovery_signal_preserves_shader_queue_and_pending_draw",
			warmup._queue == queue_before and warmup._queue_keys == keys_before \
			and warmup._queue_cursor == cursor_before and warmup._awaiting_draw \
			and warmup._render_serial == serial_before \
			and warmup._last_submit_frame == submit_frame_before \
			and warmup._instances == instances_before)
	warmup.suspend_for_recovery()
	var submitted_while_suspended := warmup._submit_next_item(false)
	warmup._process(0.0)
	warmup._on_frame_post_draw()
	_check("recovery_direct_calls_cannot_advance_inflight_shader_probe",
			not submitted_while_suspended and warmup._queue == queue_before \
			and warmup._queue_cursor == cursor_before and warmup._awaiting_draw \
			and warmup._render_serial == serial_before \
			and warmup._last_submit_frame == submit_frame_before \
			and warmup._instances == instances_before and not warmup.is_queued_for_deletion())
	_check("recovery_retains_shader_anchor_and_exact_resources",
			is_instance_valid(anchor) and warmup._anchor == anchor \
			and not anchor.is_queued_for_deletion() and anchor.get_parent() == camera \
			and anchor.get_child_count() == instances_before and is_instance_valid(probe) \
			and probe.mesh == mesh and probe.material_override == material \
			and mesh_ref.get_ref() == mesh and material_ref.get_ref() == material)
	# Retry clears router recovery before replacing its old world. The old
	# helper must remain frozen throughout that interval, not resume its queue.
	SceneRouter._reset_loading_recovery()
	warmup._process(0.0)
	warmup._on_frame_post_draw()
	_check("router_recovery_reset_does_not_revive_shader_helper",
			not SceneRouter.is_loading_recovery_active() and warmup._recovery_suspended \
			and not warmup.is_processing() and warmup._queue == queue_before \
			and warmup._queue_cursor == cursor_before and warmup._awaiting_draw \
			and warmup._render_serial == serial_before \
			and not RenderingServer.frame_post_draw.is_connected(warmup._on_frame_post_draw))
	# Also exercise guards without _awaiting_draw or a same-frame submission
	# masking them. Queue reconstruction is not permission to revive this node.
	warmup._build_queue()
	var rebuilt_queue := warmup._queue.duplicate(true)
	var submitted_after_reset := warmup._submit_next_item(false)
	warmup._process(0.0)
	warmup._on_frame_post_draw()
	_check("shader_queue_reset_cannot_bypass_recovery_latch",
			warmup._recovery_suspended and not submitted_after_reset \
			and warmup._queue == rebuilt_queue and warmup._queue_cursor == 0 \
			and not warmup._awaiting_draw and warmup._last_submit_frame == -1 \
			and warmup._render_serial == serial_before \
			and warmup._instances == instances_before and not warmup.is_processing() \
			and not warmup.is_queued_for_deletion() \
			and anchor.get_child_count() == instances_before)
	warmup.free()
	_check("shader_exit_disconnects_recovery_and_queues_camera_anchor_cleanup",
			SceneRouter.loading_recovery_started.get_connections().size() \
			== recovery_connections_before and anchor.is_queued_for_deletion())
	SceneRouter._recovery_active = recovery_before
	SceneRouter._loading_deadline_msec = deadline_before
	SceneRouter._recovery_back_armed = back_armed_before
	# These uniquely owned resources are otherwise held only by the deferred
	# anchor after helper exit; discard fixture snapshots before checking release.
	queue_before.clear()
	rebuilt_queue.clear()
	mesh = null
	material = null
	await get_tree().process_frame
	await get_tree().process_frame
	_check("shader_exit_frees_camera_owned_probe_and_unique_resources",
			not is_instance_valid(anchor) and not is_instance_valid(probe) \
			and camera.get_child_count() == 0 \
			and mesh_ref.get_ref() == null and material_ref.get_ref() == null)
	viewport.free()


func _test_recovery_active_at_construction() -> void:
	var recovery_before: bool = SceneRouter._recovery_active
	var recovery_connections_before := SceneRouter.loading_recovery_started.get_connections().size()
	SceneRouter._recovery_active = true
	var viewport := SubViewport.new()
	add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.make_current()
	var warmup := ShaderWarmup.new()
	warmup._inventory = {
		"external_probes": [],
		"materials": [StandardMaterial3D.new()],
		"meshes": [],
	}
	viewport.add_child(warmup)
	_check("active_recovery_construction_suspends_before_first_shader_submission",
			warmup._recovery_suspended and not warmup.is_processing() \
			and warmup._queue.size() == 1 and warmup._queue_cursor == 0 \
			and warmup._last_submit_frame == -1 and warmup._render_serial == 0 \
			and not warmup._awaiting_draw and warmup._instances == 0 \
			and warmup._anchor.get_child_count() == 0 \
			and not RenderingServer.frame_post_draw.is_connected(warmup._on_frame_post_draw))
	# Completion is likewise forbidden: an exhausted suspended queue retains
	# its anchor until ordinary world replacement, rather than self-freeing.
	warmup._queue_cursor = warmup._queue.size()
	warmup._process(0.0)
	warmup._on_frame_post_draw()
	_check("suspended_completed_shader_queue_waits_for_scene_exit",
			not warmup.is_queued_for_deletion() and warmup._render_serial == 0 \
			and warmup._queue_cursor == warmup._queue.size() \
			and is_instance_valid(warmup._anchor) \
			and not warmup._anchor.is_queued_for_deletion())
	warmup.free()
	_check("active_recovery_shader_exit_disconnects_router",
			SceneRouter.loading_recovery_started.get_connections().size() \
			== recovery_connections_before)
	viewport.free()
	SceneRouter._recovery_active = recovery_before


func _test_owned_inventory_and_exact_buffer_reuse() -> void:
	var world := Node3D.new()
	var shared_mesh := BoxMesh.new()
	var late_mesh := SphereMesh.new()
	var live_mesh := PlaneMesh.new()
	var late_only_mesh := CylinderMesh.new()
	var material_a := StandardMaterial3D.new()
	var material_b := StandardMaterial3D.new()
	var late_material := StandardMaterial3D.new()
	var shared := MeshInstance3D.new()
	shared.mesh = shared_mesh
	shared.material_override = material_a
	world.add_child(shared)
	var live := MeshInstance3D.new()
	live.mesh = live_mesh
	live.material_override = material_b
	world.add_child(live)
	var warmup := ShaderWarmup.new()
	warmup._world = world
	warmup._inventory = {
		"external_probes": [
			{"mesh": shared_mesh, "material": material_a},
			{"mesh": shared_mesh, "material": material_b},
			{"mesh": late_mesh, "material": late_material},
		],
		"materials": [late_material],
		"meshes": [shared_mesh, late_mesh, late_only_mesh],
	}
	warmup._build_queue()
	var summary := warmup.inventory_summary()
	_check("owned_inventory_scope_is_explicit", summary["scope"] == "owned")
	_check("owned_inventory_exact_queue_counts", int(summary["items"]) == 8 \
			and int(summary["by_type"]["external"]) == 3 \
			and int(summary["by_type"]["material"]) == 3 \
			and int(summary["by_type"]["mesh"]) == 2, str(summary))
	_check("all_distinct_exact_pairs_survive_shared_mesh_reuse",
			warmup._queue_keys.has("external:%d:%d" % [shared_mesh.get_instance_id(),
					material_a.get_instance_id()]) \
			and warmup._queue_keys.has("external:%d:%d" % [shared_mesh.get_instance_id(),
					material_b.get_instance_id()]) \
			and warmup._queue_keys.has("external:%d:%d" % [late_mesh.get_instance_id(),
					late_material.get_instance_id()]))
	_check("already_external_mesh_buffers_have_no_generic_upload_duplicate",
			not warmup._queue_keys.has("mesh:%d" % shared_mesh.get_instance_id()) \
			and not warmup._queue_keys.has("mesh:%d" % late_mesh.get_instance_id()) \
			and int(summary["duplicate_mesh_uploads_omitted"]) == 2)
	_check("unprobed_live_and_late_mesh_buffers_are_kept",
			warmup._queue_keys.has("mesh:%d" % live_mesh.get_instance_id()) \
			and warmup._queue_keys.has("mesh:%d" % late_only_mesh.get_instance_id()))
	_check("generic_material_probes_remain_even_after_external_pair",
			warmup._queue_keys.has("material:%d" % material_a.get_instance_id()) \
			and warmup._queue_keys.has("material:%d" % material_b.get_instance_id()) \
			and warmup._queue_keys.has("material:%d" % late_material.get_instance_id()))
	# An unrelated global registry resource must not consume a scene-owned queue.
	var unrelated := VisualLibrary.rock_material(Color(0.11, 0.22, 0.33), 0.77)
	warmup._build_queue()
	_check("owned_inventory_excludes_unrelated_global_cache",
			not warmup._queue_keys.has("material:%d" % unrelated.get_instance_id()))
	# Incomplete inventories must not selectively omit valid siblings/global
	# cache entries; normal callers still retain the full legacy inventory.
	warmup._inventory["materials"] = ["invalid material"]
	warmup._build_queue()
	_check("malformed_owned_inventory_falls_back_atomically",
			warmup.inventory_summary()["scope"] == "global" \
			and warmup._queue_keys.has("material:%d" % unrelated.get_instance_id()))
	warmup._inventory = {}
	warmup._build_queue()
	_check("default_inventory_retains_legacy_global_resources",
			warmup.inventory_summary()["scope"] == "global" \
			and warmup._queue_keys.has("material:%d" % unrelated.get_instance_id()))
	warmup.free()
	world.free()


func _test_instanced_pair_properties() -> void:
	var mesh := VisualLibrary.contact_patch_mesh()
	var material := VisualLibrary.contact_shadow_material(0.22)
	var registered_before := ShaderWarmup.external_probe_count()
	var anchor := ShaderWarmup._create_instanced_pair_probe(mesh, material)
	var instance := anchor.get_node("InstancedPair") as MultiMeshInstance3D
	var light := anchor.get_node("InstancedPairOmni") as OmniLight3D
	# Dummy rendering does not round-trip MultiMesh transforms. Check the same
	# pure construction math used by the setter; actual GL QA must still prove
	# the submitted buffer draws and compiles the intended program.
	var transform := ShaderWarmup._instanced_pair_transform(mesh)
	var bounds: AABB = transform * mesh.get_aabb()
	_check("instanced_pair_has_one_exact_buffer_and_material",
			instance.multimesh.mesh == mesh and instance.material_override == material \
			and instance.multimesh.instance_count == 1 \
			and instance.multimesh.transform_format == MultiMesh.TRANSFORM_3D)
	_check("instanced_pair_does_not_add_vertex_color_or_custom_data",
			not instance.multimesh.use_colors and not instance.multimesh.use_custom_data)
	_check("instanced_pair_ground_plane_faces_camera",
			(transform.basis * Vector3.UP).normalized().is_equal_approx(Vector3.BACK))
	_check("instanced_pair_is_centered_and_raster_sized",
			bounds.get_center().is_equal_approx(Vector3.ZERO) \
			and is_equal_approx(bounds.size.x, ShaderWarmup.PROBE_WORLD_SIZE) \
			and is_equal_approx(bounds.size.y, ShaderWarmup.PROBE_WORLD_SIZE))
	_check("instanced_pair_uses_only_reserved_layer",
			instance.layers == ShaderWarmup.INSTANCED_PROBE_LAYER \
			and ShaderWarmup.INSTANCED_PROBE_LAYER == (1 << 19))
	_check("instanced_pair_light_cannot_reach_default_world_layer",
			light.light_cull_mask == instance.layers and (light.light_cull_mask & 1) == 0)
	_check("instanced_pair_light_covers_probe_without_shadows",
			light.position.distance_to(bounds.get_center()) + bounds.size.length() \
			< light.omni_range and light.light_energy > 0.0 and not light.shadow_enabled \
			and instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_check("instanced_pair_does_not_spend_external_queue_capacity",
			ShaderWarmup.external_probe_count() == registered_before)
	_check("instanced_pair_anchor_owns_all_temporary_nodes",
			anchor.get_child_count() == 2 and instance.get_parent() == anchor \
			and light.get_parent() == anchor and anchor.get_parent() == null)
	var multimesh_ref: WeakRef = weakref(instance.multimesh)
	anchor.free()
	_check("instanced_pair_free_releases_light_instance_and_multimesh",
			not is_instance_valid(instance) and not is_instance_valid(light) \
			and multimesh_ref.get_ref() == null)
	_check("instanced_pair_does_not_replace_or_mutate_shared_resources",
			VisualLibrary.contact_patch_mesh() == mesh \
			and VisualLibrary.contact_shadow_material(0.22) == material \
			and mesh.size == Vector2.ONE \
			and material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED \
			and material.cull_mode == BaseMaterial3D.CULL_DISABLED \
			and not material.vertex_color_use_as_albedo)
	_check("instanced_pair_constructor_rejects_missing_resources",
			ShaderWarmup._create_instanced_pair_probe(null, material) == null \
			and ShaderWarmup._create_instanced_pair_probe(mesh, null) == null)


func _test_instanced_pair_guards() -> void:
	var mesh := VisualLibrary.contact_patch_mesh()
	var material := VisualLibrary.contact_shadow_material(0.22)
	await ShaderWarmup.warm_instanced_pair(null, mesh, material)
	var detached := Node3D.new()
	await ShaderWarmup.warm_instanced_pair(detached, mesh, material)
	_check("instanced_pair_missing_world_or_tree_skips_without_allocating",
			detached.get_child_count() == 0)
	detached.free()
	var viewport := SubViewport.new()
	add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	await ShaderWarmup.warm_instanced_pair(world, mesh, material)
	_check("instanced_pair_camera_missing_skips_without_allocating",
			world.get_child_count() == 0 and viewport.get_camera_3d() == null)
	if GameConfig.is_headless():
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.make_current()
		var original_mask := camera.cull_mask
		await ShaderWarmup.warm_instanced_pair(world, mesh, material)
		_check("instanced_pair_headless_skips_even_with_camera",
				camera.get_child_count() == 0 and camera.cull_mask == original_mask)
	viewport.free()
