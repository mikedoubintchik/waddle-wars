@tool
extends EditorScenePostImport
## Surface-only import step. Keep the imported material and exact map texels;
## store the full mip chain losslessly instead of serializing raw image arrays.

func _post_import(scene: Node) -> Object:
	var seen: Dictionary = {}
	for raw: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var instance := raw as MeshInstance3D
		if instance.mesh == null:
			continue
		for surface: int in instance.mesh.get_surface_count():
			var material := instance.mesh.surface_get_material(surface) as StandardMaterial3D
			if material == null:
				push_error("Surface import requires standard PBR")
				return null
			for slot: int in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ROUGHNESS]:
				var texture := material.get_texture(slot) as ImageTexture
				if texture == null:
					push_error("Surface import requires embedded uncompressed maps")
					return null
				var texture_id := texture.get_instance_id()
				if seen.has(texture_id):
					for linked_slot: int in BaseMaterial3D.TEXTURE_MAX:
						if material.get_texture(linked_slot) == texture:
							material.set_texture(linked_slot, seen[texture_id])
					continue
				var image := texture.get_image()
				if image == null or image.is_compressed():
					push_error("Surface import cannot read source map")
					return null
				if image.generate_mipmaps(slot == BaseMaterial3D.TEXTURE_NORMAL) != OK:
					push_error("Surface import mipmap generation failed")
					return null
				var stored := PortableCompressedTexture2D.new()
				stored.keep_compressed_buffer = true
				stored.resource_name = texture.resource_name
				stored.create_from_image(image, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
				var decoded := stored.get_image()
				if decoded == null or decoded.get_format() != image.get_format() \
						or decoded.get_size() != image.get_size() \
						or decoded.get_mipmap_count() != image.get_mipmap_count() \
						or decoded.get_data() != image.get_data():
					push_error("Surface lossless storage changed image or mip pixels")
					return null
				seen[texture_id] = stored
				# Metallic and roughness share one GLTF map. Replace every reference,
				# including metallic, while keeping the imported PBR material itself.
				for linked_slot: int in BaseMaterial3D.TEXTURE_MAX:
					if material.get_texture(linked_slot) == texture:
						material.set_texture(linked_slot, stored)
	return scene
