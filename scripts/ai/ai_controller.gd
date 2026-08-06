class_name AIController
extends RacerController
## AI driver: follows the course guide with personality-driven line choice,
## takes shortcuts, jumps/slides from course hints, uses items, shoves,
## and recovers when stuck. Difficulty scales reaction, precision, mistakes.

const THROW_RANGE: float = 25.0
const THROW_CONE_DOT: float = 0.94  # ~20 degree cone ahead
const PICKUP_SCAN_AHEAD: float = 30.0

var racer: Racer = null
var course: CourseBase = null
var personality: Dictionary = {}
var difficulty: Dictionary = {}
var rng := RandomNumberGenerator.new()

var _target_point: Vector3 = Vector3.ZERO
var _retarget_timer: float = 0.0
var _lateral_offset: float = 0.0
var _lateral_timer: float = 0.0
var _chosen_branch: int = -1
var _branch_considered: Dictionary = {}
var _item_hold_timer: float = 0.0
var _mistake_steer: float = 0.0
var _mistake_timer: float = 0.0
var _stuck_check_timer: float = 3.0
var _stuck_last_position: Vector3 = Vector3(9999, 9999, 9999)
# Progress watchdog: the position check misses a racer circling at full speed
# (moves >4m but gains no course progress — seen looping near the finish).
var _progress_watch_timer: float = 12.0
var _progress_watch_last: float = -1.0
var _slide_zone_until: float = -1.0
var _shove_eval_timer: float = 0.0
var _throw_eval_timer: float = 0.0


func configure(p_racer: Racer, p_course: CourseBase, p_personality: Dictionary, p_difficulty: Dictionary, seed_value: int) -> void:
	racer = p_racer
	course = p_course
	personality = p_personality
	difficulty = p_difficulty
	rng.seed = seed_value
	_lateral_offset = rng.randf_range(-3.5, 3.5)


func tick(delta: float) -> void:
	if racer == null or course == null or racer.state == Racer.State.FINISHED:
		steer = 0.0
		slide_held = false
		return

	_retarget_timer -= delta
	_lateral_timer -= delta
	_mistake_timer -= delta
	_shove_eval_timer -= delta
	_throw_eval_timer -= delta
	_item_hold_timer -= delta
	_stuck_check_timer -= delta

	if _lateral_timer <= 0.0:
		_lateral_timer = rng.randf_range(2.5, 5.0)
		var spread := 4.2 * (1.0 - float(personality.get("consistency", 0.5)) * 0.5)
		_lateral_offset = rng.randf_range(-spread, spread)

	if _retarget_timer <= 0.0:
		var reaction := float(difficulty.get("reaction_delay", 0.3))
		if racer.boost_mult > 1.05:
			# Boosted: retarget sooner so anticipation keeps up with the
			# extra ground covered per reaction window (post-pad corners).
			reaction *= 0.6
		_retarget_timer = reaction
		_update_target()

	_steer_toward_target(delta)
	_update_actions()
	_check_stuck()
	_check_progress_watchdog(delta)


func _update_target() -> void:
	var progress := racer.progress
	_consider_branches(progress)
	_consider_snowball_pickups()
	var lookahead := 8.0 + racer.current_speed * 0.55
	if racer.boost_mult > 1.05:
		# Extra anticipation while boosted so corners after pads are entered
		# on a line chosen for the boosted speed, not the base speed.
		lookahead += racer.current_speed * 0.25
	if _chosen_branch >= 0:
		var branch: Dictionary = course.branches[_chosen_branch]
		var entry := float(branch["entry"])
		if int(racer.guide_cache.get("path", -1)) == _chosen_branch:
			# Already on the branch: normal guide following handles it.
			_chosen_branch = _chosen_branch if progress < float(branch["exit"]) - 5.0 else -1
			_target_point = course.ai_target(racer, lookahead, _lateral_offset * 0.4)
			return
		elif progress < entry + 5.0:
			# Aim INTO the branch, never at its mouth (a target at the mouth
			# makes the racer orbit it and block the track for everyone).
			var guide: PathGuide = branch["guide"]
			var mouth := guide.position_at(0.0)
			var depth := 18.0 + maxf(0.0, 25.0 - racer.global_position.distance_to(mouth))
			_target_point = guide.point_at(minf(depth, guide.length * 0.5), 0.0)
			return
		else:
			_chosen_branch = -1
	_target_point = course.ai_target(racer, lookahead, _lateral_offset)


func _consider_branches(progress: float) -> void:
	if _chosen_branch >= 0:
		return
	for branch: Dictionary in course.upcoming_branches(progress):
		var id := int(branch["id"])
		var consider_key := "%d_%d" % [id, int(progress / 400.0)]
		if _branch_considered.has(consider_key):
			continue
		_branch_considered[consider_key] = true
		var risk := float(branch["risk"])
		var desire := float(personality.get("shortcut_pref", 0.5))
		var chance := float(difficulty.get("shortcut_chance", 0.5)) * desire * (1.2 - risk * float(personality.get("caution", 0.5)))
		if rng.randf() < clampf(chance, 0.02, 0.92):
			_chosen_branch = id


func _steer_toward_target(delta: float) -> void:
	var to_target := _target_point - racer.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 1.0:
		steer = move_toward(steer, 0.0, delta * 4.0)
		return
	var desired_yaw := atan2(-to_target.x, -to_target.z)
	var current_yaw := racer.rotation.y
	var diff := wrapf(desired_yaw - current_yaw, -PI, PI)
	var precision := float(difficulty.get("steer_precision", 0.8)) * (0.75 + 0.25 * float(personality.get("skill", 0.6)))
	var raw_steer := clampf(diff / deg_to_rad(40.0), -1.0, 1.0) * precision

	# Occasional mistakes: wobble pulse.
	if _mistake_timer <= 0.0:
		_mistake_timer = rng.randf_range(2.0, 6.0)
		var mistake_chance := float(difficulty.get("mistake_rate", 0.15)) * (1.1 - float(personality.get("consistency", 0.5)))
		if rng.randf() < mistake_chance:
			_mistake_steer = rng.randf_range(-0.7, 0.7)
			_mistake_timer = rng.randf_range(0.3, 0.7)
		else:
			_mistake_steer = 0.0
	if racer.boost_mult <= 1.05:
		# Wobble pulses are suppressed while boosted: at boost speed a pulse
		# is enough to overshoot a corner straight into the walls.
		raw_steer += _mistake_steer
	steer = clampf(lerpf(steer, raw_steer, minf(delta * 8.0, 1.0)), -1.0, 1.0)


func _update_actions() -> void:
	var progress := racer.progress
	var speed := maxf(racer.current_speed, 6.0)
	var react_lead := speed * (0.5 + float(difficulty.get("reaction_delay", 0.3)))
	var branch_id := int(racer.guide_cache.get("path", -1))
	# Hints on a branch are stored in branch-local offsets; convert the
	# racer's mapped main-line progress back to branch-local space.
	if branch_id >= 0:
		var branch_idx := int(racer.guide_cache.get("branch_idx_%d" % branch_id, 0))
		progress = float(branch_idx) * PathGuide.SAMPLE_SPACING

	# Hints: jump / slide zones.
	slide_held = false
	for hint: Dictionary in course.hints_in_range(progress, progress + react_lead, branch_id):
		var kind := String(hint["type"])
		var dist := float(hint["offset"]) - progress
		match kind:
			"jump":
				if dist < speed * 0.35 and rng.randf() > float(difficulty.get("mistake_rate", 0.15)) * 0.5:
					jump_pressed = true
			"slide":
				_slide_zone_until = float(hint["end_offset"])
			"danger_left":
				_lateral_offset = maxf(_lateral_offset, 2.0)
			"danger_right":
				_lateral_offset = minf(_lateral_offset, -2.0)
	if progress < _slide_zone_until:
		slide_held = true

	# Opportunistic downhill slide.
	if not slide_held and racer.is_on_floor():
		var floor_normal := racer.get_floor_normal()
		var forward := -racer.global_transform.basis.z
		var downhill := (Vector3.DOWN - floor_normal * Vector3.DOWN.dot(floor_normal)).dot(forward)
		if downhill > 0.18 and absf(steer) < 0.5:
			slide_held = true
	# Slide on smooth ice straights for speed.
	if not slide_held and racer.current_surface == SurfacesDB.Surface.ICE_SMOOTH and absf(steer) < 0.3:
		slide_held = rng.randf() < 0.6 + float(personality.get("risk", 0.5)) * 0.4

	# Shove nearby rivals.
	if _shove_eval_timer <= 0.0:
		_shove_eval_timer = 0.5
		var aggression := float(personality.get("aggression", 0.5)) * float(difficulty.get("item_aggression", 0.6))
		if aggression > 0.15:
			for node: Node in racer.get_tree().get_nodes_in_group(GameConfig.GROUP_RACERS):
				var other := node as Racer
				if other == null or other == racer:
					continue
				if racer.global_position.distance_to(other.global_position) < 2.2 and rng.randf() < aggression:
					shove_pressed = true
					break

	# Items. aim_back is a held state, not an edge, so it is cleared every tick
	# before anything can set it — otherwise a held item fired on a later tick
	# would inherit the aim from the last snowball evaluation.
	aim_back = false
	if racer.held_item != "" and _item_hold_timer <= 0.0:
		if _should_use_item():
			item_pressed = true
		_item_hold_timer = rng.randf_range(0.4, 1.4)

	# Collected snowballs: throw at a rival in a tight cone ahead. Only when
	# bare-handed — a held item keeps priority on the item key (see Racer).
	if racer.held_item == "" and racer.snowball_ammo > 0 \
			and _throw_eval_timer <= 0.0 and _item_hold_timer <= 0.0:
		_throw_eval_timer = 0.6
		# Someone ahead is the better prize, so a rival in front always wins the
		# shot; the over-the-shoulder throw is what a leader does about a tail.
		var throw_target := _find_throw_target()
		if throw_target == null:
			throw_target = _find_throw_target(true)
			aim_back = throw_target != null
		if throw_target != null and rng.randf() < _throw_chance():
			item_pressed = true
			_item_hold_timer = rng.randf_range(0.8, 2.2)


## Nearest unfinished rival inside the throw cone, or null.
func _find_throw_target(back: bool = false) -> Racer:
	var aim := racer.global_transform.basis.z if back else -racer.global_transform.basis.z
	var best: Racer = null
	var best_dist := THROW_RANGE
	for node: Node in racer.get_tree().get_nodes_in_group(GameConfig.GROUP_RACERS):
		var other := node as Racer
		if other == null or other == racer or other.state == Racer.State.FINISHED:
			continue
		var to_other := other.global_position - racer.global_position
		var dist := to_other.length()
		if dist > best_dist or dist < 2.0:
			continue
		if aim.dot(to_other / dist) < THROW_CONE_DOT:
			continue
		best = other
		best_dist = dist
	return best


func _throw_chance() -> float:
	var aggression := float(personality.get("aggression", 0.5)) * float(difficulty.get("item_aggression", 0.6))
	return clampf(aggression * (0.5 + float(personality.get("item_focus", 0.5)) * 0.7), 0.05, 0.9)


## Mild attraction toward on-track snowball pickups: nudge the lateral
## offset toward the nearest available pickup a bit ahead — never a hard
## turn, so the racing line and hint avoidance stay in charge.
func _consider_snowball_pickups() -> void:
	if racer.snowball_ammo >= Racer.MAX_SNOWBALL_AMMO:
		return
	var forward := -racer.global_transform.basis.z
	var right := racer.global_transform.basis.x
	var best_delta := 0.0
	var best_ahead := PICKUP_SCAN_AHEAD
	for node: Node in racer.get_tree().get_nodes_in_group(SnowballPickup.GROUP_NAME):
		var pickup := node as SnowballPickup
		if pickup == null or not pickup.is_available():
			continue
		var to_pickup := pickup.global_position - racer.global_position
		var ahead := forward.dot(to_pickup)
		if ahead < 4.0 or ahead > best_ahead:
			continue
		var lateral_delta := right.dot(to_pickup)
		if absf(lateral_delta) > 6.0:
			continue
		best_ahead = ahead
		best_delta = lateral_delta
	if best_delta != 0.0:
		_lateral_offset = clampf(_lateral_offset + clampf(best_delta, -2.5, 2.5), -5.0, 5.0)


func _should_use_item() -> bool:
	var focus := float(personality.get("item_focus", 0.5))
	var aggression := float(difficulty.get("item_aggression", 0.6))
	match racer.held_item:
		"snowball":
			return racer.race_position > 1 and rng.randf() < aggression * (0.4 + focus * 0.6)
		"shield":
			return rng.randf() < 0.25 + focus * 0.3
		"fish_frenzy":
			return absf(steer) < 0.4 and rng.randf() < 0.5 + aggression * 0.4
		"magnet":
			return rng.randf() < 0.4
		"blizzard":
			return racer.race_position < GameConfig.RACER_COUNT and rng.randf() < aggression * 0.6
	return rng.randf() < 0.3


func _check_stuck() -> void:
	if _stuck_check_timer > 0.0:
		return
	_stuck_check_timer = 3.0
	if racer.state == Racer.State.FINISHED or racer.is_stunned_or_recovering():
		_stuck_last_position = racer.global_position
		return
	if racer.global_position.distance_to(_stuck_last_position) < 4.0:
		racer.respawn_at_checkpoint()
		_chosen_branch = -1
		_branch_considered.clear()  # allow a fresh route decision after recovery
	_stuck_last_position = racer.global_position


func _check_progress_watchdog(delta: float) -> void:
	_progress_watch_timer -= delta
	if _progress_watch_timer > 0.0:
		return
	_progress_watch_timer = 12.0
	if racer.state == Racer.State.FINISHED or racer.is_stunned_or_recovering():
		_progress_watch_last = racer.progress
		return
	if _progress_watch_last >= 0.0 and racer.progress - _progress_watch_last < 6.0:
		racer.respawn_at_checkpoint()
		_chosen_branch = -1
		_branch_considered.clear()
	_progress_watch_last = racer.progress
