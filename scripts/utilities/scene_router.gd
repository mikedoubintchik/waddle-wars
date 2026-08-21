extends Node
## Scene transitions with a fade overlay and an achievement toast layer.

signal scene_changed(path: String)

const FADE_TIME: float = 0.35
## Upper bound on how long the loading overlay will wait for the incoming
## scene to finish assembling (staged course build, then ShaderWarmup).
## Generous enough for a cold Chrome cache on a slow phone, hard enough that a
## stuck build cannot strand the player on a loading screen.
const WARMUP_HOLD_FRAMES: int = 300

var _overlay_layer: CanvasLayer
var _fade_rect: ColorRect
var _loading_backdrop: FrontEndBackdrop
var _loading_card: PanelContainer
var _loading_label: Label
var _loading_progress: ProgressBar
var _loading_mascot: PenguinLoader
var _loading_box: VBoxContainer
var _toast_layer: CanvasLayer
var _busy: bool = false
var _pending_scene_path: String = ""
var _thread_progress: Array = []
var _mute_layer: CanvasLayer
var _mute_toast: Label = null
var _perf: PerfTicker = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Arm the motion-permission request at BOOT, not on the main menu.
	#
	# Armed from the menu, the first tap of the session -- Begin, on the title
	# screen -- happened before any listener existed and was wasted, so the
	# prompt could not appear until the second. Arming here, from an autoload,
	# means the very first press the player makes carries it, whatever screen
	# they land on. Deferred so the settings autoload is ready to be read.
	(func() -> void: TiltSteering.arm_permission_on_first_gesture(self)).call_deferred()
	# Profiling only: a frame-time line every couple of seconds, labelled with
	# the current scene, so in-game performance can be read off the console
	# instead of inferred from a browser task manager.
	_perf = PerfTicker.attach(self)
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 100
	add_child(_overlay_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.03, 0.06, 0.12, 1.0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.modulate.a = 0.0
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_layer.add_child(_fade_rect)
	# Compact expedition card. The mascot is a cached 2D cutout, so it remains
	# drawable while ResourceLoader works and adds no second 3D renderer.
	_loading_card = PanelContainer.new()
	_loading_card.set_anchors_preset(Control.PRESET_CENTER)
	_loading_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_loading_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_loading_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.025, 0.065, 0.125, 0.92)
	card_style.border_color = Color(0.38, 0.78, 0.94, 0.42)
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(24)
	card_style.shadow_color = Color(0.0, 0.0, 0.0, 0.34)
	card_style.shadow_size = 18
	card_style.content_margin_left = 34.0
	card_style.content_margin_right = 34.0
	card_style.content_margin_top = 24.0
	card_style.content_margin_bottom = 26.0
	_loading_card.add_theme_stylebox_override("panel", card_style)
	_fade_rect.add_child(_loading_card)

	_loading_box = VBoxContainer.new()
	_loading_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_loading_box.add_theme_constant_override("separation", 8)
	_loading_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_box.modulate.a = 0.0
	_loading_box.visible = false
	_loading_card.add_child(_loading_box)
	var route := Label.new()
	route.text = "EXPEDITION ROUTE"
	route.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	route.add_theme_font_override("font", UITheme.bold_font())
	route.add_theme_font_size_override("font_size", 14)
	route.add_theme_color_override("font_color", Color(0.52, 0.88, 1.0))
	route.add_theme_constant_override("outline_size", 5)
	route.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.10, 0.9))
	route.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_box.add_child(route)
	_loading_label = Label.new()
	_loading_label.text = "Preparing expedition…"
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.add_theme_font_override("font", UITheme.ui_font())
	_loading_label.add_theme_font_size_override("font_size", 22)
	_loading_label.add_theme_color_override("font_color", Color(0.88, 0.95, 1.0))
	_loading_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_box.add_child(_loading_label)
	_loading_progress = ProgressBar.new()
	_loading_progress.custom_minimum_size = Vector2(320.0, 12.0)
	_loading_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loading_progress.show_percentage = false
	_loading_progress.min_value = 0.0
	_loading_progress.max_value = 1.0
	_loading_progress.value = 0.0
	var rail := StyleBoxFlat.new()
	rail.bg_color = Color(0.02, 0.05, 0.10, 0.82)
	rail.set_corner_radius_all(8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.32, 0.88, 0.74)
	fill.set_corner_radius_all(8)
	_loading_progress.add_theme_stylebox_override("background", rail)
	_loading_progress.add_theme_stylebox_override("fill", fill)
	_loading_box.add_child(_loading_progress)
	_layout_loading_card()
	get_viewport().size_changed.connect(_layout_loading_card)
	_toast_layer = CanvasLayer.new()
	_toast_layer.layer = 99
	add_child(_toast_layer)
	Progression.achievement_unlocked.connect(_on_achievement_unlocked)
	_mute_layer = CanvasLayer.new()
	_mute_layer.layer = 98
	add_child(_mute_layer)


func go_to(scene_path: String) -> void:
	if _busy:
		return
	_busy = true
	get_tree().paused = false
	if GameConfig.is_headless():
		_change_now(scene_path)
		return
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	# Loading text rides the fade so heavy scene builds (course generation,
	# first-run WebGL shader compiles) never leave an unlabeled blank screen.
	_loading_box.visible = true
	_loading_box.modulate.a = 1.0
	_set_loading_stage("Preparing expedition…", 0.04)
	var tween := create_tween()
	tween.tween_property(_fade_rect, "modulate:a", 1.0, FADE_TIME)
	tween.tween_callback(_begin_threaded_load.bind(scene_path))


func is_busy() -> bool:
	return _busy


func _ensure_loading_presentation() -> void:
	# SceneRouter is an autoload, so constructing texture-backed Controls in
	# `_ready()` would decode them before the boot scene presents. BootWarmup
	# primes these caches after the first visible frame; create the actual nodes
	# only when the first transition asks for them.
	if GameConfig.is_headless():
		return
	if _loading_backdrop == null:
		_loading_backdrop = FrontEndBackdrop.new()
		_loading_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
		_loading_backdrop.set_presentation(
			FrontEndBackdrop.Context.LOADING, 0.74, true)
		_fade_rect.add_child(_loading_backdrop)
		_fade_rect.move_child(_loading_backdrop, 0)
	if _loading_mascot == null:
		_loading_mascot = PenguinLoader.new(176.0)
		_loading_mascot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_loading_box.add_child(_loading_mascot)
		# Route eyebrow stays first; mascot precedes stage text and progress rail.
		_loading_box.move_child(_loading_mascot, 1)


func _process(_delta: float) -> void:
	if _pending_scene_path.is_empty():
		return
	_thread_progress.clear()
	var status := ResourceLoader.load_threaded_get_status(
		_pending_scene_path, _thread_progress)
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			var fraction := 0.0
			if not _thread_progress.is_empty():
				fraction = clampf(float(_thread_progress[0]), 0.0, 1.0)
			_set_loading_stage("Packing the sled…", 0.08 + fraction * 0.48)
		ResourceLoader.THREAD_LOAD_LOADED:
			var path := _pending_scene_path
			_pending_scene_path = ""
			_set_loading_stage("Opening the route…", 0.62)
			var packed := ResourceLoader.load_threaded_get(path) as PackedScene
			if packed == null:
				push_error("SceneRouter: threaded load returned no PackedScene for %s" % path)
				_change_now(path)
			else:
				_change_to_packed(packed, path)
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			var path := _pending_scene_path
			_pending_scene_path = ""
			push_warning("SceneRouter: background load failed; retrying %s synchronously" % path)
			_change_now(path)


func _begin_threaded_load(scene_path: String) -> void:
	# Resource files load off the main thread. Instantiation still occurs on the
	# main thread, but the authored loader keeps drawing through the expensive
	# disk/dependency phase instead of freezing before the scene swap.
	# Build texture-backed presentation only after the plain fade is opaque, so
	# an early boot-skip can never stall the first visible splash frame.
	_ensure_loading_presentation()
	var err := ResourceLoader.load_threaded_request(scene_path, "PackedScene", true)
	if err != OK:
		push_warning("SceneRouter: could not start background load for %s (%d)" \
			% [scene_path, err])
		_change_now(scene_path)
		return
	_pending_scene_path = scene_path
	_set_loading_stage("Packing the sled…", 0.08)


func _change_now(scene_path: String) -> void:
	# A pause trigger (Escape, focus loss, controller disconnect) during the
	# fade would leave the next scene permanently paused; force unpause here
	# and again after the deferred swap change_scene_to_file performs.
	get_tree().paused = false
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("SceneRouter: failed to change scene to %s (%d)" % [scene_path, err])
	(func() -> void: get_tree().paused = false).call_deferred()
	_finish_scene_swap(scene_path)


func _change_to_packed(packed: PackedScene, scene_path: String) -> void:
	get_tree().paused = false
	var err := get_tree().change_scene_to_packed(packed)
	if err != OK:
		push_error("SceneRouter: failed to instantiate %s (%d)" % [scene_path, err])
	_finish_scene_swap(scene_path)


func _finish_scene_swap(scene_path: String) -> void:
	(func() -> void: get_tree().paused = false).call_deferred()
	_busy = false
	scene_changed.emit(scene_path)
	if _perf != null:
		_perf.set_scene_label(scene_path.get_file().get_basename())
	if not GameConfig.is_headless():
		_fade_out_when_scene_drawn()


## Holds the overlay until the incoming scene has actually presented a few
## frames — on web the first draws stall on shader compilation, and fading
## out immediately exposed seconds of half-built sky ("blue screen").
##
## It now also waits out the incoming scene's ShaderWarmup rather than lifting
## after a fixed three frames. Course construction is cheap (30-65 ms measured
## headless across all five courses); what actually costs seconds on the web
## build is linking every material's GL program, and ANGLE charges milliseconds
## per link where Safari's native path charges microseconds. ShaderWarmup does
## that work a bounded chunk per frame, so holding the overlay over it means
## the loading penguin keeps animating through the expensive part and the race
## opens on programs that are already linked — instead of the overlay lifting
## early and dumping the stall into the first seconds of the race.
func _fade_out_when_scene_drawn() -> void:
	_set_loading_stage("Warming the trail…", 0.76)
	for i: int in 3:
		await RenderingServer.frame_post_draw
	# Cap the wait: a warmup that somehow never finishes must not strand the
	# player on a loading screen.
	for i: int in WARMUP_HOLD_FRAMES:
		if get_tree() == null or not _scene_is_building():
			break
		await RenderingServer.frame_post_draw
	_set_loading_stage("Expedition ready", 1.0)
	var tween := create_tween()
	tween.tween_property(_fade_rect, "modulate:a", 0.0, FADE_TIME)
	tween.parallel().tween_property(_loading_box, "modulate:a", 0.0, FADE_TIME * 0.6)
	tween.parallel().tween_callback(func() -> void: _loading_box.visible = false).set_delay(FADE_TIME * 0.6)
	tween.tween_callback(func() -> void:
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE)


func _set_loading_stage(text: String, progress: float) -> void:
	if _loading_label != null:
		_loading_label.text = text
	if _loading_progress != null:
		_loading_progress.value = clampf(progress, 0.0, 1.0)
	if _loading_mascot != null:
		_loading_mascot.set_progress(progress)


func _layout_loading_card() -> void:
	if _loading_card == null:
		return
	var view := get_viewport().get_visible_rect().size
	var width := minf(520.0, maxf(340.0, view.x * 0.72))
	_loading_card.offset_left = -width * 0.5
	_loading_card.offset_right = width * 0.5
	_loading_card.offset_top = -178.0
	_loading_card.offset_bottom = 178.0


## True while the incoming scene is still assembling itself: a staged course
## build, a staged Waddle Run build, or a ShaderWarmup pass still linking
## programs. Web splits construction across frames so this overlay's penguins
## keep dancing through it; either way the scene underneath is not presentable
## yet.
func _scene_is_building() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	for child: Node in scene.get_children():
		if child is ShaderWarmup:
			return true
		if child is CourseBase and not (child as CourseBase).build_finished:
			return true
		if child is RunnerGame and not (child as RunnerGame).build_finished:
			return true
	return false


func _on_achievement_unlocked(id: String) -> void:
	if GameConfig.is_headless():
		return
	var info := AchievementsDB.get_item(id)
	if info.is_empty():
		return
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.14, 0.24, 0.92)
	style.border_color = Color(0.98, 0.8, 0.2)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "Achievement Unlocked!"
	title.add_theme_color_override("font_color", Color(0.98, 0.8, 0.2))
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)
	var name_label := Label.new()
	name_label.text = String(info["name"])
	name_label.add_theme_font_size_override("font_size", 26)
	vbox.add_child(name_label)
	_toast_layer.add_child(panel)
	panel.reset_size()
	var viewport_size := _toast_layer.get_viewport().get_visible_rect().size
	panel.position = Vector2(viewport_size.x - panel.size.x - 24.0, -panel.size.y - 10.0)
	var tween := create_tween()
	tween.tween_property(panel, "position:y", 24.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(2.6)
	tween.tween_property(panel, "position:y", -panel.size.y - 10.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(panel.queue_free)


## Global mute hotkey (M). Lives here rather than in the race scene so it
## works on menus, results and mid-race alike; the pause-menu toggle writes
## the same setting.
func _unhandled_input(event: InputEvent) -> void:
	if GameConfig.is_headless() or not event.is_action_pressed("mute_audio"):
		return
	var now_muted := not bool(SettingsManager.get_setting("audio", "muted"))
	SettingsManager.set_setting("audio", "muted", now_muted)
	_show_mute_toast("Sound muted" if now_muted else "Sound on")
	get_viewport().set_input_as_handled()


func _show_mute_toast(text: String) -> void:
	if _mute_toast != null and is_instance_valid(_mute_toast):
		_mute_toast.queue_free()
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.offset_top = 96.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.03, 0.06, 0.12, 0.85))
	label.add_theme_constant_override("outline_size", 8)
	_mute_layer.add_child(label)
	_mute_toast = label
	var tween := label.create_tween()
	tween.tween_interval(1.0)
	tween.tween_property(label, "modulate:a", 0.0, 0.4)
	tween.tween_callback(label.queue_free)
