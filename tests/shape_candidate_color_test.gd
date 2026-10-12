extends SceneTree
## Headless resource checks only; no game, viewport, export or capture.

var failures := 0
var passes := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var review := load("res://tools/qa/shape_candidate_browser.gd")
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([
		Color("252b31").srgb_to_linear(), Color("343d44").srgb_to_linear(), Color("d49c4c").srgb_to_linear()])
	var imported := ArrayMesh.new()
	imported.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.9
	imported.surface_set_material(0, material)
	var original := imported.surface_get_arrays(0)
	var other: Dictionary = review.compatibility_color_mesh(imported, "mobile")
	check(other.mesh == imported and other.surfaces.is_empty(), "other renderer unchanged")
	var result: Dictionary = review.compatibility_color_mesh(imported, "gl_compatibility")
	check(result.error.is_empty(), "compatibility conversion accepted")
	check(result.mesh != imported, "private mesh instance")
	check(imported.surface_get_arrays(0) == original, "imported mesh unchanged")
	check(result.mesh.surface_get_material(0) == material, "same imported PBR material")
	var active: Array = result.mesh.surface_get_arrays(0)
	check(active[Mesh.ARRAY_VERTEX] == original[Mesh.ARRAY_VERTEX], "positions preserved")
	check(active[Mesh.ARRAY_NORMAL] == original[Mesh.ARRAY_NORMAL], "normals preserved")
	check(active[Mesh.ARRAY_COLOR] != original[Mesh.ARRAY_COLOR], "encoded colors changed")
	check(result.surfaces[0].linear_roundtrip_max_error <= 0.009, "linear paint roundtrip within RGBA8 precision")
	check(result.surfaces[0].source_mesh_unchanged and result.surfaces[0].material_retained, "receipt proves isolation")
	_test_surface_material(review)
	_test_pickup_overlay(review)
	_test_visual_floor(review)
	print("[shape_candidate_color] %d passed, %d failed" % [passes, failures])
	quit(1 if failures else 0)


func _test_surface_material(review: Script) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var result: Dictionary = review.material_contract_mesh(mesh, "gl_compatibility", "rear-surface-pbr-v1")
	check(result.mesh == mesh and result.surfaces.is_empty() and result.error.is_empty(),
		"PBR maps bypass vertex color conversion without replacing mesh")
	var helper: Node = review.new()
	var material := StandardMaterial3D.new()
	material.roughness = 1.0
	material.metallic = 1.0
	material.normal_enabled = true
	material.normal_scale = 0.6
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var maps := {}
	var slots := {"base_color": BaseMaterial3D.TEXTURE_ALBEDO, "normal": BaseMaterial3D.TEXTURE_NORMAL,
		"metallic_roughness": BaseMaterial3D.TEXTURE_ROUGHNESS}
	for name: String in slots:
		var pixels := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		pixels.fill(Color(0.5, 0.7, 0.0, 1.0) if name == "metallic_roughness" else Color(0.5, 0.5, 1.0, 1.0))
		var base_bytes := pixels.get_data()
		pixels.generate_mipmaps(name == "normal")
		var texture := ImageTexture.create_from_image(pixels)
		material.set_texture(slots[name], texture)
		if name == "metallic_roughness":
			material.set_texture(BaseMaterial3D.TEXTURE_METALLIC, texture)
		var hashing := HashingContext.new()
		hashing.start(HashingContext.HASH_SHA256)
		hashing.update(base_bytes)
		maps[name] = {"width": 2, "height": 2, "rgba8_sha256": hashing.finish().hex_encode(),
			"sha256": "encoded-source", "color_space": "srgb" if name == "base_color" else "linear"}
	helper.set("_binding", {"material_contract": "rear-surface-pbr-v1", "surface_maps": maps,
		"materials": [{"normal_scale": 0.6, "double_sided": true}]})
	check(helper.call("_surface_material_error", material) == "", "three-map imported PBR accepted")
	var receipt: Dictionary = helper.call("_surface_map_receipts", material)
	check(receipt.errors.is_empty() and receipt.maps.size() == 3, "three imported texture pixel hashes match bound source")
	var again: Dictionary = helper.call("_surface_map_receipts", material)
	check(again == receipt and helper.get("_texture_cache").size() == 3, "repeat snapshot reuses texture receipts")
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	check(helper.call("_surface_material_error", material) != "", "wrong roughness channel rejected")
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	var original := material.get_texture(BaseMaterial3D.TEXTURE_ALBEDO)
	material.set_texture(BaseMaterial3D.TEXTURE_ALBEDO, ImageTexture.create_from_image(original.get_image()))
	var replaced: Dictionary = helper.call("_surface_map_receipts", material)
	check(not replaced.errors.is_empty(), "same-pixel replacement texture rejected")
	material.set_texture(BaseMaterial3D.TEXTURE_ALBEDO, original)
	original.emit_signal("changed")
	check(not String(helper.get("_error")).is_empty(), "texture mutation invalidates frozen review")
	helper.free()


func _test_pickup_overlay(review: Script) -> void:
	# Off-tree instances do not boot a game/HUD or create a rendered viewport.
	var helper: Node = review.new()
	var game: Node = load("res://scripts/runner/runner_game.gd").new()
	var hud: Node = load("res://scripts/ui/runner_hud.gd").new()
	game.add_child(hud)
	game.set("hud", hud)
	helper.set("_game", game)
	var shown := TextureRect.new()
	var hidden := TextureRect.new()
	var counter := TextureRect.new()
	hud.add_child(shown)
	hud.add_child(hidden)
	hud.add_child(counter)
	hidden.visible = false
	var saved: Array[Dictionary] = [
		{"node": shown, "path": "pickup/shown", "visible": true, "visible_in_tree": false},
		{"node": hidden, "path": "pickup/hidden", "visible": false, "visible_in_tree": false}]
	helper.set("_pickup_overlay_saved", saved)
	check(helper.call("_set_pickup_overlay_detail", true), "detail overlay policy accepted")
	check(not shown.visible and not hidden.visible and counter.visible, "only saved pickup icons hidden")
	var receipt: Dictionary = helper.call("_pickup_overlay_receipt")
	check(receipt.matched_nodes == 2 and receipt.hidden_nodes == 1 and receipt.visibility_mismatches == 0,
		"overlay receipt counts actual visibility changes")
	check(helper.call("_set_pickup_overlay_detail", false) and shown.visible and not hidden.visible,
		"rear restores mixed original visibility")
	helper.call("_set_pickup_overlay_detail", true)
	helper.call("_restore_pickup_overlay")
	check(shown.visible and not hidden.visible and counter.visible, "exit restores original visibility")
	hidden.free()
	check(not helper.call("_set_pickup_overlay_detail", true) and shown.visible,
		"missing pool node fails before partial visibility mutation")
	helper.free()
	game.free()


func _test_visual_floor(review: Script) -> void:
	var world := Node3D.new()
	var track := Node3D.new()
	world.add_child(track)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(10, 20)
	var floor_node := MeshInstance3D.new()
	floor_node.name = "GlacialIceSkin"
	floor_node.mesh = floor_mesh
	floor_node.position = Vector3(0, 0.022, -34)
	track.add_child(floor_node)
	var other_chunk := Node3D.new()
	track.add_child(other_chunk)
	var far_plane := MeshInstance3D.new()
	far_plane.name = "GlacialIceSkin"
	far_plane.mesh = floor_mesh
	far_plane.position = Vector3(100, 5, -34)
	other_chunk.add_child(far_plane)
	var player := Node3D.new()
	player.position.z = -34
	world.add_child(player)
	var holder := Node3D.new()
	player.add_child(holder)
	var model := Node3D.new()
	holder.add_child(model)
	var mesh_node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.4, 1, 0.4)
	mesh_node.mesh = box
	mesh_node.position.y = 0.5
	model.add_child(mesh_node)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0.84, -30)
	world.add_child(camera)
	var result: Dictionary = review.seat_model_on_visual_floor(track, player, holder, model, camera)
	check(result.error.is_empty(), "visible floor selected without rendering")
	check(is_equal_approx(result.height, 0.022) and result.paths.size() == 1, "disjoint higher plane ignored")
	check(is_equal_approx(result.world_y_offset, 0.022) and is_equal_approx(result.sole_min_after, 0.022),
		"actual model sole seated on visual ice")
	check(result.player_transform_unchanged and result.camera_transform_unchanged, "seating preserves player and camera")
	far_plane.position.x = 0
	var ambiguous: Dictionary = review.visual_floor_at(track, player.position)
	check(not ambiguous.error.is_empty(), "overlapping inconsistent planes rejected")
	world.free()


func check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
	else:
		failures += 1
		push_error("[shape_candidate_color] " + label)
