extends Node
## Focused contract for the shared authored expedition item cache.
## Validates provenance/budgets/material/LOD, immutable pickup mechanics and
## collision, pooled VFX ownership, and retry resource stability.

const ROOT := "res://assets/art/interactives/item_cache"
const FRAGMENT := "res://data/art/fragments/item_cache_v1.json"
const RETRY_MEMORY_LIMIT := 25 * 1024 * 1024

var _failures := 0


func _ready() -> void:
	_test_static_contract()
	var old_mode := Game.mode
	Game.mode = Game.Mode.QUICK_RACE
	var first := ItemBox.new()
	first.name = "ContractItemCache"
	add_child(first)
	await get_tree().process_frame
	_test_runtime_contract(first)
	var resource_signature := _mesh_resource_signature(first)
	var warm_memory := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	first.free()

	for retry: int in 3:
		var boxes: Array[ItemBox] = []
		for index: int in 24:
			var box := ItemBox.new()
			box.position = Vector3(float(index % 6) * 2.0, 1.1,
				float(index / 6) * -3.0)
			add_child(box)
			boxes.append(box)
		await get_tree().process_frame
		for box: ItemBox in boxes:
			_check("retry_%d_shared_meshes" % retry,
				_mesh_resource_signature(box) == resource_signature,
				"authored cache resources changed identity")
		for box: ItemBox in boxes:
			box.free()
		await get_tree().process_frame
	var growth := int(Performance.get_monitor(Performance.MEMORY_STATIC)) - warm_memory
	_check("retry_memory_bounded", growth <= RETRY_MEMORY_LIMIT,
		"growth=%d limit=%d" % [growth, RETRY_MEMORY_LIMIT])
	Game.mode = old_mode
	if _failures == 0:
		print("ITEM_CACHE_ART PASS retries=3 instances=72 growth=%d" % growth)
	else:
		push_error("ITEM_CACHE_ART FAIL failures=%d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _test_static_contract() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FRAGMENT))
	_check("fragment_json", parsed is Dictionary, FRAGMENT)
	if parsed is Dictionary:
		var runtime_assets: Array = parsed.get("runtime_assets", [])
		var exports: Array = parsed.get("source_exports", [])
		_check("source_export_count", exports.size() == 2, "count=%d" % exports.size())
		_check("runtime_asset_count", runtime_assets.size() == 7,
			"count=%d" % runtime_assets.size())
		_check("production_ready_false", _all_staged(runtime_assets),
			"visual gate must remain staged")
		_check_fragment_hashes(runtime_assets, exports)

	var wrapper := load(ROOT + "/item_cache_v1.tscn") as PackedScene
	_check("wrapper_load", wrapper != null, ROOT + "/item_cache_v1.tscn")
	if wrapper != null:
		var root := wrapper.instantiate()
		_check("wrapper_semantic", String(root.get_meta("semantic_color", ""))
			== "violet_powerup", str(root.get_meta("semantic_color", "")))
		_check("wrapper_shape_cue", String(root.get_meta("shape_cue", ""))
			== "three_lobed_pod_four_point_aperture",
			str(root.get_meta("shape_cue", "")))
		_check("wrapper_staged", not bool(root.get_meta("production_ready", true)),
			"production_ready must stay false")
		_check("wrapper_visual_only", _count_collision_nodes(root) == 0,
			"authored wrapper must contain no gameplay collision")
		_check("wrapper_lods", root.has_node("LOD0") and root.has_node("LOD1"),
			"LOD0/LOD1 roots required")
		root.free()

	for entry: Dictionary in [
		{"id": "item_cache_lod0_v1", "min": 1500, "max": 5000},
		{"id": "item_cache_lod1_v1", "min": 250, "max": 1100},
	]:
		var scene := load("%s/%s.glb" % [ROOT, entry.id]) as PackedScene
		var scene_root := scene.instantiate() if scene != null else null
		var mesh := _first_mesh(scene_root)
		_check("mesh_%s" % entry.id, mesh != null, str(entry.id))
		if scene_root != null:
			scene_root.free()
		if mesh == null:
			continue
		var triangles := mesh.get_faces().size() / 3
		_check("budget_%s" % entry.id,
			triangles >= int(entry.min) and triangles <= int(entry.max),
			"triangles=%d expected=%d..%d" % [triangles, entry.min, entry.max])
		_check("one_surface_%s" % entry.id, mesh.get_surface_count() == 1,
			"surfaces=%d" % mesh.get_surface_count())
		var aabb := mesh.get_aabb()
		_check("bounds_%s" % entry.id,
			aabb.size.x <= 1.4 and aabb.size.y <= 1.4 and aabb.size.z <= 1.4,
			str(aabb))
		_check("center_pivot_%s" % entry.id,
			(aabb.position + aabb.size * 0.5).length() <= 0.025,
			str(aabb.position + aabb.size * 0.5))

	var material := load(ROOT + "/materials/item_cache_v1.tres") as StandardMaterial3D
	_check("atlas_material", material != null, "material missing")
	if material != null:
		_check("material_opaque",
			material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED,
			"primary cache cannot use transparency")
		_check("atlas_maps", material.albedo_texture != null
			and material.normal_texture != null and material.orm_texture != null,
			"albedo + normal + packed ORM required")
		if material.albedo_texture != null:
			_check("atlas_1024", material.albedo_texture.get_size() == Vector2(1024, 1024),
				str(material.albedo_texture.get_size()))
	for role: String in ["albedo", "normal", "orm"]:
		var import_path := "%s/textures/item_cache_%s_v1.png.import" % [ROOT, role]
		var settings := FileAccess.get_file_as_string(import_path)
		_check("texture_import_%s" % role,
			settings.contains("compress/mode=2")
			and settings.contains("mipmaps/generate=true"), import_path)

	var source := FileAccess.get_file_as_string("res://scripts/gameplay/item_box.gd")
	_check("fresh_import_no_cache_preload",
		not source.contains("preload(\n\t\"res://assets/art/interactives/item_cache")
		and not source.contains("const CACHE_SCENE: PackedScene = preload")
		and not source.contains("const CACHE_MATERIAL: StandardMaterial3D = preload"),
		"authored imports must not resolve while ItemBox script parses")
	_check("fresh_import_path_only_contract",
		source.contains("const CACHE_SCENE_PATH :=")
		and source.contains("const CACHE_MATERIAL_PATH :=")
		and source.contains("ResourceLoader.exists(CACHE_SCENE_PATH")
		and source.contains("ResourceLoader.load(\n\t\t\t\tCACHE_SCENE_PATH")
		and source.contains("ResourceLoader.CACHE_MODE_REUSE"),
		"lazy cached ResourceLoader seam missing")
	_check("scene_loader_preload_seam",
		source.contains("static func preload_authored_visual() -> bool:")
		and source.contains("if preload_authored_visual():"),
		"scene construction must prime authored cache after import")
	_check("authored_warmup_registered",
		source.contains("ShaderWarmup.register_external_probe(")
		and source.contains("_cache_warmup_registered"),
		"both LOD programs must warm behind loading overlay")
	_check("mechanics_respawn_unchanged", source.contains("const RESPAWN_TIME: float = 3.5"),
		"respawn timing changed")
	_check("mechanics_roll_unchanged", source.contains(
		"PowerupsDB.roll(racer.race_position, GameConfig.RACER_COUNT, _rng)"),
		"item RNG contract changed")
	_check("mechanics_receive_unchanged", source.contains("racer.receive_item(item)"),
		"grant contract changed")
	_check("legacy_question_removed", not source.contains("GLYPH_SVG")
		and not source.contains("_get_cube_mesh"),
		"legacy question crate remains in runtime")


func _test_runtime_contract(box: ItemBox) -> void:
	_check("collision_layer", box.collision_layer == GameConfig.LAYER_PICKUPS,
		str(box.collision_layer))
	_check("collision_mask", box.collision_mask == GameConfig.LAYER_RACERS,
		str(box.collision_mask))
	var shapes: Array[CollisionShape3D] = []
	_collect_shapes(box, shapes)
	_check("single_gameplay_collider", shapes.size() == 1, "count=%d" % shapes.size())
	if shapes.size() == 1:
		var shape := shapes[0].shape as BoxShape3D
		_check("collider_shape", shape != null and shape.size == Vector3(1.4, 1.4, 1.4),
			str(shape.size) if shape != null else "wrong type")
	_check("body_signal_connected", box.body_entered.get_connections().size() == 1,
		"body_entered handler changed")
	var visual := box.get_node_or_null("AuthoredSupplyCache") as Node3D
	_check("authored_visual_active", visual != null,
		"normal ItemBox run must instantiate authored wrapper")
	if visual == null:
		return
	_check("semantic_runtime", String(visual.get_meta("semantic_color", ""))
		== "violet_powerup", str(visual.get_meta("semantic_color", "")))
	var lod0 := visual.get_node_or_null("LOD0")
	var lod1 := visual.get_node_or_null("LOD1")
	var lod0_meshes: Array[MeshInstance3D] = []
	var lod1_meshes: Array[MeshInstance3D] = []
	_collect_meshes(lod0, lod0_meshes)
	_collect_meshes(lod1, lod1_meshes)
	_check("lod_meshes", not lod0_meshes.is_empty() and not lod1_meshes.is_empty(),
		"LOD roots must resolve imported meshes")
	for mesh: MeshInstance3D in lod0_meshes:
		_check("lod0_range", is_equal_approx(mesh.visibility_range_end, 38.0),
			str(mesh.visibility_range_end))
	for mesh: MeshInstance3D in lod1_meshes:
		_check("lod1_range", is_equal_approx(mesh.visibility_range_begin, 38.0)
			and is_equal_approx(mesh.visibility_range_end, 140.0),
			"%.1f..%.1f" % [mesh.visibility_range_begin, mesh.visibility_range_end])
	_check("pooled_burst_nodes", box.get_node_or_null("PickupBurst") != null
		and box.get_node_or_null("PickupShards") != null
		and box.get_node_or_null("PickupFlash") != null,
		"existing pooled burst layers must remain preallocated")


func _all_staged(entries: Array) -> bool:
	return not entries.is_empty() and entries.all(func(entry: Variant) -> bool:
		return entry is Dictionary and not bool((entry as Dictionary).get("production_ready", true)))


func _check_fragment_hashes(runtime_assets: Array, exports: Array) -> void:
	var ok := true
	for entry: Variant in runtime_assets:
		if not entry is Dictionary:
			ok = false
			continue
		var record := entry as Dictionary
		var path := String(record.get("path", ""))
		ok = ok and String(record.get("license_id", "")) == "project_original"
		ok = ok and not path.is_empty() \
			and FileAccess.get_sha256(path) == String(record.get("sha256", ""))
	for entry: Variant in exports:
		if not entry is Dictionary:
			ok = false
			continue
		var record := entry as Dictionary
		var path := String(record.get("source", ""))
		if not path.begins_with("res://"):
			path = "res://" + path
		ok = ok and String(record.get("license_id", "")) == "project_original"
		ok = ok and FileAccess.get_sha256(path) == String(record.get("source_sha256", ""))
	_check("fragment_hashes_and_licenses", ok, "hash/license mismatch")


func _mesh_resource_signature(root: Node) -> PackedInt64Array:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(root.get_node_or_null("AuthoredSupplyCache"), meshes)
	var ids := PackedInt64Array()
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh != null:
			ids.append(mesh.mesh.get_instance_id())
	ids.sort()
	return ids


func _collect_meshes(node: Node, output: Array[MeshInstance3D]) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		output.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect_meshes(child, output)


func _collect_shapes(node: Node, output: Array[CollisionShape3D]) -> void:
	if node is CollisionShape3D:
		output.append(node as CollisionShape3D)
	for child: Node in node.get_children():
		_collect_shapes(child, output)


func _count_collision_nodes(node: Node) -> int:
	var count := 1 if node is CollisionObject3D or node is CollisionShape3D else 0
	for child: Node in node.get_children():
		count += _count_collision_nodes(child)
	return count


func _first_mesh(node: Node) -> Mesh:
	if node == null:
		return null
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return (node as MeshInstance3D).mesh
	for child: Node in node.get_children():
		var found := _first_mesh(child)
		if found != null:
			return found
	return null


func _check(label: String, condition: bool, detail: String) -> void:
	if condition:
		print("[item-cache-art] PASS %s" % label)
		return
	_failures += 1
	push_error("[item-cache-art] FAIL %s: %s" % [label, detail])
