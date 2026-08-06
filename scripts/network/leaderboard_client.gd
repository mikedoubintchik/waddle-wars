extends Node
## Optional online layer (Cloudflare Worker + D1, Clerk auth): leaderboards,
## custom display name, and cloud save sync.
##
## Everything degrades gracefully: the game is fully playable signed out and
## offline. Viewing boards works anywhere HTTP works; posting scores and cloud
## saves require Clerk sign-in (web build only — Clerk JS lives in the export
## page, see export_presets.cfg head_include).
##
## On web, requests go through the page's __ww_api fetch bridge instead of
## HTTPRequest — Godot's web HTTP path proved flaky in the field.

signal auth_changed
signal cloud_save_restored

const API_BASE: String = "https://waddle-wars-leaderboard.ninjaconsultingllc.workers.dev"
const AUTH_POLL_INTERVAL: float = 0.5
const BRIDGE_POLL_INTERVAL: float = 0.12
const SAVE_PUSH_DEBOUNCE: float = 8.0

var signed_in: bool = false
var display_name: String = ""
## True from sign_in() until the page reports Clerk ready (bundle lazy-loads).
var sign_in_pending: bool = false

var _token: String = ""
var _poll_accum: float = 0.0
var _pending_bridge: Dictionary = {}  # js id -> Callable
var _bridge_accum: float = 0.0
var _save_push_timer: float = -1.0
var _synced_this_session: bool = false


func _ready() -> void:
	set_process(can_sign_in())
	if can_sign_in():
		auth_changed.connect(_on_auth_changed_sync)


func _process(delta: float) -> void:
	_poll_accum += delta
	if _poll_accum >= AUTH_POLL_INTERVAL:
		_poll_accum = 0.0
		_sync_web_auth()
	if not _pending_bridge.is_empty():
		_bridge_accum += delta
		if _bridge_accum >= BRIDGE_POLL_INTERVAL:
			_bridge_accum = 0.0
			_poll_bridge()
	if _save_push_timer > 0.0:
		_save_push_timer -= delta
		if _save_push_timer <= 0.0:
			_push_save_now()


## Sign-in requires the Clerk JS bundle, which only exists in the web export.
func can_sign_in() -> bool:
	return OS.has_feature("web") and not GameConfig.is_headless()


func sign_in() -> void:
	if can_sign_in():
		sign_in_pending = true
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
	if bool(state.get("ready", false)):
		sign_in_pending = false
	if was != signed_in:
		auth_changed.emit()


## --- Requests ---------------------------------------------------------------

## Fetch top entries. cb receives (ok: bool, data: Dictionary) where data has
## "entries": [{rank, name, value}] and optional "me": {rank, value}.
func fetch_board(mode: String, course: String, limit: int, cb: Callable) -> void:
	var url := "%s/api/leaderboard?mode=%s&course=%s&limit=%d" % [API_BASE, mode, course, limit]
	_request("GET", url, "", cb)


## Post a personal best. cb receives (ok, data) with data holding
## {improved, best, rank, name} on success.
func submit_score(mode: String, course: String, value: int, cb: Callable) -> void:
	if _token == "":
		cb.call(false, {"error": "not signed in"})
		return
	var body := {"mode": mode, "course": course, "value": value}
	var custom := String(SettingsManager.get_setting("online", "display_name"))
	if custom.strip_edges().length() >= 2:
		body["name"] = custom.strip_edges()
	_request("POST", "%s/api/scores" % API_BASE, JSON.stringify(body), cb)


## Set the public display name (updates existing board rows server-side).
func set_display_name(name_text: String, cb: Callable) -> void:
	if _token == "":
		cb.call(false, {"error": "not signed in"})
		return
	SettingsManager.set_setting("online", "display_name", name_text.strip_edges())
	_request("POST", "%s/api/profile" % API_BASE, JSON.stringify({"name": name_text}), cb)


## --- Cloud save -------------------------------------------------------------

## Called by SaveManager after each local write; debounced push while signed in.
func notify_save_written() -> void:
	if signed_in and can_sign_in() and _synced_this_session:
		_save_push_timer = SAVE_PUSH_DEBOUNCE


func _on_auth_changed_sync() -> void:
	if not signed_in:
		_synced_this_session = false
		return
	# First sign-in this session: pull the cloud save. A pristine local save
	# adopts the remote one; otherwise local wins and pushes up.
	_request("GET", "%s/api/save" % API_BASE, "", func(ok: bool, data: Dictionary) -> void:
		_synced_this_session = true
		if ok and bool(data.get("exists", false)) and _local_save_is_pristine():
			var parsed: Variant = JSON.parse_string(String(data.get("data", "")))
			if parsed is Dictionary:
				SaveManager.adopt_cloud_save(parsed as Dictionary)
				cloud_save_restored.emit()
				return
		_push_save_now())


func _local_save_is_pristine() -> bool:
	var stats: Variant = SaveManager.data.get("stats", {})
	var races := int((stats as Dictionary).get("races_finished", 0)) if stats is Dictionary else 0
	return int(SaveManager.data.get("fish", 0)) == 0 and races == 0


func _push_save_now() -> void:
	_save_push_timer = -1.0
	if _token == "":
		return
	_request("PUT", "%s/api/save" % API_BASE, JSON.stringify(SaveManager.data),
		func(_ok: bool, _data: Dictionary) -> void: pass)


## --- Transport --------------------------------------------------------------

func _request(method: String, url: String, body: String, cb: Callable) -> void:
	if OS.has_feature("web"):
		_request_via_bridge(method, url, body, cb)
	else:
		_request_via_http(method, url, body, cb)


static func _js_quote(s: String) -> String:
	return "\"%s\"" % s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")


func _request_via_bridge(method: String, url: String, body: String, cb: Callable) -> void:
	var js := "window.__ww_api ? window.__ww_api.start(%s, %s, %s, %s) : 0" % [
		_js_quote(method), _js_quote(url), _js_quote(_token), _js_quote(body),
	]
	var id: Variant = JavaScriptBridge.eval(js, true)
	var req_id := int(id) if id != null else 0
	if req_id <= 0:
		cb.call(false, {"error": "bridge unavailable"})
		return
	_pending_bridge[req_id] = cb


func _poll_bridge() -> void:
	var done: Array = []
	for req_id: int in _pending_bridge.keys():
		var raw: Variant = JavaScriptBridge.eval("window.__ww_api.poll(%d)" % req_id, true)
		if not (raw is String) or (raw as String).is_empty():
			continue
		done.append(req_id)
		var cb: Callable = _pending_bridge[req_id]
		var parsed: Variant = JSON.parse_string(raw as String)
		if not (parsed is Dictionary):
			cb.call(false, {"error": "bad bridge response"})
			continue
		var result := parsed as Dictionary
		var body_parsed: Variant = JSON.parse_string(String(result.get("body", "")))
		var payload: Dictionary = body_parsed if body_parsed is Dictionary else {"error": String(result.get("body", ""))}
		cb.call(bool(result.get("ok", false)), payload)
	for req_id: int in done:
		_pending_bridge.erase(req_id)


func _request_via_http(method: String, url: String, body: String, cb: Callable) -> void:
	var req := HTTPRequest.new()
	req.timeout = 10.0
	add_child(req)
	var http_method := HTTPClient.METHOD_GET
	match method:
		"POST": http_method = HTTPClient.METHOD_POST
		"PUT": http_method = HTTPClient.METHOD_PUT
	var headers := PackedStringArray()
	if _token != "":
		headers.append("Authorization: Bearer %s" % _token)
	if body != "":
		headers.append("Content-Type: application/json")
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
	var err := req.request(url, headers, http_method, body)
	if err != OK:
		req.queue_free()
		cb.call(false, {"error": "request error %d" % err})


static func format_value(mode: String, value: int) -> String:
	if mode == "time":
		return RaceHUD.format_time(float(value) / 1000.0)
	return str(value)
