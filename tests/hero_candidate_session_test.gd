extends Node
## Pure input validation plus scoped selection against a prepared real asset.
## Run in a prepared isolated candidate project to include actual facade checks.

const Session := preload("res://tests/hero_candidate_session.gd")
var _checks := 0
var _failures := 0


func _check(value: bool, label: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		print("[candidate_session] FAIL ", label)


func _ready() -> void:
	var digest := "a".repeat(64)
	var binding := {"schema_version": 1, "production_ready": false, "glb_sha256": digest}
	for mode: String in ["literal", "runtime"]:
		var valid := binding.duplicate()
		valid["material_mode"] = mode
		_check(Session.request_errors("waddle-v12-runner-review-test", true, valid, digest, false).is_empty(),
			"literal route permits " + mode)
	for mode: String in ["atlas", "imported"]:
		var valid := binding.duplicate()
		valid["material_mode"] = mode
		_check(Session.request_errors("waddle-v12-atlas-runner-review-test", true, valid, digest, false).is_empty(),
			"atlas route permits " + mode)
	for invalid: Dictionary in [
		{"identity": "waddle-wars"}, {"custom": false}, {"disabled": true},
		{"hash": ""}, {"hash": "b".repeat(64)}, {"binding": null},
		{"binding": {}}, {"binding": {"schema_version": 1, "production_ready": true, "glb_sha256": digest}},
		{"binding": {"schema_version": 2, "production_ready": false, "glb_sha256": digest}},
		{"binding": {"schema_version": 1, "production_ready": false, "glb_sha256": digest, "material_mode": "atlas"}},
		{"identity": "waddle-v12-atlas-runner-review-test"},
	]:
		var errors := Session.request_errors(invalid.get("identity", "waddle-v12-runner-review-test"),
			invalid.get("custom", true), invalid.get("binding", binding),
			invalid.get("hash", digest), invalid.get("disabled", false))
		_check(not errors.is_empty(), "reject invalid request " + str(invalid))
	if FileAccess.file_exists(Session.BINDING_PATH):
		_test_bound_facade()
	print("[candidate_session] %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _test_bound_facade() -> void:
	var previous := PenguinVisual.use_authored_backend_for_qa
	var session := Session.new()
	if not session.begin():
		_check(false, "bound session starts")
		return
	_check(PenguinVisual.use_authored_backend_for_qa, "construction enables authored selection")
	var facade := PenguinVisual.new()
	add_child(facade)
	facade.setup_look(CharacterLook.from_legacy_config({"species": "emperor"}, CharacterLook.RenderRole.HERO))
	session.restore()
	_check(PenguinVisual.use_authored_backend_for_qa == previous, "construction restores prior backend flag")
	var report := session.inspect(facade)
	_check(report.get("passed", false), "bound model and active materials match")
	_check(report.get("active_model_path") == Session.CANDIDATE_PATH, "loaded scene is the candidate GLB")
	_check(report.get("qa_opt_in_restored", false), "receipt confirms selection scope ended")
	_test_material_guards(facade.get_node_or_null("AuthoredHeroPenguin") as HeroPenguinRig)
	session.restore()
	_check(PenguinVisual.use_authored_backend_for_qa == previous, "repeated restore leaves state unchanged")
	facade.free()


func _test_material_guards(rig: HeroPenguinRig) -> void:
	if rig == null or not rig.has_method("qa_material_report"):
		_check(false, "bound rig supports material guard checks")
		return
	var mesh: MeshInstance3D
	for raw: Node in rig.find_children("*", "MeshInstance3D", true, false):
		var candidate := raw as MeshInstance3D
		if candidate.mesh != null and candidate.mesh.get_surface_count() > 0:
			mesh = candidate
			break
	if mesh == null:
		_check(false, "bound rig has a surface for material guard checks")
		return
	var probe := StandardMaterial3D.new()
	var previous_override := mesh.material_override
	mesh.material_override = probe
	var report: Dictionary = rig.call("qa_material_report")
	_check(not report.get("passed", false) and str(report.get("errors", [])).contains("override"),
		"actual bound material override is rejected")
	mesh.material_override = previous_override
	_check(rig.call("qa_material_report").get("passed", false), "restored material override passes")
	var previous_overlay := mesh.material_overlay
	mesh.material_overlay = probe
	report = rig.call("qa_material_report")
	_check(not report.get("passed", false) and str(report.get("errors", [])).contains("overlay"),
		"actual bound material overlay is rejected")
	mesh.material_overlay = previous_overlay
	_check(rig.call("qa_material_report").get("passed", false), "restored material overlay passes")
	var material := mesh.get_active_material(0)
	if material == null:
		_check(false, "bound surface has an active material")
		return
	var previous_pass := material.next_pass
	material.next_pass = probe
	report = rig.call("qa_material_report")
	_check(not report.get("passed", false) and str(report.get("errors", [])).contains("material pass"),
		"actual bound additional material pass is rejected")
	material.next_pass = previous_pass
	_check(rig.call("qa_material_report").get("passed", false), "restored additional pass passes")
