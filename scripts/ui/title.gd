class_name TitleScreen
extends Control
## Premium 2D title presentation.
##
## Authored expedition key art replaces former live 3D ocean diorama. Runtime
## work is one Canvas backdrop, logo, and ordinary UI Controls. Public scene,
## class, input behavior, and cached logo_texture() API remain compatible.

const MOTION_STEP: float = 1.0 / 30.0

## Authored wordmark is primary; original glyph skeletons remain as a
## deterministic fallback if the texture cannot load. BootWarmup primes it.
const AUTHORED_LOGO_PATH := "res://assets/art/ui/waddle_wars_wordmark_v4.png"
const LOGO_LETTERS: Dictionary = {
	"W": {"w": 96.0, "paths": ["M8 10 L30 90 L48 42 L66 90 L88 10"],
			"snow": [[8.0, -1.0, 12.0, 6.0], [88.0, -1.0, 12.0, 6.0]]},
	"A": {"w": 76.0, "paths": ["M8 90 L38 10 L68 90", "M22 62 L54 62"],
			"snow": [[38.0, -1.0, 13.0, 6.5]]},
	"D": {"w": 74.0, "paths": ["M10 90 L10 10 Q64 12 64 50 Q64 88 10 90 Z"],
			"snow": [[30.0, 0.0, 14.0, 6.0]]},
	"L": {"w": 58.0, "paths": ["M10 10 L10 90 L52 90"],
			"snow": [[10.0, -1.0, 11.0, 6.0]]},
	"E": {"w": 60.0, "paths": ["M52 10 L12 10 L12 90 L52 90", "M12 50 L44 50"],
			"snow": [[30.0, -2.0, 16.0, 6.0]]},
	"R": {"w": 70.0, "paths": ["M12 90 L12 10 Q60 10 60 32 Q60 54 12 54", "M34 54 L60 90"],
			"snow": [[28.0, -1.0, 14.0, 6.0]]},
	"S": {"w": 64.0, "paths": ["M54 20 C44 8 16 6 12 26 C9 44 52 48 54 68 C56 90 22 96 10 78"],
			"snow": [[33.0, -2.0, 12.0, 5.5]]},
}
const LOGO_LETTER_GAP: float = 14.0
const LOGO_LINE_H: float = 110.0
const LOGO_LINE_GAP: float = 16.0
const LOGO_MARGIN_X: float = 22.0
const LOGO_MARGIN_Y: float = 24.0
const LOGO_RENDER_SCALE: float = 3.0
const LOGO_ROT: Array[float] = [-2.2, 1.8, -1.5, 2.0, -1.8, 1.6]
const LOGO_DY: Array[float] = [3.0, -2.0, 2.0, -3.0, 2.0, -2.0]

static var _logo_texture: Texture2D = null
static var _logo_texture_aspect: float = 0.5

var _started: bool = false
var _reduced_motion: bool = false
var _elapsed: float = 0.0
var _motion_accumulator: float = 0.0

var _backdrop: FrontEndBackdrop = null
var _header: VBoxContainer = null
var _logo: Control = null
var _logo_rect: TextureRect = null
var _logo_aspect: float = 0.5
var _action_card: PanelContainer = null
var _prompt: Button = null
var _prompt_glow: Panel = null
var _version_chip: PanelContainer = null


func _ready() -> void:
	_reduced_motion = UITheme.reduced_motion()
	UITheme.apply_ui_scale(self)
	BootProfiler.begin("title-2d")
	_build_backdrop()
	_build_tap_catcher()
	_build_foreground()
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_apply_layout):
		viewport.size_changed.connect(_apply_layout)
	_apply_layout()
	BootProfiler.step("canvas composition")
	AudioManager.play_music("music_title")
	BootProfiler.step("audio")
	BootProfiler.present()
	set_process(not _reduced_motion and not GameConfig.is_headless())


func _build_backdrop() -> void:
	_backdrop = FrontEndBackdrop.new()
	_backdrop.name = "ExpeditionBackdrop"
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.set_presentation(FrontEndBackdrop.Context.TITLE, 0.52,
		not _reduced_motion)
	add_child(_backdrop)


## Full-screen flat button sits behind visible UI. Tapping scenery starts title;
## real CTA above it retains normal focus/hover/press semantics.
func _build_tap_catcher() -> void:
	var catcher := Button.new()
	catcher.name = "TapCatcher"
	catcher.flat = true
	catcher.focus_mode = Control.FOCUS_NONE
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catcher.pressed.connect(_start_game)
	add_child(catcher)


func _build_foreground() -> void:
	var overlay := Control.new()
	overlay.name = "TitleChrome"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	_header = VBoxContainer.new()
	_header.name = "BrandHeader"
	_header.alignment = BoxContainer.ALIGNMENT_CENTER
	_header.add_theme_constant_override("separation", 8)
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_header)

	var eyebrow := Label.new()
	eyebrow.text = "ANTARCTIC EXPEDITION"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_font_override("font", UITheme.bold_font())
	eyebrow.add_theme_font_size_override("font_size", 18)
	eyebrow.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
	eyebrow.add_theme_color_override("font_outline_color", Color(0.02, 0.06, 0.12, 0.88))
	eyebrow.add_theme_constant_override("outline_size", 7)
	eyebrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(eyebrow)

	_logo = _build_logo()
	if _logo == null:
		var fallback := Label.new()
		fallback.text = GameConfig.GAME_NAME.to_upper()
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.add_theme_font_override("font", UITheme.display_font())
		fallback.add_theme_font_size_override("font_size", 86)
		fallback.add_theme_color_override("font_color", Color(0.96, 0.99, 1.0))
		fallback.add_theme_color_override("font_outline_color", Color(0.03, 0.09, 0.18))
		fallback.add_theme_constant_override("outline_size", 14)
		_logo = fallback
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(_logo)

	var subtitle := Label.new()
	subtitle.text = "RACE THE ICE  ·  OUTRUN THE STORM"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_override("font", UITheme.bold_font())
	subtitle.add_theme_font_size_override("font_size", 17)
	subtitle.add_theme_color_override("font_color", Color(0.86, 0.94, 1.0))
	subtitle.add_theme_color_override("font_outline_color", Color(0.02, 0.06, 0.12, 0.92))
	subtitle.add_theme_constant_override("outline_size", 7)
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(subtitle)

	_action_card = PanelContainer.new()
	_action_card.name = "BeginExpeditionCard"
	_action_card.mouse_filter = Control.MOUSE_FILTER_PASS
	_action_card.add_theme_stylebox_override("panel", _action_card_style())
	overlay.add_child(_action_card)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 13)
	margin.add_theme_constant_override("margin_bottom", 12)
	_action_card.add_child(margin)
	var action_column := VBoxContainer.new()
	action_column.alignment = BoxContainer.ALIGNMENT_CENTER
	action_column.add_theme_constant_override("separation", 7)
	margin.add_child(action_column)

	var destination := Label.new()
	destination.text = "NEXT DEPARTURE  ·  RESEARCH CITY"
	destination.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	destination.add_theme_font_override("font", UITheme.caption_font())
	destination.add_theme_font_size_override("font_size", 15)
	destination.add_theme_color_override("font_color", Color(0.69, 0.84, 0.96))
	destination.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_column.add_child(destination)

	_prompt = UITheme.make_button("BEGIN EXPEDITION", Vector2(0.0, 70.0), 27)
	_prompt.name = "BeginExpedition"
	_prompt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_prompt(_prompt)
	_prompt.pressed.connect(_start_game)
	UITheme.hook_sounds(_prompt)
	action_column.add_child(_prompt)
	_prompt_glow = _build_prompt_glow(_prompt)

	var hint := Label.new()
	hint.text = "Tap anywhere  ·  Enter / A"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_override("font", UITheme.caption_font())
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.64, 0.76, 0.88))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_column.add_child(hint)

	_version_chip = PanelContainer.new()
	_version_chip.name = "VersionChip"
	_version_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var version_style := StyleBoxFlat.new()
	version_style.bg_color = Color(0.025, 0.07, 0.13, 0.72)
	version_style.border_color = Color(0.61, 0.86, 1.0, 0.38)
	version_style.set_border_width_all(1)
	version_style.set_corner_radius_all(10)
	version_style.content_margin_left = 11.0
	version_style.content_margin_right = 11.0
	version_style.content_margin_top = 4.0
	version_style.content_margin_bottom = 4.0
	_version_chip.add_theme_stylebox_override("panel", version_style)
	overlay.add_child(_version_chip)
	var version := Label.new()
	version.text = "v%s" % GameConfig.GAME_VERSION
	version.add_theme_font_override("font", UITheme.bold_font())
	version.add_theme_font_size_override("font_size", 14)
	version.add_theme_color_override("font_color", Color(0.80, 0.90, 1.0))
	version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_version_chip.add_child(version)
	_prompt.grab_focus.call_deferred()


func _apply_layout() -> void:
	if _header == null or _action_card == null:
		return
	var profile := LayoutProfile.for_viewport(get_viewport())
	var safe := profile.safe_rect
	var portrait := profile.is_portrait()

	var header_width := minf(safe.size.x * (0.88 if portrait else 0.58),
		600.0 if portrait else 680.0)
	var header_height := minf(safe.size.y * (0.34 if portrait else 0.49), 350.0)
	_header.anchor_left = 0.5
	_header.anchor_right = 0.5
	_header.anchor_top = 0.0
	_header.anchor_bottom = 0.0
	_header.offset_left = -header_width * 0.5
	_header.offset_right = header_width * 0.5
	_header.offset_top = safe.position.y + (20.0 if portrait else 16.0)
	_header.offset_bottom = _header.offset_top + header_height

	var card_width := minf(safe.size.x * (0.88 if portrait else 0.54), 500.0)
	var card_height := 158.0 if portrait else 150.0
	_action_card.anchor_left = 0.5
	_action_card.anchor_right = 0.5
	_action_card.anchor_top = 1.0
	_action_card.anchor_bottom = 1.0
	_action_card.offset_left = -card_width * 0.5
	_action_card.offset_right = card_width * 0.5
	_action_card.offset_bottom = -profile.safe_insets.w - (28.0 if portrait else 22.0)
	_action_card.offset_top = _action_card.offset_bottom - card_height

	_version_chip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_version_chip.offset_left = -120.0 - profile.safe_insets.z
	_version_chip.offset_right = -14.0 - profile.safe_insets.z
	_version_chip.offset_top = -42.0 - profile.safe_insets.w
	_version_chip.offset_bottom = -14.0 - profile.safe_insets.w
	_update_logo_size()


func _process(delta: float) -> void:
	_elapsed += delta
	_motion_accumulator += delta
	if _motion_accumulator < MOTION_STEP:
		return
	_motion_accumulator = fmod(_motion_accumulator, MOTION_STEP)
	if _logo != null:
		_logo.pivot_offset = _logo.size * 0.5
		var breath := 1.0 + sin(_elapsed * 0.78) * 0.004
		_logo.scale = Vector2.ONE * breath
	if _prompt_glow != null:
		_prompt_glow.modulate.a = 0.62 + sin(_elapsed * 2.0) * 0.16


func _build_logo() -> Control:
	var texture := logo_texture()
	if texture == null:
		return null
	_logo_aspect = _logo_texture_aspect
	_logo_rect = TextureRect.new()
	_logo_rect.name = "WaddleWarsLogo"
	_logo_rect.texture = texture
	_logo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	return _logo_rect


func _update_logo_size() -> void:
	if _logo_rect == null:
		return
	var profile := LayoutProfile.for_viewport(get_viewport())
	var portrait := profile.is_portrait()
	var width := clampf(profile.safe_rect.size.x * (0.82 if portrait else 0.45),
		260.0, 530.0)
	var height_cap := profile.safe_rect.size.y * (0.23 if portrait else 0.30)
	if width * _logo_aspect > height_cap:
		width = height_cap / _logo_aspect
	_logo_rect.custom_minimum_size = Vector2(width, width * _logo_aspect)


func _style_prompt(button: Button) -> void:
	var normal := _prompt_box(Color(0.055, 0.18, 0.29, 0.96),
		Color(0.58, 0.88, 1.0, 0.94), 10)
	var hover := _prompt_box(Color(0.075, 0.28, 0.42, 0.98),
		Color(0.85, 0.97, 1.0), 14)
	var pressed := _prompt_box(Color(0.035, 0.12, 0.22, 1.0),
		Color(1.0, 0.82, 0.34), 5)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_font_override("font", UITheme.bold_font())
	button.add_theme_color_override("font_color", Color(0.96, 0.99, 1.0))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color(1.0, 0.89, 0.55))


static func _prompt_box(fill: Color, border: Color, shadow: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(16)
	box.content_margin_left = 18.0
	box.content_margin_right = 18.0
	box.shadow_color = Color(0.01, 0.03, 0.07, 0.58)
	box.shadow_size = shadow
	box.shadow_offset = Vector2(0.0, 5.0)
	return box


static func _action_card_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.022, 0.065, 0.125, 0.88)
	box.border_color = Color(0.57, 0.84, 1.0, 0.58)
	box.set_border_width_all(2)
	box.set_corner_radius_all(22)
	box.shadow_color = Color(0.005, 0.018, 0.045, 0.74)
	box.shadow_size = 18
	box.shadow_offset = Vector2(0.0, 8.0)
	return box


func _build_prompt_glow(button: Button) -> Panel:
	var glow := Panel.new()
	glow.name = "BeginGlow"
	glow.show_behind_parent = true
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.offset_left = -5.0
	glow.offset_top = -5.0
	glow.offset_right = 5.0
	glow.offset_bottom = 5.0
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.border_color = Color(0.50, 0.86, 1.0, 0.78)
	box.set_border_width_all(2)
	box.set_corner_radius_all(20)
	box.shadow_color = Color(0.32, 0.72, 1.0, 0.38)
	box.shadow_size = 12
	glow.add_theme_stylebox_override("panel", box)
	button.add_child(glow)
	return glow


## Session-cached wordmark raster. Safe before title exists.
static func logo_texture() -> Texture2D:
	if _logo_texture != null:
		return _logo_texture
	var authored := load(AUTHORED_LOGO_PATH) as Texture2D
	if authored != null and authored.get_width() > 0:
		_logo_texture = authored
		_logo_texture_aspect = float(authored.get_height()) / float(authored.get_width())
		return _logo_texture
	var svg := _build_logo_svg()
	if svg.is_empty():
		return null
	var image := Image.new()
	if image.load_svg_from_string(svg, LOGO_RENDER_SCALE) != OK:
		return null
	_logo_texture = ImageTexture.create_from_image(image)
	return _logo_texture


static func _build_logo_svg() -> String:
	var words: PackedStringArray = GameConfig.GAME_NAME.to_upper().split(" ", false)
	if words.is_empty():
		return ""
	var line_widths: Array[float] = []
	var max_width := 0.0
	for word: String in words:
		var width := 0.0
		for ci: int in word.length():
			if not LOGO_LETTERS.has(word[ci]):
				return ""
			width += float((LOGO_LETTERS[word[ci]] as Dictionary)["w"])
		width += LOGO_LETTER_GAP * float(word.length() - 1)
		line_widths.append(width)
		max_width = maxf(max_width, width)

	var layout: Array[Array] = []
	var glyph_index := 0
	for li: int in words.size():
		var x := LOGO_MARGIN_X + (max_width - line_widths[li]) * 0.5
		var y := LOGO_MARGIN_Y + 4.0 + float(li) * (LOGO_LINE_H + LOGO_LINE_GAP)
		for ci: int in words[li].length():
			var glyph := LOGO_LETTERS[words[li][ci]] as Dictionary
			layout.append([glyph, x,
				y + LOGO_DY[glyph_index % LOGO_DY.size()],
				LOGO_ROT[glyph_index % LOGO_ROT.size()]])
			x += float(glyph["w"]) + LOGO_LETTER_GAP
			glyph_index += 1

	var canvas_width := max_width + LOGO_MARGIN_X * 2.0
	var canvas_height := LOGO_MARGIN_Y * 2.0 + float(words.size()) * LOGO_LINE_H \
		+ float(words.size() - 1) * LOGO_LINE_GAP
	_logo_texture_aspect = canvas_height / canvas_width
	var parts: PackedStringArray = []
	parts.append(
		'<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'
		% [int(canvas_width), int(canvas_height), int(canvas_width), int(canvas_height)])
	parts.append(
		'<defs><linearGradient id="ice" gradientUnits="userSpaceOnUse" x1="0" y1="-4" x2="0" y2="104">'
		+ '<stop offset="0" stop-color="#ffffff"/><stop offset="0.42" stop-color="#d9edff"/>'
		+ '<stop offset="1" stop-color="#7cc4ff"/></linearGradient></defs>')
	_append_stroke_layer(parts, layout, "#06132b", 30.0, 0.38, 9.0)
	_append_stroke_layer(parts, layout, "#0e2244", 28.0, 1.0, 0.0)
	_append_stroke_layer(parts, layout, "url(#ice)", 16.0, 1.0, 0.0)
	for entry: Array in layout:
		var glyph := entry[0] as Dictionary
		var transform := _letter_transform(entry, 0.0)
		for blob: Array in glyph["snow"] as Array:
			var cx := float(blob[0])
			var cy := float(blob[1])
			var rx := float(blob[2])
			var ry := float(blob[3])
			parts.append('<ellipse cx="%.1f" cy="%.1f" rx="%.1f" ry="%.1f" fill="#a8cdec" transform="%s"/>'
				% [cx, cy + 1.5, rx, ry, transform])
			parts.append('<ellipse cx="%.1f" cy="%.1f" rx="%.1f" ry="%.1f" fill="#ffffff" transform="%s"/>'
				% [cx, cy - 1.5, rx, ry, transform])
			parts.append('<ellipse cx="%.1f" cy="%.1f" rx="%.1f" ry="%.1f" fill="#ffffff" transform="%s"/>'
				% [cx + rx * 0.6, cy - 1.0, rx * 0.5, ry * 0.9, transform])
	parts.append("</svg>")
	return "".join(parts)


static func _letter_transform(entry: Array, extra_dy: float) -> String:
	var glyph := entry[0] as Dictionary
	return "translate(%.1f %.1f) rotate(%.1f %.1f 50)" % [
		float(entry[1]), float(entry[2]) + extra_dy,
		float(entry[3]), float(glyph["w"]) * 0.5]


static func _append_stroke_layer(parts: PackedStringArray, layout: Array[Array],
		stroke: String, width: float, opacity: float, dy: float) -> void:
	for entry: Array in layout:
		var glyph := entry[0] as Dictionary
		var transform := _letter_transform(entry, dy)
		for path: String in glyph["paths"] as Array:
			parts.append(
				('<path d="%s" transform="%s" fill="none" stroke="%s" stroke-opacity="%.2f"'
				+ ' stroke-width="%.1f" stroke-linecap="round" stroke-linejoin="round"/>')
				% [path, transform, stroke, opacity, width])


func _start_game() -> void:
	if _started:
		return
	_started = true
	AudioManager.ui_click()
	SceneRouter.go_to(Game.SCENE_MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("pause") \
			or (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventMouseButton and event.pressed):
		_start_game()
