extends Node
## Hermetic real-client transport tests; no provider, browser or native UI.

const REQUEST_ID := "b19ce5a7-8257-4e02-96d5-4f8e9928bdf4"
const OTHER_ID := "664b8715-226d-4894-a43d-e8c05d5c97a1"
const CODE := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ"

class IOSHelper extends RefCounted:
	signal auth_session_started(request_id: String)
	signal auth_session_finished(request_id: String, outcome: String)
	signal auth_session_authorized(request_id: String, callback_code: String)
	var begun: Array[Dictionary] = []
	var ended: Array[String] = []
	func begin_auth_session(url: String, request_id: String) -> void:
		begun.append({"url": url, "request_id": request_id})
	func end_auth_session(request_id: String) -> void:
		ended.append(request_id)
		auth_session_finished.emit(request_id, "cancelled")

class LegacyHelper extends RefCounted:
	signal auth_session_started(request_id: String)
	signal auth_session_finished(request_id: String, outcome: String)
	func begin_auth_session(_url: String, _request_id: String) -> void:
		pass
	func end_auth_session(_request_id: String) -> void:
		pass

class Client extends "res://scripts/commerce/native_auth_client.gd":
	var helper := IOSHelper.new()
	var requests: Array[Dictionary] = []
	func _uses_ios_presentation() -> bool:
		return true
	func _ensure_ios_helper() -> bool:
		return _bind_ios_helper(helper)
	func _request(path: String, body: Dictionary, callback: Callable) -> void:
		requests.append({"path": path, "body": body.duplicate(true), "callback": callback})
	func deliver(index: int, ok: bool, payload: Dictionary) -> void:
		requests[index]["callback"].call(ok, payload)
	func count_requests(path: String) -> int:
		return requests.filter(func(item: Dictionary) -> bool: return item["path"] == path).size()

class OfflineCommerce extends "res://scripts/commerce/commerce_client.gd":
	func _ready() -> void:
		set_process(false)
	func _dispatch_request(_method: String, _path: String, _body: Dictionary, _token: String, callback: Callable) -> void:
		callback.call(false, {"error": "test_transport_blocked"})

var passed := 0
var failed := 0

func _ready() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false) or not String(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("waddle-wars-"):
		push_error("Native auth fixture requires isolated user data")
		get_tree().quit(2)
		return
	CommerceClient.set_script(OfflineCommerce)
	SaveManager.data = SaveManager.default_save()
	_test_start_contract()
	_test_callback_binding()
	_test_exchange_once()
	_test_cancel_and_expiry()
	print("[native_ios_auth_v2] %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)

func _client() -> Client:
	var client := Client.new()
	add_child(client)
	client.sign_in()
	return client

func _start_payload() -> Dictionary:
	return {"request_id": REQUEST_ID, "presentation": "ios", "flow_version": 2,
		"authorize_url": "https://waddlewars.io/api/commerce/native-auth/authorize-ios-v2?request_id=" + REQUEST_ID,
		"expires_in": 300, "interval": 3}

func _started() -> Client:
	var client := _client()
	client.deliver(0, true, _start_payload())
	client.helper.auth_session_started.emit(REQUEST_ID)
	return client

func _dispose(client: Client) -> void:
	client._cancel_local()
	client.free()

func _test_start_contract() -> void:
	var client := _client()
	check("iOS sends explicit v2 and PKCE challenge", client.requests.size() == 1 and client.requests[0]["path"] == "/start" and client.requests[0]["body"].get("flow_version") == 2 and client.requests[0]["body"].get("presentation") == "ios" and String(client.requests[0]["body"].get("challenge")).length() == 43)
	check("legacy plugin lacks required callback capability", not client._bind_ios_helper(LegacyHelper.new()))
	client.deliver(0, true, _start_payload())
	check("valid v2 presents exact authorization URL", client.helper.begun.size() == 1 and client.helper.begun[0]["url"] == _start_payload()["authorize_url"])
	check("iOS exposes no device code or code-matching instructions", client.connection_code.is_empty() and not client.status.to_lower().contains("code"))
	client._poll_authorization()
	check("before native start no token request", client.count_requests("/token") == 0)
	client.helper.auth_session_started.emit(REQUEST_ID)
	client._poll_authorization()
	check("started auth sheet never polls for token", client._ios_start_confirmed and client._poll_timer.is_stopped() and client.count_requests("/token") == 0)
	_dispose(client)
	for mode: String in ["missing_version", "old_version", "string_version", "legacy_url", "wrong_origin", "wrong_presentation"]:
		client = _client()
		var reply := _start_payload()
		match mode:
			"missing_version": reply.erase("flow_version")
			"old_version": reply["flow_version"] = 1
			"string_version": reply["flow_version"] = "2"
			"legacy_url": reply["authorize_url"] = String(reply["authorize_url"]).replace("authorize-ios-v2", "authorize-ios")
			"wrong_origin": reply["authorize_url"] = String(reply["authorize_url"]).replace("waddlewars.io", "attacker.invalid")
			"wrong_presentation": reply["presentation"] = "browser"
		client.deliver(0, true, reply)
		check("no downgrade: " + mode, not client.pending and client.helper.begun.is_empty() and client.count_requests("/token") == 0 and client._verifier.is_empty())
		_dispose(client)

func _test_callback_binding() -> void:
	var client := _started()
	client.helper.auth_session_authorized.emit(OTHER_ID, CODE)
	check("wrong request callback ignored", client.pending and not client._ios_terminal_received and client.count_requests("/token") == 0)
	client._ios_generation -= 1
	client.helper.auth_session_authorized.emit(REQUEST_ID, CODE)
	check("stale generation callback ignored", not client._ios_terminal_received and client.count_requests("/token") == 0)
	client._ios_generation = client._generation
	client.helper.auth_session_finished.emit(REQUEST_ID, "returned")
	check("legacy no-code return fails closed", not client.pending and client.count_requests("/token") == 0)
	_dispose(client)
	for bad: String in ["", "a".repeat(42), "a".repeat(44), "a".repeat(42) + "=", "a".repeat(42) + "/", "a".repeat(42) + "+", "a".repeat(42) + "é"]:
		client = _started()
		client.helper.auth_session_authorized.emit(REQUEST_ID, bad)
		check("malformed callback code rejects before exchange", not client.pending and client.count_requests("/token") == 0 and client._ios_callback_code.is_empty())
		_dispose(client)
	client = _client()
	client.deliver(0, true, _start_payload())
	client.helper.auth_session_authorized.emit(REQUEST_ID, CODE)
	check("callback before presenter started fails closed", not client.pending and client.count_requests("/token") == 0)
	_dispose(client)

func _test_exchange_once() -> void:
	var client := _started()
	var statuses: Array[String] = []
	client.status_changed.connect(func(message: String) -> void: statuses.append(message))
	var verifier := client._verifier
	client.helper.auth_session_authorized.emit(REQUEST_ID, CODE)
	check("callback authorizes exactly one PKCE plus code request", client.count_requests("/token") == 1 and client.requests[1]["body"] == {"request_id": REQUEST_ID, "verifier": verifier, "callback_code": CODE})
	check("callback secret removed from client field after dispatch", client._ios_callback_code.is_empty() and client._ios_exchange_sent)
	check("code never enters status or account snapshot", not str(statuses).contains(CODE) and not str(client.account_snapshot()).contains(CODE) and client.connection_code.is_empty())
	client.helper.auth_session_authorized.emit(REQUEST_ID, CODE)
	client.helper.auth_session_finished.emit(REQUEST_ID, "cancelled")
	client._poll_authorization()
	check("duplicate callback cannot issue second exchange", client.pending and client.count_requests("/token") == 1)
	client.deliver(1, true, {"token": "fixture-token", "user_id": "fixture-native-v2", "expires_in": 60})
	check("server success finishes and accepts account", not client.pending and client.signed_in() and client.helper.ended == [REQUEST_ID])
	check("teardown callback preserves accepted account", client.user_id == "fixture-native-v2" and client._ios_callback_code.is_empty() and client._poll_timer.is_stopped())
	client.sign_out(false)
	_dispose(client)
	for error: String in ["network_unavailable", "authorization_pending", "auth_session_unavailable", "invalid_auth_request"]:
		client = _started()
		client.helper.auth_session_authorized.emit(REQUEST_ID, CODE)
		client.deliver(1, false, {"error": error})
		client._poll_authorization()
		check("uncertain/failed code never retried: " + error, not client.pending and not client.signed_in() and client.count_requests("/token") == 1 and client._poll_timer.is_stopped() and client._verifier.is_empty())
		client.deliver(1, true, {"token": "late-token", "user_id": "fixture-native-v2", "expires_in": 60})
		check("late failed-exchange success stays rejected", not client.signed_in())
		_dispose(client)

func _test_cancel_and_expiry() -> void:
	var client := _started()
	client.cancel_sign_in()
	client.helper.auth_session_authorized.emit(REQUEST_ID, CODE)
	check("cancel before callback revokes and ignores late secret", not client.pending and client.count_requests("/cancel") == 1 and client.count_requests("/token") == 0 and client._verifier.is_empty())
	_dispose(client)
	client = _started()
	client.helper.auth_session_authorized.emit(REQUEST_ID, CODE)
	client.cancel_sign_in()
	client.deliver(1, true, {"token": "late-token", "user_id": "fixture-native-v2", "expires_in": 60})
	check("cancel during exchange rejects late JWT", not client.signed_in() and not client.pending and client._ios_callback_code.is_empty())
	_dispose(client)
	client = _started()
	client._expires_at_ms = Time.get_ticks_msec() - 1
	client.helper.auth_session_authorized.emit(REQUEST_ID, CODE)
	check("expired request does not exchange callback", not client.pending and client.count_requests("/token") == 0 and client._verifier.is_empty())
	_dispose(client)
	client = _started()
	client._on_presentation_timeout()
	check("native presentation timeout clears pending secrets", not client.pending and client.count_requests("/cancel") == 1 and client._ios_callback_code.is_empty())
	_dispose(client)

func check(label: String, ok: bool) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("[native_ios_auth_v2] %s %s" % ["PASS" if ok else "FAIL", label])
