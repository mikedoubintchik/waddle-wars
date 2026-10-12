extends Node
## Actual-window settings/account deletion proof with a synthetic disabled
## service. Run through run_frontend_qa.sh account_deletion only. This never
## signs in, submits deletion, calls billing, or writes a real user's saves.

const SETTINGS_SCENE: String = "res://scenes/menus/settings.tscn"
const TIMEOUT_SECONDS: float = 25.0
## Scroll offsets are integers while themed margins retain fractional pixels.
const SCROLL_EDGE_EPSILON: float = 1.0

class LifecycleFixture extends Node:
	signal state_changed
	var busy: bool = false
	var pending: bool = false
	var status: String = ""
	var deletion_calls: int = 0
	var check_calls: int = 0
	func account_context() -> Dictionary:
		return {}
	func can_delete() -> bool:
		return false
	func can_check_status() -> bool:
		return false
	func availability_message() -> String:
		return AccountDeletionPanel.UNAVAILABLE
	func delete_account(_confirmation: String, _expected_context: Dictionary) -> void:
		# Record accidental activation; never call a real service.
		deletion_calls += 1
	func check_status() -> void:
		check_calls += 1

var _out: String = ""
var _size: Vector2i = Vector2i(390, 844)
var _ui_scale: float = 1.0
var _wait: float = 1.2
var _touch: bool = true
var _service: LifecycleFixture
var _panel: AccountDeletionPanel
var _settings_screen: Control
var _checks: Array[Dictionary] = []
var _finished: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for argument: String in OS.get_cmdline_user_args():
		var parts := argument.split("=", true, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"out": _out = parts[1].simplify_path()
			"w": _size.x = int(parts[1])
			"h": _size.y = int(parts[1])
			"ui_scale": _ui_scale = float(parts[1])
			"wait": _wait = float(parts[1])
			"touch": _touch = parts[1].to_lower() in ["1", "true", "yes"]
	if not _validate_environment():
		get_tree().quit(2)
		return
	get_tree().create_timer(TIMEOUT_SECONDS, true, false, true).timeout.connect(_on_timeout)
	# In-memory settings only, inside the harness's unique user:// identity.
	GameConfig.force_touch = _touch
	LayoutProfile.forced_insets = Vector4(24.0, 24.0, 24.0, 24.0)
	var display: Dictionary = SettingsManager.settings.get("display", {}).duplicate(true)
	display["window_mode"] = "windowed"
	display["resolution"] = "%dx%d" % [_size.x, _size.y]
	SettingsManager.settings["display"] = display
	var accessibility: Dictionary = SettingsManager.settings.get("accessibility", {}).duplicate(true)
	accessibility["ui_scale"] = _ui_scale
	accessibility["reduced_flashing"] = true
	SettingsManager.settings["accessibility"] = accessibility
	SettingsManager.apply_all()
	DisplayServer.window_set_size(_size)
	DisplayServer.window_move_to_foreground()
	await _settle()
	_service = LifecycleFixture.new()
	add_child(_service)
	_panel = AccountDeletionPanel.new()
	_panel.lifecycle_service = _service
	var packed := load(SETTINGS_SCENE) as PackedScene
	if packed == null:
		_fail("Could not load the actual Settings scene.")
		return
	_settings_screen = packed.instantiate() as Control
	_settings_screen.add_child(_panel)
	_settings_screen.set("_account_deletion_panel", _panel)
	add_child(_settings_screen)
	await _settle()
	_settings_screen.call("_jump_to", "online")
	await get_tree().create_timer(_wait, true, false, true).timeout
	await _settle()
	var settings_scroll: ScrollContainer = _settings_screen.get("_scroll")
	settings_scroll.ensure_control_visible(_panel._open_button)
	await _settle()
	var settings_state := _settings_snapshot()
	var settings_png := await _save_frame(_settings_path())
	_panel.open_confirmation()
	await _settle()
	await get_tree().create_timer(0.25, true, false, true).timeout
	var modal_png := await _save_frame(_out)
	var modal_state := _modal_snapshot()
	_record("settings_reached_online_account_card",
		bool(settings_state["open_button_reachable"]))
	var reference_area := Rect2(0.0, 0.0, 100.0, 100.0)
	_record("scroll_edge_rounding_tolerance", _scroll_contains(reference_area,
		Rect2(0.0, 90.12, 100.0, 10.0)))
	_record("scroll_edge_rejects_larger_clipping", not _scroll_contains(reference_area,
		Rect2(0.0, 91.01, 100.0, 10.0)) and not _scroll_contains(reference_area,
		Rect2(91.01, 0.0, 10.0, 100.0)))
	_record("modal_open", _panel.is_confirmation_open())
	_record("disabled_gate", _panel._delete_button.disabled and _panel._acknowledgment.disabled)
	_record("pre_release_status_explicit", _panel._dialog_status.text == AccountDeletionPanel.UNAVAILABLE)
	_record("cancel_initial_focus", get_viewport().gui_get_focus_owner() == _panel._cancel_button)
	_record("modal_within_safe_area", bool(modal_state["card_inside_safe_area"]))
	_record("actions_within_safe_area", bool(modal_state["actions_inside_safe_area"]))
	_record("touch_targets_at_least_48", bool(modal_state["minimum_targets_met"]))
	_record("no_account_or_billing_actions", _service.deletion_calls == 0 and _service.check_calls == 0
		and not LeaderboardClient.signed_in and not NativeAuthClient.signed_in())
	_record("settings_png_saved", int(settings_png["error"]) == OK)
	_record("modal_png_saved", int(modal_png["error"]) == OK)
	var report := {
		"fixture": "actual_settings_with_synthetic_disabled_account_lifecycle",
		"rendered": int(settings_png["error"]) == OK and int(modal_png["error"]) == OK,
		"isolated_user_dir": String(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")),
		"requested_window_size": [_size.x, _size.y],
		"actual_window_size": [get_window().size.x, get_window().size.y],
		"logical_viewport_size": [get_viewport_rect_size().x, get_viewport_rect_size().y],
		"ui_scale": _ui_scale, "touch_metrics": _touch,
		"settings": settings_state, "modal": modal_state,
		"captures": {"settings": settings_png, "modal": modal_png},
		"checks": _checks,
		"synthetic_deletion_calls": _service.deletion_calls,
		"synthetic_status_calls": _service.check_calls,
		"fixture_authentication_actions": 0,
		"actual_auth_signed_in": LeaderboardClient.signed_in or NativeAuthClient.signed_in(),
	}
	var report_error := _write_report(report)
	var failures := 0
	for check: Dictionary in _checks:
		if not bool(check["passed"]):
			failures += 1
	_finished = true
	print("[account-deletion-capture] %s: %d checks, %d failed; JSON err=%d" % [
		_out, _checks.size(), failures, report_error])
	get_tree().quit(0 if failures == 0 and report_error == OK else 1)


func _validate_environment() -> bool:
	var custom_name := String(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	if not bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)) \
			or not custom_name.begins_with("waddle-wars-frontend-"):
		push_error("[account-deletion-capture] Use run_frontend_qa.sh account_deletion; isolated user:// is required.")
		return false
	if GameConfig.is_headless():
		push_error("[account-deletion-capture] A rendering device is required; no headless visual pass.")
		return false
	if _size.x < 240 or _size.y < 240 or _size.x > 4096 or _size.y > 4096 \
			or not is_finite(_ui_scale) or _ui_scale < 0.8 or _ui_scale > 1.4 \
			or not is_finite(_wait) or _wait < 0.2 or _wait > 5.0:
		push_error("[account-deletion-capture] Require w/h 240..4096, ui_scale 0.8..1.4, wait 0.2..5.")
		return false
	var project_path := ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/")
	var user_path := ProjectSettings.globalize_path("user://").simplify_path().trim_suffix("/")
	if _out.is_empty() or not _out.is_absolute_path() or not _out.ends_with(".png") \
			or _out.begins_with(project_path + "/") or _out.begins_with(user_path + "/"):
		push_error("[account-deletion-capture] out must be an absolute .png outside copied project and user://.")
		return false
	for path: String in [_out, _settings_path(), _out.get_basename() + ".json"]:
		if FileAccess.file_exists(path):
			push_error("[account-deletion-capture] Choose a fresh output prefix; file exists: " + path)
			return false
	if DirAccess.make_dir_recursive_absolute(_out.get_base_dir()) != OK:
		push_error("[account-deletion-capture] Cannot create output directory.")
		return false
	return true


func _settle() -> void:
	for _frame: int in 4:
		await get_tree().process_frame


func _settings_path() -> String:
	return _out.get_basename() + "_settings.png"


func get_viewport_rect_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func _rect(rectangle: Rect2) -> Dictionary:
	return {"x": rectangle.position.x, "y": rectangle.position.y,
		"width": rectangle.size.x, "height": rectangle.size.y}


func _settings_snapshot() -> Dictionary:
	var scroll: ScrollContainer = _settings_screen.get("_scroll")
	var button_rect := _panel._open_button.get_global_rect()
	var visible_area := scroll.get_global_rect()
	return {"scene_path": SETTINGS_SCENE, "scroll_vertical": scroll.scroll_vertical,
		"viewport": _rect(visible_area), "open_button": _rect(button_rect),
		"open_button_reachable": _scroll_contains(visible_area, button_rect),
		"scroll_edge_epsilon_logical_px": SCROLL_EDGE_EPSILON,
		"button_bottom_overflow_logical_px": maxf(0.0, button_rect.end.y - visible_area.end.y),
		"inline_status": _panel._inline_status.text,
		"account_status": String((_settings_screen.get("_account_status_label") as Label).text)}


func _scroll_contains(viewport_rect: Rect2, button_rect: Rect2) -> bool:
	return viewport_rect.grow(SCROLL_EDGE_EPSILON).encloses(button_rect)


func _modal_snapshot() -> Dictionary:
	var profile := LayoutProfile.for_viewport(get_viewport())
	var card := _panel._dialog_card.get_global_rect()
	var cancel := _panel._cancel_button.get_global_rect()
	var deletion := _panel._delete_button.get_global_rect()
	var scrollbar := _panel._dialog_scroll.get_v_scroll_bar()
	return {"safe_area": _rect(profile.safe_rect), "layout_class": String(profile.class_name_text()),
		"card": _rect(card), "cancel_button": _rect(cancel), "delete_button": _rect(deletion),
		"disclosure_viewport": _rect(_panel._dialog_scroll.get_global_rect()),
		"disclosure_scroll_max": scrollbar.max_value, "disclosure_scroll_page": scrollbar.page,
		"disclosure_scrollable": scrollbar.max_value > scrollbar.page,
		"card_inside_safe_area": profile.contains_safe_rect(card, 1.0),
		"actions_inside_safe_area": profile.contains_safe_rect(cancel, 1.0)
			and profile.contains_safe_rect(deletion, 1.0),
		"minimum_targets_met": cancel.size.y >= 48.0 and deletion.size.y >= 48.0
			and _panel._acknowledgment.size.y >= 48.0,
		"status": _panel._dialog_status.text, "acknowledgment_checked": _panel._acknowledgment.button_pressed,
		"delete_disabled": _panel._delete_button.disabled,
		"warnings": [AccountDeletionPanel.WARNING, AccountDeletionPanel.DEVICE_WARNING,
			AccountDeletionPanel.RECORD_WARNING]}


func _save_frame(path: String) -> Dictionary:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		push_error("[account-deletion-capture] Rendered image is empty: " + path)
		return {"path": path, "error": ERR_CANT_CREATE, "width": 0, "height": 0}
	var error := image.save_png(path)
	if error != OK:
		push_error("[account-deletion-capture] PNG write failed err=%d: %s" % [error, path])
	return {"path": path, "error": error, "width": image.get_width(), "height": image.get_height()}


func _write_report(report: Dictionary) -> Error:
	var path := _out.get_basename() + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var error := FileAccess.get_open_error()
		push_error("[account-deletion-capture] JSON open failed err=%d: %s" % [error, path])
		return error
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		push_error("[account-deletion-capture] JSON write failed err=%d: %s" % [error, path])
	return error


func _record(label: String, passed: bool) -> void:
	_checks.append({"name": label, "passed": passed})
	print("[account-deletion-capture] %s %s" % ["PASS" if passed else "FAIL", label])


func _fail(message: String) -> void:
	_finished = true
	push_error("[account-deletion-capture] " + message)
	get_tree().quit(1)


func _on_timeout() -> void:
	if not _finished:
		_fail("Timed out before a complete rendered capture and JSON report.")
