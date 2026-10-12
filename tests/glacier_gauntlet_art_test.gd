extends Node
## Focused authored Glacier contract: import/budgets, transactional activation,
## collision parity, isolated art RNG, retry/cache stability and profile tiers.

const EXPECTED_IDS: PackedStringArray = [
	"glacier_edge_kerb_v1",
	"glacier_surface_inlay_v1",
	"glacier_track_skin_patch_v1",
	"glacier_route_beacon_v1",
	"glacier_route_flag_v1",
	"glacier_snow_fence_v1",
	"glacier_expedition_crate_v1",
	"glacier_rescue_sled_v1",
	"glacier_field_tent_v1",
	"glacier_field_lab_v1",
	"glacier_camp_lamp_v1",
	"glacier_weather_mast_v1",
	"glacier_ice_spire_v1",
	"glacier_ice_boulder_v1",
	"glacier_snowbank_v1",
	"glacier_layered_ridge_v1",
	"glacier_cave_buttress_v1",
	"glacier_duck_gate_v1",
	"glacier_snowball_warning_v1",
	"glacier_cracking_ice_marker_v1",
	"glacier_boost_marker_v1",
	"glacier_ice_arch_landmark_v1",
	"glacier_frozen_fall_landmark_v1",
	"glacier_summit_station_landmark_v1",
]
const OBSTACLES: PackedStringArray = [
	"glacier_duck_gate_v1",
	"glacier_snowball_warning_v1",
	"glacier_cracking_ice_marker_v1",
	"glacier_boost_marker_v1",
]
const LANDMARKS: PackedStringArray = [
	"glacier_ice_arch_landmark_v1",
	"glacier_frozen_fall_landmark_v1",
	"glacier_summit_station_landmark_v1",
]
const ROOT := "res://assets/art/courses/glacier"
const RETRY_MEMORY_LIMIT: int = 25 * 1024 * 1024

var _failures: int = 0


func _ready() -> void:
	_test_static_contract()
	var old_force := CourseGlacier.force_authored_art_for_tests
	var old_disable := CourseGlacier.disable_authored_art_for_tests

	CourseGlacier.force_authored_art_for_tests = false
	CourseGlacier.disable_authored_art_for_tests = true
	var baseline := CourseGlacier.new()
	baseline.name = "BaselineGlacier"
	add_child(baseline)
	await baseline.build_ready()
	var gameplay_signature := _gameplay_signature(baseline)
	var collision_signature := _collision_signature(baseline)
	var baseline_hazards := _hazard_signature(baseline)
	baseline.free()

	CourseGlacier.force_authored_art_for_tests = true
	CourseGlacier.disable_authored_art_for_tests = false
	var authored := CourseGlacier.new()
	authored.name = "AuthoredGlacierA"
	add_child(authored)
	await authored.build_ready()
	var status := authored.authored_art_status()
	_check("kit_active", bool(status.get("active", false)), str(status))
	_check("kit_complete", int(status.get("loaded", -1)) == EXPECTED_IDS.size(), str(status))
	_check("layout_dense", int(status.get("layout_count", 0)) >= 260, str(status))
	for asset_id: String in CourseGlacier.AUTHORED_LATE_WARM_IDS:
		_check("warmup_%s" % asset_id, ShaderWarmup.has_external_probe(
			authored._authored_meshes.get(asset_id) as Mesh,
			authored._authored_material), "late mesh/material pair missing")
	_check("warmup_bounded", ShaderWarmup.external_probe_count()
		<= ShaderWarmup.MAX_EXTERNAL_PROBES,
		"count=%d" % ShaderWarmup.external_probe_count())
	_check("gameplay_guide_parity", gameplay_signature == _gameplay_signature(authored),
		"authored visual pass changed guide/hints/checkpoints")
	var authored_collisions := _collision_signature(authored)
	var authored_hazards := _hazard_signature(authored)
	_check("collider_transform_parity", collision_signature == authored_collisions,
		_signature_difference(collision_signature, authored_collisions))
	_check("hazard_transform_parity", baseline_hazards == authored_hazards,
		_signature_difference(baseline_hazards, authored_hazards))
	_check("visual_root_no_collision", _count_collision_nodes(
		authored.get_node_or_null("AuthoredGlacierArt")) == 0,
		"authored root must remain visual-only")
	var chunk_ratio := _max_chunk_radius_ratio(
		authored.get_node_or_null("AuthoredGlacierArt"))
	_check("chunk_range_local", chunk_ratio <= 1.15,
		"instance-to-centroid/range ratio=%.3f; sparse art can disappear" % chunk_ratio)
	_check("crystalline_material_family", authored._authored_ice_material != null
		and authored._authored_ice_material != authored._authored_material
		and authored._authored_ice_material.rim_enabled,
		"natural ice requires separate Compatibility-safe rim response")
	_check("atmospheric_ridge_material", authored._authored_far_ice_material != null
		and authored._authored_far_ice_material != authored._authored_ice_material
		and not authored._authored_far_ice_material.clearcoat_enabled,
		"far authored ridges require low-contrast non-glossy response")
	_check("camp_lab_material_separation", authored._authored_lab_material != null
		and authored._authored_lab_material != authored._authored_material
		and authored._authored_lab_material.rim_enabled
		and authored._authored_lab_material.albedo_color.r > 1.0,
		"hero lab needs lifted canvas response without extra light count")
	var layout_a := authored.authored_layout_signature()
	_check("opening_lab_landmark_mass",
		layout_a.count("glacier_field_lab_v1|") == 2,
		"opening requires paired hero lab volumes")
	_check("opening_warm_lamp_story",
		layout_a.count("glacier_camp_lamp_v1|") >= 4
		and layout_a.count("expedition_camp_warm_light|") == 2,
		"camp requires four fixtures and two bounded warm lights")
	_check("authored_track_skin_breakup",
		layout_a.count("glacier_track_skin_patch_v1|") >= 28,
		"main route requires sparse broad polish patches")
	var warm_memory := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	authored.free()

	# Two retries: same layout, cached resources reused, bounded working memory.
	# Hold wrappers strongly across retries; ResourceLoader may release
	# unreferenced resources, which is not evidence of retry churn.
	var held_scenes := _scene_resources()
	var scene_resource_ids := _resource_ids(held_scenes)
	var layout_b := ""
	for retry: int in 2:
		var rebuilt := CourseGlacier.new()
		rebuilt.name = "AuthoredGlacierRetry%d" % retry
		add_child(rebuilt)
		await rebuilt.build_ready()
		_check("retry_%d_active" % retry,
			bool(rebuilt.authored_art_status().get("active", false)),
			str(rebuilt.authored_art_status()))
		layout_b = rebuilt.authored_layout_signature()
		_check("retry_%d_art_rng_deterministic" % retry, layout_a == layout_b,
			"authored placement changed across retry")
		rebuilt.free()
		await get_tree().process_frame
	_check("resource_cache_stable", scene_resource_ids == _resource_ids(_scene_resources()),
		"PackedScene cache changed identity across retry")
	var retry_growth := int(Performance.get_monitor(Performance.MEMORY_STATIC)) - warm_memory
	_check("retry_memory_bounded", retry_growth <= RETRY_MEMORY_LIMIT,
		"growth=%d bytes limit=%d" % [retry_growth, RETRY_MEMORY_LIMIT])

	CourseGlacier.force_authored_art_for_tests = old_force
	CourseGlacier.disable_authored_art_for_tests = old_disable
	if _failures == 0:
		print("GLACIER_GAUNTLET_ART PASS assets=%d layout=%d retry_growth=%d" % [
			EXPECTED_IDS.size(), layout_a.count("\n") + 1, retry_growth])
	else:
		push_error("GLACIER_GAUNTLET_ART FAIL failures=%d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _test_static_contract() -> void:
	var profile := load("res://data/art/course_profiles/glacier_gauntlet_v1.tres") as CourseVisualProfile
	_check("profile_exists", profile != null, "missing CourseVisualProfile")
	if profile != null:
		_check("profile_valid", profile.validation_errors().is_empty(),
			str(profile.validation_errors()))
		for tier: String in CourseVisualProfile.TIERS:
			var values := profile.quality_settings(tier)
			_check("tier_%s" % tier, not values.is_empty()
				and values.has("dressing_density") and values.has("lod_threshold")
				and values.has("shadow_distance"), str(values))
	var fragment_text := FileAccess.get_file_as_string(
		"res://data/art/fragments/glacier_gauntlet_v1.json")
	var fragment: Variant = JSON.parse_string(fragment_text)
	_check("fragment_json", fragment is Dictionary, fragment_text.left(120))
	if fragment is Dictionary:
		var source_exports: Array = fragment.get("source_exports", [])
		var runtime_assets: Array = fragment.get("runtime_assets", [])
		_check("source_export_count", source_exports.size() == EXPECTED_IDS.size(),
			"count=%d" % source_exports.size())
		var readiness := _uniform_readiness(runtime_assets)
		_check("production_readiness_uniform", readiness >= 0,
			"fragment cannot mix staged and approved runtime records")
		_check("profile_readiness_matches", profile != null
			and profile.approved_for_runtime == (readiness == 1),
			"profile=%s fragment_state=%d" % [
				str(profile.approved_for_runtime) if profile != null else "null", readiness])
		var hash_contract := _fragment_hash_contract(runtime_assets, source_exports)
		_check("fragment_hashes", bool(hash_contract.get("hashes", false)),
			String(hash_contract.get("detail", "hash mismatch")))
		_check("fragment_licenses", bool(hash_contract.get("licenses", false)),
			String(hash_contract.get("detail", "license mismatch")))
	for asset_id: String in EXPECTED_IDS:
		var path := "%s/%s.tscn" % [ROOT, asset_id]
		var packed := load(path) as PackedScene
		var mesh := _scene_mesh(packed)
		_check("wrapper_%s" % asset_id, mesh != null, path)
		if mesh == null:
			continue
		var triangles := mesh.get_faces().size() / 3
		var minimum := 10000 if asset_id in LANDMARKS else 1500 if asset_id in OBSTACLES else 300
		var maximum := 30000 if asset_id in LANDMARKS else 5000 if asset_id in OBSTACLES else 1500
		_check("budget_%s" % asset_id, triangles >= minimum and triangles <= maximum,
			"triangles=%d expected=%d..%d" % [triangles, minimum, maximum])
		_check("surface_%s" % asset_id, mesh.get_surface_count() == 1,
			"surfaces=%d" % mesh.get_surface_count())
		_check("pivot_%s" % asset_id, absf(mesh.get_aabb().position.y) <= 0.025,
			"aabb_min_y=%.4f" % mesh.get_aabb().position.y)
		var import_text := FileAccess.get_file_as_string(
			"%s/%s.glb.import" % [ROOT, asset_id])
		_check("lod_import_%s" % asset_id,
			import_text.contains("meshes/generate_lods=true"), "generated mesh LODs required")
	var material := load(
		"res://assets/art/courses/glacier/materials/glacier_surface_v1.tres") \
		as StandardMaterial3D
	_check("atlas_material", material != null and material.albedo_texture != null
		and material.normal_texture != null and material.orm_texture != null,
		"albedo + normal + ORM required")
	if material != null and material.albedo_texture != null:
		_check("atlas_1024", material.albedo_texture.get_size() == Vector2(1024, 1024),
			str(material.albedo_texture.get_size()))
	for role: String in ["albedo", "normal", "orm"]:
		var import_path := "%s/textures/glacier_surface_%s_v1.png.import" % [ROOT, role]
		var import_settings := FileAccess.get_file_as_string(import_path)
		_check("texture_import_%s" % role,
			import_settings.contains("compress/mode=2")
			and import_settings.contains("mipmaps/generate=true"), import_path)


## 0 all staged, 1 all approved, -1 empty/mixed/invalid.
func _uniform_readiness(entries: Array) -> int:
	if entries.is_empty():
		return -1
	if not entries[0] is Dictionary:
		return -1
	var expected := bool((entries[0] as Dictionary).get("production_ready", false))
	for entry: Variant in entries:
		if not entry is Dictionary \
				or bool((entry as Dictionary).get("production_ready", not expected)) != expected:
			return -1
	return 1 if expected else 0


func _fragment_hash_contract(runtime_assets: Array, source_exports: Array) -> Dictionary:
	var licenses_valid := true
	for entry: Variant in runtime_assets:
		if not entry is Dictionary:
			return {"hashes": false, "licenses": false, "detail": "invalid runtime record"}
		var record := entry as Dictionary
		var path := String(record.get("path", ""))
		var expected := String(record.get("sha256", ""))
		licenses_valid = licenses_valid \
			and String(record.get("license_id", "")) == "project_original"
		if path.is_empty() or expected.is_empty() or FileAccess.get_sha256(path) != expected:
			return {"hashes": false, "licenses": licenses_valid,
				"detail": "runtime hash mismatch %s" % path}
	for entry: Variant in source_exports:
		if not entry is Dictionary:
			return {"hashes": false, "licenses": false, "detail": "invalid source record"}
		var record := entry as Dictionary
		var source_path := String(record.get("source", ""))
		if not source_path.begins_with("res://"):
			source_path = "res://" + source_path
		licenses_valid = licenses_valid \
			and String(record.get("license_id", "")) == "project_original"
		if FileAccess.get_sha256(source_path) != String(record.get("source_sha256", "")):
			return {"hashes": false, "licenses": licenses_valid,
				"detail": "source hash mismatch %s" % source_path}
	return {"hashes": true, "licenses": licenses_valid, "detail": ""}


func _scene_mesh(scene: PackedScene) -> Mesh:
	if scene == null:
		return null
	var root := scene.instantiate()
	var mesh := _first_mesh(root)
	root.free()
	return mesh


func _first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return (node as MeshInstance3D).mesh
	for child: Node in node.get_children():
		var found := _first_mesh(child)
		if found != null:
			return found
	return null


func _gameplay_signature(course: CourseGlacier) -> String:
	var rows := PackedStringArray()
	rows.append("length=%.4f|finish=%.4f|branches=%d" % [
		course.main_guide.length, course.finish_offset, course.branches.size()])
	for sample: int in 65:
		var offset := course.main_guide.length * float(sample) / 64.0
		var point := course.main_guide.position_at(offset)
		rows.append("p|%.3f|%.3f|%.3f" % [point.x, point.y, point.z])
	for hint: Dictionary in course.hints:
		rows.append("h|%s|%.3f|%.3f|%d" % [String(hint.get("type", "")),
			float(hint.get("offset", 0.0)), float(hint.get("end_offset", 0.0)),
			int(hint.get("branch_id", -1))])
	for offset: float in course.checkpoint_offsets:
		rows.append("c|%.3f" % offset)
	rows.sort()
	return "\n".join(rows)


func _collision_signature(root: Node) -> String:
	var rows := PackedStringArray()
	_collect_collisions(root, root, rows)
	rows.sort()
	return "\n".join(rows)


func _collect_collisions(node: Node, root: Node, rows: PackedStringArray) -> void:
	if node is CollisionObject3D:
		var body := node as CollisionObject3D
		rows.append("body|%s|%d|%d|%s" % [node.get_class(), body.collision_layer,
			body.collision_mask, _transform_signature(body.global_transform)])
	if node is CollisionShape3D:
		var shape_node := node as CollisionShape3D
		rows.append("shape|%s|%s" % [_shape_signature(shape_node.shape),
			_transform_signature(shape_node.global_transform)])
	for child: Node in node.get_children():
		_collect_collisions(child, root, rows)


func _hazard_signature(root: Node) -> String:
	var rows := PackedStringArray()
	_collect_hazards(root, root, rows)
	rows.sort()
	return "\n".join(rows)


func _collect_hazards(node: Node, root: Node, rows: PackedStringArray) -> void:
	if node.is_in_group(&"hazards") and node is Node3D:
		var spatial := node as Node3D
		var script_path := (node.get_script() as Script).resource_path \
			if node.get_script() is Script else node.get_class()
		rows.append("%s|%s" % [script_path,
			_transform_signature(spatial.global_transform)])
	for child: Node in node.get_children():
		_collect_hazards(child, root, rows)


func _transform_signature(xform: Transform3D) -> String:
	return "%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f" % [
		xform.origin.x, xform.origin.y, xform.origin.z,
		xform.basis.x.x, xform.basis.x.y, xform.basis.x.z,
		xform.basis.y.x, xform.basis.y.y, xform.basis.y.z,
		xform.basis.z.x, xform.basis.z.y, xform.basis.z.z,
	]


func _shape_signature(shape: Shape3D) -> String:
	if shape == null:
		return "null"
	if shape is BoxShape3D:
		var size := (shape as BoxShape3D).size
		return "Box|%.4f|%.4f|%.4f" % [size.x, size.y, size.z]
	if shape is SphereShape3D:
		return "Sphere|%.4f" % (shape as SphereShape3D).radius
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		return "Capsule|%.4f|%.4f" % [capsule.radius, capsule.height]
	if shape is CylinderShape3D:
		var cylinder_shape := shape as CylinderShape3D
		return "Cylinder|%.4f|%.4f" % [cylinder_shape.radius, cylinder_shape.height]
	return shape.get_class()


func _count_collision_nodes(root: Node) -> int:
	if root == null:
		return 0
	var count := 1 if root is CollisionObject3D or root is CollisionShape3D else 0
	for child: Node in root.get_children():
		count += _count_collision_nodes(child)
	return count


func _max_chunk_radius_ratio(root: Node) -> float:
	if root == null:
		return INF
	var maximum := 0.0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node := stack.pop_back() as Node
		if node is MultiMeshInstance3D:
			var instance := node as MultiMeshInstance3D
			var range_end := maxf(instance.visibility_range_end, 0.001)
			if instance.multimesh != null:
				for index: int in instance.multimesh.instance_count:
					maximum = maxf(maximum,
						instance.multimesh.get_instance_transform(index).origin.length()
						/ range_end)
		for child: Node in node.get_children():
			stack.append(child)
	return maximum


func _scene_resources() -> Array[PackedScene]:
	var resources: Array[PackedScene] = []
	for asset_id: String in EXPECTED_IDS:
		resources.append(load("%s/%s.tscn" % [ROOT, asset_id]) as PackedScene)
	return resources


func _resource_ids(resources: Array[PackedScene]) -> PackedStringArray:
	var rows := PackedStringArray()
	for index: int in resources.size():
		var resource := resources[index]
		rows.append("%s|%d" % [EXPECTED_IDS[index],
			resource.get_instance_id() if resource != null else -1])
	return rows


func _signature_difference(expected: String, actual: String) -> String:
	var expected_rows := expected.split("\n")
	var actual_rows := actual.split("\n")
	var count := maxi(expected_rows.size(), actual_rows.size())
	for index: int in count:
		var expected_row := expected_rows[index] if index < expected_rows.size() else "<missing>"
		var actual_row := actual_rows[index] if index < actual_rows.size() else "<missing>"
		if expected_row != actual_row:
			return "row=%d baseline=%s authored=%s" % [index, expected_row, actual_row]
	return "signatures differ"


func _check(label: String, passed: bool, detail: String) -> void:
	if passed:
		print("  PASS ", label)
	else:
		_failures += 1
		push_error("  FAIL %s: %s" % [label, detail])
