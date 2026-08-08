extends Node3D
## Visual QA: renders one penguin in a forced pose from the side and saves a
## PNG. Usage:
##   godot res://tests/pose_check.tscn -- pose=slide out=build/shots/pose_slide.png
##
## With `impulse=`, it instead fires one of the shove animations and saves a
## STRIP of frames across it, because a one-shot impulse cannot be judged from
## a single still -- and `view=behind` puts the camera where the chase camera
## actually sits, which is the only angle the player ever sees a shove from:
##   godot res://tests/pose_check.tscn -- impulse=tumble view=behind out=t.png

## Frame times, in seconds after the trigger, for an impulse strip.
const IMPULSE_OFFSETS: PackedFloat32Array = [0.04, 0.12, 0.26, 0.45, 0.75]

var _out_path: String = "build/shots/pose_check.png"
var _pose: String = "slide"
var _impulse: String = ""
var _view: String = "side"
var _elapsed: float = 0.0
var _done: bool = false
var _penguin: PenguinVisual = null
var _fired: bool = false
var _since_fire: float = 0.0
var _shot: int = 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.split("=")
		if parts.size() != 2:
			continue
		match parts[0]:
			"pose": _pose = parts[1]
			"out": _out_path = parts[1]
			"impulse": _impulse = parts[1]
			"view": _view = parts[1]
	DisplayServer.window_set_size(Vector2i(1280, 720))

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.7, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.85, 0.95)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	add_child(sun)

	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(10, 10)
	floor_mesh.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.92, 0.95, 1.0)
	floor_mesh.material_override = fm
	add_child(floor_mesh)

	_penguin = PenguinVisual.new()
	_penguin.setup({})
	add_child(_penguin)

	var cam := Camera3D.new()
	# Side view: penguin forward is -Z, camera on +X looking at origin.
	# Behind view: where ChaseCamera sits, which is the only angle a player
	# ever judges their own animation from.
	cam.position = Vector3(3.2, 1.0, 0.0) if _view != "behind" else Vector3(0.0, 1.5, 3.4)
	cam.look_at_from_position(cam.position, Vector3(0, 0.5, 0))
	add_child(cam)
	cam.current = true

	var pose := PenguinVisual.Pose.SLIDE
	match _pose:
		"slide": pose = PenguinVisual.Pose.SLIDE
		"swim": pose = PenguinVisual.Pose.SWIM
		"run": pose = PenguinVisual.Pose.RUN
		"air": pose = PenguinVisual.Pose.AIR
	_penguin.set_pose(pose)


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	_penguin.tick(delta, 1.0)
	if _impulse != "":
		await _tick_impulse(delta)
		return
	if _elapsed < 2.0:
		return
	_done = true
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_out_path.get_base_dir())
	var err := image.save_png(_out_path)
	print("[pose_check] saved %s err=%d" % [_out_path, err])
	get_tree().quit()


## Lets the pose settle, fires the impulse, then saves one frame per offset.
func _tick_impulse(delta: float) -> void:
	if not _fired:
		if _elapsed < 1.2:
			return
		_fired = true
		if _impulse == "lunge":
			_penguin.trigger_lunge()
		else:
			_penguin.trigger_tumble(1.0)
		print("[pose_check] fired %s" % _impulse)
		return
	_since_fire += delta
	if _shot >= IMPULSE_OFFSETS.size() or _since_fire < IMPULSE_OFFSETS[_shot]:
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s_%d.png" % [_out_path.get_basename(), _shot]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := image.save_png(path)
	print("[pose_check] saved %s t=+%.2fs err=%d" % [path, IMPULSE_OFFSETS[_shot], err])
	_shot += 1
	if _shot >= IMPULSE_OFFSETS.size():
		_done = true
		get_tree().quit(0 if err == OK else 1)
