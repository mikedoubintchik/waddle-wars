extends Control
## Keep the OS launch composition on screen until the one SceneRouter loader
## takes over. BootWarmup belongs to SceneRouter so it survives this scene.

const PORTRAIT_STILL := "res://assets/art/ui/menu/launch_screen_portrait_v1.png"
const LANDSCAPE_BACKDROP := "res://assets/art/ui/menu/loader_background_v3.webp"
const LOGO := "res://assets/art/ui/menu/loader_logo_v3.webp"

var _routed := false
var _first_frame: TextureRect
var _landscape_logo: TextureRect


func _ready() -> void:
	if BootProfiler.enabled():
		print("[ww-startup] boot_ready_ms=", Time.get_ticks_msec())
	_build_first_frame()
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_apply_layout):
		viewport.size_changed.connect(_apply_layout)
	# The web page owns its cover until the main menu's first draw.
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"if (window.__wwGraphicsAdvice && "
			+ "typeof window.__wwGraphicsAdvice.inspectRunningCanvas === 'function') { "
			+ "window.__wwGraphicsAdvice.inspectRunningCanvas(); }", true)
	BootWarmup.warm(SceneRouter)
	if BootProfiler.enabled():
		print("[ww-startup] boot_warm_requested_ms=", Time.get_ticks_msec())
	if GameConfig.is_headless():
		_route.call_deferred()
	else:
		_upgrade_after_first_present()


func _build_first_frame() -> void:
	_first_frame = TextureRect.new()
	_first_frame.name = "LaunchStill"
	_first_frame.texture = load(PORTRAIT_STILL) as Texture2D
	_first_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_first_frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_first_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_first_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_first_frame)
	_apply_layout()


func _apply_layout() -> void:
	if _first_frame == null:
		return
	var view := get_viewport().get_visible_rect().size
	var landscape := view.x > view.y
	if not landscape:
		_first_frame.texture = load(PORTRAIT_STILL) as Texture2D
		if _landscape_logo != null:
			_landscape_logo.visible = false
		return
	_first_frame.texture = load(LANDSCAPE_BACKDROP) as Texture2D
	if _landscape_logo == null:
		_landscape_logo = TextureRect.new()
		_landscape_logo.name = "LandscapeLaunchLogo"
		_landscape_logo.texture = load(LOGO) as Texture2D
		_landscape_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_landscape_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_landscape_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_landscape_logo)
	var card_width := minf(1000.0, minf(view.x * 0.90, view.y * 1.025))
	var logo_size := Vector2(card_width * 0.64, card_width * 0.332)
	_landscape_logo.position = Vector2((view.x - logo_size.x) * 0.5, view.y * 0.055)
	_landscape_logo.size = logo_size
	_landscape_logo.visible = true


func _upgrade_after_first_present() -> void:
	# Leave the first draw callback before creating the richer loader. The
	# destination's resource work waits behind SceneRouter's own draw boundary.
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_route()


func _route() -> void:
	if _routed:
		return
	_routed = true
	if BootProfiler.enabled():
		print("[ww-startup] boot_route_ms=", Time.get_ticks_msec(),
			" warm_done=", BootWarmup.is_finished())
	SceneRouter.go_to(Game.SCENE_MAIN_MENU)
