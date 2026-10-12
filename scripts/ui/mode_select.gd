extends Control

const UtilityArt := preload("res://scripts/ui/utility_reference_art.gd")
## Mode → course → difficulty setup flow, then starts the race.
##
## Built in the shared menu language established by results.gd and main_menu.gd:
## eyebrow → headline → accent rule, radius-18 cards whose captions are a small
## accent tick plus uppercase letter-spaced text, values in the display font
## over quiet uppercase captions, exactly one promoted action in solid glacier
## blue, and a staggered non-blocking entrance.
##
## The three steps share a progress rail so the screen reads as one setup flow
## rather than three unrelated lists, and every step surfaces the record that
## makes the choice mean something (course PBs, cup finishes, endless best).

## --- Mode glyphs ------------------------------------------------------------

const ICON_QUICK_RACE: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M36 4 L14 36 L28 36 L24 60 L50 26 L34 26 Z" fill="#ffd94d" stroke="#c98f1b" stroke-width="2" stroke-linejoin="round"/>
</svg>"""

const ICON_GRAND_PRIX: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M17 12 C7 12 7 28 19 29" stroke="#f5c542" stroke-width="4" fill="none"/>
<path d="M47 12 C57 12 57 28 45 29" stroke="#f5c542" stroke-width="4" fill="none"/>
<path d="M18 8 H46 V22 C46 34 40 40 32 40 C24 40 18 34 18 22 Z" fill="#f5c542" stroke="#c98f1b" stroke-width="2"/>
<rect x="28" y="40" width="8" height="8" fill="#e0b030"/>
<rect x="20" y="48" width="24" height="7" rx="2" fill="#c98f1b"/>
<path d="M24 14 L27 22 L24 30" stroke="#fff2c0" stroke-width="3" fill="none" opacity="0.8"/>
</svg>"""

const ICON_ENDLESS: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M4 56 L24 16 L38 40 L46 26 L60 56 Z" fill="#7fb4d8" stroke="#3d6d94" stroke-width="2" stroke-linejoin="round"/>
<path d="M24 16 L30 28 L27 27 L24 33 L20 27 L18 28 Z" fill="#f2f8ff"/>
<path d="M46 26 L51 36 L48 34 L46 39 L43 34 L41 36 Z" fill="#f2f8ff"/>
<path d="M24 16 V4 L34 8 L24 12" fill="#ff6b57" stroke="#b23a2b" stroke-width="1.5"/>
</svg>"""

const ICON_TIME_TRIAL: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<rect x="27" y="4" width="10" height="7" rx="2" fill="#3d6d94"/>
<path d="M44 14 L50 20" stroke="#3d6d94" stroke-width="4" stroke-linecap="round"/>
<circle cx="32" cy="37" r="21" fill="#9adcf8" stroke="#2b6f9e" stroke-width="3"/>
<circle cx="32" cy="37" r="15" fill="#d7f1fd"/>
<path d="M32 37 L32 25" stroke="#0e2036" stroke-width="4" stroke-linecap="round"/>
<path d="M32 37 L41 42" stroke="#0e2036" stroke-width="3" stroke-linecap="round"/>
<circle cx="32" cy="37" r="2.4" fill="#f5c542"/>
</svg>"""

## --- Course posters ---------------------------------------------------------
##
## All five race courses use authored runtime textures and center-cover inside
## both the landscape tile and narrow portrait row. Waddle School is registered
## here for shared poster QA without changing the five-course race selection.

const COURSE_POSTER_PATHS: Dictionary = {
	"aurora": "res://assets/art/ui/course_posters/aurora_ascent_wave1.png",
	"cinder": "res://assets/art/ui/course_posters/cinder_coast_wave2.png",
	"glacier": "res://assets/art/ui/course_posters/glacier_gauntlet_wave1.png",
	"hollow": "res://assets/art/ui/course_posters/sapphire_hollow_wave2.png",
	"iceberg": "res://assets/art/ui/course_posters/iceberg_bay_wave2.png",
	"tutorial": "res://assets/art/ui/course_posters/waddle_school_wave1.png",
}
const COURSE_POSTER_TEXTURES: Dictionary = {
	"aurora": preload("res://assets/art/ui/course_posters/aurora_ascent_wave1.png"),
	"cinder": preload("res://assets/art/ui/course_posters/cinder_coast_wave2.png"),
	"glacier": preload("res://assets/art/ui/course_posters/glacier_gauntlet_wave1.png"),
	"hollow": preload("res://assets/art/ui/course_posters/sapphire_hollow_wave2.png"),
	"iceberg": preload("res://assets/art/ui/course_posters/iceberg_bay_wave2.png"),
	"tutorial": preload("res://assets/art/ui/course_posters/waddle_school_wave1.png"),
}

## Most course posters in one landscape row before the grid wraps.
const COURSE_COLUMNS_MAX: int = 3

const DIFFICULTY_COLORS: Dictionary = {
	"chill": "#7fe08f",
	"competitive": "#f5c542",
	"emperor": "#ff6b57",
}

const DIFFICULTY_TINTS: Dictionary = {
	"chill": Color(0.498, 0.878, 0.561),
	"competitive": Color(0.961, 0.773, 0.259),
	"emperor": Color(1.0, 0.42, 0.34),
}

## One-line pitch for each difficulty beyond DifficultyDB's flavour text.
const DIFFICULTY_PITCH: Dictionary = {
	"chill": "Learn the lines. Rivals hold back and mistakes cost little.",
	"competitive": "The intended race. Rivals take shortcuts and use items on you.",
	"emperor": "Near-perfect rivals at full pace. Every corner has to be clean.",
}

## Corner language, shared with results.gd: cards are soft, rows are tighter.
const RADIUS_CARD: int = 18
## Floor for a phone card that has sized itself to its content, so a short
## card still reads as a card and stays a comfortable thumb target.
const CARD_MIN_HEIGHT: float = 120.0
const RADIUS_ROW: int = 10

## Promoted-action face, matching the main menu's Play hero and results' Race
## Again so "the button you probably want" looks identical everywhere.
const PRIMARY_FILL: Color = Color(0.129, 0.361, 0.588)
const PRIMARY_FILL_HOVER: Color = Color(0.192, 0.478, 0.741)

## Authored width of the setup column on the 1920x1080 desktop canvas.
const COLUMN_BASE: float = 1080.0

var _step: String = "mode"  # mode | course | difficulty
var _chosen_mode: Game.Mode = Game.Mode.QUICK_RACE
var _chosen_course: String = "glacier"
var _content: VBoxContainer
## Pinned bottom bar holding the step's Back button, outside the scroll.
var _footer: MarginContainer = null
var _scroll: ScrollContainer = null
var _buttons: Array[Button] = []
var _card_width: float = COLUMN_BASE
## Extra enlargement for tall/narrow (portrait) viewports — see _tall_boost().
var _boost: float = 1.0
## Shared viewport contract (class, safe insets, safe rect). Resolved once per
## build so every step measures against the same rectangle.
var _profile: LayoutProfile = null
## Gradient under the pinned footer. Held so a rotation can re-measure it.
var _scrim: TextureRect = null
var _mode_hero: Control = null
const MODE_REFERENCE := "res://assets/art/ui/menu/race_mode_reference_v1.png"
const MODE_PANELS := {
	"Quick Race": Rect2(57, 823, 326, 147),
	"Grand Prix": Rect2(57, 1018, 328, 149),
	"Time Trial": Rect2(57, 1212, 330, 151),
	"Endless Expedition": Rect2(56, 1409, 389, 152),
}
## Rasterized SVG cache: menu steps rebuild on every navigation and a phone
## rasterizing the same poster three times is pure jank.
static var _icon_cache: Dictionary = {}


func _ready() -> void:
	UtilityArt.bind_background(self, "res://assets/art/ui/menu/race_setup_background_v1.webp", "res://assets/art/ui/menu/race_setup_background_landscape_v3.webp")
	UITheme.apply_ui_scale(self)
	_profile = LayoutProfile.for_viewport(get_viewport())
	_boost = _tall_boost()
	_card_width = _measure_card_width()
	# The gallery outgrows a short landscape phone, so the step lives in a
	# scroll wrapper; while it fits, the expanding CenterContainer keeps the
	# desktop composition perfectly centered.
	_scroll = ScrollContainer.new()
	# Rows are buttons, which swallow touch drags before the ScrollContainer
	# can see them; this restores dragging the list on a phone.
	TouchScroll.attach(_scroll)
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	# A phone cannot fit four mode cards, so the step scrolls -- and with the
	# default invisible scrollbar the fold landed on a card boundary and the
	# list read as finished. The shared slim bar is the only signal that a
	# fourth mode exists. Same treatment as settings, controls and credits.
	UtilityScreenLayout.style_scrollbar(_scroll)
	add_child(_scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(center)
	_content = VBoxContainer.new()
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(_content)

	# Back lives OUTSIDE the scroll, pinned to the bottom.
	#
	# It used to be the last child of the scrolling column, which is fine on a
	# desktop where the whole step fits on screen. On a portrait phone the
	# course gallery is five stacked cards tall, so Back sat a full screen below
	# the fold -- reported, accurately, as there being no way back at all. A
	# footer cannot go below the fold.
	_footer = MarginContainer.new()
	_footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_footer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_footer.mouse_filter = Control.MOUSE_FILTER_PASS
	# Scrim under the footer so cards scrolling beneath it fade out rather than
	# running into the button. Without it the Back control reads as an unrelated
	# thing dropped on top of the list.
	_scrim = TextureRect.new()
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(0.02, 0.04, 0.09, 0.0), Color(0.02, 0.04, 0.09, 0.92)])
	fade.offsets = PackedFloat32Array([0.0, 1.0])
	var fade_tex := GradientTexture2D.new()
	fade_tex.gradient = fade
	fade_tex.fill_from = Vector2(0.0, 0.0)
	fade_tex.fill_to = Vector2(0.0, 1.0)
	_scrim.texture = fade_tex
	_scrim.stretch_mode = TextureRect.STRETCH_SCALE
	_scrim.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_scrim.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scrim)
	add_child(_footer)
	_apply_frame()
	# Normally the top of the flow, but a caller can send the player straight to
	# a later step -- "Change Course" from a pause menu or the results screen
	# opens here rather than walking mode/course/difficulty again.
	match Game.take_setup_entry_step():
		"course":
			_chosen_mode = Game.mode
			_show_course_step()
		"difficulty":
			_chosen_mode = Game.mode
			_chosen_course = Game.course_id
			_show_difficulty_step()
		_:
			_show_mode_step()
	UITheme.attach_swipe_back(self, _go_back_step)
	# Portrait is a supported orientation (see RotateOverlay), so a player can
	# turn the phone mid-flow. Every metric here -- column width, grid columns,
	# the safe-area gutters -- is measured once at build time, so without this
	# a rotation left a landscape-width column inside a portrait canvas: the
	# exact "cards run off the edge and nothing scrolls sideways" defect, just
	# reached by turning the device instead of opening the screen.
	UtilityScreenLayout.bind_view_class(self, _reflow)


## Re-measures and rebuilds the current step for a new layout class. Only fires
## when the class actually changes, so a resize burst costs one rebuild.
func _reflow(profile: LayoutProfile) -> void:
	_profile = profile
	_boost = _tall_boost()
	_card_width = _measure_card_width()
	_apply_frame()
	match _step:
		"course":
			_show_course_step()
		"difficulty":
			_show_difficulty_step()
		_:
			_show_mode_step()


## Safe-area gutters, footer band and column width, in one place so _ready and
## a rotation cannot drift apart.
func _apply_frame() -> void:
	var profile := _layout()
	if _step == "mode":
		var safe := profile.safe_rect
		_scroll.offset_left = safe.position.x + safe.size.x * (0.04 if _is_portrait() else 0.515)
		_scroll.offset_top = safe.position.y + safe.size.y * (0.48 if _is_portrait() else 0.065)
		_scroll.offset_right = -(profile.safe_insets.z + safe.size.x * 0.03)
		_scroll.offset_bottom = -(profile.safe_insets.w + safe.size.y * 0.03)
		_card_width = safe.size.x * (0.92 if _is_portrait() else 0.455)
		_content.custom_minimum_size.x = _card_width
		_content.add_theme_constant_override("separation", 0)
		_footer.hide()
		_scrim.hide()
		return
	_footer.show()
	_scrim.show()
	_scroll.offset_left = profile.safe_insets.x
	_scroll.offset_top = profile.safe_insets.y
	_scroll.offset_right = -profile.safe_insets.z
	# Footer owns this band. Content never renders under Back, even before the
	# final spacer reaches the viewport during a portrait course scroll.
	_scroll.offset_bottom = -(profile.safe_insets.w + _u(92.0))
	_content.custom_minimum_size.x = _card_width
	_content.add_theme_constant_override("separation", _gap(UITheme.SPACE_S))
	_footer.add_theme_constant_override("margin_bottom",
		roundi(profile.safe_insets.w) + _gap(UITheme.SPACE_S))
	_footer.add_theme_constant_override("margin_left",
		roundi(profile.safe_insets.x) + UITheme.screen_margin())
	_footer.add_theme_constant_override("margin_right",
		roundi(profile.safe_insets.z) + UITheme.screen_margin())
	# Tall enough to actually be a fade. A strip only as tall as the button
	# reads as a hard edge rather than content receding under a bar.
	_scrim.offset_top = -(_u(52.0) * 2.6 + float(_gap(UITheme.SPACE_L)))


## --- Layout scaling ---------------------------------------------------------
##
## The canvas_items/expand stretch pins the design width, so a portrait window
## keeps 1920 logical units across but gains logical height — every logical
## pixel then renders physically tiny and the screen shrinks into an island.
## Enlarge by the ratio of live to design height, on top of UITheme's touch
## step, exactly as main_menu.gd and results.gd do.
func _tall_boost() -> float:
	if GameConfig.is_headless() or not is_inside_tree():
		return 1.0
	var view_height := get_viewport_rect().size.y
	if view_height <= 0.0:
		return 1.0
	var design_height := 1080.0
	var window := get_window()
	if window != null and window.content_scale_size.y > 0:
		design_height = float(window.content_scale_size.y)
	return clampf(view_height / design_height, 1.0, 1.85)


## Authored font size -> on-screen size (touch step, then the tall step).
func _f(size: int) -> int:
	return maxi(1, roundi(float(UITheme.scaled_font(size)) * _boost))


## Authored horizontal metric -> on-screen metric.
func _u(value: float) -> float:
	return UITheme.scaled(value) * _boost


## Authored spacing step -> on-screen separation.
func _gap(value: int) -> int:
	return maxi(1, roundi(float(UITheme.spacing(value)) * _boost))


## Shared viewport contract, resolved lazily so helpers called before _ready
## (or from a test harness) still get a sane rectangle.
##
## Deliberately NOT gated on GameConfig.is_headless(). The gate used to live in
## every measuring helper here, which meant a headless run measured the screen
## as if it were a 1920-wide desktop no matter what viewport it was actually
## given -- so the automated mobile audit built the two-column desktop grid
## inside an 800-unit phone canvas and could not see the overflow a player
## sees. Geometry comes from the viewport; the display server has no opinion
## about it.
func _layout() -> LayoutProfile:
	if _profile == null:
		_profile = LayoutProfile.for_viewport(get_viewport()) if is_inside_tree() \
			else LayoutProfile.for_view_size(Vector2(1920.0, 1080.0))
	return _profile


## True for tall/narrow viewports, where galleries stack into single-file rows.
func _is_portrait() -> bool:
	return _layout().is_portrait()


## Width of the setup column: the authored width on desktop landscape, the
## touch content band on phones, and most of the safe rect on any portrait
## viewport.
##
## The final clamp is the load-bearing part. The step lives in a
## ScrollContainer with horizontal scrolling DISABLED, so a column even one
## unit wider than the safe rect is not "a bit tight" -- it is a card the
## player's thumb can never reach, because nothing can scroll sideways to it.
func _measure_card_width() -> float:
	var profile := _layout()
	var usable := maxf(profile.safe_rect.size.x, 1.0)
	var want := COLUMN_BASE
	if UITheme.is_touch():
		want = UITheme.content_width(COLUMN_BASE, self)
	elif profile.is_portrait():
		# Portrait desktop/test window: fill it rather than float a 1080-wide
		# desktop column in a canvas that is 800 across.
		want = usable * 0.90
	else:
		want = minf(COLUMN_BASE * _boost, profile.viewport_size.x * 0.78)
	return clampf(want, 1.0, usable)


## --- Shared building blocks -------------------------------------------------

## Small uppercase, letter-spaced context line above the headline. Sets the
## typographic hierarchy: tiny eyebrow, large headline, quiet captions.
func _eyebrow(parent: Control, text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_override("font", UITheme.display_font())
	label.add_theme_font_size_override("font_size", _f(19))
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


## Hero block: eyebrow, headline, accent rule — the same opening every other
## redesigned screen uses.
func _hero(eyebrow: String, headline: String) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", _gap(6))
	_content.add_child(box)
	if _step == "mode":
		box.queue_free()
		var safe := _profile.safe_rect
		_mode_hero = Control.new()
		_mode_hero.name = "RaceReferenceHero"
		_mode_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_mode_hero)
		var logo := TextureRect.new()
		logo.name = "WaddleRaceWordmark"
		var title_crop := AtlasTexture.new()
		title_crop.atlas = ExpeditionMenuStyle._material_texture("res://assets/art/ui/menu/race_wordmark_v4.webp")
		title_crop.region = Rect2(20,20,1734,847)
		title_crop.filter_clip = true
		logo.texture = title_crop
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var width := safe.size.x * (0.72 if _is_portrait() else 0.42)
		logo.position = safe.position + Vector2(safe.size.x * (0.14 if _is_portrait() else 0.085), safe.size.y * (0.055 if _is_portrait() else 0.10))
		logo.size = Vector2(width, width * 0.50)
		_mode_hero.add_child(logo)
		var plaque := TextureRect.new()
		plaque.name = "ChooseModeWoodPlaque"
		plaque.texture = _mode_region(Rect2(275, 408, 407, 94))
		plaque.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		plaque.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plaque.accessibility_name = headline
		plaque.size = Vector2(width * 0.62, width * 0.143)
		plaque.position = logo.position + Vector2(width * (0.19 if _is_portrait() else 0.19), logo.size.y - width * 0.02)
		_mode_hero.add_child(plaque)
		var flag_penguin := TextureRect.new()
		flag_penguin.name = "RaceFlagPenguin"
		flag_penguin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		flag_penguin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		flag_penguin.texture = ExpeditionMenuStyle._material_texture("res://assets/art/ui/menu/race_flag_penguin_v1.webp")
		flag_penguin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flag_penguin.size = Vector2(safe.size.x * (0.50 if _is_portrait() else 0.33), safe.size.y * (0.40 if _is_portrait() else 0.59))
		flag_penguin.position = safe.position + Vector2(safe.size.x * -0.055, safe.size.y * (0.11 if _is_portrait() else 0.32))
		_mode_hero.add_child(flag_penguin)
		var back := ExpeditionMenuStyle.button("BASE CAMP", false, maxi(24, roundi(safe.size.y * (0.018 if _is_portrait() else 0.034))), safe.size.y * 0.055)
		back.name = "RaceSetupBack"
		back.position = safe.position + Vector2(safe.size.x * 0.035, safe.size.y * 0.018)
		back.size = Vector2(safe.size.x * (0.29 if _is_portrait() else 0.17), safe.size.y * 0.055)
		back.icon = ExpeditionMenuStyle.wardrobe_sprite("back")
		back.expand_icon = true
		back.add_theme_constant_override("icon_max_width", roundi(back.size.y * 0.65))
		back.pressed.connect(_go_back_step)
		_mode_hero.add_child(back)
		return
	_eyebrow(box, eyebrow, Color(UITheme.COLOR_ACCENT, 0.75))
	var label := UITheme.heading(
		headline, roundi(float(UITheme.scaled_heading(52)) * _boost))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	box.add_child(UITheme.accent_rule(_u(200.0), UITheme.COLOR_ACCENT))


## Uppercase, letter-spaced caption. The workhorse label of the screen: every
## metadata line, meter name and stat caption is one of these.
func _caption(parent: Control, text: String, size: int, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_override("font", UITheme.display_font())
	label.add_theme_font_size_override("font_size", _f(size))
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


## Value label: display font, the thing the eye should land on inside a tile.
func _value(parent: Control, text: String, size: int, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UITheme.display_font())
	label.add_theme_font_size_override("font_size", _f(size))
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


## Body copy inside a card: quiet, wrapping, never more than `lines` deep.
func _body_text(parent: Control, text: String, size: int, lines: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", _f(size))
	label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.max_lines_visible = lines
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


## Small glass stat tile: value in the display font over a quiet uppercase
## caption. Identical read to the results stat strip.
func _stat_tile(parent: Control, value: String, caption: String, tint: Color,
		highlight: bool) -> PanelContainer:
	var tile := PanelContainer.new()
	var style := ExpeditionMenuStyle.surface(
		Color("fff0d8") if highlight else ExpeditionMenuStyle.IVORY,
		RADIUS_ROW)
	style.set_corner_radius_all(RADIUS_ROW)
	style.content_margin_left = _u(13.0)
	style.content_margin_right = _u(13.0)
	style.content_margin_top = _u(5.0)
	style.content_margin_bottom = _u(5.0)
	style.shadow_size = 4
	tile.add_theme_stylebox_override("panel", style)
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(tile)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(stack)
	_value(stack, value, 26, tint if highlight else UITheme.COLOR_TEXT)
	_caption(stack, caption, 13, UITheme.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	return tile


## Card shell: one radius, one border language, one padding rhythm — and it is
## a real focusable Button, because every card on this screen is a choice.
## Returns the inert full-rect content host for the caller to fill.
## Sizes a grid of cards to what they actually hold.
##
## A card's contents sit in a MarginContainer anchored to the button's full
## rect, which means they never reach the button's own minimum size: the
## height is whatever constant was authored, and the button clips. Both ends
## of that hurt on a phone. The Endless card wanted 394 units and was given
## 346, so its description was quietly cut off; the difficulty cards wanted
## 359 and were given 473, leaving a quarter of every card empty between the
## pitch and the pip meters.
##
## In a multi-column grid the cards share a row, so they take one shared
## height -- the tallest card's content, never less than the authored value.
## In the single-column phone layout nothing sits beside them, so each card
## takes its own height and the empty band disappears.
##
## Runs as a coroutine: label minimum sizes are only final once the grid has
## handed out its column width, which takes a layout pass.
func _fit_cards(grid: GridContainer, columns: int, authored: float) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(grid):
		return
	var cards: Array[Button] = []
	var wanted: Array[float] = []
	for child: Node in grid.get_children():
		var button := child as Button
		if button == null:
			continue
		var content := 0.0
		for inner: Node in button.get_children():
			var host := inner as Control
			if host != null:
				content = maxf(content, host.get_combined_minimum_size().y)
		if content <= 0.0:
			continue
		cards.append(button)
		wanted.append(content)
	if cards.is_empty():
		return
	if columns > 1:
		var tallest := authored
		for height: float in wanted:
			tallest = maxf(tallest, height)
		for button: Button in cards:
			button.custom_minimum_size.y = tallest
		return
	for i: int in cards.size():
		cards[i].custom_minimum_size.y = maxf(wanted[i], CARD_MIN_HEIGHT)


func _make_card(parent: Control, min_size: Vector2, action: Callable,
		primary: bool = false, pad: float = 18.0) -> MarginContainer:
	var button := Button.new()
	button.set_meta("premium_primary", primary)
	button.custom_minimum_size = min_size
	# Backstop for the same class of bug: whatever a future child does with its
	# minimum size, a card cannot paint outside its own rounded rect.
	button.clip_contents = true
	button.focus_mode = Control.FOCUS_ALL
	ExpeditionMenuStyle.style_button(button, primary, _f(24))
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color(0.72, 0.92, 1.0)
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(RADIUS_CARD)
	focus.set_expand_margin_all(3.0)
	button.add_theme_stylebox_override("focus", focus)
	UITheme.attach_hover_scale(button, 1.015)
	UITheme.attach_hover_glow(button)
	UITheme.hook_sounds(button)
	button.pressed.connect(action)
	parent.add_child(button)
	_buttons.append(button)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inset := roundi(_u(pad))
	margin.add_theme_constant_override("margin_left", inset)
	margin.add_theme_constant_override("margin_right", inset)
	margin.add_theme_constant_override("margin_top", inset)
	margin.add_theme_constant_override("margin_bottom", inset)
	button.add_child(margin)
	return margin


static func _card_style(bg: Color, border: Color, width: int, shadow: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(RADIUS_CARD)
	box.content_margin_left = 0.0
	box.content_margin_right = 0.0
	box.content_margin_top = 0.0
	box.content_margin_bottom = 0.0
	box.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	box.shadow_size = shadow
	box.shadow_offset = Vector2(0.0, 5.0)
	return box


## Rounded tinted plate holding a mode glyph, so every mode card opens with the
## same square rather than a loose floating icon.
func _icon_plate(parent: Control, svg: String, tint: Color, side: float) -> void:
	var plate := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(tint.r, tint.g, tint.b, 0.16)
	style.border_color = Color(tint, 0.42)
	style.set_border_width_all(1)
	style.set_corner_radius_all(RADIUS_ROW + 2)
	var pad := side * 0.18
	style.content_margin_left = pad
	style.content_margin_right = pad
	style.content_margin_top = pad
	style.content_margin_bottom = pad
	plate.add_theme_stylebox_override("panel", style)
	plate.custom_minimum_size = Vector2(side, side)
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(plate)
	var texture := _cached_icon(svg)
	if texture == null:
		return
	var icon := TextureRect.new()
	icon.texture = texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(icon)


## Rasterize-once cache in front of UITheme.make_icon: steps rebuild on every
## navigation and the posters are the most expensive glyphs on the screen.
static func _cached_icon(svg: String) -> ImageTexture:
	if _icon_cache.has(svg):
		return _icon_cache[svg] as ImageTexture
	var texture := UITheme.make_icon(svg, 2.0)
	_icon_cache[svg] = texture
	return texture


## --- Progress rail ----------------------------------------------------------

## Steps of the flow for the mode currently chosen. Endless never reaches the
## rail (it launches straight from its card).
func _rail_steps() -> Array[String]:
	if _step == "mode":
		return ["Mode", "Course", "Difficulty"]
	match _chosen_mode:
		Game.Mode.GRAND_PRIX:
			return ["Mode", "Difficulty"]
		Game.Mode.TIME_TRIAL:
			return ["Mode", "Course"]
		_:
			return ["Mode", "Course", "Difficulty"]


func _mode_name(mode: Game.Mode) -> String:
	match mode:
		Game.Mode.GRAND_PRIX:
			return "Grand Prix"
		Game.Mode.TIME_TRIAL:
			return "Time Trial"
		Game.Mode.ENDLESS:
			return "Endless"
		_:
			return "Quick Race"


## Breadcrumb of pills: settled steps carry the value chosen, the live step is
## rimmed in accent, later steps sit dim. Makes a three-screen flow read as one.
func _build_rail() -> void:
	var steps := _rail_steps()
	var current := 0
	match _step:
		"course":
			current = 1
		"difficulty":
			current = steps.size() - 1
	var values := {"Mode": _mode_name(_chosen_mode), "Course": CoursesDB.display_name(_chosen_course)}
	# Flow, not a fixed row: three pills plus their separators want 794 logical
	# units, and a portrait phone's canvas is 800 wide before margins, so the
	# last pill was clipped against the screen edge. Wrapping to a second line
	# costs nothing and keeps every step readable.
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", _gap(8))
	row.add_theme_constant_override("v_separation", _gap(6))
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	_content.add_child(row)
	for i: int in steps.size():
		if i > 0:
			var sep := Label.new()
			sep.text = "›"
			sep.add_theme_font_override("font", UITheme.display_font())
			sep.add_theme_font_size_override("font_size", _f(20))
			sep.add_theme_color_override("font_color", Color(0.55, 0.68, 0.82, 0.7))
			sep.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(sep)
		_rail_pill(row, String(steps[i]), String(values.get(steps[i], "")), i, current,
			_rail_jump(String(steps[i])))


## Where a completed rail pill goes when pressed, or an empty Callable when it
## is not a step you can return to.
##
## The rail reads as a breadcrumb and was drawn as one, but every pill was
## MOUSE_FILTER_IGNORE -- pressing "COURSE" to go back and change your mind did
## nothing at all, which is the single most obvious thing to try.
func _rail_jump(step_name: String) -> Callable:
	match step_name:
		"Mode":
			return _show_mode_step
		"Course":
			return _show_course_step
	return Callable()


func _rail_pill(parent: Control, name_text: String, value_text: String,
		index: int, current: int, jump: Callable = Callable()) -> void:
	var done := index < current
	var live := index == current
	var can_jump := done and jump.is_valid()
	var pill := PanelContainer.new()
	pill.set_meta("premium_primary", live)
	var style := StyleBoxFlat.new()
	if live:
		style.bg_color = ExpeditionMenuStyle.CORAL
		style.border_color = ExpeditionMenuStyle.GOLD
	elif done:
		style.bg_color = ExpeditionMenuStyle.IVORY
		style.border_color = ExpeditionMenuStyle.GOLD
	else:
		style.bg_color = Color("edf5f8")
		style.border_color = Color("d4e6ee")
	style.set_border_width_all(1)
	style.set_corner_radius_all(roundi(_u(16.0)))
	style.content_margin_left = _u(16.0)
	style.content_margin_right = _u(16.0)
	style.content_margin_top = _u(5.0)
	style.content_margin_bottom = _u(5.0)
	if can_jump:
		# A pill you can press has to look like one, or it is just as invisible
		# as it was when it did nothing.
		style.border_color = Color(UITheme.COLOR_ACCENT, 0.45)
	pill.add_theme_stylebox_override("panel", style)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(pill)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(stack)
	if can_jump:
		# A transparent button over the whole pill: the pill's own art stays as
		# authored (two stacked labels, which no Button can lay out), and the
		# button supplies hit-testing, focus, hover and the click sound.
		var hit := Button.new()
		hit.flat = true
		hit.set_anchors_preset(Control.PRESET_FULL_RECT)
		hit.focus_mode = Control.FOCUS_ALL
		hit.tooltip_text = "Change %s" % name_text.to_lower()
		UITheme.hook_sounds(hit)
		hit.pressed.connect(jump)
		pill.add_child(hit)
		# Deliberately NOT added to _buttons: the rail is built before the step's
		# own cards, so registering it would make _focus_first() land on a
		# breadcrumb instead of the first course. Godot's directional focus still
		# reaches it.
	if done and not value_text.is_empty():
		_caption(stack, name_text, 12, Color(0.55, 0.68, 0.82), HORIZONTAL_ALIGNMENT_CENTER)
		var value := Label.new()
		value.text = value_text
		value.add_theme_font_override("font", UITheme.bold_font())
		value.add_theme_font_size_override("font_size", _f(17))
		value.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(value)
		return
	var tint := UITheme.COLOR_ACCENT if live else Color(0.48, 0.58, 0.70)
	_caption(stack, "%d · %s" % [index + 1, name_text], 15, tint, HORIZONTAL_ALIGNMENT_CENTER)


## --- Step 1: mode -----------------------------------------------------------

func _show_mode_step() -> void:
	_step = "mode"
	_clear()
	_apply_frame()
	_hero("WADDLE RACE", "CHOOSE A MODE")

	var grid := GridContainer.new()
	grid.columns = 1
	grid.add_theme_constant_override("h_separation", _gap(14))
	grid.add_theme_constant_override("v_separation", roundi(_profile.safe_rect.size.y * 0.009))
	_content.add_child(grid)
	var tile := _mode_tile_size(grid.columns)

	var best_time := _best_time_any()
	var cup := _best_cup()
	_mode_card(grid, tile, "Quick Race", ICON_QUICK_RACE, UITheme.COLOR_ACCENT,
		"Straight to the grid. Pick a course, pick your rivals, settle it in one race.",
		"1 race · 8 racers · items on", "", "", true,
		func() -> void:
			_chosen_mode = Game.Mode.QUICK_RACE
			_show_course_step())
	_mode_card(grid, tile, "Grand Prix", ICON_GRAND_PRIX, UITheme.COLOR_GOLD,
		"All three courses back to back. Points carry over; the cup goes to the total.",
		"3 races · points · one cup",
		cup, "best cup" if not cup.is_empty() else "", false,
		func() -> void:
			_chosen_mode = Game.Mode.GRAND_PRIX
			_show_difficulty_step())
	_mode_card(grid, tile, "Time Trial", ICON_TIME_TRIAL, Color(0.55, 0.85, 0.98),
		"No rivals, no items. Just you and the ghost of your best run.",
		"solo · ghost · no items",
		RaceHUD.format_time(best_time) if best_time > 0.0 else "",
		"best lap" if best_time > 0.0 else "", false,
		func() -> void:
			_chosen_mode = Game.Mode.TIME_TRIAL
			_show_course_step())
	var endless_best := Progression.endless_high_score()
	_mode_card(grid, tile, "Endless Expedition", ICON_ENDLESS, Color(1.0, 0.55, 0.45),
		"One improvised run. The storm never slows — you just last longer.",
		"survival · rising speed",
		_fmt_int(endless_best) if endless_best > 0 else "",
		"best score" if endless_best > 0 else "", false,
		func() -> void:
			Game.start_endless())
	# Four fixed reference rows occupy the visible selection area.
	_buttons.append(_mode_hero.find_child("RaceSetupBack", true, false) as Button)
	_focus_first()
	_play_entrance()


## Card footprint for the mode grid. Height is authored per orientation, not
## shared, because the single-column card carries strictly more text than the
## two-column one: the record leaves the right-hand stat tile and becomes an
## extra line under the metadata (see _mode_card), and the longest mode name --
## "Endless Expedition" -- no longer fits one line beside the icon plate.
## Measured on a 390x844 phone (canvas 800x1731, card 662 wide): content came
## to 307 units against a 271-unit card, and _make_card clips, so the blurb and
## the record were sliced off the bottom of three of the four cards.
func _mode_tile_size(_columns: int) -> Vector2:
	return Vector2(_card_width, _profile.safe_rect.size.y * (0.112 if _is_portrait() else 0.22))


func _mode_region(region: Rect2) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = ExpeditionMenuStyle._material_texture(MODE_REFERENCE)
	atlas.region = region
	atlas.filter_clip = true
	return atlas


func _mode_card(parent: Control, tile: Vector2, title: String, _icon_svg: String,
		_tint: Color, blurb: String, meta: String, stat_value: String,
		stat_caption: String, _primary: bool, action: Callable) -> void:
	var host := _make_card(parent, tile, action, false, 10.0)
	var button := host.get_parent() as Button
	button.name = "RaceMode_" + title.to_pascal_case()
	button.accessibility_name = title
	button.tooltip_text = "%s\n%s" % [blurb, meta]
	if not stat_value.is_empty(): button.tooltip_text += "\n%s: %s" % [stat_caption, stat_value]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(tile.x * 0.025))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(row)
	var illustration := TextureRect.new()
	illustration.name = "ModeIllustration_" + title.to_pascal_case()
	illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	illustration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	illustration.texture = _mode_region(MODE_PANELS[title])
	var mask := Shader.new()
	mask.code = "shader_type canvas_item; uniform vec2 extent=vec2(300.0,150.0); varying vec2 local; void vertex(){local=VERTEX;} void fragment(){ vec4 ink=texture(TEXTURE,UV); vec2 p=local/max(extent.y,1.0); float edge=length(p-vec2(0.5,0.5))-0.5; float left=1.0-smoothstep(-0.012,0.012,edge); if(p.x>0.5) left=1.0; ink.a*=left*(1.0-smoothstep(0.87,1.0,local.x/max(extent.x,1.0))); COLOR=ink; }"
	var material := ShaderMaterial.new()
	material.shader = mask
	material.set_shader_parameter("extent", Vector2(tile.x * 0.34, tile.y - _u(20)))
	illustration.resized.connect(func() -> void: material.set_shader_parameter("extent", illustration.size))
	illustration.material = material
	var frame := MarginContainer.new()
	frame.custom_minimum_size.x = tile.x * 0.37
	frame.add_theme_constant_override("margin_top", roundi(tile.y * 0.06))
	frame.add_theme_constant_override("margin_bottom", roundi(tile.y * 0.06))
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(illustration)
	illustration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(frame)
	var display_name := "ENDLESS\nEXPEDITION" if title == "Endless Expedition" else title.to_upper()
	var font := ExpeditionMenuStyle.display_font()
	var name_size := roundi(tile.x * 0.072)
	var name_width := tile.x * 0.63 - tile.y * 0.62 - 2.0 * roundi(tile.x * 0.025) - 2.0 * roundi(_u(10.0)) - 2.0
	# Reserve the illustration, arrow, gaps and card padding before choosing
	# type size. Never split a mode name mid-word or let it escape the card.
	for line: String in display_name.split("\n"):
		while name_size > 16 and font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x > name_width:
			name_size -= 1
	var label := ExpeditionMenuStyle.label(display_name, name_size, ExpeditionMenuStyle.INK)
	label.name = "ModeName_" + title.to_pascal_case()
	label.add_theme_font_override("font", font)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	var arrow := PanelContainer.new()
	arrow.custom_minimum_size = Vector2.ONE * tile.y * 0.62
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.set_meta("premium_primary", true)
	var face := ExpeditionMenuStyle.material_box(true, 0, 0)
	arrow.add_theme_stylebox_override("panel", face)
	row.add_child(arrow)
	var glyph := ExpeditionMenuStyle.label("›", roundi(tile.y * 0.44), Color.WHITE)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.add_child(glyph)


## Fastest personal best across every course — the headline number for the
## Time Trial card when the player has actually set one.
func _best_time_any() -> float:
	var best := 0.0
	for id: String in CoursesDB.ORDER:
		var time := Progression.best_time(id)
		if time > 0.0 and (best <= 0.0 or time < best):
			best = time
	return best


## Best cup finish across difficulties, e.g. "1st" — empty when never raced.
func _best_cup() -> String:
	var best := 99
	for id: String in DifficultyDB.ORDER:
		var record := Progression.gp_record(id)
		if record.is_empty():
			continue
		best = mini(best, int(record.get("placement", 99)))
	return "" if best > 8 else _ordinal(best)


## --- Step 2: course ---------------------------------------------------------

func _show_course_step() -> void:
	_step = "course"
	_clear()
	_hero(_mode_name(_chosen_mode), "Choose a Course")
	_build_rail()

	var portrait := _is_portrait()
	# Cap the row rather than stretching it: one column per course was fine at
	# three and turns the posters into slivers as the roster grows. Beyond the
	# cap the grid wraps to a second row.
	var columns := 1 if portrait else mini(CoursesDB.ORDER.size(), COURSE_COLUMNS_MAX)
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", _gap(14))
	grid.add_theme_constant_override("v_separation", _gap(14))
	_content.add_child(grid)
	var gaps := float(_gap(14)) * float(columns - 1)
	var width := (_card_width - gaps) / float(columns)
	for id: String in CoursesDB.ORDER:
		var course_id := id
		var pick := func() -> void:
			_chosen_course = course_id
			if _chosen_mode == Game.Mode.TIME_TRIAL:
				Game.start_time_trial(course_id)
			else:
				_show_difficulty_step()
		if portrait:
			# 148 was shorter than the row's own content (measured: card 262,
			# content 336), so the record tile's caption was clipped off the
			# bottom of every card.
			_course_row(grid, Vector2(width, _u(190.0)), course_id, pick)
		else:
			_course_tile(grid, Vector2(width, _u(330.0)), course_id, pick)
	_fit_cards(grid, columns, _u(190.0) if portrait else _u(330.0))

	_build_back_row("Back", _show_mode_step)
	_focus_first()
	_play_entrance()


## Framed authored plate. KEEP_ASPECT_COVERED deliberately center-crops: every
## production landmark was authored inside the central 55% safe region.
func _course_art(parent: Control, id: String, min_size: Vector2) -> Control:
	var frame := Control.new()
	frame.custom_minimum_size = min_size
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(frame)

	# Preloaded script dependencies are decoded by SceneRouter's threaded scene
	# load. Card construction only binds an existing texture; it never blocks the
	# first course screen on synchronous disk IO or PNG decode.
	var authored := COURSE_POSTER_TEXTURES.get(id) as Texture2D
	if authored == null:
		push_error("Missing authored course poster: %s" % id)
	else:
		var scene := TextureRect.new()
		scene.name = "CoursePoster_%s" % id.capitalize()
		scene.texture = authored
		scene.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		scene.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		scene.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		scene.set_anchors_preset(Control.PRESET_FULL_RECT)
		scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(scene)

	var rim := Panel.new()
	var rim_style := StyleBoxFlat.new()
	rim_style.draw_center = false
	rim_style.border_color = Color(0.86, 0.95, 1.0, 0.28)
	rim_style.set_border_width_all(1)
	rim.add_theme_stylebox_override("panel", rim_style)
	rim.set_anchors_preset(Control.PRESET_FULL_RECT)
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(rim)
	return frame


## Records line shared by both course layouts: personal best against par, so
## the number always has something to mean.
## `compact` drops to a single tile with the par time as its caption.
##
## Two side-by-side tiles have a minimum width the portrait row cannot afford.
## Measured on a 430x932 phone (logical 800 wide, column 647): the card's inner
## content demanded 720, the Button does not clip its children, and the whole
## gallery drew off the right edge with every course name and time cut in half.
## Poster 220 + two tiles 431 does not fit in 647 at any font size worth
## reading, so on a phone the row carries one number instead of two.
func _course_records(parent: Control, id: String, info: Dictionary, tint: Color,
		compact: bool = false) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _gap(8))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var best := Progression.best_time(id)
	var par := float(info.get("par_time", 0.0))
	if compact:
		var caption := "no record"
		if best > 0.0:
			caption = "your best"
		elif par > 0.0:
			caption = "par %s" % RaceHUD.format_time(par)
		var only := _stat_tile(row, RaceHUD.format_time(best) if best > 0.0 else "—",
			caption, tint, best > 0.0)
		only.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		return
	var tile := _stat_tile(row, RaceHUD.format_time(best) if best > 0.0 else "—",
		"your best" if best > 0.0 else "no record", tint, best > 0.0)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if par > 0.0:
		var par_tile := _stat_tile(row, RaceHUD.format_time(par), "par time", tint, false)
		par_tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _course_title(parent: Control, info: Dictionary, size: int) -> void:
	var label := Label.new()
	label.text = String(info.get("name", "Course"))
	label.add_theme_font_override("font", UITheme.display_font())
	label.add_theme_font_size_override("font_size", _f(size))
	label.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A Label with no wrap or clip reports its FULL text width as its minimum
	# size, and that minimum propagates up through the row, the card and the
	# grid. On a portrait phone "Glacier Gauntlet" at this size is wider than
	# the column, so the card grew past the screen edge and every course name
	# was cut off mid-word -- on the one screen whose entire job is telling you
	# which course is which.
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(label)


## Landscape gallery tile: poster on top, name, blurb, record strip beneath.
func _course_tile(parent: Control, tile: Vector2, id: String, action: Callable) -> void:
	var info := CoursesDB.get_item(id)
	var tint := info.get("theme_color", UITheme.COLOR_ACCENT) as Color
	var host := _make_card(parent, tile, action, false, 14.0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", _gap(8))
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(column)
	var art := _course_art(column, id, Vector2(0.0, tile.y * 0.42))
	art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_course_title(column, info, 25)
	var blurb := _body_text(column, String(info.get("desc", "")), 16, 2)
	blurb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_course_records(column, id, info, tint)


## Portrait row: poster on the left, name/blurb/records stacked to its right.
func _course_row(parent: Control, tile: Vector2, id: String, action: Callable) -> void:
	var info := CoursesDB.get_item(id)
	var tint := info.get("theme_color", UITheme.COLOR_ACCENT) as Color
	var host := _make_card(parent, tile, action, false, 14.0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _gap(14))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(row)
	# Explicit height: the poster sits directly in the row, so it has to carry
	# its own size rather than inherit one from a stretching column.
	# 0.34 left the name column too narrow to hold "Glacier Gauntlet" without
	# ellipsis, which is a poor trade on the screen whose job is naming courses.
	_course_art(row, id, Vector2(tile.x * 0.29, tile.y - _u(28.0)))
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", _gap(6))
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)
	_course_title(column, info, 25)
	# The portrait row is the full width of the screen; two lines cut every
	# course description short.
	var blurb := _body_text(column, String(info.get("desc", "")), 16, 3)
	blurb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_course_records(column, id, info, tint, true)


## --- Step 3: difficulty -----------------------------------------------------

func _show_difficulty_step() -> void:
	_step = "difficulty"
	_clear()
	var context := _mode_name(_chosen_mode)
	if _chosen_mode != Game.Mode.GRAND_PRIX:
		context += " · %s" % CoursesDB.display_name(_chosen_course)
	_hero(context, "Choose Your Rivals")
	_build_rail()

	var columns := 1 if _is_portrait() else DifficultyDB.ORDER.size()
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", _gap(14))
	grid.add_theme_constant_override("v_separation", _gap(14))
	_content.add_child(grid)
	var gaps := float(_gap(14)) * float(columns - 1)
	var width := (_card_width - gaps) / float(columns)
	for i: int in DifficultyDB.ORDER.size():
		var id := String(DifficultyDB.ORDER[i])
		var difficulty_id := id
		var pick := func() -> void:
			if _chosen_mode == Game.Mode.GRAND_PRIX:
				Game.start_grand_prix(difficulty_id)
			else:
				Game.start_quick_race(_chosen_course, difficulty_id)
		# Competitive is the intended way to play, so it takes the promoted face
		# rather than the first card in reading order.
		_difficulty_card(grid, Vector2(width, _u(268.0)), id, i + 1,
			id == "competitive", pick)
	_fit_cards(grid, columns, _u(268.0))

	_build_back_row("Back",
		_show_mode_step if _chosen_mode == Game.Mode.GRAND_PRIX else _show_course_step)
	_focus_first()
	_play_entrance()


func _difficulty_card(parent: Control, tile: Vector2, id: String, tier: int,
		primary: bool, action: Callable) -> void:
	var info := DifficultyDB.get_item(id)
	var tint := DIFFICULTY_TINTS.get(id, UITheme.COLOR_GOLD) as Color
	var host := _make_card(parent, tile, action, primary, 16.0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", _gap(6))
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", _gap(10))
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(head)
	_icon_plate(head, _difficulty_icon(id, tier), tint, _u(48.0))
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	titles.add_theme_constant_override("separation", 0)
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(titles)
	var name_label := Label.new()
	name_label.text = String(info.get("name", id))
	name_label.add_theme_font_override("font", UITheme.display_font())
	name_label.add_theme_font_size_override("font_size", _f(27))
	name_label.add_theme_color_override("font_color",
		Color(0.98, 0.995, 1.0) if primary else UITheme.COLOR_TEXT)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.add_child(name_label)
	# Wrap this one. Without a wrap mode a Label reports its FULL text width as
	# its minimum size, so this tagline made the card's content wider than the
	# card -- and a Button does not clip, so the tagline, the pip meters and
	# everything else in the column drew straight out over the card beside it.
	# Wrapping drops the minimum to the longest single word. Applied here
	# rather than in _caption() because most captions in this file are
	# single-line chips that must NOT wrap.
	var tagline := _caption(titles, String(info.get("desc", "")), 13,
		Color(0.84, 0.92, 0.99, 0.9) if primary else Color(tint, 0.85))
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tagline.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tagline.max_lines_visible = 2

	_body_text(column, String(DIFFICULTY_PITCH.get(id, "")), 16, 2) \
		.add_theme_color_override("font_color",
			Color(0.84, 0.92, 0.99) if primary else UITheme.COLOR_TEXT_DIM)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	# Rival profile: the three numbers that actually change how a race feels,
	# read as pip meters so the tiers compare at a glance.
	var meters := HBoxContainer.new()
	meters.add_theme_constant_override("separation", _gap(10))
	meters.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(meters)
	_meter(meters, "pace", inverse_lerp(0.80, 1.05, float(info.get("speed_scale", 0.95))), tint)
	_meter(meters, "aggression", float(info.get("item_aggression", 0.6)), tint)
	_meter(meters, "mistakes", float(info.get("mistake_rate", 0.1)) / 0.4, tint)

	if _chosen_mode == Game.Mode.GRAND_PRIX:
		var record := Progression.gp_record(id)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", _gap(8))
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(line)
		if record.is_empty():
			_caption(line, "cup not yet contested", 13, Color(0.55, 0.68, 0.82, 0.8))
		else:
			_caption(line, "best cup", 13, Color(0.55, 0.68, 0.82))
			var value := Label.new()
			value.text = "%s · %d pts" % [
				_ordinal(int(record.get("placement", 0))), int(record.get("points", 0))]
			value.add_theme_font_override("font", UITheme.bold_font())
			value.add_theme_font_size_override("font_size", _f(15))
			value.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
			value.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.add_child(value)


## Five-pip meter under an uppercase caption. Pips (rather than a bar) keep the
## comparison discrete and read clearly at phone sizes.
func _meter(parent: Control, caption: String, value01: float, tint: Color) -> void:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", _gap(4))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(box)
	var meter_cap := _caption(box, caption, 12, Color(0.62, 0.74, 0.87))
	meter_cap.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	meter_cap.clip_text = true
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", roundi(_u(3.0)))
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(pips)
	var filled := clampi(roundi(clampf(value01, 0.0, 1.0) * 5.0), 1, 5)
	for i: int in 5:
		var pip := Panel.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(tint, 0.92) if i < filled else Color(0.62, 0.74, 0.87, 0.16)
		style.set_corner_radius_all(2)
		pip.add_theme_stylebox_override("panel", style)
		pip.custom_minimum_size = Vector2(0.0, _u(6.0))
		pip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pips.add_child(pip)


## Chevron-stack glyph: more chevrons and hotter color per difficulty tier.
func _difficulty_icon(id: String, tier: int) -> String:
	var color := String(DIFFICULTY_COLORS.get(id, "#f5c542"))
	var chevrons := ""
	for i: int in tier:
		var y := 46 - i * 13
		chevrons += "<path d=\"M14 %d L32 %d L50 %d\" stroke=\"%s\" stroke-width=\"6\" fill=\"none\" stroke-linecap=\"round\" stroke-linejoin=\"round\" opacity=\"%.2f\"/>" % [
			y + 8, y, y + 8, color, 0.55 + 0.45 * float(i + 1) / float(tier),
		]
	return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"64\" height=\"64\" viewBox=\"0 0 64 64\">%s</svg>" % chevrons


## --- Chrome -----------------------------------------------------------------

## Quiet third-tier exit. Deliberately not a card: nothing on this screen should
## compete with the choices, and every step needs the same escape hatch.
func _build_back_row(text: String, action: Callable) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_footer.add_child(row)
	var button := UITheme.make_button(
		text, UITheme.scaled_size(Vector2(220.0, 52.0)), _f(20))
	button.custom_minimum_size.y = _u(52.0)
	ExpeditionMenuStyle.style_button(button, false, _f(20))
	var icon := ExpeditionMenuStyle.wardrobe_sprite("back")
	if icon != null:
		button.icon = icon
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", roundi(_u(20.0)))
		button.add_theme_constant_override("h_separation", roundi(_u(10.0)))
	UITheme.hook_sounds(button)
	button.pressed.connect(action)
	row.add_child(button)
	_buttons.append(button)
	# Reserve the footer's height at the end of the scrolling column, so the
	# last card can be scrolled clear of it instead of living underneath it.
	var spacer := Control.new()
	spacer.custom_minimum_size.y = _u(52.0) + float(_gap(UITheme.SPACE_M))
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(spacer)


func _clear() -> void:
	if is_instance_valid(_mode_hero):
		_mode_hero.free()
		_mode_hero = null
	_buttons.clear()
	_apply_frame()
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	if _footer != null:
		for child in _footer.get_children():
			_footer.remove_child(child)
			child.queue_free()


func _focus_first() -> void:
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


## Unified staggered fade+rise entrance whenever a step is rebuilt. Never gates
## input, and calmed screens skip it outright.
func _play_entrance() -> void:
	_recolor_premium(_content)
	if UITheme.reduced_motion():
		return
	var items: Array[Control] = []
	for child in _content.get_children():
		if child is Control:
			items.append(child as Control)
	UITheme.play_entrance(self, items)


func _recolor_premium(node: Node, coral: bool = false) -> void:
	if node.has_meta("premium_primary"):
		coral = bool(node.get_meta("premium_primary"))
	if node is Label:
		var label := node as Label
		label.add_theme_color_override("font_color",
			Color.WHITE if coral else ExpeditionMenuStyle.INK)
	for child in node.get_children():
		_recolor_premium(child, coral)


## --- Formatting -------------------------------------------------------------

static func _ordinal(place: int) -> String:
	if place <= 0:
		return "—"
	var suffix := "th"
	if place % 100 < 11 or place % 100 > 13:
		match place % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [place, suffix]


## 3830 -> "3,830". Big totals are easier to read grouped (same as results.gd).
static func _fmt_int(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	for i: int in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return ("-" if value < 0 else "") + out


## --- Navigation -------------------------------------------------------------

## One step back through the flow; from the first step, back to the main menu.
## Shared by ui_cancel and the edge-swipe back gesture.
func _go_back_step() -> void:
	match _step:
		"mode":
			SceneRouter.go_back()
		"course":
			_show_mode_step()
		"difficulty":
			_show_course_step() if _chosen_mode != Game.Mode.GRAND_PRIX else _show_mode_step()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_back_step()
