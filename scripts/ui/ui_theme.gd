class_name UITheme
extends RefCounted
## Shared UI styling helpers: consistent colors, buttons with visible
## hover/focus/pressed/disabled states, panels, headings, and the animated
## menu backdrop (gradient + aurora sweep + drifting snow) used by every menu.

const COLOR_BG: Color = Color(0.078, 0.141, 0.239)  # deep navy
const COLOR_BG_DARK: Color = Color(0.055, 0.098, 0.172)
const COLOR_BG_DEEP: Color = Color(0.031, 0.055, 0.106)
const COLOR_PANEL: Color = Color(0.075, 0.129, 0.220, 0.94)
const COLOR_ACCENT: Color = Color(0.498, 0.816, 0.968)  # ice blue #7fd0f7
const COLOR_GOLD: Color = Color(0.961, 0.773, 0.259)  # gold #f5c542
const COLOR_TEXT: Color = Color(0.93, 0.96, 1.0)
const COLOR_TEXT_DIM: Color = Color(0.62, 0.72, 0.84)
const COLOR_DISABLED: Color = Color(0.42, 0.48, 0.58)
const COLOR_SHADOW: Color = Color(0.0, 0.0, 0.0, 0.35)

## Standard side margin for full-screen menu layouts.
const SCREEN_MARGIN: int = 48

## Minimum comfortable touch target height (logical px) and list spacing on
## touch devices. Applied centrally so every menu inherits them.
const TOUCH_MIN_HEIGHT: int = 48
const TOUCH_SPACING: int = 12

## Left-edge back-swipe gesture tuning (attach_swipe_back).
const SWIPE_BACK_EDGE_WIDTH: float = 36.0
const SWIPE_BACK_DISTANCE: float = 80.0
const SWIPE_BACK_TIME_MS: int = 600

const AURORA_SHADER_CODE: String = """
shader_type canvas_item;
render_mode blend_add;
uniform float strength = 0.16;
void fragment() {
	float t = TIME * 0.045;
	vec2 uv = UV;
	float wave1 = sin(uv.x * 4.4 + t * 6.0) * 0.13 + sin(uv.x * 9.7 - t * 4.0) * 0.05;
	float wave2 = sin(uv.x * 3.1 - t * 5.0 + 1.7) * 0.16 + sin(uv.x * 7.3 + t * 3.0) * 0.04;
	float band1 = exp(-pow((uv.y - 0.30 - wave1) * 6.0, 2.0));
	float band2 = exp(-pow((uv.y - 0.52 - wave2) * 7.5, 2.0));
	vec3 aurora = vec3(0.20, 0.95, 0.70) * band1 + vec3(0.45, 0.35, 0.95) * band2;
	float fade = smoothstep(1.0, 0.35, uv.y);
	float side = smoothstep(0.0, 0.12, uv.x) * smoothstep(1.0, 0.88, uv.x);
	COLOR = vec4(aurora * strength * fade * (0.6 + 0.4 * side), 1.0);
}
"""

static var _display_font: FontVariation = null
static var _button_font: FontVariation = null


## True when a touchscreen is present (phones, tablets, touch laptops).
## Headless runs always report false so sims stay deterministic.
static func is_touch() -> bool:
	if GameConfig.is_headless():
		return false
	return DisplayServer.is_touchscreen_available()


## List/row separation helper: authored value on desktop, at least
## TOUCH_SPACING on touch devices so rows never crowd fingertips.
static func spacing(base: int) -> int:
	return maxi(base, TOUCH_SPACING) if is_touch() else base


## Emboldened, letter-spaced variation of the default font for large headers.
static func display_font() -> FontVariation:
	if _display_font == null:
		_display_font = FontVariation.new()
		_display_font.base_font = ThemeDB.fallback_font
		_display_font.variation_embolden = 0.65
		_display_font.spacing_glyph = 2
	return _display_font


## Slightly emboldened variation for buttons and emphasis labels.
static func bold_font() -> FontVariation:
	if _button_font == null:
		_button_font = FontVariation.new()
		_button_font.base_font = ThemeDB.fallback_font
		_button_font.variation_embolden = 0.35
	return _button_font


static func make_button(text: String, size: Vector2 = Vector2(320, 52), font_size: int = 24) -> Button:
	var button := Button.new()
	button.text = text
	if is_touch():
		size.y = maxf(size.y, float(TOUCH_MIN_HEIGHT))
	button.custom_minimum_size = size
	button.add_theme_font_override("font", bold_font())
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", COLOR_GOLD)
	button.add_theme_color_override("font_disabled_color", COLOR_DISABLED)

	var normal := _button_box(Color(0.106, 0.176, 0.290, 0.97), Color(COLOR_ACCENT, 0.22), 1)
	var hover := _button_box(Color(0.145, 0.235, 0.376), Color(COLOR_ACCENT, 0.9), 2)
	hover.shadow_size = 9
	hover.shadow_offset = Vector2(0.0, 5.0)
	var pressed := _button_box(Color(0.066, 0.114, 0.196), Color(COLOR_GOLD, 0.9), 2)
	pressed.shadow_size = 2
	pressed.shadow_offset = Vector2(0.0, 1.0)
	pressed.content_margin_top = 12.0
	pressed.content_margin_bottom = 8.0
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color(0.72, 0.92, 1.0)
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(13)
	focus.set_expand_margin_all(3.0)
	var disabled := _button_box(Color(0.082, 0.114, 0.165, 0.8), Color(0.16, 0.21, 0.28, 0.6), 1)
	disabled.shadow_size = 0

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_stylebox_override("disabled", disabled)
	attach_hover_scale(button, 1.02)
	return button


static func _button_box(bg: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(12)
	box.content_margin_left = 18.0
	box.content_margin_right = 18.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 10.0
	box.shadow_color = COLOR_SHADOW
	box.shadow_size = 6
	box.shadow_offset = Vector2(0.0, 3.0)
	return box


## Subtle grow-on-hover/focus with a press-down dip. Pivot tracks center.
static func attach_hover_scale(control: Control, amount: float = 1.02) -> void:
	control.pivot_offset = control.size * 0.5
	control.resized.connect(func() -> void:
		control.pivot_offset = control.size * 0.5)
	var grow := func() -> void: _scale_to(control, amount)
	var rest := func() -> void: _scale_to(control, 1.0)
	control.mouse_entered.connect(grow)
	control.mouse_exited.connect(rest)
	control.focus_entered.connect(grow)
	control.focus_exited.connect(rest)
	if control is BaseButton:
		var button := control as BaseButton
		button.button_down.connect(func() -> void:
			_scale_to(control, amount - 0.04))
		button.button_up.connect(func() -> void:
			var engaged := button.is_hovered() or button.has_focus()
			_scale_to(control, amount if engaged else 1.0))


static func _scale_to(control: Control, target: float) -> void:
	if not control.is_inside_tree():
		return
	if control.has_meta("_hover_tween"):
		var old: Variant = control.get_meta("_hover_tween")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	var tween := control.create_tween()
	tween.tween_property(control, "scale", Vector2(target, target), 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	control.set_meta("_hover_tween", tween)


static func make_panel_style(bg: Color = COLOR_PANEL, border: Color = Color(COLOR_ACCENT, 0.20)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(14)
	box.content_margin_left = 20.0
	box.content_margin_right = 20.0
	box.content_margin_top = 16.0
	box.content_margin_bottom = 16.0
	box.shadow_color = COLOR_SHADOW
	box.shadow_size = 8
	box.shadow_offset = Vector2(0.0, 4.0)
	return box


static func heading(text: String, size: int = 44) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", display_font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	label.add_theme_color_override("font_outline_color", COLOR_BG_DEEP)
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.4))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 4)
	label.add_theme_constant_override("shadow_outline_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


static func sub_label(text: String, size: int = 20) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	return label


## Thin horizontal accent rule used under headers and between sections.
static func accent_rule(width: float = 220.0, color: Color = COLOR_ACCENT) -> Control:
	var holder := CenterContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rule := ColorRect.new()
	rule.color = Color(color, 0.75)
	rule.custom_minimum_size = Vector2(width, 3.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(rule)
	return holder


## Rasterizes an inline SVG string into a texture. Returns null when the
## SVG module is unavailable (callers should fall back to text glyphs).
static func make_icon(svg: String, scale: float = 1.0) -> ImageTexture:
	var img := Image.new()
	if img.load_svg_from_string(svg, scale) != OK:
		return null
	return ImageTexture.create_from_image(img)


## Rounded gradient fill texture for ProgressBar fills (StyleBoxFlat cannot
## gradient). Lighter crest at the top gives bars a glassy read.
static func make_bar_fill(from: Color, to: Color) -> StyleBoxTexture:
	var w := 96
	var h := 16
	var radius := 6.0
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y: int in h:
		var shade := 1.0 + (0.5 - float(y) / float(h - 1)) * 0.28
		for x: int in w:
			var color := from.lerp(to, float(x) / float(w - 1))
			color.r = minf(color.r * shade, 1.0)
			color.g = minf(color.g * shade, 1.0)
			color.b = minf(color.b * shade, 1.0)
			var ax := minf(float(x), float(w - 1 - x))
			var ay := minf(float(y), float(h - 1 - y))
			if ax < radius and ay < radius:
				var dx := radius - ax
				var dy := radius - ay
				var dist := sqrt(dx * dx + dy * dy) - radius
				color.a *= clampf(0.5 - dist, 0.0, 1.0)
			img.set_pixel(x, y, color)
	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(img)
	sb.texture_margin_left = radius
	sb.texture_margin_right = radius
	return sb


## Themed track/grabber styling for HSliders so they match the panel system.
static func style_slider(slider: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = COLOR_BG_DEEP
	track.set_corner_radius_all(5)
	track.set_border_width_all(1)
	track.border_color = Color(COLOR_ACCENT, 0.25)
	track.content_margin_top = 5.0
	track.content_margin_bottom = 5.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(COLOR_ACCENT, 0.85)
	fill.set_corner_radius_all(5)
	fill.content_margin_top = 5.0
	fill.content_margin_bottom = 5.0
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	# Touchscreens get a taller control rect: the track stays slim but the
	# whole rect accepts drags, so fingertips land reliably.
	if is_touch():
		slider.custom_minimum_size.y = maxf(slider.custom_minimum_size.y, float(TOUCH_MIN_HEIGHT))


## Applies the button style family to an OptionButton picker.
static func style_option_button(picker: OptionButton) -> void:
	picker.add_theme_color_override("font_color", COLOR_TEXT)
	picker.add_theme_color_override("font_hover_color", Color.WHITE)
	picker.add_theme_color_override("font_focus_color", Color.WHITE)
	var normal := _button_box(Color(0.106, 0.176, 0.290, 0.97), Color(COLOR_ACCENT, 0.22), 1)
	normal.shadow_size = 3
	var hover := _button_box(Color(0.145, 0.235, 0.376), Color(COLOR_ACCENT, 0.9), 2)
	hover.shadow_size = 4
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color(0.72, 0.92, 1.0)
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(13)
	focus.set_expand_margin_all(2.0)
	picker.add_theme_stylebox_override("normal", normal)
	picker.add_theme_stylebox_override("hover", hover)
	picker.add_theme_stylebox_override("pressed", hover)
	picker.add_theme_stylebox_override("focus", focus)
	# Touchscreens: taller picker plus a roomier dropdown so each popup row
	# is a comfortable tap target.
	if is_touch():
		picker.custom_minimum_size.y = maxf(picker.custom_minimum_size.y, float(TOUCH_MIN_HEIGHT))
		var popup := picker.get_popup()
		popup.add_theme_font_size_override("font_size", 22)
		popup.add_theme_constant_override("v_separation", 16)


## Wires standard UI sounds onto a button. Call for every interactive button.
static func hook_sounds(button: BaseButton) -> void:
	button.mouse_entered.connect(AudioManager.ui_hover)
	button.focus_entered.connect(AudioManager.ui_hover)
	button.pressed.connect(AudioManager.ui_click)


## Left-edge right-swipe "back" gesture for touch menus. Adds an invisible
## SWIPE_BACK_EDGE_WIDTH-wide full-height strip along the left edge of
## `node`; a touch (or drag with the mouse) that starts inside the strip and
## travels right more than SWIPE_BACK_DISTANCE within SWIPE_BACK_TIME_MS
## fires `callback` once. The strip is edge-only, so sliders, lists, and
## buttons elsewhere on screen are unaffected. Call after building the
## menu's children so the strip sits on top of them. The callback should be
## the same action as the screen's Back button.
static func attach_swipe_back(node: Control, callback: Callable) -> void:
	var edge := Control.new()
	edge.name = "SwipeBackEdge"
	edge.anchor_left = 0.0
	edge.anchor_right = 0.0
	edge.anchor_top = 0.0
	edge.anchor_bottom = 1.0
	edge.offset_left = 0.0
	edge.offset_right = SWIPE_BACK_EDGE_WIDTH
	edge.offset_top = 0.0
	edge.offset_bottom = 0.0
	edge.mouse_filter = Control.MOUSE_FILTER_STOP
	edge.focus_mode = Control.FOCUS_NONE
	node.add_child(edge)
	# Gesture state shared by the lambda across events.
	var state := {"tracking": false, "start_x": 0.0, "start_ms": 0}
	edge.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			var touch := event as InputEventScreenTouch
			if touch.pressed:
				state["tracking"] = true
				state["start_x"] = touch.position.x
				state["start_ms"] = Time.get_ticks_msec()
			else:
				state["tracking"] = false
			return
		if event is InputEventMouseButton:
			var click := event as InputEventMouseButton
			if click.button_index == MOUSE_BUTTON_LEFT:
				if click.pressed:
					state["tracking"] = true
					state["start_x"] = click.position.x
					state["start_ms"] = Time.get_ticks_msec()
				else:
					state["tracking"] = false
			return
		if not bool(state["tracking"]):
			return
		var drag_x: float
		if event is InputEventScreenDrag:
			drag_x = (event as InputEventScreenDrag).position.x
		elif event is InputEventMouseMotion:
			drag_x = (event as InputEventMouseMotion).position.x
		else:
			return
		if Time.get_ticks_msec() - int(state["start_ms"]) > SWIPE_BACK_TIME_MS:
			state["tracking"] = false
			return
		if drag_x - float(state["start_x"]) >= SWIPE_BACK_DISTANCE:
			state["tracking"] = false
			AudioManager.ui_click()
			callback.call())


## Full-rect animated menu backdrop: three-stop navy gradient, faint aurora
## sweep, slow drifting snow, and a corner vignette. Quality-gated so low-end
## and headless runs stay cheap; menus are never a static flat color.
static func make_background(parent: Control) -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_BG_DEEP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)

	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(0.098, 0.169, 0.290), COLOR_BG, COLOR_BG_DEEP,
	])
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
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

	var quality := String(SettingsManager.get_setting("display", "particle_quality"))
	if not GameConfig.is_headless() and quality != "low":
		_add_aurora(parent)
		_add_snow(parent, quality)
	_add_vignette(parent)


static func _add_aurora(parent: Control) -> void:
	var aurora := ColorRect.new()
	aurora.anchor_left = 0.0
	aurora.anchor_top = 0.0
	aurora.anchor_right = 1.0
	aurora.anchor_bottom = 0.62
	aurora.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = AURORA_SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	var strength := 0.16
	if bool(SettingsManager.get_setting("accessibility", "reduced_flashing")):
		strength = 0.09
	material.set_shader_parameter("strength", strength)
	aurora.material = material
	parent.add_child(aurora)


static func _add_snow(parent: Control, quality: String) -> void:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(holder)
	var snow := CPUParticles2D.new()
	snow.amount = 40 if quality == "high" else 22
	snow.lifetime = 14.0
	snow.preprocess = 14.0
	snow.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	snow.emission_rect_extents = Vector2(1400.0, 8.0)
	snow.position = Vector2(parent.get_viewport_rect().size.x * 0.5, -16.0)
	snow.direction = Vector2(0.05, 1.0)
	snow.spread = 12.0
	snow.gravity = Vector2(0.0, 4.0)
	snow.initial_velocity_min = 26.0
	snow.initial_velocity_max = 58.0
	snow.scale_amount_min = 1.2
	snow.scale_amount_max = 3.2
	snow.angular_velocity_min = -40.0
	snow.angular_velocity_max = 40.0
	snow.color = Color(0.92, 0.96, 1.0, 0.5)
	holder.add_child(snow)


static func _add_vignette(parent: Control) -> void:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.30),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, -0.15)
	var vignette := TextureRect.new()
	vignette.texture = tex
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(vignette)


## Applies the accessibility ui_scale setting to a screen root.
static func apply_ui_scale(root: Control) -> void:
	var scale_value := clampf(float(SettingsManager.get_setting("accessibility", "ui_scale")), 0.8, 1.4)
	root.scale = Vector2(scale_value, scale_value)
	root.pivot_offset = root.get_viewport_rect().size * 0.5
