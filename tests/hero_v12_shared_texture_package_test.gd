extends SceneTree
## Isolated normal-resource-import identity test; no gameplay or save access.

const KINDS := ["albedo", "normal", "orm", "masks"]
const EXPECTED_BYTES := {"albedo": 2796216, "normal": 5592432, "orm": 2796216, "masks": 5592432}
const EXPECTED_FORMATS := {"albedo": 17, "normal": 21, "orm": 17, "masks": 19}
var report: Dictionary = {"passed": false, "production_ready": false, "errors": [], "textures": [], "surfaces": []}

func _initialize() -> void:
	call_deferred("_run")

func _require(condition: bool, message: String) -> void:
	if not condition:
		report.errors.append(message)

func _run() -> void:
	var out_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out_path = argument.trim_prefix("--out=")
	var packed := load("res://atlas/hero_penguin_v12_atlas.glb") as PackedScene
	_require(packed != null, "normal imported PackedScene missing")
	if packed == null:
		_finish(out_path)
		return
	var hero := packed.instantiate()
	root.add_child(hero)
	var textures: Dictionary = {}
	var unique_all: Dictionary = {}
	for kind: String in KINDS:
		var path := "res://atlas/hero_penguin_v12_atlas_%s.png" % kind
		var texture := load(path) as Texture2D
		_require(texture != null, "missing external texture: " + kind)
		if texture == null:
			continue
		textures[kind] = texture
		unique_all[texture.get_instance_id()] = true
		var stored := texture.get_image()
		_require(stored != null, "texture image unavailable: " + kind)
		if stored == null:
			continue
		var entry := {"kind": kind, "path": texture.resource_path, "instance_id": texture.get_instance_id(),
			"compressed": stored.is_compressed(), "format": stored.get_format(),
			"width": stored.get_width(), "height": stored.get_height(),
			"mipmap_count": stored.get_mipmap_count(), "stored_payload_bytes": stored.get_data().size()}
		report.textures.append(entry)
		_require(entry.compressed and entry.width == 2048 and entry.height == 2048 and entry.mipmap_count == 11,
			"expected compressed 2048 mipmapped texture: " + kind)
		_require(entry.stored_payload_bytes == EXPECTED_BYTES[kind] and entry.format == EXPECTED_FORMATS[kind],
			"unexpected actual desktop compressed format/payload: " + kind)
	var unique_pbr: Dictionary = {}
	var surface_count := 0
	var override_ids: Dictionary = {}
	for node: Node in hero.find_children("*", "MeshInstance3D", true, false):
		var visual := node as MeshInstance3D
		_require(visual.mesh.get_blend_shape_count() == 8, "eight species shapes not imported")
		for surface in range(visual.mesh.get_surface_count()):
			var material := visual.mesh.surface_get_material(surface) as BaseMaterial3D
			_require(material != null, "expected normal-import PBR material")
			if material == null:
				continue
			surface_count += 1
			var slots := {"albedo": BaseMaterial3D.TEXTURE_ALBEDO, "normal": BaseMaterial3D.TEXTURE_NORMAL,
				"ao": BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION, "roughness": BaseMaterial3D.TEXTURE_ROUGHNESS,
				"metallic": BaseMaterial3D.TEXTURE_METALLIC}
			var ids: Dictionary = {}
			for slot: String in slots:
				var kind := slot if slot in ["albedo", "normal"] else "orm"
				var actual := material.get_texture(slots[slot])
				_require(actual != null, "missing PBR slot: " + slot)
				if actual == null:
					continue
				unique_pbr[actual.get_instance_id()] = true
				ids[slot] = actual.get_instance_id()
				_require(actual.get_instance_id() == textures[kind].get_instance_id(), "PBR/external resource identity differs: " + slot)
				_require(actual.resource_path == textures[kind].resource_path, "PBR/external path differs: " + slot)
			report.surfaces.append({"material_class": material.get_class(), "texture_ids": ids})
			var override := ShaderMaterial.new()
			override.shader = load("res://hero_v12_atlas_review.gdshader") as Shader
			for kind: String in KINDS:
				override.set_shader_parameter("atlas_" + kind, textures[kind])
				var actual: Texture2D = override.get_shader_parameter("atlas_" + kind)
				override_ids[actual.get_instance_id()] = true
				_require(actual.get_instance_id() == textures[kind].get_instance_id(), "shader external image is duplicated")
			visual.set_surface_override_material(surface, override)
	_require(surface_count == 2, "two material surfaces not preserved")
	_require(unique_pbr.size() == 3 and unique_all.size() == 4 and override_ids.size() == 4,
		"expected exactly three PBR images/four total shared images")
	var pngs: Array[String] = []
	for filename in DirAccess.get_files_at("res://atlas"):
		if filename.ends_with(".png"):
			pngs.append(filename)
	_require(pngs.size() == 4, "normal import extracted duplicate embedded PNGs")
	var dependencies := ResourceLoader.get_dependencies("res://atlas/hero_penguin_v12_atlas.glb")
	var total := 0
	for texture: Dictionary in report.textures:
		total += texture.stored_payload_bytes
	report.merge({"normal_import": "PackedScene", "unique_pbr_texture_instances": unique_pbr.size(),
		"unique_total_texture_instances": unique_all.size(), "unique_override_texture_instances": override_ids.size(),
		"shared_stored_payload_bytes": total, "atlas_png_files": pngs, "dependencies": Array(dependencies),
		"driver_vram_measured": false, "fps_measured": false})
	_require(total == 16777296, "shared texture payload changed")
	hero.queue_free()
	_finish(out_path)

func _finish(out_path: String) -> void:
	report.passed = report.errors.is_empty()
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		push_error("cannot write package import audit")
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	print("[hero-shared-textures] ", "PASS" if report.passed else "FAIL", " ", report.errors)
	quit(0 if report.passed else 1)
