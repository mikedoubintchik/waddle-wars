extends Control
## Studio splash: fades the studio wordmark in and out, then routes to title.

var _elapsed: float = 0.0
var _routed: bool = false
var _studio_label: Label
var _sub_label: Label


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.06, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	_studio_label = Label.new()
	_studio_label.text = GameConfig.STUDIO_NAME
	_studio_label.add_theme_font_size_override("font_size", 64)
	_studio_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	_studio_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_studio_label.modulate.a = 0.0
	vbox.add_child(_studio_label)

	_sub_label = Label.new()
	_sub_label.text = "presents"
	_sub_label.add_theme_font_size_override("font_size", 24)
	_sub_label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.75))
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.modulate.a = 0.0
	vbox.add_child(_sub_label)

	if GameConfig.is_headless():
		return

	var tween := create_tween()
	tween.tween_property(_studio_label, "modulate:a", 1.0, 0.6)
	tween.parallel().tween_property(_sub_label, "modulate:a", 1.0, 0.9)
	tween.tween_interval(0.9)
	tween.tween_property(_studio_label, "modulate:a", 0.0, 0.45)
	tween.parallel().tween_property(_sub_label, "modulate:a", 0.0, 0.45)


func _process(delta: float) -> void:
	_elapsed += delta
	var skip := Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("pause")
	if not _routed and (_elapsed > 2.4 or skip):
		_routed = true
		SceneRouter.go_to(Game.SCENE_TITLE)
