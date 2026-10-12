extends RefCounted
## Candidate selection is scoped to synchronous facade construction. A nearby
## GLB/hash is insufficient: inspect the selected facade and loaded Model too.

const CANDIDATE_PATH := "res://qa_hero/candidate.glb"
const BINDING_PATH := "res://qa_hero/candidate_binding.json"

var errors: PackedStringArray = []
var _previous_backend := false
var _active := false
var _binding: Dictionary = {}
var _binding_sha256 := ""


static func request_errors(identity: String, custom_save: bool, binding: Variant,
		actual_hash: String, backend_disabled: bool) -> PackedStringArray:
	var result: PackedStringArray = []
	var atlas_identity := identity.begins_with("waddle-v12-atlas-runner-review-")
	var literal_identity := identity.begins_with("waddle-v12-runner-review-")
	if not custom_save or not (atlas_identity or literal_identity):
		result.append("Candidate review requires an isolated QA save identity")
	if backend_disabled:
		result.append("Candidate review refuses disabled authored backend")
	if not binding is Dictionary:
		result.append("Candidate binding missing or invalid")
		return result
	if binding.get("schema_version") != 1 or binding.get("production_ready") != false \
			or actual_hash.length() != 64 or binding.get("glb_sha256") != actual_hash:
		result.append("Candidate model/hash binding rejected")
	var mode: String = str(binding.get("material_mode", "literal"))
	if (atlas_identity and mode not in ["atlas", "imported"]) \
			or (literal_identity and mode not in ["literal", "runtime"]):
		result.append("Candidate material mode does not match isolated review route")
	return result


func begin() -> bool:
	if _active:
		fail("Candidate session already active")
		return false
	errors.clear()
	_binding.clear()
	var parsed: Variant = null
	if FileAccess.file_exists(BINDING_PATH):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(BINDING_PATH))
	var identity := String(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	var custom_save := bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false))
	var actual := FileAccess.get_sha256(CANDIDATE_PATH) if FileAccess.file_exists(CANDIDATE_PATH) else ""
	for message: String in request_errors(identity, custom_save, parsed, actual,
			PenguinVisual.disable_authored_backend_for_tests):
		fail(message)
	if not errors.is_empty():
		return false
	_binding = parsed
	_binding_sha256 = FileAccess.get_sha256(BINDING_PATH)
	_previous_backend = PenguinVisual.use_authored_backend_for_qa
	PenguinVisual.use_authored_backend_for_qa = true
	_active = true
	return true


func restore() -> void:
	if _active:
		PenguinVisual.use_authored_backend_for_qa = _previous_backend
		_active = false


func is_active() -> bool:
	return _active


func fail(message: String) -> void:
	if message not in errors:
		errors.append(message)
		push_error(message)


func inspect(facade: PenguinVisual, rig: HeroPenguinRig = null) -> Dictionary:
	if facade == null or not facade.is_authored_backend_active():
		fail("Candidate review selected a procedural fallback")
		return {"passed": false, "errors": Array(errors), "backend": "missing_or_procedural"}
	var active := facade.get_node_or_null("AuthoredHeroPenguin") as HeroPenguinRig
	if rig != null and active != rig:
		fail("Candidate report does not belong to the active facade backend")
	rig = active
	if rig == null or not rig.has_method("qa_material_report"):
		fail("Active candidate has no material contract report")
		return {"passed": false, "errors": Array(errors), "backend": "invalid_authored"}
	var model := rig.get_node_or_null("Model")
	var model_path := model.scene_file_path if model != null else ""
	if model_path != CANDIDATE_PATH:
		fail("Active candidate Model is not the bound GLB")
	if _binding.is_empty() or FileAccess.get_sha256(CANDIDATE_PATH) != _binding.get("glb_sha256"):
		fail("Active candidate binding changed after selection")
	if FileAccess.get_sha256(BINDING_PATH) != _binding_sha256:
		fail("Candidate binding file changed after selection")
	if not rig.missing_contract_items().is_empty():
		fail("Active candidate rig contract incomplete")
	var report: Dictionary = rig.call("qa_material_report")
	if report.get("candidate_sha256") != _binding.get("glb_sha256"):
		fail("Active candidate material report has a different model hash")
	var combined_errors: Array = report.get("errors", []).duplicate()
	combined_errors.append_array(Array(errors))
	report.merge({"backend": "authored_candidate", "active_model_path": model_path,
		"active_backend_path": str(rig.get_path()), "session_errors": Array(errors),
		"qa_opt_in_restored": not _active, "errors": combined_errors}, true)
	report["passed"] = report.get("passed", false) == true and errors.is_empty()
	return report
