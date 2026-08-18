class_name RunnerPlayer
extends Node3D
## The penguin in Waddle Run.
##
## Deliberately NOT a Racer. The racing game's character is a CharacterBody3D
## with surface physics, slope handling, guides, AI hooks and a rubberband
## system — everything an endless runner must not have. A runner character is a
## state machine on rails: forward speed is dictated by the run, X snaps between
## three lanes, Y is a jump arc, and the only physics that matters is whether a
## box overlapped you. Sharing the racer would have meant fighting it in both
## modes; sharing only the ART (PenguinVisual) gets the look for free with no
## coupling at all.
##
## Collision is an Area3D on collision_mask 1<<9 (the runner layer) that reads
## its own overlaps once per frame rather than relying on signals: overlap
## callbacks arrive on the physics tick, and a runner needs the hit resolved in
## the same frame the player pressed jump, or a frame-perfect input reads as a
## missed one.

signal hit_taken(hits_left: int)
signal fish_collected(value: int)
signal powerup_gained(id: StringName)
signal powerup_expired(id: StringName)
## Passed within touching distance of a hazard without being hit. The single
## cheapest source of tension in a runner: it costs nothing to compute and it
## tells the player they were good rather than lucky.
signal near_miss
signal ramp_launched
## Move signals exist for the mission system: what the player DID is data the
## run wants, and polling state every frame would miss a jump that started and
## ended between two samples.
signal jumped
signal slid
signal lane_changed
signal shield_spent
signal died

enum State { RUN, JUMP, SLIDE, DEAD }

var lane: int = 1
var state: State = State.RUN
var hits_left: int = RunnerConfig.MAX_HITS
var invulnerable_for: float = 0.0
## Distance run, in metres. The world moves under the player in Z, so this is
## the authoritative "how far" and drives score, difficulty and the camera.
var distance: float = 0.0
var speed: float = RunnerConfig.START_SPEED

var _visual: PenguinVisual = null
var _area: Area3D = null
var _shape: CollisionShape3D = null
var _capsule: CapsuleShape3D = null
var _lane_from: float = 0.0
var _lane_to: float = 0.0
var _lane_t: float = 1.0
var _vertical: float = 0.0
var _slide_left: float = 0.0
var _height: float = RunnerConfig.STAND_HEIGHT
var _input_enabled: bool = true
## Active power-ups: id -> seconds remaining.
var powerups: Dictionary = {}
## Set while airborne off a ramp, which is a longer, flatter arc than a jump
## and is the moment the mode looks best — so it gets its own roll animation.
var _launched: bool = false
var _roll: float = 0.0
## Stumble: a hit does not just flash, it visibly costs the penguin its stride.
var _stumble: float = 0.0
var _near_miss_cooldown: float = 0.0
var _passed: Dictionary = {}
var _trail: SnowTrail = null
## Test hook: an autopilot that dodges what it can see, so a headless sim can
## run the mode end to end without a human.
static var autopilot: bool = false
var _autopilot_cooldown: float = 0.0


func setup(visual_config: Dictionary) -> void:
	_visual = PenguinVisual.new()
	_visual.setup(visual_config)
	add_child(_visual)
	_area = Area3D.new()
	_area.name = "Hitbox"
	# The player detects; it is never detected. Hazards and pickups sit on the
	# runner layer and monitor nothing themselves.
	_area.collision_layer = 0
	_area.collision_mask = 1 << 9
	_area.monitoring = true
	_shape = CollisionShape3D.new()
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.42
	_capsule.height = RunnerConfig.STAND_HEIGHT
	_shape.shape = _capsule
	_shape.position = Vector3(0.0, RunnerConfig.STAND_HEIGHT * 0.5, 0.0)
	_area.add_child(_shape)
	add_child(_area)
	if not GameConfig.is_headless():
		# Shared with the racing game: it is world-space (top_level) and takes
		# nothing but a position, a normal and a speed.
		_trail = SnowTrail.new()
		add_child(_trail)
		_trail.setup()
	position = Vector3(RunnerConfig.lane_x(lane), 0.0, 0.0)


## Input is disabled during the countdown and after death so a held key cannot
## queue a move into the game-over screen.
func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled


func tick(delta: float, run_speed: float) -> void:
	if state == State.DEAD:
		return
	speed = run_speed
	distance += speed * delta
	# The player moves through the world and the track streams around it, so Z
	# is derived from distance rather than integrated separately: two
	# accumulators for the same quantity drift apart, and the track's spawn
	# maths keys off this position.
	position.z = -distance
	invulnerable_for = maxf(0.0, invulnerable_for - delta)

	if _input_enabled:
		if autopilot:
			_autopilot(delta)
		else:
			_read_input()
	_advance_powerups(delta)
	_advance_lane(delta)
	_advance_vertical(delta)
	_advance_slide(delta)
	_resolve_overlaps()
	_advance_magnet(delta)
	_scan_near_miss(delta)
	if _trail != null:
		_trail.tick(global_position, Vector3.UP, position.y < 0.05,
			state == State.SLIDE, speed)
	_drive_visual(delta)


## --- Input ------------------------------------------------------------------

func _read_input() -> void:
	if Input.is_action_just_pressed(&"steer_left"):
		move_lane(-1)
	if Input.is_action_just_pressed(&"steer_right"):
		move_lane(1)
	if Input.is_action_just_pressed(&"jump"):
		jump()
	if Input.is_action_just_pressed(&"slide"):
		slide()


## Public so touch controls and the autopilot drive the same path as a keyboard.
func move_lane(direction: int) -> void:
	var target := clampi(lane + direction, 0, RunnerConfig.LANE_COUNT - 1)
	if target == lane:
		return
	lane = target
	# Interpolate from where the penguin actually IS, not from the lane it was
	# nominally in: a second tap mid-slide would otherwise snap it sideways.
	_lane_from = position.x
	_lane_to = RunnerConfig.lane_x(lane)
	_lane_t = 0.0
	lane_changed.emit()


func jump() -> void:
	if state == State.JUMP:
		return
	# A jump out of a slide is allowed and feels good; it is the standard
	# "cancel the slide early" move in every runner.
	state = State.JUMP
	_slide_left = 0.0
	_vertical = RunnerConfig.JUMP_SPEED
	_set_height(RunnerConfig.STAND_HEIGHT)
	jumped.emit()
	if _visual != null:
		_visual.trigger_squash(0.8)


func slide() -> void:
	if state == State.SLIDE:
		return
	# Sliding in mid-air is a fast-fall: it slams the penguin down and starts
	# the slide on landing, which is what players expect when they press slide
	# over an obstacle they mistimed.
	if state == State.JUMP:
		_vertical = minf(_vertical, -RunnerConfig.JUMP_SPEED * 0.55)
		return
	state = State.SLIDE
	_slide_left = RunnerConfig.SLIDE_TIME
	_set_height(RunnerConfig.SLIDE_HEIGHT)
	slid.emit()


## --- Motion -----------------------------------------------------------------

func _advance_lane(delta: float) -> void:
	if _lane_t >= 1.0:
		position.x = RunnerConfig.lane_x(lane)
		return
	_lane_t = minf(1.0, _lane_t + delta / RunnerConfig.LANE_CHANGE_TIME)
	# Ease-out: the move starts fast so the input feels instant, and settles so
	# the penguin does not visibly snap.
	var eased := 1.0 - pow(1.0 - _lane_t, 2.4)
	position.x = lerpf(_lane_from, _lane_to, eased)


func _advance_vertical(delta: float) -> void:
	if state != State.JUMP:
		return
	_vertical -= RunnerConfig.GRAVITY * delta
	position.y += _vertical * delta
	if position.y <= 0.0:
		position.y = 0.0
		_vertical = 0.0
		state = State.RUN
		if _visual != null:
			# A ramp landing hits harder than a hop, and the squash sells the
			# height the player just had.
			_visual.trigger_squash(0.56 if _launched else 0.72)
		_launched = false
		_roll = 0.0


func _advance_slide(delta: float) -> void:
	if state != State.SLIDE:
		return
	_slide_left -= delta
	if _slide_left <= 0.0:
		state = State.RUN
		_set_height(RunnerConfig.STAND_HEIGHT)


func _set_height(height: float) -> void:
	_height = height
	if _capsule == null:
		return
	# Capsule height includes the two hemispherical caps, so it can never be
	# shorter than its own diameter; clamp rather than let Godot silently fix it
	# and leave the shape taller than the bar the player is sliding under.
	_capsule.height = maxf(height, _capsule.radius * 2.0 + 0.01)
	_shape.position = Vector3(0.0, _capsule.height * 0.5, 0.0)


## --- Power-ups --------------------------------------------------------------

func grant_powerup(id: StringName) -> void:
	# Re-collecting a live power-up refreshes it rather than stacking: stacked
	# timers make the pill meaningless and let one lucky stretch carry a whole
	# run.
	powerups[id] = RunnerConfig.POWERUP_TIME
	powerup_gained.emit(id)


func has_powerup(id: StringName) -> bool:
	return float(powerups.get(id, 0.0)) > 0.0


func _advance_powerups(delta: float) -> void:
	if powerups.is_empty():
		return
	for id: StringName in powerups.keys():
		var left := float(powerups[id]) - delta
		if left <= 0.0:
			powerups.erase(id)
			powerup_expired.emit(id)
		else:
			powerups[id] = left


## The magnet is the power-up players feel most, because it changes what the
## screen DOES rather than what a number says: fish leave their lane and come
## to you. Pickups are moved directly rather than through physics — they are
## decorative until they touch, and a solver would be pure cost.
func _advance_magnet(delta: float) -> void:
	if not has_powerup(RunnerConfig.POWERUP_MAGNET):
		return
	var tree := get_tree()
	if tree == null:
		return
	var here := global_position + Vector3.UP * 0.7
	for node: Node in tree.get_nodes_in_group(RunnerConfig.GROUP_PICKUP):
		var pickup := node as Node3D
		if pickup == null or not is_instance_valid(pickup):
			continue
		var to_player := here - pickup.global_position
		var far := to_player.length()
		if far > RunnerConfig.MAGNET_RADIUS or far < 0.001:
			continue
		# Only pull what is still ahead: sweeping up fish already behind the
		# player reads as a bug, not a power.
		if pickup.global_position.z > here.z + 1.0:
			continue
		pickup.global_position += to_player / far \
			* minf(RunnerConfig.MAGNET_SPEED * delta, far)


## --- Near miss --------------------------------------------------------------

## A hazard that passed the player's plane this frame, close in X, without a
## hit. Tracked per-node so one obstacle cannot score twice.
func _scan_near_miss(delta: float) -> void:
	_near_miss_cooldown = maxf(0.0, _near_miss_cooldown - delta)
	var tree := get_tree()
	if tree == null or _near_miss_cooldown > 0.0:
		return
	for node: Node in tree.get_nodes_in_group(RunnerConfig.GROUP_HAZARD):
		var hazard := node as Node3D
		if hazard == null or not is_instance_valid(hazard):
			continue
		var id := hazard.get_instance_id()
		if _passed.has(id):
			continue
		var behind := hazard.global_position.z - global_position.z
		if behind < 0.0 or behind > 1.6:
			continue
		_passed[id] = true
		var side := absf(hazard.global_position.x - global_position.x)
		if side < RunnerConfig.LANE_WIDTH * 0.92 and invulnerable_for <= 0.0:
			_near_miss_cooldown = 0.35
			near_miss.emit()
			return
	# The pass-list is only ever consulted for hazards within 1.6 m, so it can
	# be dropped wholesale once it grows rather than reference-counted.
	if _passed.size() > 128:
		_passed.clear()


## --- Ramps ------------------------------------------------------------------

## A ramp throws the penguin into a long arc with a roll on the way down. It is
## the one obstacle that is pure reward, so it is worth its own animation.
func launch(power: float) -> void:
	state = State.JUMP
	_slide_left = 0.0
	_launched = true
	_roll = 0.0
	_vertical = maxf(_vertical, power)
	_set_height(RunnerConfig.STAND_HEIGHT)
	if _visual != null:
		_visual.trigger_squash(0.62)
	ramp_launched.emit()


## --- Collision --------------------------------------------------------------

func _resolve_overlaps() -> void:
	if _area == null:
		return
	for area: Area3D in _area.get_overlapping_areas():
		if not is_instance_valid(area):
			continue
		if area.is_in_group(RunnerConfig.GROUP_PICKUP):
			if area.has_method("collect"):
				var value: int = area.call("collect")
				if value > 0:
					fish_collected.emit(value)
			continue
		if area.is_in_group(RunnerConfig.GROUP_POWERUP):
			if area.has_method("collect"):
				var id: StringName = area.call("collect")
				if id != &"":
					grant_powerup(id)
			continue
		if area.is_in_group(RunnerConfig.GROUP_HAZARD):
			# A ramp is a hazard node so the track can place it with the same
			# machinery, but hitting one is the good outcome.
			if String(area.get_meta("kind", "block")) == "ramp":
				launch(RunnerConfig.RAMP_LAUNCH)
				continue
			take_hit()


func take_hit() -> void:
	if invulnerable_for > 0.0 or state == State.DEAD:
		return
	# The shield's whole job is to turn the run-ending mistake into a moment of
	# relief, so it is spent silently here rather than costing a life first.
	if has_powerup(RunnerConfig.POWERUP_SHIELD):
		powerups.erase(RunnerConfig.POWERUP_SHIELD)
		invulnerable_for = RunnerConfig.HIT_IFRAMES
		_stumble = 0.35
		powerup_expired.emit(RunnerConfig.POWERUP_SHIELD)
		shield_spent.emit()
		return
	invulnerable_for = RunnerConfig.HIT_IFRAMES
	hits_left -= 1
	_stumble = 0.75
	if _visual != null:
		_visual.trigger_tumble(1.0)
	hit_taken.emit(hits_left)
	if hits_left <= 0:
		kill()


func kill() -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	_input_enabled = false
	if _visual != null:
		_visual.set_pose(PenguinVisual.Pose.DEFEAT)
	died.emit()


## --- Presentation -----------------------------------------------------------

func _drive_visual(delta: float) -> void:
	if _visual == null:
		return
	match state:
		State.SLIDE:
			_visual.set_pose(PenguinVisual.Pose.SLIDE)
		State.JUMP:
			_visual.set_pose(PenguinVisual.Pose.AIR)
		State.DEAD:
			_visual.set_pose(PenguinVisual.Pose.DEFEAT)
		_:
			_visual.set_pose(PenguinVisual.Pose.RUN)
	# Lean into the lane change: the penguin banks toward the direction it is
	# moving, which is most of what sells a lane change as a decision rather
	# than a teleport.
	var lean := clampf((_lane_to - position.x) / RunnerConfig.LANE_WIDTH, -1.0, 1.0)
	if _lane_t >= 1.0:
		lean = 0.0
	_stumble = maxf(0.0, _stumble - delta)
	# A stumble adds a drunken wobble on top of everything else for a beat, so
	# a hit is readable from the animation alone with the HUD covered.
	var wobble := sin(_stumble * 34.0) * _stumble * 0.5
	rotation.z = lerp_angle(rotation.z, -lean * 0.32 + wobble, minf(1.0, delta * 14.0))
	rotation.y = lerp_angle(rotation.y, lean * 0.24 + wobble * 0.6, minf(1.0, delta * 12.0))
	# Airborne pitch: a tuck on the way up, an open-armed reach on the way down
	# for an ordinary jump; a full forward roll for a ramp launch, which is the
	# showpiece of the mode.
	var pitch := 0.0
	if state == State.JUMP:
		if _launched:
			_roll += delta * 7.4
			pitch = -_roll
		else:
			pitch = clampf(_vertical / RunnerConfig.JUMP_SPEED, -1.0, 1.0) * -0.42
	rotation.x = lerp_angle(rotation.x, pitch, minf(1.0, delta * (18.0 if _launched else 12.0)))
	# Blink while invulnerable so a hit is unmistakable.
	_visual.visible = invulnerable_for <= 0.0 \
		or fmod(invulnerable_for, 0.18) > 0.09
	_visual.tick(delta, clampf(speed / RunnerConfig.MAX_SPEED, 0.35, 1.0))


## --- Autopilot (headless sim only) -----------------------------------------

## Plays the mode competently enough that its distance is a fairness signal, not
## just a liveness one: it scans every lane, times jumps and slides against the
## closing speed, and steers toward ramps rather than away from them. When this
## bot dies at 200 m the track is too dense; when it runs for kilometres the
## track is too empty.
func _autopilot(delta: float) -> void:
	_autopilot_cooldown = maxf(0.0, _autopilot_cooldown - delta)
	var tree := get_tree()
	if tree == null:
		return
	# How far ahead a decision has to be made, in metres, for each verb.
	var reaction := speed * 0.34
	var scan := 4.0 + speed * 1.1
	# Per-lane threat: the nearest blocking obstacle in each lane, and the
	# nearest thing in THIS lane that needs a jump or a slide.
	var lane_block := PackedFloat32Array([scan, scan, scan])
	var jump_at := scan
	var slide_at := scan
	var ramp_lane := -1
	var ramp_at := scan
	for node: Node in tree.get_nodes_in_group(RunnerConfig.GROUP_HAZARD):
		var hazard := node as Node3D
		if hazard == null or not is_instance_valid(hazard):
			continue
		var ahead := global_position.z - hazard.global_position.z
		if ahead < 0.3 or ahead > scan:
			continue
		var hazard_lane := _lane_of(hazard.global_position.x)
		var kind := String(hazard.get_meta("kind", "block"))
		match kind:
			"ramp":
				if ahead < ramp_at:
					ramp_at = ahead
					ramp_lane = hazard_lane
			"bar":
				# A bar can span lanes, so treat it as blocking every lane it
				# covers unless the bot can get under it.
				if hazard_lane == lane and ahead < slide_at:
					slide_at = ahead
			"low":
				if hazard_lane == lane and ahead < jump_at:
					jump_at = ahead
			_:
				if hazard_lane >= 0 and hazard_lane < 3 and ahead < lane_block[hazard_lane]:
					lane_block[hazard_lane] = ahead
	# Verbs first: they are cheaper than a lane change and keep the line.
	if slide_at < reaction and state != State.SLIDE:
		slide()
		return
	if jump_at < reaction * 1.15 and state != State.JUMP:
		jump()
		return
	if _autopilot_cooldown > 0.0:
		return
	# A ramp is worth steering INTO, and it is the only obstacle that is.
	if ramp_lane >= 0 and ramp_lane != lane and ramp_at > reaction * 1.4:
		_autopilot_cooldown = 0.18
		move_lane(1 if ramp_lane > lane else -1)
		return
	# Otherwise hold the lane unless it is about to end, then take whichever
	# neighbour is clearest.
	if lane_block[lane] > reaction * 1.6:
		return
	var best_lane := lane
	var best_clear := lane_block[lane]
	for candidate: int in [lane - 1, lane + 1]:
		if candidate < 0 or candidate >= RunnerConfig.LANE_COUNT:
			continue
		if lane_block[candidate] > best_clear:
			best_clear = lane_block[candidate]
			best_lane = candidate
	if best_lane != lane:
		_autopilot_cooldown = 0.16
		move_lane(1 if best_lane > lane else -1)


## Which lane a world X sits in, or -1 when it is off the deck entirely.
func _lane_of(world_x: float) -> int:
	for i: int in RunnerConfig.LANE_COUNT:
		if absf(world_x - RunnerConfig.lane_x(i)) <= RunnerConfig.LANE_WIDTH * 0.5:
			return i
	return -1
