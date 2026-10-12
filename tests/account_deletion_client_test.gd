extends Node
## Synthetic auth/transport only; run through run_tests.sh's isolated user://.

class LifecycleFixture extends "res://scripts/network/account_lifecycle_client.gd":
	var requests: Array[Dictionary] = []
	var resumed: Array[String] = []
	func _ready() -> void:
		set_process(false)
	func _dispatch_request(method: String, path: String, body: Dictionary,
			token: String, complete: Callable) -> void:
		requests.append({"method": method, "path": path, "body": body.duplicate(true),
			"token": token, "complete": complete})
	func _resume_subject(owner: String) -> void:
		# The real native refresh transport has its own captured fixture below.
		_fenced_contexts.erase(owner)
		resumed.append(owner)
		CommerceClient._on_auth_changed()
	func deliver(index: int, ok: bool, payload: Dictionary) -> void:
		requests[index]["complete"].call(ok, payload)

class OnlineFixture extends "res://scripts/network/leaderboard_client.gd":
	var requests: Array[Dictionary] = []
	func _ready() -> void:
		set_process(false)
		auth_changed.connect(_on_auth_changed_sync)
	func _dispatch_request(method: String, url: String, body: String, complete: Callable) -> void:
		requests.append({"method": method, "url": url, "body": body, "complete": complete})
	func _local_save_is_pristine() -> bool:
		return false

class NativeFixture extends "res://scripts/commerce/native_auth_client.gd":
	var requests: Array[Dictionary] = []
	func _ready() -> void:
		set_process(false)
	func _request(path: String, body: Dictionary, complete: Callable) -> void:
		requests.append({"path": path, "body": body.duplicate(true), "complete": complete})

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	var custom := String(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	if not bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)) \
		or not custom.begins_with("waddle-wars-tests-"):
		push_error("account_deletion_client: isolated run_tests.sh identity required")
		get_tree().quit(2)
		return
	var old_flag: Variant = ProjectSettings.get_setting("account/deletion_enabled", null)
	_test_disabled_and_confirmation()
	_test_ambiguous_request()
	_test_legacy_authenticated_status()
	_test_accepted_and_duplicate_reply()
	_test_receipt_restart_and_expired_auth()
	_test_recovery_account_switch()
	_test_account_switch()
	_test_invalid_success()
	_test_web_fence()
	_test_native_fence()
	ProjectSettings.set_setting("account/deletion_enabled", old_flag)
	NativeAuthClient.sign_out(false)
	print("[account_deletion_client] DONE: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed else 0)


func _connect(owner: String) -> void:
	NativeAuthClient._token = "synthetic-token-" + owner
	NativeAuthClient.user_id = owner
	NativeAuthClient._generation += 1
	CommerceClient.configure_native_session(NativeAuthClient._token, owner)
	SaveManager.data = SaveManager.default_save()
	SaveManager.data["fish"] = 42
	SaveManager.data["unlocked_cosmetics"] = ["body_classic", "hat_beanie"]
	SaveManager.data["commerce"] = {"last_account": owner, "accounts": {
		owner: {"product_ids": ["cozy_expedition"]},
		"synthetic-other-account": {"product_ids": ["research_crew"]},
	}}
	CommerceClient._reload_cache()


func _new_client() -> LifecycleFixture:
	var client := LifecycleFixture.new()
	add_child(client)
	return client


func _accepted(identity_deleted: bool = false) -> Dictionary:
	return {"requested": true, "account_data_erased": true, "identity_deleted": identity_deleted,
		"state": "identity_deleted_retention_pending" if identity_deleted else "identity_pending",
		"deletion_complete": false, "retention_review_required": true}


func _test_disabled_and_confirmation() -> void:
	_connect("synthetic-deletion-disabled")
	var client := _new_client()
	ProjectSettings.set_setting("account/deletion_enabled", false)
	client.delete_account("DELETE_ACCOUNT", client.account_context())
	_check("disabled_sends_nothing_and_preserves_account", client.requests.is_empty()
		and SaveManager.account_deletion_state(NativeAuthClient.user_id).is_empty()
		and NativeAuthClient.signed_in() and CommerceClient.owns_product("cozy_expedition"))
	ProjectSettings.set_setting("account/deletion_enabled", true)
	client.delete_account("DELETE", client.account_context())
	_check("exact_confirmation_required", client.requests.is_empty())
	var context := client.account_context()
	_check("confirmation_context_contains_no_token", context.keys().size() == 2
		and not context.has("token") and context.has("session_epoch"))
	NativeAuthClient._generation += 1
	client.delete_account("DELETE_ACCOUNT", context)
	_check("same_owner_reauthentication_invalidates_old_confirmation", client.requests.is_empty()
		and not client.busy)
	client.free()


func _test_ambiguous_request() -> void:
	var owner := "synthetic-deletion-ambiguous"
	_connect(owner)
	var client := _new_client()
	var consent := client.account_context()
	client.delete_account("DELETE_ACCOUNT", client.account_context())
	_check("own_write_fence_keeps_public_consent_epoch_stable", client.account_context() == consent)
	_check("pending_durable_before_post", SaveManager.account_deletion_state(owner) == "pending"
		and client.requests.size() == 1 and client.requests[0]["method"] == "POST"
		and client.requests[0]["path"] == "/delete"
		and client.requests[0]["body"] == {"confirm": "DELETE_ACCOUNT",
			"recovery_receipt": SaveManager.account_deletion_receipt(owner)})
	_check("receipt_durable_before_post_and_not_public_context",
		SaveManager.account_deletion_receipt(owner).length() == 64
		and not client.account_context().has("recovery_receipt")
		and client.status_context() == {"user_id": owner})
	_check("pending_hides_cached_grants_without_erasing_them", not CommerceClient.owns_product("cozy_expedition")
		and SaveManager.data["commerce"]["accounts"].has(owner))
	client.delete_account("DELETE_ACCOUNT", client.account_context())
	client.check_status()
	_check("busy_double_actions_send_no_second_request", client.requests.size() == 1 and client.busy)
	client.deliver(0, false, {"error": "network_unavailable"})
	_check("lost_reply_never_claims_success_or_unpauses", not client.busy and client.pending
		and SaveManager.account_deletion_state(owner) == "pending" and NativeAuthClient.signed_in())
	client.delete_account("DELETE_ACCOUNT", client.account_context())
	_check("ambiguous_request_cannot_be_reposted", client.requests.size() == 1)
	client.check_status()
	_check("uncertainty_resolved_by_get_not_new_post", client.requests.size() == 2
		and client.requests[1]["method"] == "GET" and client.requests[1]["path"] == "/deletion/receipt"
		and client.requests[1]["token"] == SaveManager.account_deletion_receipt(owner))
	client.deliver(1, true, {"requested": false, "deletion_complete": false})
	_check("receipt_negative_never_releases_pending_fence", SaveManager.account_deletion_state(owner) == "pending"
		and client.pending and client.resumed.is_empty() and NativeAuthClient.signed_in())
	_check("ambiguous_receipt_preserves_earned_progress_and_fences_grants", not CommerceClient.owns_product("cozy_expedition")
		and SaveManager.data["fish"] == 42 and "hat_beanie" in SaveManager.data["unlocked_cosmetics"])
	client.free()


func _test_accepted_and_duplicate_reply() -> void:
	var owner := "synthetic-deletion-accepted"
	_connect(owner)
	SaveManager.save_now()
	SaveManager.save_now()
	var client := _new_client()
	client.delete_account("DELETE_ACCOUNT", client.account_context())
	client.deliver(0, true, _accepted())
	_check("accepted_retirement_signs_out_exact_current_account", not NativeAuthClient.signed_in()
		and SaveManager.account_deletion_state(owner) == "retired")
	_check("accepted_erases_only_linked_cache_keeps_earned_progress", not SaveManager.data["commerce"]["accounts"].has(owner)
		and SaveManager.data["commerce"]["accounts"].has("synthetic-other-account")
		and SaveManager.data["fish"] == 42 and "hat_beanie" in SaveManager.data["unlocked_cosmetics"])
	var previous_status := client.status
	client.deliver(0, true, _accepted(true))
	_check("late_duplicate_cannot_rewrite_status", client.status == previous_status and not client.busy)
	_check("provider_and_retention_pending_not_full_completion", client.pending
		and client.status.contains("pending") and client.status.contains("not confirmed complete"))
	client.check_status()
	_check("signed_out_retry_uses_status_only_receipt", client.requests.size() == 2
		and client.requests[1]["path"] == "/deletion/receipt"
		and client.requests[1]["token"] == SaveManager.account_deletion_receipt(owner))
	client.deliver(1, true, _accepted(true))
	_check("signed_out_identity_confirmation_can_advance_status", client.status.contains("identity and cloud game data deleted")
		and not NativeAuthClient.signed_in() and SaveManager.account_deletion_state(owner) == "retired")
	_check("signed_out_retired_request_can_repair_local_cleanup", client.can_check_status())
	client.free()


func _test_legacy_authenticated_status() -> void:
	var owner := "synthetic-legacy-status"
	_connect(owner)
	_check("legacy_pending_journal_preserved_without_fabricated_receipt", SaveManager.set_account_deletion_state(owner, "pending")
		and SaveManager.account_deletion_receipt(owner).is_empty())
	var client := _new_client()
	client._refresh_pending()
	client.check_status()
	_check("legacy_authenticated_status_uses_exact_owner_jwt", client.requests.size() == 1
		and client.requests[0]["path"] == "/deletion" and client.requests[0]["token"] == NativeAuthClient._token)
	client.deliver(0, true, {"requested": false, "deletion_complete": false})
	_check("only_legacy_authenticated_negative_can_release_fence", SaveManager.account_deletion_state(owner).is_empty()
		and client.resumed == [owner] and NativeAuthClient.signed_in())
	client.free()


func _test_receipt_restart_and_expired_auth() -> void:
	var owner := "synthetic-recovery-expired"
	_connect(owner)
	var first := _new_client()
	first.delete_account("DELETE_ACCOUNT", first.account_context())
	var receipt := SaveManager.account_deletion_receipt(owner)
	first.deliver(0, false, {"error": "network_unavailable"})
	NativeAuthClient.sign_out(false)
	first.free()
	var recovered := _new_client()
	recovered._refresh_pending()
	_check("restart_signed_out_finds_exact_durable_owner", recovered.pending
		and recovered.can_check_status() and recovered.status_context() == {"user_id": owner})
	recovered.check_status()
	_check("expired_session_recovery_sends_no_post_or_jwt", recovered.requests.size() == 1
		and recovered.requests[0]["method"] == "GET" and recovered.requests[0]["path"] == "/deletion/receipt"
		and recovered.requests[0]["body"].is_empty() and recovered.requests[0]["token"] == receipt)
	recovered.deliver(0, false, {"error": "status_unavailable"})
	_check("unknown_receipt_never_reconnects_or_erases", recovered.pending
		and SaveManager.account_deletion_state(owner) == "pending"
		and SaveManager.data["commerce"]["accounts"].has(owner) and recovered.resumed.is_empty())
	recovered.check_status()
	recovered.deliver(1, true, _accepted(true))
	_check("expired_session_confirmed_status_erases_only_retired_cache", SaveManager.account_deletion_state(owner) == "retired"
		and not SaveManager.data["commerce"]["accounts"].has(owner)
		and SaveManager.data["commerce"]["accounts"].has("synthetic-other-account")
		and SaveManager.data["fish"] == 42 and not NativeAuthClient.signed_in())
	_check("retirement_retains_receipt_without_claiming_full_deletion", SaveManager.account_deletion_receipt(owner) == receipt
		and recovered.status.contains("Retained-record deletion is still pending"))
	recovered.free()
	ProjectSettings.set_setting("account/deletion_enabled", false)
	var local_only := _new_client()
	local_only._refresh_pending()
	local_only.check_status()
	_check("disabled_server_restart_repairs_only_known_retired_owner_locally", local_only.can_check_status()
		and local_only.requests.is_empty() and local_only.status.contains("not confirmed complete")
		and local_only.status_context() == {"user_id": owner})
	local_only.free()
	ProjectSettings.set_setting("account/deletion_enabled", true)


func _test_recovery_account_switch() -> void:
	var owner := "synthetic-recovery-before-switch"
	_connect(owner)
	var client := _new_client()
	client.delete_account("DELETE_ACCOUNT", client.account_context())
	client.deliver(0, false, {"error": "network_unavailable"})
	NativeAuthClient.sign_out(false)
	client.check_status()
	_connect("synthetic-recovery-new-owner")
	client.deliver(1, true, _accepted(true))
	_check("delayed_recovery_never_signs_out_new_owner", NativeAuthClient.user_id == "synthetic-recovery-new-owner"
		and NativeAuthClient.signed_in() and CommerceClient.owns_product("cozy_expedition"))
	_check("status_context_never_borrows_previous_owner_receipt", client.status_context() == {"user_id": "synthetic-recovery-new-owner"})
	client.check_status()
	_check("new_owner_status_uses_authenticated_not_old_receipt", client.requests.size() == 3
		and client.requests[2]["path"] == "/deletion"
		and client.requests[2]["token"] == NativeAuthClient._token)
	client.deliver(2, true, {"requested": false, "deletion_complete": false})
	client.free()


func _test_account_switch() -> void:
	var owner := "synthetic-deletion-old-account"
	_connect(owner)
	var client := _new_client()
	client.delete_account("DELETE_ACCOUNT", client.account_context())
	_connect("synthetic-deletion-replacement")
	client.deliver(0, true, _accepted(true))
	_check("delayed_old_success_never_signs_out_replacement", NativeAuthClient.signed_in()
		and NativeAuthClient.user_id == "synthetic-deletion-replacement")
	_check("delayed_old_success_keeps_replacement_purchase_cache", CommerceClient.owns_product("cozy_expedition")
		and SaveManager.data["commerce"]["accounts"].has("synthetic-deletion-replacement")
		and SaveManager.account_deletion_state(owner) == "retired")
	client.free()


func _test_invalid_success() -> void:
	var owner := "synthetic-deletion-invalid-response"
	_connect(owner)
	var client := _new_client()
	client.delete_account("DELETE_ACCOUNT", client.account_context())
	client.deliver(0, true, {"requested": true, "deletion_complete": true})
	_check("malformed_success_never_erases_local_cache", SaveManager.account_deletion_state(owner) == "pending"
		and SaveManager.data["commerce"]["accounts"].has(owner) and client.pending)
	_check("strings_are_not_server_boolean_acknowledgments", not client._retirement_acknowledged({"requested": "true"}))
	client.free()


func _web_state(owner: String) -> Dictionary:
	var token := "header.%s.signature" % Marshalls.utf8_to_base64(JSON.stringify({"sub": owner}))
	return {"signedIn": true, "token": token, "identityEpoch": 1, "ready": true}


func _test_web_fence() -> void:
	var owner := "synthetic-deletion-web"
	var online := OnlineFixture.new()
	add_child(online)
	online._apply_web_auth_state(_web_state(owner))
	var delayed_pull: Callable = online.requests[0]["complete"]
	online._save_push_timer = 4.0
	SaveManager.set_account_deletion_state(owner, "pending")
	online.suspend_account_subject(owner)
	delayed_pull.call(true, {"exists": false})
	_check("pending_web_fence_drops_old_pull_and_debounce", online.requests.size() == 1
		and not online._synced_this_session and online._save_push_timer < 0.0)
	online._synced_this_session = true
	online._push_save_now()
	var replies: Array[Dictionary] = []
	online._request("POST", "fixture/profile", "{}", func(ok: bool, payload: Dictionary) -> void:
		replies.append({"ok": ok, "payload": payload}))
	_check("pending_web_cannot_push_or_post", online.requests.size() == 1 and replies.size() == 1
		and not replies[0]["ok"] and replies[0]["payload"]["error"] == "account_deletion_pending")
	SaveManager.set_account_deletion_state(owner, "retired")
	online.retire_account_subject(owner)
	online._apply_web_auth_state(_web_state(owner))
	_check("stale_web_bridge_cannot_reaccept_retired_identity", not online.signed_in
		and online._token.is_empty() and online._auth_owner_id.is_empty() and online.requests.size() == 1)
	online.free()


func _test_native_fence() -> void:
	var owner := "synthetic-deletion-native"
	var auth := NativeFixture.new()
	add_child(auth)
	auth._token = "synthetic-old-token"
	auth.user_id = owner
	auth._refresh_session()
	_check("native_fixture_captures_refresh_without_network", auth.requests.size() == 1)
	SaveManager.set_account_deletion_state(owner, "pending")
	auth.suspend_account_subject(owner)
	auth.requests[0]["complete"].call(true, {"token": "synthetic-stale-refresh", "user_id": owner, "expires_in": 60})
	_check("delayed_native_refresh_cannot_restore_session", auth._token == "synthetic-old-token")
	auth._refresh_session()
	_check("pending_native_refresh_sends_nothing", auth.requests.size() == 1)
	SaveManager.set_account_deletion_state(owner, "retired")
	_check("retired_native_token_cannot_be_accepted", not auth._accept_token({"token": "synthetic-retired-token",
		"user_id": owner, "expires_in": 60}) and auth._token == "synthetic-old-token")
	auth.free()


func _check(label: String, success: bool) -> void:
	if success:
		_passed += 1
		print("[account_deletion_client] PASS " + label)
	else:
		_failed += 1
		push_error("[account_deletion_client] FAIL " + label)
