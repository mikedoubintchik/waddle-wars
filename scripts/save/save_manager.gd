extends Node
## Versioned local save data with atomic writes and graceful recovery.

signal save_loaded
signal save_written

const SAVE_PATH: String = "user://save.json"
const SAVE_TMP_PATH: String = "user://save.json.tmp"
const SAVE_BACKUP_PATH: String = "user://save.json.bak"

var data: Dictionary = {}
var _dirty: bool = false


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
		"gp_records": {},
		"settings_migrated": true,
	}


func load_save() -> void:
	var loaded: Dictionary = _read_json(SAVE_PATH)
	if loaded.is_empty():
		loaded = _read_json(SAVE_BACKUP_PATH)
	data = _merge_defaults(default_save(), loaded)
	data["version"] = GameConfig.SAVE_VERSION
	save_loaded.emit()


func mark_dirty() -> void:
	_dirty = true


func save_now() -> void:
	_dirty = false
	var json := JSON.stringify(data, "\t")
	var file := FileAccess.open(SAVE_TMP_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SaveManager: cannot open %s for writing" % SAVE_TMP_PATH)
		return
	file.store_string(json)
	file.close()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.copy_absolute(
			ProjectSettings.globalize_path(SAVE_PATH),
			ProjectSettings.globalize_path(SAVE_BACKUP_PATH)
		)
	var err := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(SAVE_TMP_PATH),
		ProjectSettings.globalize_path(SAVE_PATH)
	)
	if err != OK:
		push_warning("SaveManager: atomic rename failed (%d)" % err)
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
	data = _merge_defaults(default_save(), cloud_data)
	data["version"] = GameConfig.SAVE_VERSION
	save_now()
	save_loaded.emit()


func get_value(key: String, default_value: Variant = null) -> Variant:
	return data.get(key, default_value)


func set_value(key: String, value: Variant, autosave: bool = true) -> void:
	data[key] = value
	if autosave:
		mark_dirty()


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
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_warning("SaveManager: invalid save data at %s, using defaults" % path)
	return {}


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
