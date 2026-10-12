extends Node
## Windowed loader-boundary proof. Uses the real SceneRouter UI and transition;
## only the backend request is replaced with an immediate viewport readback.
## Proves a submitted loader frame, not browser compositor presentation, worker
## loading, animation through a synchronous load, or gameplay performance.
## Run through run_frontend_qa.sh loader_boundary to isolate user://.

const TIMEOUT_SECONDS: float = 20.0
const DESTINATION: String = "res://scenes/ui/title.tscn"

class CaptureRouter:
	extends "res://scripts/utilities/scene_router.gd"

	var capture_at_request: Callable

	func _request_threaded_load(scene_path: String) -> void:
		capture_at_request.call(self, scene_path)


var _router: CaptureRouter
var _out: String = ""
var _size: Vector2i = Vector2i(960, 540)
var _finished: bool = false
var _process_serial: int = 0
var _draw_count: int = 0
var _rich_draw_count: int = 0
var _last_rich_draw: Dictionary = {}
var _checks: Array[Dictionary] = []


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.split("=", true, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"out": _out = parts[1].simplify_path()
			"w": _size.x = int(parts[1])
			"h": _size.y = int(parts[1])
	if GameConfig.is_headless():
		print("[loader-boundary] SKIP: actual-window capture requires a rendering device")
		get_tree().quit(0)
		return
	if not _validate_output():
		get_tree().quit(1)
		return
	if _size.x < 240 or _size.y < 240 or _size.x > 4096 or _size.y > 4096:
		push_error("[loader-boundary] FAIL: w/h must be between 240 and 4096")
		get_tree().quit(1)
		return
	# No persistent SettingsManager mutation: resizing exercises production's
	# orientation callback against the harness's isolated default settings.
	DisplayServer.window_set_size(_size)
	DisplayServer.window_move_to_foreground()
	get_tree().process_frame.connect(_on_process_frame)
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)
	get_tree().create_timer(TIMEOUT_SECONDS, true, false, true).timeout.connect(_on_timeout)
	# Let the real window resize and production UI scale settle before creating
	# the inherited router. Do not synthesize rendering signals or loader nodes.
	await get_tree().process_frame
	await get_tree().process_frame
	_router = CaptureRouter.new()
	_router.name = "LoaderBoundaryRouter"
	_router.capture_at_request = _capture_request_entry
	add_child(_router)
	_router.go_to(DESTINATION)


func _validate_output() -> bool:
	var project_path := ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/")
	var user_path := ProjectSettings.globalize_path("user://").simplify_path().trim_suffix("/")
	if _out.is_empty() or not _out.is_absolute_path() or not _out.ends_with(".png") \
			or _out.begins_with("res://") or _out.begins_with("user://") \
			or _out.begins_with(project_path + "/") or _out.begins_with(user_path + "/"):
		push_error("[loader-boundary] FAIL: out must be an absolute .png outside the copied project and user://")
		return false
	if FileAccess.file_exists(_out) or FileAccess.file_exists(_out.get_basename() + ".json"):
		push_error("[loader-boundary] FAIL: choose a fresh PNG/JSON output path")
		return false
	if DirAccess.make_dir_recursive_absolute(_out.get_base_dir()) != OK:
		push_error("[loader-boundary] FAIL: cannot create capture output directory")
		return false
	return true


func _on_process_frame() -> void:
	_process_serial += 1


func _on_frame_post_draw() -> void:
	_draw_count += 1
	if _router == null or _router._loading_mascot == null \
			or _router._loading_backdrop == null:
		return
	if not _router._loading_box.is_visible_in_tree() \
			or not _router._loading_mascot.is_visible_in_tree() \
			or not _router._loading_backdrop.is_visible_in_tree():
		return
	_rich_draw_count += 1
	_last_rich_draw = {
		"draw_count": _draw_count,
		"process_serial": _process_serial,
		"process_frame": Engine.get_process_frames(),
		"time_us": Time.get_ticks_usec(),
		"stage": _router._loading_label.text,
		"progress": _router._loading_mascot.get_progress(),
		"raw_phase_progress": _router._loading_progress.value,
		"fade_alpha": _router._fade_rect.modulate.a,
		"loading_box_alpha": _router._loading_box.modulate.a,
	}


func _capture_request_entry(router: CaptureRouter, scene_path: String) -> void:
	if _finished:
		return
	_finished = true
	var request_us := Time.get_ticks_usec()
	# No await here: this must read the already-submitted viewport exactly where
	# production would enter ResourceLoader.load_threaded_request().
	var image := get_viewport().get_texture().get_image()
	_check(scene_path == DESTINATION, "unchanged destination reaches backend")
	_check(router.is_busy() and router.is_presenting(), "transition guards remain held")
	_check(router._pending_scene_path.is_empty(), "no resource polling armed before request")
	_check(_rich_draw_count >= 1, "actual frame_post_draw observed authored loader")
	_check(not _last_rich_draw.is_empty() \
		and _process_serial > int(_last_rich_draw.get("process_serial", _process_serial)),
		"request enters a process frame after the authored loader draw")
	_check(_last_rich_draw.get("stage", "") == "Packing extra fish…",
		"submitted loader frame uses player-facing loading copy")
	_check(is_equal_approx(float(_last_rich_draw.get("progress", -1.0)),
		router._overall_loading_progress("Packing route assets…", 0.0)),
		"submitted courier fill matches authoritative initial resource phase")
	_check(is_equal_approx(float(_last_rich_draw.get("fade_alpha", 0.0)), 1.0),
		"submitted loading overlay fully opaque")
	_check(is_equal_approx(float(_last_rich_draw.get("loading_box_alpha", 0.0)), 1.0),
		"submitted loading content fully visible")
	_check(router._loading_backdrop is FrontEndBackdrop \
		and router._loading_backdrop.is_visible_in_tree() \
		and FrontEndBackdrop.textures_ready(), "real authored backdrop present and textured")
	_check(router._loading_mascot is PenguinLoader \
		and router._loading_mascot.is_visible_in_tree(), "real loading mascot present and visible")
	var courier: TextureRect = null
	if router._loading_mascot != null:
		courier = router._loading_mascot.get_node_or_null("ExpeditionCourier/CourierArt") as TextureRect
	_check(courier != null and courier.texture != null and courier.is_visible_in_tree() \
		and courier.get_global_rect().has_area(), "real mascot texture has drawable bounds")
	var activity_bar := router._loading_mascot.get_node_or_null("LoadingBar") as Panel \
		if router._loading_mascot != null else null
	_check(activity_bar != null and activity_bar.is_visible_in_tree() \
		and activity_bar.get_global_rect().has_area(), "single activity bar visible")
	_check(router._loading_label.text == "Packing extra fish…" \
		and is_equal_approx(router._loading_mascot.get_progress(),
			router._overall_loading_progress("Packing route assets…", 0.0)),
		"friendly copy and authoritative courier fill retained at request entry")
	_check(image != null and not image.is_empty(), "viewport readback exists at request entry")
	var png_error := ERR_INVALID_DATA
	var actual_size := Vector2i.ZERO
	if image != null and not image.is_empty():
		actual_size = image.get_size()
		_check(actual_size == _size, "capture matches requested window dimensions")
		png_error = image.save_png(_out)
	_check(png_error == OK, "request-entry frame saved without waiting for another draw")
	var report := _base_report()
	report.merge({
		"request_time_us": request_us,
		"request_process_serial": _process_serial,
		"destination": scene_path,
		"actual_image_size": [actual_size.x, actual_size.y],
		"png_error": png_error,
		"backdrop_texture": router._loading_backdrop.selected_texture_path() \
			if router._loading_backdrop != null else "",
		"mascot_texture": PenguinLoader.TEXTURE_PATH,
		"viewport_logical_size": [get_viewport().get_visible_rect().size.x,
			get_viewport().get_visible_rect().size.y],
	})
	_finish_report(report)


func _on_timeout() -> void:
	if _finished:
		return
	_finished = true
	_check(false, "request-entry capture reached within 20 seconds")
	_finish_report(_base_report())


func _base_report() -> Dictionary:
	return {
		"schema_version": 1,
		"kind": "scene_router_loader_request_entry",
		"renderer": RenderingServer.get_current_rendering_method(),
		"display_server": DisplayServer.get_name(),
		"requested_window_size": [_size.x, _size.y],
		"png_path": _out,
		"draw_count": _draw_count,
		"rich_loader_draw_count": _rich_draw_count,
		"last_rich_draw": _last_rich_draw,
		"checks": _checks,
		"limitations": "Actual-window submitted-frame proof only. Does not prove browser compositor presentation, animation through synchronous work, resource-loading performance, or gameplay smoothness.",
	}


func _finish_report(report: Dictionary) -> void:
	var failed := 0
	for check: Dictionary in _checks:
		if not bool(check["passed"]):
			failed += 1
	report["status"] = "PASS" if failed == 0 else "FAIL"
	report["check_count"] = _checks.size()
	report["failed_count"] = failed
	var output := FileAccess.open(_out.get_basename() + ".json", FileAccess.WRITE)
	if output == null:
		push_error("[loader-boundary] FAIL: could not write JSON report")
		get_tree().quit(1)
		return
	output.store_string(JSON.stringify(report, "\t") + "\n")
	output.flush()
	var write_error := output.get_error()
	output.close()
	if write_error != OK:
		push_error("[loader-boundary] FAIL: could not finish JSON report (%d)" % write_error)
		get_tree().quit(1)
		return
	print("[loader-boundary] %s: %d checks, %d failures; %s" % [
		report["status"], _checks.size(), failed, _out])
	get_tree().quit(1 if failed > 0 else 0)


func _check(condition: bool, message: String) -> void:
	_checks.append({"passed": condition, "message": message})
	if not condition:
		push_error("[loader-boundary] FAIL: " + message)
