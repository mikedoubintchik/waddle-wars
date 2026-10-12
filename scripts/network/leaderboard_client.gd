extends Node
## Optional online layer (Cloudflare Worker + D1, Clerk auth): leaderboards,
## custom display name, and cloud save sync.
##
## Everything degrades gracefully: the game is fully playable signed out and
## offline. Viewing boards works anywhere HTTP works; posting scores and cloud
## saves require Clerk sign-in. Web uses Clerk JS; enabled native releases use
## their secure authentication session and the same account-scoped API client.
##
## On web, requests go through the page's __ww_api fetch bridge instead of
## HTTPRequest — Godot's web HTTP path proved flaky in the field.

signal auth_changed
signal cloud_save_restored
signal cloud_save_conflict  # Deprecated compatibility only; never emitted.
signal cloud_sync_changed
signal public_name_changed
signal score_submission_changed(mode: String, course: String)

const API_BASE: String = "https://waddle-wars-leaderboard.ninjaconsultingllc.workers.dev"
const AUTH_POLL_INTERVAL: float = 0.5
const BRIDGE_POLL_INTERVAL: float = 0.12
# Browser timeout is 20 seconds. A separate monotonic fallback also releases
# callbacks if an old/missing shell never publishes a completion.
const BRIDGE_TIMEOUT_MSEC: int = 21000
const SAVE_PUSH_DEBOUNCE: float = 8.0
const SCORE_ACCOUNT_LIMIT: int = 4
const SCORE_TIME_COURSES: PackedStringArray = ["glacier", "aurora", "iceberg", "cinder", "hollow"]

var signed_in: bool = false
var display_name: String = ""
## True from sign_in() until the page reports Clerk ready (bundle lazy-loads).
var sign_in_pending: bool = false
var auth_ready: bool = false
## A generic bridge failure code, never provider text or account data.
var auth_error: String = ""
var auth_status: String = ""
var identity_pending: bool = false

var _token: String = ""
var _poll_accum: float = 0.0
var _pending_bridge: Dictionary = {}  # js id -> Callable
var _pending_bridge_started: Dictionary = {}  # js id -> monotonic milliseconds
var _bridge_accum: float = 0.0
var _save_push_timer: float = -1.0
var _synced_this_session: bool = false
var cloud_sync_error: bool = false
var _save_revision: String = ""
var _sync_in_flight: bool = false
var _push_in_flight: bool = false
var _revision_retries: int = 0
var _cloud_status: String = "syncing"
var _pending_cloud_pull: Dictionary = {}
var _cloud_retry_timer: float = -1.0
var _profile_requested_generation: int = -1
var _public_name_revision: int = 0
var _cloud_conflict_data: Dictionary = {}
var _cloud_conflict_owner: String = ""
var _cloud_conflict_generation: int = -1
var _auth_owner_id: String = ""
var _auth_generation: int = 0
var _bridge_identity_epoch: int = 0
# Session-only outbox: at most four account hashes and seven known boards per
# account. Keep only each board's best value, never tokens or server error text.
# Reloaded guest/local history remains available through explicit Post local best.
var _score_submissions: Dictionary = {}
var _score_account_order: Array[String] = []
var _score_attempt: int = 0


func _ready() -> void:
	set_process(can_sign_in())
	if can_sign_in():
		auth_changed.connect(_on_auth_changed_sync)


func _process(delta: float) -> void:
	_poll_accum += delta
	if _poll_accum >= AUTH_POLL_INTERVAL:
		_poll_accum = 0.0
		if _uses_native_auth():
			_sync_native_auth()
		else:
			_sync_web_auth()
		_load_public_name()
		if signed_in and not _synced_this_session and not cloud_sync_error:
			_on_auth_changed_sync()
	if not _pending_bridge.is_empty():
		_bridge_accum += delta
		if _bridge_accum >= BRIDGE_POLL_INTERVAL:
			_bridge_accum = 0.0
			_poll_bridge()
	if not _pending_cloud_pull.is_empty() and _cloud_apply_allowed():
		var pending := _pending_cloud_pull
		_pending_cloud_pull = {}
		_accept_cloud_pull(pending["data"], pending["generation"], pending["owner"])
	if _cloud_retry_timer > 0.0:
		_cloud_retry_timer -= delta
		if _cloud_retry_timer <= 0.0:
			cloud_sync_error = false
			_revision_retries = 0
			_on_auth_changed_sync()
	if _save_push_timer > 0.0:
		_save_push_timer -= delta
		if _save_push_timer <= 0.0:
			_push_save_now()


func _exit_tree() -> void:
	for req_id: int in _pending_bridge.keys():
		_cancel_bridge_request(req_id)
	_pending_bridge.clear()
	_pending_bridge_started.clear()


## Sign-in requires the Clerk JS bundle, which only exists in the web export.
## Test hook, in the style of GameConfig.force_touch. The sign-in chip is
## web-only, so a desktop test run never builds it — and it was the chip's
## minimum widths that pushed the whole main menu off the right edge of a real
## iPhone. A layout audit that cannot construct it cannot catch that class of
## bug, which is exactly what happened.
static var force_available: bool = false


func can_sign_in() -> bool:
	if force_available:
		return true
	return (OS.has_feature("web") or _uses_native_auth()) and not GameConfig.is_headless()


func _uses_native_auth() -> bool:
	return GameConfig.native_accounts_enabled()


func _account_features_disabled() -> bool:
	return GameConfig.native_offline_mvp() and not _uses_native_auth()


func _native_auth_provider() -> Node:
	return get_node_or_null("/root/NativeAuthClient")


func _sync_native_auth() -> void:
	var native := _native_auth_provider()
	if native == null:
		return
	var snapshot: Dictionary = native.call("account_snapshot")
	_apply_web_auth_state(snapshot)


func sign_in() -> void:
	if _uses_native_auth():
		var native := _native_auth_provider()
		if native != null:
			native.call("sign_in")
			_sync_native_auth()
		return
	if can_sign_in():
		auth_error = ""
		sign_in_pending = true
		var invoked: Variant = JavaScriptBridge.eval(
			"window.__ww_auth && window.__ww_auth.signIn ? (window.__ww_auth.signIn(), true) : false", true)
		if not (invoked is bool and invoked):
			sign_in_pending = false
			auth_error = "bridge"
			auth_changed.emit()


func cancel_sign_in() -> void:
	if not _uses_native_auth() or not sign_in_pending:
		return
	var native := _native_auth_provider()
	if native != null:
		native.call("cancel_sign_in")
		_sync_native_auth()


func sign_out() -> void:
	if _uses_native_auth():
		var native := _native_auth_provider()
		if native != null:
			native.call("sign_out")
			_sync_native_auth()
		return
	if can_sign_in():
		JavaScriptBridge.eval("window.__ww_auth && window.__ww_auth.signOut()", true)


func suspend_account_subject(owner: String) -> void:
	if owner != _auth_owner_id:
		return
	_auth_generation += 1
	_retire_score_posts()
	_save_push_timer = -1.0
	_synced_this_session = false
	_clear_cloud_conflict()
	cloud_sync_error = false


func resume_account_subject(owner: String) -> void:
	if owner != _auth_owner_id or not SaveManager.account_deletion_state(owner).is_empty():
		return
	_auth_generation += 1
	_retire_score_posts()
	_clear_cloud_conflict()
	cloud_sync_error = false
	_on_auth_changed_sync()


func retire_account_subject(owner: String) -> void:
	if owner != _auth_owner_id:
		return
	_auth_generation += 1
	_score_submissions.erase(owner.sha256_text())
	_score_account_order.erase(owner.sha256_text())
	_token = ""
	_auth_owner_id = ""
	signed_in = false
	display_name = ""
	sign_in_pending = false
	auth_error = ""
	_save_push_timer = -1.0
	_synced_this_session = false
	_clear_cloud_conflict()
	cloud_sync_error = false
	auth_changed.emit()
	sign_out()


func _sync_web_auth() -> void:
	var raw: Variant = JavaScriptBridge.eval("JSON.stringify(window.__ww_auth || {})", true)
	if not (raw is String):
		return
	var parsed: Variant = JSON.parse_string(raw as String)
	if not (parsed is Dictionary):
		return
	_apply_web_auth_state(parsed as Dictionary)


func _apply_web_auth_state(state: Dictionary) -> void:
	var was := signed_in
	var was_pending := sign_in_pending
	var previous_status := auth_status
	var previous_error := auth_error
	var previous_owner := _auth_owner_id
	var previous_bridge_epoch := _bridge_identity_epoch
	_bridge_identity_epoch = int(state.get("identityEpoch", 0))
	auth_ready = bool(state.get("ready", false))
	auth_error = String(state.get("error", ""))
	auth_status = String(state.get("status", "")) if _uses_native_auth() else ""
	display_name = String(state.get("name", ""))
	_token = String(state.get("token", "")) if bool(state.get("signedIn", false)) else ""
	_auth_owner_id = _token_owner(_token)
	if not _auth_owner_id.is_empty() and SaveManager.account_deletion_state(_auth_owner_id) == "retired":
		_token = ""
		_auth_owner_id = ""
		display_name = ""
	# Consumers include one-shot score submissions. Do not announce a usable
	# sign-in until the bridge's asynchronous credential request has completed.
	signed_in = not _auth_owner_id.is_empty()
	identity_pending = bool(state.get("signedIn", false)) and not signed_in
	if state.has("pending"):
		sign_in_pending = bool(state["pending"])
	elif auth_ready or not auth_error.is_empty():
		sign_in_pending = false
	if was != signed_in or previous_owner != _auth_owner_id or previous_bridge_epoch != _bridge_identity_epoch:
		_auth_generation += 1
		_retire_score_posts()
		_synced_this_session = false
		_save_push_timer = -1.0
		_clear_cloud_conflict()
		cloud_sync_error = false
		# An identity epoch can arrive before its token. Keep one-shot sign-in
		# listeners waiting when there is no previously usable session to retire.
		if was != signed_in or signed_in:
			auth_changed.emit()
	elif was_pending != sign_in_pending or previous_status != auth_status or previous_error != auth_error:
		# Opening the modal does not change identity. Still refresh buttons so
		# they cannot remain stuck on "Opening…" after Clerk settles or fails.
		auth_changed.emit()


static func _token_owner(token: String) -> String:
	# This only separates local callbacks. The server verifies every JWT.
	var parts := token.split(".")
	if parts.size() != 3:
		return ""
	var encoded := parts[1].replace("-", "+").replace("_", "/")
	while encoded.length() % 4 != 0:
		encoded += "="
	var payload: Variant = JSON.parse_string(Marshalls.base64_to_utf8(encoded))
	if not payload is Dictionary or not payload.get("sub") is String:
		return ""
	return String(payload["sub"])


## --- Requests ---------------------------------------------------------------

## Fetch top entries. cb receives (ok: bool, data: Dictionary) where data has
## "entries": [{rank, name, value}] and optional "me": {rank, value}.
func fetch_board(mode: String, course: String, limit: int, cb: Callable) -> void:
	var url := "%s/api/leaderboard?mode=%s&course=%s&limit=%d" % [API_BASE, mode, course, limit]
	_request("GET", url, "", func(ok: bool, data: Dictionary) -> void:
		# The transport owns delivery/auth-generation checks; this wrapper must
		# also preserve the original caller's freed-node callback protection.
		if not cb.is_valid():
			return
		if ok and _account_features_disabled():
			cb.call(true, _native_board_view(data))
		else:
			cb.call(ok, data))


## Mobile MVP boards retain real ranks/scores, not unmoderated public handles.
## Project only the presentation contract, so arbitrary response text cannot
## reach a row, error label or future avatar. Browser presentation is unchanged.
## This is not a server-side moderation or zero-data-collection claim.
static func _native_board_view(data: Dictionary) -> Dictionary:
	var entries: Array[Dictionary] = []
	var rows: Variant = data.get("entries", [])
	if rows is Array:
		for row: Variant in rows:
			if not row is Dictionary:
				continue
			var rank := _board_integer(row.get("rank"))
			var value := _board_integer(row.get("value"))
			if rank < 1 or value < 0:
				continue
			entries.append({"rank": rank, "value": value, "name": "Penguin #%d" % rank})
	var me: Variant = null
	var remote_me: Variant = data.get("me")
	if remote_me is Dictionary:
		var rank := _board_integer(remote_me.get("rank"))
		var value := _board_integer(remote_me.get("value"))
		if rank >= 1 and value >= 0:
			me = {"rank": rank, "value": value}
	return {"entries": entries, "me": me}


## JSON numbers may arrive as integral floats. Never coerce remote text or
## truncate fractions; bound float conversion to the signed 64-bit range.
static func _board_integer(value: Variant) -> int:
	if value is int:
		return value if value >= 0 else -1
	if value is float:
		var number: float = value
		if is_finite(number) and number >= 0.0 and number < 9223372036854775808.0 \
				and floor(number) == number:
			return int(number)
	return -1


## Post a personal best. cb receives (ok, data) with data holding
## {improved, best, rank, name} on success.
func submit_score(mode: String, course: String, value: int, cb: Callable) -> void:
	if not _score_posting_available():
		if cb.is_valid(): cb.call(false, {"error": "not signed in"})
		return
	if not _valid_score(mode, course, value):
		if cb.is_valid(): cb.call(false, {"error": "invalid score"})
		return
	var scope := _auth_owner_id.sha256_text()
	var boards := _score_boards(scope, true)
	var key := mode + ":" + course
	var entry: Dictionary = boards.get(key, {"mode": mode, "course": course,
		"value": value, "posted_value": 0, "status": "idle", "attempt": 0, "reply": {}})
	if _better_score(mode, value, int(entry["value"])):
		entry["value"] = value
	boards[key] = entry
	if entry["status"] == "posting":
		# One in-flight request per board. A stronger run is retained for the
		# next explicit retry/completed run, without starting a request loop.
		if cb.is_valid(): cb.call(false, {"error": "score_posting"})
		return
	var desired := int(entry["value"])
	if not _better_score(mode, desired, int(entry["posted_value"])):
		entry["status"] = "posted"
		var cached: Dictionary = entry["reply"].duplicate()
		cached["improved"] = false
		cached["already_posted"] = true
		if cb.is_valid(): cb.call(true, cached)
		return
	_score_attempt += 1
	var attempt := _score_attempt
	var generation := _auth_generation
	entry["attempt"] = attempt
	entry["status"] = "posting"
	score_submission_changed.emit(mode, course)
	if generation != _auth_generation or scope != _auth_owner_id.sha256_text() or not _score_posting_available():
		if cb.is_valid(): cb.call(false, {"error": "account_changed"})
		return
	var body := {"mode": mode, "course": course, "value": desired}
	var custom := custom_player_name()
	if custom.strip_edges().length() >= 2:
		body["name"] = custom.strip_edges()
	_request("POST", "%s/api/scores" % API_BASE, JSON.stringify(body),
		func(ok: bool, data: Dictionary) -> void:
			if generation != _auth_generation or scope != _auth_owner_id.sha256_text() \
					or not _score_posting_available():
				if cb.is_valid(): cb.call(false, {"error": "account_changed"})
				return
			var current: Dictionary = _score_boards(scope).get(key, {})
			if current.is_empty() or current.get("attempt") != attempt:
				if cb.is_valid(): cb.call(false, {"error": "account_changed"})
				return
			var reply := _validated_score_reply(mode, course, desired, data) if ok else {}
			var accepted := ok and not reply.is_empty()
			if accepted:
				var confirmed := int(reply["best"])
				if _better_score(mode, confirmed, int(current["posted_value"])):
					current["posted_value"] = confirmed
				current["reply"] = reply
				current["status"] = "pending" if _better_score(mode, int(current["value"]), int(current["posted_value"])) else "posted"
			else:
				current["status"] = "pending"
			score_submission_changed.emit(mode, course)
			if cb.is_valid():
				if generation != _auth_generation or scope != _auth_owner_id.sha256_text():
					cb.call(false, {"error": "account_changed"})
				else:
					cb.call(accepted, reply if accepted else ({"error": "bad score response"} if ok else data)))


func _score_posting_available() -> bool:
	return not _account_features_disabled() and signed_in and not _token.is_empty() \
		and not _auth_owner_id.is_empty() and SaveManager.account_deletion_state(_auth_owner_id).is_empty()


static func _valid_score(mode: String, course: String, value: int) -> bool:
	match mode:
		"runner": return course == "runner" and value >= 1 and value <= 1000000000
		"endless": return course == "endless" and value >= 1 and value <= 1000000
		"time": return course in SCORE_TIME_COURSES and value >= 10000 and value <= 1800000
	return false


static func _better_score(mode: String, candidate: int, current: int) -> bool:
	return candidate > 0 and (current <= 0 or (candidate < current if mode == "time" else candidate > current))


static func _validated_score_reply(mode: String, course: String, submitted: int, data: Dictionary) -> Dictionary:
	var best := _board_integer(data.get("best"))
	var rank := _board_integer(data.get("rank"))
	var public_name: Variant = data.get("name")
	if not data.get("ok") is bool or data.get("ok") != true or not data.get("improved") is bool \
			or not _valid_score(mode, course, best) or rank < 1 \
			or _better_score(mode, submitted, best) or not public_name is String:
		return {}
	var valid_name := RegEx.new()
	valid_name.compile("^[A-Za-z0-9 _.-]{2,20}$")
	if valid_name.search(public_name) == null: return {}
	return {"ok": true, "improved": data["improved"], "best": best, "rank": rank, "name": public_name}


func _score_boards(scope: String, create: bool = false) -> Dictionary:
	if create and not _score_submissions.has(scope):
		while _score_account_order.size() >= SCORE_ACCOUNT_LIMIT:
			_score_submissions.erase(_score_account_order.pop_front())
		_score_account_order.append(scope)
		_score_submissions[scope] = {}
	return _score_submissions.get(scope, {})


func _score_entry(mode: String, course: String) -> Dictionary:
	if not _score_posting_available(): return {}
	return _score_boards(_auth_owner_id.sha256_text()).get(mode + ":" + course, {})


## Never retries on sign-in, focus, timer, or a board read. Account changes
## invalidate old callbacks; that account can explicitly retry after returning.
func _retire_score_posts() -> void:
	for boards: Dictionary in _score_submissions.values():
		for entry: Dictionary in boards.values():
			if entry["status"] == "posting":
				entry["status"] = "pending"
				score_submission_changed.emit(entry["mode"], entry["course"])


func score_submission_status(mode: String, course: String) -> String:
	return String(_score_entry(mode, course).get("status", "idle"))


func pending_score_value(mode: String, course: String) -> int:
	var entry := _score_entry(mode, course)
	return int(entry.get("value", 0)) if entry.get("status") in ["pending", "posting"] else 0


func posted_score_value(mode: String, course: String) -> int:
	return int(_score_entry(mode, course).get("posted_value", 0))


func retry_pending_score(mode: String, course: String, cb: Callable = Callable()) -> bool:
	var entry := _score_entry(mode, course)
	if entry.get("status") != "pending":
		if cb.is_valid(): cb.call(false, {"error": "no pending score"})
		return false
	submit_score(mode, course, int(entry["value"]), cb)
	return true


## Only new, completed web runs auto-post. Signing in never assigns this
## device's historical guest records to an account; the board offers an
## explicit Post local best action for those real records instead.
func submit_completed_run(mode: String, course: String, value: int) -> void:
	if _account_features_disabled() or not can_sign_in() or not signed_in or value <= 0:
		return
	submit_score(mode, course, value, Callable())


func local_board_value(mode: String, course: String) -> int:
	match mode:
		"time": return int(round(Progression.best_time(course) * 1000.0))
		"runner": return Progression.runner_high_score()
		"endless": return Progression.endless_high_score()
	return 0


## Shared save-safety/prompt predicate. Runner-only and time-trial-only players
## may have no fish or races_finished, but their earned records are not pristine.
static func has_played_progress(progress: Dictionary) -> bool:
	if int(progress.get("fish", 0)) > 0 or int(progress.get("xp", 0)) > 0 \
			or int(progress.get("runner_high_score", 0)) > 0 \
			or int(progress.get("endless_high_score", 0)) > 0 \
			or bool(progress.get("tutorial_complete", false)):
		return true
	var times: Variant = progress.get("best_times", {})
	if times is Dictionary and not times.is_empty():
		return true
	for key: String in ["achievements", "gp_records"]:
		var records: Variant = progress.get(key, {})
		if records is Dictionary and not records.is_empty():
			return true
	var cosmetics: Variant = progress.get("unlocked_cosmetics", [])
	if cosmetics is Array and cosmetics.size() > 1:
		return true
	var stats: Variant = progress.get("stats", {})
	if stats is Dictionary:
		for key: String in ["races_finished", "runner_best_distance", "endless_best_distance", "fish_total"]:
			if float(stats.get(key, 0.0)) > 0.0:
				return true
	return false


## Public handles are device/account scoped, separate from private provider names.
func custom_player_name() -> String:
	var handles: Variant = SettingsManager.get_setting("online", "public_handles")
	if handles is Dictionary and handles.has(_name_scope()):
		return String(handles.get(_name_scope(), "")).strip_edges()
	# Legacy unscoped handles are guest-only; never inherit another account's.
	return String(SettingsManager.get_setting("online", "display_name")).strip_edges() if not signed_in else ""


func player_display_name() -> String:
	var custom := custom_player_name()
	return custom if not custom.is_empty() else ("Penguin" if signed_in else "Guest Explorer")


func _name_scope() -> String:
	return "account:" + _auth_owner_id.sha256_text() if signed_in else "guest"


func _store_public_name(scope: String, value: String) -> void:
	var existing: Variant = SettingsManager.get_setting("online", "public_handles")
	var handles: Dictionary = existing.duplicate(true) if existing is Dictionary else {}
	handles[scope] = value
	SettingsManager.set_setting("online", "public_handles", handles)
	public_name_changed.emit()


func _load_public_name() -> void:
	if not signed_in or _token.is_empty() or _profile_requested_generation == _auth_generation: return
	_profile_requested_generation = _auth_generation
	var generation := _auth_generation
	var owner := _auth_owner_id
	var name_revision := _public_name_revision
	var scope := _name_scope()
	_request("GET", "%s/api/profile" % API_BASE, "", func(ok: bool, response: Dictionary) -> void:
		if not ok or generation != _auth_generation or owner != _auth_owner_id or not signed_in \
			or name_revision != _public_name_revision: return
		var name_text: Variant = response.get("name")
		if not name_text is String: return
		if name_text.is_empty(): return # Old/missing service keeps local explicit handle.
		var regex := RegEx.new()
		regex.compile("^[A-Za-z0-9 _.-]{2,20}$")
		if regex.search(name_text) != null: _store_public_name(scope, name_text))


func set_display_name(name_text: String, cb: Callable) -> void:
	var cleaned := name_text.strip_edges()
	var regex := RegEx.new()
	regex.compile("^[A-Za-z0-9 _.-]{2,20}$")
	if regex.search(cleaned) == null:
		if cb.is_valid(): cb.call(false, {"error": "bad name (2-20 chars, letters/numbers/space/-_.)"})
		return
	var scope := _name_scope()
	_public_name_revision += 1
	if not signed_in:
		_store_public_name(scope, cleaned)
		if cb.is_valid(): cb.call(true, {"ok": true, "name": cleaned, "local_only": true})
		return
	if _account_features_disabled() or _token.is_empty():
		if cb.is_valid(): cb.call(false, {"error": "online unavailable"})
		return
	var generation := _auth_generation
	var owner := _auth_owner_id
	_request("POST", "%s/api/profile" % API_BASE, JSON.stringify({"name": cleaned}),
		func(ok: bool, response: Dictionary) -> void:
			if generation != _auth_generation or owner != _auth_owner_id or not signed_in:
				if cb.is_valid(): cb.call(false, {"error": "account_changed"})
				return
			if ok: _store_public_name(scope, String(response.get("name", cleaned)).strip_edges())
			if cb.is_valid(): cb.call(ok, response))


## --- Cloud save -------------------------------------------------------------

## Called by SaveManager after each local write; debounced push while signed in.
func notify_save_written() -> void:
	if signed_in and cloud_sync_error and _cloud_status == "pending":
		# Only real local writes retry unresolved legacy history; no timer loop.
		cloud_sync_error = false
		cloud_sync_changed.emit()
	if signed_in and can_sign_in() and _synced_this_session \
		and SaveManager.account_deletion_state(_auth_owner_id).is_empty():
		_save_push_timer = SAVE_PUSH_DEBOUNCE
		cloud_sync_changed.emit()


func cloud_sync_status() -> String:
	if not signed_in: return "signed_out"
	if cloud_sync_error: return _cloud_status
	if not _synced_this_session or _sync_in_flight or _push_in_flight or _save_push_timer > 0.0: return "syncing"
	return "saved"


func has_cloud_save_conflict() -> bool:
	return false


func resolve_cloud_save_conflict(_use_cloud: bool) -> bool:
	return false


func _clear_cloud_conflict() -> void:
	_cloud_conflict_data.clear()
	_cloud_conflict_owner = ""
	_cloud_conflict_generation = -1
	_save_revision = ""
	_sync_in_flight = false
	_push_in_flight = false
	_pending_cloud_pull.clear()
	_revision_retries = 0
	_cloud_retry_timer = -1.0
	_cloud_status = "syncing"
	cloud_sync_changed.emit()
	public_name_changed.emit()


func _cloud_apply_allowed() -> bool:
	# Never replace active mission state underneath a running 3D scene.
	return get_tree() == null or not get_tree().current_scene is Node3D


func _cloud_failed(status: String = "offline") -> void:
	_synced_this_session = false
	_sync_in_flight = false
	_push_in_flight = false
	cloud_sync_error = true
	_cloud_status = status
	_cloud_retry_timer = 60.0 if status == "offline" else -1.0
	cloud_sync_changed.emit()


func _valid_save_revision(value: Variant) -> bool:
	if not value is String: return false
	if value == "absent": return true
	if value.length() != 64: return false
	for character: String in value:
		if character not in "0123456789abcdef": return false
	return true


func _on_auth_changed_sync() -> void:
	if not signed_in or _auth_owner_id.is_empty() or _synced_this_session or _sync_in_flight \
			or cloud_sync_error or not _cloud_apply_allowed() \
			or not SaveManager.account_deletion_state(_auth_owner_id).is_empty():
		return
	var generation := _auth_generation
	var owner := _auth_owner_id
	_sync_in_flight = true
	cloud_sync_changed.emit()
	_request("GET", "%s/api/save?sync=2" % API_BASE, "", func(ok: bool, response: Dictionary) -> void:
		if generation != _auth_generation or owner != _auth_owner_id or not signed_in:
			return
		if not ok:
			_cloud_failed()
			return
		# An older server cannot promise a conditional write. Fail closed rather
		# than falling back to unsafe last-write-wins after silently merging.
		if response.get("sync_protocol") != 2 or not _valid_save_revision(response.get("revision")):
			_cloud_failed("unavailable")
			return
		if not _cloud_apply_allowed():
			_pending_cloud_pull = {"data": response, "generation": generation, "owner": owner}
			return
		_accept_cloud_pull(response, generation, owner))


func _accept_cloud_pull(response: Dictionary, generation: int, owner: String) -> void:
	if generation != _auth_generation or owner != _auth_owner_id or not signed_in:
		return
	var remote: Dictionary = {}
	if bool(response.get("exists", false)):
		var parsed: Variant = JSON.parse_string(String(response.get("data", "")))
		if not parsed is Dictionary:
			_cloud_failed("unavailable")
			return
		remote = parsed
	if not SaveManager.bind_cloud_owner(owner):
		_cloud_failed("unavailable")
		return
	var result := SaveManager.reconcile_cloud_save(owner, remote, String(response["revision"]))
	if not result.get("ok", false):
		_cloud_failed("pending" if result.get("error") in ["ambiguous_legacy_wallet", "ambiguous_mission_board"] else "unavailable")
		return
	_sync_in_flight = false
	_save_revision = String(response["revision"])
	_synced_this_session = true
	cloud_save_restored.emit()
	_push_save_now()


func _local_save_is_pristine() -> bool:
	return not has_played_progress(SaveManager.data)


func _push_save_now() -> void:
	_save_push_timer = -1.0
	if _token == "" or not signed_in or not _synced_this_session or _save_revision.is_empty() \
			or not SaveManager.account_deletion_state(_auth_owner_id).is_empty():
		return
	if String(SaveManager.data.get("_cloud_owner", "")) != _auth_owner_id.sha256_text():
		_cloud_failed("unavailable")
		return
	if _push_in_flight:
		_save_push_timer = SAVE_PUSH_DEBOUNCE
		return
	var generation := _auth_generation
	var owner := _auth_owner_id
	_push_in_flight = true
	cloud_sync_changed.emit()
	var body := {"sync_protocol": 2, "base_revision": _save_revision,
		"progress": SaveManager.cloud_progress_snapshot(SaveManager.data)}
	_request("PUT", "%s/api/save" % API_BASE, JSON.stringify(body),
		func(ok: bool, response: Dictionary) -> void:
			if generation != _auth_generation or owner != _auth_owner_id or not signed_in:
				return
			_push_in_flight = false
			if ok and response.get("sync_protocol") == 2 and _valid_save_revision(response.get("revision")):
				_save_revision = response["revision"]
				_revision_retries = 0
				cloud_sync_changed.emit()
				return
			if response.get("error") == "save_revision_conflict" and _revision_retries < 3:
				_revision_retries += 1
				_synced_this_session = false
				_on_auth_changed_sync()
			else:
				_cloud_failed())


## --- Transport --------------------------------------------------------------

func _request(method: String, url: String, body: String, cb: Callable) -> void:
	if not _auth_owner_id.is_empty() and not SaveManager.account_deletion_state(_auth_owner_id).is_empty():
		cb.call(false, {"error": "account_deletion_pending"})
		return
	var generation := _auth_generation
	var owner := _auth_owner_id
	var delivered: Array[bool] = [false]
	var complete := func(ok: bool, data: Dictionary) -> void:
		if delivered[0] or not cb.is_valid():
			return
		delivered[0] = true
		if generation != _auth_generation or owner != _auth_owner_id:
			cb.call(false, {"error": "account_changed"})
			return
		cb.call(ok, data)
	_dispatch_request(method, url, body, complete)


func _dispatch_request(method: String, url: String, body: String, cb: Callable) -> void:
	if OS.has_feature("web"):
		_request_via_bridge(method, url, body, cb)
	else:
		_request_via_http(method, url, body, cb)


static func _js_quote(s: String) -> String:
	return "\"%s\"" % s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")


func _request_via_bridge(method: String, url: String, body: String, cb: Callable,
		request_token: Variant = null) -> void:
	var captured_token := _token if request_token == null else String(request_token)
	var js := "window.__ww_api ? window.__ww_api.start(%s, %s, %s, %s) : 0" % [
		_js_quote(method), _js_quote(url), _js_quote(captured_token), _js_quote(body),
	]
	var id: Variant = JavaScriptBridge.eval(js, true)
	var req_id := int(id) if id != null else 0
	if req_id <= 0:
		cb.call(false, {"error": "bridge unavailable"})
		return
	_track_bridge_request(req_id, cb)


func _track_bridge_request(req_id: int, cb: Callable) -> void:
	_pending_bridge[req_id] = cb
	_pending_bridge_started[req_id] = _bridge_clock_msec()


func _bridge_clock_msec() -> int:
	return Time.get_ticks_msec()


func _read_bridge_result(req_id: int) -> Variant:
	return JavaScriptBridge.eval("window.__ww_api && typeof window.__ww_api.poll === 'function' "
		+ "? window.__ww_api.poll(%d) : ''" % req_id, true)


func _cancel_bridge_request(req_id: int) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if (window.__ww_api && typeof window.__ww_api.cancel === 'function') "
			+ "window.__ww_api.cancel(%d);" % req_id, true)


func _poll_bridge() -> void:
	var now := _bridge_clock_msec()
	for req_id: int in _pending_bridge.keys():
		# Delivery may re-enter this client or retire another queued request.
		if not _pending_bridge.has(req_id):
			continue
		var cb: Callable = _pending_bridge[req_id]
		if not cb.is_valid():
			_cancel_bridge_request(req_id)
			_pending_bridge.erase(req_id)
			_pending_bridge_started.erase(req_id)
			continue
		var raw: Variant = _read_bridge_result(req_id)
		if not (raw is String) or (raw as String).is_empty():
			if now - int(_pending_bridge_started.get(req_id, now)) < BRIDGE_TIMEOUT_MSEC:
				continue
			_cancel_bridge_request(req_id)
			_pending_bridge.erase(req_id)
			_pending_bridge_started.erase(req_id)
			cb.call(false, {"error": "network_unavailable"})
			continue
		# Consume before callbacks; completed replies win over an elapsed fallback
		# after tab suspension/pause, so a successful request is never timed out.
		_pending_bridge.erase(req_id)
		_pending_bridge_started.erase(req_id)
		var parsed: Variant = JSON.parse_string(raw as String)
		if not (parsed is Dictionary):
			cb.call(false, {"error": "bad bridge response"})
			continue
		var result := parsed as Dictionary
		var body_parsed: Variant = JSON.parse_string(String(result.get("body", "")))
		var payload: Dictionary = body_parsed if body_parsed is Dictionary else {"error": String(result.get("body", ""))}
		cb.call(bool(result.get("ok", false)), payload)


func _request_via_http(method: String, url: String, body: String, cb: Callable) -> void:
	var req := HTTPRequest.new()
	req.timeout = 10.0
	req.body_size_limit = 1024 * 1024
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
		var response := _decode_http_reply(result, code, bytes)
		cb.call(response["ok"], response["payload"]))
	var err := req.request(url, headers, http_method, body)
	if err != OK:
		req.queue_free()
		cb.call(false, {"error": "request error %d" % err})


static func _decode_http_reply(result: int, code: int, bytes: PackedByteArray) -> Dictionary:
	if result != HTTPRequest.RESULT_SUCCESS or bytes.size() > 1024 * 1024:
		return {"ok": false, "payload": {"error": "network_unavailable"}}
	var parser := JSON.new()
	var parsed: Variant = parser.data if parser.parse(bytes.get_string_from_utf8()) == OK else null
	if code >= 200 and code < 300:
		return {"ok": parsed is Dictionary, "payload": parsed if parsed is Dictionary else {"error": "bad response"}}
	# Keep machine-readable server conflicts for bounded CAS recovery; never
	# surface arbitrary provider/HTML error bodies or identity data to the UI.
	var known := ["save_revision_conflict", "save_client_upgrade_required", "unauthorized", "account_retired"]
	var error := String(parsed.get("error", "")) if parsed is Dictionary else ""
	return {"ok": false, "payload": {"error": error if error in known else "network_unavailable"}}


static func format_value(mode: String, value: int) -> String:
	if mode == "time":
		return RaceHUD.format_time(float(value) / 1000.0)
	return str(value)
