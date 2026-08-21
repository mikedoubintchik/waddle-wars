class_name BootWarmup
extends Node
## Lightweight front-end cache warmup.
##
## First boot frame presents before synchronous asset work begins. Authored
## Canvas textures, UI font, title music, and cached logo then load once and
## draw as tiny probes behind opaque splash for two frames. No SubViewport,
## Node3D, particles, lights, or gameplay shader compilation. Course-specific
## ShaderWarmup remains responsible for gameplay programs behind loading UI.

const DRAIN_FRAMES: int = 2
const PROBE_SIDE: float = 4.0
const FRONTEND_TEXTURE_PATHS: PackedStringArray = [
	"res://assets/art/ui/title_expedition_landscape_v1.png",
	"res://assets/art/ui/title_expedition_portrait_v1.png",
	"res://assets/art/ui/loader_penguin_expedition_v1.png",
]

static var _done: bool = false
static var _finished: bool = true

var _probe_layer: CanvasLayer = null


static func warm(host: Node) -> BootWarmup:
	if host == null or GameConfig.is_headless() or _done:
		_finished = true
		return null
	_done = true
	_finished = false
	var node := BootWarmup.new()
	node.name = "BootWarmup"
	host.add_child(node)
	return node


static func is_finished() -> bool:
	return _finished


func _ready() -> void:
	process_priority = -100
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Do not hide first launch behind texture decoding. Splash presents once,
	# then absorbs cache work while its own simple Canvas tween remains visible.
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	_begin_upload_probes()
	var textures: Array[Texture2D] = await _load_front_end_assets()
	if not is_inside_tree():
		return
	BootProfiler.step("2d assets cached (%d)" % textures.size())
	for _i: int in DRAIN_FRAMES:
		await RenderingServer.frame_post_draw
		if not is_inside_tree():
			return
	_finished = true
	queue_free()


func _exit_tree() -> void:
	_finished = true
	_probe_layer = null


func _load_front_end_assets() -> Array[Texture2D]:
	var textures: Array[Texture2D] = []
	# Font and streams keep their own session caches.
	UITheme.runtime_theme()
	AudioManager.preload_stream("music_title")

	var logo := TitleScreen.logo_texture()
	if logo != null:
		textures.append(logo)
		_add_upload_probe(logo, textures.size() - 1)
		await RenderingServer.frame_post_draw
		if not is_inside_tree():
			return textures

	# Request and present one authored texture at a time. Worker decode remains
	# asynchronous, while each Compatibility upload/conversion gets its own
	# rendered frame instead of accumulating into one 55-67 ms submission.
	for path: String in FRONTEND_TEXTURE_PATHS:
		var texture: Texture2D = await _load_threaded_texture(path)
		if texture != null:
			textures.append(texture)
			_add_upload_probe(texture, textures.size() - 1)
			await RenderingServer.frame_post_draw
			if not is_inside_tree():
				return textures

	# Facades adopt ResourceLoader's live cache; no second decode or upload.
	FrontEndBackdrop.preload_assets()
	PenguinLoader.loader_texture()
	return textures


func _load_threaded_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		push_warning("BootWarmup: frontend texture missing: %s" % path)
		return null
	var request_error := ResourceLoader.load_threaded_request(
		path, "Texture2D", true, ResourceLoader.CACHE_MODE_REUSE)
	if request_error != OK:
		push_warning("BootWarmup: threaded request failed for %s (%d)" % [
			path, request_error])
		return ResourceLoader.load(path) as Texture2D
	for _frame: int in 300:
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			return ResourceLoader.load_threaded_get(path) as Texture2D
		if status == ResourceLoader.THREAD_LOAD_FAILED \
				or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_warning("BootWarmup: threaded load failed for %s" % path)
			return ResourceLoader.load(path) as Texture2D
		await get_tree().process_frame
		if not is_inside_tree():
			return null
	push_warning("BootWarmup: threaded load timed out for %s" % path)
	return ResourceLoader.load(path) as Texture2D


func _begin_upload_probes() -> void:
	_probe_layer = CanvasLayer.new()
	_probe_layer.name = "CanvasUploadProbes"
	_probe_layer.layer = -100
	add_child(_probe_layer)


func _add_upload_probe(texture: Texture2D, index: int) -> void:
	if _probe_layer == null or texture == null:
		return
	var probe := TextureRect.new()
	probe.name = "TextureProbe%d" % index
	probe.texture = texture
	probe.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	probe.stretch_mode = TextureRect.STRETCH_SCALE
	probe.position = Vector2(float(index) * PROBE_SIDE, 0.0)
	probe.size = Vector2(PROBE_SIDE, PROBE_SIDE)
	probe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_probe_layer.add_child(probe)
