class_name ChaseCamera
extends Node3D
## Third-person chase camera: smoothed follow, predictive look, speed FOV,
## slide/water framing, finish orbit, trauma-based shake with accessibility
## scaling.

const BASE_FOV: float = 68.0
const MAX_FOV_BONUS: float = 18.0

var target: Racer = null
var camera: Camera3D
var _shake_trauma: float = 0.0
var _shake_time: float = 0.0
var _smoothed_pos: Vector3
var _smoothed_look: Vector3
var _finish_orbit_angle: float = 0.0
var _mode_finish: bool = false
var _fov_extra: float = 0.0
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
	var forward := -target.global_transform.basis.z

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
		var height := 2.5
		var distance := 5.0
		if target.state == Racer.State.SLIDING:
			height = 2.0
			distance = 6.0
		elif target.state == Racer.State.SWIMMING:
			height = 2.1
			distance = 5.8
		elif target.state == Racer.State.AIRBORNE:
			height = 2.9
		distance += speed_ratio * 0.7
		desired_pos = target.global_position - forward * distance + Vector3.UP * height
		look_point = target.global_position + forward * (3.2 + speed_ratio * 3.2) + Vector3.UP * 0.9

	if not _initialized:
		_smoothed_pos = desired_pos
		_smoothed_look = look_point
		_initialized = true
	var pos_rate := 1.0 - exp(-delta * 7.0)
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

	global_position = _smoothed_pos
	if _smoothed_pos.distance_squared_to(_smoothed_look) > 0.01:
		look_at(_smoothed_look, Vector3.UP)

	# FOV.
	_fov_extra = move_toward(_fov_extra, 0.0, delta * 10.0)
	var target_fov := BASE_FOV + clampf(speed_ratio - 0.9, 0.0, 1.1) * MAX_FOV_BONUS + _fov_extra
	camera.fov = lerpf(camera.fov, target_fov, minf(delta * 5.0, 1.0))

	# Shake.
	if _shake_trauma > 0.001:
		_shake_time += delta * 30.0
		var strength := _shake_trauma * _shake_trauma
		camera.h_offset = sin(_shake_time * 1.31) * strength * 0.25
		camera.v_offset = cos(_shake_time * 1.73) * strength * 0.22
		camera.rotation.z = sin(_shake_time * 0.97) * strength * 0.02
		_shake_trauma = maxf(0.0, _shake_trauma - delta * 1.6)
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
		camera.rotation.z = 0.0
