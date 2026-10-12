extends Node
## PKCE sign-in: native iOS auth session; Android uses its existing browser flow.
## Only active authentication uses timers or HTTP.
## Verifier and access token stay in memory; no plaintext credentials in saves.
## Server validates the Clerk session before every refresh and authorization.

signal auth_changed
signal status_changed(message: String)

const API_BASE: String = "https://waddlewars.io"
const CLERK_ISSUER: String = "https://clerk.waddlewars.io"

var pending: bool = false
var user_id: String = ""
var status: String = ""
var connection_code: String = ""
var _token: String = ""
var _verifier: String = ""
var _request_id: String = ""
var _expires_at_ms: int = 0
var _generation: int = 0
var _poll_timer: Timer = null
var _refresh_timer: Timer = null
var _refresh_failures: int = 0
var _ios_auth: Object = null
var _ios_request_id: String = ""
var _ios_generation: int = -1
var _ios_start_confirmed: bool = false
var _ios_terminal_received: bool = false
var _ios_callback_code: String = ""
var _ios_exchange_sent: bool = false
var _presentation_timer: Timer = null
var _poll_in_flight: bool = false
var _last_poll_at_ms: int = -1
var _poll_interval_ms: int = 3000


func _ready() -> void:
	set_process(false)
	process_mode = Node.PROCESS_MODE_ALWAYS


## In-memory bridge consumed by LeaderboardClient; never serialize to saves.
func account_snapshot() -> Dictionary:
	return {"ready": true, "pending": pending, "signedIn": signed_in(),
		"token": _token if signed_in() else "", "name": "", "identityEpoch": 0,
		"status": status, "error": _status_error()}


func signed_in() -> bool:
	return not _token.is_empty() and not user_id.is_empty()


func suspend_account_subject(owner: String) -> void:
	if owner != user_id:
		return
	# Keep the current token solely for explicit lifecycle status. Invalidate
	# older refresh completions before they can reconnect the commerce session.
	_generation += 1
	if _refresh_timer != null:
		_refresh_timer.stop()


func resume_account_subject(owner: String) -> void:
	if owner == user_id and signed_in() and SaveManager.account_deletion_state(owner).is_empty():
		_generation += 1
		_refresh_session()


func sign_in() -> void:
	if GameConfig.native_offline_mvp() and not GameConfig.native_accounts_enabled():
		_set_status("This edition plays and saves progress offline. No account is needed.")
		return
	if OS.has_feature("web") or pending or signed_in():
		return
	var ios := _uses_ios_presentation()
	if ios and not _ensure_ios_helper():
		_set_status("Account sign-in unavailable on this build. You can still play and earn cosmetics offline.")
		return
	_generation += 1
	var generation := _generation
	pending = true
	_verifier = Marshalls.raw_to_base64(Crypto.new().generate_random_bytes(32)).replace("+", "-").replace("/", "_").trim_suffix("=")
	_request_id = ""
	_last_poll_at_ms = -1
	_poll_in_flight = false
	connection_code = ""
	_ensure_timers()
	_set_status("Opening secure account sign-in…" if ios else "Opening account sign-in in your browser…")
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(_verifier.to_utf8_buffer())
	var challenge := Marshalls.raw_to_base64(hash.finish()).replace("+", "-").replace("/", "_").trim_suffix("=")
	var body := {"challenge": challenge}
	if ios:
		body["presentation"] = "ios"
		body["flow_version"] = 2
	_request("/start", body, func(ok: bool, payload: Dictionary) -> void:
		if generation != _generation:
			return
		if not ok:
			_cancel_local()
			_set_status("Account sign-in unavailable. You can still play and earn cosmetics offline.")
			return
		var request_id := String(payload.get("request_id", ""))
		var base := _base_url()
		var route := "authorize-ios-v2" if ios else "authorize"
		var expected_url := "%s/api/commerce/native-auth/%s?request_id=%s" % [base, route, request_id]
		var url := String(payload.get("authorize_url", ""))
		var flow_version: Variant = payload.get("flow_version")
		var ios_v2 := (flow_version is int or flow_version is float) and float(flow_version) == 2.0
		if not _valid_request_id(request_id) or url != expected_url or String(payload.get("presentation", "")) != ("ios" if ios else "browser") \
			or (ios and not ios_v2):
			_cancel_local()
			_set_status("Account sign-in unavailable. Try again.")
			return
		_request_id = request_id
		connection_code = "" if ios else request_id.left(8).to_upper()
		_expires_at_ms = Time.get_ticks_msec() + mini(int(payload.get("expires_in", 0)), 300) * 1000
		_poll_interval_ms = maxi(int(payload.get("interval", 3)) * 1000, 3000)
		_poll_timer.wait_time = float(_poll_interval_ms) / 1000.0
		if _expires_at_ms <= Time.get_ticks_msec():
			cancel_sign_in()
			_set_status("Account sign-in expired. Try again.")
			return
		if ios:
			_ios_request_id = request_id
			_ios_generation = generation
			_ios_start_confirmed = false
			_ios_terminal_received = false
			_ios_callback_code = ""
			_ios_exchange_sent = false
			_presentation_timer.wait_time = minf(float(_expires_at_ms - Time.get_ticks_msec()) / 1000.0, 15.0)
			_presentation_timer.start()
			_set_status("Sign in in the secure account sheet.")
			_ios_auth.call("begin_auth_session", url, request_id)
		else:
			# Only non-iOS editions use the existing external-browser flow.
			if OS.shell_open(url) != OK:
				cancel_sign_in()
				_set_status("Could not open account sign-in. Try again.")
				return
			_set_status("Match connection code %s in your browser, connect your account, then return here." % connection_code)
			_poll_timer.start())


func cancel_sign_in() -> void:
	var request_id := _request_id
	var verifier := _verifier
	_cancel_local()
	if not request_id.is_empty() and not verifier.is_empty():
		_request("/cancel", {"request_id": request_id, "verifier": verifier}, func(_ok: bool, _payload: Dictionary) -> void: pass)
	_set_status("Sign-in cancelled.")


func sign_out(clear_offline: bool = true) -> void:
	var request_id := _request_id
	var verifier := _verifier
	_cancel_local()
	_token = ""
	user_id = ""
	if _refresh_timer != null:
		_refresh_timer.stop()
	var commerce := get_node_or_null("/root/CommerceClient")
	if commerce != null:
		commerce.call("configure_native_session", "", "")
		if clear_offline:
			commerce.call("clear_offline_account")
	if not request_id.is_empty() and not verifier.is_empty():
		_request("/cancel", {"request_id": request_id, "verifier": verifier}, func(_ok: bool, _payload: Dictionary) -> void: pass)
	auth_changed.emit()
	_set_status("Signed out on this device.")


func _ensure_timers() -> void:
	if _poll_timer == null:
		_poll_timer = Timer.new()
		_poll_timer.one_shot = true
		_poll_timer.timeout.connect(_poll_authorization)
		add_child(_poll_timer)
	if _refresh_timer == null:
		_refresh_timer = Timer.new()
		_refresh_timer.one_shot = true
		_refresh_timer.timeout.connect(_refresh_session)
		add_child(_refresh_timer)
	if _presentation_timer == null:
		_presentation_timer = Timer.new()
		_presentation_timer.one_shot = true
		_presentation_timer.timeout.connect(_on_presentation_timeout)
		add_child(_presentation_timer)


func _ensure_ios_helper() -> bool:
	if _ios_auth != null:
		return _bind_ios_helper(_ios_auth)
	if not Engine.has_singleton("WaddleStoreKit"):
		return false
	return _bind_ios_helper(Engine.get_singleton("WaddleStoreKit"))


func _uses_ios_presentation() -> bool:
	return OS.has_feature("ios")


func _bind_ios_helper(helper: Object) -> bool:
	if helper == null or not _has_string_signature(helper.get_method_list(), "begin_auth_session", 2) \
		or not _has_string_signature(helper.get_method_list(), "end_auth_session", 1) \
		or not _has_string_signature(helper.get_signal_list(), "auth_session_started", 1) \
		or not _has_string_signature(helper.get_signal_list(), "auth_session_finished", 2) \
		or not _has_string_signature(helper.get_signal_list(), "auth_session_authorized", 2):
		return false
	_ios_auth = helper
	for connection: Array in [["auth_session_started", _on_ios_session_started], ["auth_session_finished", _on_ios_session_finished],
		["auth_session_authorized", _on_ios_session_authorized]]:
		if not helper.is_connected(StringName(connection[0]), connection[1]):
			helper.connect(StringName(connection[0]), connection[1])
	return true


static func _has_string_signature(entries: Array, name: String, count: int) -> bool:
	for entry: Variant in entries:
		if not entry is Dictionary or String(entry.get("name", "")) != name:
			continue
		var args: Variant = entry.get("args", [])
		if not args is Array or args.size() != count:
			return false
		for argument: Variant in args:
			if not argument is Dictionary or int(argument.get("type", -1)) != TYPE_STRING:
				return false
		return true
	return false


static func _valid_request_id(value: String) -> bool:
	if value.length() != 36 or value[8] != "-" or value[13] != "-" or value[18] != "-" or value[23] != "-":
		return false
	for index: int in value.length():
		if index in [8, 13, 18, 23]:
			continue
		if not value[index] in "0123456789abcdef":
			return false
	return value[14] in "12345" and value[19] in "89ab"


static func _valid_callback_code(value: String) -> bool:
	if value.length() != 43:
		return false
	for character: String in value:
		if not character in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-":
			return false
	return true


func _current_ios_request(request_id: String) -> bool:
	return pending and not request_id.is_empty() and request_id == _ios_request_id \
		and request_id == _request_id and _ios_generation == _generation


func _on_ios_session_started(request_id: String) -> void:
	if not _current_ios_request(request_id) or _ios_start_confirmed or _ios_terminal_received:
		return
	_ios_start_confirmed = true
	_presentation_timer.wait_time = maxf(float(_expires_at_ms - Time.get_ticks_msec()) / 1000.0, 0.1)
	_presentation_timer.start()
	# Unlike device linking, iOS v2 cannot exchange by polling. Only the
	# callback received by this exact native session supplies the second proof.


func _on_ios_session_finished(request_id: String, outcome: String) -> void:
	if not _current_ios_request(request_id) or _ios_terminal_received:
		return
	_ios_terminal_received = true
	cancel_sign_in()
	_set_status("Sign-in cancelled." if outcome == "cancelled" else "Could not complete secure sign-in. Try again.")


func _on_ios_session_authorized(request_id: String, callback_code: String) -> void:
	if not _current_ios_request(request_id) or _ios_terminal_received:
		return
	_ios_terminal_received = true
	if not _ios_start_confirmed or not _valid_callback_code(callback_code):
		cancel_sign_in()
		_set_status("Could not complete secure sign-in. Try again.")
		return
	_ios_callback_code = callback_code
	_set_status("Finishing secure sign-in…")
	_poll_authorization()


func _on_presentation_timeout() -> void:
	if not pending or _ios_request_id.is_empty():
		return
	var started := _ios_start_confirmed
	cancel_sign_in()
	_set_status("Sign-in expired. Start again when ready." if started else "Could not open secure sign-in. Try again.")


func _end_ios_presentation() -> void:
	var request_id := _ios_request_id
	_ios_request_id = ""
	_ios_generation = -1
	_ios_start_confirmed = false
	_ios_terminal_received = false
	_ios_callback_code = ""
	_ios_exchange_sent = false
	if _presentation_timer != null:
		_presentation_timer.stop()
	# Clear guards before calling the plugin: a synchronous cancellation signal
	# from native teardown must not undo an already accepted server token.
	if not request_id.is_empty() and _ios_auth != null:
		_ios_auth.call("end_auth_session", request_id)


func _poll_authorization() -> void:
	if not pending:
		return
	var ios := not _ios_request_id.is_empty()
	if ios and (not _ios_start_confirmed or not _ios_terminal_received \
		or not _valid_callback_code(_ios_callback_code) or _ios_exchange_sent):
		return
	if Time.get_ticks_msec() >= _expires_at_ms:
		cancel_sign_in()
		_set_status("Sign-in expired. Start again when ready.")
		return
	if _poll_in_flight:
		return
	var elapsed := Time.get_ticks_msec() - _last_poll_at_ms
	if not ios and _last_poll_at_ms >= 0 and elapsed < _poll_interval_ms:
		_poll_timer.wait_time = float(_poll_interval_ms - elapsed) / 1000.0
		_poll_timer.start()
		return
	var generation := _generation
	var request_id := _request_id
	_poll_in_flight = true
	_last_poll_at_ms = Time.get_ticks_msec()
	var body := {"request_id": request_id, "verifier": _verifier}
	if ios:
		body["callback_code"] = _ios_callback_code
		_ios_callback_code = ""
		_ios_exchange_sent = true
	_request("/token", body, func(ok: bool, payload: Dictionary) -> void:
		if generation != _generation or not pending or request_id != _request_id:
			return
		_poll_in_flight = false
		# v2 codes are single-use. An uncertain/lost response requires a new
		# sign-in; replaying the code must never turn into verifier-only polling.
		if not ios and not ok and String(payload.get("error", "")) in ["authorization_pending", "network_unavailable", "auth_session_unavailable"]:
			_poll_timer.wait_time = float(_poll_interval_ms) / 1000.0
			_poll_timer.start()
			return
		if not ok or not _accept_token(payload):
			cancel_sign_in()
			_set_status("Could not connect your account. Start sign-in again.")
			return
		_end_ios_presentation()
		pending = false
		_poll_timer.stop()
		_set_status("Account connected.")
		auth_changed.emit()
		var commerce := get_node_or_null("/root/CommerceClient")
		if commerce != null:
			commerce.call("refresh_store"))


## Explicit same-owner renewal used only after renewed deletion confirmation.
## Ordinary refresh/cloud/score writes stay fenced while deletion is pending.
func refresh_for_account_deletion(expected_owner: String, completion: Callable) -> void:
	if not signed_in() or user_id != expected_owner \
		or SaveManager.account_deletion_state(expected_owner) != "pending" \
		or _request_id.is_empty() or _verifier.is_empty():
		if completion.is_valid(): completion.call(false)
		return
	var generation := _generation
	_request("/refresh", {"request_id": _request_id, "verifier": _verifier}, func(ok: bool, payload: Dictionary) -> void:
		var accepted := generation == _generation and user_id == expected_owner \
			and SaveManager.account_deletion_state(expected_owner) == "pending" \
			and ok and String(payload.get("user_id", "")) == expected_owner
		if accepted:
			accepted = _accept_token(payload)
			if _refresh_timer != null: _refresh_timer.stop()
		if completion.is_valid(): completion.call(accepted))


func _refresh_session() -> void:
	if not signed_in() or not SaveManager.account_deletion_state(user_id).is_empty():
		return
	var generation := _generation
	_request("/refresh", {"request_id": _request_id, "verifier": _verifier}, func(ok: bool, payload: Dictionary) -> void:
		if generation != _generation:
			return
		if ok and String(payload.get("user_id", "")) == user_id and _accept_token(payload):
			_refresh_failures = 0
			return
		_refresh_failures += 1
		if String(payload.get("error", "")) in ["auth_session_invalid", "unauthorized", "account_retired"] or _refresh_failures >= 3:
			sign_out(false)
			_set_status("Account session expired. Sign in again to reconnect.")
		else:
			_refresh_timer.wait_time = 10.0
			_refresh_timer.start())


func _accept_token(payload: Dictionary) -> bool:
	var token := String(payload.get("token", ""))
	var next_user := String(payload.get("user_id", ""))
	var lifetime := int(payload.get("expires_in", 0))
	if token.is_empty() or next_user.is_empty() or lifetime < 5 \
		or SaveManager.account_deletion_state(next_user) in ["retired", "unavailable"]:
		return false
	if GameConfig.native_accounts_enabled() and not _token_matches_account(token, next_user):
		return false
	_token = token
	user_id = next_user
	_refresh_failures = 0
	_ensure_timers()
	_refresh_timer.wait_time = maxf(minf(float(lifetime) - 10.0, 50.0), 3.0)
	_refresh_timer.start()
	var commerce := get_node_or_null("/root/CommerceClient")
	if commerce != null:
		commerce.call("configure_native_session", _token, user_id)
	return true


static func _token_matches_account(token: String, owner: String) -> bool:
	var parts := token.split(".")
	if parts.size() != 3:
		return false
	var encoded := parts[1].replace("-", "+").replace("_", "/")
	while encoded.length() % 4 != 0:
		encoded += "="
	var claims: Variant = JSON.parse_string(Marshalls.base64_to_utf8(encoded))
	return claims is Dictionary and claims.get("iss") == CLERK_ISSUER \
		and claims.get("sub") == owner


func _cancel_local() -> void:
	_generation += 1
	pending = false
	_poll_in_flight = false
	_end_ios_presentation()
	_request_id = ""
	_verifier = ""
	connection_code = ""
	if _poll_timer != null:
		_poll_timer.stop()
	auth_changed.emit()


func _request(path: String, body: Dictionary, callback: Callable) -> void:
	var base := _base_url()
	if not base.begins_with("https://"):
		callback.call(false, {"error": "native_auth_unavailable"})
		return
	var http := HTTPRequest.new()
	http.timeout = 12.0
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
		http.queue_free()
		var raw: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		var payload: Dictionary = raw if raw is Dictionary else {"error": "network_unavailable"}
		callback.call(result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300, payload))
	var error := http.request("%s/api/commerce/native-auth%s" % [base, path],
		PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK:
		http.queue_free()
		callback.call(false, {"error": "network_unavailable"})


func _base_url() -> String:
	return String(ProjectSettings.get_setting("account/auth_api_base", API_BASE)).trim_suffix("/")


func _status_error() -> String:
	if pending or signed_in() or status.is_empty() or status in ["Sign-in cancelled.", "Signed out on this device."]:
		return ""
	return "native_auth"


func _set_status(message: String) -> void:
	status = message
	status_changed.emit(message)
