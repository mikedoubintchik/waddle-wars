class_name RaceHUD
extends CanvasLayer
## In-race HUD: position, progress, item, fish, speed, countdown, time,
## messages, and an early "Finish Race" button once the player is done while
## AI are still on course. Scales with the accessibility HUD-scale setting.
## Visual theme: deep navy rounded panels, ice-blue accents, warm yellow
## position highlight, soft drop shadows.

const PANEL_NAVY := Color(0.05, 0.09, 0.17, 0.86)
const PANEL_NAVY_DEEP := Color(0.035, 0.065, 0.13, 0.72)
const ACCENT_ICE := Color(0.55, 0.8, 1.0)
const ACCENT_YELLOW := Color(1.0, 0.85, 0.25)
const OUTLINE_NAVY := Color(0.07, 0.14, 0.27)
const SHADOW_SOFT := Color(0.0, 0.0, 0.0, 0.32)
const ITEM_ICON_EMPTY := Color(0.16, 0.26, 0.42)

## Placeholder drawn in the item slot while the player carries nothing.
const EMPTY_SLOT_SVG := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<rect x="10" y="10" width="44" height="44" rx="10" fill="#ffffff" opacity="0.5"/>
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

var manager: RaceManager = null
var player: Racer = null

var _position_label: Label
var _position_suffix: Label
var _time_label: Label
var _fish_label: Label
var _item_panel: PanelContainer
var _item_label: Label
var _item_icon: TextureRect
var _item_icon_size: float = 46.0
var _item_style: StyleBoxFlat
var _item_pulse: Tween = null
var _ammo_pips: Array[Panel] = []
var _ammo_style_full: StyleBoxFlat
var _ammo_style_empty: StyleBoxFlat
var _use_hint: HBoxContainer = null
var _use_key_label: Label = null
var _use_verb_label: Label = null
var _held_item: bool = false
var _ammo_count: int = 0
var _speed_bar: ProgressBar
var _progress_bar: ProgressBar
var _center_label: Label
var _checkpoint_label: Label
var _controls_hint: PanelContainer = null
var _bar_tags: Array[Label] = []
var _finish_button: Button = null
var _race_over: bool = false
var _hud_scale: float = 1.0
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
	_checkpoint_label.modulate = Color(1.0, 0.9, 0.5, 1.0)
	var tween := create_tween()
	tween.tween_interval(0.9)
	tween.tween_property(_checkpoint_label, "modulate:a", 0.0, 0.4)


## Shared rounded navy card style with soft drop shadow.
func _panel_style(corner: float = 12.0, margin_h: float = 14.0, margin_v: float = 6.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_NAVY
	style.set_corner_radius_all(int(corner))
	style.set_border_width_all(2)
	style.border_color = Color(ACCENT_ICE, 0.45)
	style.content_margin_left = margin_h
	style.content_margin_right = margin_h
	style.content_margin_top = margin_v
	style.content_margin_bottom = margin_v
	style.shadow_color = SHADOW_SOFT
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 3)
	return style


## Rounded gradient fill for progress-style bars, baked into a texture so
## the fill keeps soft corners (StyleBoxFlat cannot gradient).
static func _make_gradient_fill(from: Color, to: Color) -> StyleBoxTexture:
	var w := 96
	var h := 16
	var radius := 6.0
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y: int in h:
		# Subtle vertical shading: lighter crest at the top of the bar.
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


func _style_bar(bar: ProgressBar, fill_from: Color, fill_to: Color) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = PANEL_NAVY_DEEP
	bg.set_corner_radius_all(8)
	bg.set_border_width_all(1)
	bg.border_color = Color(ACCENT_ICE, 0.35)
	bg.shadow_color = SHADOW_SOFT
	bg.shadow_size = 3
	bg.shadow_offset = Vector2(0, 2)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", _make_gradient_fill(fill_from, fill_to))


static func _make_fish_texture() -> ImageTexture:
	var img := Image.new()
	if img.load_svg_from_string(FISH_ICON_SVG, 2.0) != OK:
		return null
	return ImageTexture.create_from_image(img)


## Small keyboard-keycap chip (light face, heavier bottom border) used for
## desktop input hints. Returns the panel; its Label child holds the text.
static func _make_keycap(text: String, font_size: int) -> PanelContainer:
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
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", OUTLINE_NAVY)
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
			[["Drag ↔"], "Steer"],
			[["Swipe ↑"], "Jump"],
			[["Hold ↓"], "Slide"],
			[["SHOVE"], "Bump rivals"],
			[["ITEM"], "Use pickup"],
			[["BACK v"], "Throw behind"],
		]
	else:
		hints = [
			[["steer_left", "steer_right"], "Steer"],
			[["jump"], "Jump"],
			[["slide"], "Slide"],
			[["shove"], "Shove"],
			[["use_item"], "Item"],
			[["aim_back", "use_item"], "Throw behind"],
		]
	var column: VBoxContainer = null
	if max_per_row > 0:
		column = VBoxContainer.new()
		column.add_theme_constant_override("separation", 8)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row: HBoxContainer = null
	for i: int in hints.size():
		if row == null or (max_per_row > 0 and i % max_per_row == 0):
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 16)
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if column != null:
				column.add_child(row)
		var hint: Array = hints[i]
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 4)
		pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for action: String in hint[0]:
			var cap := action
			if not UITheme.is_touch():
				var key := SettingsManager.describe_action_binding(action, "key")
				cap = key if key != "—" else "?"
			pair.add_child(_make_keycap(cap, int(14 * hud_scale)))
		var verb := Label.new()
		verb.text = String(hint[1])
		verb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		verb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		verb.add_theme_font_size_override("font_size", int(14 * hud_scale))
		verb.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
		pair.add_child(verb)
		row.add_child(pair)
	if column != null:
		return column
	return row


## Tiny dim caption naming a HUD bar ("Course", "Speed"): low-contrast with a
## thin navy outline so it reads over snow without drawing focus.
func _make_bar_tag(text: String, hud_scale: float) -> Label:
	var tag := Label.new()
	tag.text = text
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_theme_font_size_override("font_size", int(12 * hud_scale))
	tag.add_theme_color_override("font_color", Color(0.85, 0.93, 1.0, 0.62))
	tag.add_theme_constant_override("outline_size", 4)
	tag.add_theme_color_override("font_outline_color", Color(OUTLINE_NAVY, 0.85))
	return tag


## Mirrors the minimap's narrow-portrait rule: when a logical pixel renders
## physically tiny the 12 px captions are unreadable noise, so hide them.
func _update_bar_tags() -> void:
	var window := get_window()
	var viewport := get_viewport()
	if window == null or viewport == null:
		return
	var logical_width := maxf(viewport.get_visible_rect().size.x, 1.0)
	var px_per_logical := float(window.size.x) / logical_width
	for tag: Label in _bar_tags:
		tag.visible = px_per_logical >= 0.4


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hud_scale := float(SettingsManager.get_setting("accessibility", "hud_scale"))
	_hud_scale = hud_scale
	add_child(_root)

	# Position card (top left).
	var pos_panel := PanelContainer.new()
	pos_panel.position = Vector2(24, 20)
	pos_panel.add_theme_stylebox_override("panel", _panel_style(14.0, 16.0, 2.0))
	_root.add_child(pos_panel)
	var pos_box := HBoxContainer.new()
	pos_box.add_theme_constant_override("separation", 6)
	pos_panel.add_child(pos_box)
	_position_label = Label.new()
	_position_label.add_theme_font_size_override("font_size", int(76 * hud_scale))
	_position_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_position_label.add_theme_constant_override("outline_size", 8)
	_position_label.add_theme_color_override("font_outline_color", OUTLINE_NAVY)
	pos_box.add_child(_position_label)
	_position_suffix = Label.new()
	_position_suffix.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_position_suffix.add_theme_font_size_override("font_size", int(30 * hud_scale))
	_position_suffix.add_theme_color_override("font_color", Color(ACCENT_ICE, 0.95))
	pos_box.add_child(_position_suffix)
	# Seed with the real grid slot so the countdown shows actual data instead
	# of placeholders (Time Trial reads 1st / 1).
	_set_position_display(maxi(manager.racers.find(player) + 1, 1), maxi(manager.racers.size(), 1))

	# Time pill (top center).
	var time_panel := PanelContainer.new()
	time_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	time_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	time_panel.offset_left = 0
	time_panel.offset_right = 0
	time_panel.offset_top = 20
	time_panel.add_theme_stylebox_override("panel", _panel_style(18.0, 18.0, 5.0))
	_root.add_child(time_panel)
	_time_label = Label.new()
	_time_label.text = format_time(0.0)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.add_theme_font_size_override("font_size", int(34 * hud_scale))
	_time_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_time_label.add_theme_constant_override("outline_size", 6)
	_time_label.add_theme_color_override("font_outline_color", OUTLINE_NAVY)
	time_panel.add_child(_time_label)

	# Item slot (top right); border pulses while an item is held.
	_item_panel = PanelContainer.new()
	_item_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_item_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_item_panel.offset_left = -170
	_item_panel.offset_top = 20
	_item_panel.offset_right = -24
	_item_style = _panel_style(14.0, 12.0, 8.0)
	_item_style.border_color = Color(ACCENT_ICE, 0.55)
	_item_panel.add_theme_stylebox_override("panel", _item_style)
	var item_box := VBoxContainer.new()
	item_box.add_theme_constant_override("separation", 4)
	item_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_item_panel.add_child(item_box)
	var icon_center := CenterContainer.new()
	item_box.add_child(icon_center)
	_item_icon_size = 46.0 * hud_scale
	_item_icon = TextureRect.new()
	_item_icon.custom_minimum_size = Vector2(_item_icon_size, _item_icon_size)
	_item_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_item_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_item_icon.modulate = ITEM_ICON_EMPTY
	icon_center.add_child(_item_icon)
	_set_item_icon("")
	_item_label = Label.new()
	_item_label.text = "No Item"
	_item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_item_label.add_theme_font_size_override("font_size", int(17 * hud_scale))
	_item_label.add_theme_color_override("font_color", Color(0.85, 0.93, 1.0))
	item_box.add_child(_item_label)
	# Snowball ammo pips: collected throwable snowballs, up to 3.
	var ammo_box := HBoxContainer.new()
	ammo_box.alignment = BoxContainer.ALIGNMENT_CENTER
	ammo_box.add_theme_constant_override("separation", 6)
	item_box.add_child(ammo_box)
	var pip_size := 13.0 * hud_scale
	_ammo_style_full = StyleBoxFlat.new()
	_ammo_style_full.bg_color = Color(0.96, 0.98, 1.0)
	_ammo_style_full.set_corner_radius_all(int(pip_size * 0.5))
	_ammo_style_full.set_border_width_all(1)
	_ammo_style_full.border_color = Color(ACCENT_ICE, 0.9)
	_ammo_style_empty = StyleBoxFlat.new()
	_ammo_style_empty.bg_color = Color(ITEM_ICON_EMPTY, 0.55)
	_ammo_style_empty.set_corner_radius_all(int(pip_size * 0.5))
	_ammo_style_empty.set_border_width_all(1)
	_ammo_style_empty.border_color = Color(ACCENT_ICE, 0.3)
	for i: int in Racer.MAX_SNOWBALL_AMMO:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(pip_size, pip_size)
		pip.add_theme_stylebox_override("panel", _ammo_style_empty)
		ammo_box.add_child(pip)
		_ammo_pips.append(pip)
	# Desktop-only "how do I use this?" hint: keycap with the actual bound
	# key under the item slot, shown while an item or snowball ammo is held.
	# Touch devices have a dedicated item button, so no hint there.
	if not UITheme.is_touch():
		_use_hint = HBoxContainer.new()
		_use_hint.alignment = BoxContainer.ALIGNMENT_CENTER
		_use_hint.add_theme_constant_override("separation", 5)
		_use_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_use_hint.visible = false
		item_box.add_child(_use_hint)
		var use_cap := _make_keycap("?", int(15 * hud_scale))
		_use_key_label = use_cap.get_child(0) as Label
		_use_hint.add_child(use_cap)
		_use_verb_label = Label.new()
		_use_verb_label.text = "Use"
		_use_verb_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_use_verb_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_use_verb_label.add_theme_font_size_override("font_size", int(15 * hud_scale))
		_use_verb_label.add_theme_color_override("font_color", Color(0.85, 0.93, 1.0, 0.9))
		_use_hint.add_child(_use_verb_label)
	_root.add_child(_item_panel)

	# Fish counter card (bottom left) with generated fish icon.
	var fish_panel := PanelContainer.new()
	fish_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	fish_panel.grow_horizontal = Control.GROW_DIRECTION_END
	fish_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	fish_panel.offset_left = 24
	fish_panel.offset_top = -80
	fish_panel.offset_bottom = -24
	fish_panel.add_theme_stylebox_override("panel", _panel_style(14.0, 14.0, 5.0))
	_root.add_child(fish_panel)
	var fish_box := HBoxContainer.new()
	fish_box.add_theme_constant_override("separation", 8)
	fish_panel.add_child(fish_box)
	var fish_tex := _make_fish_texture()
	if fish_tex != null:
		var fish_icon := TextureRect.new()
		fish_icon.texture = fish_tex
		fish_icon.custom_minimum_size = Vector2(40 * hud_scale, 27 * hud_scale)
		fish_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fish_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		fish_box.add_child(fish_icon)
	else:
		# SVG module unavailable: fall back to a glyph so the counter
		# still reads correctly.
		var fish_glyph := Label.new()
		fish_glyph.text = "><>"
		fish_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fish_glyph.add_theme_font_size_override("font_size", int(30 * hud_scale))
		fish_glyph.add_theme_color_override("font_color", Color(0.55, 0.85, 0.95))
		fish_box.add_child(fish_glyph)
	_fish_label = Label.new()
	_fish_label.text = "0"
	_fish_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fish_label.add_theme_font_size_override("font_size", int(34 * hud_scale))
	_fish_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_fish_label.add_theme_constant_override("outline_size", 6)
	_fish_label.add_theme_color_override("font_outline_color", OUTLINE_NAVY)
	fish_box.add_child(_fish_label)

	# Speed bar (bottom right): ice blue rising to warm yellow at top speed.
	_speed_bar = ProgressBar.new()
	_speed_bar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_speed_bar.offset_left = -230
	_speed_bar.offset_top = -56
	_speed_bar.offset_right = -30
	_speed_bar.offset_bottom = -38
	_speed_bar.max_value = 1.0
	_speed_bar.show_percentage = false
	_style_bar(_speed_bar, Color(0.35, 0.65, 0.95), ACCENT_YELLOW)
	_root.add_child(_speed_bar)
	# Tiny dim caption naming the bar (playtest: its meaning wasn't obvious).
	var boost_tag := _make_bar_tag("Speed", hud_scale)
	boost_tag.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	boost_tag.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	boost_tag.grow_vertical = Control.GROW_DIRECTION_BEGIN
	boost_tag.offset_right = -30
	boost_tag.offset_bottom = -58
	_root.add_child(boost_tag)
	_bar_tags.append(boost_tag)

	# Course progress (bottom center): deep ice to bright ice gradient.
	_progress_bar = ProgressBar.new()
	_progress_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_progress_bar.anchor_left = 0.32
	_progress_bar.anchor_right = 0.68
	_progress_bar.offset_top = -46
	_progress_bar.offset_bottom = -30
	_progress_bar.max_value = 1.0
	_progress_bar.show_percentage = false
	_style_bar(_progress_bar, Color(0.3, 0.6, 0.95), Color(0.62, 0.9, 1.0))
	_root.add_child(_progress_bar)
	var course_tag := _make_bar_tag("Course", hud_scale)
	course_tag.anchor_left = 0.32
	course_tag.anchor_right = 0.32
	course_tag.anchor_top = 1.0
	course_tag.anchor_bottom = 1.0
	course_tag.grow_horizontal = Control.GROW_DIRECTION_END
	course_tag.grow_vertical = Control.GROW_DIRECTION_BEGIN
	course_tag.offset_bottom = -48
	_root.add_child(course_tag)
	_bar_tags.append(course_tag)
	# Same narrow-portrait rule as the minimap: hide the captions when logical
	# pixels render physically tiny.
	if not GameConfig.is_headless():
		get_viewport().size_changed.connect(_update_bar_tags)
		_update_bar_tags()

	_checkpoint_label = Label.new()
	_checkpoint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_checkpoint_label.anchor_left = 0.5
	_checkpoint_label.anchor_right = 0.5
	_checkpoint_label.offset_left = -150
	_checkpoint_label.offset_right = 150
	_checkpoint_label.offset_top = -80
	_checkpoint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_checkpoint_label.add_theme_font_size_override("font_size", int(24 * hud_scale))
	_checkpoint_label.add_theme_constant_override("outline_size", 5)
	_checkpoint_label.add_theme_color_override("font_outline_color", OUTLINE_NAVY)
	_checkpoint_label.modulate.a = 0.0
	_root.add_child(_checkpoint_label)

	# Center message / countdown.
	_center_label = Label.new()
	_center_label.set_anchors_preset(Control.PRESET_CENTER)
	_center_label.anchor_left = 0.5
	_center_label.anchor_right = 0.5
	_center_label.anchor_top = 0.35
	_center_label.anchor_bottom = 0.35
	_center_label.offset_left = -320
	_center_label.offset_right = 320
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.add_theme_font_size_override("font_size", int(120 * hud_scale))
	_center_label.add_theme_constant_override("outline_size", 12)
	_center_label.add_theme_color_override("font_outline_color", OUTLINE_NAVY)
	_root.add_child(_center_label)

	# Desktop-only pause hint (bottom right, under the speed bar): shows the
	# actual bound pause key at low opacity. Hidden on touch devices.
	if not UITheme.is_touch():
		var esc_hint := HBoxContainer.new()
		esc_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		esc_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		esc_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
		esc_hint.offset_right = -30
		esc_hint.offset_bottom = -10
		esc_hint.add_theme_constant_override("separation", 5)
		esc_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		esc_hint.modulate.a = 0.5
		var pause_key := SettingsManager.describe_action_binding("pause", "key")
		if pause_key == "—":
			pause_key = "Esc"
		esc_hint.add_child(_make_keycap(pause_key, int(14 * hud_scale)))
		var pause_label := Label.new()
		pause_label.text = "Pause"
		pause_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pause_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pause_label.add_theme_font_size_override("font_size", int(14 * hud_scale))
		pause_label.add_theme_color_override("font_color", Color(0.85, 0.93, 1.0))
		esc_hint.add_child(pause_label)
		_root.add_child(esc_hint)

	# Onboarding strip (bottom center): shown through the countdown and faded
	# shortly after GO. Keyboard players get live keycap bindings; touch
	# players get the gesture + button cheat sheet (SHOVE/ITEM explained).
	if bool(SettingsManager.get_setting("gameplay", "tutorial_prompts")):
		# Dark chip behind the strip: over bright snow the bare labels washed
		# out (screenshot QA).
		_controls_hint = PanelContainer.new()
		_controls_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_controls_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_controls_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_controls_hint.offset_left = 0
		_controls_hint.offset_right = 0
		_controls_hint.offset_bottom = -96
		_controls_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_controls_hint.modulate.a = 0.92
		var strip_style := UITheme.make_panel_style(Color(0.05, 0.09, 0.16, 0.78))
		strip_style.content_margin_left = 16.0
		strip_style.content_margin_right = 16.0
		strip_style.content_margin_top = 8.0
		strip_style.content_margin_bottom = 8.0
		_controls_hint.add_theme_stylebox_override("panel", strip_style)
		_controls_hint.add_child(build_controls_strip(hud_scale))
		_root.add_child(_controls_hint)

	# Course minimap (top-right card under the item slot; hides itself on
	# tiny viewports and when gameplay/show_minimap is off).
	var minimap := RaceMinimap.new()
	_root.add_child(minimap)
	minimap.setup(manager, hud_scale)


## Endless mode: time label doubles as score/distance/storm readout.
var _endless_mode: bool = false


func set_endless_status(score: int, distance: float, storm_gap: float) -> void:
	_endless_mode = true
	_time_label.text = "Score %d   •   %dm   •   Storm %dm" % [score, int(distance), int(storm_gap)]
	if storm_gap < 25.0:
		_time_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	else:
		_time_label.add_theme_color_override("font_color", Color(1, 1, 1))


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
	_speed_bar.value = clampf(player.current_speed / Racer.SLIDE_MAX_SPEED, 0.0, 1.0)
	if player.course != null and player.course is CourseBase:
		var course := player.course as CourseBase
		if course.main_guide != null and course.main_guide.length > 1.0:
			_progress_bar.value = clampf(player.progress / course.finish_offset, 0.0, 1.0)
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
	_finish_button = UITheme.make_button("Finish Race →",
		Vector2(250.0 * button_scale, 54.0 * button_scale), int(24.0 * button_scale))
	UITheme.hook_sounds(_finish_button)
	_finish_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_finish_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_finish_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_finish_button.offset_bottom = -96
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
	_center_label.modulate = Color(1.0, 0.9, 0.4)
	var tween := create_tween()
	tween.tween_interval(1.6)
	tween.tween_property(_center_label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func() -> void:
		_center_label.text = ""
		_center_label.modulate.a = 1.0)


func _on_positions(_standings: Array[Racer]) -> void:
	_set_position_display(player.race_position, manager.racers.size())


## Position card ("2nd / 8") with podium colours; also seeds the pre-race grid slot.
func _set_position_display(pos: int, total: int) -> void:
	_position_label.text = str(pos)
	var suffix := "th"
	match pos:
		1: suffix = "st"
		2: suffix = "nd"
		3: suffix = "rd"
	_position_suffix.text = "%s / %d" % [suffix, total]
	var colors := [Color(1.0, 0.85, 0.2), Color(0.8, 0.85, 0.9), Color(0.8, 0.6, 0.4)]
	_position_label.add_theme_color_override("font_color",
		colors[pos - 1] if pos >= 1 and pos <= 3 else Color(1, 1, 1))


func _on_fish(_racer: Racer, _value: int) -> void:
	_fish_label.text = "%d" % player.fish_count
	_fish_label.pivot_offset = _fish_label.size * 0.5
	var tween := create_tween()
	_fish_label.scale = Vector2.ONE * 1.3
	tween.tween_property(_fish_label, "scale", Vector2.ONE, 0.18)


func _on_item_received(_racer: Racer, item_id: String) -> void:
	var info := PowerupsDB.get_item(item_id)
	_item_label.text = String(info.get("name", item_id))
	_set_item_icon(String(info.get("icon", "")))
	var tween := create_tween()
	_item_panel.scale = Vector2.ONE * 1.15
	_item_panel.pivot_offset = _item_panel.size * 0.5
	tween.tween_property(_item_panel, "scale", Vector2.ONE, 0.2)
	_start_item_pulse()
	_held_item = true
	_update_use_hint()


func _on_item_used(_racer: Racer, _item_id: String) -> void:
	_item_label.text = "No Item"
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
## live binding each time so remaps show correctly.
func _update_use_hint() -> void:
	if _use_hint == null:
		return
	var should_show := _held_item or _ammo_count > 0
	_use_hint.visible = should_show
	if should_show:
		var key := SettingsManager.describe_action_binding("use_item", "key")
		_use_key_label.text = key if key != "—" else "Q"
		_use_verb_label.text = "Use" if _held_item else "Throw"


## Slow warm glow pulse on the item frame while an item is held. With
## reduced flashing enabled the frame holds a static bright highlight.
func _start_item_pulse() -> void:
	_stop_item_pulse()
	if bool(SettingsManager.get_setting("accessibility", "reduced_flashing")):
		_item_style.border_color = ACCENT_YELLOW
		return
	_item_pulse = create_tween()
	_item_pulse.set_loops()
	_item_pulse.tween_method(_set_item_glow, 0.0, 1.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_item_pulse.tween_method(_set_item_glow, 1.0, 0.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_item_pulse() -> void:
	if _item_pulse != null and _item_pulse.is_valid():
		_item_pulse.kill()
	_item_pulse = null
	_set_item_glow(0.0)


func _set_item_glow(amount: float) -> void:
	_item_style.border_color = Color(ACCENT_ICE, 0.55).lerp(ACCENT_YELLOW, amount)
	_item_style.shadow_color = SHADOW_SOFT.lerp(Color(ACCENT_YELLOW, 0.4), amount)


func _on_checkpoint(_racer: Racer, index: int) -> void:
	_checkpoint_label.text = "Checkpoint %d" % (index + 1)
	_checkpoint_label.modulate = Color(0.6, 0.95, 1.0, 1.0)
	AudioManager.play_sfx("sfx_checkpoint", 1.0, -6.0)
	var tween := create_tween()
	tween.tween_interval(1.0)
	tween.tween_property(_checkpoint_label, "modulate:a", 0.0, 0.5)


## Swaps the item-slot glyph. An empty id draws the dimmed placeholder square
## so the slot still reads as a slot when the player is carrying nothing.
func _set_item_icon(icon_id: String) -> void:
	if _item_icon == null:
		return
	var svg := String(ITEM_ICONS.get(icon_id, ""))
	if svg.is_empty():
		_item_icon.texture = UITheme.make_icon(EMPTY_SLOT_SVG, 1.0)
		_item_icon.modulate = ITEM_ICON_EMPTY
		return
	_item_icon.texture = UITheme.make_icon(svg, 1.0)
	_item_icon.modulate = Color.WHITE

