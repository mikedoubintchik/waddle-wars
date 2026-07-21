class_name UITheme
extends RefCounted
## Shared UI styling helpers: consistent colors, buttons with visible
## hover/focus/pressed/disabled states, panels, and headings.

const COLOR_BG: Color = Color(0.078, 0.141, 0.239)  # deep navy
const COLOR_BG_DARK: Color = Color(0.055, 0.098, 0.172)
const COLOR_PANEL: Color = Color(0.106, 0.180, 0.298, 0.94)
const COLOR_ACCENT: Color = Color(0.498, 0.816, 0.968)  # ice blue #7fd0f7
const COLOR_GOLD: Color = Color(0.961, 0.773, 0.259)  # gold #f5c542
const COLOR_TEXT: Color = Color(0.93, 0.96, 1.0)
const COLOR_TEXT_DIM: Color = Color(0.62, 0.72, 0.84)
const COLOR_DISABLED: Color = Color(0.42, 0.48, 0.58)


static func make_button(text: String, size: Vector2 = Vector2(320, 52), font_size: int = 24) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = size
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", COLOR_GOLD)
	button.add_theme_color_override("font_disabled_color", COLOR_DISABLED)

	var normal := _button_box(Color(0.125, 0.208, 0.337), Color(0.22, 0.34, 0.5), 1)
	var hover := _button_box(Color(0.165, 0.263, 0.412), COLOR_ACCENT, 2)
	var pressed := _button_box(Color(0.09, 0.15, 0.25), COLOR_GOLD, 2)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = COLOR_ACCENT
	focus.set_border_width_all(3)
	focus.set_corner_radius_all(10)
	focus.set_expand_margin_all(2.0)
	var disabled := _button_box(Color(0.09, 0.13, 0.19), Color(0.16, 0.21, 0.28), 1)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_stylebox_override("disabled", disabled)
	return button


static func _button_box(bg: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(10)
	box.content_margin_left = 16.0
	box.content_margin_right = 16.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	return box


static func make_panel_style(bg: Color = COLOR_PANEL, border: Color = Color(0.22, 0.36, 0.52)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(12)
	box.content_margin_left = 18.0
	box.content_margin_right = 18.0
	box.content_margin_top = 14.0
	box.content_margin_bottom = 14.0
	return box


static func heading(text: String, size: int = 44) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	label.add_theme_color_override("font_outline_color", COLOR_BG_DARK)
	label.add_theme_constant_override("outline_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


static func sub_label(text: String, size: int = 20) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	return label


## Wires standard UI sounds onto a button. Call for every interactive button.
static func hook_sounds(button: BaseButton) -> void:
	button.mouse_entered.connect(AudioManager.ui_hover)
	button.focus_entered.connect(AudioManager.ui_hover)
	button.pressed.connect(AudioManager.ui_click)


## Full-rect deep-navy vertical gradient background.
static func make_background(parent: Control) -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_BG_DARK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	var grad := Gradient.new()
	grad.colors = PackedColorArray([COLOR_BG, COLOR_BG_DARK])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	var rect := TextureRect.new()
	rect.texture = tex
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)


## Applies the accessibility ui_scale setting to a screen root.
static func apply_ui_scale(root: Control) -> void:
	var scale_value := clampf(float(SettingsManager.get_setting("accessibility", "ui_scale")), 0.8, 1.4)
	root.scale = Vector2(scale_value, scale_value)
	root.pivot_offset = root.get_viewport_rect().size * 0.5
