class_name ChaseCamera
extends Node3D
## Third-person chase camera: smoothed follow, predictive look, speed FOV,
## slide/water framing, finish orbit, trauma-based shake with accessibility
## scaling.
##
## The follow yaw is slerped toward the racer's movement heading with its own
## (slow) responsiveness instead of hard-locking to the racer's basis. That
## rotational lag is what makes steering read as "the penguin turns on
## screen" rather than "the whole map rotates around the penguin".

const BASE_FOV: float = 68.0
const MAX_FOV_BONUS: float = 18.0
const YAW_FOLLOW_RATE: float = 3.0  # 1/s slerp responsiveness toward heading
const YAW_CATCHUP_START: float = 1.2  # rad of error where fast catch-up kicks in
const YAW_CATCHUP_GAIN: float = 4.0  # extra rate per rad beyond the start (respawns)
## Peak camera roll into a corner, in degrees. Small on purpose: the frame
## should hint at the lean, not tip the horizon over.
## Floor the camera keeps above the racer's own feet while it is on the ground,
## so an elevated deck can never come between the two. Low enough that the
## framing on flat ground is unchanged.
const MIN_HEIGHT_OVER_TARGET: float = 0.95

const MAX_ROLL_DEG: float = 6.5
## Yaw rate (rad/s) that earns full roll. A hard corner sits near 1.6.
const FULL_ROLL_YAW_RATE: float = 1.8
## How fast the roll eases in and out (1/s).
const ROLL_RATE: float = 4.5

var target: Racer = null
var camera: Camera3D
var _shake_trauma: float = 0.0
var _shake_time: float = 0.0
var _smoothed_pos: Vector3
var _smoothed_look: Vector3
var _follow_yaw: float = 0.0
var _finish_orbit_angle: float = 0.0
var _mode_finish: bool = false
var _fov_extra: float = 0.0
var _roll: float = 0.0  ## Smoothed corner lean, radians.
var _prev_follow_yaw: float = 0.0
var _initialized: bool = false


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = BASE_FOV
	camera.near = 0.1
	camera.far = 900.0
	add_child(camera)


func attach_to(racer: Racer) -> void:
	target = racer
	_mode_finish = false
	_initialized = false


func add_shake(amount: float) -> void:
	var mode := String(SettingsManager.get_setting("accessibility", "camera_shake"))
	if mode == "off":
		return
	if mode == "reduced":
		amount *= 0.35
	_shake_trauma = minf(_shake_trauma + amount, 1.0)


func boost_fov_kick(amount: float = 8.0) -> void:
	_fov_extra = amount


func enter_finish_mode() -> void:
	_mode_finish = true
	_finish_orbit_angle = 0.0


func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var speed_ratio := clampf(target.current_speed / Racer.BASE_SPEED, 0.0, 2.0)

	var desired_pos: Vector3
	var look_point: Vector3
	if _mode_finish:
		_finish_orbit_angle += delta * 0.55
		var radius := 5.0
		desired_pos = target.global_position + Vector3(
			sin(_finish_orbit_angle) * radius,
			2.2,
			cos(_finish_orbit_angle) * radius
		)
		look_point = target.global_position + Vector3.UP * 0.8
	else:
		# Chase the racer's actual movement heading with rotational lag, so a
		# steering penguin visibly yaws/banks on screen before the camera
		# swings around behind it.
		var heading_yaw := _heading_yaw()
		if not _initialized:
			_follow_yaw = heading_yaw
			_prev_follow_yaw = heading_yaw
		else:
			var yaw_error := absf(wrapf(heading_yaw - _follow_yaw, -PI, PI))
			var yaw_rate := YAW_FOLLOW_RATE
			if yaw_error > YAW_CATCHUP_START:  # respawn / hard snap: recover fast
				yaw_rate += (yaw_error - YAW_CATCHUP_START) * YAW_CATCHUP_GAIN
			_follow_yaw = lerp_angle(_follow_yaw, heading_yaw, 1.0 - exp(-delta * yaw_rate))
		var follow_dir := Vector3(-sin(_follow_yaw), 0.0, -cos(_follow_yaw))
		var height := 2.5
		var distance := 5.0
		var look_lift := 0.9
		if target.state == Racer.State.SLIDING:
			# Sliding used to DROP the camera (2.0) while the racer went prone
			# and the look point stayed at head height, leaving barely six
			# degrees of depression -- the fastest state in the game had the
			# flattest, least readable view of the ground it was about to hit.
			# Rise instead, and aim lower, so a slide looks down the track.
			height = 3.15
			distance = 6.2
			look_lift = 0.55
		elif target.state == Racer.State.SWIMMING:
			height = 2.1
			distance = 5.8
		elif target.state == Racer.State.AIRBORNE:
			height = 2.9
		distance += speed_ratio * 0.7
		# Portrait (phone held upright): the horizontal view is narrow, so sit
		# higher and further back — the taller frame shows the track ahead
		# instead of mostly sky and snow. Vertical FOV also opens up below.
		var vp_size := get_viewport().get_visible_rect().size
		if vp_size.x < vp_size.y:
			height += 1.4
			distance += 2.2
		desired_pos = target.global_position - follow_dir * distance + Vector3.UP * height
		look_point = target.global_position + follow_dir * (3.2 + speed_ratio * 3.2) + Vector3.UP * look_lift

	if not _initialized:
		_smoothed_pos = desired_pos
		_smoothed_look = look_point
		_initialized = true
	var pos_rate := 1.0 - exp(-delta * 8.0)
	var look_rate := 1.0 - exp(-delta * 10.0)
	_smoothed_pos = _smoothed_pos.lerp(desired_pos, pos_rate)
	_smoothed_look = _smoothed_look.lerp(look_point, look_rate)

	# Keep the camera from dipping under the track.
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(
		_smoothed_pos + Vector3.UP * 4.0, _smoothed_pos + Vector3.DOWN * 1.2, GameConfig.LAYER_WORLD)
	var hit := space.intersect_ray(ray)
	if not hit.is_empty():
		var floor_y: float = (hit["position"] as Vector3).y
		_smoothed_pos.y = maxf(_smoothed_pos.y, floor_y + 0.7)

	# ...and never below the deck the RACER is standing on.
	#
	# The probe above casts down from the CAMERA, so it only ever finds what is
	# under the camera. Where the track runs along an elevated plateau, a camera
	# that has swung out past the edge is over open air: the cast falls all the
	# way to the frozen lake, the clamp does nothing, and the camera settles
	# below deck level with the plateau's edge squarely between it and the
	# player. On the deep-snow climb that meant losing sight of your own
	# penguin behind a wall of ice. Clamping to the racer's own height cannot
	# have that blind spot, because the racer is by definition standing on the
	# surface the camera needs to stay above.
	#
	# On-floor only: a jump should still be framed ballistically rather than
	# dragging the camera up the arc with the racer.
	if target.is_on_floor():
		_smoothed_pos.y = maxf(_smoothed_pos.y,
			target.global_position.y + MIN_HEIGHT_OVER_TARGET)

	global_position = _smoothed_pos
	if _smoothed_pos.distance_squared_to(_smoothed_look) > 0.01:
		look_at(_smoothed_look, Vector3.UP)

	# FOV. Godot's fov is vertical: in portrait the horizontal view collapses,
	# so widen the vertical FOV to compensate and keep the course readable.
	_fov_extra = move_toward(_fov_extra, 0.0, delta * 10.0)
	var target_fov := BASE_FOV + clampf(speed_ratio - 0.9, 0.0, 1.1) * MAX_FOV_BONUS + _fov_extra
	var vp := get_viewport().get_visible_rect().size
	if vp.x < vp.y:
		target_fov += 10.0
	camera.fov = lerpf(camera.fov, target_fov, minf(delta * 5.0, 1.0))

	# Corner lean: the frame rolls slightly into a turn, scaled by how fast the
	# racer is actually going, so the newly banked corners read as banked and a
	# hard change of direction is felt rather than merely seen. Derived from the
	# already-smoothed follow yaw, so it inherits that damping instead of
	# twitching on raw steering input.
	var roll_target := 0.0
	if not _mode_finish and delta > 0.0:
		var yaw_rate := wrapf(_follow_yaw - _prev_follow_yaw, -PI, PI) / delta
		var lean := clampf(yaw_rate / FULL_ROLL_YAW_RATE, -1.0, 1.0)
		roll_target = deg_to_rad(MAX_ROLL_DEG) * lean * clampf(speed_ratio, 0.0, 1.0)
	_prev_follow_yaw = _follow_yaw
	_roll = lerpf(_roll, roll_target, 1.0 - exp(-delta * ROLL_RATE))

	# Shake rides on top of the lean rather than replacing it.
	var shake_roll := 0.0
	if _shake_trauma > 0.001:
		_shake_time += delta * 30.0
		var strength := _shake_trauma * _shake_trauma
		camera.h_offset = sin(_shake_time * 1.31) * strength * 0.25
		camera.v_offset = cos(_shake_time * 1.73) * strength * 0.22
		shake_roll = sin(_shake_time * 0.97) * strength * 0.02
		_shake_trauma = maxf(0.0, _shake_trauma - delta * 1.6)
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
	camera.rotation.z = _roll + shake_roll


## Yaw of the direction the racer is actually travelling; falls back to the
## body facing when nearly stationary (velocity yaw is meaningless at rest).
func _heading_yaw() -> float:
	if target.current_speed > 2.0:
		return target.get_heading_yaw()
	return target.rotation.y
