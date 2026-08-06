extends Node
## Scene transitions with a fade overlay and an achievement toast layer.

signal scene_changed(path: String)

const FADE_TIME: float = 0.35

var _overlay_layer: CanvasLayer
var _fade_rect: ColorRect
var _loading_label: Label
var _loading_box: VBoxContainer
var _toast_layer: CanvasLayer
var _busy: bool = false
var _mute_layer: CanvasLayer
var _mute_toast: Label = null
var _perf: PerfTicker = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	# Busy state is a row of dancing penguins over the word, not a bare label.
	_loading_box = VBoxContainer.new()
	_loading_box.set_anchors_preset(Control.PRESET_CENTER)
	_loading_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_loading_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_loading_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_loading_box.add_theme_constant_override("separation", 10)
	_loading_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_box.modulate.a = 0.0
	_loading_box.visible = false
	_fade_rect.add_child(_loading_box)
	if not GameConfig.is_headless():
		var dancers := PenguinLoader.new(150.0)
		dancers.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_loading_box.add_child(dancers)
	_loading_label = Label.new()
	_loading_label.text = "Loading…"
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.add_theme_font_size_override("font_size", 28)
	_loading_label.add_theme_color_override("font_color", Color(0.72, 0.82, 0.95))
	_loading_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_box.add_child(_loading_label)
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
	var tween := create_tween()
	tween.tween_property(_fade_rect, "modulate:a", 1.0, FADE_TIME)
	tween.tween_callback(_change_now.bind(scene_path))


func is_busy() -> bool:
	return _busy


func _change_now(scene_path: String) -> void:
	# A pause trigger (Escape, focus loss, controller disconnect) during the
	# fade would leave the next scene permanently paused; force unpause here
	# and again after the deferred swap change_scene_to_file performs.
	get_tree().paused = false
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("SceneRouter: failed to change scene to %s (%d)" % [scene_path, err])
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
func _fade_out_when_scene_drawn() -> void:
	for i: int in 3:
		await RenderingServer.frame_post_draw
	var tween := create_tween()
	tween.tween_property(_fade_rect, "modulate:a", 0.0, FADE_TIME)
	tween.parallel().tween_property(_loading_box, "modulate:a", 0.0, FADE_TIME * 0.6)
	tween.parallel().tween_callback(func() -> void: _loading_box.visible = false).set_delay(FADE_TIME * 0.6)
	tween.tween_callback(func() -> void:
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE)


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

