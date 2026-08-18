class_name RunnerHUD
extends CanvasLayer
## Waddle Run HUD: the headline card (distance + score), a supporting row of
## fish / multiplier / lives, a bottom avalanche gauge, the centred callout, and
## the end-of-run panel.
##
## Visual system is deliberately the racing HUD's, so a player moving between
## the two modes reads one interface rather than two: the same shared card art
## (UITheme.make_card_style), the same value-over-caption type pair, the same
## GUTTER / GAP_S / GAP_M rhythm, and UITheme's palette throughout.
##
## Layout is one centred instrument stack at the top plus one gauge at the
## bottom, with nothing parked in the corners. That is what makes it survive a
## portrait phone: the design canvas pins its height, so a portrait viewport is
## only ~370 logical units wide and any left/right pair of cards would collide.
## The headline card and the end-of-run buttons flip from a row to a column
## under NARROW_WIDTH instead (see _relayout).
##
## set_stats runs once a frame, so every readout remembers the value it is
## currently showing and only touches a Label when that value actually changes.
## The steady-state per-frame cost is two float writes (the gauge value and the
## danger veil's alpha); a String is only built on the frame a number moves.

signal restart_pressed
signal menu_pressed

## --- Layout rhythm ----------------------------------------------------------
const GUTTER: float = 24.0          ## Screen-edge margin (UITheme.SPACE_M).
const GAP_S: int = 6                ## Inside a group.
const GAP_M: int = 12               ## Between groups.

## Viewport width (logical units) below which the headline card and the
## end-of-run button pair stack vertically. A landscape phone clears this
## comfortably; a portrait one never does.
const NARROW_WIDTH: float = 620.0

## --- Avalanche read ---------------------------------------------------------
## Gap at which the gauge starts warming toward red, and the gap at which the
## HUD commits to the full danger read (red veil, red numerals, pulsing tag).
const WARN_GAP: float = 18.0
const DANGER_GAP: float = 10.0
## Peak opacity of the screen-edge danger veil, reached as the gap hits zero.
const VEIL_ALPHA: float = 0.62
const GAUGE_WIDTH: float = 400.0
const GAUGE_HEIGHT: float = 16.0

## Warning red, shared by the gauge fill, the metre readout and the veil.
const COLOR_DANGER: Color = Color(1.0, 0.36, 0.30)

## Edge-weighted red wash, baked once and shared: the "the wall is right behind
## you" cue that a number in the corner cannot deliver on its own.
static var _veil_texture: GradientTexture2D = null

var _root: Control = null
## Accessibility HUD scale. The in-run readouts follow the racing HUD and take
## only this; they must NOT also take UITheme's menu touch step, because
## SettingsManager already shrinks the whole canvas on touch devices. The
## end-of-run panel is a menu, so that one does use the UITheme.scaled* helpers.
var _hud_scale: float = 1.0

var _top_box: BoxContainer = null
var _top_divider: ColorRect = null
var _distance_label: Label = null
var _score_label: Label = null
var _fish_label: Label = null
var _lives_pill: PanelContainer = null
var _life_pips: Array[Panel] = []
var _pip_alive: StyleBoxFlat = null
var _pip_spent: StyleBoxFlat = null
var _multiplier_chip: PanelContainer = null
var _multiplier_label: Label = null
var _chip_quiet: StyleBoxFlat = null
var _chip_hot: StyleBoxFlat = null
var _gauge_holder: VBoxContainer = null
var _gauge_bar: ProgressBar = null
var _gauge_tag: Label = null
var _gauge_value: Label = null
var _danger_veil: TextureRect = null
var _danger_tween: Tween = null
var _message_label: Label = null
var _message_tween: Tween = null
var _game_over: Control = null
var _game_over_buttons: BoxContainer = null

## Values currently on screen. Every one of them is compared before its Label is
## touched, so a 60 fps caller does not rebuild six strings a frame.
var _shown_distance: int = -1
var _shown_score: int = -1
var _shown_fish: int = -1
var _shown_multiplier: int = -1
var _shown_hits: int = -1
var _shown_gap: int = -1
var _in_danger: bool = false


## --- Build ------------------------------------------------------------------

func setup() -> void:
	if _root != null:
		return
	_hud_scale = float(SettingsManager.get_setting("accessibility", "hud_scale"))
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Veil first: it is a backdrop for the readouts, not an overlay on them.
	_build_danger_veil()
	_build_headline()
	_build_gauge()
	_build_message()

	if not GameConfig.is_headless():
		get_viewport().size_changed.connect(_relayout)
	_relayout()


## Card face for a HUD panel. Uses the game's shared baked card texture, so a
## HUD card costs no bake and is the same material as every menu card; only the
## padding is tightened for the smaller surface.
func _card_style(pad_h: float, pad_v: float) -> StyleBoxTexture:
	var style := UITheme.make_card_style()
	style.content_margin_left = pad_h
	style.content_margin_right = pad_h
	style.content_margin_top = pad_v
	style.content_margin_bottom = pad_v
	return style


## Rounded glass pill for the secondary row, matching the main menu's status
## chip: quiet fill, thin tinted rim, pill radius.
func _pill_style(accent: Color, fill: Color = Color(UITheme.COLOR_BG_DEEP, 0.80)) -> StyleBoxFlat:
	var style := UITheme.make_panel_style(fill, Color(accent, 0.42))
	style.set_corner_radius_all(UITheme.RADIUS_PILL)
	style.content_margin_left = 12.0 * _hud_scale
	style.content_margin_right = 12.0 * _hud_scale
	style.content_margin_top = 4.0 * _hud_scale
	style.content_margin_bottom = 4.0 * _hud_scale
	style.shadow_size = 6
	return style


## Value type: big, emboldened, with a deep-navy outline so it survives being
## drawn over bright snow. Everything read at a glance is set in this.
##
## Written here rather than taken from UITheme's ramp because the make_* helpers
## apply the menu touch step, which would double-scale over the already-shrunk
## touch canvas — the racing HUD keeps its own pair for exactly this reason.
func _value_label(text: String, size: float, color: Color = UITheme.COLOR_TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", UITheme.display_font())
	label.add_theme_font_size_override("font_size", maxi(int(size), 1))
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", maxi(int(size * 0.16), 4))
	label.add_theme_color_override("font_outline_color", UITheme.COLOR_BG_DEEP)
	return label


## Caption type: small, uppercase, tracked, dim. Names a value without ever
## competing with it.
func _caption_label(text: String, size: float, color: Color = UITheme.COLOR_TEXT_DIM) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", UITheme.caption_font())
	label.add_theme_font_size_override("font_size", maxi(int(size), 1))
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color(UITheme.COLOR_BG_DEEP, 0.9))
	return label


## Headline block (top centre): one card holding distance and score, with the
## fish / multiplier / lives row directly beneath it. One column, so the whole
## top of the screen is a single stack that cannot collide with itself however
## narrow the viewport gets.
func _build_headline() -> void:
	var s := _hud_scale
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER_TOP)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.offset_top = GUTTER * s
	column.add_theme_constant_override("separation", int(GAP_S * s))
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(column)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", _card_style(18.0 * s, 7.0 * s))
	column.add_child(card)

	# A bare BoxContainer, not an HBoxContainer: the H/V subclasses have their
	# orientation locked, and _relayout flips this one on narrow viewports.
	_top_box = BoxContainer.new()
	_top_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_top_box.add_theme_constant_override("separation", int(GAP_M * s))
	_top_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(_top_box)

	_distance_label = _stat_pair(_top_box, "Distance", 42.0 * s, "0 m", 150.0 * s)
	_top_divider = ColorRect.new()
	_top_divider.color = Color(UITheme.COLOR_ACCENT, 0.20)
	_top_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_box.add_child(_top_divider)
	_score_label = _stat_pair(_top_box, "Score", 42.0 * s, "0", 150.0 * s,
		UITheme.COLOR_GOLD)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(GAP_S * s * 1.6))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
	_build_lives_pill(row)
	_build_fish_pill(row)
	_build_multiplier_chip(row)


## Value over caption, the atom the headline card is built from. The value gets
## a floor width so the card does not twitch as digits are gained.
func _stat_pair(parent: Control, caption: String, value_size: float,
		value_text: String, min_width: float, color: Color = UITheme.COLOR_TEXT) -> Label:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(stack)
	var value := _value_label(value_text, value_size, color)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.custom_minimum_size = Vector2(min_width, 0.0)
	stack.add_child(value)
	var cap := _caption_label(caption, 13.0 * _hud_scale)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(cap)
	return value


## Hits-left indicator: one chunky pip per RunnerConfig.MAX_HITS, lit while the
## hit is still available. Reads as "how many more mistakes do I get" at a
## glance, which a bare number does not.
func _build_lives_pill(parent: Control) -> void:
	var s := _hud_scale
	_lives_pill = PanelContainer.new()
	_lives_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lives_pill.add_theme_stylebox_override("panel", _pill_style(UITheme.COLOR_ACCENT))
	parent.add_child(_lives_pill)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(maxf(5.0 * s, 3.0)))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lives_pill.add_child(row)
	var tag := _caption_label("Lives", 12.0 * s)
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(tag)

	var pip := 14.0 * s
	_pip_alive = StyleBoxFlat.new()
	_pip_alive.bg_color = Color(0.96, 0.98, 1.0)
	_pip_alive.set_corner_radius_all(int(pip * 0.34))
	_pip_alive.set_border_width_all(1)
	_pip_alive.border_color = Color(UITheme.COLOR_ACCENT, 0.95)
	_pip_alive.anti_aliasing = true
	_pip_spent = StyleBoxFlat.new()
	_pip_spent.bg_color = Color(UITheme.COLOR_BG_DEEP, 0.75)
	_pip_spent.set_corner_radius_all(int(pip * 0.34))
	_pip_spent.set_border_width_all(1)
	_pip_spent.border_color = Color(COLOR_DANGER, 0.55)
	_pip_spent.anti_aliasing = true
	for i: int in RunnerConfig.MAX_HITS:
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(pip, pip)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.add_theme_stylebox_override("panel", _pip_alive)
		row.add_child(dot)
		_life_pips.append(dot)


## Fish counter. Same drawn glyph as the racing HUD and the menu currency chip,
## so a fish means one thing everywhere in the game.
func _build_fish_pill(parent: Control) -> void:
	var s := _hud_scale
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_theme_stylebox_override("panel", _pill_style(UITheme.COLOR_ACCENT))
	parent.add_child(pill)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(maxf(7.0 * s, 4.0)))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(row)
	var texture := UITheme.make_icon(RaceHUD.FISH_ICON_SVG, 2.0)
	if texture != null:
		var icon := TextureRect.new()
		icon.texture = texture
		icon.custom_minimum_size = Vector2(28.0 * s, 19.0 * s)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
	else:
		# SVG module unavailable: an ASCII stand-in still reads, where a Unicode
		# fish would be a .notdef box in the bundled font.
		var glyph := _value_label("><>", 18.0 * s, UITheme.COLOR_ACCENT)
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(glyph)
	_fish_label = _value_label("0", 22.0 * s)
	_fish_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_fish_label)


## Score multiplier. Stays quiet at x1 and turns gold the moment clean running
## has actually earned something, so the chip is its own reward signal.
func _build_multiplier_chip(parent: Control) -> void:
	var s := _hud_scale
	_chip_quiet = _pill_style(UITheme.COLOR_ACCENT)
	_chip_hot = _pill_style(UITheme.COLOR_GOLD, Color(0.24, 0.17, 0.04, 0.85))
	_multiplier_chip = PanelContainer.new()
	_multiplier_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_multiplier_chip.add_theme_stylebox_override("panel", _chip_quiet)
	parent.add_child(_multiplier_chip)
	_multiplier_label = _value_label("x1", 22.0 * s, UITheme.COLOR_TEXT_DIM)
	_multiplier_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_multiplier_label.custom_minimum_size = Vector2(34.0 * s, 0.0)
	_multiplier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_multiplier_chip.add_child(_multiplier_label)


## Avalanche gauge (bottom centre): the cushion of track between the player and
## the wall, draining as it closes. A draining bar plus a falling metre count
## says "you are losing ground" without needing to be read.
func _build_gauge() -> void:
	var s := _hud_scale
	var bar_h := GAUGE_HEIGHT * s
	_gauge_holder = VBoxContainer.new()
	_gauge_holder.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_gauge_holder.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_gauge_holder.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_gauge_holder.offset_bottom = -GUTTER * s
	_gauge_holder.add_theme_constant_override("separation", int(maxf(3.0 * s, 2.0)))
	_gauge_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_gauge_holder)

	var caption := HBoxContainer.new()
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge_holder.add_child(caption)
	_gauge_tag = _caption_label("Avalanche", 13.0 * s)
	_gauge_tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.add_child(_gauge_tag)
	_gauge_value = _caption_label("0 m", 13.0 * s, UITheme.COLOR_TEXT)
	_gauge_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caption.add_child(_gauge_value)

	# Recessed channel: darker than the scene with a thin rim, so the fill reads
	# as sitting inside the screen rather than pasted onto it.
	var groove := Panel.new()
	groove.custom_minimum_size = Vector2(0.0, bar_h)
	groove.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var groove_style := StyleBoxFlat.new()
	groove_style.bg_color = Color(UITheme.COLOR_BG_DEEP, 0.80)
	groove_style.set_corner_radius_all(int(bar_h * 0.5))
	groove_style.set_border_width_all(1)
	groove_style.border_color = Color(UITheme.COLOR_ACCENT, 0.24)
	groove_style.anti_aliasing = true
	groove.add_theme_stylebox_override("panel", groove_style)
	_gauge_holder.add_child(groove)

	var inset := maxf(3.0 * s, 2.0)
	_gauge_bar = ProgressBar.new()
	_gauge_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gauge_bar.offset_left = inset
	_gauge_bar.offset_top = inset
	_gauge_bar.offset_right = -inset
	_gauge_bar.offset_bottom = -inset
	_gauge_bar.max_value = 1.0
	_gauge_bar.value = 1.0
	_gauge_bar.show_percentage = false
	_gauge_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge_bar.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	# One neutral fill, tinted through modulate. Re-baking a gradient stylebox as
	# the danger ramps would be a texture upload per frame; a Color write is free.
	_gauge_bar.add_theme_stylebox_override("fill",
		UITheme.make_bar_fill(Color(0.86, 0.94, 1.0), Color(1.0, 1.0, 1.0)))
	_gauge_bar.modulate = UITheme.COLOR_ACCENT
	groove.add_child(_gauge_bar)


## Screen-edge red wash that deepens as the wall closes the last few metres.
## Continuous rather than blinking, so it needs no reduced-flashing exemption.
func _build_danger_veil() -> void:
	if GameConfig.is_headless():
		return
	_danger_veil = TextureRect.new()
	_danger_veil.texture = _veil_tex()
	_danger_veil.stretch_mode = TextureRect.STRETCH_SCALE
	_danger_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_danger_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_danger_veil.modulate.a = 0.0
	_root.add_child(_danger_veil)


static func _veil_tex() -> GradientTexture2D:
	if _veil_texture != null:
		return _veil_texture
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(COLOR_DANGER.r, COLOR_DANGER.g, COLOR_DANGER.b, 0.0),
		Color(COLOR_DANGER.r, COLOR_DANGER.g, COLOR_DANGER.b, 0.10),
		Color(0.72, 0.10, 0.08, 0.95),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.48, 1.0])
	_veil_texture = GradientTexture2D.new()
	_veil_texture.gradient = grad
	_veil_texture.fill = GradientTexture2D.FILL_RADIAL
	_veil_texture.fill_from = Vector2(0.5, 0.5)
	_veil_texture.fill_to = Vector2(0.5, -0.12)
	_veil_texture.width = 128
	_veil_texture.height = 128
	return _veil_texture


## Centred callout ("Slide!", "x3"). Spans most of the width and wraps, so a
## long line is legible on a portrait phone instead of running off both edges.
func _build_message() -> void:
	_message_label = _value_label("", 54.0 * _hud_scale, UITheme.COLOR_GOLD)
	_message_label.anchor_left = 0.05
	_message_label.anchor_right = 0.95
	_message_label.anchor_top = 0.30
	_message_label.anchor_bottom = 0.30
	_message_label.offset_left = 0.0
	_message_label.offset_right = 0.0
	_message_label.offset_top = 0.0
	_message_label.offset_bottom = 0.0
	_message_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.add_theme_constant_override("outline_size", int(10.0 * _hud_scale))
	_root.add_child(_message_label)


## --- Orientation ------------------------------------------------------------

## Re-fits the two layouts that cannot survive a portrait viewport unchanged:
## the headline card's two stats and the end-of-run button pair both become
## columns, and the gauge is clamped inside the usable width. Cheap enough to
## run on every resize — no node is rebuilt.
func _relayout() -> void:
	var width := _view_width()
	var narrow := width < NARROW_WIDTH
	if _top_box != null:
		_top_box.vertical = narrow
		if narrow:
			_top_divider.custom_minimum_size = Vector2(0.0, 1.0)
			_top_divider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_top_divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		else:
			_top_divider.custom_minimum_size = Vector2(1.0, 0.0)
			_top_divider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			_top_divider.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if _gauge_holder != null:
		# Safe-area inset as well as the gutter: on a notched phone in landscape
		# the rounded corner eats further into the row than the margin allows for.
		var margin := GUTTER * _hud_scale + UITheme.safe_inset_x(_root)
		_gauge_holder.custom_minimum_size.x = clampf(GAUGE_WIDTH * _hud_scale,
			120.0, maxf(width - margin * 2.0, 120.0))
	if _game_over_buttons != null:
		_game_over_buttons.vertical = narrow


func _view_width() -> float:
	var viewport := get_viewport()
	if viewport == null:
		return 1920.0
	var width := viewport.get_visible_rect().size.x
	return width if width > 0.0 else 1920.0


## --- Per-frame readout ------------------------------------------------------

## Called every frame by the runner. Each readout compares against the value it
## is already displaying and returns early, so the common frame does no string
## work at all.
func set_stats(distance_m: float, fish: int, score: int, multiplier: int,
		hits_left: int, chaser_gap: float) -> void:
	if _root == null:
		return

	var metres := maxi(int(distance_m), 0)
	if metres != _shown_distance:
		_shown_distance = metres
		_distance_label.text = "%d m" % metres

	if score != _shown_score:
		_shown_score = score
		_score_label.text = group_digits(score)

	if fish != _shown_fish:
		var gained := fish > _shown_fish and _shown_fish >= 0
		_shown_fish = fish
		_fish_label.text = str(fish)
		if gained:
			_punch(_fish_label, 1.3)

	if multiplier != _shown_multiplier:
		var climbed := multiplier > _shown_multiplier and _shown_multiplier > 0
		_shown_multiplier = multiplier
		_multiplier_label.text = "x%d" % multiplier
		var hot := multiplier > 1
		_multiplier_chip.add_theme_stylebox_override("panel", _chip_hot if hot else _chip_quiet)
		_multiplier_label.add_theme_color_override("font_color",
			UITheme.COLOR_GOLD if hot else UITheme.COLOR_TEXT_DIM)
		if climbed:
			_punch(_multiplier_chip, 1.32)

	if hits_left != _shown_hits:
		var lost := _shown_hits >= 0 and hits_left < _shown_hits
		_shown_hits = hits_left
		for i: int in _life_pips.size():
			_life_pips[i].add_theme_stylebox_override("panel",
				_pip_alive if i < hits_left else _pip_spent)
		if lost:
			_punch(_lives_pill, 1.2)

	_gauge_bar.value = clampf(chaser_gap / RunnerConfig.CHASER_BASE_GAP, 0.0, 1.0)
	var gap_m := maxi(int(chaser_gap), 0)
	if gap_m != _shown_gap:
		_shown_gap = gap_m
		_gauge_value.text = "%d m" % gap_m
		# Colour is re-derived on the metre tick rather than every frame: a
		# theme override is a dictionary write, the gauge value is not.
		var heat := clampf((WARN_GAP - chaser_gap) / maxf(WARN_GAP - DANGER_GAP, 0.001), 0.0, 1.0)
		var tint := UITheme.COLOR_ACCENT.lerp(COLOR_DANGER, heat)
		_gauge_bar.modulate = tint
		_gauge_value.add_theme_color_override("font_color",
			tint if heat > 0.0 else UITheme.COLOR_TEXT)

	var danger := chaser_gap < DANGER_GAP
	if danger != _in_danger:
		_in_danger = danger
		_set_danger(danger)
	if _danger_veil != null:
		_danger_veil.modulate.a = clampf(
			(DANGER_GAP - chaser_gap) / DANGER_GAP, 0.0, 1.0) * VEIL_ALPHA


## Enters/leaves the committed danger read. The veil is driven continuously by
## the gap; this only owns the pulsing tag, which is a flourish and therefore
## goes through the reduced-motion gate.
func _set_danger(danger: bool) -> void:
	if _danger_tween != null and _danger_tween.is_valid():
		_danger_tween.kill()
	_danger_tween = null
	if _gauge_tag == null:
		return
	_gauge_tag.add_theme_color_override("font_color",
		COLOR_DANGER if danger else UITheme.COLOR_TEXT_DIM)
	_gauge_tag.text = "AVALANCHE!" if danger else "AVALANCHE"
	_gauge_tag.modulate.a = 1.0
	if not danger or GameConfig.is_headless() or UITheme.reduced_motion():
		return
	_danger_tween = create_tween().set_loops()
	_danger_tween.tween_property(_gauge_tag, "modulate:a", 0.35, 0.32) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_danger_tween.tween_property(_gauge_tag, "modulate:a", 1.0, 0.32) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Scale pop on a readout that just changed. Event-driven only, and skipped
## outright when the player has asked for less motion.
func _punch(control: Control, amount: float) -> void:
	if control == null or GameConfig.is_headless() or UITheme.reduced_motion():
		return
	if control.has_meta("_punch_tween"):
		var previous: Variant = control.get_meta("_punch_tween")
		if previous is Tween and (previous as Tween).is_valid():
			(previous as Tween).kill()
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2.ONE * amount
	var tween := control.create_tween()
	tween.tween_property(control, "scale", Vector2.ONE, 0.20) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	control.set_meta("_punch_tween", tween)


## 12345 -> "12,345". Scores pass six digits inside a good run, and an
## ungrouped six-digit number is read as a length rather than a value.
static func group_digits(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	var count := 0
	for i: int in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" + out) if value < 0 else out


## --- Callout ----------------------------------------------------------------

## Brief centred callout ("Slide!", "x3"). Replaces whatever is on screen.
func show_message(text: String) -> void:
	if _message_label == null:
		return
	if _message_tween != null and _message_tween.is_valid():
		_message_tween.kill()
	_message_tween = null
	_message_label.text = text
	_message_label.modulate = Color(UITheme.COLOR_GOLD, 1.0)
	_message_label.scale = Vector2.ONE
	if GameConfig.is_headless():
		return
	_message_tween = create_tween()
	if not UITheme.reduced_motion():
		_message_label.pivot_offset = _message_label.size * 0.5
		_message_label.scale = Vector2.ONE * 1.35
		_message_tween.tween_property(_message_label, "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_message_tween.tween_interval(0.75)
	_message_tween.tween_property(_message_label, "modulate:a", 0.0, 0.35)
	_message_tween.tween_callback(func() -> void:
		_message_label.text = ""
		_message_label.modulate.a = 1.0)


## --- End of run -------------------------------------------------------------

## Full-screen end-of-run panel. `summary` carries `distance` (float metres),
## `fish` (int), `score` (int), `best` (int, the standing best BEFORE this run)
## and `is_new_best` (bool).
func show_game_over(summary: Dictionary) -> void:
	hide_game_over()
	var distance := float(summary.get("distance", 0.0))
	var fish := int(summary.get("fish", 0))
	var score := int(summary.get("score", 0))
	var best := int(summary.get("best", 0))
	var record := bool(summary.get("is_new_best", false))
	var tint := UITheme.COLOR_GOLD if record else Color(0.95, 0.97, 1.0)

	_game_over = Control.new()
	_game_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Swallows taps so a stray swipe cannot reach the run underneath, and keeps
	# running whether or not the runner pauses the tree on death.
	_game_over.mouse_filter = Control.MOUSE_FILTER_STOP
	_game_over.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_game_over)

	var dim := ColorRect.new()
	dim.color = Color(UITheme.COLOR_BG_DEEP, 0.80)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game_over.add_child(dim)
	if record:
		_game_over.add_child(_celebration_glow())

	# Scroll wrapper: a short landscape phone cannot fit the card, and the two
	# buttons must stay reachable rather than being pushed off the bottom.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_game_over.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)

	var card := UITheme.make_card(center)
	card.custom_minimum_size.x = UITheme.content_width(560.0, _root)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UITheme.spacing(UITheme.SPACE_S))
	card.add_child(column)

	var eyebrow := UITheme.make_eyebrow("Waddle Run")
	column.add_child(eyebrow)
	var headline := UITheme.heading("New Best!" if record else "Run Over",
		UITheme.scaled_heading(54))
	headline.add_theme_color_override("font_color", tint)
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(headline)
	if record:
		_add_badge(column, "New Personal Best")

	column.add_child(UITheme.make_divider())
	var score_value := _add_stat_grid(column, distance, fish, score, best, record, tint)
	column.add_child(UITheme.make_spacer(UITheme.SPACE_S))

	# Two equally offered choices, side by side on a wide screen and stacked on
	# a narrow one (_relayout owns the flip, hence the bare BoxContainer).
	_game_over_buttons = BoxContainer.new()
	_game_over_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_game_over_buttons.add_theme_constant_override("separation", UITheme.spacing(UITheme.SPACE_S))
	column.add_child(_game_over_buttons)
	var button_size := UITheme.scaled_size(Vector2(240.0, 60.0))
	var again := UITheme.make_primary_button("Run Again", button_size, UITheme.scaled_font(26))
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.hook_sounds(again)
	again.pressed.connect(func() -> void: restart_pressed.emit())
	_game_over_buttons.add_child(again)
	var to_menu := UITheme.make_button("Main Menu", button_size, UITheme.scaled_font(24))
	to_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.hook_sounds(to_menu)
	to_menu.pressed.connect(func() -> void: menu_pressed.emit())
	_game_over_buttons.add_child(to_menu)
	_relayout()

	if GameConfig.is_headless():
		return
	again.grab_focus()
	AudioManager.play_sfx("sfx_victory" if record else "sfx_finish")
	_play_panel_entrance(card, score_value, score, record)


## Distance / Fish / Score, plus the standing best. On a record the best cell
## becomes the score the player just beat; otherwise it shows the gap still to
## close, which is the reason to press Run Again.
func _add_stat_grid(parent: Control, distance: float, fish: int, score: int,
		best: int, record: bool, tint: Color) -> Label:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", UITheme.spacing(UITheme.SPACE_M))
	parent.add_child(row)
	row.add_child(UITheme.make_stat("%dm" % int(distance), "Distance"))
	row.add_child(UITheme.make_stat(str(fish), "Fish"))
	var score_stat := UITheme.make_stat(group_digits(score), "Score", tint)
	row.add_child(score_stat)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", UITheme.spacing(UITheme.SPACE_S))
	parent.add_child(footer)
	if record:
		footer.add_child(UITheme.make_caption("Previous best %s" % group_digits(best)))
	elif best > 0:
		footer.add_child(UITheme.make_caption("Best %s" % group_digits(best)))
		if best > score:
			footer.add_child(UITheme.make_caption(
				"%s to beat it" % group_digits(best - score),
				UITheme.FS_CAPTION, Color(UITheme.COLOR_GOLD, 0.85)))
	return score_stat.get_child(0) as Label


## Gold pill for the record callout, matching the results screen's badge.
func _add_badge(parent: Control, text: String) -> void:
	var holder := CenterContainer.new()
	parent.add_child(holder)
	var badge := PanelContainer.new()
	var style := UITheme.make_panel_style(
		Color(UITheme.COLOR_GOLD, 0.16), Color(UITheme.COLOR_GOLD, 0.75))
	style.set_corner_radius_all(UITheme.RADIUS_PILL)
	style.content_margin_left = UITheme.scaled(22.0)
	style.content_margin_right = UITheme.scaled(22.0)
	style.content_margin_top = UITheme.scaled(6.0)
	style.content_margin_bottom = UITheme.scaled(6.0)
	badge.add_theme_stylebox_override("panel", style)
	holder.add_child(badge)
	badge.add_child(UITheme.make_caption(text, UITheme.FS_EYEBROW, UITheme.COLOR_GOLD))
	# Looping ambient flourish, so it goes through the reduced-motion gate the
	# way every other continuous animation in the game does.
	if GameConfig.is_headless() or UITheme.reduced_motion():
		return
	var tween := badge.create_tween().set_loops()
	tween.tween_property(badge, "modulate:a", 0.70, 0.9) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(badge, "modulate:a", 1.0, 0.9) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Warm gold wash behind the record panel, so a new best changes the colour of
## the whole screen rather than adding one more line of text to it.
func _celebration_glow() -> TextureRect:
	var core := Color(0.96, 0.78, 0.28, 0.26)
	var grad := Gradient.new()
	grad.colors = PackedColorArray([core, Color(core.r, core.g, core.b, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = grad
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.42)
	texture.fill_to = Vector2(0.5, 1.0)
	var glow := TextureRect.new()
	glow.texture = texture
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return glow


## Panel entrance: the card rises and fades in, and the score counts up to its
## final value — a record then gets a longer, louder count so the number itself
## is the celebration. Reduced motion keeps the fade and drops the rest.
func _play_panel_entrance(card: Control, score_value: Label, score: int, record: bool) -> void:
	_game_over.modulate.a = 0.0
	var fade := _game_over.create_tween()
	fade.tween_property(_game_over, "modulate:a", 1.0, 0.22)
	if UITheme.reduced_motion():
		return
	# Pivot tracks the card's real size: containers have not sorted yet on the
	# frame the panel is built, so a pivot captured now would be (0, 0).
	card.pivot_offset = card.size * 0.5
	card.resized.connect(func() -> void:
		card.pivot_offset = card.size * 0.5)
	card.scale = Vector2(0.94, 0.94)
	var pop := card.create_tween()
	pop.tween_property(card, "scale", Vector2.ONE, 0.32) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if score <= 0 or score_value == null:
		return
	score_value.text = "0"
	var count := score_value.create_tween()
	count.tween_method(_set_counted_score.bind(score_value),
			0.0, float(score), 1.1 if record else 0.7) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Count-up target for the end-of-run score tween.
func _set_counted_score(value: float, label: Label) -> void:
	if is_instance_valid(label):
		label.text = group_digits(int(value))


func hide_game_over() -> void:
	_game_over_buttons = null
	if _game_over != null and is_instance_valid(_game_over):
		_game_over.queue_free()
	_game_over = null
