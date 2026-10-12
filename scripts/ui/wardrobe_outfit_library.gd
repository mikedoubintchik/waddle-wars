extends Node
## One serialized threaded load per open wardrobe, with a bounded texture LRU.
## Complete images are keyed by species/hat/eyewear/neckwear; trails are separate.

signal preview_changed(key: String, texture: Texture2D, state: String)

const MANIFEST_PATH := "res://data/wardrobe/outfits_v1.json"
const ASSET_PREFIX := "res://assets/art/ui/wardrobe_outfits_v1/"
const CACHE_LIMIT := 4
const EXPECTED_OUTFITS := 480
const REQUEST_DRAIN = preload("res://scripts/utilities/threaded_resource_drain.gd")

var entries: Dictionary = {}
var requested_key := ""
var state := "unavailable"
var current_texture: Texture2D = null
var _cache: Dictionary = {}
var _recent: Array[String] = []
var _pending_key := ""
var _pending_path := ""


func _ready() -> void:
	name = "WardrobeOutfitLibrary"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	if FileAccess.file_exists(MANIFEST_PATH):
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
		if manifest is Dictionary and manifest.get("entries") is Dictionary:
			entries = manifest["entries"].duplicate(true)


static func outfit_key(look: Dictionary) -> String:
	var ids: Array[String] = []
	for slot: String in ["body", "hat", "goggles", "scarf"]:
		var id := String(look.get(slot, "body_classic" if slot == "body" else ""))
		ids.append("none" if id.is_empty() else id)
	return "__".join(ids)


func select_outfit(look: Dictionary) -> void:
	var key := outfit_key(look)
	if requested_key == key:
		return
	requested_key = key
	current_texture = null
	if _cache.has(key):
		_touch(key)
		_publish(_cache[key] as Texture2D, "ready")
		return
	if _asset_path(key).is_empty():
		_publish(null, "unavailable")
		return
	_publish(null, "loading")
	if _pending_path.is_empty():
		_start_requested_load()


func _asset_path(key: String) -> String:
	var entry: Variant = entries.get(key)
	if not entry is Dictionary:
		return ""
	var path := String(entry.get("runtime", ""))
	if path != ASSET_PREFIX + key + ".webp" or not ResourceLoader.exists(path):
		return ""
	return path


func _start_requested_load() -> void:
	REQUEST_DRAIN.watch_shutdown()
	var path := _asset_path(requested_key)
	if path.is_empty():
		_publish(null, "unavailable")
		return
	_pending_key = requested_key
	_pending_path = path
	# IGNORE keeps browsing hundreds of outfits out of the shared resource
	# cache. Only this wardrobe's four explicitly retained textures persist.
	var error := ResourceLoader.load_threaded_request(path, "Texture2D", false, ResourceLoader.CACHE_MODE_IGNORE)
	if error != OK:
		_pending_key = ""
		_pending_path = ""
		_publish(null, "unavailable")
		return
	set_process(true)


func _process(_delta: float) -> void:
	var status := ResourceLoader.load_threaded_get_status(_pending_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	var completed_key := _pending_key
	var texture: Texture2D = null
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		texture = ResourceLoader.load_threaded_get(_pending_path) as Texture2D
	elif status == ResourceLoader.THREAD_LOAD_FAILED:
		ResourceLoader.load_threaded_get(_pending_path)
	_pending_key = ""
	_pending_path = ""
	set_process(false)
	if texture != null:
		_cache[completed_key] = texture
		_touch(completed_key)
		while _recent.size() > CACHE_LIMIT:
			_cache.erase(_recent.pop_front())
	if completed_key == requested_key:
		_publish(texture, "ready" if texture != null else "unavailable")
	elif state == "loading":
		# A rapid later selection owns the preview. Never flash the earlier
		# outfit or enqueue a second simultaneous texture load.
		_start_requested_load()


func _touch(key: String) -> void:
	_recent.erase(key)
	_recent.append(key)


func _publish(texture: Texture2D, next_state: String) -> void:
	current_texture = texture
	state = next_state
	preview_changed.emit(requested_key, current_texture, state)


func _exit_tree() -> void:
	if not _pending_path.is_empty():
		REQUEST_DRAIN.abandon(_pending_path)
	_pending_key = ""
	_pending_path = ""
	current_texture = null
	_cache.clear()
	_recent.clear()
