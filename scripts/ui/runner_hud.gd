class_name RunnerHUD
extends CanvasLayer
## Waddle Run HUD: the headline card (distance + score), a supporting row of
## fish / multiplier / lives, the live challenge stack, the power-up rings, the
## bottom avalanche gauge, the reward floaters, the centred callout, and the
## end-of-run panel.
##
## Visual system is deliberately the racing HUD's, so a player moving between
## the two modes reads one interface rather than two: the same shared card art
## (UITheme.make_card_style), the same value-over-caption type pair, the same
## GUTTER / GAP_S / GAP_M rhythm, and UITheme's palette throughout.
##
## FEEDBACK IS THE POINT. An endless runner is a slot machine you steer: the
## metres tick by on their own, so the only thing that makes a run feel EARNED
## is the interface reacting to it. Four rules, applied everywhere below:
##
##   1. Nothing appears or disappears instantly. Every element eases in, eases
##      out, and overshoots slightly on the way (TRANS_BACK). A pill that pops
##      into existence reads as a bug; one that springs in reads as a reward.
##   2. Numbers travel. The score counts toward its target instead of snapping,
##      so a +50 fish is a visible surge rather than a changed digit.
##   3. Every point has a body. add_floater throws the actual number into the
##      play space above the penguin, where the player's eyes already are —
##      the corner readout is the ledger, the floater is the payoff.
##   4. Danger escalates on more than one channel at once: colour, pulse RATE,
##      and a heartbeat vignette that beats faster the closer the wall gets.
##
## Layout is one centred instrument stack at the top, the challenge stack at the
## top-left, the power-up rings at the top-right, and one gauge at the bottom.
## _relayout is what makes that survive a phone: the two corner stacks stay
## level with the headline only while there is measurably room beside it, and
## drop underneath it when there is not, and the headline card and the
## end-of-run buttons flip from a row to a column under NARROW_WIDTH.
##
## set_stats runs once a frame, so every readout remembers the value it is
## currently showing and only touches a Label when that value actually changes.
## The steady-state per-frame cost is a handful of float writes; a String is
## only built on the frame a number moves. The continuous animation (score
## count-up, floaters, mission bars, heartbeat) lives in one _process rather
## than in a tween per event, so a burst of ten pickups allocates nothing.

signal restart_pressed
signal menu_pressed

## --- Layout rhythm ----------------------------------------------------------
const GUTTER: float = 24.0          ## Screen-edge margin (UITheme.SPACE_M).
const GAP_S: int = 6                ## Inside a group.
const GAP_M: int = 12               ## Between groups.

## Viewport width (logical units) below which the headline card and the
## end-of-run button pair stack vertically.
##
## Portrait is NOT automatically below this: SettingsManager turns the design
## canvas on its side in portrait, so a portrait phone reports ~800 logical
## units of width rather than the ~370 a fixed 1920-wide canvas would give.
## Only a portrait phone at a large accessibility ui_scale actually gets here.
const NARROW_WIDTH: float = 620.0
## Width and height the centred headline stack occupies, as a row and as a
## column. Estimated rather than measured: _relayout runs before the containers
## have sorted (and on every resize), so reading the live size would sample a
## stale rect exactly when it matters. Both are deliberate over-estimates.
const HEADLINE_ROW_WIDTH: float = 366.0
const HEADLINE_ROW_HEIGHT: float = 152.0
const HEADLINE_COLUMN_WIDTH: float = 214.0
const HEADLINE_COLUMN_HEIGHT: float = 258.0
## Narrowest a challenge stack may be squeezed before it is dropped below the
## headline instead. Under this it ellipsises every goal into uselessness.
const MISSION_MIN_WIDTH: float = 154.0

## --- Avalanche read ---------------------------------------------------------
## Gap at which the gauge starts warming toward red, and the gap at which the
## HUD commits to the full danger read (red veil, red numerals, pulsing tag).
const WARN_GAP: float = 18.0
const DANGER_GAP: float = 10.0
## Peak opacity of the screen-edge danger veil, reached as the gap hits zero.
const VEIL_ALPHA: float = 0.74
## Heartbeat rate (Hz) at the edge of danger and at nought metres. Kept well
## under the 3 Hz photosensitivity line even at its fastest, and the depth is
## a modulation of an already-visible wash rather than an on/off flash — but
## it still goes through the reduced-motion gate, because the *rate* change is
## the aggressive part.
const BEAT_SLOW: float = 1.25
const BEAT_FAST: float = 2.60
const GAUGE_WIDTH: float = 400.0
const GAUGE_HEIGHT: float = 16.0

## Warning red, shared by the gauge fill, the metre readout and the veil.
const COLOR_DANGER: Color = Color(1.0, 0.36, 0.30)
## Mission-complete / goal-met green. Distinct from both the ice accent (which
## means "neutral information") and the gold (which means "score").
const COLOR_GOAL: Color = Color(0.51, 0.92, 0.60)

## --- Floaters ---------------------------------------------------------------
## Pooled rising popups. Sixteen is comfortably more than a magnet sweep can
## fire inside one floater lifetime, and the pool is built once at setup so a
## pickup never allocates a node.
const FLOAT_POOL: int = 16
## Fixed label width so the text can be centre-aligned without measuring it.
const FLOAT_WIDTH: float = 460.0
const FLOAT_RISE: float = 138.0
## Fraction of the viewport height the floaters spawn at: just above the
## penguin, so a reward lands where the player is already looking.
const FLOAT_ORIGIN_Y: float = 0.660

## --- Challenge stack --------------------------------------------------------
const MISSION_ROWS: int = 3
## Wide enough for the longest real goal line ("Dodge everything for 800 m")
## before the row ellipsises. _relayout clamps it back down when the viewport
## cannot spare the width.
const MISSION_PANEL_WIDTH: float = 300.0
const MISSION_BAR_HEIGHT: float = 7.0

## --- Power-up rings ---------------------------------------------------------
## Diameter of the draining ring, in logical units at hud_scale 1.
const RING_SIZE: float = 54.0

## Score count-up: how fast the displayed score chases the real one. The
## exponential term makes a pickup surge and settle; the flat term guarantees
## the display actually arrives instead of asymptoting forever.
const SCORE_CHASE: float = 8.0
const SCORE_MIN_RATE: float = 40.0

## Edge-weighted red wash, baked once and shared: the "the wall is right behind
## you" cue that a number in the corner cannot deliver on its own.
static var _veil_texture: GradientTexture2D = null
## Power-up ring art, baked once per pixel size and shared.
static var _ring_textures: Dictionary = {}

## Speed streaks. One additive full-screen pass driven entirely by TIME and two
## uniforms, so "faster" costs the same as "slower" — a particle system per
## frame is exactly what a mobile web build cannot pay for. The rays are fixed
## in angle and only their dash phase scrolls outward, which reads as the world
## rushing past rather than as noise.
const SPEED_SHADER_CODE: String = """
shader_type canvas_item;
render_mode blend_add;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float aspect = 1.777;
uniform vec3 tint = vec3(0.72, 0.90, 1.0);
void fragment() {
	vec2 p = (UV - vec2(0.5, 0.54)) * vec2(aspect, 1.0);
	float r = length(p);
	// Nothing in the middle third: the streaks frame the play space, they never
	// draw over the penguin or the track the player is reading.
	float gate = smoothstep(0.24, 0.86, r);
	if (gate * intensity < 0.004) {
		discard;
	}
	float a = atan(p.y, p.x);
	// Three beating sines instead of a hash: irregular ray spacing without the
	// per-pixel noise a hash gives near the centre.
	float rays = sin(a * 23.0) * sin(a * 7.0 + 1.3) * sin(a * 3.0 + 2.9);
	rays = pow(max(rays, 0.0), 2.0);
	float flow = fract(r * 1.6 - TIME * (1.0 + intensity * 2.8) + a * 0.6);
	float dash = smoothstep(0.0, 0.32, flow) * smoothstep(1.0, 0.58, flow);
	COLOR = vec4(tint * rays * dash * gate * intensity, 1.0);
}
"""

## Drawn glyphs. The bundled fallback font carries no ticks, stars or arrows
## (see UITheme's note on .notdef boxes in the web export), so anything
## symbolic in this HUD is a rasterised path.
const CHECK_SVG: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M12 34 L26 48 L52 16" stroke="#8bea99" stroke-width="9" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
</svg>"""

## Power-up faces. Magnet and shield are the racing HUD's own item glyphs, so a
## shield means one thing in both modes; the double-points crate has no racing
## equivalent and gets a drawn "x2" rather than a typed one.
const DOUBLE_SVG: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M9 21 L27 43 M27 21 L9 43" stroke="#f5c542" stroke-width="8" stroke-linecap="round"/>
<path d="M37 26 C37 19 46 16 51 21 C56 26 50 33 44 38 L37 44 H56" fill="none" stroke="#f5c542" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/>
</svg>"""

## Substitutes for the characters the bundled font lacks. Callers upstream write
## whatever reads best in source ("SET COMPLETE — 3 ★"); font_safe swaps the
## glyphs that would otherwise ship as boxes with hex digits inside them.
const GLYPH_FALLBACK: Dictionary = {
	"★": "*", "☆": "*", "—": "-", "–": "-",
	"·": "-", "•": "-", "→": ">", "←": "<",
	"↑": "^", "↓": "v", "×": "x", "✓": "+",
	"…": "...", "“": "\"", "”": "\"", "‘": "'",
	"’": "'",
}

## QA hook, matching RunnerPlayer.autopilot and RunnerGame.auto_quit_after:
## when set (or when `hud_demo=1` is passed after `--`), the HUD drives itself
## from a scripted feed instead of the game's, so the challenge stack, the
## power-up rings and the banner can be screenshotted deterministically rather
## than waiting for an autopilot run to happen to collect a crate.
static var demo_feed: bool = false

var _root: Control = null
## Accessibility HUD scale. The in-run readouts follow the racing HUD and take
## only this; they must NOT also take UITheme's menu touch step, because
## SettingsManager already shrinks the whole canvas on touch devices. The
## end-of-run panel is a menu, so that one does use the UITheme.scaled* helpers.
var _hud_scale: float = 1.0
var _reduced: bool = false
var _headless: bool = false

var _headline_column: VBoxContainer = null
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
var _hit_flash: TextureRect = null
var _speed_lines: ColorRect = null
var _speed_material: ShaderMaterial = null
var _message_label: Label = null
var _message_tween: Tween = null
var _message_text: String = ""
var _game_over: Control = null
var _game_over_buttons: BoxContainer = null

## Challenge stack.
var _mission_panel: PanelContainer = null
var _mission_rows: Array[Control] = []
var _mission_labels: Array[Label] = []
var _mission_bars: Array[ProgressBar] = []
var _mission_marks: Array[Control] = []
var _mission_pcts: Array[Label] = []
var _mission_ids: PackedStringArray = PackedStringArray()
var _mission_target: PackedFloat32Array = PackedFloat32Array()
var _mission_shown: PackedFloat32Array = PackedFloat32Array()
var _mission_pct_shown: PackedInt32Array = PackedInt32Array()
var _mission_done: Array[bool] = []
## Missions finished during THIS run, listed on the end-of-run panel so a run
## reads as a set of goals met rather than as a distance.
var _completed_missions: PackedStringArray = PackedStringArray()

## Power-up rings, one slot per RunnerConfig.POWERUP_IDS entry, built once and
## shown/hidden rather than created and freed.
var _powerup_box: BoxContainer = null
var _powerup_slots: Array[Control] = []
var _powerup_rings: Array[TextureProgressBar] = []
var _powerup_times: Array[Label] = []
var _powerup_left: PackedFloat32Array = PackedFloat32Array()
var _powerup_shown: PackedInt32Array = PackedInt32Array()
var _powerup_on: Array[bool] = []

## Floater pool. Parallel arrays rather than an array of objects, so firing one
## writes floats into existing storage instead of allocating a state record.
var _float_root: Control = null
var _float_labels: Array[Label] = []
var _float_age: PackedFloat32Array = PackedFloat32Array()
var _float_life: PackedFloat32Array = PackedFloat32Array()
var _float_x: PackedFloat32Array = PackedFloat32Array()
var _float_y: PackedFloat32Array = PackedFloat32Array()
var _float_drift: PackedFloat32Array = PackedFloat32Array()
var _float_rise: PackedFloat32Array = PackedFloat32Array()
var _float_live: int = 0
var _float_next: int = 0
var _float_lane: int = 0

## Mission-complete banner.
var _banner: Control = null
var _banner_title: Label = null
var _banner_tween: Tween = null

## Values currently on screen. Every one of them is compared before its Label is
## touched, so a 60 fps caller does not rebuild six strings a frame.
var _shown_distance: int = -1
var _shown_score: int = -1
var _shown_fish: int = -1
var _shown_multiplier: int = -1
var _shown_hits: int = -1
var _shown_gap: int = -1
var _in_danger: bool = false
## Score count-up state: the real score, and the one currently drawn.
var _score_target: float = 0.0
var _score_display: float = 0.0
## Danger state, written by set_stats and consumed by _process.
var _danger_gap: float = RunnerConfig.CHASER_BASE_GAP
var _veil_base: float = 0.0
var _beat_phase: float = 0.0
## Speed streak state. The uniform is only written when the ratio has moved
## enough to be visible.
var _speed_ratio: float = 0.0
var _speed_sent: float = -1.0
var _speed_gold: bool = false
## Guards a combo punch from firing twice in one frame when the caller uses
## both set_stats and set_combo.
var _combo_frame: int = -1
var _view_size: Vector2 = Vector2(1920.0, 1080.0)
var _demo_time: float = 0.0
var _demo_step: int = 0
## True only while the QA feed is making its calls, so the game's own (empty)
## state cannot overwrite the scripted one on the very next frame.
var _demo_driving: bool = false
## QA override for the avalanche gap, so the escalating danger read can be
## screenshotted without having to actually be caught. Negative = off.
var _demo_gap: float = -1.0


## --- Build ------------------------------------------------------------------

func setup() -> void:
	if _root != null:
		return
	_headless = GameConfig.is_headless()
	_hud_scale = float(SettingsManager.get_setting("accessibility", "hud_scale"))
	_reduced = UITheme.reduced_motion()
	if not demo_feed:
		for arg: String in OS.get_cmdline_user_args():
			if arg == "hud_demo=1":
				demo_feed = true
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Build back to front: the two washes are a backdrop for the readouts, never
	# an overlay on them, and the floaters must sit above every panel.
	_build_speed_lines()
	_build_danger_veil()
	_build_hit_flash()
	_build_headline()
	_build_gauge()
	_build_missions()
	_build_powerups()
	_build_floaters()
	_build_banner()
	_build_message()

	if not _headless:
		get_viewport().size_changed.connect(_relayout)
	_relayout()
	set_process(not _headless)
	_play_entrance()


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
	_headline_column = VBoxContainer.new()
	_headline_column.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_headline_column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_headline_column.offset_top = GUTTER * s
	_headline_column.add_theme_constant_override("separation", int(GAP_S * s))
	_headline_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_headline_column)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", _card_style(18.0 * s, 7.0 * s))
	_headline_column.add_child(card)

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
	_headline_column.add_child(row)
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
## The wash itself is continuous; only its heartbeat modulation (see _process)
## is animated, and that goes through the reduced-motion gate.
func _build_danger_veil() -> void:
	if _headless:
		return
	_danger_veil = TextureRect.new()
	_danger_veil.texture = _veil_tex()
	_danger_veil.stretch_mode = TextureRect.STRETCH_SCALE
	_danger_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_danger_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_danger_veil.modulate.a = 0.0
	_root.add_child(_danger_veil)


## One-shot impact wash, separate from the danger veil so a hit taken at three
## metres does not fight the continuous alpha the gap is driving.
func _build_hit_flash() -> void:
	if _headless:
		return
	_hit_flash = TextureRect.new()
	_hit_flash.texture = _veil_tex()
	_hit_flash.stretch_mode = TextureRect.STRETCH_SCALE
	_hit_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hit_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hit_flash.modulate = Color(1.0, 0.72, 0.66, 0.0)
	_root.add_child(_hit_flash)


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


## Additive streak field driven by set_speed_ratio. Hidden outright below a
## visible intensity, so a slow opening frame costs nothing at all.
func _build_speed_lines() -> void:
	if _headless:
		return
	var shader := Shader.new()
	shader.code = SPEED_SHADER_CODE
	_speed_material = ShaderMaterial.new()
	_speed_material.shader = shader
	_speed_lines = ColorRect.new()
	_speed_lines.color = Color.WHITE
	_speed_lines.material = _speed_material
	_speed_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_speed_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_lines.visible = false
	_root.add_child(_speed_lines)


## --- Challenge stack --------------------------------------------------------

## The three live goals, top-left under the safe area. Every row is built once
## and then only re-texted; a goal arriving or leaving animates rather than
## popping, because the stack is in peripheral vision and a silent swap there
## is invisible.
func _build_missions() -> void:
	var s := _hud_scale
	_mission_panel = PanelContainer.new()
	_mission_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_mission_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mission_panel.add_theme_stylebox_override("panel", _card_style(13.0 * s, 11.0 * s))
	_mission_panel.visible = false
	_root.add_child(_mission_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(maxf(GAP_S * s, 4.0)))
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mission_panel.add_child(column)

	var head := _caption_label("Challenges", 12.0 * s, Color(UITheme.COLOR_ACCENT, 0.85))
	column.add_child(head)

	# One baked fill for all three bars; the per-row colour is a modulate write.
	var fill := UITheme.make_bar_fill(Color(0.62, 0.86, 1.0), Color(0.92, 0.99, 1.0))
	var check := UITheme.make_icon(CHECK_SVG, 0.6)
	for i: int in MISSION_ROWS:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", int(maxf(2.0 * s, 1.0)))
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.visible = false
		column.add_child(row)

		var head_row := HBoxContainer.new()
		head_row.add_theme_constant_override("separation", int(maxf(6.0 * s, 3.0)))
		head_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(head_row)

		var text := _caption_label("", 13.0 * s, UITheme.COLOR_TEXT)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.clip_text = true
		text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		head_row.add_child(text)

		var pct := _caption_label("0%", 12.0 * s, Color(UITheme.COLOR_TEXT_DIM, 0.95))
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		head_row.add_child(pct)

		var mark: Control = null
		if check != null:
			var icon := TextureRect.new()
			icon.texture = check
			icon.custom_minimum_size = Vector2(15.0 * s, 15.0 * s)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			mark = icon
		else:
			mark = _caption_label("OK", 12.0 * s, COLOR_GOAL)
		mark.visible = false
		head_row.add_child(mark)

		var groove := _thin_bar(MISSION_BAR_HEIGHT * s, fill)
		row.add_child(groove)

		_mission_rows.append(row)
		_mission_labels.append(text)
		_mission_pcts.append(pct)
		_mission_marks.append(mark)
		_mission_bars.append(groove.get_child(0) as ProgressBar)
		_mission_ids.append("")
		_mission_target.append(0.0)
		_mission_shown.append(0.0)
		_mission_pct_shown.append(-1)
		_mission_done.append(false)


## Recessed thin channel with a progress fill inside it, the same material as
## the avalanche gauge one size down.
func _thin_bar(height: float, fill: StyleBoxTexture) -> Panel:
	var groove := Panel.new()
	groove.custom_minimum_size = Vector2(0.0, height)
	groove.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	groove.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UITheme.COLOR_BG_DEEP, 0.85)
	style.set_corner_radius_all(maxi(int(height * 0.5), 2))
	style.set_border_width_all(1)
	style.border_color = Color(UITheme.COLOR_ACCENT, 0.22)
	style.anti_aliasing = true
	groove.add_theme_stylebox_override("panel", style)

	var inset := maxf(height * 0.18, 1.0)
	var bar := ProgressBar.new()
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.offset_left = inset
	bar.offset_top = inset
	bar.offset_right = -inset
	bar.offset_bottom = -inset
	bar.max_value = 1.0
	bar.value = 0.0
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	bar.add_theme_stylebox_override("fill", fill)
	bar.modulate = UITheme.COLOR_ACCENT
	groove.add_child(bar)
	return groove


## --- Power-up rings ---------------------------------------------------------

## One ring per power-up, top-right. A draining ring beats a countdown label
## because it is read without being looked at: the player sees how much is
## left out of the corner of their eye while still watching the lane.
func _build_powerups() -> void:
	var s := _hud_scale
	_powerup_box = BoxContainer.new()
	_powerup_box.vertical = true
	_powerup_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_powerup_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_powerup_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_powerup_box.add_theme_constant_override("separation", int(maxf(GAP_S * s, 4.0)))
	_powerup_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_powerup_box)

	var ring_px := maxi(int(RING_SIZE * s), 20)
	for id: StringName in RunnerConfig.POWERUP_IDS:
		var tint := _powerup_color(id)
		var slot := PanelContainer.new()
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.size_flags_horizontal = Control.SIZE_SHRINK_END
		slot.add_theme_stylebox_override("panel",
			_pill_style(tint, Color(UITheme.COLOR_BG_DEEP, 0.86)))
		slot.visible = false
		slot.modulate.a = 0.0
		_powerup_box.add_child(slot)

		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 0)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(column)

		var ring := TextureProgressBar.new()
		ring.texture_under = _ring_tex(ring_px)
		ring.texture_progress = _ring_tex(ring_px)
		ring.tint_under = Color(tint.r, tint.g, tint.b, 0.20)
		ring.tint_progress = tint
		ring.fill_mode = TextureProgressBar.FILL_CLOCKWISE
		ring.radial_initial_angle = 0.0
		ring.radial_center_offset = Vector2.ZERO
		ring.max_value = 1.0
		ring.value = 1.0
		ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(ring)

		var glyph := _powerup_icon(id)
		if glyph != null:
			var icon := TextureRect.new()
			icon.texture = glyph
			icon.set_anchors_preset(Control.PRESET_FULL_RECT)
			var pad := float(ring_px) * 0.23
			icon.offset_left = pad
			icon.offset_top = pad
			icon.offset_right = -pad
			icon.offset_bottom = -pad
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ring.add_child(icon)

		var time_label := _caption_label("0s", 12.0 * s, tint)
		time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(time_label)

		_powerup_slots.append(slot)
		_powerup_rings.append(ring)
		_powerup_times.append(time_label)
		_powerup_left.append(0.0)
		_powerup_shown.append(-1)
		_powerup_on.append(false)


## One colour per verb the power-up rewrites: pink for "collect differently",
## ice for "a mistake is free", gold for "worth more".
func _powerup_color(id: StringName) -> Color:
	if id == RunnerConfig.POWERUP_SHIELD:
		return Color(0.44, 0.84, 0.98)
	if id == RunnerConfig.POWERUP_DOUBLE:
		return UITheme.COLOR_GOLD
	return Color(0.95, 0.44, 0.65)


func _powerup_icon(id: StringName) -> ImageTexture:
	if id == RunnerConfig.POWERUP_DOUBLE:
		return UITheme.make_icon(DOUBLE_SVG, 0.9)
	var key := "shield" if id == RunnerConfig.POWERUP_SHIELD else "magnet"
	return UITheme.make_icon(String(RaceHUD.ITEM_ICONS.get(key, "")), 0.9)


## White annulus, baked once per pixel size. Tinted per power-up through
## TextureProgressBar's tint_under / tint_progress, so all three rings share
## one texture.
static func _ring_tex(px: int) -> ImageTexture:
	if _ring_textures.has(px):
		return _ring_textures[px] as ImageTexture
	var img := Image.create_empty(px, px, false, Image.FORMAT_RGBA8)
	var centre := float(px) * 0.5 - 0.5
	var outer := float(px) * 0.5 - 1.0
	var inner := outer - maxf(float(px) * 0.15, 2.0)
	for y: int in px:
		for x: int in px:
			var d := Vector2(float(x) - centre, float(y) - centre).length()
			var a := clampf(outer - d + 0.5, 0.0, 1.0) * clampf(d - inner + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	var tex := ImageTexture.create_from_image(img)
	_ring_textures[px] = tex
	return tex


## --- Floaters ---------------------------------------------------------------

## Pre-built pool of rising popups. Built once so a magnet sweep firing eight
## fish in half a second costs eight float writes, not eight node allocations.
func _build_floaters() -> void:
	_float_root = Control.new()
	_float_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_float_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_float_root)
	var s := _hud_scale
	var width := FLOAT_WIDTH * s
	for i: int in FLOAT_POOL:
		var label := _value_label("", 30.0 * s, UITheme.COLOR_TEXT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size = Vector2(width, 52.0 * s)
		label.pivot_offset = label.size * 0.5
		label.visible = false
		_float_root.add_child(label)
		_float_labels.append(label)
		_float_age.append(0.0)
		_float_life.append(0.0)
		_float_x.append(0.0)
		_float_y.append(0.0)
		_float_drift.append(0.0)
		_float_rise.append(0.0)


## --- Banner -----------------------------------------------------------------

## Mission-complete banner. Parked at the bottom centre, immediately above the
## avalanche gauge: a celebration belongs where the player's peripheral vision
## already is, and that strip is empty deck rather than track they are reading.
func _build_banner() -> void:
	var s := _hud_scale
	_banner = PanelContainer.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := UITheme.make_panel_style(
		Color(0.035, 0.105, 0.075, 0.95), Color(COLOR_GOAL, 0.90))
	style.set_corner_radius_all(UITheme.RADIUS_PILL)
	style.content_margin_left = 20.0 * s
	style.content_margin_right = 20.0 * s
	style.content_margin_top = 6.0 * s
	style.content_margin_bottom = 6.0 * s
	style.shadow_color = Color(COLOR_GOAL, 0.30)
	style.shadow_size = 12
	(_banner as PanelContainer).add_theme_stylebox_override("panel", style)
	_banner.visible = false
	_banner.modulate.a = 0.0
	# Pivot tracks the pill's real width, which changes with every headline it
	# is given; connected once here rather than per show.
	_banner.resized.connect(func() -> void:
		_banner.pivot_offset = _banner.size * 0.5)
	_root.add_child(_banner)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(maxf(10.0 * s, 5.0)))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(row)
	var check := UITheme.make_icon(CHECK_SVG, 0.55)
	if check != null:
		var icon := TextureRect.new()
		icon.texture = check
		icon.custom_minimum_size = Vector2(22.0 * s, 22.0 * s)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)
	column.add_child(_caption_label("Challenge Complete", 12.0 * s,
		Color(0.66, 0.96, 0.76)))
	_banner_title = _value_label("", 22.0 * s, Color(0.93, 1.0, 0.94))
	column.add_child(_banner_title)


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


## Staggered arrival for the whole overlay, so a run opens with the interface
## assembling itself rather than with a finished HUD already pasted on frame
## one. Uses the game's shared entrance rather than a bespoke one: it waits two
## frames for containers to sort before capturing target positions, which is
## exactly the trap a hand-rolled slide falls into here (on the frame setup
## runs, every anchored block still reports position zero).
func _play_entrance() -> void:
	if _headless or _reduced:
		return
	var blocks: Array[Control] = [_headline_column, _mission_panel,
		_powerup_box, _gauge_holder]
	UITheme.play_entrance(_root, blocks, 22.0 * _hud_scale)


## --- Orientation ------------------------------------------------------------

## Re-fits everything that cannot survive a portrait viewport unchanged: the
## headline card's two stats and the end-of-run button pair become columns, the
## gauge is clamped inside the usable width, and the two corner stacks drop
## below the (now much taller) headline instead of colliding with it. Cheap
## enough to run on every resize — no node is rebuilt.
func _relayout() -> void:
	_view_size = _view_rect()
	var width := _view_size.x
	var narrow := width < NARROW_WIDTH
	var s := _hud_scale
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

	# Safe-area inset as well as the gutter: on a notched phone in landscape
	# the rounded corner eats further into the row than the margin allows for.
	var margin := GUTTER * s + UITheme.safe_inset_x(_root)
	var usable := maxf(width - margin * 2.0, 120.0)
	if _gauge_holder != null:
		_gauge_holder.custom_minimum_size.x = clampf(GAUGE_WIDTH * s, 120.0, usable)

	# Where the two corner stacks go is a geometry question, not an orientation
	# one: they sit level with the headline only while there is genuinely room
	# beside it, and drop underneath it when there is not. Deciding this by
	# orientation instead is what puts a challenge row under the distance
	# readout on the in-between widths (a portrait phone reports ~800).
	var ring_width := RING_SIZE * s + 34.0 * s
	var headline_w := (HEADLINE_COLUMN_WIDTH if narrow else HEADLINE_ROW_WIDTH) * s
	var headline_h := (HEADLINE_COLUMN_HEIGHT if narrow else HEADLINE_ROW_HEIGHT) * s
	var side_room := (width - headline_w) * 0.5 - margin - GAP_M * s
	var stacked := side_room < maxf(ring_width, MISSION_MIN_WIDTH * s)
	var corner_top := GUTTER * s + (headline_h + GAP_M * s if stacked else 0.0)
	var mission_room := (usable - ring_width - GAP_M * s) if stacked else side_room
	if _powerup_box != null:
		_powerup_box.offset_right = -margin
		_powerup_box.offset_top = corner_top
	if _mission_panel != null:
		_mission_panel.offset_left = margin
		_mission_panel.offset_top = corner_top
		_mission_panel.custom_minimum_size.x = clampf(
			MISSION_PANEL_WIDTH * s, 110.0, maxf(mission_room, 110.0))
	if _banner != null:
		# Immediately above the gauge, which owns the last ~52 units.
		_banner.offset_bottom = -(GUTTER + 56.0) * s
	if _message_label != null:
		var anchor := 0.42 if narrow else 0.30
		_message_label.anchor_top = anchor
		_message_label.anchor_bottom = anchor
	if _speed_material != null and _view_size.y > 0.0:
		_speed_material.set_shader_parameter("aspect", _view_size.x / _view_size.y)
	if _game_over_buttons != null:
		_game_over_buttons.vertical = narrow


func _view_rect() -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return Vector2(1920.0, 1080.0)
	var size := viewport.get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return Vector2(1920.0, 1080.0)
	return size


## True when the QA feed owns the HUD and a call from the game should be
## dropped. Always false in a normal build.
func _demo_blocks() -> bool:
	return demo_feed and not _demo_driving


## --- Per-frame readout ------------------------------------------------------

## Called every frame by the runner. Each readout compares against the value it
## is already displaying and returns early, so the common frame does no string
## work at all. Continuous animation is NOT done here — it lives in _process,
## which runs whether or not the game is feeding the HUD.
func set_stats(distance_m: float, fish: int, score: int, multiplier: int,
		hits_left: int, chaser_gap: float) -> void:
	if _root == null:
		return
	if _demo_gap >= 0.0:
		chaser_gap = _demo_gap

	var metres := maxi(int(distance_m), 0)
	if metres != _shown_distance:
		_shown_distance = metres
		_distance_label.text = "%d m" % metres

	# The score TARGET moves here; the drawn number chases it in _process, so a
	# +50 fish reads as a surge instead of as a changed digit.
	_score_target = float(score)
	if score < _shown_score:
		# A restart, not a gain: snap rather than counting backwards. This is
		# also the only reliable "a new run began" signal the HUD gets, so the
		# run-scoped challenge list is reset here.
		_score_display = _score_target
		_shown_score = score
		_score_label.text = group_digits(score)
		_completed_missions = PackedStringArray()

	if fish != _shown_fish:
		var gained := fish > _shown_fish and _shown_fish >= 0
		_shown_fish = fish
		_fish_label.text = str(fish)
		if gained:
			_punch(_fish_label, 1.3)

	# The QA feed owns the chip when it is driving, so a scripted combo is not
	# overwritten by the real (x1) multiplier on the very next frame.
	if not _demo_blocks():
		_apply_multiplier(multiplier, multiplier > _shown_multiplier and _shown_multiplier > 0)

	if hits_left != _shown_hits:
		var lost := _shown_hits >= 0 and hits_left < _shown_hits
		_shown_hits = hits_left
		for i: int in _life_pips.size():
			_life_pips[i].add_theme_stylebox_override("panel",
				_pip_alive if i < hits_left else _pip_spent)
		if lost:
			_punch(_lives_pill, 1.2)
			# The pip that just went out gets its own collapse, so the loss has a
			# location on screen and not just a colour change.
			if hits_left >= 0 and hits_left < _life_pips.size():
				_punch(_life_pips[hits_left], 1.9)

	_gauge_bar.value = clampf(chaser_gap / RunnerConfig.CHASER_BASE_GAP, 0.0, 1.0)
	_danger_gap = chaser_gap
	# Curved rather than linear, and deliberately back-loaded: the wash stays a
	# hint through the half of the window the player can still run out of, and
	# only takes the screen over in the last few metres, where it has to be
	# unmissable. A straight ramp spends most of its range crying wolf.
	_veil_base = pow(clampf((DANGER_GAP - chaser_gap) / DANGER_GAP, 0.0, 1.0), 1.25) \
		* VEIL_ALPHA
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


## Enters/leaves the committed danger read. The veil and the tag's pulse are
## driven continuously in _process (their RATE is part of the escalation, which
## a fixed-duration tween cannot express); this only owns the one-shot swap.
func _set_danger(danger: bool) -> void:
	if _gauge_tag == null:
		return
	_gauge_tag.add_theme_color_override("font_color",
		COLOR_DANGER if danger else UITheme.COLOR_TEXT_DIM)
	_gauge_tag.text = "AVALANCHE!" if danger else "AVALANCHE"
	_beat_phase = 0.0
	if danger:
		_punch(_gauge_holder, 1.06)
	else:
		_gauge_tag.modulate.a = 1.0
		if _danger_veil != null:
			_danger_veil.modulate.a = 0.0


## Scale pop on a readout that just changed. Event-driven only, and skipped
## outright when the player has asked for less motion.
func _punch(control: Control, amount: float) -> void:
	if control == null or _headless or _reduced:
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


## Swaps any character the bundled fallback font cannot draw for one it can.
##
## ThemeDB.fallback_font is Godot's own subset and carries no stars, arrows,
## dashes or ellipses; a desktop editor run papers over that with an OS font
## fallback, but the web export cannot, and each missing glyph ships as a
## .notdef box with its hex digits inside. Callers upstream write whatever
## reads best in source, so the HUD sanitises at the point of display.
static func font_safe(text: String) -> String:
	var font := ThemeDB.fallback_font
	if font == null or text.is_empty():
		return text
	var missing := false
	for i: int in text.length():
		if not font.has_char(text.unicode_at(i)):
			missing = true
			break
	if not missing:
		return text
	var out := ""
	for i: int in text.length():
		var glyph := text[i]
		if font.has_char(text.unicode_at(i)):
			out += glyph
		else:
			out += String(GLYPH_FALLBACK.get(glyph, ""))
	return out


## --- Continuous animation ---------------------------------------------------

## One tick for everything that eases rather than jumps. Deliberately a single
## _process instead of a tween per event: a run fires dozens of pickups a
## minute, and each one would otherwise allocate and schedule a Tween.
func _process(delta: float) -> void:
	if _root == null:
		return
	if demo_feed:
		_demo_tick(delta)
	_tick_score(delta)
	if _float_live > 0:
		_tick_floaters(delta)
	_tick_missions(delta)
	_tick_powerups(delta)
	_tick_danger(delta)


## Score count-up. The exponential term gives the surge, the flat term
## guarantees arrival; the Label is only touched when the drawn integer moves.
func _tick_score(delta: float) -> void:
	var gap := _score_target - _score_display
	if absf(gap) < 0.5:
		if _shown_score != int(_score_target):
			_shown_score = int(_score_target)
			_score_display = _score_target
			_score_label.text = group_digits(_shown_score)
		return
	var step := gap * minf(delta * SCORE_CHASE, 1.0)
	if absf(step) < SCORE_MIN_RATE * delta:
		step = signf(gap) * minf(SCORE_MIN_RATE * delta, absf(gap))
	_score_display += step
	var drawn := int(_score_display)
	if drawn != _shown_score:
		_shown_score = drawn
		_score_label.text = group_digits(drawn)


## Rise / drift / pop / fade for every live floater. Reads and writes only
## packed float storage plus three Control properties per active popup.
func _tick_floaters(delta: float) -> void:
	var live := 0
	for i: int in _float_labels.size():
		var life := _float_life[i]
		if life <= 0.0:
			continue
		var age := _float_age[i] + delta
		if age >= life:
			_float_life[i] = 0.0
			_float_labels[i].visible = false
			continue
		_float_age[i] = age
		live += 1
		var label := _float_labels[i]
		var t := age / life
		# Rise: fast out of the gate, coasting at the top, the way a coin arc
		# behaves. Cubic ease-out, no library call.
		var inv := 1.0 - t
		var rise := 1.0 - inv * inv * inv
		label.position = Vector2(
			_float_x[i] + _float_drift[i] * t,
			_float_y[i] - _float_rise[i] * rise)
		# Overshoot on the way in, a slight shrink on the way out. The overshoot
		# is what makes a +25 feel like it was thrown at the screen.
		var pop := 1.0
		if t < 0.16:
			var k := t / 0.16
			pop = lerpf(0.55, 1.20, 1.0 - pow(1.0 - k, 3.0))
		elif t < 0.36:
			var k2 := (t - 0.16) / 0.20
			pop = lerpf(1.20, 1.0, k2 * k2 * (3.0 - 2.0 * k2))
		else:
			pop = lerpf(1.0, 0.88, (t - 0.36) / 0.64)
		label.scale = Vector2(pop, pop)
		label.modulate.a = 1.0 if t < 0.55 else clampf((1.0 - t) / 0.45, 0.0, 1.0)
	_float_live = live


## Mission bars ease toward their reported progress. Only the bars that are
## actually moving are written, so a stack of three finished goals is free.
func _tick_missions(delta: float) -> void:
	for i: int in _mission_bars.size():
		if not _mission_rows[i].visible:
			continue
		var target := _mission_target[i]
		var shown := _mission_shown[i]
		var gap := target - shown
		if absf(gap) < 0.002:
			if shown != target:
				_mission_shown[i] = target
				_mission_bars[i].value = target
			continue
		shown += gap * minf(delta * 7.0, 1.0)
		_mission_shown[i] = shown
		_mission_bars[i].value = shown
		var pct := int(round(shown * 100.0))
		if pct != _mission_pct_shown[i] and not _mission_done[i]:
			_mission_pct_shown[i] = pct
			_mission_pcts[i].text = "%d%%" % pct


## Ring drain plus the about-to-expire warning. The remaining time is counted
## down locally between set_powerups calls so the ring is smooth even if the
## caller only reports at a coarser rate.
func _tick_powerups(delta: float) -> void:
	for i: int in _powerup_rings.size():
		if not _powerup_on[i]:
			continue
		var left := maxf(_powerup_left[i] - delta, 0.0)
		_powerup_left[i] = left
		_powerup_rings[i].value = clampf(left / RunnerConfig.POWERUP_TIME, 0.0, 1.0)
		var secs := int(ceil(left))
		if secs != _powerup_shown[i]:
			_powerup_shown[i] = secs
			_powerup_times[i].text = "%ds" % secs
		# Last two seconds: the ring breathes so the player knows to spend the
		# window rather than discovering it has closed.
		if _reduced:
			continue
		var slot := _powerup_slots[i]
		if left < 2.0:
			slot.modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(left * 16.0))
		elif slot.modulate.a < 1.0:
			slot.modulate.a = minf(slot.modulate.a + delta * 4.0, 1.0)


## The escalation: the veil deepens with proximity AND beats faster, and the
## gauge tag beats with it. Two channels moving together is what separates
## "close" from "about to die"; one of them alone reads as decoration.
func _tick_danger(delta: float) -> void:
	if _danger_veil == null:
		return
	if _veil_base <= 0.0:
		if _danger_veil.modulate.a > 0.0:
			_danger_veil.modulate.a = maxf(_danger_veil.modulate.a - delta * 1.6, 0.0)
		return
	if _reduced:
		_danger_veil.modulate.a = _veil_base
		return
	var closeness := clampf(1.0 - _danger_gap / DANGER_GAP, 0.0, 1.0)
	_beat_phase += delta * lerpf(BEAT_SLOW, BEAT_FAST, closeness) * TAU
	if _beat_phase > TAU:
		_beat_phase -= TAU
	# Sharpened sine: a long quiet stretch and a short swell, which reads as a
	# pulse rather than as a fade in and out.
	var beat := pow(0.5 + 0.5 * sin(_beat_phase), 2.2)
	_danger_veil.modulate.a = _veil_base * (0.80 + 0.42 * beat)
	if _gauge_tag != null:
		_gauge_tag.modulate.a = 0.42 + 0.58 * beat


## --- Floaters ---------------------------------------------------------------

## Throws `text` into the play space just above the penguin, where the reward
## actually happened. Pooled: no node is created per call, and firing more than
## the pool holds recycles the oldest popup rather than dropping the newest.
##
## `kind` is one of &"fish", &"score", &"powerup", &"mission", &"near_miss" and
## chooses colour, size and dwell — the player learns "gold means score, ice
## means fish" without ever reading the words.
func add_floater(text: String, kind: StringName) -> void:
	if _root == null or _headless or text.is_empty():
		return
	var s := _hud_scale
	var color := UITheme.COLOR_TEXT
	var size := 30.0
	var life := 0.95
	var rise := FLOAT_RISE
	var lift := 0.0
	match kind:
		&"fish":
			color = UITheme.COLOR_ACCENT
			size = 31.0
		&"score":
			color = UITheme.COLOR_GOLD
			size = 36.0
			life = 1.05
			rise = FLOAT_RISE * 1.15
		&"powerup":
			color = Color(0.82, 0.66, 1.0)
			size = 33.0
			life = 1.20
			rise = FLOAT_RISE * 1.05
		&"mission":
			color = COLOR_GOAL
			size = 30.0
			life = 1.20
		&"near_miss":
			color = Color(1.0, 0.76, 0.40)
			size = 26.0
			life = 0.78
			rise = FLOAT_RISE * 0.8
			# Near misses fire while the player is squeezing past something, so
			# they start higher and stay clear of the pickup numbers.
			lift = 58.0

	var slot := _claim_floater()
	var label := _float_labels[slot]
	label.text = font_safe(text)
	label.add_theme_font_size_override("font_size", maxi(int(size * s), 1))
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", maxi(int(size * s * 0.18), 4))
	label.visible = true
	label.modulate.a = 1.0
	label.scale = Vector2(0.55, 0.55)

	# Alternate the sideways drift and stagger the start height, so a burst
	# fans out instead of stacking into one illegible pile.
	_float_lane = (_float_lane + 1) % 6
	var side := 1.0 if _float_lane % 2 == 0 else -1.0
	var tier := float(_float_lane) / 5.0
	_float_x[slot] = (_view_size.x - FLOAT_WIDTH * s) * 0.5 \
		+ side * (34.0 + tier * 76.0) * s
	_float_y[slot] = _view_size.y * FLOAT_ORIGIN_Y \
		- (lift + float(_float_lane) * 19.0) * s
	_float_drift[slot] = side * (30.0 + tier * 40.0) * s
	_float_rise[slot] = rise * s
	_float_life[slot] = life
	_float_age[slot] = 0.0
	label.position = Vector2(_float_x[slot], _float_y[slot])
	_float_live += 1


## Next free pool slot, falling back to round-robin recycling so a burst larger
## than the pool always shows the newest popups.
func _claim_floater() -> int:
	for i: int in _float_labels.size():
		if _float_life[i] <= 0.0:
			return i
	var slot := _float_next
	_float_next = (_float_next + 1) % _float_labels.size()
	_float_live -= 1
	return slot


## --- Power-ups --------------------------------------------------------------

## `active` maps RunnerConfig.POWERUP_* to seconds remaining; anything missing
## is inactive. Safe to call every frame — the common case (nothing active,
## nothing showing) does three dictionary lookups and returns.
func set_powerups(active: Dictionary) -> void:
	if _root == null or _demo_blocks():
		return
	for i: int in _powerup_rings.size():
		var id: StringName = RunnerConfig.POWERUP_IDS[i]
		var left := float(active.get(id, 0.0))
		var on := left > 0.0
		if on:
			# Re-picking a live power-up refreshes it: trust the caller's clock
			# over the locally interpolated one whenever it is ahead.
			if left > _powerup_left[i] + 0.05:
				_pop_powerup(i)
			_powerup_left[i] = left
		if on == _powerup_on[i]:
			continue
		_powerup_on[i] = on
		if on:
			_powerup_shown[i] = -1
			_powerup_rings[i].value = clampf(left / RunnerConfig.POWERUP_TIME, 0.0, 1.0)
			_show_powerup(i)
		else:
			_hide_powerup(i)


func _show_powerup(index: int) -> void:
	var slot := _powerup_slots[index]
	slot.visible = true
	if _headless or _reduced:
		slot.modulate.a = 1.0
		slot.scale = Vector2.ONE
		return
	_kill_meta_tween(slot, "_slot_tween")
	slot.pivot_offset = slot.size * 0.5
	slot.modulate.a = 0.0
	slot.scale = Vector2(0.55, 0.55)
	var tween := slot.create_tween()
	tween.set_parallel(true)
	tween.tween_property(slot, "modulate:a", 1.0, 0.18)
	tween.tween_property(slot, "scale", Vector2.ONE, 0.42) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	slot.set_meta("_slot_tween", tween)


func _hide_powerup(index: int) -> void:
	var slot := _powerup_slots[index]
	if _headless or _reduced:
		slot.visible = false
		return
	_kill_meta_tween(slot, "_slot_tween")
	slot.pivot_offset = slot.size * 0.5
	var tween := slot.create_tween()
	tween.set_parallel(true)
	tween.tween_property(slot, "modulate:a", 0.0, 0.22)
	tween.tween_property(slot, "scale", Vector2(0.7, 0.7), 0.22) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func() -> void:
		if not _powerup_on[index]:
			slot.visible = false)
	slot.set_meta("_slot_tween", tween)


## Refresh punch: picking up a power-up you already hold has to look like it
## did something, or the crate reads as wasted.
func _pop_powerup(index: int) -> void:
	if not _powerup_on[index]:
		return
	_punch(_powerup_slots[index], 1.28)


func _kill_meta_tween(control: Control, key: String) -> void:
	if not control.has_meta(key):
		return
	var previous: Variant = control.get_meta(key)
	if previous is Tween and (previous as Tween).is_valid():
		(previous as Tween).kill()


## --- Challenges -------------------------------------------------------------

## `rows` is up to MISSION_ROWS dictionaries of
## {"id": String, "text": String, "progress": float 0..1, "done": bool}.
## Rows are matched by id: an unchanged goal only moves its bar, a replaced one
## animates out and back in, and a goal that has just been met flips to the
## finished treatment with a pop. Safe to call every frame.
func set_missions(rows: Array) -> void:
	if _root == null or _demo_blocks():
		return
	var any := false
	for i: int in _mission_rows.size():
		if i >= rows.size():
			_retire_mission(i)
			continue
		var entry: Dictionary = rows[i] if rows[i] is Dictionary else {}
		var id := String(entry.get("id", ""))
		var text := String(entry.get("text", ""))
		var progress := clampf(float(entry.get("progress", 0.0)), 0.0, 1.0)
		var done := bool(entry.get("done", false))
		any = true
		var row := _mission_rows[i]
		var fresh := id != _mission_ids[i]
		if fresh:
			_mission_ids[i] = id
			_mission_labels[i].text = font_safe(text).to_upper()
			_mission_shown[i] = 0.0
			_mission_pct_shown[i] = -1
			_mission_done[i] = false
			_mission_bars[i].value = 0.0
			_mission_bars[i].modulate = UITheme.COLOR_ACCENT
			_mission_labels[i].add_theme_color_override("font_color", UITheme.COLOR_TEXT)
			_mission_pcts[i].add_theme_color_override("font_color",
				Color(UITheme.COLOR_TEXT_DIM, 0.95))
			_mission_marks[i].visible = false
			_mission_pcts[i].visible = true
			if not row.visible:
				row.visible = true
			_reveal_mission(i)
		_mission_target[i] = progress
		if done != _mission_done[i]:
			_mission_done[i] = done
			_set_mission_done(i, done)
			if done:
				_note_completed(text)
	if _mission_panel != null:
		_mission_panel.visible = any


## Finished treatment: the bar goes green and full, the percentage is replaced
## by a tick, and the row pops once so a goal met mid-run is noticed even in
## peripheral vision.
func _set_mission_done(index: int, done: bool) -> void:
	_mission_bars[index].modulate = COLOR_GOAL if done else UITheme.COLOR_ACCENT
	_mission_labels[index].add_theme_color_override("font_color",
		COLOR_GOAL if done else UITheme.COLOR_TEXT)
	_mission_marks[index].visible = done
	_mission_pcts[index].visible = not done
	if done:
		_mission_target[index] = 1.0
		_punch(_mission_rows[index], 1.10)


## New goal sliding into an occupied slot.
func _reveal_mission(index: int) -> void:
	var row := _mission_rows[index]
	if _headless or _reduced:
		row.modulate.a = 1.0
		return
	_kill_meta_tween(row, "_row_tween")
	row.modulate.a = 0.0
	var tween := row.create_tween()
	tween.tween_property(row, "modulate:a", 1.0, 0.28) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	row.set_meta("_row_tween", tween)


## A slot the caller stopped reporting: fade the row out rather than blanking
## the stack between sets.
func _retire_mission(index: int) -> void:
	if not _mission_rows[index].visible:
		return
	_mission_ids[index] = ""
	_mission_target[index] = 0.0
	_mission_done[index] = false
	var row := _mission_rows[index]
	if _headless or _reduced:
		row.visible = false
		return
	_kill_meta_tween(row, "_row_tween")
	var tween := row.create_tween()
	tween.tween_property(row, "modulate:a", 0.0, 0.20)
	tween.tween_callback(func() -> void:
		if _mission_ids[index] == "":
			row.visible = false)
	row.set_meta("_row_tween", tween)


func _note_completed(text: String) -> void:
	var clean := font_safe(text)
	if clean.is_empty():
		return
	for existing: String in _completed_missions:
		if existing.nocasecmp_to(clean) == 0:
			return
	_completed_missions.append(clean)


## --- Callouts ---------------------------------------------------------------

## Celebratory banner for a goal just met. Deliberately parked over the empty
## deck at the bottom rather than across the lane the player is reading, so it
## never costs them the obstacle they are about to hit.
func show_mission_complete(text: String) -> void:
	if _banner == null:
		return
	_note_completed(text)
	_banner_title.text = font_safe(text)
	_banner.visible = true
	if _headless:
		return
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	if _reduced:
		_banner.modulate.a = 1.0
		_banner.scale = Vector2.ONE
		_banner_tween = create_tween()
		_banner_tween.tween_interval(1.8)
		_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.4)
		_banner_tween.tween_callback(func() -> void: _banner.visible = false)
		return
	# Squash-and-stretch rather than a slide: the banner is anchor-positioned, so
	# tweening its `position` would fight _relayout and leave it displaced if a
	# second completion lands mid-flight. Scale moves it without touching layout.
	_banner.modulate.a = 0.0
	_banner.scale = Vector2(0.82, 0.35)
	_banner_tween = create_tween()
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.18)
	_banner_tween.tween_property(_banner, "scale", Vector2.ONE, 0.48) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.chain().tween_interval(1.7)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.34)
	_banner_tween.parallel().tween_property(_banner, "scale",
			Vector2(1.04, 0.55), 0.34) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_banner_tween.tween_callback(func() -> void:
		_banner.visible = false)


## One-shot red impact wash plus a kick on the lives pill. Separate from the
## danger veil so a hit taken with the wall already close still registers.
func flash_hit() -> void:
	if _hit_flash == null:
		return
	_kill_meta_tween(_hit_flash, "_flash_tween")
	var peak := 0.45 if _reduced else 0.92
	_hit_flash.modulate.a = peak
	var tween := _hit_flash.create_tween()
	tween.tween_property(_hit_flash, "modulate:a", 0.0, 0.55) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_hit_flash.set_meta("_flash_tween", tween)
	_punch(_lives_pill, 1.24)


## Speed streak intensity, 0..1. Called every frame; the shader uniform is only
## written when the ratio has moved enough to see, and the whole pass is hidden
## below a visible intensity so a slow opening costs nothing.
func set_speed_ratio(ratio: float) -> void:
	_speed_ratio = clampf(ratio, 0.0, 1.0)
	if _speed_material == null:
		return
	# Reduced motion keeps the cue (it is genuinely informative) but takes most
	# of the energy out of it.
	var intensity := pow(_speed_ratio, 0.70) * (0.30 if _reduced else 0.90)
	if absf(intensity - _speed_sent) < 0.012:
		return
	_speed_sent = intensity
	_speed_material.set_shader_parameter("intensity", intensity)
	var visible_now := intensity > 0.015
	if _speed_lines.visible != visible_now:
		_speed_lines.visible = visible_now


## Multiplier chip. `just_raised` is the caller telling the HUD that this is a
## reward, not a redraw: the chip pops, flashes, and the streaks turn gold.
func set_combo(multiplier: int, just_raised: bool) -> void:
	if _demo_blocks():
		return
	_apply_multiplier(multiplier, just_raised)


## Shared by set_stats and set_combo so the two cannot double-punch the chip on
## a frame where the caller uses both.
func _apply_multiplier(multiplier: int, punch: bool) -> void:
	if _multiplier_chip == null:
		return
	var hot := multiplier > 1
	if multiplier != _shown_multiplier:
		_shown_multiplier = multiplier
		_multiplier_label.text = "x%d" % multiplier
		_multiplier_chip.add_theme_stylebox_override("panel", _chip_hot if hot else _chip_quiet)
		_multiplier_label.add_theme_color_override("font_color",
			UITheme.COLOR_GOLD if hot else UITheme.COLOR_TEXT_DIM)
	# Streaks pick up the multiplier's colour, so a hot run literally changes
	# the colour of the screen edge.
	var gold := multiplier >= 3
	if gold != _speed_gold and _speed_material != null:
		_speed_gold = gold
		_speed_material.set_shader_parameter("tint",
			Vector3(1.0, 0.86, 0.52) if gold else Vector3(0.72, 0.90, 1.0))
	if not punch:
		return
	var frame := Engine.get_process_frames()
	if frame == _combo_frame:
		return
	_combo_frame = frame
	_punch(_multiplier_chip, 1.45)
	if _headless or _reduced:
		return
	_kill_meta_tween(_multiplier_chip, "_combo_tween")
	_multiplier_chip.modulate = Color(1.6, 1.5, 1.15)
	var tween := _multiplier_chip.create_tween()
	tween.tween_property(_multiplier_chip, "modulate", Color.WHITE, 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_multiplier_chip.set_meta("_combo_tween", tween)


## Brief centred callout ("Slide!", "x3"). Replaces whatever is on screen.
##
## Repeating the SAME text while the previous callout is still on screen is a
## no-op: the countdown feeds "3", "3", "3"… once a frame, and restarting the
## pop every frame would freeze the numeral at its overshoot scale.
func show_message(text: String) -> void:
	if _message_label == null:
		return
	var clean := font_safe(text)
	var running := _message_tween != null and _message_tween.is_valid()
	if running and clean == _message_text:
		return
	if running:
		_message_tween.kill()
	_message_tween = null
	_message_text = clean
	_message_label.text = clean
	_message_label.modulate = Color(UITheme.COLOR_GOLD, 1.0)
	_message_label.scale = Vector2.ONE
	if _headless:
		return
	_message_tween = create_tween()
	if not _reduced:
		_message_label.pivot_offset = _message_label.size * 0.5
		_message_label.scale = Vector2.ONE * 1.35
		_message_tween.tween_property(_message_label, "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_message_tween.tween_interval(0.75)
	_message_tween.tween_property(_message_label, "modulate:a", 0.0, 0.35)
	_message_tween.tween_callback(func() -> void:
		_message_label.text = ""
		_message_text = ""
		_message_label.modulate.a = 1.0)


## --- End of run -------------------------------------------------------------

## Full-screen end-of-run panel. `summary` carries `distance` (float metres),
## `fish` (int), `score` (int), `best` (int, the standing best BEFORE this run)
## and `is_new_best` (bool). An optional `missions` array of strings overrides
## the challenge list the HUD tracked during the run.
func show_game_over(summary: Dictionary) -> void:
	# Captured before hide_game_over, which clears the run-scoped list.
	var completed := _completed_missions.duplicate()
	if summary.has("missions"):
		completed = PackedStringArray()
		for entry: Variant in summary["missions"]:
			completed.append(font_safe(String(entry)))
	hide_game_over()
	var distance := float(summary.get("distance", 0.0))
	var fish := int(summary.get("fish", 0))
	var score := int(summary.get("score", 0))
	var best := int(summary.get("best", 0))
	var record := bool(summary.get("is_new_best", false))
	var tint := UITheme.COLOR_GOLD if record else Color(0.95, 0.97, 1.0)

	# The run is over: stop the in-run animation from fighting the panel.
	_veil_base = 0.0
	set_speed_ratio(0.0)

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
	var score_value := _add_stat_grid(column, distance, fish, score, tint)
	# The comparison line and the goals met land AFTER the count-up, so the
	# result reads as a sequence: here is the number, here is what it beat,
	# here is what you finished on the way.
	var footer := _add_footer(column, score, best, record)
	var goals := _add_mission_list(column, completed)
	column.add_child(UITheme.make_spacer(UITheme.SPACE_S))

	# Two choices, but not equal ones: Run Again is the whole point of a runner,
	# so it leads the row and wears the promoted face.
	_game_over_buttons = BoxContainer.new()
	_game_over_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_game_over_buttons.add_theme_constant_override("separation", UITheme.spacing(UITheme.SPACE_S))
	column.add_child(_game_over_buttons)
	var button_size := UITheme.scaled_size(Vector2(240.0, 60.0))
	var again := UITheme.make_primary_button("Run Again", button_size, UITheme.scaled_font(28))
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.hook_sounds(again)
	again.pressed.connect(func() -> void: restart_pressed.emit())
	_game_over_buttons.add_child(again)
	var to_menu := UITheme.make_button("Main Menu",
		UITheme.scaled_size(Vector2(200.0, 56.0)), UITheme.scaled_font(22))
	to_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.hook_sounds(to_menu)
	to_menu.pressed.connect(func() -> void: menu_pressed.emit())
	_game_over_buttons.add_child(to_menu)
	_relayout()

	if _headless:
		return
	again.grab_focus()
	AudioManager.play_sfx("sfx_victory" if record else "sfx_finish")
	_play_panel_entrance(card, score_value, score, record, footer, goals)


## Distance / Fish / Score, plus the standing best. On a record the best cell
## becomes the score the player just beat; otherwise it shows the gap still to
## close, which is the reason to press Run Again.
func _add_stat_grid(parent: Control, distance: float, fish: int, score: int,
		tint: Color) -> Label:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", UITheme.spacing(UITheme.SPACE_M))
	parent.add_child(row)
	row.add_child(UITheme.make_stat("%dm" % int(distance), "Distance"))
	row.add_child(UITheme.make_stat(str(fish), "Fish"))
	var score_stat := UITheme.make_stat(group_digits(score), "Score", tint)
	row.add_child(score_stat)
	return score_stat.get_child(0) as Label


## The line that lands after the count-up: what the run beat, or what it still
## has to beat. Returned so the entrance can hold it back.
func _add_footer(parent: Control, score: int, best: int, record: bool) -> Control:
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
	return footer


## Challenges finished during the run. A runner's session is a set of goals,
## not a distance, and listing them is what makes a short run still feel like
## it produced something.
func _add_mission_list(parent: Control, completed: PackedStringArray) -> Control:
	if completed.is_empty():
		return null
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", UITheme.spacing(4))
	parent.add_child(holder)
	holder.add_child(UITheme.make_divider())
	var title := UITheme.make_caption("Challenges Cleared", UITheme.FS_CAPTION,
		Color(COLOR_GOAL, 0.9))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(title)
	var check := UITheme.make_icon(CHECK_SVG, 0.45)
	# Four is all a phone panel can hold without scrolling past the buttons.
	for i: int in mini(completed.size(), 4):
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", UITheme.scaled_int(8))
		holder.add_child(row)
		if check != null:
			var icon := TextureRect.new()
			icon.texture = check
			icon.custom_minimum_size = Vector2(UITheme.scaled(16.0), UITheme.scaled(16.0))
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(icon)
		row.add_child(UITheme.make_caption(completed[i], UITheme.FS_CAPTION,
			Color(0.88, 0.96, 0.90)))
	if completed.size() > 4:
		holder.add_child(UITheme.make_caption(
			"+%d more" % (completed.size() - 4), UITheme.FS_CAPTION))
	return holder


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
	if _headless or _reduced:
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


## Panel entrance, choreographed as a result rather than as a screen: the card
## rises and fades in, the score counts up to its final value (a record gets a
## longer, louder count so the number itself is the celebration), and only then
## do the comparison line and the cleared challenges land. Reduced motion keeps
## the fade and drops the rest.
func _play_panel_entrance(card: Control, score_value: Label, score: int,
		record: bool, footer: Control, goals: Control) -> void:
	_game_over.modulate.a = 0.0
	var fade := _game_over.create_tween()
	fade.tween_property(_game_over, "modulate:a", 1.0, 0.22)
	if _reduced:
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

	var count_time := 1.1 if record else 0.7
	if score > 0 and score_value != null:
		score_value.text = "0"
		var count := score_value.create_tween()
		count.tween_method(_set_counted_score.bind(score_value),
				0.0, float(score), count_time) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		# The number is doing the celebrating, so it grows while it counts and
		# settles the instant it arrives.
		score_value.pivot_offset = score_value.size * 0.5
		score_value.resized.connect(func() -> void:
			score_value.pivot_offset = score_value.size * 0.5)
		var swell := score_value.create_tween()
		swell.tween_property(score_value, "scale", Vector2(1.16, 1.16), count_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		swell.tween_property(score_value, "scale", Vector2.ONE, 0.28) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		count_time = 0.0
	_land_after(footer, count_time + 0.10)
	_land_after(goals, count_time + 0.26)


## Holds a block invisible, then rises it into place. Used for the two lines
## that are only meaningful once the score has finished counting.
func _land_after(control: Control, delay: float) -> void:
	if control == null or not is_instance_valid(control):
		return
	control.modulate.a = 0.0
	var tween := control.create_tween()
	tween.tween_interval(delay)
	tween.tween_property(control, "modulate:a", 1.0, 0.26) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Count-up target for the end-of-run score tween.
func _set_counted_score(value: float, label: Label) -> void:
	if is_instance_valid(label):
		label.text = group_digits(int(value))


func hide_game_over() -> void:
	_game_over_buttons = null
	if _game_over != null and is_instance_valid(_game_over):
		_game_over.queue_free()
	_game_over = null


## --- QA feed ----------------------------------------------------------------

## Scripted stand-in for the game's own calls, used only when demo_feed is set
## (see the static above). It exercises the parts of the HUD an autopilot run
## cannot be relied on to produce — power-up rings, the completion banner, a
## hit — so visual QA is deterministic instead of luck.
func _demo_tick(delta: float) -> void:
	_demo_time += delta
	var t := _demo_time
	# Last act: close the avalanche so the escalation (colour, beat rate,
	# heartbeat vignette) can be judged from a still.
	if t > 15.0:
		_demo_gap = maxf(9.6 - (t - 15.0) * 1.7, 0.4)
	var steps: Array[float] = [1.2, 2.0, 3.0, 4.2, 5.0, 6.2, 7.4, 8.6, 9.6, 11.0,
		12.4, 13.6, 18.6]
	if _demo_step >= steps.size() or t < steps[_demo_step]:
		return
	_demo_driving = true
	match _demo_step:
		0:
			set_missions([
				{"id": "a", "text": "Collect 40 fish", "progress": 0.35, "done": false},
				{"id": "b", "text": "Run 1200 m", "progress": 0.12, "done": false},
				{"id": "c", "text": "5 near misses", "progress": 0.60, "done": false},
			])
		1:
			add_floater("+25", &"fish")
			set_powerups({RunnerConfig.POWERUP_MAGNET: 9.0})
		2:
			add_floater("MAGNET", &"powerup")
			set_combo(2, true)
		3:
			add_floater("CLOSE!", &"near_miss")
			set_powerups({RunnerConfig.POWERUP_MAGNET: 6.6,
				RunnerConfig.POWERUP_SHIELD: 9.0})
		4:
			add_floater("+50", &"fish")
			set_missions([
				{"id": "a", "text": "Collect 40 fish", "progress": 0.78, "done": false},
				{"id": "b", "text": "Run 1200 m", "progress": 0.44, "done": false},
				{"id": "c", "text": "5 near misses", "progress": 1.0, "done": true},
			])
		5:
			show_mission_complete("5 near misses")
			add_floater("MISSION", &"mission")
		6:
			set_powerups({RunnerConfig.POWERUP_SHIELD: 5.6,
				RunnerConfig.POWERUP_DOUBLE: 9.0})
			add_floater("DOUBLE POINTS", &"powerup")
		7:
			set_combo(4, true)
			add_floater("x4", &"score")
		8:
			flash_hit()
			add_floater("AIRBORNE", &"score")
		9:
			set_powerups({RunnerConfig.POWERUP_DOUBLE: 4.0})
			set_missions([
				{"id": "a", "text": "Collect 40 fish", "progress": 1.0, "done": true},
				{"id": "b", "text": "Run 1200 m", "progress": 0.82, "done": false},
				{"id": "c", "text": "5 near misses", "progress": 1.0, "done": true},
			])
		10:
			add_floater("+25", &"fish")
			add_floater("CLOSE!", &"near_miss")
		11:
			set_powerups({})
		12:
			show_game_over({
				"distance": 812.0, "fish": 63, "score": 4180,
				"best": 3950, "is_new_best": true,
			})
	_demo_driving = false
	_demo_step += 1
