extends Node
## Deterministic real-course visual matrix for opening/cave/shortcut/downhill/
## finish. Uses the live authored Glacier build and live hero racer.
##
## godot --path . --rendering-method gl_compatibility \
##   res://tests/glacier_gauntlet_art_shot.tscn -- \
##   zone=cave out=qa_shots/courses/glacier/cave_540x960.png w=540 h=960

const ZONES: PackedStringArray = [
	"opening", "cave", "cave_environment", "shortcut", "downhill", "finish",
]

var _zone := "opening"
var _out_path := "qa_shots/courses/glacier/opening.png"
var _width := 1920
var _height := 1080
var _settle := 6.2


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pieces := arg.split("=", false, 1)
		if pieces.size() != 2:
			continue
		match pieces[0]:
			"zone": _zone = pieces[1]
			"out": _out_path = pieces[1]
			"w": _width = int(pieces[1])
			"h": _height = int(pieces[1])
			"wait": _settle = float(pieces[1])
	if _zone not in ZONES:
		push_error("glacier shot: unknown zone %s" % _zone)
		get_tree().quit(1)
		return
	DisplayServer.window_set_size(Vector2i(_width, _height))
	DisplayServer.window_set_position(Vector2i(40, 60))
	DisplayServer.window_move_to_foreground()
	SettingsManager.set_setting("display", "particle_quality", "high")
	Game.mode = Game.Mode.QUICK_RACE
	Game.course_id = "glacier"
	Game.difficulty_id = "competitive"
	RaceManager.autopilot_player = true
	var monitor := GlacierShotMonitor.new()
	monitor.zone = _zone
	monitor.out_path = _out_path
	monitor.width = _width
	monitor.height = _height
	monitor.settle = _settle
	get_tree().root.add_child.call_deferred(monitor)
	SceneRouter.go_to.call_deferred(Game.SCENE_RACE)


class GlacierShotMonitor:
	extends Node

	var zone := "opening"
	var out_path := ""
	var width := 1920
	var height := 1080
	var settle := 6.2
	var _elapsed := 0.0
	var _staged := false
	var _camera: Camera3D = null

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(delta: float) -> void:
		var race := get_tree().current_scene
		if not _staged:
			if race == null or race.get("course") == null or race.get("manager") == null:
				return
			var course := race.get("course") as CourseGlacier
			var manager := race.get("manager") as RaceManager
			if course == null or manager == null or manager.player == null or not course.build_finished:
				return
			var status := course.authored_art_status()
			if not bool(status.get("active", false)):
				push_error("glacier shot: authored art inactive %s" % status)
				get_tree().quit(1)
				return
			_stage(course, manager)
			_staged = true
			print("[glacier_shot] staged zone=%s status=%s" % [zone, status])
			return
		_elapsed += delta
		if _elapsed < settle:
			return
		set_process(false)
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(out_path.get_base_dir()))
		var error := image.save_png(out_path)
		print("[glacier_shot] saved %s %dx%d zone=%s err=%d" % [
			out_path, image.get_width(), image.get_height(), zone, error])
		get_tree().quit(0 if error == OK else 1)

	func _stage(course: CourseGlacier, manager: RaceManager) -> void:
		var guide: PathGuide = course.main_guide
		var offset := 125.0
		match zone:
			"opening":
				# Past opening ice dip: cream packed-snow value key, event camp and
				# distant arch share frame. Countdown/GO clears before capture.
				offset = 215.0
			"cave":
				offset = float(guide.nearest(Vector3(-6, 44, -420), -1)["offset"]) - 8.0
			"cave_environment":
				# Environment-only review plate. Shared ItemBox visuals are a known
				# external interactive milestone; their mechanics stay instantiated.
				offset = float(guide.nearest(Vector3(-6, 44, -420), -1)["offset"]) - 8.0
			"downhill":
				offset = float(guide.nearest(Vector3(4, 44, -1150), -1)["offset"]) + 32.0
			"finish":
				offset = maxf(0.0, course.finish_offset - 62.0)
			"shortcut":
				if not course.branches.is_empty():
					guide = course.branches[0].get("guide") as PathGuide
					offset = guide.length * 0.42
		var xform := guide.transform_at(offset)
		var player := manager.player
		player.global_position = guide.point_at(offset, 0.0, 1.0)
		player.global_rotation = Vector3(0.0, guide.yaw_at(offset), 0.0)
		player.current_speed = 0.0
		player.set_process(false)
		player.set_physics_process(false)
		for racer: Racer in manager.racers:
			if racer != player:
				racer.visible = false
				racer.set_process(false)
				racer.set_physics_process(false)
		if zone == "cave_environment":
			for child: Node in course.get_children():
				if child is ItemBox:
					(child as ItemBox).visible = false
			print("[glacier_shot] cave environment plate hides shared ItemBox art only")
		_camera = Camera3D.new()
		_camera.name = "GlacierArtCamera"
		_camera.fov = 72.0 if height > width else 60.0
		_camera.near = 0.08
		course.add_child(_camera)
		var distance := 16.5 if height > width else 12.5
		var lift := 4.8 if height > width else 3.6
		_camera.global_position = xform.origin + xform.basis.z * distance \
			+ xform.basis.y * lift
		_camera.look_at(xform.origin - xform.basis.z * 30.0 + xform.basis.y * 2.4,
			Vector3.UP)
		_camera.make_current()
		ShaderWarmup.warm(get_tree().current_scene)
