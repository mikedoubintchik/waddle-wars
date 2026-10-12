extends Node
## Tests actual imported trail art, shared particle/material contracts, and
## reference-driven cosmetic attachments. No account or save writes.

var checks: Array[Dictionary] = []

func _ready() -> void:
	if not String(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("waddle-wars-equipment-"):
		push_error("Equipment art fixture requires isolated waddle-wars-equipment-* user data")
		get_tree().quit(2)
		return
	_run.call_deferred()

func _run() -> void:
	for id: String in CosmeticsDB.items_in_category("trail"):
		var texture := TrailEffect._particle_texture(id)
		check(texture != null and texture.resource_path == TrailEffect.PARTICLE_PATHS[id], id + ": exact registered texture loaded")
		if texture == null:
			continue
		var pixels := texture.get_image()
		check(pixels != null and pixels.get_size() == Vector2i(256, 256) and pixels.has_mipmaps(), id + ": bounded imported pixels and mipmaps")
		check(pixels.get_pixel(0, 0).a < 0.01 and pixels.get_pixel(128, 128).a > 0.2, id + ": transparent corners and visible subject")
		var trail := TrailEffect.create(id)
		check(trail != null and trail.amount == 30 and is_equal_approx(trail.lifetime, 1.05), id + ": gameplay particle budget unchanged")
		var material := trail.draw_pass_1.material as StandardMaterial3D
		var process := trail.process_material as ParticleProcessMaterial
		check(material.albedo_texture == texture and material.albedo_color == Color.WHITE and material.vertex_color_use_as_albedo, id + ": gameplay uses exact art with one neutral modulation")
		var neutral_fade := process.color_ramp != null
		if neutral_fade:
			for tint: Color in process.color_ramp.gradient.colors:
				neutral_fade = neutral_fade and tint.r == 1.0 and tint.g == 1.0 and tint.b == 1.0
		check(process.color.r == 1.0 and process.color.g == 1.0 and process.color.b == 1.0 and neutral_fade and process.hue_variation_min == 0.0 and process.hue_variation_max == 0.0, id + ": preserved authored palette through alpha-only lifetime fade")
		var quad := trail.draw_pass_1 as QuadMesh
		check(is_equal_approx(quad.size.x, quad.size.y), id + ": square transparent canvas retains aspect")
		trail.free()
	check(TrailEffect.create("") == null and TrailEffect.create("invalid") == null, "clear and invalid trail IDs create no emitter")
	check(TrailEffect._particle_textures.size() == 4, "trail cache bounded to four catalog textures")
	for id: String in ["hat_beanie", "scarf_red", "scarf_rainbow"]:
		var visual := PenguinVisual.new()
		add_child(visual)
		visual.setup({"species": "emperor", "hat": id if id == "hat_beanie" else "", "scarf": id if id.begins_with("scarf_") else ""})
		if id == "hat_beanie":
			var pom := visual.find_child("BeaniePom", true, false) as MeshInstance3D
			check(pom != null and (pom.material_override as StandardMaterial3D).albedo_color == (CosmeticsDB.get_item(id)["color"] as Color).lightened(0.08), "beanie pom matches reference red yarn")
		else:
			var left := visual.find_child("ScarfTailLeft", true, false) as MeshInstance3D
			var right := visual.find_child("ScarfTailRight", true, false) as MeshInstance3D
			check(left != null and right != null and left.mesh == right.mesh, id + ": two reference scarf ends share mesh")
			if id == "scarf_rainbow":
				var collar := visual.find_child("ScarfCollar", true, false) as MeshInstance3D
				var tail_texture := (left.material_override as StandardMaterial3D).albedo_texture as GradientTexture2D
				var neck_texture := (collar.material_override as StandardMaterial3D).albedo_texture as GradientTexture2D
				check(tail_texture.gradient.get_point_count() == 6 and neck_texture.gradient.colors == tail_texture.gradient.colors, "rainbow scarf keeps all six reference colors on collar and both ends")
				check(tail_texture.fill_to == Vector2.DOWN and neck_texture.fill_to == Vector2.RIGHT, "scarf bands follow tail and collar UV directions")
		visual.free()
	var passed := checks.filter(func(row: Dictionary) -> bool: return row.passed).size()
	var output := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="): output = arg.trim_prefix("out=")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file := FileAccess.open(output.path_join("equipment-art.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"passed": passed, "total": checks.size(), "checks": checks, "limits": "Headless decoded resources/materials only; actual Chrome appearance remains separate."}, "\t"))
	print("[equipment-art] %d/%d passed" % [passed, checks.size()])
	get_tree().quit(0 if passed == checks.size() else 1)

func check(passed: bool, description: String) -> void:
	checks.append({"passed": passed, "description": description})
	if not passed: push_error(description)
