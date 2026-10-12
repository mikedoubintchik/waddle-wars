extends Node
## Explicit account retirement. No polling, commerce grants or automatic erasure.
## A durable local journal fences ambiguous requests. Its status-only receipt
## survives expired sign-in; server remains authority for identity/data erasure.

signal state_changed

const API_BASE: String = "https://waddle-wars-leaderboard.ninjaconsultingllc.workers.dev"
const REQUEST_TIMEOUT: float = 20.0

var busy: bool = false
var pending: bool = false
var status: String = ""
var _sequence: int = 0
var _last_subject: String = ""
var _fenced_contexts: Dictionary = {}
var _transitioning_local_auth: bool = false


func _ready() -> void:
	set_process(false)
	process_mode = Node.PROCESS_MODE_ALWAYS
	LeaderboardClient.auth_changed.connect(_on_auth_changed)
	NativeAuthClient.auth_changed.connect(_on_auth_changed)
	_refresh_pending()


## Only an opaque owner and session epoch reach confirmation UI, never a token.
func account_context() -> Dictionary:
	var context := _auth_context()
	if String(context.get("token", "")).is_empty() or String(context.get("user_id", "")).is_empty():
		return {}
	var owner := String(context["user_id"])
	var epoch := int(context.get("session_epoch", 0))
	var fence: Dictionary = _fenced_contexts.get(owner, {})
	# Our own write-fence invalidation is not a new sign-in. Keep the public
	# consent epoch stable while still fencing transport callbacks internally.
	if epoch == int(fence.get("fenced_epoch", -1)):
		epoch = int(fence["consent_epoch"])
	return {"user_id": owner, "session_epoch": epoch}


func can_delete() -> bool:
	var context := account_context()
	return _enabled() and not busy and not context.is_empty() \
		and SaveManager.account_deletion_journal_available() \
		and SaveManager.account_deletion_state(String(context["user_id"])).is_empty()


## A retry reuses the original operation and needs fresh visible consent.
## A missing receipt never establishes that an earlier request did not commit.
func can_retry_deletion() -> bool:
	var context := account_context()
	if not _enabled() or busy or context.is_empty() or not SaveManager.account_deletion_journal_available():
		return false
	var owner := String(context["user_id"])
	return SaveManager.account_deletion_state(owner) == "pending" \
		and not SaveManager.account_deletion_receipt(owner).is_empty()


func availability_message() -> String:
	if not _enabled():
		return "Account deletion is not enabled in this pre-release build."
	if not SaveManager.account_deletion_journal_available():
		return "Local account status cannot be read. Account activity is paused until this device's status is repaired."
	if pending:
		return "A deletion request is unresolved. Check status, or reconnect the same account and review Retry deletion."
	if account_context().is_empty():
		return "Sign in to the account you want to delete."
	return "Delete the connected account and its cloud game data. Review the confirmation before continuing."


func can_check_status() -> bool:
	if busy or not SaveManager.account_deletion_journal_available():
		return false
	if not account_context().is_empty():
		return _enabled()
	var owner := _status_subject()
	return not owner.is_empty() and (SaveManager.account_deletion_state(owner) == "retired" \
		or (_enabled() and not SaveManager.account_deletion_receipt(owner).is_empty()))


## Read-only public status identity; never expose a receipt or session token.
func status_context() -> Dictionary:
	var owner := _status_subject()
	return {"user_id": owner} if not owner.is_empty() else {}


func _status_subject() -> String:
	var current := account_context()
	if not current.is_empty():
		return String(current["user_id"])
	var durable := SaveManager.account_deletion_recovery_subject()
	return durable if not durable.is_empty() else _last_subject


func _new_recovery_receipt() -> String:
	var bytes := Crypto.new().generate_random_bytes(32)
	return bytes.hex_encode() if bytes.size() == 32 else ""


func delete_account(confirmation: String, expected_context: Dictionary) -> void:
	if busy:
		return
	if not _enabled():
		_set_status("Account deletion is not enabled in this pre-release build.")
		return
	if confirmation != "DELETE_ACCOUNT":
		_set_status("Confirm account deletion before continuing.")
		return
	var context := account_context()
	if context.is_empty() or context != expected_context:
		_set_status("Account changed. Review the deletion confirmation again.")
		return
	if not can_delete():
		_set_status("Check the existing deletion request before trying again.")
		return
	var raw := _auth_context()
	var owner := String(context["user_id"])
	var receipt := _new_recovery_receipt()
	if receipt.is_empty() or not SaveManager.begin_account_deletion(owner, receipt):
		_set_status("Could not save deletion status on this device. No deletion request was sent.")
		return
	_last_subject = owner
	_suspend_subject(owner)
	var completion_context := account_context()
	_set_status("Requesting account deletion…")
	_start_request("POST", "/delete", {"confirm": "DELETE_ACCOUNT", "recovery_receipt": receipt}, raw,
		func(ok: bool, payload: Dictionary) -> void:
			_handle_response(ok, payload, owner, completion_context, false))


func check_status() -> void:
	if busy:
		return
	var owner := _status_subject()
	var receipt := SaveManager.account_deletion_receipt(owner)
	if _enabled() and not receipt.is_empty() \
		and SaveManager.account_deletion_state(owner) in ["pending", "retired"]:
		_last_subject = owner
		var context := account_context()
		_set_status("Checking account deletion…")
		_start_request("GET", "/deletion/receipt", {}, {"token": receipt},
			func(ok: bool, payload: Dictionary) -> void:
				# A missing receipt may precede a delayed POST commit. Only positive
				# retirement status is authoritative; NEVER release its fence.
				_handle_response(ok, payload, owner, context, false))
		return
	# A confirmed server retirement authorizes repair of interrupted local cleanup
	# even after this device has signed out. It does not prove provider completion.
	if account_context().is_empty() and not owner.is_empty() \
		and SaveManager.account_deletion_state(owner) == "retired":
		var repaired := SaveManager.erase_account_purchase_cache(owner)
		CommerceClient._reload_cache()
		_set_status("Account deletion was requested. Local purchase cache cleared; identity and retained-record deletion are not confirmed complete."
			if repaired else "Account deletion was requested. Local cleanup is incomplete; try Check status again.")
		return
	if not _enabled():
		_set_status("Account deletion is not enabled in this pre-release build.")
		return
	var raw := _auth_context()
	var context := account_context()
	if context.is_empty():
		_set_status("Sign in to the same account to check deletion status. Do not submit another deletion request.")
		return
	owner = String(context["user_id"])
	_last_subject = owner
	_set_status("Checking account deletion…")
	_start_request("GET", "/deletion", {}, raw, func(ok: bool, payload: Dictionary) -> void:
		_handle_response(ok, payload, owner, context, true))


func retry_account_deletion(confirmation: String, expected_context: Dictionary) -> void:
	if busy:
		return
	if confirmation != "DELETE_ACCOUNT" or expected_context.is_empty() \
		or account_context() != expected_context or not can_retry_deletion():
		_set_status("Reconnect the same account and review the deletion confirmation again.")
		return
	var owner := String(expected_context["user_id"])
	var receipt := SaveManager.account_deletion_receipt(owner)
	_sequence += 1
	var sequence := _sequence
	var delivered: Array[bool] = [false]
	busy = true
	_set_status("Refreshing the same account before retrying deletion…")
	_renew_deletion_credential(owner, func(ok: bool) -> void:
		if delivered[0] or sequence != _sequence:
			return
		delivered[0] = true
		busy = false
		if account_context() != expected_context:
			_set_status("Account changed. Review the deletion confirmation again.")
			return
		var raw := _auth_context()
		if not ok or not _fresh_deletion_token(String(raw.get("token", "")), owner):
			_set_status("Reconnect the same account, then review Retry deletion. The existing request is still protected; Check status remains available.")
			return
		if not can_retry_deletion() or SaveManager.account_deletion_receipt(owner) != receipt:
			_set_status("Deletion status changed. Check status before continuing.")
			return
		_last_subject = owner
		_set_status("Retrying the same account deletion request…")
		_start_request("POST", "/delete", {"confirm": "DELETE_ACCOUNT", "recovery_receipt": receipt}, raw,
			func(accepted: bool, payload: Dictionary) -> void:
				_handle_response(accepted, payload, owner, expected_context, false)))


func _renew_deletion_credential(owner: String, complete: Callable) -> void:
	if OS.has_feature("web"):
		# Clerk's web session keeps its own token refreshed. No request may use
		# the previous account or an expired token merely because consent exists.
		complete.call(_fresh_deletion_token(String(_auth_context().get("token", "")), owner))
	else:
		NativeAuthClient.refresh_for_account_deletion(owner, complete)


static func _fresh_deletion_token(token: String, owner: String) -> bool:
	var parts := token.split(".")
	if parts.size() != 3:
		return false
	var encoded := parts[1].replace("-", "+").replace("_", "/")
	while encoded.length() % 4 != 0:
		encoded += "="
	var claims: Variant = JSON.parse_string(Marshalls.base64_to_utf8(encoded))
	if not claims is Dictionary or claims.get("sub") != owner:
		return false
	# This is a freshness/owner guard only; the server verifies the signature.
	var now := Time.get_unix_time_from_system()
	var issued: Variant = claims.get("iat")
	var expires: Variant = claims.get("exp")
	return (issued is int or issued is float) and (expires is int or expires is float) \
		and float(issued) <= now + 30.0 and float(issued) >= now - 300.0 \
		and float(expires) > now + 5.0


func _handle_response(ok: bool, payload: Dictionary, owner: String,
		completion_context: Dictionary, is_status_check: bool) -> void:
	if ok and _retirement_acknowledged(payload):
		var current := account_context()
		var other_account := not current.is_empty() and String(current["user_id"]) != owner
		var suffix := " Your currently connected account was not deleted or signed out." if other_account else ""
		var marked := SaveManager.set_account_deletion_state(owner, "retired")
		var cleaned := SaveManager.erase_account_purchase_cache(owner) if marked else false
		CommerceClient._reload_cache()
		_evict_if_current(owner, completion_context)
		if not marked or not cleaned:
			_set_status("Server account retirement confirmed. Local cleanup is incomplete; check status again. Full deletion is not confirmed complete." + suffix)
		elif GameConfig.native_accounts_enabled():
			_set_status(("Account identity and cloud game data deleted. Offline progress kept. Limited security markers and deletion receipts remain."
				if bool(payload["identity_deleted"]) else "Cloud game data deleted. Offline progress kept. Account identity deletion is pending; use Check status.") + suffix)
		elif bool(payload["identity_deleted"]):
			_set_status("Account identity and cloud game data deleted. Local purchase cache cleared. Retained-record deletion is still pending; no automatic refund was issued." + suffix)
		else:
			_set_status("Cloud game data deleted and local purchase cache cleared. Account identity deletion is pending. Full deletion is not confirmed complete." + suffix)
		return
	# Only a successful authenticated status read can resolve an uncertain POST.
	# A transport failure or even an error reply may follow a committed erasure.
	if is_status_check and ok and payload.get("requested") is bool \
		and not bool(payload["requested"]) and payload.get("deletion_complete") is bool \
		and not bool(payload["deletion_complete"]) \
		and SaveManager.account_deletion_state(owner) != "retired":
		if SaveManager.set_account_deletion_state(owner, ""):
			_resume_subject(owner)
			_set_status("No deletion request is recorded for this account. Your account remains connected.")
		else:
			_set_status("No server deletion is recorded, but local status could not be saved. Account activity remains paused.")
		return
	var code := String(payload.get("error", ""))
	if code in ["unauthorized", "fresh_session_token_required"]:
		_set_status("Reconnect the same account, then check deletion status. Deletion has not been confirmed.")
	else:
		_set_status("Deletion status could not be confirmed. Account activity remains paused; use Check status when connected.")


static func _retirement_acknowledged(payload: Dictionary) -> bool:
	return payload.get("requested") is bool and bool(payload["requested"]) \
		and payload.get("account_data_erased") is bool and bool(payload["account_data_erased"]) \
		and payload.get("identity_deleted") is bool \
		and payload.get("deletion_complete") is bool and not bool(payload["deletion_complete"]) \
		and payload.get("retention_review_required") is bool and bool(payload["retention_review_required"]) \
		and String(payload.get("state", "")) == ("identity_deleted_retention_pending"
			if bool(payload["identity_deleted"]) else "identity_pending")


func _start_request(method: String, path: String, body: Dictionary,
		raw: Dictionary, callback: Callable) -> void:
	_sequence += 1
	var sequence := _sequence
	var delivered: Array[bool] = [false]
	busy = true
	_refresh_pending()
	state_changed.emit()
	var complete := func(ok: bool, payload: Dictionary) -> void:
		if delivered[0] or sequence != _sequence:
			return
		delivered[0] = true
		busy = false
		callback.call(ok, payload)
	_dispatch_request(method, path, body, String(raw.get("token", "")), complete)


func _dispatch_request(method: String, path: String, body: Dictionary,
		token: String, complete: Callable) -> void:
	var base := String(ProjectSettings.get_setting("commerce/api_base", API_BASE)).trim_suffix("/")
	var origin := RegEx.create_from_string("^https://[A-Za-z0-9.-]+(?::[0-9]{1,5})?$")
	if origin.search(base) == null or token.is_empty():
		complete.call(false, {"error": "account_deletion_unavailable"})
		return
	var timeout := get_tree().create_timer(REQUEST_TIMEOUT, true)
	timeout.timeout.connect(func() -> void: complete.call(false, {"error": "network_unavailable"}))
	var text := JSON.stringify(body) if not body.is_empty() else ""
	if OS.has_feature("web"):
		# Bypass ordinary game-route fencing only for these two lifecycle paths.
		# The bridge transports the existing token; server JWT auth is authoritative.
		if path == "/deletion/receipt":
			var js := "window.__ww_api ? window.__ww_api.startReceipt(%s, %s) : 0" % [
				LeaderboardClient._js_quote("%s/api/account%s" % [base, path]), LeaderboardClient._js_quote(token)]
			var result: Variant = JavaScriptBridge.eval(js, true)
			var request_id := int(result) if result != null else 0
			if request_id > 0:
				LeaderboardClient._track_bridge_request(request_id, complete)
			else:
				complete.call(false, {"error": "network_unavailable"})
		else:
			LeaderboardClient._request_via_bridge(method, "%s/api/account%s" % [base, path], text, complete, token)
		return
	var http := HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT
	http.max_redirects = 0
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
		http.queue_free()
		var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		var payload: Dictionary = parsed if parsed is Dictionary else {"error": "network_unavailable"}
		complete.call(result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300, payload))
	var request_headers := PackedStringArray(["X-Waddle-Deletion-Receipt: %s" % token]) if path == "/deletion/receipt" \
		else PackedStringArray(["Authorization: Bearer %s" % token, "Content-Type: application/json"])
	var error := http.request("%s/api/account%s" % [base, path], request_headers,
		HTTPClient.METHOD_POST if method == "POST" else HTTPClient.METHOD_GET, text)
	if error != OK:
		http.queue_free()
		complete.call(false, {"error": "network_unavailable"})


func _auth_context() -> Dictionary:
	if OS.has_feature("web"):
		return {"user_id": LeaderboardClient._auth_owner_id, "token": LeaderboardClient._token,
			"session_epoch": LeaderboardClient._auth_generation}
	return {"user_id": NativeAuthClient.user_id, "token": NativeAuthClient._token,
		"session_epoch": NativeAuthClient._generation}


func _suspend_subject(owner: String) -> void:
	var before := account_context()
	LeaderboardClient.suspend_account_subject(owner)
	NativeAuthClient.suspend_account_subject(owner)
	var after := _auth_context()
	if String(before.get("user_id", "")) == owner and String(after.get("user_id", "")) == owner:
		_fenced_contexts[owner] = {"consent_epoch": int(before["session_epoch"]),
			"fenced_epoch": int(after.get("session_epoch", 0))}
	CommerceClient._on_auth_changed()


func _resume_subject(owner: String) -> void:
	_fenced_contexts.erase(owner)
	LeaderboardClient.resume_account_subject(owner)
	NativeAuthClient.resume_account_subject(owner)
	CommerceClient._on_auth_changed()


func _evict_if_current(owner: String, expected_context: Dictionary) -> void:
	if account_context() != expected_context or String(expected_context.get("user_id", "")) != owner:
		return
	_transitioning_local_auth = true
	if OS.has_feature("web"):
		LeaderboardClient.retire_account_subject(owner)
	else:
		NativeAuthClient.sign_out(false)
	_transitioning_local_auth = false
	_fenced_contexts.erase(owner)


func _enabled() -> bool:
	var flag: Variant = ProjectSettings.get_setting("account/deletion_enabled", false)
	return flag is bool and bool(flag)


func _on_auth_changed() -> void:
	if _transitioning_local_auth:
		return
	_refresh_pending()
	state_changed.emit()


func _refresh_pending() -> void:
	var owner := _status_subject()
	pending = not owner.is_empty() and SaveManager.account_deletion_state(owner) in ["pending", "retired"]


func _set_status(message: String) -> void:
	status = message
	_refresh_pending()
	state_changed.emit()
