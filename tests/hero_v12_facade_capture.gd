extends "res://tests/hero_penguin_capture.gd"
## Reuse the exact existing facade capture, adding bound candidate diagnostics.

var _qa_samples: Array[Dictionary] = []
const CandidateSession := preload("res://tests/hero_candidate_session.gd")
var _candidate_session := CandidateSession.new()
var _candidate_selected := false


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		await super._ready()
		return
	var output := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("output="):
			output = arg.trim_prefix("output=")
	_motion_name = "run"
	_capture_fps = 60
	_build_stage()
	if not _candidate_selected:
		get_tree().quit(2)
		return
	_configure_camera()
	if not _prepare_motion_clock():
		get_tree().quit(2)
		return
	for frame: int in 96:
		_step_motion(1.0 / 60.0)
	var passed := _write_qa_report(output)
	print("[v12-facade] HEADLESS PREFLIGHT ", "PASS" if passed else "FAIL", "; no pixels captured")
	get_tree().quit(0 if passed else 1)


func _build_stage() -> void:
	if not _candidate_session.begin():
		_capture_failed = true
		return
	# Candidate stills must use the same facade as motion and actual gameplay.
	if _motion_name.is_empty() and _cosmetic_config.is_empty():
		_cosmetic_config["species"] = "emperor"
	super._build_stage()
	_candidate_session.restore()
	var report := _candidate_session.inspect(_facade, _hero)
	_candidate_selected = report.get("passed", false) == true
	_capture_failed = not _candidate_selected
	if not _candidate_selected:
		get_tree().quit(2)


func _exit_tree() -> void:
	_candidate_session.restore()


func _configure_camera() -> void:
	if _candidate_selected:
		super._configure_camera()


func _capture_pose(output_dir: String, label: String, pose: int,
		clip: StringName, settle_seconds: float) -> void:
	if not _candidate_selected or not _candidate_session.inspect(_facade, _hero).get("passed", false):
		_capture_failed = true
		return
	await super._capture_pose(output_dir, label, pose, clip, settle_seconds)


func _prepare_motion_clock() -> bool:
	_qa_samples.clear()
	return _candidate_selected and super._prepare_motion_clock()


func _step_motion(delta: float) -> void:
	super._step_motion(delta)
	if _hero != null and _hero.has_method("qa_motion_snapshot"):
		_qa_samples.append(_hero.call("qa_motion_snapshot"))


func _capture_motion(output_dir: String) -> void:
	if not _candidate_selected or not _candidate_session.inspect(_facade, _hero).get("passed", false):
		_capture_failed = true
		return
	await super._capture_motion(output_dir)
	var sequence := output_dir.path_join("hero_penguin_%s_%s_%s%s_%dfps" % [
		_motion_name, _view_name, _orientation_name, _capture_suffix(), _capture_fps])
	var path := sequence.path_join("timeline.json")
	var timeline: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not timeline is Dictionary:
		_capture_failed = true
		return
	timeline["base_capture_live_asset_sha256"] = timeline["asset_sha256"]
	timeline["asset_sha256"] = FileAccess.get_sha256("res://qa_hero/candidate.glb")
	timeline["qa_only"] = true
	timeline["production_ready"] = false
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(timeline, "\t"))
	_capture_failed = not _write_qa_report(output_dir) or _capture_failed


func _write_qa_report(output: String) -> bool:
	var report: Dictionary = _candidate_session.inspect(_facade, _hero)
	var attached := true
	var root_identity := true
	var minimum := INF
	var maximum_support := -INF
	var chest_min := INF
	var chest_max := -INF
	for row: Dictionary in _qa_samples:
		root_identity = root_identity and row.skeleton_root_identity
		# The first capture samples include the real idle->run blend. Feet may
		# settle from idle, so assess attached-foot locomotion after that blend.
		if float(row.clip_time) > 0.15:
			attached = attached and row.feet_local_follow_body
			minimum = minf(minimum, minf(row.left_sole_world_y, row.right_sole_world_y))
			maximum_support = maxf(maximum_support, minf(row.left_sole_world_y, row.right_sole_world_y))
		chest_min = minf(chest_min, row.chest_roll)
		chest_max = maxf(chest_max, row.chest_roll)
	var motion_pass := root_identity and attached and is_finite(minimum) \
		and minimum >= -0.006 and maximum_support <= 0.035 \
		and chest_max - chest_min >= 8.0 and chest_max - chest_min <= 25.0
	report.merge({"fps": _capture_fps, "view": _view_name, "samples": _qa_samples,
		"root_identity": root_identity, "attached_run_feet": attached,
		"minimum_sole_world_y": minimum, "maximum_support_world_y": maximum_support,
		"chest_roll_span": chest_max - chest_min, "motion_pass": motion_pass,
		"headless": DisplayServer.get_name() == "headless", "performance_measured": false})
	report["passed"] = report.passed and motion_pass and _qa_samples.size() > 20
	DirAccess.make_dir_recursive_absolute(output)
	var file := FileAccess.open(output.path_join("candidate_review.json"), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(report, "\t"))
	return bool(report.passed)
