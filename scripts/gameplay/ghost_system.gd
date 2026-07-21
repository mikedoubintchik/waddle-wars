class_name GhostSystem
extends Node
## Time Trial ghost: records the player's run at a fixed sample rate and
## plays back the locally saved best run as a translucent penguin.

const SAMPLE_INTERVAL: float = 0.1
const GHOST_VERSION: int = 1

var player: Racer = null
var course_id: String = ""
var recording: bool = false

var _record_times: PackedFloat32Array = []
var _record_positions: PackedVector3Array = []
var _record_yaws: PackedFloat32Array = []
var _record_clock: float = 0.0
var _sample_accum: float = 0.0

var _ghost_times: PackedFloat32Array = []
var _ghost_positions: PackedVector3Array = []
var _ghost_yaws: PackedFloat32Array = []
var _ghost_total: float = 0.0
var _ghost_visual: PenguinVisual = null
var _ghost_clock: float = 0.0
var _ghost_index: int = 0
var _playing: bool = false


static func ghost_path(p_course_id: String) -> String:
	return "user://ghost_%s.dat" % p_course_id


func setup(p_player: Racer, p_course_id: String) -> void:
	player = p_player
	course_id = p_course_id
	_load_ghost()


func start_run() -> void:
	recording = true
	_record_clock = 0.0
	_sample_accum = 0.0
	_record_times.clear()
	_record_positions.clear()
	_record_yaws.clear()
	if not _ghost_times.is_empty():
		_playing = true
		_ghost_clock = 0.0
		_ghost_index = 0
		if _ghost_visual != null:
			_ghost_visual.visible = true


func stop_run() -> void:
	recording = false
	_playing = false
	if _ghost_visual != null:
		_ghost_visual.visible = false


func has_ghost() -> bool:
	return not _ghost_times.is_empty()


func ghost_total_time() -> float:
	return _ghost_total


func _physics_process(delta: float) -> void:
	if recording and player != null and is_instance_valid(player):
		_record_clock += delta
		_sample_accum += delta
		if _sample_accum >= SAMPLE_INTERVAL:
			_sample_accum -= SAMPLE_INTERVAL
			_record_times.append(_record_clock)
			_record_positions.append(player.global_position)
			_record_yaws.append(player.rotation.y)
	if _playing and _ghost_visual != null:
		_ghost_clock += delta
		_advance_ghost(delta)


func _advance_ghost(delta: float) -> void:
	while _ghost_index < _ghost_times.size() - 1 and _ghost_times[_ghost_index + 1] < _ghost_clock:
		_ghost_index += 1
	if _ghost_index >= _ghost_times.size() - 1:
		_ghost_visual.set_pose(PenguinVisual.Pose.CELEBRATE)
		_ghost_visual.tick(delta, 0.5)
		return
	var t0 := _ghost_times[_ghost_index]
	var t1 := _ghost_times[_ghost_index + 1]
	var alpha := clampf((_ghost_clock - t0) / maxf(t1 - t0, 0.001), 0.0, 1.0)
	var pos := _ghost_positions[_ghost_index].lerp(_ghost_positions[_ghost_index + 1], alpha)
	var speed := _ghost_positions[_ghost_index].distance_to(_ghost_positions[_ghost_index + 1]) / maxf(t1 - t0, 0.001)
	_ghost_visual.global_position = pos
	_ghost_visual.rotation.y = lerp_angle(_ghost_yaws[_ghost_index], _ghost_yaws[_ghost_index + 1], alpha)
	_ghost_visual.set_pose(PenguinVisual.Pose.RUN if speed > 1.0 else PenguinVisual.Pose.IDLE)
	_ghost_visual.anim_speed = speed / Racer.BASE_SPEED
	_ghost_visual.tick(delta, clampf(speed / Racer.BASE_SPEED, 0.0, 1.5))


## Saves the current recording as the new best ghost.
func save_recording(total_time: float) -> void:
	var file := FileAccess.open(ghost_path(course_id), FileAccess.WRITE)
	if file == null:
		push_warning("GhostSystem: cannot write ghost file")
		return
	file.store_var({
		"version": GHOST_VERSION,
		"course": course_id,
		"total_time": total_time,
		"times": _record_times,
		"positions": _record_positions,
		"yaws": _record_yaws,
	})
	file.close()


func _load_ghost() -> void:
	var path := ghost_path(course_id)
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var data: Variant = file.get_var()
	file.close()
	if not data is Dictionary or int(data.get("version", 0)) != GHOST_VERSION:
		return
	_ghost_times = data.get("times", PackedFloat32Array())
	_ghost_positions = data.get("positions", PackedVector3Array())
	_ghost_yaws = data.get("yaws", PackedFloat32Array())
	_ghost_total = float(data.get("total_time", 0.0))
	if _ghost_times.is_empty() or GameConfig.is_headless():
		return
	_ghost_visual = PenguinVisual.new()
	_ghost_visual.setup({
		"body_color": Color(0.5, 0.8, 1.0),
		"belly_color": Color(0.8, 0.95, 1.0),
	})
	add_child(_ghost_visual)
	_make_translucent(_ghost_visual)
	_ghost_visual.visible = false


func _make_translucent(node: Node) -> void:
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			var mat := mesh_instance.material_override
			if mat is StandardMaterial3D:
				var ghost_mat := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				ghost_mat.albedo_color.a = 0.42
				ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mesh_instance.material_override = ghost_mat
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_make_translucent(child)
