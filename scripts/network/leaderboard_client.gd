extends Node
## Optional online leaderboard client (Cloudflare Worker + D1, Clerk auth).
##
## Everything degrades gracefully: the game is fully playable signed out and
## offline. Viewing boards works anywhere HTTP works; posting scores requires
## Clerk sign-in, which is only available in the web build (Clerk JS lives in
## the export page — see export_presets.cfg head_include).

signal auth_changed

const API_BASE: String = "https://waddle-wars-leaderboard.ninjaconsultingllc.workers.dev"
const AUTH_POLL_INTERVAL: float = 1.0

var signed_in: bool = false
var display_name: String = ""

var _token: String = ""
var _poll_accum: float = 0.0


func _ready() -> void:
	set_process(can_sign_in())


func _process(delta: float) -> void:
	_poll_accum += delta
	if _poll_accum < AUTH_POLL_INTERVAL:
		return
	_poll_accum = 0.0
	_sync_web_auth()


## Sign-in requires the Clerk JS bundle, which only exists in the web export.
func can_sign_in() -> bool:
	return OS.has_feature("web") and not GameConfig.is_headless()


func sign_in() -> void:
	if can_sign_in():
		JavaScriptBridge.eval("window.__ww_auth && window.__ww_auth.signIn()", true)


func sign_out() -> void:
	if can_sign_in():
		JavaScriptBridge.eval("window.__ww_auth && window.__ww_auth.signOut()", true)


func _sync_web_auth() -> void:
	var raw: Variant = JavaScriptBridge.eval("JSON.stringify(window.__ww_auth || {})", true)
	if not (raw is String):
		return
	var parsed: Variant = JSON.parse_string(raw as String)
	if not (parsed is Dictionary):
		return
	var state := parsed as Dictionary
	var was := signed_in
	signed_in = bool(state.get("signedIn", false))
	display_name = String(state.get("name", ""))
	_token = String(state.get("token", ""))
	if was != signed_in:
		auth_changed.emit()


## Fetch top entries. cb receives (ok: bool, data: Dictionary) where data has
## "entries": [{rank, name, value}] and optional "me": {rank, value}.
func fetch_board(mode: String, course: String, limit: int, cb: Callable) -> void:
	var url := "%s/api/leaderboard?mode=%s&course=%s&limit=%d" % [API_BASE, mode, course, limit]
	var headers := PackedStringArray()
	if _token != "":
		headers.append("Authorization: Bearer %s" % _token)
	_request(url, HTTPClient.METHOD_GET, headers, "", cb)


## Post a personal best. cb receives (ok, data) with data holding
## {improved, best, rank, name} on success.
func submit_score(mode: String, course: String, value: int, cb: Callable) -> void:
	if _token == "":
		cb.call(false, {"error": "not signed in"})
		return
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % _token,
	])
	var body := JSON.stringify({"mode": mode, "course": course, "value": value})
	_request("%s/api/scores" % API_BASE, HTTPClient.METHOD_POST, headers, body, cb)


func _request(url: String, method: HTTPClient.Method, headers: PackedStringArray, body: String, cb: Callable) -> void:
	var req := HTTPRequest.new()
	req.timeout = 10.0
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, bytes: PackedByteArray) -> void:
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
			cb.call(false, {"error": "http %d (result %d)" % [code, result]})
			return
		var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if parsed is Dictionary:
			cb.call(true, parsed as Dictionary)
		else:
			cb.call(false, {"error": "bad response"}))
	var err := req.request(url, headers, method, body)
	if err != OK:
		req.queue_free()
		cb.call(false, {"error": "request error %d" % err})


static func format_value(mode: String, value: int) -> String:
	if mode == "time":
		return RaceHUD.format_time(float(value) / 1000.0)
	return str(value)
