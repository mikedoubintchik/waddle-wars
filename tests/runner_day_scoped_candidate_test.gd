extends Node
## Scoped release-catalog contract. No debug fragment or fixture catalog.
var _scene_ids := PackedStringArray([
	"runner_day_deck_kerb_b_v1", "runner_day_deck_kerb_c_v1", "runner_day_deck_kerb_v1",
	"runner_day_iceberg_cluster_v1", "runner_day_research_lab_v1", "runner_day_signal_pylon_v1",
])
const SEED := 20260818
var _checks := 0
var _failures := 0

func _ready() -> void:
	var catalog := ArtCatalog.new()
	_check("central_catalog_loads", catalog.reload_manifest() == OK)
	_check("no_preview_overlay", not catalog.preview_overlay_active())
	var art := load("res://data/art/runner_art_set_foundation.tres") as RunnerArtSet
	_check("art_set_stays_partial", not art.production_ready and art.allow_procedural_fallback)
	_check("art_set_valid_against_release_catalog", art.validation_errors(catalog).is_empty())
	var expected := _scene_ids.duplicate()
	expected.append("runner_day_surface_material_v1")
	expected.sort()
	_check("release_preload_exactly_selected_seven_roles", art.collect_preload_ids("day") == expected)
	_check("no_unknown_release_preloads", catalog.begin_preload(expected) == OK)
	while not bool(catalog.poll_preload().get("complete", false)):
		await get_tree().process_frame
	_check("all_release_preloads_succeeded", int(catalog.preload_status().get("failed", -1)) == 0)
	for id: String in _scene_ids:
		var entry := catalog.asset_entry(id)
		_check(id + "_release_registered", bool(entry.get("production_ready", false)))
		var packed := catalog.loaded_resource(id) as PackedScene
		var instance := packed.instantiate()
		var mesh := RunnerTrack._first_scene_mesh(instance)
		_check(id + "_normal_import_mesh", mesh != null)
		if mesh != null:
			_check(id + "_one_surface", mesh.get_surface_count() == 1)
			var count := mesh.get_faces().size() / 3
			_check(id + "_triangle_budget", count >= 300 and count <= 1500)
			_check(id + "_ground_pivot", absf(mesh.get_aabb().position.y) <= 0.02)
		instance.free()
	for id: String in ["runner_day_radar_landmark_v1", "runner_day_research_hub_landmark_v1", "runner_day_icebreaker_landmark_v1", "runner_day_snowcat_v1", "runner_day_barrier_v1", "runner_day_ramp_v1", "runner_day_gantry_v1", "runner_day_tunnel_shell_v1", "runner_day_cargo_stack_v1", "runner_day_shell_material_v1"]:
		_check(id + "_remains_unregistered", not catalog.has_asset(id))
	var material := catalog.loaded_resource("runner_day_surface_material_v1") as ShaderMaterial
	_check("one_shared_surface_material", material != null)
	for map: String in ["painted_albedo", "painted_normal", "packed_orm"]:
		var texture := material.get_shader_parameter(map) as Texture2D
		_check(map + "_1024_texture_loaded", texture != null and texture.get_size() == Vector2(1024,1024))
	_check("surface_backface_culling_retained", not material.shader.code.contains("cull_disabled"))
	var authored := _track(art,catalog)
	var fallback := _track(null,null)
	var logic := RunnerTrack.new()
	add_child(logic)
	logic.setup_golden_slice(SEED,0)
	var signature := _signature(logic)
	_check("all_360m_colliders_pickups_powerups_match_fallback", _signature(authored) == _signature(fallback))
	_check("all_360m_colliders_pickups_powerups_match_logic", _signature(authored) == signature)
	var used := _authored_ids(authored)
	_check("exactly_six_selected_roles_instanced", used == _scene_ids)
	_check("partial_status_does_not_claim_whole_kit", not bool(authored.authored_day_kit_status()["active"]) and int(authored.authored_day_kit_status()["loaded"]) == 6)
	var meshes := authored._authored_day_meshes.duplicate()
	for index: int in 4:
		authored.setup_golden_slice(SEED,1)
		_check("retry_%d_same_gameplay" % index, _signature(authored) == signature)
		_check("retry_%d_same_selected_roles" % index, _authored_ids(authored) == _scene_ids)
		_check("retry_%d_same_cached_meshes" % index, authored._authored_day_meshes == meshes)
		_check("retry_%d_bounded_live_chunks" % index, authored._chunks.size() == RunnerTrack.GOLDEN_SLICE_CHUNKS)
		await get_tree().process_frame
	for track: RunnerTrack in [authored,fallback,logic]: track.free()
	# Fresh streamed DAY followed by later bands preserves biome scope and RNG.
	var chunks_per_biome := ceili(RunnerConfig.BIOME_LENGTH / RunnerConfig.CHUNK_LENGTH)
	for biome: int in RunnerTrack.BIOME_COUNT:
		var distance_band := biome * chunks_per_biome
		var a := _normal_track(art,catalog,distance_band)
		var b := _normal_track(null,null,distance_band)
		_check("stream_band_%d_same_gameplay" % distance_band,_signature(a)==_signature(b))
		if distance_band > 0:
			var actual_biome := true
			for chunk: Node in a.get_children():
				if chunk is RunnerTrack.RunnerChunk:
					actual_biome = actual_biome and int(chunk.biome) == biome
			_check("band_%d_is_expected_later_biome" % distance_band, actual_biome)
			_check("biome_%d_has_no_DAY_geometry" % biome,_authored_ids(a).is_empty())
		a.free();b.free()
	await get_tree().process_frame
	print("[day-scoped-candidate] DONE: %d/%d passed" % [_checks-_failures,_checks])
	get_tree().quit(1 if _failures else 0)

func _track(art: RunnerArtSet,catalog: ArtCatalog) -> RunnerTrack:
	var track := RunnerTrack.new()
	add_child(track)
	track.process_mode = Node.PROCESS_MODE_DISABLED
	if art != null: track.configure_art(art,catalog)
	track.setup_golden_slice(SEED,1)
	return track

func _normal_track(art: RunnerArtSet,catalog: ArtCatalog,start: int) -> RunnerTrack:
	var track := RunnerTrack.new()
	add_child(track)
	track.process_mode = Node.PROCESS_MODE_DISABLED
	track._headless = false
	track._seed = SEED
	track._golden_slice = false
	track._clear()
	if art != null: track.configure_art(art,catalog)
	track._prime_art_cache()
	for index: int in range(start,start+6): track._spawn_chunk(index,0.72)
	return track

func _signature(root: Node) -> PackedStringArray:
	var rows := PackedStringArray()
	for node: Node in root.find_children("*","Node3D",true,false):
		var family := ""
		for group: StringName in [RunnerConfig.GROUP_HAZARD,RunnerConfig.GROUP_PICKUP,RunnerConfig.GROUP_POWERUP]:
			if node.is_in_group(group): family = String(group)
		if family.is_empty(): continue
		var shapes := PackedStringArray()
		for child: Node in node.get_children():
			if child is CollisionShape3D:
				var shape := child.shape as Shape3D
				var extent := str(shape.size) if shape is BoxShape3D else (str(shape.radius) if shape is SphereShape3D else str(shape.get_class()))
				shapes.append("%s|%s|%s" % [shape.get_class(),extent,(child as Node3D).transform])
		rows.append("%s|%s|%s|%s|%s|%s|%s" % [family,node.get_meta("kind",""),node.get_meta("lane",-1),node.get_meta("span",1),node.get_meta("powerup",""),(node as Node3D).global_transform,shapes])
	rows.sort()
	return rows

func _authored_ids(root: Node) -> PackedStringArray:
	var ids := PackedStringArray()
	for node: Node in root.find_children("*","Node",true,false):
		if node.has_meta("authored_asset_id"):
			var id := String(node.get_meta("authored_asset_id"))
			if not id in ids: ids.append(id)
	ids.sort()
	return ids

func _check(label: String,ok: bool) -> void:
	_checks += 1
	if not ok: _failures += 1
	print("[day-scoped-candidate] %s %s" % ["PASS" if ok else "FAIL",label])
