class_name RaceHUD
extends CanvasLayer
## In-race HUD: position, progress, item, fish, speed, countdown, time,
## messages, and an early "Finish Race" button once the player is done while
## AI are still on course. Scales with the accessibility HUD-scale setting.
##
## Visual system — deliberately small, so the overlay reads as one design
## instead of a pile of separate widgets:
##   * One card. Every panel (position, clock, item, fish, control strip) uses
##     the same baked 9-patch: rounded navy body with a vertical gradient, an
##     ice rim that is brightest along the top edge, and a soft drop shadow.
##     Same radius, same edge weight, same shadow everywhere.
##   * One rhythm. GUTTER from every screen edge, GAP_S inside a group, GAP_M
##     between groups, and a single bottom baseline shared by the fish card and
##     both gauges. The item card matches the minimap card's width so the whole
##     right-hand column is one stack.
##   * One type scale. UITheme.display_font for values (place, clock, fish,
##     speed), the same font small/dim/uppercase for captions — a glance lands
##     on the numbers, the captions only answer "what is this?" on purpose.
##   * One palette: UITheme's. The HUD no longer carries its own colours.

## --- Layout rhythm ----------------------------------------------------------
const GUTTER: float = 24.0          ## Screen-edge margin (UITheme.SPACE_M).
const GAP_S: int = 6                ## Inside a group.
const GAP_M: int = 12               ## Between groups.
const CARD_RADIUS: float = 14.0     ## Matches UITheme.make_panel_style.
const BAR_HEIGHT: float = 20.0      ## Gauge capsule height at hud_scale 1.
## Right-hand column width: RaceMinimap.BASE_SIZE, so the item slot and the map
## below it share one edge. Capped on touch devices, where the pause button is
## parked immediately left of this column.
const COLUMN_WIDTH: float = 150.0
const COLUMN_WIDTH_TOUCH_MAX: float = 158.0
## Item card height, reserved up front (including the desktop "use" hint row)
## so picking an item up never reflows the card. Stays clear of the minimap,
## which drops in at RaceMinimap.TOP_CLEARANCE (156) * hud_scale.
const ITEM_CARD_HEIGHT: float = 133.0
const ITEM_CARD_HEIGHT_TOUCH: float = 110.0

## Baked card texture geometry: the shadow bleeds SHADOW_PAD outside the card
## rect (drawn through expand margins) and the 9-patch corners hold the rim and
## the ends of the body gradient.
const CARD_TEX_SIZE: int = 96
const CARD_TEX_PAD: float = 14.0

## Placeholder drawn in the item slot while the player carries nothing: a
## dashed slot outline reads as "empty on purpose" where the old flat square
## read as a missing icon.
const EMPTY_SLOT_SVG := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<rect x="9" y="9" width="46" height="46" rx="13" fill="none" stroke="#ffffff" stroke-width="3.4" stroke-dasharray="10 8" stroke-linecap="round"/>
</svg>"""

const FISH_ICON_SVG := """<svg xmlns="http://www.w3.org/2000/svg" width="60" height="40" viewBox="0 0 60 40">
<path d="M3 20 L19 8 L19 32 Z" fill="#6fc0ee"/>
<ellipse cx="34" cy="21" rx="21" ry="12" fill="#8fd8f8"/>
<path d="M26 11 Q35 3 44 11 Q35 15 26 11 Z" fill="#5fb0e2"/>
<path d="M20 21 Q34 31 50 22 Q34 27 20 21 Z" fill="#5fb0e2" opacity="0.7"/>
<circle cx="45" cy="17" r="3.2" fill="#0e2036"/>
<circle cx="46.2" cy="15.8" r="1.1" fill="#ffffff"/>
</svg>"""

## Drawn item-slot glyphs, one per PowerupsDB "icon" key. The slot used to be
## a flat colour swatch, which read as unfinished next to the rest of the HUD.
const ITEM_ICONS: Dictionary = {
	"snowball": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<circle cx="32" cy="34" r="22" fill="#eef6ff" stroke="#9dbdd8" stroke-width="2.5"/>
<circle cx="24" cy="26" r="6" fill="#ffffff" opacity="0.9"/>
<circle cx="41" cy="42" r="4" fill="#cfe2f2"/>
<circle cx="43" cy="27" r="3" fill="#dfeeff"/>
<circle cx="27" cy="44" r="3" fill="#cfe2f2"/>
</svg>""",
	"shield": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M32 6 L54 15 V33 C54 46 44 55 32 59 C20 55 10 46 10 33 V15 Z" fill="#6fd0f7" stroke="#2f7fa8" stroke-width="3" stroke-linejoin="round"/>
<path d="M32 12 L48 19 V33 C48 42 41 49 32 52 Z" fill="#a6e6ff" opacity="0.65"/>
<path d="M22 32 L29 40 L44 24" stroke="#ffffff" stroke-width="5" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
</svg>""",
	"bolt": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M36 4 L14 36 H28 L24 60 L50 26 H34 Z" fill="#ffc93f" stroke="#c98f1b" stroke-width="3" stroke-linejoin="round"/>
<path d="M33 12 L22 32 H31" stroke="#fff3c4" stroke-width="3.5" fill="none" stroke-linecap="round"/>
</svg>""",
	"magnet": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M14 46 V30 C14 20 22 12 32 12 C42 12 50 20 50 30 V46" fill="none" stroke="#e05a8c" stroke-width="12" stroke-linecap="butt"/>
<rect x="8" y="44" width="12" height="12" fill="#d7e6f5"/>
<rect x="44" y="44" width="12" height="12" fill="#d7e6f5"/>
<path d="M20 30 C20 23 25 18 32 18 C39 18 44 23 44 30" fill="none" stroke="#f5a0c0" stroke-width="3" opacity="0.7"/>
</svg>""",
	"cloud": """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M18 40 C11 40 7 35 7 30 C7 24 12 20 18 21 C20 13 27 9 34 11 C41 12 46 18 46 25 C53 25 57 30 57 35 C57 39 54 43 49 43 Z" fill="#dfeaf7" stroke="#8fa8c4" stroke-width="2.5" stroke-linejoin="round"/>
<path d="M20 50 L18 58 M32 50 L30 60 M44 50 L42 57" stroke="#a8c8e8" stroke-width="4" stroke-linecap="round"/>
</svg>""",
}

## Shared card art (see _card_texture). Built once per run, reused by every
## card style — the styles differ only in their content margins.
static var _card_tex: ImageTexture = null

var manager: RaceManager = null
var player: Racer = null

var _position_card: PanelContainer = null
var _position_label: Label = null
var _position_suffix: Label = null
var _position_total: Label = null
var _position_stripe: Panel = null
var _time_label: Label
var _time_caption: Label
var _fish_label: Label
var _item_panel: Panel
var _item_glow: Panel
var _item_glow_style: StyleBoxFlat
var _item_label: Label
var _item_icon: TextureRect
var _item_icon_size: float = 44.0
var _item_pulse: Tween = null
var _ammo_pips: Array[Panel] = []
var _ammo_style_full: StyleBoxFlat
var _ammo_style_empty: StyleBoxFlat
var _groove_cache: StyleBoxTexture = null
var _use_hint: HBoxContainer = null
var _use_key_label: Label = null
var _use_verb_label: Label = null
var _held_item: bool = false
var _ammo_count: int = 0
var _speed_bar: ProgressBar
var _speed_flag: Label
var _speed_flagged: bool = false
var _progress_bar: ProgressBar
var _progress_value: Label
var _progress_shown: int = -1
var _center_label: Label
var _checkpoint_label: Label
var _controls_hint: PanelContainer = null
var _bar_tags: Array[Label] = []
var _esc_hint: Control = null
var _finish_button: Button = null
var _race_over: bool = false
var _hud_scale: float = 1.0
var _hint_bottom: float = -92.0
var _root: Control


func setup(p_manager: RaceManager, p_player: Racer) -> void:
	manager = p_manager
	player = p_player
	_build()
	manager.countdown_tick.connect(_on_countdown)
	manager.race_started.connect(_fade_controls_hint)
	manager.positions_updated.connect(_on_positions)
	manager.message.connect(show_message)
	manager.race_completed.connect(_on_race_completed)
	# Early-finish offer: only meaningful when AI rivals keep racing after the
	# player is done (never Time Trial or Endless; pointless in headless sims).
	if not manager.single_racer_mode and not (manager is EndlessManager) \
			and not GameConfig.is_headless():
		manager.player_finished.connect(_on_player_finished)
	player.fish_collected.connect(_on_fish)
	player.item_received.connect(_on_item_received)
	player.item_used.connect(_on_item_used)
	player.snowball_ammo_changed.connect(_on_snowball_ammo)
	player.checkpoint_reached.connect(_on_checkpoint)
	# Accessibility: visual captions for important audio events.
	player.stunned_changed.connect(func(_racer: Racer, is_stunned: bool) -> void:
		if is_stunned:
			_audio_cue("Bonk!"))
	player.shove_landed.connect(func(_attacker: Racer, _victim: Racer) -> void:
		_audio_cue("Shove landed!"))
	player.respawned.connect(func(_racer: Racer) -> void:
		_audio_cue("Back on track"))


func _audio_cue(text: String) -> void:
	if not bool(SettingsManager.get_setting("accessibility", "audio_visual_cues")):
		return
	_checkpoint_label.text = text
	_checkpoint_label.modulate = Color(UITheme.COLOR_GOLD, 1.0)
	var tween := create_tween()
	tween.tween_interval(0.9)
	tween.tween_property(_checkpoint_label, "modulate:a", 0.0, 0.4)


## --- Shared visual language -------------------------------------------------

## The one HUD card, baked once as a 9-patch: rounded navy body with a vertical
## gradient (lighter crest, deeper foot), an ice rim strongest along the top
## edge and fading down the sides, and a soft drop shadow that bleeds outside
## the card rect. StyleBoxFlat can only manage a flat fill plus one border
## colour, which is exactly why the old panels read as pasted-on rectangles.
static func _card_texture() -> ImageTexture:
	if _card_tex != null:
		return _card_tex
	var n := CARD_TEX_SIZE
	var pad := CARD_TEX_PAD
	var radius := CARD_RADIUS
	var half := Vector2(n, n) * 0.5
	var extent := half - Vector2(pad, pad) - Vector2(radius, radius)
	var body_top := UITheme.COLOR_BG.lerp(UITheme.COLOR_ACCENT, 0.10)
	var body_bottom := UITheme.COLOR_BG_DEEP
	var rim := UITheme.COLOR_ACCENT
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y: int in n:
		# Gradient runs across the card body only; the 9-patch stretches its
		# middle band, so the crest and foot keep their authored thickness.
		var t := clampf((float(y) + 0.5 - pad) / (float(n) - 2.0 * pad), 0.0, 1.0)
		var body := body_top.lerp(body_bottom, t)
		var rim_strength := lerpf(0.60, 0.16, t)
		for x: int in n:
			var p := Vector2(float(x) + 0.5, float(y) + 0.5) - half
			var d := _round_box_sdf(p, extent, radius)
			var cover := clampf(0.5 - d, 0.0, 1.0)
			# Rim sits just inside the edge so the card keeps a crisp outline.
			var edge := clampf(1.0 - absf(d + 1.0) / 1.3, 0.0, 1.0)
			var color := body.lerp(rim, edge * rim_strength)
			var alpha := (0.86 + edge * rim_strength * 0.12) * cover
			# Drop shadow, offset down, blurred by distance outside the card.
			var ds := _round_box_sdf(p - Vector2(0.0, 3.0), extent, radius)
			var shade := clampf(1.0 - ds / 11.0, 0.0, 1.0)
			var shadow_a := shade * shade * 0.40
			var out_a := alpha + shadow_a * (1.0 - alpha)
			if out_a > 0.0001:
				var rgb := (Vector3(color.r, color.g, color.b) * alpha) / out_a
				img.set_pixel(x, y, Color(rgb.x, rgb.y, rgb.z, out_a))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	_card_tex = ImageTexture.create_from_image(img)
	return _card_tex


## Signed distance to a rounded box centred on the origin (negative inside).
static func _round_box_sdf(p: Vector2, extent: Vector2, radius: float) -> float:
	var q := Vector2(absf(p.x), absf(p.y)) - extent
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius


## Card style for a panel, differing from every other card only in padding.
func _card_style(pad_h: float, pad_v: float) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = _card_texture()
	style.set_texture_margin_all(CARD_TEX_PAD + CARD_RADIUS + 2.0)
	style.set_expand_margin_all(CARD_TEX_PAD)
	style.content_margin_left = pad_h
	style.content_margin_right = pad_h
	style.content_margin_top = pad_v
	style.content_margin_bottom = pad_v
	return style


## Value type: big, bright, emboldened, with a deep-navy outline so it survives
## bright snow. Everything the racer reads at a glance is set in this.
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


## Caption type: small, uppercase, letter-spaced, dim. Names a gauge or a card
## without ever competing with the value next to it.
func _caption_label(text: String, size: float, alpha: float = 1.0) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", UITheme.display_font())
	label.add_theme_font_size_override("font_size", maxi(int(size), 1))
	label.add_theme_color_override("font_color", Color(UITheme.COLOR_TEXT_DIM, alpha))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color(UITheme.COLOR_BG_DEEP, 0.9))
	return label


## Baked gauge groove: a capsule channel cut into the screen — denser along
## its top lip (inner shadow), with the ice rim brightest along the *bottom*
## lip, the inverse of the cards. Cards catch the light on top, grooves catch
## it underneath, which is what makes one read as raised and the other as
## recessed. Baked at the live bar height so it never stretches.
func _groove_style(height: float) -> StyleBoxTexture:
	if _groove_cache != null:
		return _groove_cache
	var pad := 6.0
	var h := int(roundf(height)) + int(pad) * 2
	var radius := (float(h) - pad * 2.0) * 0.5
	var w := int(pad + radius + 2.0) * 2 + 4
	var half := Vector2(float(w), float(h)) * 0.5
	var extent := Vector2(half.x - pad - radius, 0.0)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var base := UITheme.COLOR_BG_DEEP
	var rim := UITheme.COLOR_ACCENT
	for y: int in h:
		var t := clampf((float(y) + 0.5 - pad) / maxf(float(h) - pad * 2.0, 1.0), 0.0, 1.0)
		# Inner shadow along the top lip, and the rim highlight underneath.
		var inner := clampf(1.0 - t * 3.2, 0.0, 1.0)
		var rim_strength := lerpf(0.18, 0.72, t)
		for x: int in w:
			var p := Vector2(float(x) + 0.5, float(y) + 0.5) - half
			var d := _round_box_sdf(p, extent, radius)
			var cover := clampf(0.5 - d, 0.0, 1.0)
			var edge := clampf(1.0 - absf(d + 1.0) / 1.3, 0.0, 1.0)
			var color := base.lerp(rim, edge * rim_strength)
			var alpha := (0.60 + inner * 0.22 + edge * rim_strength * 0.30) * cover
			img.set_pixel(x, y, Color(color.r, color.g, color.b, alpha))
	var style := StyleBoxTexture.new()
	style.texture = ImageTexture.create_from_image(img)
	style.texture_margin_left = pad + radius + 2.0
	style.texture_margin_right = pad + radius + 2.0
	style.texture_margin_top = 0.0
	style.texture_margin_bottom = 0.0
	# Vertical 1:1: the drawn box is the bar plus its two pads, which is exactly
	# the baked height, so the capsule ends stay circular at any hud scale.
	style.expand_margin_left = pad
	style.expand_margin_right = pad
	style.expand_margin_top = pad
	style.expand_margin_bottom = pad
	style.set_content_margin_all(0.0)
	_groove_cache = style
	return style


## One gauge: groove panel with the gradient fill inset inside it. Returns the
## groove for the caller to place; its only child is the ProgressBar.
func _make_gauge(height: float, inset: float, fill_from: Color, fill_to: Color) -> Panel:
	var groove := Panel.new()
	groove.mouse_filter = Control.MOUSE_FILTER_IGNORE
	groove.add_theme_stylebox_override("panel", _groove_style(height))
	var bar := ProgressBar.new()
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.offset_left = inset
	bar.offset_top = inset
	bar.offset_right = -inset
	bar.offset_bottom = -inset
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	bar.add_theme_stylebox_override("fill", UITheme.make_bar_fill(fill_from, fill_to))
	groove.add_child(bar)
	return groove


static func _make_fish_texture() -> ImageTexture:
	return UITheme.make_icon(FISH_ICON_SVG, 2.0)


## Small keyboard-keycap chip (light face, heavier bottom border) used for
## desktop input hints. Returns the panel; its Label child holds the text.
##
## `text` of the form "arrow:left" (also right/up/down/both) prints a drawn
## arrow instead of a character. The bundled font has no arrow glyphs at all,
## so a typed one is a .notdef box on the web build -- see UITheme.ARROW_SVG.
static func make_keycap(text: String, font_size: int) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.9, 0.95, 1.0)
	style.set_corner_radius_all(5)
	style.set_border_width_all(1)
	style.border_width_bottom = 3
	style.border_color = Color(0.45, 0.6, 0.78)
	style.content_margin_left = 7.0
	style.content_margin_right = 7.0
	style.content_margin_top = 1.0
	style.content_margin_bottom = 2.0
	cap.add_theme_stylebox_override("panel", style)
	if text.begins_with("arrow:"):
		cap.add_child(UITheme.arrow_icon(
			text.substr(6), float(font_size) * 1.15, UITheme.COLOR_BG_DEEP))
		return cap
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", UITheme.bold_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", UITheme.COLOR_BG_DEEP)
	cap.add_child(label)
	return cap


## Shared control-reference strip: keycap/gesture pairs for the core race
## actions, used by the in-race onboarding chip and the pause menu. Reads the
## live key bindings at build time so remaps always display correctly; touch
## devices get the gesture + button cheat sheet instead. With max_per_row > 0
## the pairs wrap into centered rows (compact layouts like the pause menu).
static func build_controls_strip(hud_scale: float, max_per_row: int = 0) -> Control:
	var hints: Array = []
	if UITheme.is_touch():
		hints = [
			[["arrow:both"], "Drag to steer"],
			[["arrow:up"], "Swipe to jump"],
			[["arrow:down"], "Hold to slide"],
			[["SHOVE"], "Bump rivals"],
			[["ITEM"], "Use pickup"],
			[["BACK"], "Throw behind"],
		]
	else:
		# Steering shows the arrow keys rather than the WASD letters: both are
		# bound, and an arrow states the direction without having to be read.
		hints = [
			[["arrow:left", "arrow:right"], "Steer"],
			[["jump"], "Jump"],
			[["slide"], "Slide"],
			[["shove"], "Shove"],
			[["use_item"], "Item"],
			[["aim_back", "use_item"], "Throw behind"],
		]
	var column: VBoxContainer = null
	if max_per_row > 0:
		column = VBoxContainer.new()
		column.add_theme_constant_override("separation", GAP_S + 2)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row: HBoxContainer = null
	for i: int in hints.size():
		if row == null or (max_per_row > 0 and i % max_per_row == 0):
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 18)
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if column != null:
				column.add_child(row)
		var hint: Array = hints[i]
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 5)
		pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for action: String in hint[0]:
			var cap := action
			if not UITheme.is_touch() and not action.begins_with("arrow:"):
				var key := SettingsManager.describe_action_binding(action, "key")
				cap = key if key != "—" else "?"
			pair.add_child(make_keycap(cap, int(14 * hud_scale)))
		var verb := Label.new()
		verb.text = String(hint[1])
		verb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		verb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		verb.add_theme_font_size_override("font_size", int(15 * hud_scale))
		verb.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
		verb.add_theme_constant_override("outline_size", 4)
		verb.add_theme_color_override("font_outline_color", Color(UITheme.COLOR_BG_DEEP, 0.9))
		pair.add_child(verb)
		row.add_child(pair)
	if column != null:
		return column
	return row


## Mirrors the minimap's narrow-portrait rule: when a logical pixel renders
## physically tiny the gauge captions are unreadable noise rather than help,
## so they hide and the capsules speak for themselves.
func _update_bar_tags() -> void:
	var window := get_window()
	var viewport := get_viewport()
	if window == null or viewport == null:
		return
	var logical_width := maxf(viewport.get_visible_rect().size.x, 1.0)
	var px_per_logical := float(window.size.x) / logical_width
	var legible := px_per_logical >= 0.55
	for tag: Label in _bar_tags:
		tag.visible = legible
	if _esc_hint != null:
		_esc_hint.visible = legible


## --- Build ------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hud_scale := float(SettingsManager.get_setting("accessibility", "hud_scale"))
	_hud_scale = hud_scale
	add_child(_root)

	_build_position_card(hud_scale)
	_build_time_card(hud_scale)
	_build_item_card(hud_scale)
	_build_fish_card(hud_scale)
	_build_gauges(hud_scale)
	_build_messages(hud_scale)
	_build_hints(hud_scale)
	# Same narrow-portrait rule as the minimap: drop the micro-captions and the
	# pause reminder when logical pixels render physically tiny, where they are
	# unreadable noise rather than help.
	if not GameConfig.is_headless():
		get_viewport().size_changed.connect(_update_bar_tags)
		_update_bar_tags()

	# Course minimap (top-right card under the item slot; hides itself on
	# tiny viewports and when gameplay/show_minimap is off).
	var minimap := RaceMinimap.new()
	_root.add_child(minimap)
	minimap.setup(manager, hud_scale)


## Position card (top left): a podium-coloured edge stripe, the place numeral
## as the loudest thing on screen, and a quiet ordinal/field column beside it.
## Hidden outright when there is nobody to be ahead of (Time Trial, Endless) —
## "1st of 1" is furniture, and the clock deserves the attention instead.
func _build_position_card(s: float) -> void:
	if manager.single_racer_mode or manager.racers.size() <= 1:
		return
	_position_card = PanelContainer.new()
	_position_card.position = Vector2(GUTTER, GUTTER)
	_position_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_position_card.add_theme_stylebox_override("panel", _card_style(14.0 * s, 8.0 * s))
	_root.add_child(_position_card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(10 * s))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_position_card.add_child(row)

	_position_stripe = Panel.new()
	_position_stripe.custom_minimum_size = Vector2(4.0 * s, 0.0)
	_position_stripe.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_position_stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_position_stripe)

	_position_label = _value_label("1", 66 * s)
	# Fixed numeral box: the card must not twitch wider when the place changes.
	_position_label.custom_minimum_size = Vector2(44.0 * s, 0.0)
	_position_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_position_label)

	var ordinal := VBoxContainer.new()
	ordinal.add_theme_constant_override("separation", 0)
	ordinal.alignment = BoxContainer.ALIGNMENT_CENTER
	ordinal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ordinal)
	_position_suffix = _value_label("ST", 22 * s, UITheme.COLOR_ACCENT)
	ordinal.add_child(_position_suffix)
	_position_total = _caption_label("of 8", 14 * s)
	ordinal.add_child(_position_total)

	# Seed with the real grid slot so the countdown shows actual data instead
	# of placeholders.
	_set_position_display(maxi(manager.racers.find(player) + 1, 1), maxi(manager.racers.size(), 1))


## Clock card (top centre): caption above, monospaced-feeling numerals below.
func _build_time_card(s: float) -> void:
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.offset_left = 0
	card.offset_right = 0
	card.offset_top = GUTTER
	card.add_theme_stylebox_override("panel", _card_style(20.0 * s, 6.0 * s))
	_root.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	_time_caption = _caption_label("Time", 12 * s)
	_time_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_time_caption)
	_time_label = _value_label(format_time(0.0), 34 * s)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_time_label)


## Item card (top right): a recessed well holding the pickup glyph, the pickup
## name, ammo pips, and (desktop) the live "use" keycap. Fixed height with the
## hint row reserved, so the card never reflows mid-race; width matches the
## minimap card below it so the right column reads as one stack.
func _build_item_card(s: float) -> void:
	var width := COLUMN_WIDTH * s
	if UITheme.is_touch():
		# The touch pause button parks just left of this column.
		width = minf(width, COLUMN_WIDTH_TOUCH_MAX)
	var height := (ITEM_CARD_HEIGHT_TOUCH if UITheme.is_touch() else ITEM_CARD_HEIGHT) * s

	_item_panel = Panel.new()
	_item_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_item_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_item_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_item_panel.offset_left = -GUTTER - width
	_item_panel.offset_right = -GUTTER
	_item_panel.offset_top = GUTTER
	_item_panel.offset_bottom = GUTTER + height
	_item_panel.add_theme_stylebox_override("panel", _card_style(8.0 * s, 8.0 * s))
	_root.add_child(_item_panel)

	# Warm ring behind the card, faded in while an item is held. Kept as its
	# own node so the card art itself stays a plain shared style.
	_item_glow = Panel.new()
	_item_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_item_glow.offset_left = -3.0
	_item_glow.offset_top = -3.0
	_item_glow.offset_right = 3.0
	_item_glow.offset_bottom = 3.0
	_item_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_item_glow.modulate.a = 0.0
	_item_glow_style = StyleBoxFlat.new()
	_item_glow_style.draw_center = false
	_item_glow_style.set_corner_radius_all(int(CARD_RADIUS + 3.0))
	_item_glow_style.set_border_width_all(2)
	_item_glow_style.border_color = Color(UITheme.COLOR_GOLD, 0.9)
	_item_glow_style.shadow_color = Color(UITheme.COLOR_GOLD, 0.35)
	_item_glow_style.shadow_size = 10
	_item_glow.add_theme_stylebox_override("panel", _item_glow_style)
	_item_panel.add_child(_item_glow)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 8.0 * s
	box.offset_right = -8.0 * s
	box.offset_top = 8.0 * s
	box.offset_bottom = -8.0 * s
	box.add_theme_constant_override("separation", int(5 * s))
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_item_panel.add_child(box)

	# Recessed well: gives the glyph a socket to sit in instead of floating.
	_item_icon_size = 40.0 * s
	var well := Panel.new()
	well.custom_minimum_size = Vector2(_item_icon_size + 14.0 * s, _item_icon_size + 14.0 * s)
	well.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var well_style := StyleBoxFlat.new()
	well_style.bg_color = Color(UITheme.COLOR_BG_DEEP, 0.55)
	well_style.set_corner_radius_all(int(10 * s))
	well_style.set_border_width_all(1)
	well_style.border_color = Color(UITheme.COLOR_ACCENT, 0.18)
	well.add_theme_stylebox_override("panel", well_style)
	box.add_child(well)

	_item_icon = TextureRect.new()
	_item_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_item_icon.offset_left = 7.0 * s
	_item_icon.offset_top = 7.0 * s
	_item_icon.offset_right = -7.0 * s
	_item_icon.offset_bottom = -7.0 * s
	_item_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_item_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_child(_item_icon)
	_set_item_icon("")

	_item_label = _caption_label("No Item", 14 * s)
	_item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_item_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_item_label.clip_text = true
	box.add_child(_item_label)

	# Snowball ammo pips: collected throwable snowballs, up to 3.
	var ammo_box := HBoxContainer.new()
	ammo_box.alignment = BoxContainer.ALIGNMENT_CENTER
	ammo_box.add_theme_constant_override("separation", int(6 * s))
	ammo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(ammo_box)
	var pip_size := 10.0 * s
	_ammo_style_full = StyleBoxFlat.new()
	_ammo_style_full.bg_color = Color(0.96, 0.98, 1.0)
	_ammo_style_full.set_corner_radius_all(int(pip_size * 0.5))
	_ammo_style_full.set_border_width_all(1)
	_ammo_style_full.border_color = Color(UITheme.COLOR_ACCENT, 0.9)
	_ammo_style_empty = StyleBoxFlat.new()
	_ammo_style_empty.bg_color = Color(UITheme.COLOR_BG_DEEP, 0.7)
	_ammo_style_empty.set_corner_radius_all(int(pip_size * 0.5))
	_ammo_style_empty.set_border_width_all(1)
	_ammo_style_empty.border_color = Color(UITheme.COLOR_ACCENT, 0.28)
	for i: int in Racer.MAX_SNOWBALL_AMMO:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(pip_size, pip_size)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.add_theme_stylebox_override("panel", _ammo_style_empty)
		ammo_box.add_child(pip)
		_ammo_pips.append(pip)

	# Desktop-only "how do I use this?" hint: keycap with the actual bound key,
	# shown while an item or snowball ammo is held. Touch devices have a
	# dedicated item button, so no hint there.
	if not UITheme.is_touch():
		_use_hint = HBoxContainer.new()
		_use_hint.alignment = BoxContainer.ALIGNMENT_CENTER
		_use_hint.add_theme_constant_override("separation", int(5 * s))
		_use_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_use_hint.modulate.a = 0.0
		box.add_child(_use_hint)
		var use_cap := make_keycap("?", int(14 * s))
		_use_key_label = use_cap.get_child(0) as Label
		_use_hint.add_child(use_cap)
		_use_verb_label = _caption_label("Use", 13 * s)
		_use_verb_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_use_hint.add_child(_use_verb_label)


## Fish counter (bottom left), on the same baseline as both gauges.
func _build_fish_card(s: float) -> void:
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	card.grow_horizontal = Control.GROW_DIRECTION_END
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.offset_left = GUTTER
	card.offset_bottom = -GUTTER
	card.add_theme_stylebox_override("panel", _card_style(13.0 * s, 5.0 * s))
	_root.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(9 * s))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var fish_tex := _make_fish_texture()
	if fish_tex != null:
		var fish_icon := TextureRect.new()
		fish_icon.texture = fish_tex
		fish_icon.custom_minimum_size = Vector2(38 * s, 26 * s)
		fish_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fish_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		fish_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(fish_icon)
	else:
		# SVG module unavailable: fall back to a glyph so the counter still
		# reads correctly.
		var fish_glyph := _value_label("><>", 26 * s, UITheme.COLOR_ACCENT)
		fish_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(fish_glyph)
	_fish_label = _value_label("0", 30 * s)
	_fish_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_fish_label)


## Course and speed gauges. Both are the same capsule with the same caption
## row above them, sitting on the same bottom baseline as the fish card, so the
## bottom edge of the screen reads as one instrument rail instead of two
## unrelated slabs. On touch the speed gauge moves to the left column, because
## the bottom-right corner belongs to the SHOVE / ITEM buttons.
func _build_gauges(s: float) -> void:
	var bar_h := BAR_HEIGHT * s
	var cap_h := 17.0 * s
	var rail_h := bar_h + 4.0 * s + cap_h
	_hint_bottom = -(GUTTER + rail_h + float(GAP_M))

	# Course progress (bottom centre): caption left, percentage right.
	var course_caption := HBoxContainer.new()
	course_caption.anchor_left = 0.32
	course_caption.anchor_right = 0.68
	course_caption.anchor_top = 1.0
	course_caption.anchor_bottom = 1.0
	course_caption.offset_top = -(GUTTER + rail_h)
	course_caption.offset_bottom = -(GUTTER + bar_h + 4.0 * s)
	course_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(course_caption)
	var course_tag := _caption_label("Course", 13 * s)
	course_tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	course_caption.add_child(course_tag)
	_bar_tags.append(course_tag)
	_progress_value = _caption_label("0%", 13 * s)
	_progress_value.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	_progress_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	course_caption.add_child(_progress_value)
	_bar_tags.append(_progress_value)

	var course_groove := _make_gauge(bar_h, 3.0 * s,
		UITheme.COLOR_ACCENT.darkened(0.18), UITheme.COLOR_ACCENT.lightened(0.55))
	course_groove.anchor_left = 0.32
	course_groove.anchor_right = 0.68
	course_groove.anchor_top = 1.0
	course_groove.anchor_bottom = 1.0
	course_groove.offset_top = -(GUTTER + bar_h)
	course_groove.offset_bottom = -GUTTER
	_root.add_child(course_groove)
	_progress_bar = course_groove.get_child(0) as ProgressBar

	# Speed gauge: right column on desktop, above the fish card on touch.
	var speed_w := 210.0 * s
	var touch := UITheme.is_touch()
	var speed_bottom := -GUTTER if not touch else -(GUTTER + 52.0 * s + float(GAP_M))
	var speed_caption := HBoxContainer.new()
	speed_caption.anchor_top = 1.0
	speed_caption.anchor_bottom = 1.0
	if touch:
		speed_caption.anchor_left = 0.0
		speed_caption.anchor_right = 0.0
		speed_caption.offset_left = GUTTER
		speed_caption.offset_right = GUTTER + speed_w
	else:
		speed_caption.anchor_left = 1.0
		speed_caption.anchor_right = 1.0
		speed_caption.offset_left = -GUTTER - speed_w
		speed_caption.offset_right = -GUTTER
	speed_caption.offset_top = speed_bottom - rail_h
	speed_caption.offset_bottom = speed_bottom - bar_h - 4.0 * s
	speed_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(speed_caption)
	var speed_tag := _caption_label("Speed", 13 * s)
	speed_tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_caption.add_child(speed_tag)
	_bar_tags.append(speed_tag)
	# Lights up only at the top of the gauge, so peak speed reads without a
	# number to parse.
	_speed_flag = _caption_label("Max", 13 * s)
	_speed_flag.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	_speed_flag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed_flag.modulate.a = 0.0
	speed_caption.add_child(_speed_flag)

	var speed_groove := _make_gauge(bar_h, 3.0 * s,
		UITheme.COLOR_ACCENT.darkened(0.12), UITheme.COLOR_GOLD)
	speed_groove.anchor_top = 1.0
	speed_groove.anchor_bottom = 1.0
	if touch:
		speed_groove.anchor_left = 0.0
		speed_groove.anchor_right = 0.0
		speed_groove.offset_left = GUTTER
		speed_groove.offset_right = GUTTER + speed_w
	else:
		speed_groove.anchor_left = 1.0
		speed_groove.anchor_right = 1.0
		speed_groove.offset_left = -GUTTER - speed_w
		speed_groove.offset_right = -GUTTER
	speed_groove.offset_top = speed_bottom - bar_h
	speed_groove.offset_bottom = speed_bottom
	_root.add_child(speed_groove)
	_speed_bar = speed_groove.get_child(0) as ProgressBar


## Countdown / message / checkpoint text, stacked clear of the control strip.
func _build_messages(s: float) -> void:
	_checkpoint_label = _value_label("", 24 * s, UITheme.COLOR_ACCENT)
	_checkpoint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_checkpoint_label.anchor_left = 0.5
	_checkpoint_label.anchor_right = 0.5
	_checkpoint_label.offset_left = -180
	_checkpoint_label.offset_right = 180
	_checkpoint_label.offset_top = _hint_bottom - 52.0
	_checkpoint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_checkpoint_label.modulate.a = 0.0
	_root.add_child(_checkpoint_label)

	_center_label = _value_label("", 120 * s)
	_center_label.set_anchors_preset(Control.PRESET_CENTER)
	_center_label.anchor_left = 0.5
	_center_label.anchor_right = 0.5
	_center_label.anchor_top = 0.35
	_center_label.anchor_bottom = 0.35
	_center_label.offset_left = -320
	_center_label.offset_right = 320
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.add_theme_constant_override("outline_size", 12)
	_root.add_child(_center_label)


## Pause reminder and the onboarding control strip.
func _build_hints(s: float) -> void:
	# Desktop-only pause hint: sits above the speed gauge at low opacity with
	# the actual bound key. Hidden on touch devices (they get a pause button).
	if not UITheme.is_touch():
		var esc_hint := HBoxContainer.new()
		esc_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		esc_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		esc_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
		esc_hint.offset_right = -GUTTER
		esc_hint.offset_bottom = _hint_bottom - 6.0
		esc_hint.add_theme_constant_override("separation", int(5 * s))
		esc_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		esc_hint.modulate.a = 0.45
		var pause_key := SettingsManager.describe_action_binding("pause", "key")
		if pause_key == "—":
			pause_key = "Esc"
		esc_hint.add_child(make_keycap(pause_key, int(13 * s)))
		esc_hint.add_child(_caption_label("Pause", 13 * s))
		_root.add_child(esc_hint)
		_esc_hint = esc_hint

	# Onboarding strip (bottom centre, above the rail): shown through the
	# countdown and faded a while after GO. Keyboard players get live keycap
	# bindings; touch players get the gesture + button cheat sheet.
	if bool(SettingsManager.get_setting("gameplay", "tutorial_prompts")):
		_controls_hint = PanelContainer.new()
		_controls_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_controls_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_controls_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_controls_hint.offset_left = 0
		_controls_hint.offset_right = 0
		_controls_hint.offset_bottom = _hint_bottom
		_controls_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_controls_hint.add_theme_stylebox_override("panel", _card_style(16.0 * s, 7.0 * s))
		_controls_hint.add_child(build_controls_strip(s))
		_root.add_child(_controls_hint)


## Endless mode: time label doubles as score/distance/storm readout.
var _endless_mode: bool = false


func set_endless_status(score: int, distance: float, storm_gap: float) -> void:
	_endless_mode = true
	_time_caption.text = "ENDLESS"
	_time_label.text = "Score %d   •   %dm   •   Storm %dm" % [score, int(distance), int(storm_gap)]
	if storm_gap < 25.0:
		_time_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	else:
		_time_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT)


## Screen-edge speed lines shown while boosted / at slide top speed.
var _speed_lines: Control = null
var _speed_line_items: Array[ColorRect] = []


func _ensure_speed_lines() -> void:
	if _speed_lines != null:
		return
	_speed_lines = Control.new()
	_speed_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_speed_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_lines.modulate.a = 0.0
	_root.add_child(_speed_lines)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i: int in 14:
		var line := ColorRect.new()
		line.color = Color(1, 1, 1, rng.randf_range(0.25, 0.5))
		var vertical := rng.randf() > 0.5
		var length := rng.randf_range(80.0, 220.0)
		line.custom_minimum_size = Vector2(3, length)
		var edge := rng.randf()
		line.anchor_left = 0.02 if edge < 0.5 else 0.94
		line.anchor_top = rng.randf_range(0.05, 0.8)
		line.anchor_right = line.anchor_left
		line.anchor_bottom = line.anchor_top
		line.rotation = deg_to_rad(rng.randf_range(-6.0, 6.0))
		if not vertical:
			line.anchor_left = rng.randf_range(0.1, 0.9)
			line.anchor_top = 0.03 if edge < 0.5 else 0.92
		_speed_lines.add_child(line)
		_speed_line_items.append(line)


func _process(_delta: float) -> void:
	if manager == null or player == null or not is_instance_valid(player):
		return
	if manager.started and not _endless_mode:
		_time_label.text = format_time(manager.race_time)
	# Speed lines fade with extreme speed; respect reduced-flashing setting.
	_ensure_speed_lines()
	var reduced := bool(SettingsManager.get_setting("accessibility", "reduced_flashing"))
	var over_speed := clampf((player.current_speed / Racer.BASE_SPEED - 1.25) * 1.4, 0.0, 1.0)
	var target_alpha := 0.0 if reduced else over_speed * 0.6
	_speed_lines.modulate.a = lerpf(_speed_lines.modulate.a, target_alpha, 0.15)
	var speed_ratio := clampf(player.current_speed / Racer.SLIDE_MAX_SPEED, 0.0, 1.0)
	_speed_bar.value = speed_ratio
	# "MAX" tag with hysteresis so it never flickers at the threshold.
	if speed_ratio > 0.97 and not _speed_flagged:
		_speed_flagged = true
		_speed_flag.modulate.a = 1.0
	elif speed_ratio < 0.92 and _speed_flagged:
		_speed_flagged = false
		_speed_flag.modulate.a = 0.0
	if player.course != null and player.course is CourseBase:
		var course := player.course as CourseBase
		if course.main_guide != null and course.main_guide.length > 1.0:
			var ratio := clampf(player.progress / course.finish_offset, 0.0, 1.0)
			_progress_bar.value = ratio
			# Only touch the label when the rounded value actually moves.
			var pct := int(ratio * 100.0)
			if pct != _progress_shown:
				_progress_shown = pct
				_progress_value.text = "%d%%" % pct
	# Keyboard/controller reachability: the finish button is the HUD's only
	# focusable, so reclaim focus if a pause-menu round trip dropped it.
	if _finish_button != null and is_instance_valid(_finish_button) \
			and not _finish_button.disabled and get_viewport().gui_get_focus_owner() == null:
		_finish_button.grab_focus()


static func format_time(seconds: float) -> String:
	var minutes := int(seconds) / 60
	var secs := fmod(seconds, 60.0)
	return "%d:%05.2f" % [minutes, secs]


func _on_countdown(value: int) -> void:
	_center_label.text = str(value) if value > 0 else "GO!"
	_center_label.modulate = Color(1, 1, 1) if value > 0 else Color(0.4, 1.0, 0.5)
	_center_label.scale = Vector2.ONE * 1.4
	_center_label.pivot_offset = _center_label.size * 0.5
	var tween := create_tween()
	tween.tween_property(_center_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if value == 0:
		tween.tween_interval(0.5)
		tween.tween_property(_center_label, "modulate:a", 0.0, 0.4)
		tween.tween_callback(func() -> void:
			_center_label.text = ""
			_center_label.modulate.a = 1.0)


## Fades out the keyboard onboarding strip a while after the race starts.
func _fade_controls_hint() -> void:
	if _controls_hint == null:
		return
	var tween := create_tween()
	# 8s proved too short in playtests — hold well into the first stretch so
	# new players can glance down mid-run, then fade.
	tween.tween_interval(30.0)
	tween.tween_callback(func() -> void:
		_dismiss_controls_hint(0.6))


## Fades and frees the onboarding chip; also called early when the player
## finishes, since the strip is dead weight (and in the finish button's slot)
## once the run is over.
func _dismiss_controls_hint(fade_sec: float) -> void:
	if _controls_hint == null:
		return
	var chip := _controls_hint
	_controls_hint = null
	var tween := create_tween()
	tween.tween_property(chip, "modulate:a", 0.0, fade_sec)
	tween.tween_callback(chip.queue_free)


## Player done, rivals still racing: after a short grace window offer to close
## the race out instead of making the player watch the full finish timeout.
func _on_player_finished(_racer: Racer) -> void:
	_dismiss_controls_hint(0.4)
	get_tree().create_timer(4.0, false).timeout.connect(_show_finish_button)


## Bottom-center "Finish Race" button (focusable, touch-sized): collapses the
## manager's remaining finish window, so AI still on course resolve exactly as
## they would at the timeout (projected times, DNF rules unchanged).
func _show_finish_button() -> void:
	if _race_over or _finish_button != null or manager == null or not is_inside_tree():
		return
	var button_scale := clampf(_hud_scale, 0.85, 1.6)
	_finish_button = UITheme.make_button("Finish Race",
		Vector2(250.0 * button_scale, 54.0 * button_scale), int(24.0 * button_scale))
	# Drawn arrow, not "→": the bundled font has no arrow glyph, so the typed
	# one printed a .notdef box on the web build.
	var finish_arrow := UITheme.arrow_texture(
		"right", UITheme.COLOR_TEXT, int(36.0 * button_scale))
	if finish_arrow != null:
		_finish_button.icon = finish_arrow
		_finish_button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_finish_button.expand_icon = true
	UITheme.hook_sounds(_finish_button)
	_finish_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_finish_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_finish_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_finish_button.offset_bottom = _hint_bottom
	_finish_button.pressed.connect(_on_finish_button_pressed)
	_root.add_child(_finish_button)
	if UITheme.reduced_motion():
		_finish_button.modulate.a = 1.0
	else:
		_finish_button.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(_finish_button, "modulate:a", 1.0, 0.25)
	_finish_button.grab_focus()


func _on_finish_button_pressed() -> void:
	if manager == null or _race_over:
		return
	_race_over = true
	if _finish_button != null:
		_finish_button.disabled = true
	# Close the finish window through the manager's own time-based path: the
	# next physics tick runs its normal completion, which assigns projected
	# times to any AI still on course.
	if manager._finish_countdown > 0.05:
		manager._finish_countdown = 0.05


func _on_race_completed() -> void:
	_race_over = true
	if _finish_button != null and is_instance_valid(_finish_button):
		_finish_button.queue_free()
	_finish_button = null


func show_message(text: String) -> void:
	_center_label.text = text
	_center_label.modulate = UITheme.COLOR_GOLD
	var tween := create_tween()
	tween.tween_interval(1.6)
	tween.tween_property(_center_label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func() -> void:
		_center_label.text = ""
		_center_label.modulate.a = 1.0)


func _on_positions(_standings: Array[Racer]) -> void:
	_set_position_display(player.race_position, manager.racers.size())


## Position card ("2 ND / of 8") with podium colours on the numeral, the
## ordinal and the edge stripe; also seeds the pre-race grid slot.
func _set_position_display(pos: int, total: int) -> void:
	if _position_label == null:
		return
	_position_label.text = str(pos)
	var suffix := "TH"
	match pos:
		1: suffix = "ST"
		2: suffix = "ND"
		3: suffix = "RD"
	_position_suffix.text = suffix
	_position_total.text = "OF %d" % total
	var accent := UITheme.COLOR_TEXT
	match pos:
		1: accent = UITheme.COLOR_GOLD
		2: accent = Color(0.82, 0.87, 0.94)
		3: accent = Color(0.85, 0.62, 0.42)
	_position_label.add_theme_color_override("font_color", accent)
	_position_suffix.add_theme_color_override("font_color", accent)
	var stripe := StyleBoxFlat.new()
	stripe.bg_color = Color(accent, 0.9)
	stripe.set_corner_radius_all(int(2.0 * _hud_scale))
	_position_stripe.add_theme_stylebox_override("panel", stripe)


func _on_fish(_racer: Racer, _value: int) -> void:
	_fish_label.text = "%d" % player.fish_count
	_fish_label.pivot_offset = _fish_label.size * 0.5
	var tween := create_tween()
	_fish_label.scale = Vector2.ONE * 1.3
	tween.tween_property(_fish_label, "scale", Vector2.ONE, 0.18)


func _on_item_received(_racer: Racer, item_id: String) -> void:
	var info := PowerupsDB.get_item(item_id)
	_item_label.text = String(info.get("name", item_id)).to_upper()
	_item_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	_set_item_icon(String(info.get("icon", "")))
	var tween := create_tween()
	_item_panel.scale = Vector2.ONE * 1.15
	_item_panel.pivot_offset = _item_panel.size * 0.5
	tween.tween_property(_item_panel, "scale", Vector2.ONE, 0.2)
	_start_item_pulse()
	_held_item = true
	_update_use_hint()


func _on_item_used(_racer: Racer, _item_id: String) -> void:
	_item_label.text = "NO ITEM"
	_item_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	_set_item_icon("")
	_stop_item_pulse()
	_held_item = false
	_update_use_hint()


func _on_snowball_ammo(_racer: Racer, ammo: int) -> void:
	for i: int in _ammo_pips.size():
		_ammo_pips[i].add_theme_stylebox_override("panel",
			_ammo_style_full if i < ammo else _ammo_style_empty)
	_item_panel.pivot_offset = _item_panel.size * 0.5
	_item_panel.scale = Vector2.ONE * 1.08
	var tween := create_tween()
	tween.tween_property(_item_panel, "scale", Vector2.ONE, 0.15)
	_ammo_count = ammo
	_update_use_hint()


## Desktop keycap hint under the item slot: visible while the player holds
## an item ("Use") or, with no item, snowball ammo ("Throw"). Rereads the
## live binding each time so remaps show correctly. The row keeps its space
## either way, so the card never reflows.
func _update_use_hint() -> void:
	if _use_hint == null:
		return
	var should_show := _held_item or _ammo_count > 0
	_use_hint.modulate.a = 1.0 if should_show else 0.0
	if should_show:
		var key := SettingsManager.describe_action_binding("use_item", "key")
		_use_key_label.text = key if key != "—" else "Q"
		_use_verb_label.text = "USE" if _held_item else "THROW"


## Slow warm glow pulse around the item card while an item is held. With
## reduced flashing enabled the ring holds a static highlight instead.
func _start_item_pulse() -> void:
	_stop_item_pulse()
	if bool(SettingsManager.get_setting("accessibility", "reduced_flashing")):
		_item_glow.modulate.a = 0.85
		return
	_item_pulse = create_tween()
	_item_pulse.set_loops()
	_item_pulse.tween_property(_item_glow, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_item_pulse.tween_property(_item_glow, "modulate:a", 0.28, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_item_pulse() -> void:
	if _item_pulse != null and _item_pulse.is_valid():
		_item_pulse.kill()
	_item_pulse = null
	_item_glow.modulate.a = 0.0


func _on_checkpoint(_racer: Racer, index: int) -> void:
	_checkpoint_label.text = "Checkpoint %d" % (index + 1)
	_checkpoint_label.modulate = Color(UITheme.COLOR_ACCENT, 1.0)
	AudioManager.play_sfx("sfx_checkpoint", 1.0, -6.0)
	var tween := create_tween()
	tween.tween_interval(1.0)
	tween.tween_property(_checkpoint_label, "modulate:a", 0.0, 0.5)


## Swaps the item-slot glyph. An empty id draws the dashed placeholder so the
## slot still reads as a slot when the player is carrying nothing.
func _set_item_icon(icon_id: String) -> void:
	if _item_icon == null:
		return
	var svg := String(ITEM_ICONS.get(icon_id, ""))
	if svg.is_empty():
		_item_icon.texture = UITheme.make_icon(EMPTY_SLOT_SVG, 1.0)
		_item_icon.modulate = Color(UITheme.COLOR_ACCENT, 0.34)
		return
	_item_icon.texture = UITheme.make_icon(svg, 1.0)
	_item_icon.modulate = Color.WHITE
