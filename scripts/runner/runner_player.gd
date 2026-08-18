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
	_advance_lane(delta)
	_advance_vertical(delta)
	_advance_slide(delta)
	_resolve_overlaps()
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


func jump() -> void:
	if state == State.JUMP:
		return
	# A jump out of a slide is allowed and feels good; it is the standard
	# "cancel the slide early" move in every runner.
	state = State.JUMP
	_slide_left = 0.0
	_vertical = RunnerConfig.JUMP_SPEED
	_set_height(RunnerConfig.STAND_HEIGHT)
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
			_visual.trigger_squash(0.72)


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
		if area.is_in_group(RunnerConfig.GROUP_HAZARD):
			take_hit()


func take_hit() -> void:
	if invulnerable_for > 0.0 or state == State.DEAD:
		return
	invulnerable_for = RunnerConfig.HIT_IFRAMES
	hits_left -= 1
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
	rotation.z = lerp_angle(rotation.z, -lean * 0.32, minf(1.0, delta * 14.0))
	rotation.y = lerp_angle(rotation.y, lean * 0.24, minf(1.0, delta * 12.0))
	# Blink while invulnerable so a hit is unmistakable.
	_visual.visible = invulnerable_for <= 0.0 \
		or fmod(invulnerable_for, 0.18) > 0.09
	_visual.tick(delta, clampf(speed / RunnerConfig.MAX_SPEED, 0.35, 1.0))


## --- Autopilot (headless sim only) -----------------------------------------

## Looks a short way ahead for hazards in the current lane and reacts the way a
## competent player would. Not meant to be good — meant to be good enough that
## a sim can prove the mode runs, streams and scores for minutes at a time.
func _autopilot(delta: float) -> void:
	_autopilot_cooldown = maxf(0.0, _autopilot_cooldown - delta)
	if _autopilot_cooldown > 0.0:
		return
	var tree := get_tree()
	if tree == null:
		return
	var look_ahead := 3.0 + speed * 0.55
	var best_threat: Node3D = null
	var best_distance := look_ahead
	for node: Node in tree.get_nodes_in_group(RunnerConfig.GROUP_HAZARD):
		var hazard := node as Node3D
		if hazard == null or not is_instance_valid(hazard):
			continue
		var ahead := global_position.z - hazard.global_position.z
		if ahead < 0.5 or ahead > best_distance:
			continue
		if absf(hazard.global_position.x - global_position.x) > RunnerConfig.LANE_WIDTH * 0.5:
			continue
		best_threat = hazard
		best_distance = ahead
	if best_threat == null:
		return
	_autopilot_cooldown = 0.25
	match String(best_threat.get_meta("kind", "block")):
		"bar":
			slide()
		"low":
			jump()
		_:
			# A blocking obstacle: step toward the middle when possible, since
			# the middle lane always has two escapes.
			move_lane(-1 if lane > 0 else 1)
