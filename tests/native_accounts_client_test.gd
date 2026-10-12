extends Node
## No network, no native session presentation. Shared account entry-point contract.

class NativeFixture extends Node:
	var starts: int = 0
	var stops: int = 0
	var state: Dictionary = {"ready": true, "pending": false, "signedIn": false, "token": "", "name": "", "identityEpoch": 0}
	func sign_in() -> void:
		starts += 1
		state["pending"] = true
	func sign_out() -> void:
		stops += 1
		state["pending"] = false
		state["signedIn"] = false
		state["token"] = ""
	func account_snapshot() -> Dictionary:
		return state.duplicate()

class ClientFixture extends "res://scripts/network/leaderboard_client.gd":
	var native: NativeFixture
	var requests: Array[Dictionary] = []
	func _ready() -> void:
		set_process(false)
	func _uses_native_auth() -> bool:
		return true
	func _native_auth_provider() -> Node:
		return native
	func _dispatch_request(method: String, url: String, body: String, cb: Callable) -> void:
		requests.append({"method": method, "url": url, "body": body, "callback": cb})

var passed: int = 0
var failed: int = 0

func _ready() -> void:
	var native := NativeFixture.new()
	var client := ClientFixture.new()
	client.native = native
	add_child(native)
	add_child(client)
	var changes: Array[int] = [0]
	client.auth_changed.connect(func() -> void: changes[0] += 1)
	client.sign_in()
	check("shared sign-in calls native presenter once", native.starts == 1)
	check("native presentation remains pending", client.sign_in_pending and not client.signed_in)
	client._sync_native_auth()
	check("pending polls do not produce repeated identity changes", changes[0] == 1)
	var owner := "user_syntheticNative"
	var token := jwt({"iss": "https://clerk.waddlewars.io", "sub": owner})
	native.state.merge({"signedIn": true, "pending": false, "token": token}, true)
	client._sync_native_auth()
	check("native credential reaches shared account client", client.signed_in and client._token == token and client._auth_owner_id == owner)
	check("completed sign-in clears pending exactly once", not client.sign_in_pending and changes[0] == 2)
	check("provider name is never published automatically", client.display_name.is_empty())
	var before := client._auth_generation
	native.state["token"] = jwt({"iss": "https://clerk.waddlewars.io", "sub": owner, "fresh": true})
	client._sync_native_auth()
	check("native refresh updates credential without changing owner generation", client._token != token and client._auth_generation == before)
	client.submit_score("runner", "runner", 1234, func(_ok: bool, _body: Dictionary) -> void: pass)
	check("native authenticated score uses normal protected HTTP dispatch", client.requests.size() == 1 and client.requests[0]["method"] == "POST")
	var old_request: Callable = client.requests[0]["callback"]
	client.sign_out()
	check("shared sign-out calls native revocation and clears token", native.stops == 1 and not client.signed_in and client._token.is_empty())
	old_request.call(true, {"ok": true, "best": 1234, "rank": 1, "name": "Penguin"})
	check("late native score response cannot restore signed-out account", not client.signed_in and client.score_submission_status("runner", "runner") == "idle")
	# Terminal failures and cancellation update the same account UI, without
	# provider strings or repeated polling notifications.
	native.state.merge({"pending": false, "status": "Could not connect your account. Start sign-in again.", "error": "native_auth"}, true)
	client._sync_native_auth()
	check("native failure exposes retry state and safe status", client.auth_error == "native_auth" and not client.sign_in_pending and client.auth_status.begins_with("Could not connect"))
	native.state.merge({"pending": false, "status": "Sign-in cancelled.", "error": ""}, true)
	client._sync_native_auth()
	check("cancellation returns button to idle", not client.sign_in_pending and client.auth_error.is_empty() and client.auth_status == "Sign-in cancelled.")
	var notifications := changes[0]
	client._sync_native_auth()
	check("settled status does not notify every poll", changes[0] == notifications)
	native.state.merge({"signedIn": true, "token": token, "status": "Account connected."}, true)
	client._sync_native_auth()
	client.requests.clear()
	client._load_public_name()
	check("native profile is fetched using protected endpoint", client.requests.size() == 1 and client.requests[0]["url"].ends_with("/api/profile"))
	client.requests[0]["callback"].call(true, {"name": "Ice Explorer"})
	check("native custom name used independently of private provider name", client.player_display_name() == "Ice Explorer" and client.display_name.is_empty())
	client._sync_native_auth()
	check("auth polling preserves public profile name", client.player_display_name() == "Ice Explorer")
	client.requests.clear()
	client._on_auth_changed_sync()
	check("native cloud pull asks for conditional save protocol", client.requests.size() == 1 and client.requests[0]["url"].ends_with("/api/save?sync=2"))
	client.requests[0]["callback"].call(true, {"exists": false})
	check("native cloud never overwrites through legacy server", client.cloud_sync_status() == "unavailable" and client.requests.size() == 1)
	var saved_data := SaveManager.data.duplicate(true)
	SaveManager.data = SaveManager.default_save()
	client.cloud_sync_error = false
	client._on_auth_changed_sync()
	client.requests[1]["callback"].call(true, {"exists": false, "sync_protocol": 2, "revision": "absent"})
	check("native reconciled progress is pushed with CAS", client.requests.size() == 3 and client.requests[2]["method"] == "PUT" and JSON.parse_string(client.requests[2]["body"]).get("base_revision") == "absent")
	client.requests[2]["callback"].call(true, {"ok": true, "sync_protocol": 2, "revision": "a".repeat(64)})
	check("native confirmed cloud save reports saved", client.cloud_sync_status() == "saved")
	SaveManager.data = saved_data
	check("production native token exact issuer accepted", NativeAuthClient._token_matches_account(token, owner))
	check("development native token rejected", not NativeAuthClient._token_matches_account(jwt({"iss": "https://stunning-hen-13.clerk.accounts.dev", "sub": owner}), owner))
	check("mismatched native subject rejected", not NativeAuthClient._token_matches_account(token, "user_other"))
	check("malformed native token rejected", not NativeAuthClient._token_matches_account("not-a-jwt", owner))
	var conflict := client._decode_http_reply(HTTPRequest.RESULT_SUCCESS, 409, '{"error":"save_revision_conflict"}'.to_utf8_buffer())
	check("native HTTP409 keeps CAS conflict for recovery", not conflict["ok"] and conflict["payload"]["error"] == "save_revision_conflict")
	var malformed := client._decode_http_reply(HTTPRequest.RESULT_SUCCESS, 503, "<html>private provider details</html>".to_utf8_buffer())
	check("native HTTP errors never expose provider body", malformed["payload"]["error"] == "network_unavailable")
	var oversized := PackedByteArray()
	oversized.resize(1024 * 1024 + 1)
	check("native HTTP reply size bounded", not client._decode_http_reply(HTTPRequest.RESULT_SUCCESS, 200, oversized)["ok"])
	client.free()
	native.free()
	print("[native_accounts_client] %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)

func jwt(payload: Dictionary) -> String:
	var encoded := Marshalls.utf8_to_base64(JSON.stringify(payload)).replace("+", "-").replace("/", "_").trim_suffix("=")
	return "synthetic." + encoded + ".signature"

func check(label: String, ok: bool) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("[native_accounts_client] %s %s" % ["PASS" if ok else "FAIL", label])
