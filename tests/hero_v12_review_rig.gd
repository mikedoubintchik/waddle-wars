extends HeroPenguinRig
## QA-only material seam. All animation/state/cadence/pose code is inherited.
## The isolated wrapper is the only scene that may select this controller.

const QA_CANDIDATE := "res://qa_hero/candidate.glb"
var qa_errors: PackedStringArray = []
var _material_repairs: Array[Dictionary] = []


func _apply_materials(mesh_instance: MeshInstance3D, _palette: Dictionary,
		_identity_color: Color) -> void:
	var identity := String(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	if not identity.begins_with("waddle-v12-runner-review-") \
			or not bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)) \
			or not FileAccess.file_exists("res://qa_hero/candidate_binding.json"):
		_qa_error("QA material controller requires an isolated, bound review project")
		return
	if mesh_instance.mesh == null:
		_qa_error("Candidate mesh missing")
		return
	for surface: int in mesh_instance.mesh.get_surface_count():
		var material := mesh_instance.mesh.surface_get_material(surface) as BaseMaterial3D
		if material == null:
			_qa_error("Candidate requires imported PBR material")
			continue
		if not material.vertex_color_use_as_albedo:
			var arrays := mesh_instance.mesh.surface_get_arrays(surface)
			var colors: Variant = arrays[Mesh.ARRAY_COLOR]
			if not colors is PackedColorArray or colors.is_empty():
				_qa_error("Literal-paint material has no imported COLOR_0")
				continue
			_material_repairs.append({"surface": surface, "material_id": material.get_instance_id(),
				"imported_vertex_color_use_as_albedo": false, "explicit_qa_repair": true})
			material.vertex_color_use_as_albedo = true
		# No semantic recolor or substitute shader: preserve the imported PBR.
		mesh_instance.set_surface_override_material(surface, null)


func _qa_error(message: String) -> void:
	if message not in qa_errors:
		qa_errors.append(message)
		push_error(message)


func qa_material_report() -> Dictionary:
	_ensure_runtime()
	var errors := qa_errors.duplicate()
	var surfaces: Array[Dictionary] = []
	for mesh: MeshInstance3D in _meshes:
		if mesh.mesh == null:
			errors.append("Candidate mesh disappeared after configuration")
			continue
		if mesh.material_override != null:
			errors.append("Candidate has an unexpected global material override")
		if mesh.material_overlay != null:
			errors.append("Unexpected material overlay")
		for surface: int in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			var active := mesh.get_active_material(surface)
			if active != null and active.next_pass != null:
				errors.append("Unexpected additional material pass")
			if material == null or active != material \
					or mesh.get_surface_override_material(surface) != null \
					or not material.vertex_color_use_as_albedo:
				errors.append("Active literal-paint material changed after configuration")
			surfaces.append({"surface": surface, "mesh": mesh.name,
				"material_class": material.get_class() if material != null else "missing",
				"material_id": material.get_instance_id() if material != null else 0,
				"active_material_id": active.get_instance_id() if active != null else 0,
				"global_override_is_null": mesh.material_override == null,
				"override_is_null": mesh.get_surface_override_material(surface) == null,
				"literal_color_enabled": material.vertex_color_use_as_albedo if material != null else false,
				"vertex_color_is_srgb": material.vertex_color_is_srgb if material != null else false,
				"roughness": material.roughness if material != null else -1.0})
	var bound: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://qa_hero/candidate_binding.json"))
	var actual := FileAccess.get_sha256(QA_CANDIDATE)
	var hash_matches := bound is Dictionary and actual == String(bound.get("glb_sha256", ""))
	return {"candidate_sha256": actual, "binding_matches": hash_matches,
		"controller": get_script().resource_path, "inherited_controller": "res://scripts/characters/hero_penguin_rig.gd",
		"inherited_controller_sha256": FileAccess.get_sha256("res://scripts/characters/hero_penguin_rig.gd"),
		"species": _configured_species, "surfaces": surfaces,
		"errors": Array(errors), "production_ready": false, "import_flag_repairs": _material_repairs,
		"passed": errors.is_empty() and hash_matches and surfaces.size() == 2 and _configured_species == "emperor"}


func qa_motion_snapshot() -> Dictionary:
	return preload("res://tests/hero_candidate_motion.gd").snapshot(self)
