class_name AccountDeletionPanel
extends VBoxContainer
## Reusable account deletion disclosure. Service owns credentials and requests;
## this panel only receives public status and an immutable opening identity.

const CONFIRMATION: String = "DELETE_ACCOUNT"
const UNAVAILABLE: String = "Account deletion is not enabled in this pre-release build."
const WARNING: String = "Deleting your account is permanent and cannot be undone. Your cloud profile, leaderboard scores, and cloud save will be removed."
const DEVICE_WARNING: String = "This device's earned offline progress will be kept. Cached purchases linked to the deleted account will be removed from this device."
const RECORD_WARNING: String = "Financial and transaction records may be retained according to the finalized retention policy. Account deletion does not automatically refund purchases."
const NATIVE_DEVICE_WARNING: String = "This device's earned offline progress will be kept."
const NATIVE_RECORD_WARNING: String = "Limited account security markers and deletion receipts are retained to prevent old sessions from restoring deleted data. Identity deletion may remain pending if the sign-in service is unavailable."
const OWNER_CHANGED: String = "The signed-in account changed. Cancel and reopen this panel to review deletion for the current account."
const MIN_TARGET: float = 48.0

## Injectable seam for a synthetic, network-free UI fixture.
var lifecycle_service: Object = null

var _open_button: Button
var _inline_status: Label
var _overlay: Control
var _dialog_card: PanelContainer
var _dialog_scroll: ScrollContainer
var _dialog_status: Label
var _acknowledgment: CheckBox
var _cancel_button: Button
var _delete_button: Button
var _check_button: Button
var _actions: BoxContainer
var _confirmation_context: Dictionary = {}
var _status_owner: String = ""
var _owner_changed: bool = false
var _submitted: bool = false
var _request_locked: bool = false
var _confirmation_open: bool = false
var _fit_pending: bool = false
var _retry_mode: bool = false


func _enter_tree() -> void:
	_connect_sources()
	if _dialog_card != null:
		# Reparenting during a settings rebuild re-enters the tree without a
		# second _ready call. Reconnect now; restore geometry/focus after children.
		_on_viewport_changed.call_deferred()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", UITheme.spacing(10))
	var title := UITheme.make_title("Account deletion", 22)
	add_child(title)
	_inline_status = _paragraph(UNAVAILABLE, 16)
	add_child(_inline_status)
	_open_button = _button("Delete account…")
	_open_button.name = "OpenAccountDeletion"
	_open_button.pressed.connect(open_confirmation)
	add_child(_open_button)
	_build_confirmation()
	_connect_sources()
	_refresh_state()


func _connect_sources() -> void:
	if lifecycle_service == null:
		lifecycle_service = get_node_or_null("/root/AccountLifecycleClient")
	if lifecycle_service != null and lifecycle_service.has_signal("state_changed") \
			and not lifecycle_service.is_connected("state_changed", _on_service_state_changed):
		lifecycle_service.connect("state_changed", _on_service_state_changed)
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_on_viewport_changed):
		viewport.size_changed.connect(_on_viewport_changed)


func _exit_tree() -> void:
	if lifecycle_service != null and is_instance_valid(lifecycle_service) \
			and lifecycle_service.is_connected("state_changed", _on_service_state_changed):
		lifecycle_service.disconnect("state_changed", _on_service_state_changed)
	var viewport := get_viewport()
	if viewport != null and viewport.size_changed.is_connected(_on_viewport_changed):
		viewport.size_changed.disconnect(_on_viewport_changed)


func _build_confirmation() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	_overlay = Control.new()
	_overlay.name = "AccountDeletionConfirmation"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(_overlay)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.01, 0.02, 0.04, 0.88)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(shade)
	_dialog_card = PanelContainer.new()
	_dialog_card.name = "DeletionDialog"
	_dialog_card.add_theme_stylebox_override("panel", UITheme.make_panel_style())
	_overlay.add_child(_dialog_card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", UITheme.spacing(12))
	_dialog_card.add_child(content)
	var title := _paragraph("Delete account", 26, UITheme.COLOR_TEXT)
	content.add_child(title)
	_dialog_scroll = ScrollContainer.new()
	_dialog_scroll.name = "DeletionDisclosureScroll"
	_dialog_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_dialog_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dialog_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dialog_scroll.follow_focus = true
	TouchScroll.attach(_dialog_scroll)
	UtilityScreenLayout.style_scrollbar(_dialog_scroll)
	content.add_child(_dialog_scroll)
	var disclosure := VBoxContainer.new()
	disclosure.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	disclosure.add_theme_constant_override("separation", UITheme.spacing(14))
	_dialog_scroll.add_child(disclosure)
	var native_accounts := GameConfig.native_accounts_enabled()
	for message: String in [WARNING, NATIVE_DEVICE_WARNING if native_accounts else DEVICE_WARNING,
		NATIVE_RECORD_WARNING if native_accounts else RECORD_WARNING]:
		disclosure.add_child(_paragraph(message, 18, UITheme.COLOR_TEXT))
	var acknowledgment_row := HBoxContainer.new()
	acknowledgment_row.add_theme_constant_override("separation", 8)
	disclosure.add_child(acknowledgment_row)
	_acknowledgment = CheckBox.new()
	_acknowledgment.name = "PermanentDeletionAcknowledgment"
	_acknowledgment.custom_minimum_size = Vector2(MIN_TARGET, MIN_TARGET)
	_acknowledgment.tooltip_text = "I understand that account deletion is permanent."
	_acknowledgment.toggled.connect(_on_acknowledgment_toggled)
	acknowledgment_row.add_child(_acknowledgment)
	var acknowledgment_text := _paragraph(
		"I understand that account deletion is permanent.", 18, UITheme.COLOR_TEXT)
	acknowledgment_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	acknowledgment_text.mouse_filter = Control.MOUSE_FILTER_STOP
	acknowledgment_text.gui_input.connect(_on_acknowledgment_label_input)
	acknowledgment_row.add_child(acknowledgment_text)
	_dialog_status = _paragraph(UNAVAILABLE, 16)
	_dialog_status.name = "DeletionStatus"
	disclosure.add_child(_dialog_status)
	_check_button = _button("Check status")
	_check_button.name = "CheckDeletionStatus"
	_check_button.pressed.connect(_on_check_pressed)
	disclosure.add_child(_check_button)
	_actions = BoxContainer.new()
	_actions.add_theme_constant_override("separation", UITheme.spacing(12))
	content.add_child(_actions)
	_cancel_button = _button("Cancel")
	_cancel_button.name = "CancelAccountDeletion"
	_cancel_button.pressed.connect(cancel_confirmation)
	_actions.add_child(_cancel_button)
	_delete_button = _button("Delete account")
	_delete_button.name = "ConfirmAccountDeletion"
	_delete_button.add_theme_color_override("font_color", Color(1.0, 0.72, 0.68))
	_delete_button.pressed.connect(_on_delete_pressed)
	_actions.add_child(_delete_button)
	_overlay.hide()
	_on_viewport_changed()


func _paragraph(message: String, font_size: int,
		color: Color = UITheme.COLOR_TEXT_DIM) -> Label:
	var label := UITheme.make_paragraph(message, font_size, color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _button(caption: String) -> Button:
	var button := UITheme.make_button(caption,
		Vector2(0.0, maxf(MIN_TARGET, UITheme.scaled_size(Vector2(0.0, MIN_TARGET)).y)),
		UITheme.scaled_font(18))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button


func _on_viewport_changed() -> void:
	if _dialog_card == null:
		return
	_apply_dialog_geometry()
	if not _fit_pending and is_inside_tree():
		_fit_pending = true
		get_tree().process_frame.connect(_finish_viewport_fit, CONNECT_ONE_SHOT)
	_refresh_state()


func _finish_viewport_fit() -> void:
	_fit_pending = false
	if not is_inside_tree():
		return
	# Width changes rewrap labels and change container minimums during sorting.
	# Fit again afterward so a stale minimum cannot pin the dialog below safe area.
	_apply_dialog_geometry()
	_refresh_state()


func _apply_dialog_geometry() -> void:
	var profile := LayoutProfile.for_viewport(get_viewport())
	var available := profile.safe_rect.grow(-16.0)
	var card_size := Vector2(minf(720.0, maxf(available.size.x, 1.0)),
		minf(760.0, maxf(available.size.y, 1.0)))
	_actions.vertical = card_size.x < 450.0
	_dialog_card.size = card_size
	_dialog_card.position = available.position + (available.size - card_size) * 0.5


func open_confirmation() -> void:
	if _confirmation_open:
		return
	_confirmation_context = _account_context().duplicate(true)
	_status_owner = _service_status_owner()
	_owner_changed = false
	_retry_mode = _service_can_retry_deletion()
	_submitted = _service_pending() and not _retry_mode
	_request_locked = false
	_acknowledgment.set_pressed_no_signal(false)
	_confirmation_open = true
	_overlay.show()
	_refresh_state()
	_on_viewport_changed()
	_cancel_button.grab_focus()


func cancel_confirmation() -> void:
	if not _confirmation_open or _service_busy():
		return
	_confirmation_open = false
	_confirmation_context.clear()
	_acknowledgment.set_pressed_no_signal(false)
	_overlay.hide()
	_open_button.grab_focus()


## Settings Back, swipe and Escape stop at the open confirmation.
func consume_back() -> bool:
	if not _confirmation_open:
		return false
	cancel_confirmation()
	return true


func is_confirmation_open() -> bool:
	return _confirmation_open


func _input(event: InputEvent) -> void:
	if not _confirmation_open:
		return
	if event.is_action_pressed("ui_cancel"):
		consume_back()
		get_viewport().set_input_as_handled()
		return
	for action: StringName in [&"ui_accept", &"ui_focus_next", &"ui_focus_prev",
			&"ui_up", &"ui_down", &"ui_left", &"ui_right"]:
		if not event.is_action_pressed(action):
			continue
		var focused := get_viewport().gui_get_focus_owner()
		if _service_busy() or focused == null or not _dialog_card.is_ancestor_of(focused):
			if not _cancel_button.disabled:
				_cancel_button.grab_focus()
			get_viewport().set_input_as_handled()
		return


func _on_service_state_changed() -> void:
	_request_locked = false
	_refresh_state()


func _refresh_state() -> void:
	if _inline_status == null:
		return
	var available := _service_can_retry_deletion() if _retry_mode else _service_can_delete()
	var busy := _service_busy()
	var pending := _service_pending()
	var message := _service_status()
	if message.is_empty():
		if pending or _submitted:
			message = "Deletion request started. Completion has not been verified."
		else:
			message = _service_availability_message()
	_inline_status.text = message
	_open_button.disabled = busy
	_open_button.text = "Review deletion request…" if pending else "Delete account…"
	if _confirmation_open and not _same_context(_confirmation_context, _account_context()):
		_owner_changed = true
		_acknowledgment.set_pressed_no_signal(false)
	_dialog_status.text = message + ("\n" + OWNER_CHANGED if _owner_changed else "")
	_acknowledgment.disabled = busy or (pending and not _retry_mode) or _submitted or not available or _owner_changed
	_cancel_button.disabled = busy
	_delete_button.text = "Retry deletion" if _retry_mode else "Delete account"
	_delete_button.disabled = busy or _request_locked or (pending and not _retry_mode) or _submitted \
		or not available or _owner_changed or not _acknowledgment.button_pressed \
		or String(_confirmation_context.get("user_id", "")).is_empty()
	_check_button.visible = pending or _submitted
	# Losing sign-in must invalidate destructive consent, but a status-only
	# receipt may still check this exact opening owner. Never retarget to another.
	_check_button.disabled = busy or _request_locked or _status_owner != _service_status_owner() \
		or not _service_can_check_status()
	_update_focus_paths()


func _on_acknowledgment_toggled(_pressed: bool) -> void:
	_refresh_state()


func _on_acknowledgment_label_input(event: InputEvent) -> void:
	if _acknowledgment.disabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_acknowledgment.button_pressed = not _acknowledgment.button_pressed
		_acknowledgment.accept_event()


func _on_delete_pressed() -> void:
	# Validate again at activation: an owner switch need not wait for a signal,
	# and disabling the button alone does not stop queued/double activation.
	_refresh_state()
	if not _confirmation_open or _delete_button.disabled or lifecycle_service == null:
		return
	_submitted = true
	_request_locked = true
	_acknowledgment.set_pressed_no_signal(false)
	_refresh_state()
	lifecycle_service.call("retry_account_deletion" if _retry_mode else "delete_account",
		CONFIRMATION, _confirmation_context.duplicate(true))
	_refresh_state()


func _on_check_pressed() -> void:
	_refresh_state()
	if not _confirmation_open or _check_button.disabled or lifecycle_service == null:
		return
	_request_locked = true
	_refresh_state()
	lifecycle_service.call("check_status")
	_refresh_state()


func _update_focus_paths() -> void:
	if _cancel_button == null:
		return
	var controls: Array[Control] = []
	for control: BaseButton in [_acknowledgment, _check_button, _cancel_button, _delete_button]:
		if control.visible and not control.disabled:
			controls.append(control)
	for index: int in controls.size():
		var control := controls[index]
		var previous := control.get_path_to(controls[(index - 1 + controls.size()) % controls.size()])
		var next := control.get_path_to(controls[(index + 1) % controls.size()])
		control.focus_previous = previous
		control.focus_next = next
		control.focus_neighbor_left = previous
		control.focus_neighbor_top = previous
		control.focus_neighbor_right = next
		control.focus_neighbor_bottom = next
	if _confirmation_open:
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null and not controls.has(focused) and not _cancel_button.disabled:
			_cancel_button.grab_focus()


func _account_context() -> Dictionary:
	if lifecycle_service == null or not is_instance_valid(lifecycle_service):
		return {}
	var context: Variant = lifecycle_service.call("account_context")
	if not context is Dictionary or String(context.get("user_id", "")).is_empty():
		return {}
	# Retain only the documented non-secret identity fields.
	return {"user_id": String(context.get("user_id", "")),
		"session_epoch": int(context.get("session_epoch", 0))}


func _same_context(left: Dictionary, right: Dictionary) -> bool:
	return String(left.get("user_id", "")) == String(right.get("user_id", "")) \
		and int(left.get("session_epoch", 0)) == int(right.get("session_epoch", 0))


func _service_can_delete() -> bool:
	return lifecycle_service != null and is_instance_valid(lifecycle_service) \
		and bool(lifecycle_service.call("can_delete"))


func _service_can_retry_deletion() -> bool:
	return lifecycle_service != null and is_instance_valid(lifecycle_service) \
		and lifecycle_service.has_method("can_retry_deletion") \
		and bool(lifecycle_service.call("can_retry_deletion"))


func _service_busy() -> bool:
	return lifecycle_service != null and is_instance_valid(lifecycle_service) \
		and bool(lifecycle_service.get("busy"))


func _service_pending() -> bool:
	return lifecycle_service != null and is_instance_valid(lifecycle_service) \
		and bool(lifecycle_service.get("pending"))


func _service_status() -> String:
	return String(lifecycle_service.get("status")) \
		if lifecycle_service != null and is_instance_valid(lifecycle_service) else ""


func _service_availability_message() -> String:
	if lifecycle_service != null and is_instance_valid(lifecycle_service) \
			and lifecycle_service.has_method("availability_message"):
		return String(lifecycle_service.call("availability_message"))
	return "Review what will be removed before deleting your account." \
		if _service_can_delete() else UNAVAILABLE


func _service_can_check_status() -> bool:
	if lifecycle_service != null and is_instance_valid(lifecycle_service) \
			and lifecycle_service.has_method("can_check_status"):
		return bool(lifecycle_service.call("can_check_status"))
	return not _account_context().is_empty()


func _service_status_owner() -> String:
	if lifecycle_service != null and is_instance_valid(lifecycle_service) \
		and lifecycle_service.has_method("status_context"):
		var context: Variant = lifecycle_service.call("status_context")
		return String(context.get("user_id", "")) if context is Dictionary else ""
	return String(_account_context().get("user_id", ""))
