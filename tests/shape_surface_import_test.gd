extends SceneTree
## Imported-resource verification only. No runner, camera, viewport or captures.
var failures := 0
var passes := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var review := load("res://_qa_local/shape_candidate_browser.gd")
	var helper: Node = review.new()
	var binding: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://qa_shape/candidate_binding.json"))
	helper.set("_binding", binding)
	# A new load of the saved imported scene must prove storage, not an in-memory
	# texture left over from the editor post-import callback.
	var packed := ResourceLoader.load("res://qa_shape/candidate.glb", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	var model := packed.instantiate()
	var records: Array = []
	for raw: Node in model.find_children("*", "MeshInstance3D", true, false):
		var instance := raw as MeshInstance3D
		for surface: int in instance.mesh.get_surface_count():
			var material := instance.mesh.surface_get_material(surface) as StandardMaterial3D
			check(material != null and instance.material_override == null and instance.material_overlay == null,
				"actual imported standard material without substitutes")
			check(helper.call("_surface_material_error", material) == "", "actual imported PBR settings match contract")
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			check(arrays[Mesh.ARRAY_TANGENT] is PackedFloat32Array and not arrays[Mesh.ARRAY_TANGENT].is_empty(), "imported tangent frame exists")
			check(arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array and not arrays[Mesh.ARRAY_TEX_UV].is_empty(), "imported UV0 exists")
			var receipt: Dictionary = helper.call("_surface_map_receipts", material)
			check(receipt.errors.is_empty(), "actual imported PNG pixels and mipmaps match bound source: " + str(receipt.errors))
			var second: Dictionary = helper.call("_surface_map_receipts", material)
			check(receipt == second, "cached imported texture signature remains identical")
			var storage: Array = []
			for slot: int in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ROUGHNESS]:
				var texture := material.get_texture(slot) as PortableCompressedTexture2D
				var exact := texture != null
				if exact:
					var persisted := texture.get_image()
					var regenerated: Image = persisted.duplicate()
					regenerated.clear_mipmaps()
					exact = texture.get_compression_mode() == PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS \
						and regenerated.generate_mipmaps(slot == BaseMaterial3D.TEXTURE_NORMAL) == OK \
						and regenerated.get_format() == persisted.get_format() \
						and regenerated.get_mipmap_count() == persisted.get_mipmap_count() \
						and regenerated.get_data() == persisted.get_data()
					storage.append({"slot": slot, "texture_class": texture.get_class(),
						"compression_mode": texture.get_compression_mode(), "image_format": persisted.get_format(),
						"mipmap_count": persisted.get_mipmap_count(),
						"all_mips_sha256": review._hash(persisted.get_data()), "regenerated_all_mips_identical": exact})
				check(exact, "persisted lossless map and every mip match source-derived pixels, slot " + str(slot))
			records.append({"material": material.resource_name, "filter": material.texture_filter,
				"normal_scale": material.normal_scale, "roughness_channel": material.roughness_texture_channel,
				"metallic_channel": material.metallic_texture_channel,
				"geometry_sha256": review._hash(arrays), "textures": receipt, "storage": storage})
	check(records.size() == int(binding.surface_count), "all source surfaces verified")
	print("SURFACE_IMPORT_RECEIPT " + JSON.stringify({"candidate_sha256": binding.glb_sha256,
		"passes": passes, "failures": failures, "resources": records}))
	model.free()
	helper.free()
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
	else:
		failures += 1
		push_error("[shape_surface_import] " + label)
