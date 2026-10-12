extends "res://tests/hero_v12_runner_capture.gd"
## Same real RunnerGame, camera, controls, capture and teardown. QA title only.

func _ready() -> void:
	super._ready()
	var binding: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://qa_hero/candidate_binding.json"))
	if binding is Dictionary:
		DisplayServer.window_set_title("Waddle Wars — QA %s / %s (unapproved)" % [
			binding.get("candidate_label", "atlas"), binding.get("material_mode", "invalid")])
