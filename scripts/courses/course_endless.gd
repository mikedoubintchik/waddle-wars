class_name CourseEndless
extends CourseBase
## ENDLESS EXPEDITION: a long course assembled from reusable segment
## templates with a deterministic seed. Difficulty ramps with distance; a
## blizzard storm front chases the racers (see EndlessManager).

const SNOW := SurfacesDB.Surface.PACKED_SNOW
const DEEP := SurfacesDB.Surface.DEEP_SNOW
const ICE := SurfacesDB.Surface.ICE_SMOOTH
const RICE := SurfacesDB.Surface.ICE_ROUGH

## 0 = randomize per run; tests set a fixed value for determinism.
static var run_seed: int = 0

const SEGMENT_COUNT: int = 26

var _cursor: Vector3 = Vector3(0, 110, 30)
var _heading: float = 0.0  # yaw; 0 = -Z
var _pts: Array = []
var _post_build: Array[Callable] = []

## Rolling-terrain state: a slow sine swell (~±4.5m over ~570m wavelength)
## layered onto every segment's height so the expedition undulates instead of
## descending on a ruler. Driven purely by accumulated distance — fully
## deterministic per seed, and no extra rng draws (segment rolls stay
## byte-identical for a given run_seed).
const ROLL_AMPLITUDE: float = 4.5
const ROLL_FREQUENCY: float = 0.011  # rad per meter of course distance
var _roll_distance: float = 0.0
var _roll_prev: float = 0.0


func _init() -> void:
	course_id = "endless"


static func p2(pos: Vector3, extra: Dictionary = {}) -> Dictionary:
	var d := {"pos": pos}
	d.merge(extra)
	return d


func _advance(forward: float, lateral: float, drop: float, extra: Dictionary = {}) -> void:
	# Bounded wander keeps the course from self-intersecting.
	var turn := atan2(lateral, forward)
	_heading = clampf(_heading + turn, deg_to_rad(-38.0), deg_to_rad(38.0))
	var dist := Vector2(forward, lateral).length()
	_cursor += Vector3(-sin(_heading), 0.0, -cos(_heading)) * dist
	_cursor.y -= drop
	# Mild rolling swell on top of the segment's own drop. Applied as the
	# delta of an absolute sine so the roll never accumulates: worst-case
	# extra grade is ~ROLL_AMPLITUDE*ROLL_FREQUENCY (~2.8 degrees) on top of
	# the steepest segment (downhill, ~6.7 degrees) — well under the AI cap.
	_roll_distance += dist
	var roll := sin(_roll_distance * ROLL_FREQUENCY) * ROLL_AMPLITUDE
	_cursor.y += roll - _roll_prev
	_roll_prev = roll
	_pts.append(p2(_cursor, extra))


func build_course() -> void:
	var seed_value := run_seed if run_seed != 0 else int(Time.get_unix_time_from_system())
	rng.seed = seed_value

	_pts.append(p2(_cursor, {"width": 20.0}))
	_advance(60, 0, 1, {"width": 20.0})

	var segments: Array[String] = ["straight", "scurve", "downhill"]
	var pool_easy: Array[String] = ["straight", "scurve", "downhill", "boost_runway", "slalom"]
	var pool_mid: Array[String] = ["scurve", "downhill", "slalom", "tunnel", "climb", "geyser_field", "boost_runway"]
	var pool_hard: Array[String] = ["downhill", "tunnel", "snowball_alley", "icicle_run", "seal_crossing", "geyser_field", "slalom", "climb"]
	while segments.size() < SEGMENT_COUNT:
		var tier := segments.size() / 6
		var pool := pool_easy if tier == 0 else (pool_mid if tier == 1 else pool_hard)
		segments.append(pool[rng.randi_range(0, pool.size() - 1)])

	for i: int in segments.size():
		_build_segment(segments[i], 1.0 + float(i) * 0.05)
	_advance(120, 0, 2, {"width": 20.0})

	setup_main(_pts)
	finalize()
	for hook: Callable in _post_build:
		hook.call()

	# Fish and items sprinkled along the whole run.
	var offset := 100.0
	while offset < main_guide.length - 100.0:
		if rng.randf() < 0.65:
			add_fish_line(offset, rng.randi_range(5, 9), 5.0, rng.randf_range(-4.0, 4.0))
		if fmod(offset, 400.0) < 160.0:
			add_item_row(offset + 60.0)
		elif fmod(offset, 400.0) > 240.0:
			add_snowball_row(offset + 30.0)  # no rng draws: seed determinism kept
		offset += 170.0

	_decorate()
	build_environment({
		"sky_top": Color(0.2, 0.5, 0.86),
		"sky_horizon": Color(0.82, 0.92, 1.0),
		"ground_color": Color(0.85, 0.92, 0.98),
		"sun_angle_deg": -44.0,
		"sun_energy": 1.25,
		"fog_color": Color(0.82, 0.9, 1.0),
		"fog_density": 0.0018,
		"snow": true,
	})
	var lowest := INF
	for point: Vector3 in main_guide.points:
		lowest = minf(lowest, point.y)
	add_ground_plane(lowest - 18.0, Color(0.88, 0.93, 0.98))


func _build_segment(kind: String, intensity: float) -> void:
	match kind:
		"straight":
			# Front half packed snow, back half a smooth-ice patch: recurring
			# slide rewards on straights. rng draw order/count unchanged so
			# segment rolls stay byte-identical for a given run_seed. A point's
			# dict governs the span it STARTS (build_ribbon span [i, i+1) uses
			# points[i]), so ICE rides the mid point, not the end point.
			var fwd := rng.randf_range(90, 130)
			var lat := rng.randf_range(-15, 15)
			var drop := rng.randf_range(2, 5)
			_advance(fwd * 0.55, lat, drop * 0.55, {"width": 18.0, "surface": ICE})
			_advance(fwd * 0.45, 0, drop * 0.45, {"width": 18.0})
			var ice_start: Vector3 = _pts[_pts.size() - 2]["pos"]
			_post_build.append(func() -> void:
				var o := float(main_guide.nearest(ice_start, -1)["offset"])
				add_hint(o - 5.0, "slide", o + fwd * 0.45))
		"scurve":
			var side := 1.0 if rng.randf() > 0.5 else -1.0
			_advance(70, 35 * side, 3, {"width": 16.0})
			_advance(70, -35 * side, 3, {"width": 16.0})
			# Corner-exit acceleration pad: reward a clean line out of the S.
			var exit_pos := _cursor
			_post_build.append(func() -> void:
				var o := float(main_guide.nearest(exit_pos, -1)["offset"])
				TrackBuilder.add_boost_pad(self, main_guide, o - 6.0))
		"downhill":
			_advance(60, rng.randf_range(-10, 10), 4, {"width": 18.0, "surface": ICE})
			var start := _cursor
			_advance(120, rng.randf_range(-20, 20), 14, {"width": 18.0, "surface": ICE})
			_post_build.append(func() -> void:
				var o := float(main_guide.nearest(start, -1)["offset"])
				add_hint(o - 20.0, "slide", o + 160.0)
				# Pad at the drop-in launches the slide.
				TrackBuilder.add_boost_pad(self, main_guide, o + 6.0))
		"climb":
			# Acceleration pad at the uphill start helps carry speed into the
			# deep-snow grind.
			var base := _cursor
			_advance(90, rng.randf_range(-10, 10), -5, {"width": 14.0, "surface": DEEP})
			_advance(50, 0, 1, {"width": 16.0})
			_post_build.append(func() -> void:
				var o := float(main_guide.nearest(base, -1)["offset"])
				TrackBuilder.add_boost_pad(self, main_guide, o + 8.0))
		"slalom":
			var side := 1.0 if rng.randf() > 0.5 else -1.0
			for i: int in 3:
				_advance(45, 24 * side, 2, {"width": 12.0, "surface": RICE})
				side = -side
			var pos := _cursor
			_post_build.append(func() -> void:
				var xform := main_guide.transform_at(float(main_guide.nearest(pos, -1)["offset"]))
				for s: float in [-1.0, 1.0]:
					TrackBuilder.add_ice_crystal(self, xform.origin + xform.basis.x * (8.0 * s), rng.randf_range(2.5, 5.0)))
		"tunnel":
			_advance(50, 0, 2, {"width": 11.0, "surface": ICE})
			var start := _cursor
			_advance(60, 0, 2, {"width": 11.0, "surface": ICE})
			_post_build.append(func() -> void:
				var o := float(main_guide.nearest(start, -1)["offset"])
				TrackBuilder.add_overhead_bar(self, main_guide, o + 8.0)
				TrackBuilder.add_overhead_bar(self, main_guide, o + 34.0)
				add_hint(o - 35.0, "slide", o + 55.0))
		"geyser_field":
			var start := _cursor
			_advance(130, rng.randf_range(-12, 12), 5, {"width": 20.0})
			_post_build.append(func() -> void:
				var o := float(main_guide.nearest(start, -1)["offset"])
				for i: int in 4:
					var geyser := HazardGeyser.new()
					geyser.phase_offset = rng.randf() * 3.0
					geyser.position = main_guide.point_at(o + 20.0 + float(i) * 26.0, rng.randf_range(-6.0, 6.0), 0.0)
					add_child(geyser))
		"snowball_alley":
			var start := _cursor
			_advance(160, rng.randf_range(-14, 14), 8, {"width": 20.0})
			var end := _cursor
			_post_build.append(func() -> void:
				var o1 := float(main_guide.nearest(start, -1)["offset"])
				var o2 := float(main_guide.nearest(end, -1)["offset"])
				var ball := HazardSnowball.new()
				ball.configure(main_guide, o1, o2, rng.randf_range(-4.0, 4.0), 13.0 * intensity)
				add_child(ball)
				add_hint(o1 - 30.0, "danger_left" if rng.randf() > 0.5 else "danger_right", o2))
		"icicle_run":
			var start := _cursor
			_advance(110, rng.randf_range(-10, 10), 4, {"width": 14.0, "surface": RICE})
			_post_build.append(func() -> void:
				var o := float(main_guide.nearest(start, -1)["offset"])
				for i: int in 5:
					var icicle := HazardIcicle.new()
					icicle.position = main_guide.point_at(o + 12.0 + float(i) * 20.0, rng.randf_range(-5.0, 5.0), 7.0)
					add_child(icicle))
		"seal_crossing":
			var start := _cursor
			_advance(90, 0, 3, {"width": 20.0, "surface": ICE})
			_post_build.append(func() -> void:
				var o := float(main_guide.nearest(start, -1)["offset"])
				for i: int in 2:
					var seal := HazardSeal.new()
					seal.configure(main_guide, o + 25.0 + float(i) * 30.0, 7.0, 3.5 + intensity)
					add_child(seal))
		"boost_runway":
			var start := _cursor
			_advance(110, rng.randf_range(-8, 8), 6, {"width": 16.0, "surface": ICE})
			_post_build.append(func() -> void:
				var o := float(main_guide.nearest(start, -1)["offset"])
				TrackBuilder.add_boost_pad(self, main_guide, o + 25.0, -3.0)
				TrackBuilder.add_boost_pad(self, main_guide, o + 55.0, 3.0)
				add_fish_line(o + 20.0, 8, 5.0, 0.0, 1.5))


func _decorate() -> void:
	var offset := 80.0
	var side := 1.0
	while offset < main_guide.length - 80.0:
		var xform := main_guide.transform_at(offset)
		var lateral := (12.0 + rng.randf_range(0.0, 4.0)) * side
		if rng.randf() > 0.5:
			TrackBuilder.add_flag(self, xform.origin + xform.basis.x * lateral, Color(0.9, 0.3, 0.3) if side > 0 else Color(0.25, 0.5, 0.9))
		else:
			TrackBuilder.add_rock(self, xform.origin + xform.basis.x * (lateral + 4.0) + Vector3.DOWN, rng.randf_range(0.8, 1.6), rng)
		side = -side
		offset += 90.0
	for i: int in 12:
		var angle := TAU * float(i) / 12.0
		var dist := rng.randf_range(350.0, 550.0)
		var mountain := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = rng.randf_range(70.0, 120.0)
		cone.height = rng.randf_range(140.0, 260.0)
		cone.radial_segments = 7
		mountain.mesh = cone
		mountain.material_override = TrackBuilder.prop_material(Color(0.8, 0.87, 0.95), 0.9)
		mountain.position = Vector3(sin(angle) * dist, 40.0, -1500.0 + cos(angle) * dist * 1.6)
		add_child(mountain)


## Entry point used by race.gd for Mode.ENDLESS.
func run_endless(race_root: Node3D, powerups: PowerupSystem) -> void:
	var manager := EndlessManager.new()
	race_root.add_child(manager)
	manager.setup(self, powerups, false)
	var camera_rig := ChaseCamera.new()
	race_root.add_child(camera_rig)
	camera_rig.attach_to(manager.player)
	if not GameConfig.is_headless():
		camera_rig.camera.make_current()
	var hud := RaceHUD.new()
	race_root.add_child(hud)
	hud.setup(manager, manager.player)
	manager.hud = hud
	race_root.add_child(PauseMenu.new())
	if SettingsManager.touch_controls_enabled():
		var touch := TouchControls.new()
		race_root.add_child(touch)
		touch.setup(manager.player.controller as PlayerController)
	AudioManager.play_music("music_race")
