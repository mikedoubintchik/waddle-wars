class_name RunnerHUD
extends CanvasLayer
## Waddle Run HUD: the headline card (distance + score), a supporting row of
## fish / multiplier / lives, the live challenge stack, the power-up rings, the
## bottom avalanche gauge, the reward floaters, the centred callout, and the
## end-of-run panel.
##
## Live HUD follows the expedition menus: painted ivory snow cards, navy
## Lilita One type, coral lives and authored ImageGen power-up sprites.
## Numbers, progress and touch ownership remain native controls.
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
signal pause_pressed
signal results_cover_changed(covered: bool)


## Raw touch ownership is local to this button. Owned drags/releases remain
## consumed while paused; new touches must reach controls on the pause overlay. A
## normal Button only receives mouse-emulated finger 0; RunnerTouch otherwise
## sees every unhandled finger as a gameplay gesture.
class PauseButton:
	extends Button

	var _touches: Dictionary = {}
	var _emulated_press: bool = false

	func _input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			var touch := event as InputEventScreenTouch
			if touch.pressed and not get_tree().paused and not disabled and is_visible_in_tree() \
					and get_global_rect().has_point(touch.position):
				_touches[touch.index] = true
				get_viewport().set_input_as_handled()
				pressed.emit()
			elif not touch.pressed and _touches.has(touch.index):
				_touches.erase(touch.index)
				get_viewport().set_input_as_handled()
		elif event is InputEventScreenDrag:
			if _touches.has((event as InputEventScreenDrag).index):
				get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton:
			var mouse := event as InputEventMouseButton
			if mouse.device == InputEvent.DEVICE_ID_EMULATION \
					and mouse.button_index == MOUSE_BUTTON_LEFT:
				if _emulated_press or (mouse.pressed and (not get_tree().paused or _touches.has(0)) \
						and not disabled \
						and is_visible_in_tree() and get_global_rect().has_point(mouse.position)):
					_emulated_press = mouse.pressed
					get_viewport().set_input_as_handled()
		elif event is InputEventMouseMotion and _emulated_press \
				and event.device == InputEvent.DEVICE_ID_EMULATION:
			get_viewport().set_input_as_handled()

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
const HEADLINE_ROW_WIDTH: float = 540.0
const HEADLINE_ROW_HEIGHT: float = 260.0
const HEADLINE_COLUMN_WIDTH: float = 320.0
const HEADLINE_COLUMN_HEIGHT: float = 380.0
## Narrowest a challenge stack may be squeezed before it is dropped below the
## headline instead. Under this it ellipsises every goal into uselessness.
const MISSION_MIN_WIDTH: float = 154.0

## --- Avalanche read ---------------------------------------------------------
## Gap at which the gauge starts warming toward red, and the gap at which the
## HUD commits to the full danger read (red veil, red numerals, pulsing tag).
const WARN_GAP: float = 18.0
const DANGER_GAP: float = 10.0
## Peak opacity of the screen-edge danger veil, reached as the gap hits zero.
const VEIL_ALPHA: float = 0.22
## Heartbeat rate (Hz) at the edge of danger and at nought metres. Kept well
## under the 3 Hz photosensitivity line even at its fastest, and the depth is
## a modulation of an already-visible wash rather than an on/off flash — but
## it still goes through the reduced-motion gate, because the *rate* change is
## the aggressive part.
const BEAT_SLOW: float = 1.25
const BEAT_FAST: float = 2.60
const GAUGE_WIDTH: float = 720.0
const GAUGE_HEIGHT: float = 42.0
## Fixed metre scale, so the same absolute gap always has the same visual length.
const GAUGE_DISPLAY_RANGE: float = 64.0

## Warning red, shared by the gauge fill, the metre readout and the veil.
const COLOR_DANGER: Color = Color(1.0, 0.36, 0.30)
## Mission-complete / goal-met green. Distinct from both the ice accent (which
## means "neutral information") and the gold (which means "score").
const COLOR_GOAL: Color = Color("21894f")
const INK: Color = ExpeditionMenuStyle.INK
const INK_MUTED: Color = ExpeditionMenuStyle.INK_MUTED
const ICE: Color = Color("168ed0")

## --- Floaters ---------------------------------------------------------------
## Pooled rising popups. Sixteen is comfortably more than a magnet sweep can
## fire inside one floater lifetime, and the pool is built once at setup so a
## pickup never allocates a node.
const FLOAT_POOL: int = 16
## Fixed label width so the text can be centre-aligned without measuring it.
const FLOAT_WIDTH: float = 460.0
const FISH_FLOATER_SIZE := Vector2(96.0, 64.0)
const FLOAT_RISE: float = 138.0
## Fraction of the viewport height the floaters spawn at: just above the
## penguin, so a reward lands where the player is already looking.
const FLOAT_ORIGIN_Y: float = 0.660

## --- Challenge stack --------------------------------------------------------
const MISSION_ROWS: int = 3
## Wide enough for the longest real goal line ("Dodge everything for 800 m")
## before the row ellipsises. _relayout clamps it back down when the viewport
## cannot spare the width.
const MISSION_PANEL_WIDTH: float = 460.0
const MISSION_BAR_HEIGHT: float = 16.0

## --- Power-up rings ---------------------------------------------------------
## Diameter of the draining ring, in logical units at hud_scale 1.
const RING_SIZE: float = 104.0

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
var _layout: LayoutProfile = null

var _headline_column: VBoxContainer = null
var _top_box: BoxContainer = null
var _top_divider: ColorRect = null
var _distance_label: Label = null
var _score_label: Label = null
var _fish_label: Label = null
var _fish_pill: PanelContainer = null
var _fish_counter_icon: TextureRect = null
var _indicator_applied_scale := -1.0
var _lives_pill: PanelContainer = null
var _life_pips: Array[Panel] = []
var _pip_alive: StyleBoxTexture = null
var _pip_spent: StyleBoxTexture = null
var _multiplier_chip: PanelContainer = null
var _multiplier_label: Label = null
var _chip_quiet: StyleBox = null
var _chip_hot: StyleBox = null
var _gauge_holder: PanelContainer = null
var _gauge_bar: ProgressBar = null
var _gauge_tag: Label = null
var _gauge_value: Label = null
var _danger_veil: TextureRect = null
var _hit_flash: TextureRect = null
var _speed_lines: ColorRect = null
var _speed_material: ShaderMaterial = null
var _message_label: Label = null
var _objective_label: Label = null
var _message_tween: Tween = null
var _message_text: String = ""
var _game_over: Control = null
var _game_over_buttons: BoxContainer = null
var _results_stage: Control = null
var _results_title: TextureRect = null
var _results_background: TextureRect = null
var _results_hero: TextureRect = null
var _results_art_space: Control = null
var _results_card: PanelContainer = null
var _results_summary: PanelContainer = null
var _results_inset_margin: MarginContainer = null
var _results_mission_labels: Array[Label] = []
var _pause_button: PauseButton = null

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
var _mission_amounts: PackedFloat32Array = PackedFloat32Array()
var _mission_goals: PackedFloat32Array = PackedFloat32Array()
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
var _float_badges: Array[Panel] = []
var _float_fish_icons: Array[TextureRect] = []
var _float_kinds: Array[StringName] = []
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
var _hud_view_size: Vector2 = Vector2(1920.0, 1080.0)
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
	_root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
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
	_build_pause()
	_build_floaters()
	_build_banner()
	_build_message()

	if not _headless:
		get_viewport().size_changed.connect(_relayout)
	_relayout()
	set_process(not _headless)
	_play_entrance()


func _build_pause() -> void:
	_pause_button = PauseButton.new()
	_pause_button.name = "PauseButton"
	_pause_button.text = ""
	_pause_button.accessibility_name = "Pause the run"
	_pause_button.icon = RunnerHUDArt.hud_sprite("pause")
	_pause_button.expand_icon = true
	_pause_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_button.add_theme_constant_override("icon_max_width", int(46.0 * _hud_scale))
	_pause_button.tooltip_text = "Pause the run"
	_pause_button.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_button.clip_text = true
	_pause_button.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	_pause_button.add_theme_font_size_override("font_size", int(20.0 * _hud_scale))
	_pause_button.add_theme_color_override("font_color", INK)
	var face := RunnerHUDArt.hud_panel("powerup", 20.0 * _hud_scale, 24.0 * _hud_scale, 14.0 * _hud_scale)
	_pause_button.add_theme_stylebox_override("normal", face)
	for state: String in ["hover", "pressed"]:
		var active := RunnerHUDArt.hud_panel("powerup", 20.0 * _hud_scale,
			24.0 * _hud_scale, 14.0 * _hud_scale,
			Color("fff0dd") if state == "hover" else Color("c4dded"))
		_pause_button.add_theme_stylebox_override(state, active)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color("59baff")
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(14)
	_pause_button.add_theme_stylebox_override("focus", focus)
	_pause_button.pressed.connect(func() -> void: pause_pressed.emit())
	_root.add_child(_pause_button)
	set_pause_available(false)


func set_pause_available(available: bool) -> void:
	if _pause_button == null:
		return
	_pause_button.disabled = not available
	_pause_button.visible = available


## Shares the headline/corner-stack budget with _relayout. The control never
## covers the headline; power-up rings reserve the following row underneath.
static func pause_rect_for_profile(profile: LayoutProfile, hud_scale: float = 1.0) -> Rect2:
	var fit := _reference_fit(profile.viewport_size)
	if fit < 0.999:
		var design := LayoutProfile.for_view_size(profile.viewport_size / fit, profile.safe_insets / fit)
		var authored := pause_rect_for_profile(design, hud_scale)
		var actual_size := (authored.size * fit).max(Vector2(56.0, 56.0)).min(profile.safe_rect.size)
		var actual_position := authored.position * fit
		actual_position.x = clampf(authored.end.x * fit - actual_size.x,
			profile.safe_rect.position.x, profile.safe_rect.end.x - actual_size.x)
		actual_position.y = clampf(actual_position.y,
			profile.safe_rect.position.y, profile.safe_rect.end.y - actual_size.y)
		return Rect2(actual_position, actual_size)
	var s := maxf(hud_scale, 0.1)
	var width := profile.viewport_size.x
	var safe := profile.safe_rect
	var margin := maxf(36.0 * s, maxf(profile.safe_insets.x, profile.safe_insets.z))
	var narrow := width < NARROW_WIDTH * s
	var headline_w := (HEADLINE_COLUMN_WIDTH if narrow else HEADLINE_ROW_WIDTH) * s
	var headline_h := (HEADLINE_COLUMN_HEIGHT if narrow else HEADLINE_ROW_HEIGHT) * s
	var side_room := (width - headline_w) * 0.5 - margin - GAP_M * s
	# Pause can use a narrower corner than the challenge card. Keep it beside
	# tall large-text headlines when the short viewport cannot fit it below.
	var stacked := side_room < 56.0
	var top := maxf((76.0 if profile.is_portrait() else 56.0) * s, profile.safe_insets.y) \
		+ (headline_h + GAP_M * s if stacked else 0.0)
	var button_width := maxf(112.0 * s, 56.0)
	if not stacked:
		button_width = minf(button_width, side_room)
	var button_size := Vector2(minf(button_width, safe.size.x),
		minf(maxf(104.0 * s, 56.0), safe.size.y))
	return Rect2(Vector2(
		clampf(width - margin - button_size.x, safe.position.x, safe.end.x - button_size.x),
		clampf(top, safe.position.y, safe.end.y - button_size.y)), button_size)


## Card face for a HUD panel. Uses the game's shared baked card texture, so a
## HUD card costs no bake and is the same material as every menu card; only the
## padding is tightened for the smaller surface.
func _card_style(pad_h: float, pad_v: float) -> StyleBox:
	return ExpeditionMenuStyle.material_card(pad_h, pad_v)


func _pill_style(_accent: Color, tint: Color = Color.WHITE, scale_override: float = -1.0) -> StyleBox:
	var s := scale_override if scale_override > 0.0 else _hud_scale
	return RunnerHUDArt.hud_panel("chip", 24.0 * s, 14.0 * s, 14.0 * s, tint)


func _indicator_scale() -> float:
	# Large accessibility HUDs use the column layout. Fit the supporting chip
	# row within that column without shrinking the user's primary score text.
	return _hud_scale * (0.64 if _hud_design_rect().x < NARROW_WIDTH * _hud_scale else 1.0)


func _value_label(text: String, size: float, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	label.add_theme_font_size_override("font_size", maxi(int(size), 1))
	label.add_theme_color_override("font_color", color)
	return label


func _caption_label(text: String, size: float, color: Color = INK_MUTED) -> Label:
	return _value_label(text.to_upper(), size, color)


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
	card.add_theme_stylebox_override("panel", RunnerHUDArt.hud_panel("gauge", 28.0 * s, 32.0 * s, 20.0 * s))
	_headline_column.add_child(card)

	# A bare BoxContainer, not an HBoxContainer: the H/V subclasses have their
	# orientation locked, and _relayout flips this one on narrow viewports.
	_top_box = BoxContainer.new()
	_top_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_top_box.add_theme_constant_override("separation", int(GAP_M * s))
	_top_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(_top_box)

	var view := _hud_design_rect()
	var stat_width := (200.0 if view.x < NARROW_WIDTH * s else (208.0 if view.y > view.x else 230.0)) * s
	_distance_label = _stat_pair(_top_box, "Distance", 66.0 * s, "0 m", stat_width)
	_top_divider = ColorRect.new()
	_top_divider.color = Color(ICE, 0.20)
	_top_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_box.add_child(_top_divider)
	_score_label = _stat_pair(_top_box, "Score", 66.0 * s, "0", stat_width,
		INK)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(16.0 * s))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_headline_column.add_child(row)
	_build_lives_pill(row)
	_build_fish_pill(row)
	_build_multiplier_chip(row)


## Value over caption, the atom the headline card is built from. The value gets
## a floor width so the card does not twitch as digits are gained.
func _stat_pair(parent: Control, caption: String, value_size: float,
		value_text: String, min_width: float, color: Color = INK) -> Label:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(stack)
	var value := _value_label(value_text, value_size, color)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.custom_minimum_size = Vector2(min_width, 0.0)
	stack.add_child(value)
	var cap := _caption_label(caption, 21.0 * _hud_scale)
	cap.add_theme_font_override("font", UITheme.caption_font())
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(cap)
	return value


## Hits-left indicator: one chunky pip per RunnerConfig.MAX_HITS, lit while the
## hit is still available. Reads as "how many more mistakes do I get" at a
## glance, which a bare number does not.
func _build_lives_pill(parent: Control) -> void:
	var s := _indicator_scale()
	_lives_pill = PanelContainer.new()
	_lives_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lives_pill.add_theme_stylebox_override("panel", _pill_style(ICE, Color.WHITE, s))
	parent.add_child(_lives_pill)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(maxf(5.0 * s, 3.0)))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lives_pill.add_child(row)
	var pip := Vector2(44.0, 38.0) * s
	_pip_alive = StyleBoxTexture.new()
	_pip_alive.texture = RunnerHUDArt.hud_sprite("heart")
	_pip_spent = _pip_alive.duplicate() as StyleBoxTexture
	_pip_spent.texture = RunnerHUDArt.hud_sprite("heart_spent")
	for i: int in RunnerConfig.MAX_HITS:
		var dot := Panel.new()
		dot.custom_minimum_size = pip
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.add_theme_stylebox_override("panel", _pip_alive)
		row.add_child(dot)
		_life_pips.append(dot)


## Fish counter. Same drawn glyph as the racing HUD and the menu currency chip,
## so a fish means one thing everywhere in the game.
func _build_fish_pill(parent: Control) -> void:
	var s := _indicator_scale()
	var pill := PanelContainer.new()
	_fish_pill = pill
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_theme_stylebox_override("panel", _pill_style(ICE, Color.WHITE, s))
	parent.add_child(pill)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(maxf(7.0 * s, 4.0)))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(row)
	var texture := RunnerHUDArt.hud_sprite("fish")
	if texture != null:
		var icon := TextureRect.new()
		_fish_counter_icon = icon
		icon.texture = texture
		icon.custom_minimum_size = Vector2(52.0 * s, 40.0 * s)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
	else:
		# SVG module unavailable: an ASCII stand-in still reads, where a Unicode
		# fish would be a .notdef box in the bundled font.
		var glyph := _value_label("><>", 18.0 * s, ICE)
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(glyph)
	_fish_label = _value_label("0", 44.0 * s)
	_fish_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_fish_label)


## Score multiplier. Stays quiet at x1 and turns gold the moment clean running
## has actually earned something, so the chip is its own reward signal.
func _build_multiplier_chip(parent: Control) -> void:
	var s := _indicator_scale()
	_chip_quiet = _pill_style(ICE, Color.WHITE, s)
	_chip_hot = _pill_style(UITheme.COLOR_GOLD, Color("ffdc91"), s)
	_multiplier_chip = PanelContainer.new()
	_multiplier_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_multiplier_chip.add_theme_stylebox_override("panel", _chip_quiet)
	parent.add_child(_multiplier_chip)
	_multiplier_label = _value_label("x1", 44.0 * s, INK_MUTED)
	_multiplier_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_multiplier_label.custom_minimum_size = Vector2(60.0 * s, 0.0)
	_multiplier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_multiplier_chip.add_child(_multiplier_label)


## Avalanche gauge (bottom centre): the cushion of track between the player and
## the wall, draining as it closes. A draining bar plus a falling metre count
## says "you are losing ground" without needing to be read.
func _build_gauge() -> void:
	var s := _hud_scale
	var bar_h := GAUGE_HEIGHT * s
	_gauge_holder = PanelContainer.new()
	# The sprite's snow crest and curved rim are decoration, not text space.
	_gauge_holder.add_theme_stylebox_override("panel", RunnerHUDArt.hud_panel("gauge", 60.0 * s, 40.0 * s, 24.0 * s))
	_gauge_holder.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_gauge_holder.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_gauge_holder.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_gauge_holder.offset_bottom = -GUTTER * s

	_gauge_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_gauge_holder)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(8.0 * s))
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge_holder.add_child(column)
	var caption := HBoxContainer.new()
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(caption)
	_gauge_tag = _caption_label("Avalanche Gap", 24.0 * s, INK)
	_gauge_tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gauge_tag.clip_text = true
	_gauge_tag.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	caption.add_child(_gauge_tag)
	_gauge_value = _caption_label("", 24.0 * s, INK)
	# The countdown freezes the chaser at its real starting gap. Seed that
	# distance here, before the first running tick feeds set_stats.
	_shown_gap = maxi(int(RunnerConfig.CHASER_BASE_GAP), 0)
	_gauge_value.text = "%d m BEHIND" % _shown_gap
	_gauge_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caption.add_child(_gauge_value)

	# Recessed channel: darker than the scene with a thin rim, so the fill reads
	# as sitting inside the screen rather than pasted onto it.
	var groove := Panel.new()
	groove.custom_minimum_size = Vector2(0.0, bar_h)
	groove.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var groove_style := StyleBoxFlat.new()
	groove_style.bg_color = Color("c5c8ca")
	groove_style.border_color = Color("99a0a7")
	groove_style.set_border_width_all(2)
	groove_style.set_corner_radius_all(roundi(bar_h * 0.5))
	groove_style.anti_aliasing = true
	groove.add_theme_stylebox_override("panel", groove_style)
	column.add_child(groove)

	var inset := maxf(3.0 * s, 2.0)
	_gauge_bar = ProgressBar.new()
	_gauge_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gauge_bar.offset_left = inset
	_gauge_bar.offset_top = inset
	_gauge_bar.offset_right = -inset
	_gauge_bar.offset_bottom = -inset
	_gauge_bar.max_value = 1.0
	_gauge_bar.step = 0.0
	_gauge_bar.value = RunnerConfig.CHASER_BASE_GAP / GAUGE_DISPLAY_RANGE
	_gauge_bar.show_percentage = false
	_gauge_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge_bar.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	# One neutral fill, tinted through modulate. Re-baking a gradient stylebox as
	# the danger ramps would be a texture upload per frame; a Color write is free.
	_gauge_bar.add_theme_stylebox_override("fill", RunnerHUDArt.hud_panel("ice_fill", 0.0, 0.0, 0.0))
	_gauge_bar.modulate = Color.WHITE
	_gauge_bar.step = 0.0
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


## Submit the real Canvas shader before gameplay. The 3D warmup passes cannot
## discover it while this ColorRect is hidden. Zero intensity discards every
## fragment, but the visible, nontransparent rectangle still submits its real
## shader/material. Preserve HUD state; this is called while countdown is held.
func warm_render_resources() -> void:
	if _headless or not is_inside_tree() or _speed_material == null \
			or not is_instance_valid(_speed_lines):
		return
	var lines := _speed_lines
	var material := _speed_material
	var was_visible := lines.visible
	var prior_intensity: Variant = material.get_shader_parameter("intensity")
	material.set_shader_parameter("intensity", 0.0)
	lines.visible = true
	await RenderingServer.frame_post_draw
	# A cancelled scene may detach the HUD or free its rectangle during the
	# await. Restore any surviving resources without touching the gameplay cache.
	material.set_shader_parameter("intensity", prior_intensity)
	if is_instance_valid(lines):
		lines.visible = was_visible


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
	_mission_panel.add_theme_stylebox_override("panel", RunnerHUDArt.hud_panel("card", 28.0 * s, 42.0 * s, 22.0 * s))
	_mission_panel.visible = false
	_root.add_child(_mission_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(maxf(GAP_S * s, 4.0)))
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mission_panel.add_child(column)

	var head := _caption_label("Challenges", 36.0 * s, INK)
	column.add_child(head)

	# One baked fill for all three bars; the per-row colour is a modulate write.
	var fill := UITheme.make_bar_fill(Color("099c2c"), Color("64ed56"))
	var check := UITheme.make_icon(CHECK_SVG, 0.6)
	for i: int in MISSION_ROWS:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", int(maxf(2.0 * s, 1.0)))
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.visible = false
		var row_face := PanelContainer.new()
		var inset := StyleBoxFlat.new()
		inset.bg_color = Color("eeeae2")
		inset.border_color = Color(1.0, 1.0, 1.0, 0.88)
		inset.border_width_top = 2
		inset.set_corner_radius_all(int(18.0 * s))
		inset.content_margin_top = 9.0 * s
		inset.content_margin_left = 12.0 * s
		inset.content_margin_right = 12.0 * s
		inset.content_margin_bottom = 9.0 * s
		row_face.add_theme_stylebox_override("panel", inset)
		column.add_child(row_face)
		row_face.add_child(row)

		var head_row := BoxContainer.new()
		head_row.add_theme_constant_override("separation", int(maxf(6.0 * s, 3.0)))
		head_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(head_row)
		head_row.resized.connect(_fit_mission_row.bind(i))

		var text := _caption_label("", 26.0 * s, INK)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.clip_text = false
		# WORD_SMART can split even the non-breaking distance/unit token when a
		# growing counter narrows its sibling. Keep whole words; the measured
		# layout below moves that counter onto its own line before it can squeeze.
		text.autowrap_mode = TextServer.AUTOWRAP_WORD
		text.max_lines_visible = -1
		# Wrapped labels have no useful minimum height while their HBox is
		# negotiating width. Reserve a readable first line, then grow for the full title.
		text.custom_minimum_size.y = 32.0 * s
		text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		text.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		head_row.add_child(text)

		var pct := _caption_label("0 / 0", 24.0 * s, INK)
		pct.size_flags_vertical = Control.SIZE_SHRINK_END
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		# Leave the painted card's rounded inner edge clear at large counters.
		pct.add_theme_constant_override("outline_size", 0)
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
		_mission_amounts.append(0.0)
		_mission_goals.append(0.0)
		_mission_done.append(false)


## Large real totals must not squeeze an indivisible distance/unit into the
## counter. Keep the normal reference row, moving its count below only when
## the longest intact title word cannot fit beside that exact count.
func _fit_mission_row(index: int) -> void:
	if index >= _mission_labels.size(): return
	var title := _mission_labels[index]
	var metric := _mission_pcts[index]
	var head := title.get_parent() as BoxContainer
	if head.size.x <= 0.0: return
	var font := title.get_theme_font("font")
	var font_size := title.get_theme_font_size("font_size")
	var title_width := font.get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	# Query current text, not the Label's cached minimum before container sort.
	# This matters at 999 -> 1,000 while the parent itself keeps the same width.
	var side_width := metric.get_theme_font("font").get_string_size(metric.text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, metric.get_theme_font_size("font_size")).x if metric.visible else 0.0
	if _mission_marks[index].visible: side_width += _mission_marks[index].get_combined_minimum_size().x
	var stack := title_width + side_width + head.get_theme_constant("separation") + 8.0 > head.size.x
	if head.vertical != stack: head.vertical = stack
	metric.size_flags_horizontal = Control.SIZE_SHRINK_END if stack else Control.SIZE_FILL


## Recessed thin channel with a progress fill inside it, the same material as
## the avalanche gauge one size down.
func _thin_bar(height: float, fill: StyleBoxTexture) -> Panel:
	var groove := Panel.new()
	groove.custom_minimum_size = Vector2(0.0, height)
	groove.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	groove.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("bfc3c6")
	style.set_corner_radius_all(maxi(int(height * 0.5), 2))
	style.set_border_width_all(1)
	style.border_color = Color("a4a7aa")
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
	bar.step = 0.0
	bar.value = 0.0
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	bar.add_theme_stylebox_override("fill", fill)
	bar.modulate = COLOR_GOAL
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
	_powerup_box.add_theme_constant_override("separation", int(14.0 * s))
	_powerup_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_powerup_box)
	var ring_px := maxi(int(96.0 * s), 20)
	for id: StringName in RunnerConfig.POWERUP_IDS:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(128.0 * s, 136.0 * s)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_theme_stylebox_override("panel", RunnerHUDArt.hud_panel("powerup", 9.0 * s, 18.0 * s, 8.0 * s))
		slot.visible = false
		slot.modulate.a = 0.0
		_powerup_box.add_child(slot)
		var face := Control.new()
		face.custom_minimum_size = Vector2(RING_SIZE, RING_SIZE) * s
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(face)
		var ring := TextureProgressBar.new()
		ring.position = Vector2(4.0, 6.0) * s
		ring.texture_under = _ring_tex(ring_px)
		ring.texture_progress = _ring_tex(ring_px)
		ring.tint_under = Color(0.68, 0.73, 0.73, 0.5)
		ring.tint_progress = Color.WHITE
		ring.fill_mode = TextureProgressBar.FILL_CLOCKWISE
		ring.radial_initial_angle = 45.0
		ring.radial_fill_degrees = 270.0
		ring.max_value = 1.0
		ring.step = 0.0
		ring.value = 1.0
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.add_child(ring)
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.texture = _powerup_icon(id)
		icon.position = Vector2(18.0, 4.0) * s
		icon.size = Vector2(68.0, 76.0) * s
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.add_child(icon)
		var timer_chip := PanelContainer.new()
		timer_chip.position = Vector2(54.0, 72.0) * s
		timer_chip.custom_minimum_size = Vector2(50.0, 32.0) * s
		var timer_style := _pill_style(INK)
		timer_style.content_margin_left = 6.0 * s
		timer_style.content_margin_right = 6.0 * s
		timer_style.content_margin_top = 1.0 * s
		timer_style.content_margin_bottom = 1.0 * s
		timer_chip.add_theme_stylebox_override("panel", timer_style)
		timer_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.add_child(timer_chip)
		var time_label := _caption_label("0s", 24.0 * s, INK)
		time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		timer_chip.add_child(time_label)
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


func _powerup_icon(id: StringName) -> Texture2D:
	return RunnerHUDArt.hud_sprite(String(id))


## White annulus, baked once per pixel size. Tinted per power-up through
## TextureProgressBar's tint_under / tint_progress, so all three rings share
## one texture.
static func _ring_tex(px: int) -> ImageTexture:
	if _ring_textures.has(px):
		return _ring_textures[px] as ImageTexture
	var img := Image.create_empty(px, px, false, Image.FORMAT_RGBA8)
	var centre := float(px) * 0.5 - 0.5
	var outer := float(px) * 0.5 - 1.0
	var inner := outer - maxf(float(px) * 0.060, 2.0)
	for y: int in px:
		for x: int in px:
			var d := Vector2(float(x) - centre, float(y) - centre).length()
			var a := clampf(outer - d + 0.5, 0.0, 1.0) * clampf(d - inner + 0.5, 0.0, 1.0)
			var color := Color("25ae54").lerp(Color("4faee6"), float(x) / maxf(float(px - 1), 1.0))
			color.a = a
			img.set_pixel(x, y, color)
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
	var fish_texture := RunnerHUDArt.sprite("fish")
	for i: int in FLOAT_POOL:
		var label := _value_label("", 30.0 * s, INK)
		label.add_theme_constant_override("outline_size", int(5.0 * s))
		label.add_theme_color_override("font_outline_color", INK)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size = Vector2(width, 52.0 * s)
		label.pivot_offset = label.size * 0.5
		label.visible = false
		_float_root.add_child(label)
		var badge := Panel.new()
		badge.show_behind_parent = true
		badge.position = Vector2((width - 182.0 * s) * 0.5, 1.0 * s)
		badge.size = Vector2(182.0 * s, 49.0 * s)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_stylebox_override("panel", _pill_style(ICE))
		badge.visible = false
		label.add_child(badge)
		_float_badges.append(badge)
		var fish_icon := TextureRect.new()
		# Disable native texture minima before assigning the painted sprite;
		# otherwise its source dimensions override this small reward glyph.
		fish_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fish_icon.texture = fish_texture
		fish_icon.position = Vector2((width - FISH_FLOATER_SIZE.x * s) * 0.5, 0.0)
		fish_icon.size = FISH_FLOATER_SIZE * s
		fish_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		fish_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fish_icon.visible = false
		label.add_child(fish_icon)
		_float_fish_icons.append(fish_icon)
		_float_labels.append(label)
		_float_kinds.append(&"")
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
	(_banner as PanelContainer).add_theme_stylebox_override("panel", _card_style(24.0 * s, 12.0 * s))
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
	column.add_child(_caption_label("Challenge Complete", 18.0 * s, COLOR_GOAL))
	_banner_title = _value_label("", 26.0 * s, INK)
	column.add_child(_banner_title)


## Centred callout ("Slide!", "x3"). Spans most of the width and wraps, so a
## long line is legible on a portrait phone instead of running off both edges.
func _build_message() -> void:
	_message_label = _value_label("", 72.0 * _hud_scale, ExpeditionMenuStyle.CORAL)
	_message_label.anchor_left = 0.05
	_message_label.anchor_right = 0.95
	_message_label.anchor_top = 0.38
	_message_label.anchor_bottom = 0.38
	_message_label.offset_left = 0.0
	_message_label.offset_right = 0.0
	_message_label.offset_top = 0.0
	_message_label.offset_bottom = 0.0
	_message_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.add_theme_constant_override("outline_size", int(7.0 * _hud_scale))
	_message_label.add_theme_color_override("font_outline_color", ExpeditionMenuStyle.IVORY)
	_message_label.add_theme_color_override("font_shadow_color", INK)
	_message_label.add_theme_constant_override("shadow_offset_y", int(5.0 * _hud_scale))
	_root.add_child(_message_label)

	# A quiet objective under the countdown makes the chase explicit before
	# the player moves. Built once, then shares the callout's existing fade.
	_objective_label = _value_label("Stay ahead of the avalanche", 24.0 * _hud_scale)
	_objective_label.add_theme_constant_override("outline_size", int(6.0 * _hud_scale))
	_objective_label.add_theme_color_override("font_outline_color", ExpeditionMenuStyle.IVORY)
	_objective_label.name = "RunnerObjective"
	_objective_label.anchor_left = 0.0
	_objective_label.anchor_right = 1.0
	_objective_label.anchor_top = 0.38
	_objective_label.anchor_bottom = 0.38
	_objective_label.offset_top = 72.0 * _hud_scale
	_objective_label.offset_bottom = 72.0 * _hud_scale
	# Wrapping grows downward, so a narrow portrait line never covers the count.
	_objective_label.grow_vertical = Control.GROW_DIRECTION_END
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_label.hide()
	_root.add_child(_objective_label)


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
	var fit := _reference_fit(_view_size)
	_hud_view_size = _view_size / fit
	_root.size = _hud_view_size
	_root.scale = Vector2.ONE * fit
	var width := _hud_view_size.x
	var s := _hud_scale
	var actual_profile := UITheme.layout_profile(_root) if _root != null \
		else LayoutProfile.for_view_size(_view_size)
	_layout = LayoutProfile.for_view_size(_hud_view_size, actual_profile.safe_insets / fit)
	var safe_x := maxf(_layout.safe_insets.x, _layout.safe_insets.z)
	var safe_top := _layout.safe_insets.y
	var safe_bottom := _layout.safe_insets.w
	var narrow := width < NARROW_WIDTH * s
	if _distance_label != null:
		var stat_width := (200.0 if narrow else (208.0 if _layout.is_portrait() else 230.0)) * s
		_distance_label.custom_minimum_size.x = stat_width
		_score_label.custom_minimum_size.x = stat_width
	_resize_indicators()
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
	var margin := maxf(36.0 * s, safe_x)
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
	var top_margin := maxf((76.0 if _layout.is_portrait() else 56.0) * s, safe_top)
	var side_room := (width - headline_w) * 0.5 - margin - GAP_M * s
	var stacked := side_room < maxf(ring_width, MISSION_MIN_WIDTH * s)
	if _headline_column != null:
		var centre := 0.605 if _layout.is_portrait() and not narrow and not stacked else 0.5
		_headline_column.anchor_left = centre
		_headline_column.anchor_right = centre
		_headline_column.offset_top = top_margin
	var corner_top := top_margin + (headline_h + GAP_M * s if stacked else 0.0)
	var actual_pause := pause_rect_for_profile(actual_profile, s)
	var pause_rect := Rect2(actual_pause.position / fit, actual_pause.size / fit)
	if _headline_column != null and _layout.is_portrait() and not narrow and not stacked:
		var clear_center := minf(0.605, (pause_rect.position.x - GAP_M * s - headline_w * 0.5) / width)
		_headline_column.anchor_left = clear_center
		_headline_column.anchor_right = clear_center
	var mission_room := (usable - maxf(ring_width, pause_rect.size.x) - GAP_M * s) \
		if stacked else side_room
	if _layout.is_portrait() and not narrow and not stacked:
		mission_room = width * 0.325 - margin
	if _pause_button != null:
		_pause_button.position = pause_rect.position
		_pause_button.custom_minimum_size = pause_rect.size
		_pause_button.size = pause_rect.size
	if _powerup_box != null:
		_powerup_box.vertical = _layout.is_portrait() or width < 1200.0 * s
		_powerup_box.offset_right = -margin
		_powerup_box.offset_top = pause_rect.end.y + GAP_M * s
	if _mission_panel != null:
		_mission_panel.offset_left = margin
		_mission_panel.offset_top = corner_top if stacked else maxf(44.0 * s, safe_top)
		_mission_panel.custom_minimum_size.x = clampf(
			MISSION_PANEL_WIDTH * s, 110.0, maxf(mission_room, 110.0))
		# The reference phone rows keep the full title and real counter together.
		# Desktop-sized counter text was taking half the phone row and leaving
		# single units on another line. Limit this adjustment to challenge text.
		for index: int in _mission_labels.size():
			_mission_labels[index].add_theme_font_size_override("font_size", roundi((22.0 if _layout.is_portrait() else 26.0) * s))
			_mission_pcts[index].add_theme_font_size_override("font_size", roundi((18.0 if _layout.is_portrait() else 24.0) * s))
			_fit_mission_row(index)
	if _banner != null:
		# Leave a visible gap above the thicker sculpted gauge and its snow cap.
		_banner.offset_bottom = -(maxf((124.0 if _layout.is_portrait() else 42.0) * s, safe_bottom) + 140.0 * s)
	if _gauge_holder != null:
		_gauge_holder.offset_bottom = -maxf((124.0 if _layout.is_portrait() else 42.0) * s, safe_bottom)
	if _message_label != null:
		var anchor := 0.42 if narrow else 0.38
		_message_label.anchor_top = anchor
		_message_label.anchor_bottom = anchor
		if _objective_label != null:
			_objective_label.anchor_top = anchor
			_objective_label.anchor_bottom = anchor
			_objective_label.offset_left = margin
			_objective_label.offset_right = -margin
	if _speed_material != null and _view_size.y > 0.0:
		_speed_material.set_shader_parameter("aspect", _view_size.x / _view_size.y)
	if _game_over_buttons != null:
		_game_over_buttons.vertical = true
	_relayout_results()


func _resize_indicators() -> void:
	var s := _indicator_scale()
	if is_equal_approx(s, _indicator_applied_scale) or _lives_pill == null or _fish_pill == null:
		return
	_indicator_applied_scale = s
	_lives_pill.add_theme_stylebox_override("panel", _pill_style(ICE, Color.WHITE, s))
	_fish_pill.add_theme_stylebox_override("panel", _pill_style(ICE, Color.WHITE, s))
	_chip_quiet = _pill_style(ICE, Color.WHITE, s)
	_chip_hot = _pill_style(UITheme.COLOR_GOLD, Color("ffdc91"), s)
	_multiplier_chip.add_theme_stylebox_override("panel", _chip_hot if _shown_multiplier > 1 else _chip_quiet)
	for pip: Panel in _life_pips:
		pip.custom_minimum_size = Vector2(44.0, 38.0) * s
	if _fish_counter_icon != null:
		_fish_counter_icon.custom_minimum_size = Vector2(52.0, 40.0) * s
	_fish_label.add_theme_font_size_override("font_size", maxi(roundi(44.0 * s), 1))
	_multiplier_label.add_theme_font_size_override("font_size", maxi(roundi(44.0 * s), 1))
	_multiplier_label.custom_minimum_size.x = 60.0 * s


## Rotation changes composition in place: score, focus, and completed challenges
## remain the same nodes, so resizing cannot restart a count-up or lose input.
func _relayout_results() -> void:
	if _game_over == null or _results_card == null:
		return
	var portrait := _view_size.y >= _view_size.x
	var result_unit := (_view_size.x / 1080.0) if portrait else (_view_size.y / 1080.0)
	_scale_result_layout(_results_card, result_unit)
	(_results_inset_margin.get_parent() as VBoxContainer).alignment = BoxContainer.ALIGNMENT_BEGIN if portrait else BoxContainer.ALIGNMENT_END
	_results_inset_margin.add_theme_constant_override("margin_bottom", roundi(_view_size.y * 0.04) if not portrait else 16)
	if _results_background != null:
		_results_background.texture = RunnerHUDArt.caught_background(portrait)
	_results_stage.visible = not portrait
	_results_art_space.visible = portrait
	# Reserve the actual card height first. At the touch layout's 792x1408
	# logical size, a fixed 43% hero spacer hid Base Camp below the first view.
	var card_height := _results_card.get_combined_minimum_size().y
	_results_art_space.custom_minimum_size.y = minf(_view_size.y * 0.50,
		maxf(0.0, _view_size.y - card_height - 64.0)) if portrait else 0.0
	_results_title.anchor_top = 0.05 if portrait else 0.02
	_results_title.anchor_left = 0.08 if portrait else 0.035
	_results_title.anchor_right = 0.92 if portrait else 0.47
	_results_title.anchor_bottom = 0.28 if portrait else 0.40
	_results_card.custom_minimum_size.x = _view_size.x * (0.90 if portrait else 0.42)
	_results_inset_margin.add_theme_constant_override("margin_right", 16 if portrait else roundi(_view_size.x * 0.08))
	if not _results_summary.has_meta("portrait") or _results_summary.get_meta("portrait", not portrait) != portrait \
			or not is_equal_approx(float(_results_summary.get_meta("result_unit", 0.0)), result_unit):
		_results_summary.set_meta("portrait", portrait)
		_results_summary.set_meta("result_unit", result_unit)
		_results_summary.add_theme_stylebox_override("panel", StyleBoxEmpty.new() if portrait else ExpeditionMenuStyle.material_card(16.0 * result_unit, 16.0 * result_unit))
	for label: Label in _results_mission_labels:
		# Separate full labels remain readable after rotation; no joined summary,
		# ellipsis, or fixed line cap can hide a completed challenge.
		var font_size := roundi(28.0 * result_unit)
		if label.get_theme_font_size("font_size") != font_size:
			label.add_theme_font_size_override("font_size", font_size)
		label.custom_minimum_size.y = 34.0 * result_unit


## Scale the authored results layout against its logical reference width, not
## global UI touch scaling. Keep nodes/data/focus intact when rotating.
func _scale_result_layout(node: Control, unit: float) -> void:
	if node.name == "CompletedMissionText":
		return # Its full-label metrics are orientation-specific immediately above.
	if not node.has_meta("results_design_min"):
		node.set_meta("results_design_min", node.custom_minimum_size)
		var metrics := {}
		for key: String in ["separation", "margin_left", "margin_right", "margin_top", "margin_bottom"]:
			if node.has_theme_constant_override(key): metrics[key] = node.get_theme_constant(key)
		node.set_meta("results_design_constants", metrics)
		if node.has_theme_font_size_override("font_size"):
			node.set_meta("results_design_font", node.get_theme_font_size("font_size"))
		if node != _results_summary and node.has_theme_stylebox_override("panel"):
			# Each result panel already owns its style. Resource.duplicate() loses
			# the custom painted surface's non-exported texture/region properties.
			var panel := node.get_theme_stylebox("panel")
			node.set_meta("results_design_padding", Vector4(panel.content_margin_left, panel.content_margin_top,
				panel.content_margin_right, panel.content_margin_bottom))
		if node.name == "IllustratedAction":
			node.set_meta("results_design_offsets", Vector2(node.offset_left, node.offset_right))
	if node != _results_card:
		var minimum: Vector2 = node.get_meta("results_design_min")
		if not node.custom_minimum_size.is_equal_approx(minimum * unit): node.custom_minimum_size = minimum * unit
	for key: String in node.get_meta("results_design_constants"):
		var value := roundi(float(node.get_meta("results_design_constants")[key]) * unit)
		if node.get_theme_constant(key) != value: node.add_theme_constant_override(key, value)
	if node.has_meta("results_design_font"):
		var font_size := maxi(1, roundi(float(node.get_meta("results_design_font")) * unit))
		if node.get_theme_font_size("font_size") != font_size: node.add_theme_font_size_override("font_size", font_size)
	if node.has_meta("results_design_padding"):
		var padding: Vector4 = node.get_meta("results_design_padding")
		var panel := node.get_theme_stylebox("panel")
		for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			var value := padding[[SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM].find(side)]
			# Snow corners keep a fixed logical radius, while phone text scales
			# down. Reserve the painted ivory interior for portrait captions.
			if side == SIDE_TOP and _view_size.y >= _view_size.x:
				if node.name == "ResultsScorePanel": value = 36.0
				elif String(node.name).begins_with("ResultsStatPanel"): value = 28.0
			if value >= 0.0 and not is_equal_approx(panel.get_content_margin(side), value * unit):
				panel.set_content_margin(side, value * unit)
	if node.has_meta("results_design_offsets"):
		var offsets: Vector2 = node.get_meta("results_design_offsets")
		node.offset_left = offsets.x * unit
		node.offset_right = offsets.y * unit
	for child: Node in node.get_children():
		if child is Control: _scale_result_layout(child, unit)


static func _reference_fit(size: Vector2) -> float:
	# Touch menus use a smaller logical canvas. Keep the authored in-run
	# composition stable without changing SettingsManager or result layouts.
	return minf(size.x / 1080.0, 1.0) if size.y > size.x else 1.0


func _hud_design_rect() -> Vector2:
	var actual := _view_rect()
	return actual / maxf(_reference_fit(actual), 0.001)


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

	_gauge_bar.value = clampf(chaser_gap / GAUGE_DISPLAY_RANGE, 0.0, 1.0)
	_danger_gap = chaser_gap
	# Curved rather than linear, and deliberately back-loaded: the wash stays a
	# hint through the half of the window the player can still run out of, and
	# keeps the course readable even in the last few metres. The gap meter and
	# label carry the urgent warning; the edge wash remains a supporting cue.
	_veil_base = pow(clampf((DANGER_GAP - chaser_gap) / DANGER_GAP, 0.0, 1.0), 1.25) \
		* VEIL_ALPHA
	var gap_m := maxi(int(chaser_gap), 0)
	if gap_m != _shown_gap:
		_shown_gap = gap_m
		_gauge_value.text = "%d m BEHIND" % gap_m
		# Colour is re-derived on the metre tick rather than every frame: a
		# theme override is a dictionary write, the gauge value is not.
		var heat := clampf((WARN_GAP - chaser_gap) / maxf(WARN_GAP - DANGER_GAP, 0.001), 0.0, 1.0)
		var tint := ICE.lerp(COLOR_DANGER, heat)
		_gauge_bar.modulate = Color.WHITE.lerp(Color(1.0, 0.54, 0.48), heat)
		_gauge_value.add_theme_color_override("font_color",
			tint if heat > 0.0 else INK)

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
		COLOR_DANGER if danger else INK_MUTED)
	_gauge_tag.text = "AVALANCHE CLOSE!" if danger else "AVALANCHE GAP"
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
		if _float_kinds[i] == &"fish":
			# Fish goes into fish counter; score already counts up separately.
			# No unexplained "+25 fish" badge covering the decision lanes.
			var target := _float_x[i]
			var target_y := _float_y[i]
			if _fish_label != null and is_instance_valid(_fish_label):
				var counter_center := _fish_label.get_global_rect().get_center() \
					- _float_root.global_position
				target = counter_center.x - label.size.x * 0.5
				target_y = counter_center.y - label.size.y * 0.5
			var travel := t * t * (3.0 - 2.0 * t)
			label.position = Vector2(lerpf(_float_x[i], target, travel),
				lerpf(_float_y[i], target_y, travel) - sin(t * PI) * 46.0 * _hud_scale)
			var fish_scale := lerpf(1.0, 0.62, travel)
			label.scale = Vector2.ONE * fish_scale
			label.modulate.a = clampf((1.0 - t) * 3.0, 0.0, 1.0)
			continue
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
			_mission_pcts[i].text = "%s / %s" % [group_digits(int(_mission_amounts[i])), group_digits(int(_mission_goals[i]))]


## Ring drain plus the about-to-expire warning. The remaining time is counted
## from the player's authoritative remaining seconds. Presentation never
## spends extra time or keeps counting while gameplay is paused.
func _tick_powerups(delta: float) -> void:
	for i: int in _powerup_rings.size():
		if not _powerup_on[i]:
			continue
		var left := maxf(_powerup_left[i] - (delta if demo_feed else 0.0), 0.0)
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
	if _root == null or _headless or (text.is_empty() and kind != &"fish"):
		return
	var s := _hud_scale
	var color := ExpeditionMenuStyle.IVORY
	var size := 30.0
	var life := 0.95
	var rise := FLOAT_RISE
	var lift := 0.0
	match kind:
		&"fish":
			color = ICE
			size = 24.0
			life = 0.58
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
	label.text = "" if kind == &"fish" else font_safe(text)
	_float_kinds[slot] = kind
	_float_badges[slot].visible = false
	_float_fish_icons[slot].visible = kind == &"fish"
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
	_float_x[slot] = (_hud_view_size.x - FLOAT_WIDTH * s) * 0.5 \
		+ side * (34.0 + tier * 76.0) * s
	_float_y[slot] = _hud_view_size.y * FLOAT_ORIGIN_Y \
		- (lift + float(_float_lane) * 19.0) * s
	if kind == &"fish":
		_float_x[slot] = (_hud_view_size.x - FLOAT_WIDTH * s) * 0.5 \
			+ side * (10.0 + tier * 28.0) * s
		_float_y[slot] = _hud_view_size.y * 0.76 - tier * 22.0 * s
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
		_powerup_left[i] = maxf(left, 0.0)
		_powerup_rings[i].value = clampf(left / RunnerConfig.POWERUP_TIME, 0.0, 1.0)
		var seconds := int(ceil(maxf(left, 0.0)))
		if seconds != _powerup_shown[i]:
			_powerup_shown[i] = seconds
			_powerup_times[i].text = "%ds" % seconds
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

## A glanceable title uses the mission's typed fields; the complete description
## remains available to accessibility, hover, and the full Missions page.
static func compact_mission_title(entry: Dictionary) -> String:
	var target := group_digits(maxi(int(entry.get("target", 0)), 0))
	var kind := int(entry.get("kind", -1))
	match kind:
		RunnerMissions.Kind.DISTANCE_RUN, RunnerMissions.Kind.DISTANCE_TOTAL:
			return "RUN %s m" % target
		RunnerMissions.Kind.CLEAN_RUN:
			return "DODGE %s m" % target
		RunnerMissions.Kind.MULTIPLIER_RUN:
			return "RUN %s m AT x%d+" % [target, int(entry.get("mult", 2))]
		RunnerMissions.Kind.FISH_TOTAL, RunnerMissions.Kind.FISH_RUN:
			return "COLLECT %s FISH" % target
		RunnerMissions.Kind.JUMP_TOTAL, RunnerMissions.Kind.JUMP_RUN:
			return "JUMP %s TIMES" % target
		RunnerMissions.Kind.SLIDE_TOTAL, RunnerMissions.Kind.SLIDE_RUN:
			return "SLIDE %s TIMES" % target
		RunnerMissions.Kind.LANE_TOTAL, RunnerMissions.Kind.LANE_RUN:
			return "%s LANE CHANGES" % target
		RunnerMissions.Kind.NEAR_MISS_TOTAL, RunnerMissions.Kind.NEAR_MISS_RUN:
			return "%s NEAR MISSES" % target
		RunnerMissions.Kind.POWERUP_TOTAL, RunnerMissions.Kind.POWERUP_RUN:
			return "USE %s POWER-UPS" % target
		RunnerMissions.Kind.POWERUP_SPECIFIC:
			var power_names := {"magnet": "MAGNETS", "shield": "SHIELDS", "double": "DOUBLE POINTS"}
			var param := String(entry.get("param", ""))
			if power_names.has(param):
				return "%s %s" % [target, power_names[param]]
		RunnerMissions.Kind.RAMP_TOTAL, RunnerMissions.Kind.RAMP_RUN:
			return "TAKE %s RAMPS" % target
	# Unknown future or synthetic rows retain their complete supplied wording.
	var full := font_safe(String(entry.get("text", ""))).to_upper().replace(" M ", " m ")
	return full.trim_suffix(" M") + " m" if full.ends_with(" M") else full

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
		var fresh := id != _mission_ids[i] or text != _mission_labels[i].tooltip_text
		if fresh:
			_mission_ids[i] = id
			# Keep a distance and its unit on the same line at every HUD scale.
			_mission_labels[i].text = compact_mission_title(entry).replace(" m", "\u00a0m")
			_mission_labels[i].tooltip_text = text
			_mission_labels[i].accessibility_name = text
			# Containers grow for the complete typed title; never hide a third line.
			_mission_labels[i].max_lines_visible = -1
			_mission_shown[i] = 0.0
			_mission_pct_shown[i] = -1
			_mission_done[i] = false
			_mission_bars[i].value = 0.0
			_mission_bars[i].modulate = Color.WHITE
			_mission_labels[i].add_theme_color_override("font_color", INK)
			_mission_pcts[i].add_theme_color_override("font_color",
				Color(INK_MUTED, 0.95))
			_mission_marks[i].visible = false
			_mission_pcts[i].visible = true
			if not row.visible:
				row.visible = true
			_reveal_mission(i)
		var amount := float(entry.get("current", progress * 100.0))
		var goal := float(entry.get("target", 100.0))
		var count_changed := fresh or int(amount) != int(_mission_amounts[i]) \
			or int(goal) != int(_mission_goals[i])
		_mission_amounts[i] = amount
		_mission_goals[i] = goal
		if count_changed:
			_mission_pcts[i].text = "%s / %s" % [group_digits(int(amount)), group_digits(int(goal))]
		_mission_target[i] = progress
		var done_changed := done != _mission_done[i]
		if done_changed:
			_mission_done[i] = done
			_set_mission_done(i, done)
			if done:
				_note_completed(text)
		if count_changed or done_changed:
			_fit_mission_row(i)
	if _mission_panel != null:
		_mission_panel.visible = any


## Finished treatment: the bar goes green and full, the percentage is replaced
## by a tick, and the row pops once so a goal met mid-run is noticed even in
## peripheral vision.
func _set_mission_done(index: int, done: bool) -> void:
	# Fill already carries the reference green; keep its recessed track neutral.
	_mission_bars[index].modulate = Color.WHITE
	_mission_labels[index].add_theme_color_override("font_color",
		COLOR_GOAL if done else INK)
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
	# This channel also carries aggregate set rewards. Only set_missions or
	# the authoritative run summary may register a completed challenge.
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
	# Entry properties share one step; the reading interval, exit and hide must
	# follow it. Leaving parallel mode enabled hid the banner at 0.48 seconds.
	_banner_tween.set_parallel(false)
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
			INK if hot else INK_MUTED)
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
	_message_label.modulate = Color.WHITE
	_message_label.scale = Vector2.ONE
	var countdown := clean == "3" or clean == "2" or clean == "1" or clean == "GO!"
	_objective_label.visible = countdown
	_objective_label.modulate.a = 1.0
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
	if countdown:
		_message_tween.parallel().tween_property(_objective_label, "modulate:a", 0.0, 0.35)
	_message_tween.tween_callback(func() -> void:
		_message_label.text = ""
		_message_text = ""
		_message_label.modulate.a = 1.0
		_objective_label.hide()
		_objective_label.modulate.a = 1.0)


## --- End of run -------------------------------------------------------------

## Full-screen end-of-run panel. `summary` carries `distance` (float metres),
## `fish` (int), `score` (int), `best` (int, the standing best BEFORE this run)
## and `is_new_best` (bool). An optional `missions` array of strings overrides
## the challenge list the HUD tracked during the run.
func show_game_over(summary: Dictionary) -> void:
	set_pause_available(false)
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
	# Extra completed rows consume the same finite viewport. Keep the normal
	# one-row reference generous; compact only dense summaries to retain both actions.
	var compact_summary := completed.size() > 1
	var full_board_summary := completed.size() >= MISSION_ROWS
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

	_results_background = TextureRect.new()
	_results_background.name = "CaughtInSnowBackground"
	_results_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_results_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_results_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_results_background.texture = RunnerHUDArt.caught_background(_view_size.y >= _view_size.x)
	_results_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game_over.add_child(_results_background)
	if record:
		_game_over.add_child(_celebration_glow())

	# Scroll wrapper: a short landscape phone cannot fit the card, and the two
	# buttons must stay reachable rather than being pushed off the bottom.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_game_over.add_child(scroll)
	var center := HBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	_results_stage = Control.new()
	_results_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_results_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Always parent the stage, even when hidden in portrait, so it is freed with
	# the results screen. An unparented portrait stage leaked on every run.
	center.add_child(_results_stage)
	_results_title = TextureRect.new()
	_results_title.texture = ExpeditionMenuStyle._material_texture(
		"res://assets/art/ui/menu/runner_complete_wordmark_v2.webp")
	_results_title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_results_title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_results_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_results_title.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_results_title.anchor_top = 0.02
	_game_over.add_child(_results_title)
	var card_holder := VBoxContainer.new()
	card_holder.alignment = BoxContainer.ALIGNMENT_CENTER
	card_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_child(card_holder)
	_results_art_space = Control.new()
	card_holder.add_child(_results_art_space)
	var inset := MarginContainer.new()
	_results_inset_margin = inset
	for side: String in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_%s" % side, UITheme.scaled_int(16))
	card_holder.add_child(inset)

	var card := UITheme.make_card(inset)
	_results_card = card
	card.minimum_size_changed.connect(_relayout_results, CONNECT_DEFERRED)
	card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	card.add_child(column)
	_results_summary = PanelContainer.new()
	column.add_child(_results_summary)
	var summary_column := VBoxContainer.new()
	summary_column.add_theme_constant_override("separation", 10)
	_results_summary.add_child(summary_column)

	var score_face := PanelContainer.new()
	score_face.name = "ResultsScorePanel"
	score_face.add_theme_stylebox_override("panel", RunnerHUDArt.hud_panel("card", 32.0, 14.0, 16.0))
	score_face.custom_minimum_size.y = 220.0 if full_board_summary else 244.0
	summary_column.add_child(score_face)
	var score_stack := VBoxContainer.new()
	score_face.add_child(score_stack)
	var score_caption := ExpeditionMenuStyle.label("SCORE", 40 if full_board_summary else 48)
	score_caption.name = "ResultsScoreCaption"
	score_caption.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	score_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_stack.add_child(score_caption)
	var score_value := ExpeditionMenuStyle.label(group_digits(score), 100 if full_board_summary else (110 if compact_summary else 120))
	score_value.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	score_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var score_inset := PanelContainer.new()
	score_inset.add_theme_stylebox_override("panel", _results_inset())
	score_stack.add_child(score_inset)
	score_inset.add_child(score_value)
	if record:
		_add_badge(score_stack, "New Personal Best")

	_add_stat_grid(summary_column, distance, fish, maxi(best, score), tint)
	# The comparison line and the goals met land AFTER the count-up, so the
	# result reads as a sequence: here is the number, here is what it beat,
	# here is what you finished on the way.
	var footer: Control = null
	var goals := _add_mission_list(summary_column, completed, summary.get("mission_rows", []))
	column.add_child(UITheme.make_spacer(4))

	# Two choices, but not equal ones: Run Again is the whole point of a runner,
	# so it leads the row and wears the promoted face.
	_game_over_buttons = BoxContainer.new()
	_game_over_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_game_over_buttons.add_theme_constant_override("separation", 10)
	column.add_child(_game_over_buttons)
	var again_height := 144.0 if compact_summary else 160.0
	var menu_height := 100.0 if compact_summary else 110.0
	var again := ExpeditionMenuStyle.button("RUN AGAIN", true,
		44, again_height)
	# A native focus halo must not add a second rectangular border over art.
	var focus_line := StyleBoxEmpty.new()
	again.add_theme_stylebox_override("focus", focus_line)
	ExpeditionMenuStyle.illustrated_action(again, "RUN AGAIN", ExpeditionMenuStyle._material_texture(
		"res://assets/art/ui/menu/run_action_icon_v5.webp"), 72 if compact_summary else 76, again_height)
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	again.pressed.connect(func() -> void: restart_pressed.emit())
	_game_over_buttons.add_child(again)
	var to_menu := ExpeditionMenuStyle.button("BASE CAMP", false,
		34, menu_height)
	to_menu.add_theme_stylebox_override("focus", focus_line)
	to_menu.icon = RunnerHUDArt.sprite("camp")
	to_menu.expand_icon = true
	to_menu.add_theme_constant_override("icon_max_width", UITheme.scaled_int(72))
	to_menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	to_menu.custom_minimum_size.x = 460.0
	ExpeditionMenuStyle.illustrated_action(to_menu, "BASE CAMP", RunnerHUDArt.sprite("camp"), 40 if compact_summary else 44, menu_height, false, ExpeditionMenuStyle.INK)
	# The reference uses a small destination mark beside its caption; the
	# generic action's near-full-height mascot makes this secondary CTA too loud.
	var camp_picture := to_menu.get_node("IllustratedAction").get_child(0) as TextureRect
	camp_picture.custom_minimum_size = Vector2(menu_height * 0.66, menu_height * 0.64)
	to_menu.pressed.connect(func() -> void: menu_pressed.emit())
	_game_over_buttons.add_child(to_menu)
	_recolor_results(card)
	_relayout()

	if _headless:
		_on_results_cover_ready(_game_over)
		return
	again.grab_focus()
	AudioManager.play_sfx("sfx_victory" if record else "sfx_finish")
	_play_panel_entrance(card, score_value, score, record, footer, goals)


func _recolor_results(node: Node) -> void:
	if node.name == "IllustratedAction":
		return
	if node is Label:
		(node as Label).add_theme_color_override("font_color",
			ExpeditionMenuStyle.INK)
	for child in node.get_children():
		_recolor_results(child)


func _results_inset() -> StyleBoxFlat:
	var face := StyleBoxFlat.new()
	face.bg_color = Color("eee8da")
	face.border_color = Color("d8d2c5")
	face.set_border_width_all(2)
	face.set_corner_radius_all(18)
	face.set_content_margin_all(4)
	face.shadow_color = Color(0.23, 0.20, 0.14, 0.10)
	face.shadow_offset = Vector2(0, -2)
	face.shadow_size = 4
	return face


## Distance / Fish / Score, plus the standing best. On a record the best cell
## becomes the score the player just beat; otherwise it shows the gap still to
## close, which is the reason to press Run Again.
func _add_stat_grid(parent: Control, distance: float, fish: int, best: int,
		_tint: Color) -> Label:
	var row := HBoxContainer.new()
	row.name = "ResultsStats"
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	for entry: Array in [["BEST", group_digits(best), "trophy"],
		["DISTANCE", "%d m" % int(distance), "pin"], ["FISH", str(fish), "fish"]]:
		var tile := PanelContainer.new()
		tile.name = "ResultsStatPanel" + String(entry[0]).capitalize()
		tile.add_theme_stylebox_override("panel", RunnerHUDArt.hud_panel("card", 14.0, 12.0, 12.0))
		tile.custom_minimum_size.y = 112.0
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(tile)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		tile.add_child(line)
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.texture = RunnerHUDArt.sprite(String(entry[2]))
		icon.custom_minimum_size = Vector2(54.0, 64.0)
		if entry[2] == "fish":
			var fish_region := AtlasTexture.new()
			fish_region.atlas = ExpeditionMenuStyle._material_texture("res://assets/art/ui/menu/home_fish_symbol_clean_v2.png")
			fish_region.region = Rect2(26, 18, 178, 108)
			fish_region.filter_clip = true
			icon.texture = fish_region
			icon.custom_minimum_size = Vector2(62.0, 64.0)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		line.add_child(icon)
		var stack := VBoxContainer.new()
		stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(stack)
		for value: String in [String(entry[0]), String(entry[1])]:
			var label := ExpeditionMenuStyle.label(value, 24 if value == entry[0] else 40)
			label.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			if value == entry[0]:
				label.name = "ResultsStatCaption"
				stack.add_child(label)
			else:
				var inset := PanelContainer.new()
				inset.add_theme_stylebox_override("panel", _results_inset())
				stack.add_child(inset)
				inset.add_child(label)
	return null


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
func _add_mission_list(parent: Control, completed: PackedStringArray,
		mission_rows: Array = []) -> Control:
	var stack := VBoxContainer.new()
	stack.name = "ResultsCompletedMissions"
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 14)
	parent.add_child(stack)
	var summaries: Array[Dictionary] = []
	for mission: String in completed:
		summaries.append({"text": mission, "progress": 1.0, "done": true})
	# With no completed goal, keep the real closest challenge visible. It uses
	# its actual progress, rather than an invented completion or generic banner.
	if summaries.is_empty():
		var closest: Dictionary = {}
		for candidate: Variant in mission_rows:
			if candidate is Dictionary and not bool(candidate.get("done", false)) and (closest.is_empty()
					or float(candidate.get("progress", 0.0)) > float(closest.get("progress", 0.0))):
				closest = candidate
		if not closest.is_empty():
			summaries.append(closest.duplicate())
	if summaries.is_empty():
		var empty := PanelContainer.new()
		empty.add_theme_stylebox_override("panel", RunnerHUDArt.hud_panel("gauge", 28.0, 24.0, 20.0))
		empty.custom_minimum_size.y = 116.0
		stack.add_child(empty)
		var prior_board_complete := not mission_rows.is_empty() and mission_rows.all(
			func(entry: Variant) -> bool: return entry is Dictionary and bool(entry.get("done", false)))
		var message := ExpeditionMenuStyle.label("New goals on your next run" if prior_board_complete
			else "Complete challenges to earn rewards.", 28)
		message.name = "ResultsGoalsStatus"
		message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_child(message)
		return stack
	var check_texture := UITheme.make_icon(CHECK_SVG.replace("#8bea99", "#ffffff"), 1.0)
	var fill := UITheme.make_bar_fill(Color("179a30"), Color("68e857"))
	for entry: Dictionary in summaries:
		var mission := String(entry.get("text", ""))
		var done := bool(entry.get("done", false))
		var tile := PanelContainer.new()
		tile.name = "CompletedMissionRow"
		tile.add_theme_stylebox_override("panel", RunnerHUDArt.hud_panel("gauge", 40.0, 30.0, 20.0))
		tile.custom_minimum_size.y = 108.0
		stack.add_child(tile)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		tile.add_child(row)
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		var asset := "mission_fish_icon_exact_v1" if mission.to_lower().contains("fish") else "mission_flag_icon_exact_v1"
		icon.texture = load("res://assets/art/ui/menu/%s.webp" % asset)
		icon.custom_minimum_size = Vector2(48.0, 48.0)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)
		var content := VBoxContainer.new()
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		content.add_theme_constant_override("separation", 6)
		row.add_child(content)
		var label := ExpeditionMenuStyle.label(font_safe(mission), 28)
		label.name = "CompletedMissionText"
		label.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_child(label)
		_results_mission_labels.append(label)
		var groove := _thin_bar(20.0, fill if done else UITheme.make_bar_fill(Color("3184c2"), Color("70c7ed")))
		var progress := groove.get_child(0) as ProgressBar
		progress.value = clampf(float(entry.get("progress", 0.0)), 0.0, 1.0)
		progress.modulate = Color.WHITE
		content.add_child(groove)
		if not done:
			var amount := ExpeditionMenuStyle.label("%s / %s" % [
				group_digits(int(entry.get("current", 0))), group_digits(int(entry.get("target", 0)))], 22)
			amount.name = "ResultMissionProgress"
			amount.autowrap_mode = TextServer.AUTOWRAP_OFF
			amount.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
			amount.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(amount)
			continue
		var badge := PanelContainer.new()
		badge.name = "CompletionCheck"
		badge.custom_minimum_size = Vector2(44.0, 44.0)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var style := ExpeditionMenuStyle.surface(Color("38ae40"), 22, true)
		style.border_color = Color("78d55c")
		style.set_content_margin_all(6)
		badge.add_theme_stylebox_override("panel", style)
		row.add_child(badge)
		var check := TextureRect.new()
		check.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		check.texture = check_texture
		check.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.add_child(check)
	return stack


## Gold pill for the record callout, matching the results screen's badge.
func _add_badge(parent: Control, text: String) -> void:
	var holder := CenterContainer.new()
	parent.add_child(holder)
	var badge := PanelContainer.new()
	var style := UITheme.make_panel_style(Color("dfc990"), Color("aa935e"))
	style.set_corner_radius_all(UITheme.RADIUS_PILL)
	style.content_margin_left = 22.0
	style.content_margin_right = 22.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	badge.add_theme_stylebox_override("panel", style)
	holder.add_child(badge)
	var caption := ExpeditionMenuStyle.label(text.to_upper(), 23, Color("435774"))
	caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	badge.add_child(caption)
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
	var core := Color(0.96, 0.78, 0.28, 0.08)
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
	fade.finished.connect(_on_results_cover_ready.bind(_game_over))
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


func _on_results_cover_ready(overlay: Control) -> void:
	# A quick Retry can replace/free a fading result. Its old callback must not
	# hide the new run, nor may missing/transparent art suppress live geometry.
	if not is_instance_valid(overlay) or overlay != _game_over \
			or overlay.is_queued_for_deletion() or not overlay.is_visible_in_tree() \
			or overlay.modulate.a < 1.0 or _results_background == null \
			or _results_background.texture == null:
		return
	results_cover_changed.emit(true)


func hide_game_over() -> void:
	# Restore the scene before the old opaque page is removed.
	if is_instance_valid(_game_over):
		results_cover_changed.emit(false)
	_game_over_buttons = null
	_results_stage = null
	_results_title = null
	_results_background = null
	_results_hero = null
	_results_art_space = null
	_results_card = null
	_results_summary = null
	_results_inset_margin = null
	_results_mission_labels.clear()
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
