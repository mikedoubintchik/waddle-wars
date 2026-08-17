class_name Racer
extends CharacterBody3D
## Core racer: state machine, surface-aware movement, jumping with coyote
## time and input buffering, belly sliding, swimming, shoving, items,
## checkpoint recovery. Driven by a RacerController (player or AI).
##
## Feel layer: jump arcs hang briefly at the apex then fall fast; walls
## deflect instead of stopping (velocity projects along the surface);
## racer-vs-racer contact trades momentum by "mass" (boost = heavier);
## shoves knock the victim into a short forced slide through move_and_slide;
## riders inherit moving-platform velocity so icebergs don't slip out from
## underfoot. All of it lives on top of the scalar-speed model — external
## pushes go through velocity, never position teleports.

enum State { WADDLING, SLIDING, AIRBORNE, SWIMMING, BOOSTED, STUNNED, RECOVERING, FINISHED }

signal state_changed(new_state: State)
signal checkpoint_reached(racer: Racer, index: int)
signal race_finished(racer: Racer)
signal fish_collected(racer: Racer, value: int)
signal item_received(racer: Racer, item_id: String)
signal item_used(racer: Racer, item_id: String)
signal snowball_ammo_changed(racer: Racer, ammo: int)
signal shove_landed(attacker: Racer, victim: Racer)
## Fired on the VICTIM of a connected shove. shove_landed fires on the
## attacker and is what progression counts; this is the other half, so the
## camera and the controller can react when the hit is taken rather than dealt.
signal shoved(racer: Racer, attacker: Racer)
signal respawned(racer: Racer)
signal stunned_changed(racer: Racer, is_stunned: bool)
## Fired whenever the ice shield starts, is broken, or runs out. `active` is
## the new state; the HUD reads shield_remaining() for the countdown.
signal shield_changed(racer: Racer, active: bool)

const GRAVITY: float = 30.0
const JUMP_VELOCITY: float = 11.0
const BASE_SPEED: float = 12.5
const SLIDE_MAX_SPEED: float = 26.0
## Baseline braking after crossing the line -- a deliberate coast-down, not a
## wall. _tick_finished raises it as far as the remaining runway demands.
const FINISH_DECEL: float = 9.0
## Metres of guide kept in hand past the stopping point.
const FINISH_RUNWAY_MARGIN: float = 6.0
## Over this much remaining runway the post-finish coast target tapers to zero.
const FINISH_TAPER_DISTANCE: float = 38.0
const SLOPE_SLIDE_ACCEL: float = 15.0
const COYOTE_TIME: float = 0.14
const JUMP_BUFFER: float = 0.16
const APEX_HANG_SPEED: float = 2.6  # |v_y| window treated as the jump apex
const APEX_HANG_GRAVITY: float = 0.55  # gravity scale inside the apex hang
const FALL_GRAVITY: float = 1.45  # gravity scale while descending from a jump
const MAX_FALL_SPEED: float = 38.0  # terminal velocity (kill-plane dives)
## Contacts at or below this height (metres above the racer origin) belong to
## hurdles the penguin is expected to jump, so they never deflect a heading.
const JUMPABLE_HEIGHT: float = 1.1
const KNOCK_DECAY: float = 16.0  # m/s^2 bleed on shove/seal knockback slides
const MAX_STEER_DEG: float = 55.0
const STEER_AUTHORITY_MAX: float = 1.6  # yaw response scales with speed up to this
const BOOST_MAX_MULT: float = 1.5  # apply_boost() clamp
const BOOST_TOP_SPEED_MULT: float = 1.55  # cap on surface max_speed * boost_mult
const BOOST_SLIDE_TOP_MULT: float = 1.6  # cap on slide_target * boost_mult
const BOOST_FADE_BASE: float = 0.18  # boost fade floor (mult/s) — ease-out tail
const BOOST_FADE_SCALE: float = 0.9  # extra fade per unit of boost above 1.0
const BOOST_STRAIGHTEN_RATE: float = 0.8  # heading pull toward guide tangent while boosted
## Lateral acceleration a fully banked surface adds, in m/s^2, pulling the
## racer down the camber. Banked corners are geometry alone until something
## makes them push: this is what turns a banked corner into a corner that
## helps you, and running wide onto the high side into a real mistake.
## Deliberately gentle -- it biases a line, it does not drive one.
## Belly-slide spray tuning: below this speed a slide throws nothing, and this
## much steering angle counts as a full-lock carve for spray purposes.
const SPRAY_MIN_SPEED: float = 6.0
const SPRAY_FULL_CARVE_DEG: float = 26.0
const SPRAY_MIN_RATIO: float = 0.18
const CAMBER_ACCEL: float = 7.0
## Camber is felt most on a belly slide (no feet to edge with); on foot the
## racer grips far more of it away.
const CAMBER_WADDLE_SCALE: float = 0.35
const BANK_MAX_DEG: float = 15.0  # visual roll into turns
## Surface conform: how far the body will lean to match the ground it is
## standing on, as the sine of the angle (0.32 ~= 18.7 degrees, comfortably
## past TrackBuilder.MAX_BANK_DEG), and how fast it settles there. Slower than
## the steering lean on purpose -- terrain arrives under you, it is not
## something you do.
const SURFACE_CONFORM_SIN: float = 0.32
const SURFACE_CONFORM_RATE: float = 8.5
## Weight transfer: radians of body pitch per m/s^2 of acceleration, and the
## cap. Deliberately small; past this it reads as a wheelie.
const WEIGHT_PITCH_SCALE: float = 0.010
const WEIGHT_PITCH_MAX: float = 0.13
const BANK_YAW_RATE_SCALE: float = 0.32  # rad of roll per rad/s of yaw rate
const SHOVE_COOLDOWN: float = 1.6
const SHOVE_RANGE: float = 2.4
const STUN_TIME: float = 1.1
const STUMBLE_TIME: float = 0.55
const RECOVER_TIME: float = 0.9
const MAX_SNOWBALL_AMMO: int = 3
## Seconds an unused ice shield lasts. It still blocks exactly one hit; this is
## the window in which it is available to do so.
##
## Without a clock a shield taken on a clean run simply never ended, so the
## player carried a glowing bubble to the finish and the power-up read as
## broken. 8s sits with the rest of the table -- magnet 6s, blizzard cloud 5s --
## and is long enough to cover the stretch after a pickup where an attack is
## actually likely.
const SHIELD_DURATION: float = 8.0
## Tail of SHIELD_DURATION during which the shell visibly winds down, so the
## shield never vanishes without warning.
const SHIELD_WARN: float = 2.5

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
var snowball_ammo: int = 0  # collected throwable snowballs (0..MAX_SNOWBALL_AMMO)
var current_surface: SurfacesDB.Surface = SurfacesDB.Surface.PACKED_SNOW

var _facing_yaw: float = 0.0
var _velocity_yaw: float = 0.0
## Sideways drift accumulated from the surface camber, in world space.
var _camber_velocity: Vector3 = Vector3.ZERO
var _prev_facing_yaw: float = 0.0
var _visual_bank: float = 0.0
var _visual_pitch: float = 0.0
## Surface-conform lean and weight-transfer pitch, smoothed (see _update_visual).
var _surface_roll: float = 0.0
var _surface_pitch: float = 0.0
var _weight_pitch: float = 0.0
var _prev_speed: float = 0.0
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
var _shield_material: ShaderMaterial = null
var _shield_timer: float = 0.0
var _was_on_floor: bool = false
var _airborne_from_jump: bool = false
var _knock_velocity: Vector3 = Vector3.ZERO  # decaying shove/bump slide
var _wall_sfx_cooldown: float = 0.0
var _platform_node: AnimatableBody3D = null  # moving platform underfoot
var _platform_prev_origin: Vector3 = Vector3.ZERO
var _platform_velocity: Vector3 = Vector3.ZERO
var _platform_carry_timer: float = 0.0  # keeps inherited momentum after leaving
var _slide_particles: GPUParticles3D = null
var _snow_trail: SnowTrail = null
var _slide_audio: AudioStreamPlayer3D = null
var _bubble_particles: GPUParticles3D = null
var _finish_slowdown: float = 1.0
var _collision_shape: CollisionShape3D = null
var _capsule: CapsuleShape3D = null
var _crouched: bool = false
var _swim_stroke_timer: float = 0.0
# Cached ray queries: rebuilt params + exclude array every tick per racer
# showed up in profiling, so these are created once and only from/to mutate.
var _surface_query: PhysicsRayQueryParameters3D = null
var _ceiling_query: PhysicsRayQueryParameters3D = null
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
	_surface_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, GameConfig.LAYER_WORLD, [get_rid()])
	_ceiling_query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, GameConfig.LAYER_WORLD, [get_rid()])
	_make_slide_particles()
	_make_slide_audio()


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
	var trail_id := String(visual_config.get("trail", ""))
	if trail_id != "" and not GameConfig.is_headless():
		var trail := TrailEffect.create(trail_id)
		if trail != null:
			add_child(trail)
	# Carved snow groove behind every racer. Child of the racer so it dies with
	# it, top_level so the carved line stays where it was carved.
	if not GameConfig.is_headless():
		_snow_trail = SnowTrail.new()
		add_child(_snow_trail)
		_snow_trail.setup()
	_facing_yaw = rotation.y
	_velocity_yaw = rotation.y
	_prev_facing_yaw = rotation.y
	last_checkpoint_transform = global_transform


## Looping scrape emitter, owned by the racer so it follows in 3D and so eight
## racers cannot exhaust the shared one-shot SFX pool between them.
func _make_slide_audio() -> void:
	if GameConfig.is_headless() or not AudioManager.has_sound("sfx_slide"):
		return
	var shared := AudioManager.get_stream("sfx_slide")
	if shared == null:
		return
	# Duplicate before touching loop_mode. get_stream() hands back the one
	# shared resource for that key, so looping it in place looped it for every
	# other caller too -- including the wind zone's one-shot whoosh, which then
	# never stopped and, one instance every 2.6 s, walked the whole SFX pool
	# into permanently-busy loops. That is the "everything sounds broken and
	# something is whooshing forever" bug; the copy is what makes it local.
	var stream := shared.duplicate() as AudioStream
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			var bytes_per_sample := 2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1
			var channels := 2 if wav.stereo else 1
			wav.loop_end = wav.data.size() / (bytes_per_sample * channels)
	_slide_audio = AudioStreamPlayer3D.new()
	_slide_audio.stream = stream
	_slide_audio.bus = &"SFX"
	_slide_audio.max_distance = 60.0
	_slide_audio.volume_db = -16.0
	add_child(_slide_audio)


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
	# Underwater bubbles while swimming.
	_bubble_particles = GPUParticles3D.new()
	var bubble_mat := ParticleProcessMaterial.new()
	bubble_mat.direction = Vector3.UP
	bubble_mat.spread = 20.0
	bubble_mat.initial_velocity_min = 0.8
	bubble_mat.initial_velocity_max = 1.8
	bubble_mat.gravity = Vector3(0, 2.5, 0)
	bubble_mat.scale_min = 0.3
	bubble_mat.scale_max = 0.8
	bubble_mat.color = Color(0.8, 0.95, 1.0, 0.7)
	_bubble_particles.process_material = bubble_mat
	var bubble := SphereMesh.new()
	bubble.radius = 0.05
	bubble.height = 0.1
	bubble.radial_segments = 6
	bubble.rings = 4
	var bubble_draw := StandardMaterial3D.new()
	bubble_draw.albedo_color = Color(0.85, 0.96, 1.0, 0.55)
	bubble_draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bubble_draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bubble.material = bubble_draw
	_bubble_particles.draw_pass_1 = bubble
	_bubble_particles.amount = 16
	_bubble_particles.lifetime = 0.8
	_bubble_particles.emitting = false
	_bubble_particles.position = Vector3(0, 0.4, 0.3)
	add_child(_bubble_particles)


func _physics_process(delta: float) -> void:
	if course == null or controller == null:
		return
	controller.tick(delta)
	_update_timers(delta)
	_update_guide()
	_detect_surface()
	_update_platform_carry(delta)
	if _snow_trail != null:
		_snow_trail.tick(global_position, get_floor_normal() if is_on_floor() else Vector3.UP,
			is_on_floor() and (current_surface == SurfacesDB.Surface.PACKED_SNOW
				or current_surface == SurfacesDB.Surface.DEEP_SNOW),
			state == State.SLIDING, current_speed)

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

	if controller.item_pressed and state != State.FINISHED:
		# Item key priority: a held item always fires first; bare-handed it
		# throws a collected snowball instead (no extra binding needed).
		if held_item != "":
			use_held_item()
		elif snowball_ammo > 0:
			throw_snowball()
	_update_camber(delta)
	move_and_slide()
	_resolve_contacts(delta)
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
	_wall_sfx_cooldown = maxf(0.0, _wall_sfx_cooldown - delta)
	if _has_shield:
		_shield_timer = maxf(0.0, _shield_timer - delta)
		# The shell reads its own remaining life, so the last seconds thin and
		# flicker rather than the bubble simply blinking out of existence.
		if _shield_material != null:
			_shield_material.set_shader_parameter(
				"charge", clampf(_shield_timer / SHIELD_WARN, 0.0, 1.0))
		if _shield_timer <= 0.0:
			_expire_shield()
	if _knock_velocity != Vector3.ZERO:
		_knock_velocity = _knock_velocity.move_toward(Vector3.ZERO, KNOCK_DECAY * delta)
	if _boost_timer <= 0.0 and boost_mult > 1.0:
		# Ease-out fade instead of a cliff: fast falloff at full boost that
		# tapers as it nears base pace (~1.2s total, same as the old linear
		# fade, but the end of a boost reads as a glide instead of a wall).
		boost_mult = maxf(1.0, boost_mult - (BOOST_FADE_BASE + (boost_mult - 1.0) * BOOST_FADE_SCALE) * delta)
	if controller.jump_pressed:
		_jump_buffer_timer = JUMP_BUFFER
		controller.consume_jump()


func _update_guide() -> void:
	var guide: Dictionary = course.get_guide(self)
	_guide_yaw = float(guide.get("yaw", _guide_yaw))
	progress = float(guide.get("progress", progress))
	total_progress = float(last_checkpoint_index + 1) * 10000.0 + progress


## Drift volumes currently containing this racer (see SnowDriftField).
var _drift_count: int = 0


func enter_snow_drift() -> void:
	_drift_count += 1


func exit_snow_drift() -> void:
	_drift_count = maxi(0, _drift_count - 1)


func _detect_surface() -> void:
	if not _water_areas.is_empty():
		current_surface = SurfacesDB.Surface.WATER
		return
	var space := get_world_3d().direct_space_state
	_surface_query.from = global_position + Vector3.UP * 0.5
	_surface_query.to = global_position + Vector3.DOWN * 2.5
	var hit := space.intersect_ray(_surface_query)
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider")
	if collider != null and collider.has_meta("surface"):
		current_surface = collider.get_meta("surface") as SurfacesDB.Surface
	else:
		current_surface = SurfacesDB.Surface.PACKED_SNOW
	# Standing in a drift ploughs like deep snow whatever the deck underneath
	# is tagged as. The surface ray only ever sees the geometry BELOW the
	# racer, and a drift is piled on top of it, so it can never be found that
	# way -- SnowDriftField reports it instead.
	if _drift_count > 0:
		current_surface = SurfacesDB.Surface.DEEP_SNOW
		return
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
			_land_feedback(vertical_velocity)
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
		var downhill_dot := downhill.dot(forward)
		var slope_push := downhill_dot * SLOPE_SLIDE_ACCEL
		current_speed += (slope_push + float(surface["slide_bonus"])) * delta
		# Slick surfaces sustain a belly slide well above waddle pace on flat
		# or descending ground (penguins are fast on ice). Never applied while
		# ascending, so the uphill stall stand-up below still bleeds speed
		# under its 5.0 threshold (QA finding).
		# Boost stacks multiplicatively with slick-surface targets, so cap the
		# combined multiplier: a pad hit mid-slide tops out ~1.6x base instead
		# of 2x+ (playtest: boosted racers became uncontrollable).
		var slide_target := BASE_SPEED * minf(float(surface["slide_target"]) * boost_mult, BOOST_SLIDE_TOP_MULT) * speed_scale
		var slide_ramp := float(surface["slide_ramp"])
		if slide_ramp > 0.0 and on_floor and downhill_dot >= -0.02 and current_speed < slide_target:
			current_speed = move_toward(current_speed, slide_target, slide_ramp * delta)
		current_speed = clampf(current_speed, 0.0, SLIDE_MAX_SPEED)
		# Sliding uphill or into deep snow bleeds speed fast; standing back up
		# is handled once speed drops below waddle pace. Same downhill gate as
		# the ramp above: on ascents the floor must not hold speed, or the <5.0
		# stall stand-up never fires (QA finding).
		if downhill_dot >= -0.02 and current_speed < BASE_SPEED * 0.55 * speed_scale:
			current_speed = move_toward(current_speed, BASE_SPEED * 0.55 * speed_scale, 4.0 * delta)
	else:
		# Same combined cap as sliding: surface speed and boost never stack past
		# ~1.55x base, keeping top boost speed inside steerable range.
		var target := BASE_SPEED * minf(float(surface["max_speed"]) * boost_mult, BOOST_TOP_SPEED_MULT) * speed_scale * stumble_mult * _finish_slowdown
		var accel := 14.0 * float(surface["accel"])
		if not on_floor:
			accel *= 0.5
		current_speed = move_toward(current_speed, target, accel * delta)

	# Steering.
	var grip := float(surface["grip"])
	if not on_floor:
		grip *= 0.45
	if sliding:
		# Belly grip scales with the surface itself: packed snow still bites
		# (~0.75x) while smooth ice drops to ~0.5x, so ice slides drift wide
		# and carve late where snow slides stay planted and steerable.
		grip *= 0.30 + 0.45 * float(surface["grip"])
	var sensitivity := 1.0
	if is_player:
		sensitivity = float(SettingsManager.get_setting("gameplay", "steer_sensitivity"))
	var steer := clampf(controller.steer, -1.0, 1.0) * sensitivity
	if _stumble_timer > 0.0:
		steer *= 0.4
	var steer_target := steer * deg_to_rad(MAX_STEER_DEG)
	# Yaw response scales with speed so the turning radius stays roughly
	# constant: without this, boost pads doubled speed while turn rate stayed
	# tuned for BASE_SPEED and the racer felt like a runaway sled (playtest).
	var speed_authority := clampf(current_speed / BASE_SPEED, 1.0, STEER_AUTHORITY_MAX)
	# Below waddle pace the nose answers faster still: pulling out of a
	# stumble, respawn, or standing start feels immediate, not barge-like.
	# A low-speed steering boost was tried here (1.45x below base speed) to make
	# standing starts and post-stumble turns answer instantly. It over-steered
	# guide-following racers into a wall-hugging oscillation and deadlocked the
	# tutorial autopilot, so yaw response stays flat across the speed range.
	var low_speed_assist := 1.0
	_steer_offset = lerpf(_steer_offset, steer_target, minf(delta * 7.0 * grip * speed_authority * low_speed_assist, 1.0))
	_facing_yaw = _wrap_lerp_angle(_facing_yaw, _guide_yaw + _steer_offset, minf(delta * 5.0 * speed_authority * low_speed_assist, 1.0))
	if boost_mult > 1.02:
		# Light auto-straighten while boosted: pull the heading toward the
		# guide tangent so a pad hit mid-corner doesn't launch into the walls.
		# Fades out with active steering input so it never fights the player.
		var straighten := BOOST_STRAIGHTEN_RATE * (1.0 - absf(steer))
		if straighten > 0.0:
			_facing_yaw = _wrap_lerp_angle(_facing_yaw, _guide_yaw, minf(delta * straighten, 1.0))
	_velocity_yaw = _wrap_lerp_angle(_velocity_yaw, _facing_yaw, minf(delta * (2.0 + 6.0 * grip) * speed_authority, 1.0))

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
		vertical_velocity = maxf(vertical_velocity - GRAVITY * _jump_gravity_scale() * delta, -MAX_FALL_SPEED)

	# Shove.
	if controller.shove_pressed and _shove_cooldown <= 0.0 and state != State.FINISHED:
		_attempt_shove()

	_apply_velocity()
	_was_on_floor = on_floor
	_update_slide_spray(on_floor)
	_update_slide_loop(on_floor)
	_set_crouched(state == State.SLIDING or state == State.SWIMMING)


## Continuous belly-slide scrape.
##
## This used to be a one-shot fired on entering the slide state, so any slide
## longer than the sample went silent while the penguin was visibly still
## scraping along the ice -- the single most-heard sound in the game, missing
## for most of its duration. It is now a looping emitter owned by the racer,
## with pitch and volume tracking speed so a fast slide is heard as a fast one.
func _update_slide_loop(on_floor: bool) -> void:
	if _slide_audio == null:
		return
	var active := state == State.SLIDING and on_floor and current_speed > SPRAY_MIN_SPEED
	if not active:
		if _slide_audio.playing:
			_slide_audio.stop()
		return
	var ratio := clampf(current_speed / SLIDE_MAX_SPEED, 0.0, 1.0)
	_slide_audio.pitch_scale = 0.86 + ratio * 0.34
	_slide_audio.volume_db = lerpf(-16.0, -5.0, ratio)
	if not _slide_audio.playing:
		_slide_audio.play()


## Spray volume tracks how hard the racer is actually working the surface.
##
## It used to be a boolean above 6 m/s, so a gentle straight-line slide threw
## exactly as much snow as a full-lock carve through a banked corner -- the
## effect carried no information. Emission now scales with speed over the
## threshold and with how far the nose is turned out of the guide line, which
## is the moment a slide is biting and the moment spray should sell it.
func _update_slide_spray(on_floor: bool) -> void:
	var active := state == State.SLIDING and on_floor and current_speed > SPRAY_MIN_SPEED
	_slide_particles.emitting = active
	if not active:
		return
	var speed_part := clampf(
		(current_speed - SPRAY_MIN_SPEED) / maxf(SLIDE_MAX_SPEED - SPRAY_MIN_SPEED, 0.001), 0.0, 1.0)
	var carve_part := clampf(absf(_steer_offset) / deg_to_rad(SPRAY_FULL_CARVE_DEG), 0.0, 1.0)
	# Carve dominates: a hard direction change should read louder than raw pace.
	_slide_particles.amount_ratio = clampf(
		SPRAY_MIN_RATIO + speed_part * 0.35 + carve_part * 0.55, SPRAY_MIN_RATIO, 1.0)


func _tick_swimming(delta: float) -> void:
	var surface := SurfacesDB.get_item(SurfacesDB.Surface.WATER)
	var target := BASE_SPEED * float(surface["max_speed"]) * speed_scale * boost_mult
	current_speed = move_toward(current_speed, target, 10.0 * delta)

	var steer := clampf(controller.steer, -1.0, 1.0)
	_steer_offset = lerpf(_steer_offset, steer * deg_to_rad(45.0), minf(delta * 6.0, 1.0))
	_facing_yaw = _wrap_lerp_angle(_facing_yaw, _guide_yaw + _steer_offset, minf(delta * 5.0, 1.0))
	_velocity_yaw = _wrap_lerp_angle(_velocity_yaw, _facing_yaw, minf(delta * 6.0, 1.0))

	# Periodic stroke audio while actually moving through the water.
	_swim_stroke_timer -= delta
	if _swim_stroke_timer <= 0.0 and current_speed > 2.0:
		_swim_stroke_timer = randf_range(0.55, 0.75)
		AudioManager.play_sfx_3d("sfx_swim", global_position, randf_range(0.92, 1.08), -8.0)

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
	if _bubble_particles != null:
		_bubble_particles.emitting = global_position.y < _water_surface_y - 0.1
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
	_finish_slowdown = maxf(_finish_slowdown - delta * 0.9, 0.0)
	var target := BASE_SPEED * 0.5 * _finish_slowdown
	var decel := FINISH_DECEL
	# Stop inside whatever track is actually left.
	#
	# The old rule braked at a flat 6 m/s^2 and only zeroed the coast target in
	# the last 12 m. A racer crossing the line at full tilt needs roughly fifty
	# metres to shed that, so on any course whose finish sits near the end of
	# the guide the penguin sailed straight off the far edge. Now the coast
	# target tapers over the final stretch and the brake is whatever rate the
	# remaining runway demands, so the stop is guaranteed rather than hoped for.
	if course != null and course.get("main_guide") != null:
		var guide: PathGuide = course.get("main_guide")
		var runway := maxf(guide.length - FINISH_RUNWAY_MARGIN - progress, 0.0)
		target *= clampf(runway / FINISH_TAPER_DISTANCE, 0.0, 1.0)
		if runway > 0.5:
			decel = maxf(decel, (current_speed * current_speed) / (2.0 * runway))
		else:
			decel = maxf(decel, FINISH_DECEL * 6.0)
	current_speed = move_toward(current_speed, target, decel * delta)
	_steer_offset = lerpf(_steer_offset, 0.0, minf(delta * 4.0, 1.0))
	_facing_yaw = _wrap_lerp_angle(_facing_yaw, _guide_yaw, minf(delta * 4.0, 1.0))
	_velocity_yaw = _facing_yaw
	if is_on_floor():
		vertical_velocity = -2.0
	else:
		vertical_velocity -= GRAVITY * delta
	_apply_velocity()


## External forces (wind, racer bumps), accumulated then consumed every
## physics tick so pushes go through move_and_slide and can never tunnel
## through colliders.
var _external_push: Vector3 = Vector3.ZERO


func apply_wind(push: Vector3) -> void:
	_external_push += push


func _apply_velocity() -> void:
	var dir := _yaw_to_dir(_velocity_yaw)
	velocity = dir * current_speed + Vector3.UP * vertical_velocity \
			+ _external_push + _knock_velocity + _platform_velocity + _camber_velocity
	_external_push = Vector3.ZERO
	rotation.y = _facing_yaw


## Sideways pull from a banked surface, integrated as its own velocity so it
## biases the line without fighting the guide-relative steering model (which
## owns heading). Only the cross-track component counts -- along-track slope is
## already handled as slope acceleration by the speed code above.
func _update_camber(delta: float) -> void:
	if not is_on_floor() or state == State.FINISHED:
		_camber_velocity = _camber_velocity.lerp(Vector3.ZERO, minf(delta * 6.0, 1.0))
		return
	var normal := get_floor_normal()
	# Flat ground has nothing to give, and a wall-steep hit is not camber.
	if normal.y > 0.999 or normal.y < 0.35:
		_camber_velocity = _camber_velocity.lerp(Vector3.ZERO, minf(delta * 6.0, 1.0))
		return
	var downhill := Vector3.DOWN - normal * Vector3.DOWN.dot(normal)
	if downhill.length_squared() < 0.0001:
		_camber_velocity = _camber_velocity.lerp(Vector3.ZERO, minf(delta * 6.0, 1.0))
		return
	var forward := _yaw_to_dir(_velocity_yaw)
	var across := forward.cross(Vector3.UP).normalized()
	# Cross-track slope only: how much of the fall line runs sideways.
	var lateral := across * downhill.dot(across)
	var scale := 1.0 if state == State.SLIDING else CAMBER_WADDLE_SCALE
	var target := lateral * CAMBER_ACCEL * scale
	_camber_velocity = _camber_velocity.lerp(target, minf(delta * 4.0, 1.0))


## Jump arc shaping: reduced gravity in a small window around the apex (the
## hang) and a heavier pull on the way down (fast fall). Only applied to arcs
## the racer jumped into — geyser launches, ledge walk-offs, and water
## breaches keep the plain parabola the courses were tuned around. The hang
## slightly outweighs the fast fall, so net airtime and peak height sit a
## hair ABOVE the old symmetric arc and gap jumps only get more forgiving.
func _jump_gravity_scale() -> float:
	if not _airborne_from_jump:
		return 1.0
	if absf(vertical_velocity) < APEX_HANG_SPEED:
		return APEX_HANG_GRAVITY
	if vertical_velocity < 0.0:
		return FALL_GRAVITY
	return 1.0


## Riders inherit moving-platform velocity. The iceberg hoppers are
## AnimatableBody3D moved in code with sync_to_physics off, so the physics
## server reports no platform velocity — track the frame delta manually and
## feed it into velocity. After leaving the platform the inherited momentum
## persists briefly (jumping off a moving berg carries), then bleeds off.
func _update_platform_carry(delta: float) -> void:
	# AI carry is damped: rivals cannot anticipate inherited drift, and full
	# carry swept them off the moving iceberg slabs.
	var carry_scale := 1.0 if is_player else 0.5
	# Player-only: AI target selection doesn't model inherited platform drift,
	# and carrying rivals sideways mid-crossing measurably raised DNF rates.
	if not is_player:
		return
	var found: AnimatableBody3D = null
	if is_on_floor():
		for i: int in get_slide_collision_count():
			var col := get_slide_collision(i)
			if col.get_normal().y > 0.55:
				found = col.get_collider() as AnimatableBody3D
				if found != null:
					break
	if found != null:
		if found == _platform_node and delta > 0.0001:
			var vel := (found.global_position - _platform_prev_origin) / delta * carry_scale
			# A teleporting platform (course reset) must not fling the rider.
			_platform_velocity = vel if vel.length_squared() < 144.0 else Vector3.ZERO
		else:
			_platform_velocity = Vector3.ZERO
		_platform_node = found
		_platform_prev_origin = found.global_position
		_platform_carry_timer = 0.5
	else:
		_platform_node = null
		if is_on_floor():
			# Back on solid ground: drop the carry immediately.
			_platform_velocity = Vector3.ZERO
			_platform_carry_timer = 0.0
		elif _platform_carry_timer > 0.0:
			_platform_carry_timer -= delta
		else:
			_platform_velocity = _platform_velocity.move_toward(Vector3.ZERO, 6.0 * delta)


## Post-move contact response: walls deflect instead of stopping, and
## racer-vs-racer touches exchange believable momentum.
func _resolve_contacts(delta: float) -> void:
	if state == State.FINISHED:
		return
	# Player-only. Rivals aim at a fixed guide target and cannot correct for a
	# redirected heading, so deflections compounded into off-course spirals and
	# DNFs. The human gets the feel; AI keep the path the courses are tuned
	# around, and still feel the player's bumps (the player's own contact pass
	# pushes both bodies).
	if not is_player:
		return
	for i: int in get_slide_collision_count():
		var col := get_slide_collision(i)
		var normal := col.get_normal()
		var other := col.get_collider() as Racer
		if other != null:
			_bump_racer(other, normal)
		elif normal.y < 0.4 and normal.y > -0.5:
			# Low obstacles (hurdle bars, kerbs) are meant to be hopped. Deflecting
			# there made racers grind sideways along them instead of backing off and
			# jumping, which deadlocked the tutorial hop lesson. Only contacts above
			# jump-clearing height count as walls.
			if col.get_position().y - global_position.y > JUMPABLE_HEIGHT:
				_glance_wall(normal, delta)


## Project the travel direction along a wall instead of grinding into it:
## glancing scrapes keep nearly all speed, head-on hits bleed hard while the
## heading swings parallel. Self-limiting — once the heading runs along the
## wall the into-component is ~0 and both the redirect and the bleed vanish.
func _glance_wall(normal: Vector3, delta: float) -> void:
	var flat := Vector3(normal.x, 0.0, normal.z)
	if flat.length_squared() < 0.01:
		return
	flat = flat.normalized()
	var dir := _yaw_to_dir(_velocity_yaw)
	var into := dir.dot(flat)  # < 0 when driving at the wall
	if into > -0.05:
		return
	var along := dir - flat * into
	along.y = 0.0
	if along.length_squared() < 0.003:
		# Dead-perpendicular hit: deflect along the wall toward the course
		# direction so nobody ever sticks nose-first to a cliff.
		var tangent := flat.cross(Vector3.UP)
		along = tangent if tangent.dot(_yaw_to_dir(_guide_yaw)) >= 0.0 else -tangent
	along = along.normalized()
	var weight := minf(delta * 14.0, 1.0)
	_velocity_yaw = _wrap_lerp_angle(_velocity_yaw, atan2(-along.x, -along.z), weight)
	var keep := sqrt(maxf(1.0 - into * into, 0.0))
	current_speed *= lerpf(1.0, maxf(keep, 0.3), weight)
	if into < -0.55 and current_speed > 7.0 and _wall_sfx_cooldown <= 0.0:
		_wall_sfx_cooldown = 0.5
		AudioManager.play_sfx_3d("sfx_impact", global_position, randf_range(0.82, 0.92), -12.0)
		if visual != null:
			visual.trigger_squash(0.88)


## Racer-vs-racer contact: trade momentum along the contact normal, weighted
## by "mass" so a boosted racer barges through and the lighter body soaks the
## hit. Both bodies may process the same touch on their own ticks, so the
## impulse is halved per side and scales with closing speed only — once the
## pair separates it naturally goes quiet.
func _bump_racer(other: Racer, normal: Vector3) -> void:
	if other.state == State.FINISHED:
		return
	var flat := Vector3(normal.x, 0.0, normal.z)
	if flat.length_squared() < 0.01:
		return
	flat = flat.normalized()  # points from the other racer toward us
	var closing := (_yaw_to_dir(other._velocity_yaw) * other.current_speed \
			- _yaw_to_dir(_velocity_yaw) * current_speed).dot(flat)
	if closing < 0.6:
		return
	var my_mass := _bump_mass()
	var other_mass := other._bump_mass()
	var share := other_mass / (my_mass + other_mass)
	var impulse := minf(closing, 10.0) * 0.55
	# AI-vs-AI pack jostle stays gentle: full impulses chain-knocked rivals off
	# the iceberg platform section.
	if not is_player and not other.is_player:
		impulse *= 0.5
	# AI-vs-AI pack jostle stays gentle: full impulses occasionally chain-
	# knocked three rivals off the iceberg platform section (sim-measured).
	if not is_player and not other.is_player:
		impulse *= 0.5
	_external_push += flat * impulse * share
	other._external_push -= flat * impulse * (1.0 - share)
	if closing > 5.0 and _wall_sfx_cooldown <= 0.0:
		_wall_sfx_cooldown = 0.4
		AudioManager.play_sfx_3d("sfx_stumble", global_position, randf_range(0.9, 1.05), -12.0)


## Effective mass for racer-vs-racer bumps: boost and sheer pace carry weight.
func _bump_mass() -> float:
	return 1.0 + (boost_mult - 1.0) * 1.6 + clampf(current_speed / BASE_SPEED - 1.0, 0.0, 1.0) * 0.5


## --- State helpers ---------------------------------------------------------

func _set_state(new_state: State) -> void:
	if state == new_state or state == State.FINISHED:
		return
	if state == State.SWIMMING and _bubble_particles != null:
		_bubble_particles.emitting = false
	state = new_state
	state_changed.emit(new_state)


## fall_speed is the (negative) vertical velocity at touchdown: harder falls
## squash deeper so landings after the fast-fall arc read with real weight.
func _land_feedback(fall_speed: float = 0.0) -> void:
	if visual != null:
		visual.trigger_squash(clampf(0.78 + (fall_speed + 6.0) * 0.014, 0.56, 0.8))
	AudioManager.play_sfx_3d("sfx_land", global_position, randf_range(0.92, 1.05), -6.0)
	if course != null and course.has_method("spawn_land_puff"):
		course.spawn_land_puff(global_position)


## Heading the body is actually moving along (used by the chase camera so it
## can lag behind turns instead of hard-locking to the facing).
func get_heading_yaw() -> float:
	return _velocity_yaw


func _update_visual(delta: float) -> void:
	if visual == null:
		return
	# Bank into turns: steering visibly rolls the penguin on screen instead of
	# reading as the whole world rotating around a fixed sprite.
	if delta > 0.0001:
		var yaw_rate := wrapf(_facing_yaw - _prev_facing_yaw, -PI, PI) / delta
		var bank_target := 0.0
		if state == State.WADDLING or state == State.BOOSTED or state == State.SLIDING or state == State.AIRBORNE:
			var bank_max := deg_to_rad(BANK_MAX_DEG)
			bank_target = clampf(yaw_rate * BANK_YAW_RATE_SCALE, -bank_max, bank_max)
		# Conform to the surface, THEN add the steering lean on top.
		#
		# The roll used to be the steering bank alone, so on a banked corner the
		# deck rolled up to MAX_BANK_DEG under a penguin that stayed dead level.
		# The racer looked like it was riding a rail suspended over the track
		# rather than standing on it -- the single clearest "this is a prototype"
		# tell left in the movement, and one I introduced when I banked the
		# corners in the first place. The same applies fore-and-aft: pitch only
		# followed the ground while belly-sliding, so a penguin waddling down a
		# hill stayed board-flat while the hill fell away beneath it.
		var conform_roll := 0.0
		var conform_pitch := 0.0
		if is_on_floor():
			var floor_n := get_floor_normal()
			var fwd := _yaw_to_dir(_facing_yaw)
			var right := fwd.cross(Vector3.UP).normalized()
			# Components of the surface normal in the body's own frame give the
			# two lean angles directly, and clamping them keeps a freak normal
			# (a wall graze, a collision corner) from throwing the pose.
			conform_roll = asin(clampf(floor_n.dot(right), -SURFACE_CONFORM_SIN, SURFACE_CONFORM_SIN))
			conform_pitch = -asin(clampf(floor_n.dot(fwd), -SURFACE_CONFORM_SIN, SURFACE_CONFORM_SIN))
		_surface_roll = lerpf(_surface_roll, conform_roll, minf(delta * SURFACE_CONFORM_RATE, 1.0))
		_surface_pitch = lerpf(_surface_pitch, conform_pitch, minf(delta * SURFACE_CONFORM_RATE, 1.0))
		_visual_bank = lerpf(_visual_bank, bank_target, minf(delta * 7.0, 1.0))
		visual.rotation.z = _visual_bank + _surface_roll

		# Weight transfer: the body pitches back as it picks up speed and tips
		# forward when it scrubs off. Small, but it is most of what separates a
		# character being accelerated from a character accelerating.
		var accel := 0.0 if delta <= 0.0 else (current_speed - _prev_speed) / delta
		_weight_pitch = lerpf(_weight_pitch,
			clampf(-accel * WEIGHT_PITCH_SCALE, -WEIGHT_PITCH_MAX, WEIGHT_PITCH_MAX),
			minf(delta * 5.0, 1.0))

		# Slope-aligned pitch while belly sliding, plus a subtle nose-follow
		# on the jump arc (up on the rise, down on the fall) so descents and
		# airtime read ballistic instead of board-flat.
		var pitch_target := 0.0
		if state == State.SLIDING and is_on_floor():
			var floor_n2 := get_floor_normal()
			var fwd2 := _yaw_to_dir(_velocity_yaw)
			var slope_t := fwd2 - floor_n2 * fwd2.dot(floor_n2)
			if slope_t.length_squared() > 0.001:
				pitch_target = asin(clampf(slope_t.normalized().y, -0.55, 0.55))
		elif state == State.AIRBORNE:
			pitch_target = clampf(vertical_velocity * 0.028, -0.34, 0.26)
		_visual_pitch = lerpf(_visual_pitch, pitch_target, minf(delta * 6.0, 1.0))
		# The slide already aligns itself to the slope, so it does not also take
		# the generic conform pitch or it would double up.
		var conform_term := 0.0 if state == State.SLIDING else _surface_pitch
		visual.rotation.x = _visual_pitch + conform_term + _weight_pitch
	_prev_speed = current_speed
	_prev_facing_yaw = _facing_yaw
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
	# The swing happens whether or not it connects. A shove that misses used to
	# produce a sound over a completely unchanged penguin, which reads as the
	# button not working rather than as a miss.
	if visual != null:
		visual.trigger_lunge()
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
	var landed := best != null and best.receive_shove(self)
	# A whiff is a thinner, higher swing with no impact behind it. Played after
	# the scan rather than before, because the sound has to know whether it hit
	# -- previously both outcomes played the identical cue at identical volume,
	# so a miss and a hit were audibly the same event.
	if landed:
		AudioManager.play_sfx_3d("sfx_shove", global_position, randf_range(0.9, 1.02))
		shove_landed.emit(self, best)
	else:
		AudioManager.play_sfx_3d("sfx_shove", global_position, randf_range(1.2, 1.35), -7.0)


## Returns true if the shove connected.
func receive_shove(attacker: Racer) -> bool:
	# Immunity is checked BEFORE the shield, not alongside it. Folding all
	# three into one condition meant a shove thrown at someone already inside
	# their i-frames still ate the shield -- a shield spent blocking a hit that
	# could not have landed in the first place.
	if _shove_immunity > 0.0 or _invuln_timer > 0.0 or state == State.FINISHED:
		return false
	if _has_shield:
		break_shield()
		return false
	_shove_immunity = 2.2
	# Steering lockout and the forced slide both scale with the attacker's
	# pace: a full-sprint hit launches a longer, harder tumble than a
	# standing-start nudge.
	var pace := clampf(attacker.current_speed / BASE_SPEED, 0.4, 1.8)
	_stumble_timer = clampf(STUMBLE_TIME * (0.65 + pace * 0.4), 0.35, 0.95)
	var push := global_position - attacker.global_position
	push.y = 0.0
	push = push.normalized() if push.length_squared() > 0.001 \
			else _yaw_to_dir(attacker._velocity_yaw)
	# Crisp impulse + short victim slide through move_and_slide (never a
	# position teleport, so a shove can't press anyone through walls).
	_knock_velocity = push * (4.0 + attacker.current_speed * 0.28)
	var side := signf(push.dot(_yaw_to_dir(_velocity_yaw + PI / 2.0)))
	_steer_offset += side * deg_to_rad(25.0)
	current_speed *= 0.72
	if visual != null:
		visual.trigger_squash(0.8)
		visual.trigger_tumble(side)
	# Impact FX at the contact point rather than on either penguin, so the hit
	# is visible even when both bodies are off-frame or hidden behind the
	# camera's own racer -- which, on a behind-the-back chase camera, is most of
	# the time.
	_spawn_shove_impact((global_position + attacker.global_position) * 0.5 + Vector3.UP * 0.55)
	AudioManager.play_sfx_3d("sfx_stumble", global_position, randf_range(0.9, 1.1))
	AudioManager.play_sfx_3d("sfx_impact", global_position, randf_range(1.15, 1.3), -5.0)
	shoved.emit(self, attacker)
	return true


## --- Shove impact FX ---------------------------------------------------------
## A ground shockwave ring, a billboard flash, and a kick of snow spray at the
## contact point. All unshaded and additive (gl_compatibility-safe); the meshes
## and materials are built once and shared, so a hit costs two nodes and one
## tween.
##
## This exists because the shove's whole feedback budget used to be spent on
## the two penguins, and the camera sits behind one of them: the player's own
## shove happened somewhere past their own back, out of frame. A world-space
## flash at the contact point is visible from anywhere.
##
## The ring lies FLAT. A first pass stood it upright facing along the push,
## which is a better idea on paper -- and on screen it was a white croquet hoop
## planted in the snow, because the bottom half sank through the deck and what
## was left read as a solid arch of scenery rather than as a wave. Flat on the
## ground it cannot intersect anything, and it is the shape every racing game
## uses for an impact for exactly that reason.

static var _impact_ring_mesh: TorusMesh = null
static var _impact_flash_mesh: QuadMesh = null
static var _impact_ring_material: StandardMaterial3D = null
static var _impact_flash_material: StandardMaterial3D = null


static func _get_impact_ring_mesh() -> TorusMesh:
	if _impact_ring_mesh == null:
		_impact_ring_mesh = TorusMesh.new()
		# Thin: a fat ring reads as a solid object, and this has to read as a
		# wave that is on its way out.
		_impact_ring_mesh.inner_radius = 0.46
		_impact_ring_mesh.outer_radius = 0.50
		_impact_ring_mesh.rings = 28
		_impact_ring_mesh.ring_segments = 5
	return _impact_ring_mesh


static func _get_impact_flash_mesh() -> QuadMesh:
	if _impact_flash_mesh == null:
		_impact_flash_mesh = QuadMesh.new()
		_impact_flash_mesh.size = Vector2(1.5, 1.5)
	return _impact_flash_mesh


func _spawn_shove_impact(pos: Vector3) -> void:
	if GameConfig.is_headless() or course == null or not is_instance_valid(course):
		return
	# Reduced flashing drops the additive flash but KEEPS the ring. The ring is
	# an expanding shape, not a brightness spike, and it is the only part of
	# this that survives the player's own penguin blocking the view -- taking it
	# away would leave that setting with no shove feedback at all.
	var reduced := bool(SettingsManager.get_setting("accessibility", "reduced_flashing"))
	if _impact_ring_material == null:
		_impact_ring_material = StandardMaterial3D.new()
		_impact_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_impact_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_impact_ring_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_impact_ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_impact_ring_material.disable_receive_shadows = true
		_impact_flash_material = VisualLibrary.billboard_puff_material(
			Color(1.0, 0.96, 0.86, 0.95), 32, 0.9, true).duplicate() as StandardMaterial3D
		_impact_flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD

	# Ring on the deck under the contact, flash at chest height.
	var ground := Vector3(pos.x, global_position.y + 0.12, pos.z)

	var ring := MeshInstance3D.new()
	ring.mesh = _get_impact_ring_mesh()
	ring.material_override = _impact_ring_material.duplicate() as StandardMaterial3D
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = ground
	ring.scale = Vector3(0.6, 1.0, 0.6)
	course.add_child(ring)

	var ring_mat := ring.material_override as StandardMaterial3D
	# Cyan rather than white. Additive white on a snow course either vanishes
	# into the ground or blows out to a flat slab; a cool tint keeps a readable
	# edge against everything this game is set on.
	ring_mat.albedo_color = Color(0.38, 0.82, 1.0, 0.5 if reduced else 0.8)

	# Tweened from the COURSE, not from the racer: these nodes are the course's
	# children, and a tween owned by a racer that gets freed mid-flight would
	# stop without ever running the callback that removes them.
	var tween := course.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(3.2, 1.0, 3.2), 0.26) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring_mat, "albedo_color:a", 0.0, 0.26)

	if not reduced:
		var flash := MeshInstance3D.new()
		flash.mesh = _get_impact_flash_mesh()
		flash.material_override = _impact_flash_material.duplicate() as StandardMaterial3D
		flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flash.position = pos
		flash.scale = Vector3.ONE * 0.5
		course.add_child(flash)
		var flash_mat := flash.material_override as StandardMaterial3D
		tween.tween_property(flash, "scale", Vector3.ONE * 1.9, 0.16) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(flash_mat, "albedo_color:a", 0.0, 0.16)
		tween.chain().tween_callback(func() -> void:
			if is_instance_valid(flash):
				flash.queue_free())

	tween.chain().tween_callback(func() -> void:
		if is_instance_valid(ring):
			ring.queue_free())

	# Snow kicked up by the scuffle, through the course's existing pooled puff
	# emitters -- the same burst a hard landing throws, so a shove sits in the
	# visual language the course already speaks.
	if course.has_method("spawn_land_puff"):
		course.call("spawn_land_puff", ground)


## Comedic stumble away from a world position (seal bumps, soft hazards).
func receive_shove_from_position(source: Vector3) -> void:
	if _invuln_timer > 0.0 or state == State.FINISHED:
		return
	if _has_shield:
		break_shield()
		return
	_stumble_timer = STUMBLE_TIME
	var push := global_position - source
	push.y = 0.0
	push = push.normalized() if push.length_squared() > 0.001 \
			else -_yaw_to_dir(_velocity_yaw)
	# Velocity knock instead of a teleport: the bounce-away slide resolves
	# through move_and_slide and can never press the victim into geometry.
	_knock_velocity = push * 6.5
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


## Boost multiplier is clamped to BOOST_MAX_MULT and never downgraded by a
## weaker overlapping boost; combined surface*boost speed is capped in the
## movement code so pads top out ~1.5x base speed.
func apply_boost(duration: float, mult: float = 1.45) -> void:
	_boost_timer = maxf(_boost_timer, duration)
	boost_mult = clampf(maxf(boost_mult, mult), 1.0, BOOST_MAX_MULT)
	# Pads must feel instant: snap straight to near-boosted pace instead of
	# waiting for the accel ramp to climb there (playtest feedback).
	var top := BASE_SPEED * minf(mult, BOOST_SLIDE_TOP_MULT if state == State.SLIDING else BOOST_TOP_SPEED_MULT) * speed_scale
	current_speed = maxf(current_speed, top * 0.92)
	if state == State.WADDLING:
		_set_state(State.BOOSTED)


func apply_blizzard_slip(duration: float) -> void:
	# The only damage entry point that had neither guard. A blizzard cloud
	# re-checks its overlaps every 0.4 s, so without these a racer standing in
	# one loses a shield to a hit their i-frames were already absorbing, and a
	# finished racer coasting through the cloud is still affected by it.
	if _invuln_timer > 0.0 or state == State.FINISHED:
		return
	if _has_shield:
		break_shield()
		return
	_blizzard_slip_timer = duration


## Shield bubble: a fresnel shell, opaque only where it turns away.
##
## The old shield was an UNSHADED sphere at a flat 30% alpha. Unshaded means no
## falloff, so it laid an even milky wash across the whole racer -- and the
## rim_enabled it was relying on to make an edge does nothing on an unshaded
## StandardMaterial3D. In practice the power-up erased the character wearing
## it, which is a bad trade in a game where you need to see who you are.
##
## A bubble is glass: nearly invisible face-on, bright at the grazing edge.
## Driving alpha off fresnel gives exactly that, so the shell reads as a sphere
## while leaving the middle -- where the penguin is -- clear. depth_draw off
## and cull disabled let the far side contribute its own rim, which is what
## makes it read as volume rather than as a disc. gl_compatibility-safe.
const SHIELD_SHADER_CODE := """shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec4 shell_color : source_color = vec4(0.30, 0.78, 1.0, 1.0);
// 1.0 for most of the shield's life, falling to 0.0 across its last seconds.
// Drives the whole wind-down, so a shield that is about to lapse looks
// different from a fresh one -- otherwise the timer would be invisible and the
// bubble would just blink out.
uniform float charge : hint_range(0.0, 1.0) = 1.0;
// 0.0 under the reduced-flashing accessibility setting, which replaces the
// end-of-life stutter with a smooth fade. The stutter is a hard 6 Hz on/off on
// both alpha and emission -- exactly the kind of thing that setting exists to
// suppress -- and the wind-down still reads without it, through the thinning
// shell and the band speeding up.
uniform float flicker : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	// Exponent sets how much of the shell is visible. 2.6 confined it to a
	// sliver that vanished entirely against snow -- the power-up went from
	// erasing the racer to giving no feedback at all, which is its own bug.
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 1.7);
	// A slow band travelling up the shell so an active shield reads as powered
	// rather than as a static bauble. It accelerates as the charge drains, so
	// the shell looks agitated before it goes.
	float band = 0.5 + 0.5 * sin(UV.y * 12.0 - TIME * (2.4 + (1.0 - charge) * 7.0));
	// A hard bright line right at the silhouette, so the bubble has an edge
	// you can find on a white course, over a softer body that stays clear
	// where the penguin is.
	float lip = smoothstep(0.72, 0.97, fres);
	float a = clamp(fres * 0.55 + lip * 0.75 + band * fres * 0.25, 0.0, 0.92);
	// Failing shell: a fast stutter that only bites in the last of the charge,
	// plus an overall thinning. Both are gated on (1.0 - charge) so a shield
	// with time left is completely unaffected by any of this.
	float stutter = mix(1.0, 0.35 + 0.65 * step(0.35, fract(TIME * 6.0)), (1.0 - charge) * flicker);
	a *= mix(0.45, 1.0, charge) * stutter;
	ALBEDO = shell_color.rgb;
	EMISSION = shell_color.rgb * (0.6 + band * 0.5) * (fres + lip * 0.8) * stutter;
	ALPHA = a;
}
"""

static var _shield_shader: Shader = null


static func _get_shield_shader() -> Shader:
	if _shield_shader == null:
		_shield_shader = Shader.new()
		_shield_shader.code = SHIELD_SHADER_CODE
	return _shield_shader


func give_shield() -> void:
	var was_active := _has_shield
	_has_shield = true
	# Taking a second shield refreshes the clock rather than stacking, which is
	# the only sane reading of a one-hit shield you already have.
	_shield_timer = SHIELD_DURATION
	if _shield_visual == null and visual != null:
		var sphere := SphereMesh.new()
		sphere.radius = 0.85
		sphere.height = 1.7
		sphere.radial_segments = 24
		sphere.rings = 12
		_shield_material = ShaderMaterial.new()
		_shield_material.shader = _get_shield_shader()
		sphere.material = _shield_material
		_shield_visual = MeshInstance3D.new()
		_shield_visual.mesh = sphere
		_shield_visual.position.y = 0.55
		_shield_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_shield_visual)
	if _shield_material != null:
		_shield_material.set_shader_parameter("charge", 1.0)
		_shield_material.set_shader_parameter("flicker",
			0.0 if bool(SettingsManager.get_setting("accessibility", "reduced_flashing")) else 1.0)
	if _shield_visual != null:
		_shield_visual.visible = true
	if not was_active:
		shield_changed.emit(self, true)


func has_shield() -> bool:
	return _has_shield


## Seconds of shield left, 0.0 when there is none. Drives the HUD countdown.
func shield_remaining() -> float:
	return _shield_timer if _has_shield else 0.0


func break_shield() -> void:
	_clear_shield()
	AudioManager.play_sfx_3d("sfx_shield_break", global_position)
	_invuln_timer = maxf(_invuln_timer, 0.8)


## Ran out of time rather than absorbing anything. Deliberately quieter than
## break_shield and grants no invulnerability: nothing hit you, so nothing
## should follow. The distinct sound is what tells the player the difference.
func _expire_shield() -> void:
	_clear_shield()
	AudioManager.play_sfx_3d("sfx_shield_break", global_position, 1.45, -9.0)


func _clear_shield() -> void:
	if not _has_shield:
		return
	_has_shield = false
	_shield_timer = 0.0
	if _shield_visual != null:
		_shield_visual.visible = false
	shield_changed.emit(self, false)


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


## Grants throwable snowball ammo. Returns false when already full, so
## pickups can stay on the track for whoever still has room.
func add_snowball_ammo(amount: int = 1) -> bool:
	if snowball_ammo >= MAX_SNOWBALL_AMMO or state == State.FINISHED:
		return false
	snowball_ammo = mini(snowball_ammo + amount, MAX_SNOWBALL_AMMO)
	snowball_ammo_changed.emit(self, snowball_ammo)
	return true


## Throws one collected snowball. Routed through item_used so the existing
## PowerupSystem snowball projectile and its forgiving forward-targeting
## fire exactly like the power-up version (same on-hit tumble).
func throw_snowball() -> bool:
	if snowball_ammo <= 0 or state == State.FINISHED:
		return false
	snowball_ammo -= 1
	snowball_ammo_changed.emit(self, snowball_ammo)
	item_used.emit(self, "snowball")
	return true


## --- Water ------------------------------------------------------------------

func enter_water(area: Area3D, surface_y: float) -> void:
	if area not in _water_areas:
		_water_areas.append(area)
	_water_surface_y = surface_y
	if state != State.SWIMMING and state != State.FINISHED and global_position.y < surface_y + 0.3:
		_set_state(State.SWIMMING)
		vertical_velocity = minf(vertical_velocity, 0.0)
		_swim_stroke_timer = randf_range(0.4, 0.6)  # first stroke after the splash, not on top of it
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
	_knock_velocity = Vector3.ZERO
	_platform_node = null
	_platform_velocity = Vector3.ZERO
	_platform_carry_timer = 0.0
	_water_areas.clear()
	guide_cache = {}  # force fresh global guide search from the new position
	_invuln_timer = 2.0
	_recover_timer = RECOVER_TIME
	# Randomized post-respawn stumble desyncs the next approach from moving
	# platforms: a fixed respawn->arrival period can resonate with a platform
	# cycle so every retry meets the same bad phase.
	_stumble_timer = randf_range(0.2, 1.4)
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
	# Drop any shield at the line. _update_timers runs in every state, so a
	# shield taken late otherwise stays lit through the celebration and then
	# pops sfx_shield_break partway through it -- a break sound for a hit that
	# never happened, over a racer who has already won.
	_clear_shield()
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
	_ceiling_query.from = global_position + Vector3.UP * 0.4
	_ceiling_query.to = global_position + Vector3.UP * 1.35
	return not space.intersect_ray(_ceiling_query).is_empty()


func _yaw_to_dir(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _wrap_lerp_angle(from: float, to: float, weight: float) -> float:
	return lerp_angle(from, to, weight)
