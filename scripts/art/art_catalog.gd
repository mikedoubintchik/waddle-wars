class_name ArtCatalog
extends Resource
## Deterministic runtime manifest plus explicit lazy-preload cache.

const SCHEMA_VERSION: int = 1
const DEFAULT_MANIFEST_PATH: String = "res://assets/art/art_manifest.json"
const REQUEST_DRAIN = preload("res://scripts/utilities/threaded_resource_drain.gd")
const ALLOWED_KINDS: PackedStringArray = [
	"scene", "animation_library", "material", "texture", "mesh", "resource",
]
const PREVIEW_FRAGMENT_KEYS: PackedStringArray = [
	"concepts", "generated_assets", "runtime_assets", "source_exports",
]
const PREVIEW_RUNTIME_ROOT: String = "res://assets/art/"

@export_file("*.json") var manifest_path: String = DEFAULT_MANIFEST_PATH
@export var strict_paths: bool = true

var _manifest: Dictionary = {}
var _entries: Dictionary = {}
var _errors := PackedStringArray()
var _pending: Dictionary = {}
var _loaded: Dictionary = {}
var _failed: Dictionary = {}
## Debug/editor-only entries staged from an honest production_ready=false art
## fragment. Release catalogs never see these IDs; reload_manifest() removes
## the overlay and restores the canonical manifest exactly.
var _preview_ids := PackedStringArray()


func reload_manifest() -> Error:
	_abandon_pending()
	_manifest = {}
	_entries.clear()
	_errors.clear()
	_loaded.clear()
	_failed.clear()
	_preview_ids.clear()
	if manifest_path.is_empty() or not FileAccess.file_exists(manifest_path):
		_errors.append("manifest not found: %s" % manifest_path)
		return ERR_FILE_NOT_FOUND
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		_errors.append("cannot open manifest: %s" % manifest_path)
		return FileAccess.get_open_error()
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		_errors.append("manifest JSON error at line %d: %s" % [parser.get_error_line(), parser.get_error_message()])
		return parse_error
	if not parser.data is Dictionary:
		_errors.append("manifest root must be an object")
		return ERR_INVALID_DATA
	_manifest = parser.data
	_index_manifest()
	if not _errors.is_empty():
		# Indexing is transactional: never expose valid-looking entries from a
		# manifest whose sibling fields or entries failed validation. Keeping
		# `_manifest` populated here would let `_ensure_loaded()` return OK on a
		# later call and bypass the original reload error.
		_manifest = {}
		_entries.clear()
		return ERR_INVALID_DATA
	return OK


func manifest_errors() -> PackedStringArray:
	return _errors.duplicate()


func manifest() -> Dictionary:
	return _manifest.duplicate(true)


## Pure policy seam so tests can prove release exports cannot opt into review
## art even though the test process itself runs from a debug editor binary.
static func preview_overlay_allowed(debug_build: bool, editor_build: bool) -> bool:
	return debug_build or editor_build


func preview_overlay_active() -> bool:
	return not _preview_ids.is_empty()


func preview_asset_ids() -> PackedStringArray:
	return _preview_ids.duplicate()


## Transactionally adds review-only runtime assets from a fragment. Every
## entry must explicitly remain production_ready=false and resolve below the
## runtime art root. Any bad sibling rejects the whole call: existing entries,
## manifest state and resource caches remain unchanged.
func apply_preview_fragment(fragment_path: String) -> Error:
	if not preview_overlay_allowed(OS.is_debug_build(), OS.has_feature("editor")):
		_errors.append("preview overlay denied outside debug/editor builds")
		return ERR_UNAUTHORIZED
	var manifest_error := _ensure_loaded()
	if manifest_error != OK:
		return manifest_error
	if not fragment_path.begins_with("res://") or not FileAccess.file_exists(fragment_path):
		_errors.append("preview fragment must be an existing local res:// file: %s" % fragment_path)
		return ERR_FILE_NOT_FOUND
	var file := FileAccess.open(fragment_path, FileAccess.READ)
	if file == null:
		_errors.append("cannot open preview fragment: %s" % fragment_path)
		return FileAccess.get_open_error()
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		_errors.append("preview fragment JSON error at line %d: %s" % [
			parser.get_error_line(), parser.get_error_message(),
		])
		return parse_error
	if not parser.data is Dictionary:
		_errors.append("preview fragment root must be an object")
		return ERR_INVALID_DATA
	var fragment: Dictionary = parser.data
	var validation_errors := _preview_fragment_shape_errors(fragment)
	var staged: Dictionary = {}
	if validation_errors.is_empty():
		var runtime_assets: Array = fragment["runtime_assets"]
		for value: Variant in runtime_assets:
			if not value is Dictionary:
				validation_errors.append("runtime_assets entry must be an object")
				continue
			var entry: Dictionary = value
			var asset_id := String(entry.get("id", ""))
			var kind := String(entry.get("kind", ""))
			var path := String(entry.get("path", ""))
			if not _valid_id(asset_id):
				validation_errors.append("invalid preview asset ID: %s" % asset_id)
				continue
			if staged.has(asset_id):
				validation_errors.append("duplicate preview asset ID: %s" % asset_id)
				continue
			if kind not in ALLOWED_KINDS:
				validation_errors.append("preview asset '%s' has invalid kind '%s'" % [
					asset_id, kind,
				])
			if not entry.has("production_ready") or not entry["production_ready"] is bool \
					or bool(entry["production_ready"]):
				validation_errors.append(
					"preview asset '%s' must explicitly set production_ready=false" % asset_id)
			if not _valid_preview_runtime_path(path):
				validation_errors.append(
					"preview asset '%s' path must stay below %s: %s" % [
						asset_id, PREVIEW_RUNTIME_ROOT, path,
					])
			elif not ResourceLoader.exists(path):
				validation_errors.append(
					"preview asset '%s' resource does not exist: %s" % [asset_id, path])
			if _entries.has(asset_id):
				var existing: Dictionary = _entries[asset_id]
				if asset_id not in _preview_ids or existing != entry:
					validation_errors.append("preview asset ID conflicts with catalog: %s" % asset_id)
				continue
			staged[asset_id] = entry.duplicate(true)
	if not validation_errors.is_empty():
		for error: String in validation_errors:
			_errors.append("preview fragment: %s" % error)
		return ERR_INVALID_DATA

	# Commit only after every sibling passed. Sorted IDs make manifest output
	# deterministic even if fragment generation changes JSON entry order.
	var staged_ids := PackedStringArray()
	for value: Variant in staged.keys():
		staged_ids.append(String(value))
	staged_ids.sort()
	var assets: Array = (_manifest.get("assets", []) as Array).duplicate(true)
	for asset_id: String in staged_ids:
		var entry: Dictionary = staged[asset_id]
		_entries[asset_id] = entry.duplicate(true)
		assets.append(entry.duplicate(true))
		_preview_ids.append(asset_id)
	_preview_ids.sort()
	_manifest["assets"] = assets
	return OK


func budgets() -> Dictionary:
	var value: Variant = _manifest.get("budgets", {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func asset_ids(group: String = "") -> PackedStringArray:
	_ensure_loaded()
	var ids := PackedStringArray()
	for asset_id: String in _entries.keys():
		var entry: Dictionary = _entries[asset_id]
		if group.is_empty() or group in _string_array(entry.get("groups", [])):
			ids.append(asset_id)
	ids.sort()
	return ids


func has_asset(asset_id: String) -> bool:
	_ensure_loaded()
	return _entries.has(asset_id)


func asset_entry(asset_id: String) -> Dictionary:
	_ensure_loaded()
	var value: Variant = _entries.get(asset_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func asset_path(asset_id: String) -> String:
	_ensure_loaded()
	return String((_entries.get(asset_id, {}) as Dictionary).get("path", ""))


func begin_preload(asset_ids_to_load: PackedStringArray) -> Error:
	REQUEST_DRAIN.watch_shutdown()
	var load_error := _ensure_loaded()
	if load_error != OK:
		return load_error
	var first_error := OK
	for asset_id: String in asset_ids_to_load:
		if _loaded.has(asset_id) or _pending.has(asset_id):
			continue
		if not _entries.has(asset_id):
			_failed[asset_id] = "unknown asset ID"
			if first_error == OK:
				first_error = ERR_DOES_NOT_EXIST
			continue
		var path := String((_entries[asset_id] as Dictionary).get("path", ""))
		if not ResourceLoader.exists(path):
			_failed[asset_id] = "resource not found: %s" % path
			if first_error == OK:
				first_error = ERR_FILE_NOT_FOUND
			continue
		if GameConfig.is_headless():
			# Godot 4.7.1's dummy renderer has non-thread-safe material/mesh
			# RID owners. Parallel resource decoding can corrupt their allocation
			# even though no frame is drawn. Upstream reproduces this on 4.7.1:
			# https://github.com/godotengine/godot/issues/121949
			# The engine fix targets 4.8 (PR 121958); preserve our 4.7.1 pin and
			# load synchronously only when there is no interactive loading UI.
			var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
			if resource == null:
				_failed[asset_id] = "resource load returned null: %s" % path
				if first_error == OK:
					first_error = ERR_CANT_OPEN
			else:
				_loaded[asset_id] = resource
			continue
		var request_error := ResourceLoader.load_threaded_request(
			path, "", true, ResourceLoader.CACHE_MODE_REUSE
		)
		if request_error != OK:
			_failed[asset_id] = "threaded request failed: %d" % request_error
			if first_error == OK:
				first_error = request_error
			continue
		_pending[asset_id] = path
	return first_error


func begin_preload_group(group: String) -> Error:
	return begin_preload(asset_ids(group))


func poll_preload() -> Dictionary:
	var completed: Array[String] = []
	for asset_id: Variant in _pending.keys():
		var id := String(asset_id)
		var path := String(_pending[id])
		var progress: Array = []
		var status := ResourceLoader.load_threaded_get_status(path, progress)
		match status:
			ResourceLoader.THREAD_LOAD_LOADED:
				var resource := ResourceLoader.load_threaded_get(path)
				if resource == null:
					_failed[id] = "threaded load returned null: %s" % path
				else:
					_loaded[id] = resource
				completed.append(id)
			ResourceLoader.THREAD_LOAD_FAILED:
				# Failed jobs retain their ResourceLoader token until collected too.
				ResourceLoader.load_threaded_get(path)
				_failed[id] = "threaded load failed: %s" % path
				completed.append(id)
			ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_failed[id] = "threaded load failed: %s" % path
				completed.append(id)
	for asset_id: String in completed:
		_pending.erase(asset_id)
	return preload_status()


func preload_status() -> Dictionary:
	var total := _pending.size() + _loaded.size() + _failed.size()
	var finished := _loaded.size() + _failed.size()
	return {
		"total": total,
		"pending": _pending.size(),
		"loaded": _loaded.size(),
		"failed": _failed.size(),
		"progress": 1.0 if total == 0 else float(finished) / float(total),
		"complete": _pending.is_empty(),
		"failures": _failed.duplicate(true),
	}


func load_now(asset_id: String) -> Resource:
	if _loaded.has(asset_id):
		return _loaded[asset_id] as Resource
	if _ensure_loaded() != OK or not _entries.has(asset_id):
		return null
	var path := String((_entries[asset_id] as Dictionary).get("path", ""))
	if not ResourceLoader.exists(path):
		_failed[asset_id] = "resource not found: %s" % path
		return null
	var resource := ResourceLoader.load(path)
	if resource == null:
		_failed[asset_id] = "resource load returned null: %s" % path
		return null
	_loaded[asset_id] = resource
	return resource


func loaded_resource(asset_id: String) -> Resource:
	return _loaded.get(asset_id, null) as Resource


func instantiate_scene(asset_id: String) -> Node:
	var resource := loaded_resource(asset_id)
	if resource == null:
		resource = load_now(asset_id)
	var packed := resource as PackedScene
	if packed == null:
		_failed[asset_id] = "asset is not a PackedScene"
		return null
	return packed.instantiate()


func clear_runtime_cache() -> void:
	_abandon_pending()
	_loaded.clear()
	_failed.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# A RefCounted reaches this notification after its reference count is
		# zero: do not dispatch another instance method on the dying Resource.
		for path: String in _pending.values():
			REQUEST_DRAIN.abandon(path)
		_pending.clear()


func _abandon_pending() -> void:
	for path: String in _pending.values():
		REQUEST_DRAIN.abandon(path)
	_pending.clear()


func _ensure_loaded() -> Error:
	return reload_manifest() if _manifest.is_empty() else OK


func _index_manifest() -> void:
	if int(_manifest.get("schema_version", -1)) != SCHEMA_VERSION:
		_errors.append("schema_version must be %d" % SCHEMA_VERSION)
	if String(_manifest.get("catalog_id", "")).is_empty():
		_errors.append("catalog_id is required")
	var assets: Variant = _manifest.get("assets", [])
	if not assets is Array:
		_errors.append("assets must be an array")
		return
	for value: Variant in assets:
		if not value is Dictionary:
			_errors.append("asset entry must be an object")
			continue
		var entry: Dictionary = value
		var asset_id := String(entry.get("id", ""))
		var kind := String(entry.get("kind", ""))
		var path := String(entry.get("path", ""))
		if not _valid_id(asset_id):
			_errors.append("invalid asset ID: %s" % asset_id)
			continue
		if _entries.has(asset_id):
			_errors.append("duplicate asset ID: %s" % asset_id)
			continue
		if kind not in ALLOWED_KINDS:
			_errors.append("asset '%s' has invalid kind '%s'" % [asset_id, kind])
		if not path.begins_with("res://"):
			_errors.append("asset '%s' path must be a res:// resource" % asset_id)
		elif strict_paths and not path.begins_with("res://assets/art/"):
			_errors.append("asset '%s' path must be below res://assets/art/" % asset_id)
		elif strict_paths and not ResourceLoader.exists(path):
			_errors.append("asset '%s' resource does not exist: %s" % [asset_id, path])
		_entries[asset_id] = entry.duplicate(true)


static func _string_array(value: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if value is Array or value is PackedStringArray:
		for item: Variant in value:
			result.append(String(item))
	return result


static func _preview_fragment_shape_errors(fragment: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var keys := PackedStringArray()
	for key: Variant in fragment.keys():
		keys.append(String(key))
	keys.sort()
	if keys != PREVIEW_FRAGMENT_KEYS:
		errors.append("fragment must contain exactly %s" % str(PREVIEW_FRAGMENT_KEYS))
		return errors
	for key: String in PREVIEW_FRAGMENT_KEYS:
		if not fragment[key] is Array:
			errors.append("%s must be an array" % key)
	return errors


static func _valid_preview_runtime_path(path: String) -> bool:
	if not path.begins_with(PREVIEW_RUNTIME_ROOT) or path.contains("\\"):
		return false
	var relative := path.trim_prefix(PREVIEW_RUNTIME_ROOT)
	if relative.is_empty():
		return false
	for segment: String in relative.split("/", true):
		if segment.is_empty() or segment == "." or segment == "..":
			return false
	var runtime_root := ProjectSettings.globalize_path(PREVIEW_RUNTIME_ROOT).simplify_path()
	var candidate := ProjectSettings.globalize_path(path).simplify_path()
	return candidate.begins_with(runtime_root.trim_suffix("/") + "/")


static func _valid_id(value: String) -> bool:
	if value.is_empty():
		return false
	for index: int in value.length():
		var code := value.unicode_at(index)
		var allowed := code >= 97 and code <= 122
		allowed = allowed or (index > 0 and code >= 48 and code <= 57)
		allowed = allowed or (index > 0 and code == 95)
		if not allowed:
			return false
	return true
