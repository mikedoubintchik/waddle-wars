extends Control
## Studio splash: wordmark eases in with a fade + scale settle and an
## expanding accent rule, holds, then fades and routes to title.

var _elapsed: float = 0.0
var _routed: bool = false
var _studio_label: Label
var _sub_label: Label
var _rule: ColorRect


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.06, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var glow_grad := Gradient.new()
	glow_grad.colors = PackedColorArray([
		Color(0.14, 0.26, 0.44, 0.55), Color(0.03, 0.06, 0.12, 0.0),
	])
	glow_grad.offsets = PackedFloat32Array([0.0, 1.0])
	var glow_tex := GradientTexture2D.new()
	glow_tex.gradient = glow_grad
	glow_tex.fill = GradientTexture2D.FILL_RADIAL
	glow_tex.fill_from = Vector2(0.5, 0.5)
	glow_tex.fill_to = Vector2(0.5, 0.0)
	var glow := TextureRect.new()
	glow.texture = glow_tex
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	center.add_child(vbox)

	_studio_label = Label.new()
	_studio_label.text = GameConfig.STUDIO_NAME
	_studio_label.add_theme_font_override("font", UITheme.display_font())
	_studio_label.add_theme_font_size_override("font_size", 64)
	_studio_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	_studio_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.5))
	_studio_label.add_theme_constant_override("shadow_offset_x", 0)
	_studio_label.add_theme_constant_override("shadow_offset_y", 4)
	_studio_label.add_theme_constant_override("shadow_outline_size", 8)
	_studio_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_studio_label.modulate.a = 0.0
	vbox.add_child(_studio_label)

	var rule_holder := CenterContainer.new()
	vbox.add_child(rule_holder)
	_rule = ColorRect.new()
	_rule.color = Color(UITheme.COLOR_ACCENT, 0.85)
	_rule.custom_minimum_size = Vector2(0.0, 3.0)
	rule_holder.add_child(_rule)

	_sub_label = Label.new()
	_sub_label.text = "presents"
	_sub_label.add_theme_font_size_override("font_size", 24)
	_sub_label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.75))
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.modulate.a = 0.0
	vbox.add_child(_sub_label)

	if GameConfig.is_headless():
		return

	# Wordmark settles from slightly large; pivot needs post-layout size.
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_studio_label.pivot_offset = _studio_label.size * 0.5
	_studio_label.scale = Vector2(1.12, 1.12)

	var tween := create_tween()
	tween.tween_property(_studio_label, "modulate:a", 1.0, 0.55)
	tween.parallel().tween_property(_studio_label, "scale", Vector2.ONE, 0.7) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_rule, "custom_minimum_size:x", 280.0, 0.7) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_sub_label, "modulate:a", 1.0, 0.85)
	tween.tween_interval(0.8)
	tween.tween_property(_studio_label, "modulate:a", 0.0, 0.4)
	tween.parallel().tween_property(_sub_label, "modulate:a", 0.0, 0.4)
	tween.parallel().tween_property(_rule, "modulate:a", 0.0, 0.4)


func _process(delta: float) -> void:
	_elapsed += delta
	var skip := Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("pause")
	if not _routed and (_elapsed > 2.4 or skip):
		_routed = true
		SceneRouter.go_to(Game.SCENE_TITLE)
