extends Node
## Scene transitions with a fade overlay and an achievement toast layer.

signal scene_changed(path: String)

const FADE_TIME: float = 0.35

var _overlay_layer: CanvasLayer
var _fade_rect: ColorRect
var _toast_layer: CanvasLayer
var _busy: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 100
	add_child(_overlay_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.03, 0.06, 0.12, 1.0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.modulate.a = 0.0
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_layer.add_child(_fade_rect)
	_toast_layer = CanvasLayer.new()
	_toast_layer.layer = 99
	add_child(_toast_layer)
	Progression.achievement_unlocked.connect(_on_achievement_unlocked)


func go_to(scene_path: String) -> void:
	if _busy:
		return
	_busy = true
	get_tree().paused = false
	if GameConfig.is_headless():
		_change_now(scene_path)
		return
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
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
	if not GameConfig.is_headless():
		var tween := create_tween()
		tween.tween_interval(0.05)
		tween.tween_property(_fade_rect, "modulate:a", 0.0, FADE_TIME)
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
