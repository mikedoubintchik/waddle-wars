extends Node
## Exact pending-operation retry with synthetic auth/transport. No live deletion.

class LifecycleFixture extends "res://scripts/network/account_lifecycle_client.gd":
	var raw: Dictionary = {}
	var requests: Array[Dictionary] = []
	var renewals: Array[Dictionary] = []
	var evicted: Array[String] = []
	func _ready() -> void:
		set_process(false)
	func _auth_context() -> Dictionary:
		return raw.duplicate()
	func _suspend_subject(_owner: String) -> void:
		pass
	func _renew_deletion_credential(owner: String, complete: Callable) -> void:
		renewals.append({"owner": owner, "complete": complete})
	func _dispatch_request(method: String, path: String, body: Dictionary, token: String, complete: Callable) -> void:
		requests.append({"method": method, "path": path, "body": body.duplicate(), "token": token, "complete": complete})
	func _evict_if_current(owner: String, context: Dictionary) -> void:
		if account_context() == context:
			evicted.append(owner)
			raw = {}

class NativeFixture extends "res://scripts/commerce/native_auth_client.gd":
	var requests: Array[Dictionary] = []
	func _request(path: String, body: Dictionary, complete: Callable) -> void:
		requests.append({"path": path, "body": body.duplicate(), "complete": complete})

var passed: int = 0
var failed: int = 0

func _ready() -> void:
	var custom := String(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	if not bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)) or not custom.begins_with("waddle-wars-tests-"):
		push_error("account_deletion_retry: isolated user directory required")
		get_tree().quit(2)
		return
	var previous: Variant = ProjectSettings.get_setting("account/deletion_enabled", null)
	ProjectSettings.set_setting("account/deletion_enabled", true)
	SaveManager.data = SaveManager.default_save()
	await recovery_and_visible_consent()
	await rejected_renewals()
	native_renewal()
	ProjectSettings.set_setting("account/deletion_enabled", previous)
	print("[account_deletion_retry] %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)

func client(owner: String) -> LifecycleFixture:
	var value := LifecycleFixture.new()
	value.raw = {"user_id": owner, "token": jwt(owner, -120), "session_epoch": 1}
	add_child(value)
	return value

func begin_pending(value: LifecycleFixture) -> String:
	var context := value.account_context()
	value.delete_account("DELETE_ACCOUNT", context)
	check("initial deletion has persisted receipt before POST", value.requests.size() == 1 and value.requests[0]["path"] == "/delete")
	value.requests[0]["complete"].call(false, {"error": "unauthorized"})
	var receipt := SaveManager.account_deletion_receipt(String(context["user_id"]))
	check("rejected POST keeps durable pending operation", receipt.length() == 64 and value.pending and not value.busy)
	return receipt

func recovery_and_visible_consent() -> void:
	var owner := "retry-consent-owner"
	var value := client(owner)
	var receipt := begin_pending(value)
	value.check_status()
	value.requests[1]["complete"].call(false, {"error": "status_unavailable"})
	check("receipt404 neither posts nor releases fence", value.requests.size() == 2 and SaveManager.account_deletion_state(owner) == "pending")
	check("same pending owner can explicitly retry", value.can_retry_deletion())
	value.retry_account_deletion("DELETE", value.account_context())
	check("retry requires exact renewed consent", value.renewals.is_empty())
	var old := value.account_context()
	value.raw["session_epoch"] = 2
	value.retry_account_deletion("DELETE_ACCOUNT", old)
	check("reauthentication invalidates earlier consent", value.renewals.is_empty())
	var viewport := SubViewport.new()
	viewport.size = Vector2i(430, 932)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var stage := VBoxContainer.new()
	viewport.add_child(stage)
	var panel := AccountDeletionPanel.new()
	panel.lifecycle_service = value
	stage.add_child(panel)
	await get_tree().process_frame
	panel.open_confirmation()
	check("pending dialog clearly labels retry", panel._delete_button.text == "Retry deletion" and panel._retry_mode)
	check("retry starts with fresh unchecked acknowledgment", not panel._acknowledgment.button_pressed and panel._delete_button.disabled and not panel._acknowledgment.disabled)
	panel._on_delete_pressed()
	check("opening dialog never retries automatically", value.renewals.is_empty())
	panel._acknowledgment.button_pressed = true
	panel._on_delete_pressed()
	check("confirmed retry refreshes once before POST", value.renewals.size() == 1 and value.requests.size() == 2 and value.busy)
	panel._on_delete_pressed()
	value.retry_account_deletion("DELETE_ACCOUNT", value.account_context())
	check("busy duplicate retry cannot start another refresh", value.renewals.size() == 1)
	value.raw["token"] = jwt(owner)
	value.renewals[0]["complete"].call(true)
	check("fresh same-owner refresh retries one original POST", value.requests.size() == 3 and value.requests[2]["path"] == "/delete" and value.requests[2]["method"] == "POST")
	check("retry preserves original receipt and operation consent", value.requests[2]["body"] == {"confirm": "DELETE_ACCOUNT", "recovery_receipt": receipt} and value.requests[2]["token"] == value.raw["token"])
	value.renewals[0]["complete"].call(true)
	check("duplicate refresh response cannot repeat deletion", value.requests.size() == 3)
	value.requests[2]["complete"].call(false, {"error": "network_unavailable"})
	check("failed retry keeps receipt/fence and requires reopened confirmation", SaveManager.account_deletion_receipt(owner) == receipt and SaveManager.account_deletion_state(owner) == "pending" and panel._delete_button.disabled and panel._acknowledgment.disabled)
	panel.cancel_confirmation()
	panel.open_confirmation()
	check("reopened retry requires another explicit acknowledgment", not panel._acknowledgment.button_pressed and panel._delete_button.disabled and not panel._acknowledgment.disabled)
	panel._acknowledgment.button_pressed = true
	panel._on_delete_pressed()
	value.renewals[1]["complete"].call(true)
	check("second intentional retry reuses same receipt", value.requests.size() == 4 and value.requests[3]["body"]["recovery_receipt"] == receipt)
	value.requests[3]["complete"].call(true, accepted())
	check("confirmed retirement uses captured raw owner", value.evicted == [owner] and SaveManager.account_deletion_state(owner) == "retired")
	check("retired operation can never retry", not value.can_retry_deletion() and panel._delete_button.disabled)
	viewport.free()
	value.free()

func rejected_renewals() -> void:
	for reason: String in ["wrong_owner", "new_epoch", "expired", "failed"]:
		var owner := "retry-rejected-" + reason
		var value := client(owner)
		var receipt := begin_pending(value)
		value.retry_account_deletion("DELETE_ACCOUNT", value.account_context())
		check(reason + " starts one explicit renewal", value.renewals.size() == 1)
		match reason:
			"wrong_owner": value.raw = {"user_id": "replacement-owner", "token": jwt("replacement-owner"), "session_epoch": 2}
			"new_epoch": value.raw["session_epoch"] = 2
			"expired": value.raw["token"] = jwt(owner, -30)
			"failed": value.raw["token"] = jwt(owner)
		value.renewals[0]["complete"].call(reason != "failed")
		check(reason + " sends no retry POST", value.requests.size() == 1 and not value.busy)
		check(reason + " preserves original operation fence", SaveManager.account_deletion_state(owner) == "pending" and SaveManager.account_deletion_receipt(owner) == receipt)
		value.free()
	check("stale issued token cannot authorize retry", not AccountLifecycleClient._fresh_deletion_token(jwt("freshness", 60, -400), "freshness"))
	check("future issued token cannot authorize retry", not AccountLifecycleClient._fresh_deletion_token(jwt("freshness", 60, 60), "freshness"))
	check("different JWT owner cannot authorize retry", not AccountLifecycleClient._fresh_deletion_token(jwt("other"), "freshness"))
	check("malformed JWT cannot authorize retry", not AccountLifecycleClient._fresh_deletion_token("not-a-token", "freshness"))

func native_renewal() -> void:
	var owner := "retry-native-helper"
	SaveManager.begin_account_deletion(owner, "c".repeat(64))
	var native := NativeFixture.new()
	add_child(native)
	native.user_id = owner
	native._token = jwt(owner, -60)
	native._request_id = "synthetic-request"
	native._verifier = "a".repeat(43)
	var results: Array[bool] = []
	native.refresh_for_account_deletion("other", func(ok: bool) -> void: results.append(ok))
	check("native helper refuses different owner", results == [false] and native.requests.is_empty())
	native.refresh_for_account_deletion(owner, func(ok: bool) -> void: results.append(ok))
	check("native helper uses existing PKCE capability once", native.requests.size() == 1 and native.requests[0]["path"] == "/refresh" and native.requests[0]["body"]["verifier"] == native._verifier)
	native.requests[0]["complete"].call(true, {"user_id": owner, "token": jwt(owner), "expires_in": 60})
	check("native pending credential can refresh for deletion", results == [false, true] and native.user_id == owner)
	check("successful explicit renewal keeps ordinary refresh suspended", native._refresh_timer.is_stopped() and SaveManager.account_deletion_state(owner) == "pending")
	native.refresh_for_account_deletion(owner, func(ok: bool) -> void: results.append(ok))
	native._generation += 1
	native.requests[1]["complete"].call(true, {"user_id": owner, "token": jwt(owner), "expires_in": 60})
	check("native late renewal cannot survive identity epoch change", results[-1] == false and native._refresh_timer.is_stopped())
	native.free()

func jwt(owner: String, lifetime: int = 60, issued_offset: int = 0) -> String:
	var now := int(Time.get_unix_time_from_system())
	var payload := {"iss": "https://clerk.waddlewars.io", "sub": owner, "iat": now + issued_offset, "exp": now + lifetime}
	var encoded := Marshalls.utf8_to_base64(JSON.stringify(payload)).replace("+", "-").replace("/", "_").trim_suffix("=")
	return "synthetic." + encoded + ".signature"

func accepted() -> Dictionary:
	return {"requested": true, "account_data_erased": true, "identity_deleted": true,
		"state": "identity_deleted_retention_pending", "deletion_complete": false, "retention_review_required": true}

func check(label: String, ok: bool) -> void:
	if ok: passed += 1
	else: failed += 1
	print("[account_deletion_retry] %s %s" % ["PASS" if ok else "FAIL", label])
