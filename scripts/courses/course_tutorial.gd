class_name CourseTutorial
extends CourseBase
## WADDLE SCHOOL: a short guided course teaching steering, jumping, sliding,
## surfaces, shoving, items, checkpoints, and finishing — all through real
## gameplay with signposted practice zones.

const SNOW := SurfacesDB.Surface.PACKED_SNOW
const DEEP := SurfacesDB.Surface.DEEP_SNOW
const ICE := SurfacesDB.Surface.ICE_SMOOTH


func _init() -> void:
	course_id = "tutorial"


static func p(x: float, y: float, z: float, extra: Dictionary = {}) -> Dictionary:
	var d := {"pos": Vector3(x, y, z)}
	d.merge(extra)
	return d


func build_course() -> void:
	var pts: Array = [
		p(0, 20, 30, {"width": 18.0}),
		p(0, 20, -30, {"width": 18.0}),        # steering slalom zone
		p(-12, 19, -90, {"width": 18.0}),
		p(10, 18, -150, {"width": 18.0}),
		p(0, 17, -210, {"width": 16.0}),       # jump zone (bar hops)
		p(0, 16, -280, {"width": 14.0}),       # slide tunnel zone
		p(0, 15, -340, {"width": 14.0, "surface": ICE}),   # ice showcase
		p(0, 14.5, -400, {"width": 14.0, "surface": DEEP}),  # deep snow showcase
		p(0, 13, -450, {"width": 18.0}),       # shove practice
		p(0, 11, -520, {"width": 18.0}),       # item practice
		p(0, 8, -600, {"width": 18.0, "surface": ICE}),  # final slide
		p(0, 6, -660, {"width": 18.0}),
		p(0, 6, -700, {"width": 18.0}),
	]
	setup_main(pts)
	finalize()

	# Slalom gates.
	for gate: Array in [[80.0, -4.0], [110.0, 4.0], [140.0, -4.0]]:
		var xform := main_guide.transform_at(float(gate[0]))
		TrackBuilder.add_flag(self, xform.origin + xform.basis.x * (float(gate[1]) - 2.5), Color(0.3, 0.8, 0.4))
		TrackBuilder.add_flag(self, xform.origin + xform.basis.x * (float(gate[1]) + 2.5), Color(0.3, 0.8, 0.4))

	# Jump bars: low walls to hop over (thin, forgiving).
	var jump_offset := _offset_near(Vector3(0, 17, -210))
	for i: int in 2:
		var bar := StaticBody3D.new()
		bar.collision_layer = GameConfig.LAYER_WORLD
		bar.collision_mask = 0
		var mesh := BoxMesh.new()
		mesh.size = Vector3(14.0, 0.5, 0.5)
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = TrackBuilder.prop_material(Color(0.85, 0.4, 0.3))
		bar.add_child(instance)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = mesh.size
		shape.shape = box
		bar.add_child(shape)
		var xform := main_guide.transform_at(jump_offset + float(i) * 26.0)
		bar.transform = Transform3D(xform.basis, xform.origin + Vector3.UP * 0.3)
		add_child(bar)
		add_hint(jump_offset + float(i) * 26.0 - 12.0, "jump")

	# Slide tunnel.
	var tunnel_offset := _offset_near(Vector3(0, 16, -280))
	TrackBuilder.add_overhead_bar(self, main_guide, tunnel_offset)
	TrackBuilder.add_overhead_bar(self, main_guide, tunnel_offset + 18.0)
	add_hint(tunnel_offset - 35.0, "slide", tunnel_offset + 30.0)

	# Item box row for the item lesson.
	add_item_row(_offset_near(Vector3(0, 11, -520)) - 20.0)
	add_fish_line(60.0, 6, 5.0, 0.0)
	add_fish_line(_offset_near(Vector3(0, 15, -340)), 8, 5.0, 0.0)
	add_fish_line(_offset_near(Vector3(0, 8, -600)), 8, 5.0, 0.0)
	add_hint(_offset_near(Vector3(0, 8, -600)) - 10.0, "slide", _offset_near(Vector3(0, 6, -660)))

	# Friendly scenery.
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 7
	for i: int in 8:
		var xform := main_guide.transform_at(rng2.randf_range(20.0, main_guide.length - 40.0))
		TrackBuilder.add_spectator(self, xform.origin + xform.basis.x * (11.0 * (1.0 if i % 2 == 0 else -1.0)), xform.origin, rng2)
	build_environment({
		"sky_top": Color(0.35, 0.65, 0.9),
		"sky_horizon": Color(0.85, 0.93, 1.0),
		"sun_angle_deg": -55.0,
		"sun_energy": 1.3,
		"fog_color": Color(0.85, 0.92, 1.0),
		"fog_density": 0.003,
		"snow": false,
	})
	add_ground_plane(-10.0, Color(0.9, 0.94, 0.99))


func _offset_near(point: Vector3) -> float:
	return float(main_guide.nearest(point, -1)["offset"])


## Entry point used by race.gd for Mode.TUTORIAL.
func run_tutorial(race_root: Node3D, powerups: PowerupSystem) -> void:
	var manager := TutorialManager.new()
	race_root.add_child(manager)
	manager.setup_tutorial(self, powerups)
