extends Node
## Versioned local save data with atomic writes and graceful recovery.

signal save_loaded
signal save_written

const Reconciler = preload("res://scripts/save/cloud_save_reconciler.gd")
const CLOUD_REPLICA_PATH: String = "user://cloud_replica.json"
var _cloud_replica: String = ""

const SAVE_PATH: String = "user://save.json"
const SAVE_TMP_PATH: String = "user://save.json.tmp"
const SAVE_BACKUP_PATH: String = "user://save.json.bak"
const SAVE_BACKUP_TMP_PATH: String = "user://save.json.bak.tmp"
const SAVE_RETIRE_TMP_PATH: String = "user://save.account-retirement.tmp"
## Earlier cleanup staging paths are explicit, never discovered with a glob.
const LEGACY_RETIRE_TMP_PATHS: PackedStringArray = [
	"user://save.json.retire.tmp",
	"user://save.json.bak.retire.tmp",
	"user://save.json.tmp.retire.tmp",
]
## Device-only retirement journal. Recovery receipts never join normal saves,
## cloud progress, presentation state or diagnostics.
const ACCOUNT_DELETION_PATH: String = "user://account_deletion.json"
const ACCOUNT_DELETION_TMP_PATH: String = "user://account_deletion.json.tmp"

var data: Dictionary = {}
var _dirty: bool = false
var _account_deletion_states: Dictionary = {}
var _account_deletion_receipts: Dictionary = {}
var _account_deletion_recovery_owner: String = ""
## A verified pending clear may rename successfully before final readback
## fails. Only that exact authorized transaction can clear a known receipt.
var _account_deletion_expected_journal: Dictionary = {}
var _account_deletion_journal_available: bool = true
var _account_deletion_journal_loaded: bool = false


func _ready() -> void:
	load_save()
	var timer := Timer.new()
	timer.wait_time = 3.0
	timer.autostart = true
	timer.timeout.connect(_on_autosave_tick)
	add_child(timer)


static func default_save() -> Dictionary:
	return {
		"version": GameConfig.SAVE_VERSION,
		"fish": 0,
		"xp": 0,
		"unlocked_cosmetics": ["body_classic"],
		"equipped": {
			"body": "body_classic",
			"hat": "",
			"scarf": "",
			"goggles": "",
			"trail": "",
		},
		"achievements": {},
		"stats": {
			"fish_total": 0,
			"shoves_landed": 0,
			"races_finished": 0,
			"races_won": 0,
			"items_used": {},
			"shortcuts_taken": {},
			"endless_best_distance": 0.0,
		},
		"tutorial_complete": false,
		"best_times": {},
		"endless_high_score": 0,
		# Daily challenge: the UTC day number last completed, that run's time,
		# and the consecutive-day streak. See DailyChallenge.
		"daily_last_day": -1,
		"daily_last_time": 0.0,
		"daily_streak": 0,
		"daily_best_streak": 0,
		"gp_records": {},
		"settings_migrated": true,
	}


func load_save() -> void:
	_load_account_deletion_journal()
	var loaded: Dictionary = _read_json(SAVE_PATH)
	if loaded.is_empty():
		loaded = _read_json(SAVE_BACKUP_PATH)
	data = _merge_defaults(default_save(), loaded)
	data["version"] = GameConfig.SAVE_VERSION
	data = _without_retired_purchase_caches(data)
	# A crash may leave retirement confirmed before every save copy was scrubbed.
	# The journal fences recovery immediately; retry the disk cleanup on load.
	if not _scrub_retired_save_files():
		_dirty = true
		push_warning("SaveManager: retired purchase cache cleanup remains pending")
	save_loaded.emit()


func mark_dirty() -> void:
	_dirty = true


func save_now() -> void:
	if not _load_account_deletion_journal():
		_dirty = true
		return
	data = _without_retired_purchase_caches(data)
	# Normal save retries also fence any staging copies left by an interrupted
	# write or a previous account retirement. Main is replaced below.
	if not _scrub_retired_save_files(false):
		_dirty = true
		return
	# Never rotate an old, unsanitized account cache into the recovery copy.
	# Keep a valid existing backup when the main save is corrupt.
	if FileAccess.file_exists(SAVE_PATH):
		var previous := _read_json_checked(SAVE_PATH)
		if bool(previous["ok"]):
			var backup := _without_retired_purchase_caches(previous["data"])
			if not _write_json_atomically(SAVE_BACKUP_PATH, SAVE_BACKUP_TMP_PATH, backup):
				_dirty = true
				return
		elif not _scrub_retired_save_file(SAVE_BACKUP_PATH):
			_dirty = true
			return
	if not _write_json_atomically(SAVE_PATH, SAVE_TMP_PATH, data):
		_dirty = true
		return
	_dirty = false
	save_written.emit()
	# Cloud sync is optional and web-only; the client no-ops when signed out.
	# Looked up dynamically: SaveManager autoloads before LeaderboardClient,
	# so early saves run while the client does not exist yet.
	var lb := get_node_or_null("/root/LeaderboardClient")
	if lb != null:
		lb.notify_save_written()


## Replace local progress with a cloud save blob (validated through the same
## defaults merge as disk loads) and persist it. Called by LeaderboardClient
## when a signed-in player's local save is pristine and a cloud copy exists.
func adopt_cloud_save(cloud_data: Dictionary) -> void:
	# Commerce is a local per-account cache, never cloud progress or proof of
	# ownership. Older cloud saves may contain another account's cached grants.
	# Ignore that field and preserve only this device's existing verified cache.
	var local_commerce: Variant = data.get("commerce")
	data = _merge_defaults(default_save(), cloud_progress_snapshot(cloud_data))
	if local_commerce is Dictionary:
		data["commerce"] = local_commerce.duplicate(true)
	data["version"] = GameConfig.SAVE_VERSION
	_load_account_deletion_journal()
	data = _without_retired_purchase_caches(data)
	save_now()
	save_loaded.emit()


## Deep-copy earned progress for cloud sync. The original local save, including
## account-scoped offline purchase caches, remains unchanged and recoverable.
static func cloud_progress_snapshot(local_data: Dictionary) -> Dictionary:
	return Reconciler.progress(local_data)


func _cloud_state_path(owner_hash: String) -> String:
	return "user://cloud_sync_%s.json" % owner_hash


func _cloud_state(owner_hash: String) -> Dictionary:
	return _read_json(_cloud_state_path(owner_hash))


func _write_cloud_state(owner_hash: String, value: Dictionary) -> bool:
	var path := _cloud_state_path(owner_hash)
	return _write_json_atomically(path, path + ".tmp", value)


## Account ownership stays device-only. Never upload one signed-in account's
## progress to a different account merely because this browser changed user.
## An initially unbound guest save is carried into the first chosen account.
func bind_cloud_owner(owner: String) -> bool:
	if owner.is_empty() or not account_deletion_state(owner).is_empty():
		return false
	var target := owner.sha256_text()
	var previous := String(data.get("_cloud_owner", ""))
	if previous == target:
		return true
	if not previous.is_empty():
		var old_state := _cloud_state(previous)
		if FileAccess.file_exists(_cloud_state_path(previous)) and old_state.is_empty(): return false
		old_state["working"] = cloud_progress_snapshot(data)
		if not _write_cloud_state(previous, old_state): return false
	var target_state := _cloud_state(target)
	# An unreadable existing account slot is not equivalent to an empty account.
	if FileAccess.file_exists(_cloud_state_path(target)) and target_state.is_empty():
		return false
	var candidate := data.duplicate(true) if previous.is_empty() else default_save()
	if target_state.get("working") is Dictionary:
		candidate = target_state["working"].duplicate(true)
	var original := data.duplicate(true)
	var commerce: Variant = data.get("commerce")
	data = _merge_defaults(default_save(), candidate)
	if commerce is Dictionary: data["commerce"] = commerce.duplicate(true)
	data["_cloud_owner"] = target
	save_now()
	if _dirty:
		data = original
		return false
	save_loaded.emit()
	return true


## Preserve first and latest pre-merge progress on disk before changing local
## data. Purchase caches/deletion receipts never enter these recovery copies.
func reconcile_cloud_save(owner: String, cloud: Dictionary, revision: String) -> Dictionary:
	if owner.is_empty() or String(data.get("_cloud_owner", "")) != owner.sha256_text() \
			or not account_deletion_state(owner).is_empty():
		return {"ok": false, "error": "account_changed"}
	var original := data.duplicate(true)
	var result := Reconciler.reconcile(data, cloud)
	if not result.get("ok", false) and result.get("error") not in ["ambiguous_legacy_wallet", "ambiguous_mission_board"]: return result
	var owner_hash := owner.sha256_text()
	var state := _cloud_state(owner_hash)
	if FileAccess.file_exists(_cloud_state_path(owner_hash)) and state.is_empty():
		return {"ok": false, "error": "recovery_unavailable"}
	var backups := {"local": cloud_progress_snapshot(data), "cloud": cloud_progress_snapshot(cloud), "revision": revision}
	if not state.has("originals"): state["originals"] = backups.duplicate(true)
	state["latest_originals"] = backups
	state["working"] = result["progress"].duplicate(true) if result.get("ok", false) else cloud_progress_snapshot(data)
	state["observed_revision"] = revision
	state["last_reconcile_status"] = result.get("wallet_policy", result.get("error", "unknown"))
	if not _write_cloud_state(owner_hash, state):
		return {"ok": false, "error": "backup_failed"}
	if not result.get("ok", false): return result
	var local_commerce: Variant = data.get("commerce")
	data = _merge_defaults(default_save(), result["progress"])
	if local_commerce is Dictionary: data["commerce"] = local_commerce.duplicate(true)
	data["_cloud_owner"] = owner_hash
	save_now()
	if _dirty:
		data = original
		return {"ok": false, "error": "local_write_failed"}
	save_loaded.emit()
	return result


func _wallet_replica() -> String:
	if not _cloud_replica.is_empty(): return _cloud_replica
	var stored := _read_json(CLOUD_REPLICA_PATH)
	if stored.get("id") is String and String(stored["id"]).length() == 64:
		_cloud_replica = stored["id"]
		return _cloud_replica
	if FileAccess.file_exists(CLOUD_REPLICA_PATH): return ""
	var replica := Crypto.new().generate_random_bytes(32).hex_encode()
	if not _write_json_atomically(CLOUD_REPLICA_PATH, CLOUD_REPLICA_PATH + ".tmp", {"id": replica}): return ""
	_cloud_replica = replica
	return replica


## A milestone reward has one identity across offline replicas. Repeating the
## same grant cannot mint another copy of its fish after reconciliation.
func grant_fish_reward(reward_id: String, amount: int) -> int:
	var replica := _wallet_replica()
	if replica.is_empty() or amount <= 0: return 0
	var previous := 0
	if Reconciler.wallet_valid(data):
		previous = int(data[Reconciler.WALLET_KEY].get("rewards", {}).get(reward_id, 0))
	var wallet := Reconciler.reward_wallet(data, reward_id, amount, replica)
	if wallet.is_empty() or amount <= previous: return 0
	data[Reconciler.WALLET_KEY] = wallet
	data["fish"] = Reconciler.wallet_balance(wallet)
	mark_dirty()
	return amount - previous


## Cosmetic spends have a stable item identity, so two offline devices buying
## the same earned-fish item charge it once after reconciliation.
func spend_cosmetic_fish(costs: Dictionary, expected_total: int) -> bool:
	var total := 0
	for cost: Variant in costs.values():
		if not (cost is int or cost is float) or cost < 0 or int(cost) != cost: return false
		total += int(cost)
	if total != expected_total or total > int(data.get("fish", 0)): return false
	var replica := _wallet_replica()
	if replica.is_empty(): return false
	var wallet := Reconciler.purchase_wallet(data, costs, replica)
	if wallet.is_empty(): return false
	data[Reconciler.WALLET_KEY] = wallet
	data["fish"] = Reconciler.wallet_balance(wallet)
	mark_dirty()
	return true


## Read the durable device-only state. Empty means no unresolved deletion.
## An unavailable journal fences account use until its durable state is known.
func account_deletion_state(owner: String) -> String:
	if owner.is_empty():
		return ""
	if not account_deletion_journal_available():
		return "unavailable"
	return String(_account_deletion_states.get(owner, ""))


## Private service getter, not a UI or normal-save field. No disk polling.
func account_deletion_receipt(owner: String) -> String:
	if owner.is_empty() or not account_deletion_journal_available():
		return ""
	return String(_account_deletion_receipts.get(owner, ""))


## Use only the explicitly recorded most recent owner, never guess among
## accounts or infer a recovery target from an ordinary purchase cache.
func account_deletion_recovery_subject() -> String:
	if not account_deletion_journal_available():
		return ""
	return _account_deletion_recovery_owner


func account_deletion_journal_available() -> bool:
	if not _account_deletion_journal_loaded:
		_load_account_deletion_journal()
	return _account_deletion_journal_available


## Explicit repair/recovery seam. Ownership getters never poll local disk.
## Startup, disk loads and every durable mutation also validate the journal.
func refresh_account_deletion_journal() -> bool:
	return _load_account_deletion_journal()


## Persist the pending fence and random recovery receipt in ONE atomic journal
## mutation before transport. Existing unresolved receipts are never replaced.
func begin_account_deletion(owner: String, receipt: String) -> bool:
	if owner.is_empty() or not _valid_account_deletion_receipt(receipt) or not _load_account_deletion_journal():
		return false
	var previous := String(_account_deletion_states.get(owner, ""))
	if not previous.is_empty():
		return previous == "pending" and _account_deletion_receipts.get(owner, "") == receipt
	var states := _account_deletion_states.duplicate(true)
	var receipts := _account_deletion_receipts.duplicate(true)
	states[owner] = "pending"
	receipts[owner] = receipt
	return _persist_account_deletion_journal(states, receipts, owner)


## Pending may be cleared after a definitive failure. Retirement is permanent
## on this device, including when cache cleanup must be retried after a crash.
func set_account_deletion_state(owner: String, state: String) -> bool:
	if owner.is_empty() or state not in ["", "pending", "retired"] or not _load_account_deletion_journal():
		return false
	var previous := String(_account_deletion_states.get(owner, ""))
	if previous == "retired" and state != "retired":
		return false
	if state == previous:
		return true
	var next := _account_deletion_states.duplicate(true)
	var receipts := _account_deletion_receipts.duplicate(true)
	var recovery_owner := _account_deletion_recovery_owner
	if state.is_empty():
		next.erase(owner)
		receipts.erase(owner)
		if recovery_owner == owner:
			recovery_owner = ""
	else:
		next[owner] = state
	return _persist_account_deletion_journal(next, receipts, recovery_owner)


func _persist_account_deletion_journal(states: Dictionary, receipts: Dictionary, recovery_owner: String) -> bool:
	var journal := {"version": 1, "accounts": states}
	if not receipts.is_empty():
		journal["receipts"] = receipts
	if not recovery_owner.is_empty():
		journal["recovery_owner"] = recovery_owner
	# Match the exact disk representation, including JSON's float numbers.
	# Raw Dictionary equality distinguishes version int1 from parsed float1.0.
	var normalized := JSON.new()
	if normalized.parse(JSON.stringify(journal)) != OK or not normalized.data is Dictionary:
		return false
	_account_deletion_expected_journal = normalized.data
	if not _write_json_atomically(ACCOUNT_DELETION_PATH, ACCOUNT_DELETION_TMP_PATH, journal):
		# Rename may have succeeded before readback failed. Preserve any newly
		# durable fence, but never report an unverified transition as success.
		_load_account_deletion_journal()
		return false
	_account_deletion_states = states
	_account_deletion_receipts = receipts
	_account_deletion_recovery_owner = recovery_owner
	_account_deletion_expected_journal = {}
	return true


## Remove only confirmed retired account purchase caches. Earned progress,
## guest progress, settings and other account caches survive. No cloud upload.
func erase_account_purchase_cache(owner: String) -> bool:
	if owner.is_empty() or not _load_account_deletion_journal() \
			or String(_account_deletion_states.get(owner, "")) != "retired":
		return false
	data = _without_retired_purchase_caches(data)
	_dirty = true
	var complete := _scrub_retired_save_files(true, true)
	_dirty = not complete
	# CommerceClient reloads its in-memory overlay through this existing signal.
	save_loaded.emit()
	return complete


func get_value(key: String, default_value: Variant = null) -> Variant:
	# Preserve the underlying cache for repair, but do not expose purchase
	# ownership when an unreadable journal might contain a retired owner.
	if key == "commerce" and not account_deletion_journal_available():
		return {}
	return data.get(key, default_value)


func set_value(key: String, value: Variant, autosave: bool = true) -> bool:
	if key == "fish":
		var delta := int(value) - int(data.get("fish", 0))
		if delta != 0:
			var replica := _wallet_replica()
			if replica.is_empty(): return false
			var wallet := Reconciler.change_wallet(data, delta, replica)
			if wallet.is_empty(): return false
			data[Reconciler.WALLET_KEY] = wallet
			value = Reconciler.wallet_balance(wallet)
	data[key] = value
	if autosave:
		mark_dirty()
	return true


## Development-only wipe. Never wired to release UI.
func reset_all() -> void:
	data = default_save()
	save_now()


func _on_autosave_tick() -> void:
	if _dirty:
		save_now()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if _dirty:
			save_now()


func _read_json(path: String) -> Dictionary:
	var result := _read_json_checked(path)
	return result["data"] if bool(result["ok"]) else {}


func _read_json_checked(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "data": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("SaveManager: cannot read %s" % path)
		return {"ok": false, "data": {}}
	var content := file.get_as_text()
	var error := file.get_error()
	file.close()
	var json := JSON.new()
	if error not in [OK, ERR_FILE_EOF] or json.parse(content) != OK or not json.data is Dictionary:
		push_warning("SaveManager: invalid JSON at %s" % path)
		return {"ok": false, "data": {}}
	return {"ok": true, "data": json.data}


func _write_json_file(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveManager: cannot open %s for writing" % path)
		return false
	file.store_string(JSON.stringify(value, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		push_warning("SaveManager: write failed at %s (%d)" % [path, error])
		return false
	return true


func _replace_file(source: String, destination: String) -> bool:
	var error := DirAccess.rename_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(destination))
	if error != OK:
		push_warning("SaveManager: atomic rename failed at %s (%d)" % [destination, error])
	return error == OK


func _write_json_atomically(path: String, temporary: String, value: Dictionary) -> bool:
	# Refuse non-JSON values rather than replacing a recoverable save with them.
	var normalized := JSON.new()
	if normalized.parse(JSON.stringify(value)) != OK or not normalized.data is Dictionary:
		push_warning("SaveManager: cannot serialize valid JSON at %s" % path)
		return false
	if not _write_json_file(temporary, value):
		return false
	# Compare JSON-normalized values: disk numbers parse as floats.
	var expected: Dictionary = normalized.data
	var staged := _read_json_checked(temporary)
	if not bool(staged["ok"]) or staged["data"] != expected:
		push_warning("SaveManager: staged JSON verification failed at %s" % temporary)
		return false
	# Only the fixed, already-temporary retirement buffer is rewritten in place
	# when preserving its prior valid snapshot. Durable files use atomic rename.
	if temporary != path and not _replace_file(temporary, path):
		return false
	var persisted := _read_json_checked(path)
	if not bool(persisted["ok"]) or persisted["data"] != expected:
		push_warning("SaveManager: persisted JSON verification failed at %s" % path)
		return false
	return true


func _load_account_deletion_journal() -> bool:
	_account_deletion_journal_loaded = true
	if not FileAccess.file_exists(ACCOUNT_DELETION_PATH):
		if DirAccess.dir_exists_absolute(ACCOUNT_DELETION_PATH) or not _account_deletion_states.is_empty():
			_account_deletion_journal_available = false
			push_warning("SaveManager: account deletion journal missing; writes remain pending")
			return false
		_account_deletion_states = {}
		_account_deletion_receipts = {}
		_account_deletion_recovery_owner = ""
		_account_deletion_expected_journal = {}
		_account_deletion_journal_available = true
		return true
	var result := _read_json_checked(ACCOUNT_DELETION_PATH)
	var journal: Dictionary = result["data"]
	if not bool(result["ok"]) or journal.get("version", 0) != 1 or not journal.get("accounts") is Dictionary:
		_account_deletion_journal_available = false
		push_warning("SaveManager: account deletion journal unavailable; writes remain pending")
		return false
	var states: Dictionary = journal["accounts"]
	for owner: Variant in states:
		if not owner is String or String(owner).is_empty() or states[owner] not in ["pending", "retired"]:
			_account_deletion_journal_available = false
			push_warning("SaveManager: account deletion journal invalid; writes remain pending")
			return false
	var raw_receipts: Variant = journal.get("receipts", {})
	var recovery_owner: Variant = journal.get("recovery_owner", "")
	if not raw_receipts is Dictionary or not recovery_owner is String:
		_account_deletion_journal_available = false
		push_warning("SaveManager: account deletion recovery journal invalid; writes remain pending")
		return false
	var receipts: Dictionary = raw_receipts
	for owner: Variant in receipts:
		if not owner is String or not states.has(owner) or not _valid_account_deletion_receipt(receipts[owner]):
			_account_deletion_journal_available = false
			push_warning("SaveManager: account deletion recovery journal invalid; writes remain pending")
			return false
	if not String(recovery_owner).is_empty() and not receipts.has(recovery_owner):
		_account_deletion_journal_available = false
		push_warning("SaveManager: account deletion recovery owner unavailable; writes remain pending")
		return false
	for owner: String in _account_deletion_states:
		if _account_deletion_states[owner] == "retired" and states.get(owner, "") != "retired":
			_account_deletion_journal_available = false
			push_warning("SaveManager: account deletion journal lost retirement; writes remain pending")
			return false
	for owner: String in _account_deletion_receipts:
		var authorized_clear := not _account_deletion_expected_journal.is_empty() \
			and journal == _account_deletion_expected_journal and not states.has(owner) and not receipts.has(owner)
		if receipts.get(owner, "") != _account_deletion_receipts[owner] and not authorized_clear:
			_account_deletion_journal_available = false
			push_warning("SaveManager: account deletion recovery receipt changed; writes remain pending")
			return false
	_account_deletion_states = states.duplicate(true)
	_account_deletion_receipts = receipts.duplicate(true)
	_account_deletion_recovery_owner = String(recovery_owner)
	_account_deletion_expected_journal = {}
	_account_deletion_journal_available = true
	return true


static func _valid_account_deletion_receipt(value: Variant) -> bool:
	if not value is String or String(value).length() != 64:
		return false
	var receipt: String = value
	for index: int in 64:
		var code := receipt.unicode_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102):
			return false
	return true


func _without_retired_purchase_caches(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	for key: String in ["account_deletion", "account_deletion_receipt", "account_deletion_receipts", "account_deletion_recovery_owner"]:
		result.erase(key)
	var raw_commerce: Variant = result.get("commerce")
	if not raw_commerce is Dictionary:
		return result
	var commerce: Dictionary = raw_commerce
	var accounts: Variant = commerce.get("accounts")
	for owner: String in _account_deletion_states:
		if _account_deletion_states[owner] != "retired":
			continue
		if accounts is Dictionary:
			accounts.erase(owner)
		if commerce.get("last_account", "") == owner:
			commerce.erase("last_account")
	return result


func _scrub_retired_save_file(path: String) -> bool:
	if not _account_deletion_journal_available:
		return false
	if not _account_deletion_states.values().has("retired") or not FileAccess.file_exists(path):
		return true
	var loaded := _read_json_checked(path)
	if not bool(loaded["ok"]):
		return false
	var clean := _without_retired_purchase_caches(loaded["data"])
	if clean == loaded["data"]:
		return true
	return _write_json_atomically(path, SAVE_RETIRE_TMP_PATH, clean)


func _scrub_retired_save_files(include_main: bool = true, persist_current: bool = false) -> bool:
	if not _account_deletion_journal_available:
		return false
	if not _account_deletion_states.values().has("retired"):
		return true
	var complete := true
	# The fixed staging buffer may hold another retirement's valid snapshot.
	# Keep its own progress while scrubbing it; subsequent atomic writes reuse
	# the buffer, then its sanitized original snapshot is restored at the end.
	var staged_snapshot: Variant = null
	if FileAccess.file_exists(SAVE_RETIRE_TMP_PATH):
		var staged := _read_json_checked(SAVE_RETIRE_TMP_PATH)
		if bool(staged["ok"]):
			staged_snapshot = _without_retired_purchase_caches(staged["data"])
		else:
			complete = false
	if include_main:
		if persist_current:
			# Persist current progress without rotating former main into backup.
			if not _write_json_atomically(SAVE_PATH, SAVE_RETIRE_TMP_PATH, data):
				complete = false
		elif not _scrub_retired_save_file(SAVE_PATH):
			complete = false
	for path: String in [SAVE_BACKUP_PATH, SAVE_TMP_PATH, SAVE_BACKUP_TMP_PATH]:
		if not _scrub_retired_save_file(path):
			complete = false
	for path: String in LEGACY_RETIRE_TMP_PATHS:
		if not _scrub_retired_save_file(path):
			complete = false
	if staged_snapshot is Dictionary:
		if not _write_json_atomically(SAVE_RETIRE_TMP_PATH, SAVE_RETIRE_TMP_PATH, staged_snapshot):
			complete = false
	return complete


## Deep-merges loaded data over defaults so missing optional fields never
## erase valid progress and new versions gain new keys automatically.
## Type-mismatched entries (corrupt or hand-edited saves) keep the default.
func _merge_defaults(defaults: Dictionary, loaded: Dictionary) -> Dictionary:
	var result := defaults.duplicate(true)
	for key: Variant in loaded.keys():
		var value: Variant = loaded[key]
		var default_value: Variant = result.get(key)
		if default_value is Dictionary and value is Dictionary:
			result[key] = _merge_defaults(default_value, value)
		elif default_value is int and value is float:
			# JSON parses every number as float; restore the int default's type.
			result[key] = int(value)
		elif default_value != null and typeof(value) != typeof(default_value):
			pass  # Keep the default.
		else:
			result[key] = value
	return result
