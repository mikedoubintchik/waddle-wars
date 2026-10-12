extends Node
## Headless queue/resource coverage, not a claim that a GPU rasterized every
## surface or that warmup caused/fixed a measured hitch. Uses real DAY imports.

var _passes: int = 0
var _failures: int = 0
const RELEASE_DAY_ASSETS := [
	"runner_day_deck_kerb_b_v1", "runner_day_deck_kerb_c_v1", "runner_day_deck_kerb_v1",
	"runner_day_iceberg_cluster_v1", "runner_day_research_lab_v1", "runner_day_signal_pylon_v1",
]
const RELEASE_RUNNER_PROBES := 23 # Six approved DAY pairs plus17 non-DAY/fallback pairs.


class NoWarmupTrack:
	extends RunnerTrack

	func _register_shader_warmup_probes() -> void:
		pass


func _ready() -> void:
	var saved_probes := ShaderWarmup._external_probes.duplicate()
	var saved_keys := ShaderWarmup._external_probe_keys.duplicate()
	var saved_scoped_probes := ShaderWarmup._scoped_external_probes.duplicate(true)
	var saved_scoped_keys := ShaderWarmup._scoped_external_probe_keys.duplicate(true)
	var saved_overflows := ShaderWarmup._external_probe_overflows.duplicate(true)
	ShaderWarmup._external_probes.clear()
	ShaderWarmup._external_probe_keys.clear()
	ShaderWarmup._scoped_external_probes.clear()
	ShaderWarmup._scoped_external_probe_keys.clear()
	ShaderWarmup._external_probe_overflows.clear()
	var saved_detail := VisualLibrary._detail_level_cache
	VisualLibrary._detail_level_cache = 1.0
	_test_actual_dusk_resources()
	_test_surface_probe_contract()
	ShaderWarmup._external_probes.assign(saved_probes)
	ShaderWarmup._external_probe_keys = saved_keys
	ShaderWarmup._scoped_external_probes = saved_scoped_probes
	ShaderWarmup._scoped_external_probe_keys = saved_scoped_keys
	ShaderWarmup._external_probe_overflows = saved_overflows
	VisualLibrary._detail_level_cache = saved_detail
	print("[runner_dusk_warmup] DONE: %d passed, %d failed" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(label: String, success: bool, detail: String = "") -> void:
	if success:
		_passes += 1
		print("[runner_dusk_warmup] PASS %s" % label)
	else:
		_failures += 1
		print("[runner_dusk_warmup] FAIL %s %s" % [label, detail])


func _test_actual_dusk_resources() -> void:
	var catalog := ArtCatalog.new()
	_check("central_manifest", catalog.reload_manifest() == OK)
	_check("real_day_release_without_preview", not catalog.preview_overlay_active())
	var art_set := load(RunnerGame.RUNNER_ART_SET_PATH) as RunnerArtSet
	var baseline := NoWarmupTrack.new()
	baseline.configure_art(art_set, catalog)
	baseline.setup(20260907, 1.0, 1)
	var status := baseline.authored_day_kit_status()
	_check("exact_six_release_day_meshes_loaded", status.asset_ids == PackedStringArray(RELEASE_DAY_ASSETS)
			and status.loaded == 6 and status.surface_material and not status.active)
	var track := RunnerTrack.new()
	track.configure_art(art_set, catalog)
	track.setup(20260907, 1.0, 1)
	_check("registration_does_not_change_opening_nodes_or_gameplay",
			_tree_signature(track) == _tree_signature(baseline))
	_check("registration_does_not_change_generator_state",
			_stream_state(track) == _stream_state(baseline))
	var seam := RunnerTrack._seam_mesh()
	var verge := RunnerTrack._verge_mesh()
	var opening := ShaderWarmup.new()
	opening._collect_queue(track)
	_check("authored_opening_has_no_procedural_seam_or_verge",
			not opening._queue_keys.has("mesh:%d" % seam.get_instance_id())
			and not opening._queue_keys.has("mesh:%d" % verge.get_instance_id()))
	_check("private_buffers_not_in_visual_library_cache",
			seam not in VisualLibrary.cached_meshes() and verge not in VisualLibrary.cached_meshes())
	opening.free()

	# Inspect a real DUSK deck without streaming, physics or a render window.
	var dusk := RunnerTrack.RunnerChunk.new()
	dusk.index = ceili(RunnerConfig.BIOME_LENGTH / RunnerConfig.CHUNK_LENGTH)
	dusk.biome = RunnerTrack.Biome.DUSK
	track._build_deck(dusk, RunnerTrack.Pattern.OPEN)
	var actual_seams := dusk.get_node("Seams") as MeshInstance3D
	var actual_verge := dusk.get_node("Verge") as MeshInstance3D
	_check("exact_dusk_seam_registered", ShaderWarmup.has_external_probe(
			actual_seams.mesh, actual_seams.material_override, [], RunnerTrack.SHADER_WARMUP_SCOPE))
	var verge_probe: Dictionary = {}
	for probe: Dictionary in ShaderWarmup._scoped_external_probes[RunnerTrack.SHADER_WARMUP_SCOPE]:
		if probe.get("mesh") == actual_verge.mesh:
			verge_probe = probe
	_check("exact_dusk_verge_registered", not verge_probe.is_empty())
	var actual_materials: Array[Material] = []
	for surface: int in actual_verge.mesh.get_surface_count():
		actual_materials.append(actual_verge.get_active_material(surface))
	for instance: MeshInstance3D in [actual_seams, actual_verge]:
		for surface: int in instance.mesh.get_surface_count():
			print("[runner_dusk_warmup] SURFACE %s/%d format=%d vertices=%d material=%s" % [
					instance.name, surface, instance.mesh.surface_get_format(surface),
					instance.mesh.surface_get_array_len(surface),
					ShaderWarmup._resource_label(instance.get_active_material(surface))])
	_check("four_surface_materials_preserved",
			verge_probe.get("surface_materials", []) == actual_materials)
	_check("surface_aware_lookup_finds_exact_verge", ShaderWarmup.has_external_probe(
			actual_verge.mesh, null, actual_materials, RunnerTrack.SHADER_WARMUP_SCOPE))
	_check("no_blanket_verge_material", not verge_probe.is_empty()
			and verge_probe.get("material") == null)
	_check("fresh_release_runner_external_budget_exactly_23",
			ShaderWarmup.external_probe_count(RunnerTrack.SHADER_WARMUP_SCOPE) == RELEASE_RUNNER_PROBES,
			"actual=%d cap=%d" % [ShaderWarmup.external_probe_count(RunnerTrack.SHADER_WARMUP_SCOPE),
					ShaderWarmup.MAX_EXTERNAL_PROBES])
	var all_day := true
	for asset_id: String in RELEASE_DAY_ASSETS:
		var mesh := track._authored_day_mesh(asset_id)
		var material := track._authored_day_draw_material(asset_id)
		if asset_id == RunnerTrack.DAY_ICEBERG_ASSET:
			mesh = RunnerTrack.ReferenceIce.sea_mesh(mesh)
			material = RunnerTrack.ReferenceIce.material()
		all_day = all_day and ShaderWarmup.has_external_probe(
				mesh, material, [], RunnerTrack.SHADER_WARMUP_SCOPE)
	_check("all_six_release_day_draw_pairs_retained", all_day)
	var tree_before := _tree_signature(track)
	var state_before := _stream_state(track)
	var count_before := ShaderWarmup.external_probe_count(RunnerTrack.SHADER_WARMUP_SCOPE)
	track._register_shader_warmup_probes()
	_check("retry_registration_idempotent",
			ShaderWarmup.external_probe_count(RunnerTrack.SHADER_WARMUP_SCOPE) == count_before)
	_check("retry_registration_no_nodes_or_state_changes",
			_tree_signature(track) == tree_before and _stream_state(track) == state_before)
	var warmup := ShaderWarmup.new()
	warmup._world = track
	warmup._external_scope = RunnerTrack.SHADER_WARMUP_SCOPE
	warmup._build_queue()
	var external_count := 0
	for item: Dictionary in warmup._queue:
		if item.type == "external":
			external_count += 1
	_check("all_external_probes_fit_before_queue_cap", external_count == count_before
			and warmup._queue.size() <= 128 and ShaderWarmup.MAX_INSTANCES == 128
			and ShaderWarmup.MAX_EXTERNAL_PROBES == 32)
	print(("[runner_dusk_warmup] COVERAGE external=%d/%d total_queue=%d/%d; "
			+ "track-only fixture; not an exhaustive full-runner pipeline audit")
			% [external_count, ShaderWarmup.MAX_EXTERNAL_PROBES,
				warmup._queue.size(), ShaderWarmup.MAX_INSTANCES])
	# Exercise the normal queue dispatcher: material_override must not erase
	# four independent material surfaces when the actual probe is instantiated.
	if not verge_probe.is_empty():
		var anchor := Node3D.new()
		warmup._anchor = anchor
		var row := verge_probe.duplicate()
		row["type"] = "external"
		warmup._spawn_queue_item(row)
		_check("one_exact_verge_instance", anchor.get_child_count() == 1)
		if anchor.get_child_count() == 1:
			var submitted := anchor.get_child(0) as MeshInstance3D
			var exact := submitted.mesh == actual_verge.mesh and submitted.material_override == null
			for surface: int in 4:
				exact = exact and submitted.get_active_material(surface) == actual_materials[surface]
			_check("spawn_retains_real_mesh_and_all_four_overrides", exact)
		warmup._anchor = null
		anchor.free()
	warmup.free()
	# Populate a prior mode's entire legacy budget. Runner owns an independent
	# registry and must preserve every prior pair without clearing either scope.
	ShaderWarmup._external_probes.clear()
	ShaderWarmup._external_probe_keys.clear()
	var prior_mesh := BoxMesh.new()
	var prior_material := StandardMaterial3D.new()
	ShaderWarmup.register_external_probe(prior_mesh, prior_material)
	for index: int in ShaderWarmup.MAX_EXTERNAL_PROBES - 1:
		ShaderWarmup.register_external_probe(BoxMesh.new(), prior_material)
	var legacy_keys := ShaderWarmup._external_probe_keys.duplicate()
	track._register_shader_warmup_probes()
	_check("full_prior_registry_keeps_all_pairs_and_cap",
			ShaderWarmup.external_probe_count() == 32
			and ShaderWarmup.has_external_probe(prior_mesh, prior_material)
			and ShaderWarmup._external_probe_keys == legacy_keys)
	_check("full_prior_registry_cannot_starve_dusk_or_late_day",
			ShaderWarmup.has_external_probe(actual_seams.mesh, actual_seams.material_override, [],
					RunnerTrack.SHADER_WARMUP_SCOPE)
			and ShaderWarmup.has_external_probe(actual_verge.mesh, null, actual_materials,
					RunnerTrack.SHADER_WARMUP_SCOPE)
			and ShaderWarmup.has_external_probe(track._authored_day_mesh(RunnerTrack.DAY_DECK_C_ASSET),
					track._authored_day_draw_material(RunnerTrack.DAY_DECK_C_ASSET), [], RunnerTrack.SHADER_WARMUP_SCOPE))
	warmup = ShaderWarmup.new()
	warmup._world = track
	warmup._external_scope = RunnerTrack.SHADER_WARMUP_SCOPE
	warmup._build_queue()
	_check("runner_after_prior_mode_has_all_23_release_late_pairs",
			int(warmup.inventory_summary()["by_type"]["external"]) == RELEASE_RUNNER_PROBES
			and bool(warmup.inventory_summary()["external_registry"]["registry_complete"]))
	track._register_shader_warmup_probes()
	var before_retry := _queue_keys(warmup)
	warmup._build_queue()
	_check("runner_retry_preserves_complete_ordered_inventory", _queue_keys(warmup) == before_retry
			and ShaderWarmup.external_scope_status(RunnerTrack.SHADER_WARMUP_SCOPE)["dropped"] == 0)
	warmup._external_scope = &""
	warmup._build_queue()
	var other_mode_keys := _queue_keys(warmup)
	var retained_default := true
	for key: String in legacy_keys:
		retained_default = retained_default and "external:%s" % key in other_mode_keys
	_check("return_to_other_mode_restores_untouched_default_registry", retained_default
			and int(warmup.inventory_summary()["by_type"]["external"]) == 32)
	print("[runner_dusk_warmup] COVERAGE prior-mode -> runner -> retry -> other-mode "
			+ "retains all23 runner pairs and all32 prior-mode pairs; queue/resource coverage, not GPU compilation evidence.")
	warmup.free()
	dusk.free()
	track.free()
	baseline.free()


func _queue_keys(warmup: ShaderWarmup) -> PackedStringArray:
	var keys := PackedStringArray()
	for item: Dictionary in warmup._queue:
		keys.append(String(item["key"]))
	return keys


func _test_surface_probe_contract() -> void:
	ShaderWarmup._external_probes.clear()
	ShaderWarmup._external_probe_keys.clear()
	var mesh := RunnerTrack._verge_mesh()
	var materials: Array[Material] = [StandardMaterial3D.new(), StandardMaterial3D.new(),
			StandardMaterial3D.new(), StandardMaterial3D.new()]
	var originals: Array[Material] = []
	for surface: int in 4:
		originals.append(mesh.surface_get_material(surface))
	ShaderWarmup.register_external_probe(null, materials[0])
	ShaderWarmup.register_external_probe(mesh, null)
	ShaderWarmup.register_external_probe(mesh, materials[0], materials)
	ShaderWarmup.register_external_probe(mesh, null, [materials[0]])
	ShaderWarmup.register_external_probe(mesh, null, [materials[0], materials[1], null, materials[3]])
	_check("invalid_or_ambiguous_surface_lists_rejected", ShaderWarmup.external_probe_count() == 0)
	ShaderWarmup.register_external_probe(mesh, materials[0])
	_check("legacy_pair_key_unchanged", ShaderWarmup._external_probes[0].key
			== "%d:%d" % [mesh.get_instance_id(), materials[0].get_instance_id()])
	var supplied: Array[Material] = materials.duplicate()
	ShaderWarmup.register_external_probe(mesh, null, supplied)
	supplied[0] = StandardMaterial3D.new()
	_check("registration_owns_surface_list_copy",
			ShaderWarmup._external_probes[1].surface_materials == materials
			and ShaderWarmup.has_external_probe(mesh, null, materials)
			and not ShaderWarmup.has_external_probe(mesh, null, supplied))
	ShaderWarmup.register_external_probe(mesh, null, materials)
	_check("identical_surface_probe_deduplicates", ShaderWarmup.external_probe_count() == 2)
	ShaderWarmup.register_external_probe(mesh, null, supplied)
	_check("changed_surface_identity_has_distinct_key", ShaderWarmup.external_probe_count() == 3)
	var reordered: Array[Material] = materials.duplicate()
	reordered.reverse()
	ShaderWarmup.register_external_probe(mesh, null, reordered)
	_check("surface_order_has_distinct_key", ShaderWarmup.external_probe_count() == 4)
	var other_mesh := mesh.duplicate() as Mesh
	ShaderWarmup.register_external_probe(other_mesh, null, materials)
	_check("mesh_identity_has_distinct_key", ShaderWarmup.external_probe_count() == 5)
	var warmup := ShaderWarmup.new()
	warmup._build_queue()
	var queued := false
	for item: Dictionary in warmup._queue:
		if item.type == "external" and item.get("surface_materials", []) == materials \
				and item.mesh == mesh:
			queued = item.material == null
	_check("queue_retains_surface_list_and_no_blanket", queued)
	var unchanged := true
	for surface: int in 4:
		unchanged = unchanged and mesh.surface_get_material(surface) == originals[surface]
	_check("probe_registration_never_mutates_cached_mesh_materials", unchanged)
	warmup.free()


func _tree_signature(root: Node) -> Array:
	var result: Array = [root.get_class()]
	if root is Node3D:
		result.append((root as Node3D).transform)
	if root is MeshInstance3D:
		var instance := root as MeshInstance3D
		result.append([instance.mesh, instance.material_override, instance.cast_shadow])
	if root is MultiMeshInstance3D:
		var multi := (root as MultiMeshInstance3D).multimesh
		result.append([multi.mesh, multi.instance_count, multi.use_colors])
	if root is RunnerTrack.RunnerChunk:
		var chunk := root as RunnerTrack.RunnerChunk
		result.append([chunk.index, chunk.pattern, chunk.biome, chunk.obstacles,
				chunk.fish_base, chunk.marks, chunk.mark_colors, chunk.rows])
	result.append(root.get_groups())
	for child: Node in root.get_children():
		result.append(_tree_signature(child))
	return result


func _stream_state(track: RunnerTrack) -> Array:
	return [track._seed, track._first_index, track._next_index, track._last_pattern,
			track._tunnel_left, track._lane_jump_z, track._lane_slide_z,
			track._air_from_z, track._air_to_z, track._next_powerup_z, track._powerup_cursor,
			track._chunk_rng(17, 11).state, track._chunk_rng(17, 60493).state]
