extends Node
## Actual-window capture of production SceneRouter's recovery presentation.
## Run through run_frontend_qa.sh loader_recovery for isolated user://.
## Only the resource-request backend is stalled. The production watchdog is
## polled at its real deadline; drawing, layout, controls and focus are real.
## This is recovery UI QA, not proof of gameplay freezing or performance.

const TIMEOUT_SECONDS: float = 20.0
const DESTINATION: String = "res://scenes/ui/title.tscn"
const MIN_BUTTON_SIZE: float = 44.0

class CaptureRouter:
	extends "res://scripts/utilities/scene_router.gd"

	var request_entered: Callable

	func _request_threaded_load(scene_path: String) -> void:
		# Intentionally leave resource work stalled without changing production
		# presentation, watchdog, layout, focus or recovery methods.
		request_entered.call(self, scene_path)


var _router: CaptureRouter
var _out: String = ""
var _size: Vector2i = Vector2i(540, 960)
var _capture_image_size: Vector2i = Vector2i.ZERO
var _finished: bool = false
var _request_seen: bool = false
var _process_serial: int = 0
var _draw_serial: int = 0
var _loader_draw_count: int = 0
var _recovery_draw_count: int = 0
var _last_loader_draw: Dictionary = {}
var _first_recovery_draw: Dictionary = {}
var _request: Dictionary = {}
var _focus_samples: Array[Dictionary] = []
var _checks: Array[Dictionary] = []


func _ready() -> void:
	if GameConfig.is_headless() and "parse_only=1" in OS.get_cmdline_user_args():
		print("[loader-recovery-parse] PASS: capture scene and autoload references compile; no visual checks run")
		get_tree().quit(0)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.split("=", true, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"out": _out = parts[1].simplify_path()
			"w": _size.x = int(parts[1])
			"h": _size.y = int(parts[1])
	if not _validate_environment():
		get_tree().quit(2)
		return
	# Production SettingsManager owns orientation and content scaling. Do not
	# force a logical viewport size or substitute a layout/safe-area profile.
	DisplayServer.window_set_size(_size)
	DisplayServer.window_move_to_foreground()
	get_tree().process_frame.connect(_on_process_frame)
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)
	get_tree().create_timer(TIMEOUT_SECONDS, true, false, true).timeout.connect(_on_timeout)
	await get_tree().process_frame
	await get_tree().process_frame
	if _finished:
		return
	_router = CaptureRouter.new()
	_router.name = "RecoveryCaptureRouter"
	_router.request_entered = _on_request_entered
	add_child(_router)
	_router.go_to(DESTINATION)


func _validate_environment() -> bool:
	var custom_name := str(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	if not bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)) \
			or not custom_name.begins_with("waddle-wars-frontend-"):
		push_error("[loader-recovery] Run through run_frontend_qa.sh; isolated user:// is required")
		return false
	if GameConfig.is_headless():
		push_error("[loader-recovery] Actual-window capture requires a rendering device; no headless visual pass")
		return false
	if _size.x < 240 or _size.y < 240 or _size.x > 4096 or _size.y > 4096:
		push_error("[loader-recovery] w/h must be between 240 and 4096")
		return false
	var project_path := ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/")
	var user_path := ProjectSettings.globalize_path("user://").simplify_path().trim_suffix("/")
	if _out.is_empty() or not _out.is_absolute_path() or not _out.ends_with(".png") \
			or _out.begins_with(project_path + "/") or _out.begins_with(user_path + "/"):
		push_error("[loader-recovery] out must be an absolute .png outside copied project and user://")
		return false
	if FileAccess.file_exists(_out) or FileAccess.file_exists(_out.get_basename() + ".json"):
		push_error("[loader-recovery] Choose a fresh PNG/JSON output path")
		return false
	if DirAccess.make_dir_recursive_absolute(_out.get_base_dir()) != OK:
		push_error("[loader-recovery] Cannot create capture output directory")
		return false
	return true


func _on_process_frame() -> void:
	_process_serial += 1


func _on_frame_post_draw() -> void:
	_draw_serial += 1
	if _router == null or _finished:
		return
	if _router._recovery_active:
		if _router._loading_recovery.is_visible_in_tree() \
				and _router._fade_rect.is_visible_in_tree():
			_recovery_draw_count += 1
			if _first_recovery_draw.is_empty():
				_first_recovery_draw = _snapshot("first_recovery_post_draw")
		return
	if _router._loading_backdrop != null and _router._loading_mascot != null \
			and _router._loading_backdrop.is_visible_in_tree() \
			and _router._loading_mascot.is_visible_in_tree() \
			and _router._loading_box.is_visible_in_tree():
		_loader_draw_count += 1
		_last_loader_draw = _snapshot("loader_post_draw")


func _on_request_entered(router: CaptureRouter, scene_path: String) -> void:
	if _finished:
		return
	_check(not _request_seen, "only one backend request entered")
	_request_seen = true
	_request = _snapshot("resource_request_entry")
	_request["destination"] = scene_path
	_check(scene_path == DESTINATION, "unchanged destination reaches stalled backend")
	_check(router.is_busy() and router.is_presenting(), "presentation guards held at request entry")
	_check(router._pending_scene_path.is_empty(), "stalled backend did not arm resource polling")
	_check(_loader_draw_count > 0, "real authored loader draw preceded backend request")
	_check(not _last_loader_draw.is_empty() \
			and _process_serial > int(_last_loader_draw.get("process_serial", _process_serial)),
		"backend entered a process frame after authored loader draw")
	var deadline := router._loading_deadline_msec
	_check(deadline > 0, "production armed deadline before backend request")
	if deadline <= 0:
		_finished = true
		_finish_report(_base_report())
		return
	# Use production's armed deadline, never manufacture or reset it here.
	# This checks watchdog boundary/UI, not 30 seconds of wall-clock waiting.
	router._poll_loading_watchdog(deadline - 1)
	_check(not router._recovery_active, "watchdog does not recover before deadline")
	router._poll_loading_watchdog(deadline)
	_check(router._recovery_active, "production watchdog enters recovery at deadline")
	_request["injected_watchdog_now_msec"] = deadline
	_request["recovery_trigger_draw_serial"] = _draw_serial
	_capture_recovery.call_deferred()


func _capture_recovery() -> void:
	# Real layout queues need a process turn before readback. Observe actual
	# RenderingServer submissions only; never force_draw or emit draw signals.
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if _finished:
		return
	_check(_recovery_draw_count > 0, "recovery controls reached actual frame_post_draw")
	_check(int(_first_recovery_draw.get("draw_serial", 0)) \
			> int(_request.get("recovery_trigger_draw_serial", _draw_serial)),
		"recovery draw follows watchdog transition")
	_check_cover_and_gate()
	var profile := LayoutProfile.for_viewport(get_viewport())
	_check_button(_router._retry_button, "Retry", profile)
	_check_button(_router._back_button, "Back", profile)
	_check(_router._retry_button != null and _router._back_button != null \
			and not _router._retry_button.get_global_rect().intersects(_router._back_button.get_global_rect()),
		"Retry and Back hit rectangles do not overlap")
	_check(not _router._loading_progress.is_visible_in_tree(), "recovery hides stale loading progress")
	_check(_router._loading_mascot != null and not _router._loading_mascot.is_visible_in_tree(),
		"recovery hides loading animation")
	_check(get_viewport().gui_get_focus_owner() == _router._retry_button,
		"production recovery gives initial keyboard focus to Retry")
	_focus_samples.append(_snapshot("initial_retry_focus"))
	_send_tab(false)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if _finished:
		return
	_check(get_viewport().gui_get_focus_owner() == _router._back_button,
		"real Tab input reaches Back while tree is paused")
	_focus_samples.append(_snapshot("tab_back_focus"))
	_send_tab(true)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if _finished:
		return
	_check(get_viewport().gui_get_focus_owner() == _router._retry_button,
		"real Shift-Tab input returns to Retry while tree is paused")
	_focus_samples.append(_snapshot("shift_tab_retry_focus"))
	_check_cover_and_gate()
	# This runs immediately after the real post-draw signal; readback does not
	# create an extra draw or substitute a fabricated recovery screenshot.
	var image := get_viewport().get_texture().get_image()
	_check(image != null and not image.is_empty(), "recovery viewport readback exists")
	var actual_size := Vector2i.ZERO
	var png_error := ERR_INVALID_DATA
	if image != null and not image.is_empty():
		actual_size = image.get_size()
		_capture_image_size = actual_size
		_check(actual_size == _size, "recovery PNG matches requested window dimensions")
		png_error = image.save_png(_out)
	_check(png_error == OK, "actual submitted recovery frame saved")
	var report := _base_report()
	report["actual_image_size"] = [actual_size.x, actual_size.y]
	report["png_error"] = png_error
	report["capture_state"] = _snapshot("captured_post_draw")
	_finished = true
	_finish_report(report)


func _send_tab(reverse: bool) -> void:
	# Exercise the real GUI focus path, without clicking either navigation
	# action or directly assigning focus after production's initial grab.
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_TAB
		event.physical_keycode = KEY_TAB
		event.shift_pressed = reverse
		event.pressed = pressed
		Input.parse_input_event(event)


func _check_cover_and_gate() -> void:
	var fade := _router._fade_rect
	var effective_alpha := fade.color.a * fade.modulate.a * fade.self_modulate.a
	_check(fade.is_visible_in_tree() and is_equal_approx(effective_alpha, 1.0),
		"recovery retains fully opaque production cover")
	_check(fade.get_global_rect().encloses(get_viewport().get_visible_rect()),
		"opaque cover encloses whole logical viewport")
	_check(fade.mouse_filter == Control.MOUSE_FILTER_STOP,
		"cover blocks pointer input to underlying scene")
	_check(_router._recovery_active and _router._presenting and _router.is_busy(),
		"recovery keeps presentation gate held")
	_check(get_tree().paused, "production recovery pauses scene tree")
	_check(_router.process_mode == Node.PROCESS_MODE_ALWAYS and _router.can_process(),
		"recovery router remains processable while paused")


func _check_button(button: Button, label: String, profile: LayoutProfile) -> void:
	_check(button != null, label + " is a real production Button")
	if button == null:
		return
	var rect := button.get_global_rect()
	_check(button.is_visible_in_tree() and not button.disabled and button.can_process(),
		label + " remains visible, enabled and processable while paused")
	_check(button.focus_mode == Control.FOCUS_ALL, label + " accepts keyboard focus")
	_check(rect.size.x >= MIN_BUTTON_SIZE and rect.size.y >= MIN_BUTTON_SIZE,
		label + " hit area is at least 44 logical units on both axes")
	_check(profile.contains_safe_rect(rect), label + " lies inside production safe rectangle")
	var window_rect := _scaled_rect(rect, Vector2(get_window().size))
	_check(window_rect.size.x >= MIN_BUTTON_SIZE and window_rect.size.y >= MIN_BUTTON_SIZE,
		label + " hit area is at least 44 window-client coordinate pixels on both axes")


func _scaled_rect(rect: Rect2, output_size: Vector2) -> Rect2:
	var view := get_viewport().get_visible_rect()
	var output_scale := Vector2(output_size.x / maxf(view.size.x, 1.0),
		output_size.y / maxf(view.size.y, 1.0))
	return Rect2((rect.position - view.position) * output_scale, rect.size * output_scale)


func _rect_data(rect: Rect2) -> Dictionary:
	return {"x": rect.position.x, "y": rect.position.y,
		"width": rect.size.x, "height": rect.size.y}


func _button_data(button: Button) -> Dictionary:
	if button == null:
		return {"present": false}
	return {
		"present": true, "class": button.get_class(), "text": button.text,
		"rect_logical": _rect_data(button.get_global_rect()),
		"rect_window_client_pixels": _rect_data(_scaled_rect(button.get_global_rect(), Vector2(get_window().size))),
		"rect_image_pixels": _rect_data(_scaled_rect(button.get_global_rect(), Vector2(_capture_image_size))) \
			if _capture_image_size != Vector2i.ZERO else null,
		"visible": button.is_visible_in_tree(), "disabled": button.disabled,
		"can_process": button.can_process(), "focus_mode": button.focus_mode,
		"has_focus": button.has_focus(),
	}


func _snapshot(phase: String) -> Dictionary:
	var profile := LayoutProfile.for_viewport(get_viewport())
	var focus := get_viewport().gui_get_focus_owner()
	return {
		"phase": phase, "time_us": Time.get_ticks_usec(),
		"process_serial": _process_serial, "draw_serial": _draw_serial,
		"process_frame": Engine.get_process_frames(), "tree_paused": get_tree().paused,
		"presenting": _router._presenting, "busy": _router.is_busy(),
		"recovery_active": _router._recovery_active,
		"loading_deadline_msec": _router._loading_deadline_msec,
		"fade_visible": _router._fade_rect.is_visible_in_tree(),
		"fade_alpha": _router._fade_rect.modulate.a,
		"fade_color_alpha": _router._fade_rect.color.a,
		"fade_rect_logical": _rect_data(_router._fade_rect.get_global_rect()),
		"loading_box_alpha": _router._loading_box.modulate.a,
		"stage": _router._loading_label.text,
		"safe_rect_logical": _rect_data(profile.safe_rect),
		"layout_class": profile.class_name_text(),
		"viewport_logical_rect": _rect_data(get_viewport().get_visible_rect()),
		"window_client_size": [get_window().size.x, get_window().size.y],
		"focus_owner_path": str(focus.get_path()) if focus != null else "",
		"retry": _button_data(_router._retry_button),
		"back": _button_data(_router._back_button),
	}


func _on_timeout() -> void:
	if _finished:
		return
	_finished = true
	_check(false, "actual recovery frame captured within 20 seconds")
	_finish_report(_base_report())


func _base_report() -> Dictionary:
	return {
		"schema_version": 1, "kind": "scene_router_recovery_actual_window",
		"renderer": RenderingServer.get_current_rendering_method(),
		"display_server": DisplayServer.get_name(),
		"requested_window_size": [_size.x, _size.y], "png_path": _out,
		"isolated_user_name": ProjectSettings.get_setting("application/config/custom_user_dir_name", ""),
		"draw_count": _draw_serial, "loader_draw_count": _loader_draw_count,
		"recovery_draw_count": _recovery_draw_count,
		"last_loader_draw": _last_loader_draw, "request_entry": _request,
		"first_recovery_draw": _first_recovery_draw, "focus_samples": _focus_samples,
		"checks": _checks,
		"size_metric": "Minimum44 uses window-client coordinate pixels = logical size * Window.size / viewport visible size. Image-pixel bounds use actual readback dimensions and remain null before readback. Neither metric is asserted to be browser CSS pixels or device pixels.",
		"limitations": "Actual native-window submitted-frame/layout/focus proof. Resource request deliberately stalled; watchdog now injected at production's armed deadline, not wall-clock elapsed. Underlying scene is this harness, not gameplay. Does not prove gameplay freezing, Retry/Back navigation completion, browser compositor presentation, phone CSS-point target sizing, or performance. Scaled rects assume production canvas_items expand scaling without letterboxing.",
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
		push_error("[loader-recovery] Could not write JSON report")
		get_tree().quit(1)
		return
	output.store_string(JSON.stringify(report, "\t") + "\n")
	output.flush()
	var write_error := output.get_error()
	output.close()
	if write_error != OK:
		push_error("[loader-recovery] Could not finish JSON report (%d)" % write_error)
		get_tree().quit(1)
		return
	print("[loader-recovery] %s: %d checks, %d failures; %s" % [
		report["status"], _checks.size(), failed, _out])
	get_tree().quit(1 if failed > 0 else 0)


func _check(condition: bool, message: String) -> void:
	_checks.append({"passed": condition, "message": message})
	if not condition:
		push_error("[loader-recovery] FAIL: " + message)
