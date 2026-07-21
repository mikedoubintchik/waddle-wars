class_name Racer
extends CharacterBody3D
## Core racer: state machine, surface-aware movement, jumping with coyote
## time and input buffering, belly sliding, swimming, shoving, items,
## checkpoint recovery. Driven by a RacerController (player or AI).

enum State { WADDLING, SLIDING, AIRBORNE, SWIMMING, BOOSTED, STUNNED, RECOVERING, FINISHED }

signal state_changed(new_state: State)
signal checkpoint_reached(racer: Racer, index: int)
signal race_finished(racer: Racer)
signal fish_collected(racer: Racer, value: int)
signal item_received(racer: Racer, item_id: String)
signal item_used(racer: Racer, item_id: String)
signal shove_landed(attacker: Racer, victim: Racer)
signal respawned(racer: Racer)
signal stunned_changed(racer: Racer, is_stunned: bool)

const GRAVITY: float = 30.0
const JUMP_VELOCITY: float = 11.0
const BASE_SPEED: float = 12.5
const SLIDE_MAX_SPEED: float = 26.0
const SLOPE_SLIDE_ACCEL: float = 15.0
const COYOTE_TIME: float = 0.14
const JUMP_BUFFER: float = 0.16
const MAX_STEER_DEG: float = 55.0
const SHOVE_COOLDOWN: float = 1.6
const SHOVE_RANGE: float = 2.4
const STUN_TIME: float = 1.1
const STUMBLE_TIME: float = 0.55
const RECOVER_TIME: float = 0.9

var racer_key: String = "player"
var display_name: String = "You"
var is_player: bool = false
var course: Node3D = null  # CourseBase, set by RaceManager
var controller: RacerController = null
var visual: PenguinVisual = null

var state: State = State.WADDLING
var current_speed: float = 0.0
var vertical_velocity: float = 0.0
var speed_scale: float = 1.0  # difficulty / rubberband, set by RaceManager
var boost_mult: float = 1.0

var progress: float = 0.0  # distance along course guide path
var total_progress: float = 0.0  # checkpoints * big + progress
var race_position: int = 1
var last_checkpoint_index: int = -1
var last_checkpoint_transform: Transform3D
var finish_time: float = -1.0
var fish_count: int = 0
var held_item: String = ""
var current_surface: SurfacesDB.Surface = SurfacesDB.Surface.PACKED_SNOW

var _facing_yaw: float = 0.0
var _velocity_yaw: float = 0.0
var _steer_offset: float = 0.0
var _guide_yaw: float = 0.0
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _boost_timer: float = 0.0
var _stun_timer: float = 0.0
var _stumble_timer: float = 0.0
var _recover_timer: float = 0.0
var _invuln_timer: float = 0.0
var _shove_cooldown: float = 0.0
var _shove_immunity: float = 0.0
var _blizzard_slip_timer: float = 0.0
var _water_areas: Array[Area3D] = []
var _water_surface_y: float = 0.0
var _has_shield: bool = false
var _shield_visual: MeshInstance3D = null
var _was_on_floor: bool = false
var _airborne_from_jump: bool = false
var _slide_particles: GPUParticles3D = null
var _finish_slowdown: float = 1.0
var _collision_shape: CollisionShape3D = null
var _capsule: CapsuleShape3D = null
var _crouched: bool = false
var guide_cache: Dictionary = {}  # used by CourseBase for cached lookups


func _ready() -> void:
	collision_layer = GameConfig.LAYER_RACERS
	collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_RACERS
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = 1.2
	add_to_group(GameConfig.GROUP_RACERS)
	_collision_shape = CollisionShape3D.new()
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.35
	_capsule.height = 1.0
	_collision_shape.shape = _capsule
	_collision_shape.position.y = 0.55
	add_child(_collision_shape)
	_make_slide_particles()


func setup(key: String, name_text: String, player: bool, visual_config: Dictionary, p_controller: RacerController, p_course: Node3D) -> void:
	racer_key = key
	display_name = name_text
	is_player = player
	course = p_course
	controller = p_controller
	add_child(controller)
	if player:
		add_to_group(GameConfig.GROUP_PLAYER)
	visual = PenguinVisual.new()
	visual.setup(visual_config)
	add_child(visual)
	_facing_yaw = rotation.y
	_velocity_yaw = rotation.y
	last_checkpoint_transform = global_transform


func _make_slide_particles() -> void:
	_slide_particles = GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0.5, 1)
	mat.spread = 25.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 4.0
	mat.gravity = Vector3(0, -8, 0)
	mat.scale_min = 0.05
	mat.scale_max = 0.16
	mat.color = Color(0.95, 0.98, 1.0, 0.8)
	_slide_particles.process_material = mat
	var puff := SphereMesh.new()
	puff.radius = 0.06
	puff.height = 0.12
	puff.radial_segments = 6
	puff.rings = 4
	var draw_mat := StandardMaterial3D.new()
	draw_mat.albedo_color = Color(0.97, 0.99, 1.0, 0.7)
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material = draw_mat
	_slide_particles.draw_pass_1 = puff
	_slide_particles.amount = 24
	_slide_particles.lifetime = 0.5
	_slide_particles.emitting = false
	_slide_particles.position = Vector3(0, 0.1, 0.4)
	add_child(_slide_particles)


func _physics_process(delta: float) -> void:
	if course == null or controller == null:
		return
	controller.tick(delta)
	_update_timers(delta)
	_update_guide()
	_detect_surface()

	match state:
		State.FINISHED:
			_tick_finished(delta)
		State.STUNNED:
			_tick_stunned(delta)
		State.RECOVERING:
			_tick_recovering(delta)
		State.SWIMMING:
			_tick_swimming(delta)
		_:
			_tick_ground_air(delta)

	move_and_slide()
	_check_kill_plane()
	_update_visual(delta)
	controller.consume_edges()


func _update_timers(delta: float) -> void:
	_coyote_timer = maxf(0.0, _coyote_timer - delta)
	_jump_buffer_timer = maxf(0.0, _jump_buffer_timer - delta)
	_boost_timer = maxf(0.0, _boost_timer - delta)
	_shove_cooldown = maxf(0.0, _shove_cooldown - delta)
	_shove_immunity = maxf(0.0, _shove_immunity - delta)
	_invuln_timer = maxf(0.0, _invuln_timer - delta)
	_stumble_timer = maxf(0.0, _stumble_timer - delta)
	_blizzard_slip_timer = maxf(0.0, _blizzard_slip_timer - delta)
	if _boost_timer <= 0.0:
		boost_mult = 1.0
	if controller.jump_pressed:
		_jump_buffer_timer = JUMP_BUFFER
		controller.consume_jump()


func _update_guide() -> void:
	var guide: Dictionary = course.get_guide(self)
	_guide_yaw = float(guide.get("yaw", _guide_yaw))
	progress = float(guide.get("progress", progress))
	total_progress = float(last_checkpoint_index + 1) * 10000.0 + progress


func _detect_surface() -> void:
	if not _water_areas.is_empty():
		current_surface = SurfacesDB.Surface.WATER
		return
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.5,
		global_position + Vector3.DOWN * 2.5,
		GameConfig.LAYER_WORLD
	)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider")
	if collider != null and collider.has_meta("surface"):
		current_surface = collider.get_meta("surface") as SurfacesDB.Surface
	else:
		current_surface = SurfacesDB.Surface.PACKED_SNOW
	if _blizzard_slip_timer > 0.0 and current_surface == SurfacesDB.Surface.PACKED_SNOW:
		current_surface = SurfacesDB.Surface.ICE_SMOOTH


## --- Core ground / air movement -------------------------------------------

func _tick_ground_air(delta: float) -> void:
	var surface := SurfacesDB.get_item(current_surface)
	var on_floor := is_on_floor()
	var sliding := state == State.SLIDING
	# Keep sliding while a low ceiling blocks standing up.
	var wants_slide := (controller.slide_held or (sliding and _ceiling_blocked())) and _stumble_timer <= 0.0

	if on_floor:
		_coyote_timer = COYOTE_TIME
		if not _was_on_floor and _airborne_from_jump or (not _was_on_floor and vertical_velocity < -6.0):
			_land_feedback()
		_airborne_from_jump = false

	# Penguins cannot slide up a hill: once a slide stalls on an ascent,
	# stand back up so the racer waddles instead of drifting backward.
	if sliding and on_floor and current_speed < 5.0:
		var stall_normal := get_floor_normal()
		var stall_forward := _yaw_to_dir(_velocity_yaw)
		var stall_downhill := (Vector3.DOWN - stall_normal * Vector3.DOWN.dot(stall_normal)).dot(stall_forward)
		if stall_downhill < 0.02 and not _ceiling_blocked():
			wants_slide = false

	# State selection on the ground.
	if on_floor:
		if wants_slide:
			if state != State.SLIDING:
				_set_state(State.SLIDING)
				AudioManager.play_sfx_3d("sfx_slide", global_position, randf_range(0.95, 1.05), -6.0)
		elif _boost_timer > 0.0:
			_set_state(State.BOOSTED)
		else:
			_set_state(State.WADDLING)
	else:
		if state != State.AIRBORNE and _coyote_timer <= 0.0:
			_set_state(State.AIRBORNE)

	sliding = state == State.SLIDING

	# Speed.
	var stumble_mult := 0.55 if _stumble_timer > 0.0 else 1.0
	if sliding:
		current_speed *= pow(float(surface["slide_keep"]), delta)
		var floor_normal := get_floor_normal() if on_floor else Vector3.UP
		var forward := _yaw_to_dir(_velocity_yaw)
		var downhill := Vector3.DOWN - floor_normal * Vector3.DOWN.dot(floor_normal)
		var slope_push := downhill.dot(forward) * SLOPE_SLIDE_ACCEL
		current_speed += (slope_push + float(surface["slide_bonus"])) * delta
		current_speed = clampf(current_speed, 0.0, SLIDE_MAX_SPEED * boost_mult)
		# Sliding uphill or into deep snow bleeds speed fast; standing back up
		# is handled once speed drops below waddle pace.
		if current_speed < BASE_SPEED * 0.55 * speed_scale:
			current_speed = move_toward(current_speed, BASE_SPEED * 0.55 * speed_scale, 4.0 * delta)
	else:
		var target := BASE_SPEED * float(surface["max_speed"]) * speed_scale * boost_mult * stumble_mult * _finish_slowdown
		var accel := 14.0 * float(surface["accel"])
		if not on_floor:
			accel *= 0.5
		current_speed = move_toward(current_speed, target, accel * delta)

	# Steering.
	var grip := float(surface["grip"])
	if not on_floor:
		grip *= 0.45
	if sliding:
		grip *= 0.55
	var sensitivity := 1.0
	if is_player:
		sensitivity = float(SettingsManager.get_setting("gameplay", "steer_sensitivity"))
	var steer := clampf(controller.steer, -1.0, 1.0) * sensitivity
	if _stumble_timer > 0.0:
		steer *= 0.4
	var steer_target := steer * deg_to_rad(MAX_STEER_DEG)
	_steer_offset = lerpf(_steer_offset, steer_target, minf(delta * 7.0 * grip, 1.0))
	_facing_yaw = _wrap_lerp_angle(_facing_yaw, _guide_yaw + _steer_offset, minf(delta * 5.0, 1.0))
	_velocity_yaw = _wrap_lerp_angle(_velocity_yaw, _facing_yaw, minf(delta * (2.0 + 6.0 * grip), 1.0))

	# Jumping.
	if _jump_buffer_timer > 0.0 and (on_floor or _coyote_timer > 0.0) and _stumble_timer <= 0.0:
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		vertical_velocity = JUMP_VELOCITY
		_airborne_from_jump = true
		_set_state(State.AIRBORNE)
		if visual != null:
			visual.trigger_squash(1.28)
		AudioManager.play_sfx_3d("sfx_jump", global_position, randf_range(0.95, 1.08))
	elif on_floor and vertical_velocity < 0.0:
		vertical_velocity = -2.0
	else:
		vertical_velocity -= GRAVITY * delta

	# Shove.
	if controller.shove_pressed and _shove_cooldown <= 0.0 and state != State.FINISHED:
		_attempt_shove()

	_apply_velocity()
	_was_on_floor = on_floor
	_slide_particles.emitting = sliding and on_floor and current_speed > 6.0
	_set_crouched(state == State.SLIDING or state == State.SWIMMING)


func _tick_swimming(delta: float) -> void:
	var surface := SurfacesDB.get_item(SurfacesDB.Surface.WATER)
	var target := BASE_SPEED * float(surface["max_speed"]) * speed_scale * boost_mult
	current_speed = move_toward(current_speed, target, 10.0 * delta)

	var steer := clampf(controller.steer, -1.0, 1.0)
	_steer_offset = lerpf(_steer_offset, steer * deg_to_rad(45.0), minf(delta * 6.0, 1.0))
	_facing_yaw = _wrap_lerp_angle(_facing_yaw, _guide_yaw + _steer_offset, minf(delta * 5.0, 1.0))
	_velocity_yaw = _wrap_lerp_angle(_velocity_yaw, _facing_yaw, minf(delta * 6.0, 1.0))

	# Buoyancy spring toward just below the surface; dive / burst inputs.
	var target_y := _water_surface_y - 0.35
	if controller.slide_held:
		target_y = _water_surface_y - 1.4
	var y_error := target_y - global_position.y
	vertical_velocity = lerpf(vertical_velocity, y_error * 4.0, minf(delta * 5.0, 1.0))
	if _jump_buffer_timer > 0.0:
		_jump_buffer_timer = 0.0
		vertical_velocity = 7.5
		current_speed = minf(current_speed + 3.0, SLIDE_MAX_SPEED)
		AudioManager.play_sfx_3d("sfx_splash", global_position, randf_range(1.0, 1.15), -4.0)
	if _water_areas.is_empty():
		_set_state(State.AIRBORNE)
	_apply_velocity()


func _tick_stunned(delta: float) -> void:
	_stun_timer -= delta
	current_speed = move_toward(current_speed, 0.0, 18.0 * delta)
	if is_on_floor():
		vertical_velocity = -2.0
	else:
		vertical_velocity -= GRAVITY * delta
	_apply_velocity()
	if _stun_timer <= 0.0:
		_invuln_timer = 1.4
		stunned_changed.emit(self, false)
		_set_state(State.WADDLING)


func _tick_recovering(delta: float) -> void:
	_recover_timer -= delta
	current_speed = move_toward(current_speed, BASE_SPEED * 0.5, 8.0 * delta)
	_facing_yaw = _wrap_lerp_angle(_facing_yaw, _guide_yaw, minf(delta * 6.0, 1.0))
	_velocity_yaw = _facing_yaw
	if is_on_floor():
		vertical_velocity = -2.0
	else:
		vertical_velocity -= GRAVITY * delta
	_apply_velocity()
	if _recover_timer <= 0.0:
		_set_state(State.WADDLING)


func _tick_finished(delta: float) -> void:
	_finish_slowdown = maxf(_finish_slowdown - delta * 0.35, 0.0)
	# Never coast off the end of the course after finishing.
	if course != null and course.get("main_guide") != null:
		var guide: PathGuide = course.get("main_guide")
		if progress > guide.length - 12.0:
			_finish_slowdown = 0.0
	current_speed = move_toward(current_speed, BASE_SPEED * 0.5 * _finish_slowdown, 6.0 * delta)
	_steer_offset = lerpf(_steer_offset, 0.0, minf(delta * 4.0, 1.0))
	_facing_yaw = _wrap_lerp_angle(_facing_yaw, _guide_yaw, minf(delta * 4.0, 1.0))
	_velocity_yaw = _facing_yaw
	if is_on_floor():
		vertical_velocity = -2.0
	else:
		vertical_velocity -= GRAVITY * delta
	_apply_velocity()


func _apply_velocity() -> void:
	var dir := _yaw_to_dir(_velocity_yaw)
	velocity = dir * current_speed + Vector3.UP * vertical_velocity
	rotation.y = _facing_yaw


## --- State helpers ---------------------------------------------------------

func _set_state(new_state: State) -> void:
	if state == new_state or state == State.FINISHED:
		return
	state = new_state
	state_changed.emit(new_state)


func _land_feedback() -> void:
	if visual != null:
		visual.trigger_squash(0.72)
	AudioManager.play_sfx_3d("sfx_land", global_position, randf_range(0.92, 1.05), -6.0)
	if course != null and course.has_method("spawn_land_puff"):
		course.spawn_land_puff(global_position)


func _update_visual(delta: float) -> void:
	if visual == null:
		return
	var ratio := current_speed / BASE_SPEED
	visual.anim_speed = ratio
	match state:
		State.WADDLING, State.BOOSTED:
			visual.set_pose(PenguinVisual.Pose.RUN if current_speed > 1.0 else PenguinVisual.Pose.IDLE)
		State.SLIDING:
			visual.set_pose(PenguinVisual.Pose.SLIDE)
		State.AIRBORNE:
			visual.set_pose(PenguinVisual.Pose.AIR)
		State.SWIMMING:
			visual.set_pose(PenguinVisual.Pose.SWIM)
		State.STUNNED:
			visual.set_pose(PenguinVisual.Pose.STUN)
		State.RECOVERING:
			visual.set_pose(PenguinVisual.Pose.RUN)
		State.FINISHED:
			visual.set_pose(PenguinVisual.Pose.CELEBRATE if race_position <= 3 else PenguinVisual.Pose.DEFEAT)
	visual.tick(delta, clampf(ratio, 0.0, 1.5))


## --- Interactions ----------------------------------------------------------

func _attempt_shove() -> void:
	_shove_cooldown = SHOVE_COOLDOWN
	AudioManager.play_sfx_3d("sfx_shove", global_position, randf_range(0.9, 1.1))
	var best: Racer = null
	var best_distance := SHOVE_RANGE
	for node: Node in get_tree().get_nodes_in_group(GameConfig.GROUP_RACERS):
		var other := node as Racer
		if other == null or other == self or other.state == State.FINISHED:
			continue
		var distance := global_position.distance_to(other.global_position)
		if distance < best_distance:
			best = other
			best_distance = distance
	if best != null and best.receive_shove(self):
		shove_landed.emit(self, best)


## Returns true if the shove connected.
func receive_shove(attacker: Racer) -> bool:
	if _shove_immunity > 0.0 or _invuln_timer > 0.0 or _has_shield:
		if _has_shield:
			break_shield()
		return false
	_shove_immunity = 2.2
	_stumble_timer = STUMBLE_TIME
	var push := (global_position - attacker.global_position).normalized()
	global_position += push * 0.6
	_steer_offset += signf(push.dot(_yaw_to_dir(_velocity_yaw + PI / 2.0))) * deg_to_rad(25.0)
	current_speed *= 0.72
	if visual != null:
		visual.trigger_squash(0.8)
	AudioManager.play_sfx_3d("sfx_stumble", global_position, randf_range(0.9, 1.1))
	return true


## Comedic stumble away from a world position (seal bumps, soft hazards).
func receive_shove_from_position(source: Vector3) -> void:
	if _invuln_timer > 0.0 or state == State.FINISHED:
		return
	if _has_shield:
		break_shield()
		return
	_stumble_timer = STUMBLE_TIME
	var push := (global_position - source).normalized()
	push.y = 0.0
	global_position += push * 0.5
	current_speed *= 0.65
	if visual != null:
		visual.trigger_squash(0.78)


## Full stun (snowball hit, major hazard).
func apply_stun(source: String = "") -> bool:
	if _invuln_timer > 0.0 or state == State.FINISHED:
		return false
	if _has_shield:
		break_shield()
		return false
	_stun_timer = STUN_TIME
	stunned_changed.emit(self, true)
	_set_state(State.STUNNED)
	if visual != null:
		visual.trigger_squash(0.6)
	AudioManager.play_sfx_3d("sfx_impact", global_position, randf_range(0.9, 1.08))
	return true


func apply_boost(duration: float, mult: float = 1.45) -> void:
	_boost_timer = maxf(_boost_timer, duration)
	boost_mult = mult
	if state == State.WADDLING:
		_set_state(State.BOOSTED)


func apply_blizzard_slip(duration: float) -> void:
	if _has_shield:
		break_shield()
		return
	_blizzard_slip_timer = duration


func give_shield() -> void:
	_has_shield = true
	if _shield_visual == null and visual != null:
		var sphere := SphereMesh.new()
		sphere.radius = 0.85
		sphere.height = 1.7
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.5, 0.85, 1.0, 0.3)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.rim_enabled = true
		mat.rim = 0.8
		sphere.material = mat
		_shield_visual = MeshInstance3D.new()
		_shield_visual.mesh = sphere
		_shield_visual.position.y = 0.55
		add_child(_shield_visual)
	if _shield_visual != null:
		_shield_visual.visible = true


func has_shield() -> bool:
	return _has_shield


func break_shield() -> void:
	_has_shield = false
	if _shield_visual != null:
		_shield_visual.visible = false
	AudioManager.play_sfx_3d("sfx_shield_break", global_position)
	_invuln_timer = maxf(_invuln_timer, 0.8)


func collect_fish(value: int) -> void:
	fish_count += value
	fish_collected.emit(self, value)


func receive_item(item_id: String) -> void:
	if held_item != "" or state == State.FINISHED:
		return
	held_item = item_id
	item_received.emit(self, item_id)


func use_held_item() -> String:
	if held_item == "":
		return ""
	var id := held_item
	held_item = ""
	item_used.emit(self, id)
	return id


## --- Water ------------------------------------------------------------------

func enter_water(area: Area3D, surface_y: float) -> void:
	if area not in _water_areas:
		_water_areas.append(area)
	_water_surface_y = surface_y
	if state != State.SWIMMING and state != State.FINISHED and global_position.y < surface_y + 0.3:
		_set_state(State.SWIMMING)
		vertical_velocity = minf(vertical_velocity, 0.0)
		AudioManager.play_sfx_3d("sfx_splash", global_position, randf_range(0.9, 1.05))
		if course != null and course.has_method("spawn_splash"):
			course.spawn_splash(global_position)


func exit_water(area: Area3D) -> void:
	_water_areas.erase(area)
	if _water_areas.is_empty() and state == State.SWIMMING:
		_set_state(State.AIRBORNE)


## --- Checkpoints & recovery -------------------------------------------------

func on_checkpoint(index: int, checkpoint_transform: Transform3D) -> void:
	if index > last_checkpoint_index and state != State.FINISHED:
		last_checkpoint_index = index
		last_checkpoint_transform = checkpoint_transform
		checkpoint_reached.emit(self, index)


func respawn_at_checkpoint() -> void:
	if state == State.FINISHED:
		return
	global_transform = last_checkpoint_transform
	global_position += Vector3.UP * 1.0
	var forward := -last_checkpoint_transform.basis.z
	_facing_yaw = atan2(-forward.x, -forward.z)
	_velocity_yaw = _facing_yaw
	_steer_offset = 0.0
	current_speed = BASE_SPEED * 0.35
	vertical_velocity = 0.0
	_water_areas.clear()
	guide_cache = {}  # force fresh global guide search from the new position
	_invuln_timer = 2.0
	_recover_timer = RECOVER_TIME
	_set_state(State.RECOVERING)
	respawned.emit(self)
	AudioManager.play_sfx_3d("sfx_respawn", global_position, 1.0, -6.0)


func _check_kill_plane() -> void:
	if course == null or global_position.y >= float(course.get("kill_y")):
		return
	if state == State.FINISHED:
		# Finished racers that somehow tumble off just snap back on-track.
		global_transform = last_checkpoint_transform
		current_speed = 0.0
		vertical_velocity = 0.0
		return
	respawn_at_checkpoint()


func finish_race_now(time_seconds: float) -> void:
	if state == State.FINISHED:
		return
	finish_time = time_seconds
	_finish_slowdown = 1.0
	state = State.FINISHED
	state_changed.emit(State.FINISHED)
	race_finished.emit(self)


func is_stunned_or_recovering() -> bool:
	return state == State.STUNNED or state == State.RECOVERING


## Low profile while sliding/swimming so racers fit under low obstacles.
func _set_crouched(crouched: bool) -> void:
	if _crouched == crouched or _capsule == null:
		return
	_crouched = crouched
	if crouched:
		_capsule.height = 0.7
		_collision_shape.position.y = 0.36
	else:
		_capsule.height = 1.0
		_collision_shape.position.y = 0.55


func _ceiling_blocked() -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.4,
		global_position + Vector3.UP * 1.35,
		GameConfig.LAYER_WORLD
	)
	query.exclude = [get_rid()]
	return not space.intersect_ray(query).is_empty()


func _yaw_to_dir(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _wrap_lerp_angle(from: float, to: float, weight: float) -> float:
	return lerp_angle(from, to, weight)
