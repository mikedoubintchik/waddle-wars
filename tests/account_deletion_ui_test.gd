extends Node
## Synthetic service and private SubViewport only. No auth, HTTP, browser,
## credentials, billing calls, or save mutations are part of this UI fixture.

const PanelScript = preload("res://scripts/ui/account_deletion_panel.gd")

class SettingsFixture:
	extends "res://scripts/ui/settings_menu.gd"
	func _ready() -> void:
		# Build the real settings composition below with the synthetic service.
		pass

class LifecycleFixture extends Node:
	signal state_changed
	var busy: bool = false
	var pending: bool = false
	var status: String = ""
	var enabled: bool = false
	var context: Dictionary = {"user_id": "fixture-owner-one", "session_epoch": 1}
	var deletion_calls: Array[Dictionary] = []
	var check_calls: int = 0
	var internal_fence_generation: int = 0
	var recovery_owner: String = ""
	func account_context() -> Dictionary:
		return context.duplicate(true)
	func status_context() -> Dictionary:
		return {"user_id": String(context["user_id"])} if not context.is_empty() \
			else ({"user_id": recovery_owner} if pending and not recovery_owner.is_empty() else {})
	func can_delete() -> bool:
		return enabled and not context.is_empty()
	func availability_message() -> String:
		if not enabled:
			return PanelScript.UNAVAILABLE
		return "Sign in to the account you want to delete." if context.is_empty() \
			else "Review what will be removed before deleting your account."
	func can_check_status() -> bool:
		return not busy and (pending or not context.is_empty())
	func delete_account(confirmation: String, expected_context: Dictionary) -> void:
		# Deliberately leave busy unchanged to test the panel's own double-click
		# fence, independently of a service's synchronous busy transition.
		deletion_calls.append({"confirmation": confirmation,
			"context": expected_context.duplicate(true)})
		# A service may fence prior callbacks internally without changing the
		# public authentication epoch shown to this confirmation panel.
		internal_fence_generation += 1
		recovery_owner = String(expected_context.get("user_id", ""))
	func check_status() -> void:
		check_calls += 1
	func set_context(owner: String, epoch: int, notify: bool = true) -> void:
		context = {"user_id": owner, "session_epoch": epoch} if not owner.is_empty() else {}
		if notify:
			state_changed.emit()
	func set_state(message: String, next_busy: bool, next_pending: bool) -> void:
		status = message
		busy = next_busy
		pending = next_pending
		state_changed.emit()

var _passes: int = 0
var _failures: int = 0
var _service: LifecycleFixture
var _panel: AccountDeletionPanel
var _viewport: SubViewport
var _stage: Control
var _saved_insets: Vector4


func _ready() -> void:
	_saved_insets = LayoutProfile.forced_insets
	LayoutProfile.forced_insets = Vector4(24.0, 24.0, 24.0, 24.0)
	_service = LifecycleFixture.new()
	add_child(_service)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(390, 844)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_stage = VBoxContainer.new()
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(_stage)
	_panel = PanelScript.new()
	_panel.lifecycle_service = _service
	_stage.add_child(_panel)
	await _settle()
	_test_disabled_and_cancel()
	_test_enabled_signed_out_availability()
	_test_acknowledgment_and_double_click()
	_test_status_and_busy_back()
	_test_signed_out_pending_check()
	_test_frozen_owner()
	_test_same_owner_new_session()
	await _test_safe_sizing_and_orientation()
	await _test_settings_rebuild_preserves_confirmation()
	LayoutProfile.forced_insets = _saved_insets
	_viewport.queue_free()
	_service.queue_free()
	await _settle()
	print("[account_deletion_ui] DONE: %d passed, %d failed" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("[account_deletion_ui] PASS %s" % label)
	else:
		_failures += 1
		print("[account_deletion_ui] FAIL %s%s" % [label,
			": %s" % detail if not detail.is_empty() else ""])


func _settle() -> void:
	for _frame: int in 3:
		await get_tree().process_frame


func _reset_fixture() -> void:
	_service.set_state("", false, false)
	_panel.cancel_confirmation()
	_service.deletion_calls.clear()
	_service.check_calls = 0
	_service.recovery_owner = ""
	_service.enabled = true
	_service.set_context("fixture-owner-one", 1)


func _test_disabled_and_cancel() -> void:
	_check("delete_discoverable_while_disabled", not _panel._open_button.disabled)
	_panel._open_button.pressed.emit()
	_check("first_step_only_opens_disclosure", _panel.is_confirmation_open()
		and _service.deletion_calls.is_empty())
	_check("pre_release_unavailability_explicit",
		_panel._dialog_status.text == PanelScript.UNAVAILABLE)
	_panel._acknowledgment.button_pressed = true
	_panel._delete_button.pressed.emit()
	_check("disabled_gate_cannot_dispatch", _panel._delete_button.disabled
		and _service.deletion_calls.is_empty())
	_panel._cancel_button.pressed.emit()
	_check("cancel_makes_no_request", not _panel.is_confirmation_open()
		and _service.deletion_calls.is_empty())
	_check("warning_covers_permanent_cloud_deletion",
		PanelScript.WARNING.contains("permanent") and PanelScript.WARNING.contains("cloud profile")
		and PanelScript.WARNING.contains("leaderboard scores") and PanelScript.WARNING.contains("cloud save"))
	_check("warning_preserves_earned_and_removes_cached_purchase_copy",
		PanelScript.DEVICE_WARNING.contains("earned offline progress will be kept")
		and PanelScript.DEVICE_WARNING.contains("Cached purchases")
		and PanelScript.RECORD_WARNING.contains("does not automatically refund"))


func _test_enabled_signed_out_availability() -> void:
	_reset_fixture()
	_service.set_context("", 2)
	_panel.open_confirmation()
	_check("enabled_signed_out_requests_auth_without_false_pre_release_claim",
		_panel._dialog_status.text == "Sign in to the account you want to delete."
		and _panel._delete_button.disabled and _service.deletion_calls.is_empty())
	_panel.cancel_confirmation()


func _test_acknowledgment_and_double_click() -> void:
	_reset_fixture()
	_panel.open_confirmation()
	_check("destructive_action_never_initial_focus",
		_viewport.gui_get_focus_owner() == _panel._cancel_button)
	_panel._delete_button.pressed.emit()
	_check("acknowledgment_required", _service.deletion_calls.is_empty()
		and _panel._delete_button.disabled)
	_panel._acknowledgment.button_pressed = true
	_check("acknowledgment_enables_current_owner", not _panel._delete_button.disabled)
	_panel._delete_button.pressed.emit()
	_panel._delete_button.pressed.emit()
	_check("double_click_one_request_without_service_busy", _service.deletion_calls.size() == 1)
	var request: Dictionary = _service.deletion_calls[0] if not _service.deletion_calls.is_empty() else {}
	_check("explicit_confirmation_and_frozen_public_context",
		request.get("confirmation") == "DELETE_ACCOUNT"
		and request.get("context") == {"user_id": "fixture-owner-one", "session_epoch": 1})
	_check("internal_request_fence_keeps_public_owner_context",
		_service.internal_fence_generation > 0 and _service.account_context() == request.get("context")
		and not _panel._owner_changed)


func _test_status_and_busy_back() -> void:
	_service.set_state("Deletion is pending. Check status before assuming completion.", true, true)
	_check("busy_locks_buttons", _panel._delete_button.disabled
		and _panel._cancel_button.disabled and _panel._check_button.disabled)
	_check("busy_back_stays_inside_confirmation", _panel.consume_back()
		and _panel.is_confirmation_open())
	_service.set_state("Deletion is pending. Check status before assuming completion.", false, true)
	_check("pending_status_shown_without_fake_completion",
		_panel._dialog_status.text.contains("Deletion is pending")
		and _panel._check_button.visible and not _panel._check_button.disabled)
	_panel._check_button.pressed.emit()
	_panel._check_button.pressed.emit()
	_check("check_status_double_click_one_request", _service.check_calls == 1)
	_service.set_state("Deletion status could not be verified. Try checking again.", false, true)
	_check("status_signal_releases_check_lock", not _panel._check_button.disabled
		and _panel._dialog_status.text.contains("could not be verified"))
	_check("idle_back_closes_confirmation_only", _panel.consume_back()
		and not _panel.is_confirmation_open())


func _test_frozen_owner() -> void:
	_reset_fixture()
	_panel.open_confirmation()
	_panel._acknowledgment.button_pressed = true
	_service.set_context("fixture-owner-two", 2, false)
	_panel._delete_button.pressed.emit()
	_check("silent_owner_switch_cannot_confirm", _service.deletion_calls.is_empty()
		and _panel._delete_button.disabled and not _panel._acknowledgment.button_pressed)
	_check("owner_switch_requires_reopen", _panel._dialog_status.text.contains("Cancel and reopen"))
	_check("opening_owner_never_retargeted",
		_panel._confirmation_context == {"user_id": "fixture-owner-one", "session_epoch": 1})
	_service.set_context("fixture-owner-one", 1)
	_panel._acknowledgment.button_pressed = true
	_panel._delete_button.pressed.emit()
	_check("switch_back_cannot_reuse_old_consent", _service.deletion_calls.is_empty())
	_panel.cancel_confirmation()


func _test_signed_out_pending_check() -> void:
	_reset_fixture()
	_panel.open_confirmation()
	_panel._acknowledgment.button_pressed = true
	_panel._delete_button.pressed.emit()
	_service.set_context("", 2)
	_service.set_state("Account retirement was confirmed. Local cleanup needs repair.", false, true)
	_check("accepted_signout_never_retargets_original_confirmation",
		_panel._confirmation_context == {"user_id": "fixture-owner-one", "session_epoch": 1}
		and _panel._delete_button.disabled and not _panel._check_button.disabled)
	_panel._check_button.pressed.emit()
	_check("same_opening_owner_receipt_check_survives_signout", _service.check_calls == 1
		and _service.deletion_calls.size() == 1)
	_service.set_state("Local status needs another check.", false, true)
	_panel.cancel_confirmation()
	_panel.open_confirmation()
	_check("signed_out_pending_can_request_safe_local_status_repair",
		_panel._check_button.visible and not _panel._check_button.disabled
		and _panel._delete_button.disabled)
	_panel._check_button.pressed.emit()
	_check("signed_out_check_uses_service_without_new_deletion",
		_service.check_calls == 2 and _service.deletion_calls.size() == 1)
	_service.set_state("Identity and retained-record deletion remain unverified.", false, true)
	_panel.cancel_confirmation()


func _test_same_owner_new_session() -> void:
	_reset_fixture()
	_panel.open_confirmation()
	_panel._acknowledgment.button_pressed = true
	_service.set_context("fixture-owner-one", 2)
	_panel._delete_button.pressed.emit()
	_check("new_session_invalidates_same_owner_consent", _service.deletion_calls.is_empty()
		and not _panel._acknowledgment.button_pressed)
	_panel.cancel_confirmation()


func _test_safe_sizing_and_orientation() -> void:
	_reset_fixture()
	_panel.open_confirmation()
	_panel._acknowledgment.button_pressed = true
	var opening := _panel._confirmation_context.duplicate(true)
	for shape: Vector2i in [Vector2i(320, 568), Vector2i(390, 844), Vector2i(844, 390)]:
		_viewport.size = shape
		await _settle()
		var profile := LayoutProfile.for_viewport(_viewport)
		_check("dialog_within_safe_area_%dx%d" % [shape.x, shape.y],
			profile.contains_safe_rect(_panel._dialog_card.get_global_rect(), 1.0),
			"dialog=%s safe=%s card_min=%s scroll_min=%s" % [
				_panel._dialog_card.get_global_rect(), profile.safe_rect,
				_panel._dialog_card.get_combined_minimum_size(),
				_panel._dialog_scroll.get_combined_minimum_size()])
		_check("visible_actions_within_safe_area_%dx%d" % [shape.x, shape.y],
			profile.contains_safe_rect(_panel._cancel_button.get_global_rect(), 1.0)
			and profile.contains_safe_rect(_panel._delete_button.get_global_rect(), 1.0))
		_check("touch_targets_at_least_48_%dx%d" % [shape.x, shape.y],
			_panel._cancel_button.size.y >= 48.0 and _panel._delete_button.size.y >= 48.0
			and _panel._acknowledgment.size.y >= 48.0)
		_check("resize_keeps_owner_and_consent_%dx%d" % [shape.x, shape.y],
			_panel._confirmation_context == opening and _panel._acknowledgment.button_pressed
			and _service.deletion_calls.is_empty())
	_check("short_landscape_disclosure_scrolls",
		_panel._dialog_scroll.get_v_scroll_bar().max_value > _panel._dialog_scroll.get_v_scroll_bar().page)
	_panel.cancel_confirmation()


func _test_settings_rebuild_preserves_confirmation() -> void:
	_reset_fixture()
	var menu := SettingsFixture.new()
	# Use the same injected panel; settings must preserve it across reflow.
	_viewport.add_child(menu)
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.reparent(menu, false)
	menu._account_deletion_panel = _panel
	menu._build_layout(LayoutProfile.for_viewport(_viewport), false, 0.0)
	await _settle()
	_panel.open_confirmation()
	_panel._acknowledgment.button_pressed = true
	var instance_id := _panel.get_instance_id()
	var opening := _panel._confirmation_context.duplicate(true)
	menu._build_layout(LayoutProfile.for_view_size(Vector2(390, 844)), false, 0.0)
	await _settle()
	_check("settings_rebuild_preserves_panel_instance",
		menu._account_deletion_panel.get_instance_id() == instance_id)
	_check("settings_rebuild_preserves_original_confirmation",
		_panel.is_confirmation_open() and _panel._confirmation_context == opening
		and _panel._acknowledgment.button_pressed and _service.deletion_calls.is_empty())
	_service.set_state("Fixture status after settings rotation.", false, false)
	_check("settings_rebuild_keeps_live_status_subscription",
		_panel._dialog_status.text == "Fixture status after settings rotation."
		and _panel._inline_status.text == "Fixture status after settings rotation.")
	menu._go_back()
	_check("settings_back_closes_modal_without_leaving_host",
		is_instance_valid(menu) and not _panel.is_confirmation_open())
	_panel.reparent(_stage, false)
	menu.queue_free()
	await _settle()
