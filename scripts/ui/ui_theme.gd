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

## Spacing rhythm used across every menu: small (within a group), medium
## (between groups), large (between major regions). Prefer these three steps
## over ad-hoc values so screens share one vertical rhythm.
const SPACE_S: int = 16
const SPACE_M: int = 24
const SPACE_L: int = 40

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

## Drawn menu icon glyphs (64x64 SVG, same hand-drawn style as the fish icon
## in main_menu/race_hud). Used by make_menu_button for the primary menus.
const ICON_PLAY: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M18 10 L54 32 L18 54 Z" fill="#7fe08f" stroke="#3f8f55" stroke-width="3" stroke-linejoin="round"/>
<path d="M24 18 L24 46" stroke="#b8f0c4" stroke-width="3" stroke-linecap="round" opacity="0.7"/>
</svg>"""

const ICON_SCHOOL: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M32 10 L60 23 L32 36 L4 23 Z" fill="#6fa8d8" stroke="#3d6d94" stroke-width="2" stroke-linejoin="round"/>
<path d="M16 30 V44 Q32 52 48 44 V30" fill="#4d7fae" stroke="#3d6d94" stroke-width="2"/>
<path d="M56 25 V42" stroke="#f5c542" stroke-width="3" stroke-linecap="round"/>
<circle cx="56" cy="45" r="3" fill="#f5c542"/>
</svg>"""

const ICON_PALETTE: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M32 6 C17 6 5 17 5 31 C5 45 16 57 30 58 C36 58 38 52 34 48 C30 44 33 39 39 39 L46 39 C53 39 59 33 59 25 C59 13 47 6 32 6 Z" fill="#e8ddc8" stroke="#a08e6e" stroke-width="2"/>
<circle cx="20" cy="22" r="4" fill="#ff6b57"/>
<circle cx="34" cy="16" r="4" fill="#f5c542"/>
<circle cx="46" cy="22" r="4" fill="#7fe08f"/>
<circle cx="16" cy="36" r="4" fill="#6fa8d8"/>
</svg>"""

const ICON_TROPHY: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M17 12 C7 12 7 28 19 29" stroke="#f5c542" stroke-width="4" fill="none"/>
<path d="M47 12 C57 12 57 28 45 29" stroke="#f5c542" stroke-width="4" fill="none"/>
<path d="M18 8 H46 V22 C46 34 40 40 32 40 C24 40 18 34 18 22 Z" fill="#f5c542" stroke="#c98f1b" stroke-width="2"/>
<rect x="28" y="40" width="8" height="8" fill="#e0b030"/>
<rect x="20" y="48" width="24" height="7" rx="2" fill="#c98f1b"/>
<path d="M24 14 L27 22 L24 30" stroke="#fff2c0" stroke-width="3" fill="none" opacity="0.8"/>
</svg>"""

const ICON_GEAR: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<g stroke="#9fc4e0" stroke-width="7" stroke-linecap="round" fill="none">
<path d="M32 8 V16 M32 48 V56 M8 32 H16 M48 32 H56 M15 15 L21 21 M43 43 L49 49 M49 15 L43 21 M21 43 L15 49"/>
<circle cx="32" cy="32" r="14"/>
</g>
<circle cx="32" cy="32" r="5" fill="#22303f"/>
</svg>"""

const ICON_FILM: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<rect x="8" y="14" width="48" height="40" rx="4" fill="#5a7ba6" stroke="#3d5578" stroke-width="2"/>
<path d="M8 26 H56" stroke="#3d5578" stroke-width="2.5"/>
<path d="M12 14 L20 26 M24 14 L32 26 M36 14 L44 26 M48 14 L56 26" stroke="#d7e6f5" stroke-width="3"/>
<path d="M16 38 L28 34 M16 46 L34 44" stroke="#9fc4e0" stroke-width="3" stroke-linecap="round" opacity="0.8"/>
</svg>"""

const ICON_DOOR: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M10 8 H38 V56 H10 Z" fill="#7a5c40" stroke="#54402c" stroke-width="2" stroke-linejoin="round"/>
<circle cx="31" cy="33" r="2.6" fill="#f5c542"/>
<path d="M42 32 H58 M51 24 L59 32 L51 40" stroke="#9fc4e0" stroke-width="4" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
</svg>"""

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


## Side margin for full-screen menu layouts: SCREEN_MARGIN on desktop, the
## large rhythm step on phones so content keeps generous but usable margins
## inside a 390pt-wide portrait viewport.
static func screen_margin() -> int:
	return SPACE_L if is_touch() else SCREEN_MARGIN


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

	# Frosted-glass state family: translucent fill lets the animated backdrop
	# glow through; an icy rim plus inner top-highlight / bottom-shade strips
	# (added below) give each button glassy depth. Hover lifts (brighter rim,
	# larger shadow, 1.02 scale); pressed compresses (0.98 scale, tight shadow).
	var normal := _button_box(Color(0.141, 0.227, 0.365, 0.58), Color(0.78, 0.90, 1.0, 0.22), 1)
	var hover := _button_box(Color(0.196, 0.310, 0.478, 0.76), Color(COLOR_ACCENT, 0.95), 2)
	hover.shadow_size = 10
	hover.shadow_offset = Vector2(0.0, 5.0)
	var pressed := _button_box(Color(0.055, 0.098, 0.176, 0.85), Color(COLOR_GOLD, 0.9), 2)
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
	var disabled := _button_box(Color(0.082, 0.114, 0.165, 0.55), Color(0.16, 0.21, 0.28, 0.5), 1)
	disabled.shadow_size = 0

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_stylebox_override("disabled", disabled)
	_attach_glass_edges(button)
	attach_hover_scale(button, 1.02)
	return button


## Standard stacked-menu button with a leading drawn-icon glyph (see the
## ICON_* consts). Falls back to the plain themed button when the SVG module
## is unavailable, so headless runs and sims are unaffected.
static func make_menu_button(text: String, icon_svg: String, size: Vector2 = Vector2(520, 72), font_size: int = 32) -> Button:
	var button := make_button(text, size, font_size)
	if icon_svg != "":
		var texture := make_icon(icon_svg, 1.0)
		if texture != null:
			button.icon = texture
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width", 34)
			button.add_theme_constant_override("h_separation", 14)
	return button


## Inner 1px top highlight + darker bottom shade strips: the two-tone edge
## treatment StyleBoxFlat cannot express (single border color). Strips are
## anchored to the button rect, inset past the corner radius, and inert.
static func _attach_glass_edges(button: Button) -> void:
	var sheen := ColorRect.new()
	sheen.name = "GlassSheen"
	sheen.color = Color(1.0, 1.0, 1.0, 0.10)
	sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheen.focus_mode = Control.FOCUS_NONE
	sheen.anchor_left = 0.0
	sheen.anchor_right = 1.0
	sheen.anchor_top = 0.0
	sheen.anchor_bottom = 0.0
	sheen.offset_left = 13.0
	sheen.offset_right = -13.0
	sheen.offset_top = 1.0
	sheen.offset_bottom = 2.5
	button.add_child(sheen)
	var shade := ColorRect.new()
	shade.name = "GlassShade"
	shade.color = Color(0.0, 0.0, 0.0, 0.16)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.focus_mode = Control.FOCUS_NONE
	shade.anchor_left = 0.0
	shade.anchor_right = 1.0
	shade.anchor_top = 1.0
	shade.anchor_bottom = 1.0
	shade.offset_left = 13.0
	shade.offset_right = -13.0
	shade.offset_top = -2.5
	shade.offset_bottom = -1.0
	button.add_child(shade)


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
	box.shadow_size = 5
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
## Grows from its center on screen entry (headless-safe no-op).
static func accent_rule(width: float = 220.0, color: Color = COLOR_ACCENT) -> Control:
	var holder := CenterContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rule := ColorRect.new()
	rule.color = Color(color, 0.75)
	rule.custom_minimum_size = Vector2(width, 3.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(rule)
	animate_rule(rule)
	return holder


## Grow-from-zero entrance for a rule/underline Control. Scale-only, so it
## never triggers container relayout; pivot centers when the rule has a fixed
## authored width and stays left-anchored for stretch-to-fill rules.
static func animate_rule(rule: Control) -> void:
	if GameConfig.is_headless():
		return
	var start := func() -> void:
		rule.pivot_offset = Vector2(rule.custom_minimum_size.x * 0.5, rule.custom_minimum_size.y * 0.5)
		rule.scale.x = 0.0
		var tween := rule.create_tween()
		tween.tween_interval(0.12)
		tween.tween_property(rule, "scale:x", 1.0, 0.5) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	rule.ready.connect(start, CONNECT_ONE_SHOT)


## Unified screen-entry transition: staggered fade + rise for a screen's main
## blocks (title, cards, buttons). Call from _ready after building children;
## no await needed by callers. Headless runs skip it entirely so sims and the
## unit suite see final layout immediately. Items freed mid-flight are skipped.
static func play_entrance(root: Control, items: Array[Control], rise: float = 20.0) -> void:
	if GameConfig.is_headless():
		return
	for item: Control in items:
		item.modulate.a = 0.0
	var tree := root.get_tree()
	if tree == null:
		for item: Control in items:
			item.modulate.a = 1.0
		return
	# Two frames before capturing target positions: queue_freed siblings leave
	# the tree and containers finish sorting (mode_select rebuilds steps).
	var second_frame := func() -> void:
		_start_entrance(root, items, rise)
	var first_frame := func() -> void:
		tree.process_frame.connect(second_frame, CONNECT_ONE_SHOT)
	tree.process_frame.connect(first_frame, CONNECT_ONE_SHOT)


static func _start_entrance(root: Control, items: Array[Control], rise: float) -> void:
	if not is_instance_valid(root) or not root.is_inside_tree():
		return
	for i: int in items.size():
		var item := items[i]
		if not is_instance_valid(item) or not item.is_inside_tree():
			continue
		var target_y := item.position.y
		item.position.y = target_y + rise
		var delay := minf(0.04 + 0.055 * float(i), 0.5)
		var tween := item.create_tween()
		tween.set_parallel(true)
		tween.tween_property(item, "modulate:a", 1.0, 0.24).set_delay(delay)
		tween.tween_property(item, "position:y", target_y, 0.32) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(delay)


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
	var normal := _button_box(Color(0.141, 0.227, 0.365, 0.62), Color(0.78, 0.90, 1.0, 0.22), 1)
	normal.shadow_size = 3
	var hover := _button_box(Color(0.196, 0.310, 0.478, 0.78), Color(COLOR_ACCENT, 0.95), 2)
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
