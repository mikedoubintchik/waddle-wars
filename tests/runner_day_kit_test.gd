extends Node
## Focused DAY authored-kit contract. Uses real wrapper scenes through
## RunnerArtSet/ArtCatalog, then compares rendered and logic-only layouts.

const SEED: int = 20260818
const EXPECTED_IDS: PackedStringArray = [
	"runner_day_barrier_v1",
	"runner_day_cargo_stack_v1",
	"runner_day_deck_kerb_b_v1",
	"runner_day_deck_kerb_c_v1",
	"runner_day_deck_kerb_v1",
	"runner_day_gantry_v1",
	"runner_day_iceberg_cluster_v1",
	"runner_day_icebreaker_landmark_v1",
	"runner_day_radar_landmark_v1",
	"runner_day_ramp_v1",
	"runner_day_research_hub_landmark_v1",
	"runner_day_research_lab_v1",
	"runner_day_signal_pylon_v1",
	"runner_day_snowcat_v1",
	"runner_day_tunnel_shell_v1",
]
const TRIANGLE_RANGES: Dictionary = {
	"runner_day_barrier_v1": Vector2i(1500, 5000),
	"runner_day_cargo_stack_v1": Vector2i(300, 1500),
	"runner_day_deck_kerb_b_v1": Vector2i(300, 1500),
	"runner_day_deck_kerb_c_v1": Vector2i(300, 1500),
	"runner_day_deck_kerb_v1": Vector2i(300, 1500),
	"runner_day_gantry_v1": Vector2i(1500, 5000),
	"runner_day_iceberg_cluster_v1": Vector2i(300, 1500),
	"runner_day_icebreaker_landmark_v1": Vector2i(10000, 30000),
	"runner_day_radar_landmark_v1": Vector2i(10000, 30000),
	"runner_day_ramp_v1": Vector2i(1500, 5000),
	"runner_day_research_hub_landmark_v1": Vector2i(10000, 30000),
	"runner_day_research_lab_v1": Vector2i(300, 1500),
	"runner_day_signal_pylon_v1": Vector2i(300, 1500),
	"runner_day_snowcat_v1": Vector2i(1500, 5000),
	"runner_day_tunnel_shell_v1": Vector2i(1500, 5000),
}
const AUTHORED_OBSTACLE_IDS: PackedStringArray = [
	"runner_day_barrier_v1", "runner_day_gantry_v1", "runner_day_ramp_v1",
	"runner_day_snowcat_v1",
]
const LANDMARK_IDS: PackedStringArray = [
	"runner_day_icebreaker_landmark_v1", "runner_day_radar_landmark_v1",
	"runner_day_research_hub_landmark_v1",
]

var _failures: int = 0


func _ready() -> void:
	var art_set := load("res://data/art/runner_art_set_foundation.tres") as RunnerArtSet
	var catalog := ArtCatalog.new()
	catalog.manifest_path = "res://tests/fixtures/art/runner_day_kit_catalog.json"
	_check("catalog_reload", catalog.reload_manifest() == OK, str(catalog.manifest_errors()))
	_check("art_set_valid", art_set != null and art_set.validation_errors().is_empty(),
			str(art_set.validation_errors()) if art_set != null else "null")
	for asset_id: String in EXPECTED_IDS:
		_check("catalog_%s" % asset_id, catalog.has_asset(asset_id), catalog.asset_path(asset_id))
		var packed := catalog.load_now(asset_id) as PackedScene
		var mesh := _scene_mesh(packed) if packed != null else null
		_check("wrapper_%s" % asset_id, mesh != null, "missing mesh")
		if mesh != null:
			var budget: Vector2i = TRIANGLE_RANGES[asset_id]
			var triangles := _triangle_count(mesh)
			_check("surface_%s" % asset_id, mesh.get_surface_count() == 1,
					"surfaces=%d" % mesh.get_surface_count())
			_check("budget_%s" % asset_id,
					triangles >= budget.x and triangles <= budget.y,
					"triangles=%d expected=%d..%d" % [triangles, budget.x, budget.y])
			_check("pivot_%s" % asset_id, absf(mesh.get_aabb().position.y) <= 0.02,
					"aabb_min_y=%.4f" % mesh.get_aabb().position.y)
	var deck_mesh := _scene_mesh(catalog.load_now(
			"runner_day_deck_kerb_v1") as PackedScene)
	var lab_mesh := _scene_mesh(catalog.load_now(
			"runner_day_research_lab_v1") as PackedScene)
	var tunnel_mesh := _scene_mesh(catalog.load_now(
			"runner_day_tunnel_shell_v1") as PackedScene)
	_check("deck_white_is_deposit_not_base", deck_mesh != null
			and _mesh_white_area_ratio(deck_mesh) <= 0.28,
			"white_area_ratio=%.3f" % _mesh_white_area_ratio(deck_mesh))
	_check("occupied_port_has_warm_windows", lab_mesh != null
			and _has_warm_window_colour(lab_mesh), "warm amber COLOR_0 missing")
	var surface := catalog.load_now("runner_day_surface_material_v1") as ShaderMaterial
	var shell := catalog.load_now("runner_day_shell_material_v1") as ShaderMaterial
	var surface_albedo: Texture2D = null
	var surface_normal: Texture2D = null
	var surface_orm: Texture2D = null
	if surface != null:
		surface_albedo = surface.get_shader_parameter("painted_albedo") as Texture2D
		surface_normal = surface.get_shader_parameter("painted_normal") as Texture2D
		surface_orm = surface.get_shader_parameter("packed_orm") as Texture2D
	_check("surface_maps", surface != null and surface_albedo != null
			and surface_normal != null and surface_orm != null,
			"albedo/normal/ORM required")
	_check("surface_runtime_backface_culling", surface != null and surface.shader != null
			and not surface.shader.code.contains("cull_disabled"), str(surface))
	_check("tunnel_has_no_opposite_winding_duplicates", tunnel_mesh != null
			and _opposite_winding_duplicate_count(tunnel_mesh) == 0,
			"duplicates=%d" % _opposite_winding_duplicate_count(tunnel_mesh))
	_check("painted_shader_variants_exactly_two", surface != null and shell != null
			and surface.shader != null and shell.shader != null
			and surface.shader != shell.shader
			and surface.shader.resource_path.ends_with("runner_day_surface_v1.gdshader")
			and shell.shader.resource_path.ends_with("runner_day_shell_v1.gdshader"),
			"surface=%s shell=%s" % [
				surface.shader.resource_path if surface != null and surface.shader != null else "null",
				shell.shader.resource_path if shell != null and shell.shader != null else "null",
			])
	if surface != null and surface_albedo != null:
		_check("atlas_1024", surface_albedo.get_width() == 1024
				and surface_albedo.get_height() == 1024,
				str(surface_albedo.get_size()))
		var normal_strength := float(surface.get_shader_parameter("normal_strength"))
		var emission_lift := float(surface.get_shader_parameter("emission_lift"))
		_check("painted_material_response", normal_strength >= 0.75
				and emission_lift > 0.0 and emission_lift <= 0.08
				and surface.shader.code.contains("EMISSION = painted * emission_lift")
				and not surface.shader.code.contains("SCREEN_TEXTURE")
				and not surface.shader.code.contains("DEPTH_TEXTURE")
				and not surface.shader.code.contains("dFdx")
				and not surface.shader.code.contains("dFdy"),
				"normal=%.2f emission=%.3f" % [normal_strength, emission_lift])
	if shell != null and shell.shader != null:
		var shell_normal_strength := float(shell.get_shader_parameter("normal_strength"))
		var shell_emission_lift := float(shell.get_shader_parameter("emission_lift"))
		_check("painted_shell_response", shell_normal_strength >= 0.75
				and shell_emission_lift > 0.0 and shell_emission_lift <= 0.08
				and shell.shader.code.contains("EMISSION = painted * emission_lift")
				and not shell.shader.code.contains("SCREEN_TEXTURE")
				and not shell.shader.code.contains("DEPTH_TEXTURE")
				and not shell.shader.code.contains("dFdx")
				and not shell.shader.code.contains("dFdy"),
				"normal=%.2f emission=%.3f" % [shell_normal_strength, shell_emission_lift])
	var orm_texture := load(
			"res://assets/art/runner/day/textures/runner_day_surface_orm_v1.png") as Texture2D
	var albedo_texture := load(
			"res://assets/art/runner/day/textures/runner_day_surface_albedo_v1.png") as Texture2D
	var normal_texture := load(
			"res://assets/art/runner/day/textures/runner_day_surface_normal_v1.png") as Texture2D
	var orm_image := orm_texture.get_image() if orm_texture != null else null
	var albedo_image := albedo_texture.get_image() if albedo_texture != null else null
	var normal_image := normal_texture.get_image() if normal_texture != null else null
	if orm_image != null and orm_image.is_compressed():
		orm_image.decompress()
	if albedo_image != null and albedo_image.is_compressed():
		albedo_image.decompress()
	if normal_image != null and normal_image.is_compressed():
		normal_image.decompress()
	if orm_image != null and not orm_image.is_empty():
		var ice := _atlas_sample(orm_image, 4)
		var snow := _atlas_sample(orm_image, 5)
		var glass := _atlas_sample(orm_image, 6)
		var gold := _atlas_sample(orm_image, 11)
		_check("orm_semantic_materials",
			snow.g >= 0.62 and snow.b <= 0.08
			and ice.g >= 0.20 and ice.g <= 0.62 and ice.b <= 0.08
			and glass.g <= 0.45 and gold.b >= 0.35,
			"ice=%s snow=%s glass=%s gold=%s" % [ice, snow, glass, gold])
		var roughness_range := _atlas_channel_range(orm_image, 1, 1)
		_check("orm_macro_roughness_range", roughness_range >= 0.12,
			"range=%.4f" % roughness_range)
		var deck_paint := _atlas_sample(orm_image, 13)
		var tracked_frost := _atlas_sample(orm_image, 14)
		var warm_window := _atlas_sample(orm_image, 15)
		_check("orm_lived_in_materials",
			deck_paint.g >= 0.42 and deck_paint.g <= 0.80
			and tracked_frost.g >= 0.64 and warm_window.g <= 0.44,
			"deck=%s frost=%s window=%s" % [deck_paint, tracked_frost, warm_window])
	else:
		_check("orm_semantic_materials", false, "ORM source unavailable")
		_check("orm_macro_roughness_range", false, "ORM source unavailable")
	if albedo_image != null and not albedo_image.is_empty():
		var value_range := _atlas_value_range(albedo_image, 1)
		_check("atlas_macro_value_range", value_range >= 0.08,
			"range=%.4f" % value_range)
	else:
		_check("atlas_macro_value_range", false, "albedo source unavailable")
	if normal_image != null and not normal_image.is_empty():
		var normal_range := maxf(_atlas_channel_range(normal_image, 1, 0),
				_atlas_channel_range(normal_image, 1, 1))
		_check("normal_macro_response", normal_range >= 0.10,
			"range=%.4f" % normal_range)
	else:
		_check("normal_macro_response", false, "normal source unavailable")
	for role: String in ["albedo", "normal", "orm"]:
		var import_path := "res://assets/art/runner/day/textures/runner_day_surface_%s_v1.png.import" % role
		var import_settings := FileAccess.get_file_as_string(import_path)
		_check("texture_import_%s" % role,
				import_settings.contains("compress/mode=2")
				and import_settings.contains("mipmaps/generate=true"), import_path)

	var visual_track := RunnerTrack.new()
	visual_track.name = "VisualTrack"
	add_child(visual_track)
	visual_track.configure_art(art_set, catalog)
	visual_track.setup_golden_slice(SEED, 1)
	var status := visual_track.authored_day_kit_status()
	_check("kit_active", bool(status.get("active", false)), str(status))
	_check("kit_count", int(status.get("loaded", -1)) == EXPECTED_IDS.size(), str(status))
	var used := _authored_ids(visual_track)
	_check("all_roles_instanced", used == EXPECTED_IDS, str(used))
	var authored_tunnels := visual_track.find_children(
			"AuthoredTunnel", "MultiMeshInstance3D", true, false)
	var tunnel_surface_only := authored_tunnels.size() == 1
	for value: Node in authored_tunnels:
		tunnel_surface_only = tunnel_surface_only \
				and (value as GeometryInstance3D).material_override == surface
	_check("authored_tunnel_reuses_day_surface_signature", tunnel_surface_only,
			"tunnels=%d" % authored_tunnels.size())
	var authored_icebergs := _multimesh_instance_count(
			visual_track, "AuthoredIcebergClusters")
	_check("icebergs_are_skyline_beats_not_wallpaper",
			authored_icebergs >= 3 and authored_icebergs <= 5,
			"instances=%d" % authored_icebergs)
	var authored_landmarks := 0
	for value: Node in visual_track.find_children("*", "MultiMeshInstance3D", true, false):
		if String(value.get_meta("authored_asset_id", "")) in LANDMARK_IDS:
			authored_landmarks += (value as MultiMeshInstance3D).multimesh.instance_count
	_check("three_destination_hierarchy", authored_landmarks == 3,
			"landmark_instances=%d" % authored_landmarks)
	for family: String in ["AuthoredSignalPylons", "AuthoredResearchLabs", "AuthoredCargoStacks"]:
		var family_nodes := visual_track.find_children(
				family, "MultiMeshInstance3D", true, false).size()
		_check("clustered_%s" % family, family_nodes > 0
				and family_nodes < RunnerTrack.GOLDEN_SLICE_CHUNKS,
				"nodes=%d chunks=%d" % [family_nodes, RunnerTrack.GOLDEN_SLICE_CHUNKS])
	var authored_obstacles := 0
	var authored_obstacle_shadows_off := true
	for value: Node in visual_track.find_children("*", "MeshInstance3D", true, false):
		if not value.has_meta("authored_asset_id"):
			continue
		var obstacle_id := String(value.get_meta("authored_asset_id"))
		if obstacle_id not in AUTHORED_OBSTACLE_IDS:
			continue
		authored_obstacles += 1
		authored_obstacle_shadows_off = authored_obstacle_shadows_off and (
				(value as GeometryInstance3D).cast_shadow \
				== GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_check("authored_obstacles_use_pooled_contact_not_cast_shadows",
			authored_obstacles > 0 and authored_obstacle_shadows_off,
			"obstacles=%d shadows_off=%s" % [
				authored_obstacles, authored_obstacle_shadows_off])
	var contact_nodes := visual_track.find_children("Contact", "MultiMeshInstance3D", true, false)
	var pooled_contacts := 0
	for value: Node in contact_nodes:
		pooled_contacts += (value as MultiMeshInstance3D).multimesh.instance_count
	_check("portal_feet_join_contact_pool", pooled_contacts > authored_obstacles,
			"contacts=%d authored_obstacles=%d" % [pooled_contacts, authored_obstacles])
	_check("deck_variants_instanced",
		visual_track.find_children("AuthoredDeckKerb*", "MultiMeshInstance3D", true, false).size()
				== RunnerTrack.GOLDEN_SLICE_CHUNKS * 3,
		"nodes=%d" % visual_track.find_children(
				"AuthoredDeckKerb*", "MultiMeshInstance3D", true, false).size())
	var deck_module_count := 0
	var deck_alignment_clean := true
	var deck_alignment_detail := ""
	for value: Node in visual_track.find_children(
			"AuthoredDeckKerb*", "MultiMeshInstance3D", true, false):
		var multi := (value as MultiMeshInstance3D).multimesh
		deck_module_count += multi.instance_count
		var source_transforms: Array = value.get_meta("authored_source_transforms", [])
		deck_alignment_clean = deck_alignment_clean \
				and source_transforms.size() == multi.instance_count
		for index: int in source_transforms.size():
			var transform: Transform3D = source_transforms[index]
			var scale := transform.basis.get_scale()
			var aligned := absf(transform.origin.y - RunnerTrack.AUTHORED_DAY_DECK_Y) <= 0.001 \
					and scale.distance_to(Vector3.ONE) <= 0.001
			deck_alignment_clean = deck_alignment_clean and aligned
			if not aligned and deck_alignment_detail.is_empty():
				deck_alignment_detail = "%s[%d] y=%.6f scale=%s" % [
						value.name, index, transform.origin.y, scale]
	_check("deck_modules_exact_seam_alignment",
		deck_module_count == RunnerTrack.GOLDEN_SLICE_CHUNKS * 6
		and deck_alignment_clean,
		"instances=%d aligned=%s first=%s" % [
				deck_module_count, deck_alignment_clean, deck_alignment_detail])
	_check("authored_deck_replaces_double_verge",
		visual_track.find_children("Verge", "MeshInstance3D", true, false).is_empty()
		and visual_track.find_children(
				"AuthoredDaySnowShelf", "MeshInstance3D", true, false).size()
				== RunnerTrack.GOLDEN_SLICE_CHUNKS,
		"verges=%d shelves=%d" % [
			visual_track.find_children("Verge", "MeshInstance3D", true, false).size(),
			visual_track.find_children(
					"AuthoredDaySnowShelf", "MeshInstance3D", true, false).size(),
		])
	var pylon_grounded := true
	var pylon_count := 0
	var pylon_grounding_detail := ""
	for value: Node in visual_track.find_children(
			"AuthoredSignalPylons", "MultiMeshInstance3D", true, false):
		var multi := (value as MultiMeshInstance3D).multimesh
		pylon_count += multi.instance_count
		var source_transforms: Array = value.get_meta("authored_source_transforms", [])
		pylon_grounded = pylon_grounded \
				and source_transforms.size() == multi.instance_count
		for index: int in source_transforms.size():
			var transform: Transform3D = source_transforms[index]
			var y := transform.origin.y
			var grounded := absf(y - RunnerTrack.AUTHORED_DAY_KERB_TOP) <= 0.001
			pylon_grounded = pylon_grounded and grounded
			if not grounded and pylon_grounding_detail.is_empty():
				pylon_grounding_detail = "%s[%d] y=%.6f" % [value.name, index, y]
	_check("pylons_seat_on_authored_kerb", pylon_count > 0 and pylon_grounded,
		"instances=%d grounded=%s first=%s" % [
				pylon_count, pylon_grounded, pylon_grounding_detail])
	for asset_id: String in EXPECTED_IDS:
		_check("warmup_%s" % asset_id, ShaderWarmup.has_external_probe(
				visual_track._authored_day_mesh(asset_id),
				visual_track._authored_day_material(false)),
				"exact imported mesh/material pair missing")
	_check("warmup_bounded", ShaderWarmup.external_probe_count()
			<= ShaderWarmup.MAX_EXTERNAL_PROBES,
			"count=%d" % ShaderWarmup.external_probe_count())

	var logic_track := RunnerTrack.new()
	logic_track.name = "LogicTrack"
	add_child(logic_track)
	logic_track.configure_art(art_set, catalog)
	logic_track.setup_golden_slice(SEED, 0)
	_check("gameplay_layout_unchanged", _hazard_snapshot(visual_track) == _hazard_snapshot(logic_track),
			"authored visuals changed hazard transforms")
	visual_track.setup_golden_slice(SEED, 1)
	_check("retry_reuses_complete_kit", bool(visual_track.authored_day_kit_status().get("active", false)),
			str(visual_track.authored_day_kit_status()))

	var normal_track := RunnerTrack.new()
	normal_track.name = "NormalDayTrack"
	add_child(normal_track)
	normal_track.configure_art(art_set, catalog)
	normal_track.setup(SEED, 1.0, 1)
	var normal_ids := _authored_ids(normal_track)
	_check("normal_day_activates_review_kit",
			bool(normal_track.authored_day_kit_status().get("active", false))
			and "runner_day_deck_kerb_v1" in normal_ids,
			"status=%s ids=%s" % [normal_track.authored_day_kit_status(), normal_ids])

	visual_track.queue_free()
	logic_track.queue_free()
	normal_track.queue_free()
	if _failures == 0:
		print("RUNNER_DAY_KIT PASS assets=%d" % EXPECTED_IDS.size())
	else:
		push_error("RUNNER_DAY_KIT FAIL failures=%d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _scene_mesh(scene: PackedScene) -> Mesh:
	var root := scene.instantiate()
	var result := _first_mesh(root)
	root.free()
	return result


func _first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return (node as MeshInstance3D).mesh
	for child: Node in node.get_children():
		var result := _first_mesh(child)
		if result != null:
			return result
	return null


func _triangle_count(mesh: Mesh) -> int:
	return mesh.get_faces().size() / 3


## Counts coincident triangles emitted twice with opposite winding. Imported
## vertices may be split by normal/UV seams, so position keys—not indices—own
## identity. Premium tunnel shell uses one inward inner face and one outward
## outer face; duplicate reverse faces would hide broken winding by adding a
## new two-sided signature and can z-fight under Compatibility.
func _opposite_winding_duplicate_count(mesh: Mesh) -> int:
	if mesh == null:
		return -1
	var duplicates := 0
	for surface: int in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			indices.resize(vertices.size())
			for index: int in vertices.size():
				indices[index] = index
		var seen: Dictionary = {}
		for triangle: int in floori(float(indices.size()) / 3.0):
			var points := PackedStringArray()
			for corner: int in 3:
				var point := vertices[indices[triangle * 3 + corner]]
				points.append("%d,%d,%d" % [roundi(point.x * 10000.0),
						roundi(point.y * 10000.0), roundi(point.z * 10000.0)])
			points.sort()
			var key := "|".join(points)
			if seen.has(key):
				duplicates += 1
			else:
				seen[key] = true
	return duplicates


func _mesh_white_area_ratio(mesh: Mesh) -> float:
	if mesh == null or mesh.get_surface_count() == 0:
		return 1.0
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if vertices.is_empty() or colours.is_empty():
		return 1.0
	var total_area := 0.0
	var white_area := 0.0
	var triangle_indices := indices
	if triangle_indices.is_empty():
		triangle_indices.resize(vertices.size())
		for index: int in vertices.size():
			triangle_indices[index] = index
	for triangle: int in floori(float(triangle_indices.size()) / 3.0):
		var a := triangle_indices[triangle * 3]
		var b := triangle_indices[triangle * 3 + 1]
		var c := triangle_indices[triangle * 3 + 2]
		var area := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).length() * 0.5
		var colour := (colours[a] + colours[b] + colours[c]) / 3.0
		var maximum := maxf(colour.r, maxf(colour.g, colour.b))
		var minimum := minf(colour.r, minf(colour.g, colour.b))
		total_area += area
		if colour.get_luminance() > 0.90 and maximum - minimum < 0.10:
			white_area += area
	return white_area / maxf(total_area, 0.000001)


func _has_warm_window_colour(mesh: Mesh) -> bool:
	if mesh == null or mesh.get_surface_count() == 0:
		return false
	var arrays := mesh.surface_get_arrays(0)
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for colour: Color in colours:
		if colour.r >= 0.82 and colour.g >= 0.42 and colour.g <= 0.72 \
				and colour.b <= 0.32:
			return true
	return false


func _multimesh_instance_count(root: Node, node_name: String) -> int:
	var total := 0
	for value: Node in root.find_children(node_name, "MultiMeshInstance3D", true, false):
		var instance := value as MultiMeshInstance3D
		if instance != null and instance.multimesh != null:
			total += instance.multimesh.instance_count
	return total


func _atlas_sample(image: Image, tile_index: int) -> Color:
	var tile_size := floori(float(image.get_width()) / 4.0)
	var tile_row := floori(float(tile_index) / 4.0)
	var x := (tile_index % 4) * tile_size + floori(float(tile_size) / 2.0)
	var y := tile_row * tile_size + floori(float(tile_size) / 2.0)
	return image.get_pixel(x, y)


func _atlas_value_range(image: Image, tile_index: int) -> float:
	var tile_size := floori(float(image.get_width()) / 4.0)
	var tile_row := floori(float(tile_index) / 4.0)
	var minimum := 1.0
	var maximum := 0.0
	for row: int in 5:
		for column: int in 5:
			var x := (tile_index % 4) * tile_size \
					+ floori(float(tile_size * (column + 1)) / 6.0)
			var y := tile_row * tile_size \
					+ floori(float(tile_size * (row + 1)) / 6.0)
			var value := image.get_pixel(x, y).get_luminance()
			minimum = minf(minimum, value)
			maximum = maxf(maximum, value)
	return maximum - minimum


func _atlas_channel_range(image: Image, tile_index: int, channel: int) -> float:
	var tile_size := floori(float(image.get_width()) / 4.0)
	var tile_row := floori(float(tile_index) / 4.0)
	var minimum := 1.0
	var maximum := 0.0
	for row: int in 7:
		for column: int in 7:
			var x := (tile_index % 4) * tile_size \
					+ floori(float(tile_size * (column + 1)) / 8.0)
			var y := tile_row * tile_size \
					+ floori(float(tile_size * (row + 1)) / 8.0)
			var colour := image.get_pixel(x, y)
			var value: float = [colour.r, colour.g, colour.b][channel]
			minimum = minf(minimum, value)
			maximum = maxf(maximum, value)
	return maximum - minimum


func _authored_ids(root: Node) -> PackedStringArray:
	var found := PackedStringArray()
	_collect_authored_ids(root, found)
	found.sort()
	return found


func _collect_authored_ids(node: Node, found: PackedStringArray) -> void:
	if node.has_meta("authored_asset_id"):
		var asset_id := String(node.get_meta("authored_asset_id"))
		if asset_id not in found:
			found.append(asset_id)
	for child: Node in node.get_children():
		_collect_authored_ids(child, found)


func _hazard_snapshot(root: Node) -> PackedStringArray:
	var rows := PackedStringArray()
	_collect_hazards(root, rows)
	rows.sort()
	return rows


func _collect_hazards(node: Node, rows: PackedStringArray) -> void:
	if node.is_in_group(RunnerConfig.GROUP_HAZARD):
		var spatial := node as Node3D
		if spatial == null:
			_failures += 1
			push_error("  FAIL hazard_not_node3d: %s" % node)
			return
		rows.append("%s|%d|%d|%.3f|%.3f|%.3f" % [
			String(node.get_meta("kind", "")), int(node.get_meta("lane", -1)),
			int(node.get_meta("span", -1)), spatial.global_position.x,
			spatial.global_position.y, spatial.global_position.z,
		])
	for child: Node in node.get_children():
		_collect_hazards(child, rows)


func _check(label: String, passed: bool, detail: String) -> void:
	if passed:
		print("  PASS ", label)
	else:
		_failures += 1
		push_error("  FAIL %s: %s" % [label, detail])
