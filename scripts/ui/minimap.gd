class_name RaceMinimap
extends Control
## In-race course minimap (top-right HUD card): the main racing line projected
## from its guide curve to 2D and drawn as an ice-blue ribbon with checkpoint
## ticks and a checkered finish bar, branch shortcuts as fainter threads, and
## live racer dots — a larger gold dot with a white ring for the player,
## personality accent colors for rivals. All course geometry is baked once at
## setup into preallocated point arrays (the course is static), auto-fitted and
## rotated so the start sits at the bottom heading up. Per-frame cost is index
## writes into those arrays at ~10 Hz plus the _draw calls themselves — no
## heap allocations — so the map stays cheap on single-threaded web builds.
## Hidden during the countdown, when the optional gameplay/show_minimap
## setting is explicitly false, and when the card would render physically
## tiny (narrow portrait viewports).

const PANEL_BG := Color(0.035, 0.065, 0.13, 0.72)
const PANEL_BORDER := Color(0.55, 0.8, 1.0, 0.35)
const SHADOW_SOFT := Color(0.0, 0.0, 0.0, 0.32)
const TRACK_ICE := Color(0.55, 0.82, 1.0, 0.85)
const TRACK_OUTLINE := Color(0.10, 0.19, 0.33, 0.95)
const BRANCH_THREAD := Color(0.55, 0.82, 1.0, 0.38)
const CHECKPOINT_TICK := Color(0.55, 0.8, 1.0, 0.5)
const CHECKER_DARK := Color(0.08, 0.10, 0.14, 0.95)
const CHECKER_LIGHT := Color(0.97, 0.98, 1.0, 0.95)
const PLAYER_GOLD := Color(1.0, 0.85, 0.25)
const PLAYER_RING := Color(1.0, 1.0, 1.0, 0.95)
const AI_NEUTRAL := Color(0.78, 0.84, 0.92)
const DOT_OUTLINE := Color(0.05, 0.09, 0.17, 0.85)

const BASE_SIZE: float = 150.0      ## Card edge in logical px at hud_scale 1.
const TOP_CLEARANCE: float = 156.0  ## Keeps the card below the item slot.
const UPDATE_INTERVAL: float = 0.1  ## Racer dot refresh cadence (~10 Hz).
const MIN_PHYSICAL_PX: float = 60.0 ## Hide when the card would render smaller.
const MAX_TRACK_POINTS: int = 220   ## Resample cap for the ribbon polyline.
const TRACK_WIDTH_M: float = 19.0   ## World ribbon width driving map width.

var _manager: RaceManager = null
var _course: CourseBase = null
var _hud_scale: float = 1.0
var _panel_size: Vector2 = Vector2(BASE_SIZE, BASE_SIZE)
var _panel_style: StyleBoxFlat = null
var _map_xform: Transform2D = Transform2D.IDENTITY
var _ribbon_width: float = 4.0
var _checker_px: float = 3.0
var _track_points: PackedVector2Array = PackedVector2Array()
var _branch_points: Array[PackedVector2Array] = []
var _checkpoint_ticks: PackedVector2Array = PackedVector2Array()
var _finish_dark: PackedVector2Array = PackedVector2Array()
var _finish_light: PackedVector2Array = PackedVector2Array()
var _dot_points: PackedVector2Array = PackedVector2Array()
var _dot_colors: PackedColorArray = PackedColorArray()
var _dot_alive: PackedByteArray = PackedByteArray()
var _player_index: int = -1
var _accum: float = 0.0
var _started: bool = false
var _fits: bool = true


func setup(p_manager: RaceManager, p_hud_scale: float) -> void:
	_manager = p_manager
	_course = p_manager.course
	_hud_scale = clampf(p_hud_scale, 0.5, 2.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	if GameConfig.is_headless() or _course == null or _course.main_guide == null \
			or _course.main_guide.length < 1.0:
		set_process(false)
		return

	var edge := BASE_SIZE * _hud_scale
	_panel_size = Vector2(edge, edge)
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_right = -24.0
	offset_left = -24.0 - edge
	offset_top = 24.0 + TOP_CLEARANCE * _hud_scale
	offset_bottom = offset_top + edge

	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = PANEL_BG
	_panel_style.set_corner_radius_all(14)
	_panel_style.set_border_width_all(2)
	_panel_style.border_color = PANEL_BORDER
	_panel_style.shadow_color = SHADOW_SOFT
	_panel_style.shadow_size = 5
	_panel_style.shadow_offset = Vector2(0, 3)

	_build_map_geometry()
	_build_dot_arrays()
	_started = _manager.started
	_manager.race_started.connect(_on_race_started)
	SettingsManager.setting_changed.connect(_on_setting_changed)
	get_viewport().size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()


## Projects the main line and branch guides onto the card: rotate so the
## start heading points up, fit all points with uniform padding, then bake
## the transformed polylines, checkpoint ticks, and the finish checker bar.
func _build_map_geometry() -> void:
	var guide := _course.main_guide
	var pad := 12.0 * _hud_scale + 3.0

	# Rotation from the initial travel direction: start at the bottom, heading
	# up. Averaged over the first stretch so a wiggle at the grid can't skew it.
	var dir3 := guide.position_at(minf(30.0, guide.length * 0.25)) - guide.position_at(0.0)
	var dir := Vector2(dir3.x, dir3.z)
	if dir.length_squared() < 0.001:
		dir = Vector2(0.0, -1.0)
	var rot_angle := -PI * 0.5 - dir.angle()
	var rot := Transform2D(rot_angle, Vector2.ZERO)

	# Rotated (unscaled) samples: main line first, then each branch.
	var step := maxf(4.0, guide.length / float(MAX_TRACK_POINTS))
	var count := maxi(int(ceil(guide.length / step)) + 1, 2)
	_track_points.resize(count)
	for i: int in count:
		var p := guide.position_at(minf(float(i) * step, guide.length))
		_track_points[i] = rot * Vector2(p.x, p.z)
	_branch_points.clear()
	for branch: Dictionary in _course.branches:
		var branch_guide: PathGuide = branch["guide"]
		if branch_guide == null or branch_guide.length < 1.0:
			continue
		var branch_step := maxf(4.0, branch_guide.length / 80.0)
		var branch_count := maxi(int(ceil(branch_guide.length / branch_step)) + 1, 2)
		var pts := PackedVector2Array()
		pts.resize(branch_count)
		for i: int in branch_count:
			var p := branch_guide.position_at(minf(float(i) * branch_step, branch_guide.length))
			pts[i] = rot * Vector2(p.x, p.z)
		_branch_points.append(pts)

	# Uniform fit with padding around the union of all polylines.
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for p: Vector2 in _track_points:
		low = low.min(p)
		high = high.max(p)
	for pts: PackedVector2Array in _branch_points:
		for p: Vector2 in pts:
			low = low.min(p)
			high = high.max(p)
	var span := (high - low).max(Vector2.ONE)
	var avail := _panel_size - Vector2(pad, pad) * 2.0
	var map_scale := minf(avail.x / span.x, avail.y / span.y)
	var shift := _panel_size * 0.5 - (low + high) * 0.5 * map_scale
	for i: int in _track_points.size():
		_track_points[i] = _track_points[i] * map_scale + shift
	for pts: PackedVector2Array in _branch_points:
		for i: int in pts.size():
			pts[i] = pts[i] * map_scale + shift
	_map_xform = Transform2D(rot_angle, Vector2.ZERO).scaled(Vector2(map_scale, map_scale))
	_map_xform.origin = shift
	_ribbon_width = clampf(TRACK_WIDTH_M * map_scale, 2.5, 8.0)

	# Checkpoint ticks: short strokes across the ribbon.
	var tick_half := _ribbon_width * 0.5 + 2.5
	_checkpoint_ticks.resize(_course.checkpoint_offsets.size() * 2)
	for i: int in _course.checkpoint_offsets.size():
		var offset := _course.checkpoint_offsets[i]
		var pos := _map_point(guide.position_at(offset))
		var across := _map_across(guide, offset)
		_checkpoint_ticks[i * 2] = pos - across * tick_half
		_checkpoint_ticks[i * 2 + 1] = pos + across * tick_half

	# Finish: 4x2 checkered bar across the ribbon at the finish offset.
	_checker_px = clampf(_ribbon_width * 0.55, 2.2, 3.6)
	var finish_pos := _map_point(guide.position_at(_course.finish_offset))
	var finish_across := _map_across(guide, _course.finish_offset)
	var finish_along := Vector2(-finish_across.y, finish_across.x)
	_finish_dark.resize(8)
	_finish_light.resize(8)
	var dark_index := 0
	var light_index := 0
	for i: int in 4:
		for j: int in 2:
			var center := finish_pos + finish_across * ((float(i) - 1.5) * _checker_px) \
				+ finish_along * ((float(j) - 0.5) * _checker_px)
			var from := center - finish_along * (_checker_px * 0.5)
			var to := center + finish_along * (_checker_px * 0.5)
			if (i + j) % 2 == 0:
				_finish_dark[dark_index] = from
				_finish_dark[dark_index + 1] = to
				dark_index += 2
			else:
				_finish_light[light_index] = from
				_finish_light[light_index + 1] = to
				light_index += 2


## World position -> card-local point.
func _map_point(world: Vector3) -> Vector2:
	return _map_xform * Vector2(world.x, world.z)


## Unit vector across the ribbon (map space) at a main-line offset.
func _map_across(guide: PathGuide, offset: float) -> Vector2:
	var t := guide.tangent_at(offset)
	var along := _map_xform.basis_xform(Vector2(t.x, t.z))
	if along.length_squared() < 0.000001:
		return Vector2.RIGHT
	along = along.normalized()
	return Vector2(-along.y, along.x)


## Preallocates one dot slot per racer. Player = gold; rivals use their
## personality accent_color (documented UI hint), neutral ice otherwise.
func _build_dot_arrays() -> void:
	var racers := _manager.racers
	_dot_points.resize(racers.size())
	_dot_colors.resize(racers.size())
	_dot_alive.resize(racers.size())
	for i: int in racers.size():
		_dot_alive[i] = 0
		_dot_points[i] = _panel_size * 0.5
		if racers[i] == _manager.player:
			_player_index = i
			_dot_colors[i] = PLAYER_GOLD
		else:
			var accent: Variant = PersonalitiesDB.get_item(racers[i].racer_key).get("accent_color")
			_dot_colors[i] = accent if accent is Color else AI_NEUTRAL


func _process(delta: float) -> void:
	_accum += delta
	if _accum < UPDATE_INTERVAL:
		return
	_accum = fmod(_accum, UPDATE_INTERVAL)
	if _manager == null or not is_visible_in_tree():
		return
	_update_dots()
	queue_redraw()


## Writes current racer positions into the preallocated dot arrays (no per-call
## allocations). Dots clamp to the card so a fallen racer never escapes it.
func _update_dots() -> void:
	var racers := _manager.racers
	# The HUD is built before the grid is populated, so the first dot arrays
	# can be empty (or hold only the player). Re-baking whenever the roster
	# size changes is what makes rivals appear at all.
	if racers.size() != _dot_points.size():
		_build_dot_arrays()
	var clamp_low := Vector2(8.0, 8.0)
	var clamp_high := _panel_size - clamp_low
	var count := mini(racers.size(), _dot_points.size())
	for i: int in count:
		var racer := racers[i]
		if not is_instance_valid(racer) or not racer.is_inside_tree() or not racer.visible:
			_dot_alive[i] = 0
			continue
		_dot_alive[i] = 1
		var p := _map_xform * Vector2(racer.global_position.x, racer.global_position.z)
		_dot_points[i] = p.clamp(clamp_low, clamp_high)


func _draw() -> void:
	if _panel_style == null:
		return
	draw_style_box(_panel_style, Rect2(Vector2.ZERO, _panel_size))
	for pts: PackedVector2Array in _branch_points:
		if pts.size() >= 2:
			draw_polyline(pts, BRANCH_THREAD, maxf(_ribbon_width * 0.45, 1.5), true)
	if _track_points.size() >= 2:
		draw_polyline(_track_points, TRACK_OUTLINE, _ribbon_width + 3.0, true)
		draw_polyline(_track_points, TRACK_ICE, _ribbon_width, true)
	if _checkpoint_ticks.size() >= 2:
		draw_multiline(_checkpoint_ticks, CHECKPOINT_TICK, 1.5, true)
	if _finish_light.size() >= 2:
		draw_multiline(_finish_light, CHECKER_LIGHT, _checker_px, true)
	if _finish_dark.size() >= 2:
		draw_multiline(_finish_dark, CHECKER_DARK, _checker_px, true)
	# The player marker goes down FIRST as a filled gold disc with a white
	# ring, then rivals draw over it. Racers are bunched within a few map
	# pixels for much of a race, and painting the larger player dot last hid
	# every rival underneath it.
	if _player_index >= 0 and _player_index < _dot_points.size() \
			and _dot_alive[_player_index] == 1:
		var player_pos := _dot_points[_player_index]
		var player_radius := 5.6 * _hud_scale
		draw_circle(player_pos, player_radius + 2.4, PLAYER_RING, true, -1.0, true)
		draw_circle(player_pos, player_radius, PLAYER_GOLD, true, -1.0, true)
	var ai_radius := 3.6 * _hud_scale
	for i: int in _dot_points.size():
		if i == _player_index or _dot_alive[i] == 0:
			continue
		draw_circle(_dot_points[i], ai_radius + 1.4, DOT_OUTLINE, true, -1.0, true)
		draw_circle(_dot_points[i], ai_radius, _dot_colors[i], true, -1.0, true)


## --- Visibility -------------------------------------------------------------

func _on_race_started() -> void:
	_started = true
	_update_dots()
	_refresh_visibility()
	if visible:
		modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(self, "modulate:a", 1.0, 0.35)
	queue_redraw()


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "gameplay/show_minimap":
		_refresh_visibility()


## Hide when the card would render physically tiny (the canvas_items/expand
## stretch keeps logical width constant, so narrow portrait windows shrink
## every logical pixel — a 150 px card becomes an unreadable thumbnail).
func _on_viewport_resized() -> void:
	var viewport := get_viewport()
	var window := get_window()
	if viewport == null or window == null:
		return
	var logical_width := maxf(viewport.get_visible_rect().size.x, 1.0)
	var physical_edge := _panel_size.x * float(window.size.x) / logical_width
	_fits = physical_edge >= MIN_PHYSICAL_PX
	_refresh_visibility()


## Optional key with no default_settings() entry: get_setting returns null
## while unset, which reads as enabled — only an explicit false hides the map
## (same missing-key pattern as gameplay/touch_hints_seen).
func _setting_enabled() -> bool:
	return SettingsManager.get_setting("gameplay", "show_minimap") != false


func _refresh_visibility() -> void:
	visible = _started and _fits and _setting_enabled()
