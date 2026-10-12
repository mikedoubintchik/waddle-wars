extends HeroPenguinRig
## Integration fixture: inherit production materials AND animation unchanged.
## This never promotes the existing unapproved authored model into production.

const QA_CANDIDATE := "res://qa_hero/candidate.glb"
const MOTION := preload("res://tests/hero_candidate_motion.gd")


func qa_motion_snapshot() -> Dictionary:
	return MOTION.snapshot(self)


func qa_material_report() -> Dictionary:
	_ensure_runtime()
	var errors: Array[String] = []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://qa_hero/candidate_binding.json"))
	var binding: Dictionary = parsed if parsed is Dictionary else {}
	var identity := String(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	if not identity.begins_with("waddle-v12-runner-review-") \
			or not bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)):
		errors.append("Runtime fixture requires isolated review identity")
	var actual := FileAccess.get_sha256(QA_CANDIDATE)
	if binding.get("material_mode") != "runtime" or binding.get("color_contract") != "runtime-semantic-COLOR_0" \
			or actual.is_empty() or actual != binding.get("glb_sha256"):
		errors.append("Canonical runtime binding mismatch")
	var model := get_node_or_null("Model")
	if model == null or model.scene_file_path != QA_CANDIDATE:
		errors.append("Loaded model is not the bound candidate")
	var resources: Dictionary = binding.get("runtime_resources", {})
	if resources.size() != 5:
		errors.append("Runtime material dependencies incomplete")
	for path: String in resources:
		if FileAccess.get_sha256("res://" + path) != resources[path]:
			errors.append("Runtime resource changed: " + path)
	var headless := DisplayServer.get_name() == "headless"
	var surfaces: Array[Dictionary] = []
	for mesh: MeshInstance3D in _meshes:
		if mesh.material_override != null:
			errors.append("Unexpected global material override")
		if mesh.material_overlay != null:
			errors.append("Unexpected material overlay")
		for surface: int in mesh.mesh.get_surface_count():
			var active := mesh.get_active_material(surface)
			if active != null and active.next_pass != null:
				errors.append("Unexpected additional material pass")
			var row := {"mesh": mesh.name, "surface": surface,
				"material_class": active.get_class() if active != null else "missing",
				"shader": "", "maps": {}}
			if headless:
				if active == null or not active is StandardMaterial3D:
					errors.append("Headless structure fixture missing neutral material")
			elif active != MATERIAL_TEMPLATE:
				errors.append("Active material differs from production template")
			else:
				var material := active as ShaderMaterial
				row.shader = material.shader.resource_path
				for kind: String in ["albedo", "normal", "orm"]:
					var texture := material.get_shader_parameter("feather_" + kind) as Texture2D
					var expected := "res://assets/art/characters/textures/hero_penguin_v1_%s.png" % kind
					if texture == null or texture.resource_path != expected:
						errors.append("Active texture mismatch: " + kind)
					row.maps[kind] = texture.resource_path if texture != null else "missing"
			surfaces.append(row)
	return {"candidate_sha256": actual, "binding_matches": errors.is_empty(),
		"controller": get_script().resource_path, "inherited_controller": "res://scripts/characters/hero_penguin_rig.gd",
		"inherited_controller_sha256": FileAccess.get_sha256("res://scripts/characters/hero_penguin_rig.gd"),
		"material_mode": "runtime", "species": _configured_species, "surfaces": surfaces,
		"runtime_resources": resources, "headless": headless, "material_parity_verified": not headless and errors.is_empty(),
		"production_ready": false, "source_fidelity_approved": false,
		"errors": errors, "passed": errors.is_empty() and surfaces.size() == 1 and _configured_species == "emperor"}
