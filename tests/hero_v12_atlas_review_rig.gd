extends "res://tests/hero_v12_review_rig.gd"
## Quarantined atlas material seam. Motion snapshots and ALL controller code
## remain inherited. The literal COLOR_0 parent hook is never called.

const ATLAS_KINDS := ["albedo", "normal", "orm", "masks"]
const ATLAS_SHADER := "res://tests/shaders/hero_v12_atlas_review.gdshader"
var _atlas_binding: Dictionary = {}
var _candidate_binding: Dictionary = {}
var _atlas_textures: Dictionary = {}
var _atlas_material: ShaderMaterial
var _atlas_checked := false


func _check_atlas_binding() -> bool:
	if _atlas_checked:
		return qa_errors.is_empty()
	_atlas_checked = true
	var identity := String(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	if not identity.begins_with("waddle-v12-atlas-runner-review-") \
			or not bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)):
		_qa_error("Atlas review requires an isolated QA save identity")
		return false
	var candidate: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://qa_hero/candidate_binding.json"))
	var atlas: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://qa_hero/atlas_binding.json"))
	if not candidate is Dictionary or not atlas is Dictionary:
		_qa_error("Atlas/candidate binding missing")
		return false
	_candidate_binding = candidate
	_atlas_binding = atlas
	var actual := FileAccess.get_sha256(QA_CANDIDATE)
	var gate: Variant = atlas.get("projection_gate")
	# JSON numbers are floats in Godot; the host gate also checks exact JSON
	# types before snapshotting. No rejected diagnostic can become a PASS.
	if atlas.get("schema_version") != 1 or atlas.get("uv_contract") != "unique-nonoverlapping-v1" \
			or atlas.get("texture_layout") != "shared-external-v1" \
			or not gate is Dictionary or not gate.get("passed") is bool \
			or gate.get("passed") != true or not gate.get("missing_pixels") is float \
			or gate.get("missing_pixels") != 0.0:
		_qa_error("Atlas projection/layout contract rejected")
		return false
	if actual != atlas.get("glb_sha256") or actual != candidate.get("glb_sha256") \
			or FileAccess.get_sha256("res://qa_hero/atlas_binding.json") != candidate.get("atlas_binding_sha256") \
			or FileAccess.get_sha256(ATLAS_SHADER) != candidate.get("shader_sha256") \
			or candidate.get("production_ready") != false \
			or not candidate.get("material_mode") in ["imported", "atlas"]:
		_qa_error("Atlas candidate/hash binding changed")
		return false
	for kind: String in ATLAS_KINDS:
		var path := "res://qa_hero/hero_penguin_v12_atlas_%s.png" % kind
		if not atlas.get("textures", {}) is Dictionary \
				or FileAccess.get_sha256(path) != atlas.get("textures", {}).get(kind):
			_qa_error("Bound atlas PNG changed: " + kind)
			continue
		var texture := load(path) as Texture2D
		if texture == null:
			_qa_error("Normal-import atlas texture unavailable: " + kind)
			continue
		_atlas_textures[kind] = texture
	if qa_errors.is_empty() and candidate.material_mode == "atlas":
		_atlas_material = ShaderMaterial.new()
		_atlas_material.shader = load(ATLAS_SHADER) as Shader
		for kind: String in ATLAS_KINDS:
			_atlas_material.set_shader_parameter("atlas_" + kind, _atlas_textures[kind])
		_atlas_material.set_shader_parameter("normal_strength", 1.0)
		# No instance palette override: desired/reference shader defaults match
		# exactly, preserving this candidate's baked pigment at ratio one.
	return qa_errors.is_empty()


func _apply_materials(mesh_instance: MeshInstance3D, _palette: Dictionary,
		_identity_color: Color) -> void:
	if not _check_atlas_binding():
		return
	if mesh_instance.mesh == null:
		_qa_error("Atlas candidate mesh missing")
		return
	for surface: int in mesh_instance.mesh.get_surface_count():
		var material := mesh_instance.mesh.surface_get_material(surface) as BaseMaterial3D
		var arrays := mesh_instance.mesh.surface_get_arrays(surface)
		var colors: Variant = arrays[Mesh.ARRAY_COLOR]
		if material == null or material.vertex_color_use_as_albedo \
				or (colors is PackedColorArray and not colors.is_empty()):
			_qa_error("Atlas route requires normal-import PBR without COLOR_0")
			continue
		var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
		if not uvs is PackedVector2Array or uvs.is_empty():
			_qa_error("Unique atlas TEXCOORD_0 missing")
			continue
		var slots := {"albedo": BaseMaterial3D.TEXTURE_ALBEDO, "normal": BaseMaterial3D.TEXTURE_NORMAL,
			"ao": BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION, "roughness": BaseMaterial3D.TEXTURE_ROUGHNESS,
			"metallic": BaseMaterial3D.TEXTURE_METALLIC}
		for slot: String in slots:
			var kind := slot if slot in ["albedo", "normal"] else "orm"
			var actual := material.get_texture(slots[slot])
			var expected: Texture2D = _atlas_textures[kind]
			if actual == null or actual.get_instance_id() != expected.get_instance_id() \
					or actual.resource_path != expected.resource_path:
				_qa_error("Imported PBR does not share bound external texture: " + slot)
		mesh_instance.set_surface_override_material(surface, _atlas_material)


func qa_material_report() -> Dictionary:
	_ensure_runtime()
	_check_atlas_binding()
	var errors := qa_errors.duplicate()
	var surfaces: Array[Dictionary] = []
	var unique_pbr: Dictionary = {}
	for mesh: MeshInstance3D in _meshes:
		if mesh.mesh == null:
			errors.append("Atlas candidate mesh disappeared after configuration")
			continue
		if mesh.material_override != null:
			errors.append("Atlas candidate has an unexpected global material override")
		if mesh.material_overlay != null:
			errors.append("Unexpected material overlay")
		for surface: int in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			var ids: Dictionary = {}
			if material != null:
				for kind: String in ["albedo", "normal", "orm"]:
					var slot := {"albedo": BaseMaterial3D.TEXTURE_ALBEDO, "normal": BaseMaterial3D.TEXTURE_NORMAL,
						"orm": BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION}[kind] as int
					var texture := material.get_texture(slot)
					if texture != null:
						ids[kind] = texture.get_instance_id()
						unique_pbr[texture.get_instance_id()] = true
			var override := mesh.get_surface_override_material(surface)
			var active := mesh.get_active_material(surface)
			if active != null and active.next_pass != null:
				errors.append("Unexpected additional material pass")
			var expected: Material = _atlas_material if _atlas_material != null else material
			if override != _atlas_material or active != expected or expected == null:
				errors.append("Atlas/imported material selection changed after configuration")
			surfaces.append({"surface": surface, "mesh": mesh.name,
				"material_class": material.get_class() if material != null else "missing",
				"material_id": material.get_instance_id() if material != null else 0,
				"active_material_id": active.get_instance_id() if active != null else 0,
				"global_override_is_null": mesh.material_override == null,
				"texture_ids": ids, "vertex_color_enabled": material.vertex_color_use_as_albedo if material != null else false,
				"override_is_null": override == null,
				"override_id": override.get_instance_id() if override != null else 0})
	var textures: Array[Dictionary] = []
	var total := 0
	var unique_all: Dictionary = {}
	for kind: String in _atlas_textures:
		var texture: Texture2D = _atlas_textures[kind]
		unique_all[texture.get_instance_id()] = true
		var stored := texture.get_image()
		if stored == null or not stored.is_compressed() or not stored.has_mipmaps() \
				or stored.get_width() != stored.get_height() or not stored.get_width() in [512, 1024, 2048]:
			errors.append("Expected square compressed mipmapped atlas: " + kind)
			continue
		total += stored.get_data().size()
		textures.append({"kind": kind, "resource_path": texture.resource_path,
			"instance_id": texture.get_instance_id(), "sha256": _atlas_binding.textures[kind],
			"compressed": stored.is_compressed(), "width": stored.get_width(), "height": stored.get_height(),
			"format": stored.get_format(), "mipmap_count": stored.get_mipmap_count(),
			"stored_payload_bytes": stored.get_data().size()})
	var pngs: Array[String] = []
	for filename: String in DirAccess.get_files_at("res://qa_hero"):
		if filename.ends_with(".png"):
			pngs.append(filename)
	if pngs.size() != 4 or unique_all.size() != 4 or unique_pbr.size() != 3:
		errors.append("Atlas texture residency is not exactly four shared external maps")
	if _configured_species != "emperor":
		errors.append("This source-pigment review supports emperor only; no species recolor approval")
	return {"candidate_sha256": FileAccess.get_sha256(QA_CANDIDATE), "binding_matches": errors.is_empty(),
		"candidate_label": _candidate_binding.get("candidate_label", "invalid"),
		"material_mode": _candidate_binding.get("material_mode", "invalid"),
		# The source JSON bytes/hash stay unchanged. Emit the already-validated
		# count as integer JSON, since Godot parses every source number as float.
		"projection_gate": {"passed": _atlas_binding.get("projection_gate", {}).get("passed", false),
			"missing_pixels": int(_atlas_binding.get("projection_gate", {}).get("missing_pixels", -1))},
		"controller": get_script().resource_path, "inherited_controller": "res://scripts/characters/hero_penguin_rig.gd",
		"inherited_controller_sha256": FileAccess.get_sha256("res://scripts/characters/hero_penguin_rig.gd"),
		"shader_sha256": FileAccess.get_sha256(ATLAS_SHADER), "source_pigment_ratio": 1.0,
		"species": _configured_species, "surfaces": surfaces, "textures": textures,
		"unique_pbr_texture_instances": unique_pbr.size(), "unique_total_texture_instances": unique_all.size(),
		"shared_stored_payload_bytes": total, "atlas_png_files": pngs,
		"driver_vram_measured": false, "performance_measured": false,
		"production_ready": false, "source_fidelity_approved": false, "errors": Array(errors),
		"passed": errors.is_empty() and surfaces.size() == 2}
