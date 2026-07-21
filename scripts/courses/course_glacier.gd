class_name CourseGlacier
extends CourseBase
## GLACIER GAUNTLET: bright daytime glacier. Wide beginner slope, ice cave
## slalom, low slide tunnel, cracking-ice shortcut, rolling snowball slope,
## deep-snow climb, and a huge final downhill slide.

const SNOW := SurfacesDB.Surface.PACKED_SNOW
const DEEP := SurfacesDB.Surface.DEEP_SNOW
const ICE := SurfacesDB.Surface.ICE_SMOOTH
const RICE := SurfacesDB.Surface.ICE_ROUGH


func _init() -> void:
	course_id = "glacier"


static func p(x: float, y: float, z: float, extra: Dictionary = {}) -> Dictionary:
	var d := {"pos": Vector3(x, y, z)}
	d.merge(extra)
	return d


func build_course() -> void:
	var pts: Array = [
		# Start plateau and pre-start straight.
		p(0, 60, 35, {"width": 18.0}),
		p(0, 60, -20, {"width": 18.0}),
		# Wide beginner slope, gentle right drift.
		p(4, 56, -90, {"width": 22.0}),
		p(14, 49, -170, {"width": 22.0}),
		p(24, 42, -240, {"width": 20.0}),
		# S-curves on packed snow.
		p(6, 38, -310, {"width": 16.0}),
		p(-14, 34, -370, {"width": 16.0}),
		p(-6, 32, -420, {"width": 14.0}),
		# Ice cave slalom (rough ice, narrower).
		p(8, 30, -460, {"width": 12.0, "surface": RICE}),
		p(-8, 28, -500, {"width": 12.0, "surface": RICE}),
		p(8, 27, -535, {"width": 12.0, "surface": RICE}),
		p(0, 26, -565, {"width": 12.0, "surface": RICE}),
		# Low tunnel: smooth ice, slide required under bars.
		p(0, 25, -600, {"width": 11.0, "surface": ICE}),
		p(0, 24, -640, {"width": 11.0, "surface": ICE, "wall_l": false}),
		# Safe loop right (the long way around the crevasse field).
		p(22, 23, -690, {"width": 14.0, "wall_l": false}),
		p(38, 21, -740, {"width": 14.0}),
		p(34, 19, -800, {"width": 14.0, "wall_l": false}),
		p(12, 17, -840, {"width": 16.0, "wall_l": false}),
		# Rejoin; rolling snowball slope (wide, descending).
		p(0, 15, -880, {"width": 20.0, "wall_l": false}),
		p(-8, 12, -950, {"width": 20.0}),
		p(-4, 9, -1020, {"width": 20.0}),
		# Deep snow climb.
		p(4, 10, -1070, {"width": 14.0, "surface": DEEP}),
		p(8, 14, -1120, {"width": 14.0, "surface": DEEP}),
		# Crest, then the big final downhill slide.
		p(4, 15, -1150, {"width": 18.0}),
		p(-10, 8, -1220, {"width": 18.0, "surface": ICE}),
		p(-16, 3, -1290, {"width": 18.0, "surface": ICE}),
		p(-8, 0.5, -1360, {"width": 18.0, "surface": ICE}),
		# Finish straight.
		p(0, 0, -1420, {"width": 18.0}),
		p(0, 0, -1470, {"width": 18.0}),
	]
	setup_main(pts)

	# Cracking-ice shortcut: cuts the safe loop, narrow smooth ice.
	var branch_pts: Array = [
		p(0, 23.3, -652, {"width": 10.0, "surface": ICE, "wall_l": false, "wall_r": false}),
		p(-4, 22, -700, {"width": 8.0, "surface": ICE, "wall_l": false, "wall_r": false}),
		# The crevasse: no floor, only cracking ice tiles bridge it.
		p(-4, 21, -724, {"width": 8.0, "gap": true, "wall_l": false, "wall_r": false}),
		p(-4, 19.5, -790, {"width": 8.0, "surface": ICE, "wall_l": false, "wall_r": false}),
		p(0, 15.5, -872, {"width": 10.0, "surface": ICE, "wall_l": false, "wall_r": false}),
	]
	var shortcut := add_branch(branch_pts, 0.65, "cracking_ice")

	finalize()

	# --- Track furniture ----------------------------------------------------
	var tunnel_offset := _offset_near(Vector3(0, 24.5, -620))

	# --- Hints for AI (offsets computed from geometry, not guessed) ---------
	add_hint(tunnel_offset - 40.0, "slide", tunnel_offset + 40.0)  # low tunnel
	var snowball_slope := _offset_near(Vector3(-8, 12, -950))
	add_hint(snowball_slope - 20.0, "slide", snowball_slope + 110.0)
	var final_downhill := _offset_near(Vector3(-10, 8, -1220))
	add_hint(final_downhill - 10.0, "slide", final_downhill + 190.0)
	add_hint(10.0, "slide", 120.0, 0)  # shortcut: slide the cracking ice fast
	TrackBuilder.add_overhead_bar(self, main_guide, tunnel_offset - 12.0)
	TrackBuilder.add_overhead_bar(self, main_guide, tunnel_offset + 10.0)

	var downhill_offset := _offset_near(Vector3(-10, 8, -1220))
	TrackBuilder.add_boost_pad(self, main_guide, downhill_offset + 20.0, -3.0)
	TrackBuilder.add_boost_pad(self, main_guide, downhill_offset + 60.0, 3.0)

	# Rolling snowballs on the wide descending slope: two lanes, offset
	# timing, plus AI danger hints steering bots toward the safe side.
	var snowball_slope_start := _offset_near(Vector3(0, 15, -880))
	var snowball_slope_end := _offset_near(Vector3(-4, 9, -1020))
	var ball_a := HazardSnowball.new()
	ball_a.configure(main_guide, snowball_slope_start, snowball_slope_end, -4.5, 15.0)
	add_child(ball_a)
	var ball_b := HazardSnowball.new()
	ball_b.configure(main_guide, snowball_slope_start + 60.0, snowball_slope_end, 4.5, 13.0)
	add_child(ball_b)
	add_hint(snowball_slope_start - 30.0, "danger_left", snowball_slope_start + 40.0)
	add_hint(snowball_slope_start + 40.0, "danger_right", snowball_slope_end)

	# Cracking ice tiles bridge the shortcut's crevasse: speed is safety.
	var gap_start := float(shortcut.nearest(Vector3(-4, 21, -724), -1)["offset"]) - 6.0
	var gap_end := float(shortcut.nearest(Vector3(-4, 19.5, -790), -1)["offset"]) + 6.0
	var tile_offset := gap_start
	while tile_offset < gap_end:
		var tile := HazardCrackingIce.new()
		add_child(tile)
		tile.global_position = shortcut.point_at(tile_offset, 0.0, -0.25)
		tile_offset += 5.8

	# Item rows and fish.
	add_item_row(120.0)
	add_item_row(_offset_near(Vector3(-6, 32, -420)) - 10.0)
	add_item_row(_offset_near(Vector3(12, 17, -840)))
	add_item_row(_offset_near(Vector3(4, 15, -1150)))
	add_fish_line(70.0, 6, 5.0, 0.0)
	add_fish_line(200.0, 8, 5.0, -4.0)
	add_fish_line(340.0, 8, 5.0, 4.0)
	add_fish_line(_offset_near(Vector3(8, 30, -460)), 10, 4.5, 0.0)
	add_fish_line(20.0, 8, 6.0, 0.0, 0.0, shortcut)  # reward the shortcut
	add_fish_line(_offset_near(Vector3(-8, 12, -950)), 10, 5.0, -5.0)
	add_fish_line(_offset_near(Vector3(-16, 3, -1290)), 12, 5.5, 0.0)

	_decorate()
	build_environment({
		"sky_top": Color(0.18, 0.45, 0.85),
		"sky_horizon": Color(0.8, 0.92, 1.0),
		"ground_color": Color(0.85, 0.92, 0.98),
		"sun_angle_deg": -50.0,
		"sun_energy": 1.45,
		"fog_color": Color(0.8, 0.9, 1.0),
		"fog_density": 0.0018,
		"snow": true,
	})
	add_ground_plane(-24.0, Color(0.88, 0.93, 0.98))


func _offset_near(point: Vector3) -> float:
	return float(main_guide.nearest(point, -1)["offset"])


func _decorate() -> void:
	# Course-side flags every ~110m alternating sides.
	var offset := 60.0
	var side := 1.0
	while offset < main_guide.length - 60.0:
		var xform := main_guide.transform_at(offset)
		var lateral := (10.0 + rng.randf_range(0.0, 3.0)) * side
		TrackBuilder.add_flag(self, xform.origin + xform.basis.x * lateral, Color(0.9, 0.3, 0.3) if side > 0 else Color(0.25, 0.5, 0.9))
		side = -side
		offset += 110.0

	# Ice cave: arches + crystals around the slalom.
	var cave_start := _offset_near(Vector3(8, 30, -460))
	var cave_end := _offset_near(Vector3(0, 26, -565))
	var cave_offset := cave_start
	while cave_offset < cave_end:
		var xform := main_guide.transform_at(cave_offset)
		var arch := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 8.0
		torus.outer_radius = 10.5
		arch.mesh = torus
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.5, 0.75, 0.95, 0.9)
		mat.roughness = 0.15
		mat.rim_enabled = true
		mat.rim = 0.5
		arch.material_override = mat
		arch.transform = Transform3D(xform.basis.rotated(xform.basis.x, deg_to_rad(90)), xform.origin + Vector3.UP * 1.0)
		add_child(arch)
		for side_sign: float in [-1.0, 1.0]:
			TrackBuilder.add_ice_crystal(self, xform.origin + xform.basis.x * (8.5 * side_sign) + Vector3.DOWN * 0.5,
				rng.randf_range(2.0, 5.0))
		cave_offset += 22.0

	# Spectator penguins near start and finish.
	for i: int in 10:
		var near_start := main_guide.transform_at(rng.randf_range(10.0, 90.0))
		var lateral := (11.5 + rng.randf_range(0.0, 4.0)) * (1.0 if i % 2 == 0 else -1.0)
		TrackBuilder.add_spectator(self, near_start.origin + near_start.basis.x * lateral, near_start.origin, rng)
	for i: int in 8:
		var near_finish := main_guide.transform_at(finish_offset - rng.randf_range(5.0, 70.0))
		var lateral := (11.5 + rng.randf_range(0.0, 4.0)) * (1.0 if i % 2 == 0 else -1.0)
		TrackBuilder.add_spectator(self, near_finish.origin + near_finish.basis.x * lateral, near_finish.origin, rng)

	# Distant mountains: big low-poly cones around the course.
	for i: int in 14:
		var angle := TAU * float(i) / 14.0 + rng.randf_range(-0.15, 0.15)
		var dist := rng.randf_range(320.0, 520.0)
		var mountain := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = rng.randf_range(60.0, 130.0)
		cone.height = rng.randf_range(120.0, 240.0)
		cone.radial_segments = 7
		mountain.mesh = cone
		mountain.material_override = TrackBuilder.prop_material(Color(0.82, 0.88, 0.96), 0.9)
		mountain.position = Vector3(sin(angle) * dist, -20.0 + cone.height * 0.5, -700.0 + cos(angle) * dist)
		add_child(mountain)

	# Rocks and crystals scattered along the route.
	for i: int in 26:
		var offset2 := rng.randf_range(40.0, main_guide.length - 60.0)
		var xform2 := main_guide.transform_at(offset2)
		var lateral2 := rng.randf_range(13.0, 26.0) * (1.0 if rng.randf() > 0.5 else -1.0)
		if rng.randf() > 0.4:
			TrackBuilder.add_rock(self, xform2.origin + xform2.basis.x * lateral2 + Vector3.DOWN * 1.0, rng.randf_range(0.7, 1.8), rng)
		else:
			TrackBuilder.add_ice_crystal(self, xform2.origin + xform2.basis.x * lateral2 + Vector3.DOWN * 1.0, rng.randf_range(2.0, 6.0))

	# Wooden research walkway along the safe loop.
	var walkway_start := _offset_near(Vector3(22, 23, -690))
	var walkway_offset := walkway_start
	while walkway_offset < walkway_start + 120.0:
		var xform3 := main_guide.transform_at(walkway_offset)
		var plank := MeshInstance3D.new()
		var plank_mesh := BoxMesh.new()
		plank_mesh.size = Vector3(2.4, 0.2, 5.5)
		plank.mesh = plank_mesh
		plank.material_override = TrackBuilder.prop_material(Color(0.55, 0.4, 0.24))
		plank.transform = Transform3D(xform3.basis, xform3.origin + xform3.basis.x * 9.5 + Vector3.UP * 0.6)
		add_child(plank)
		walkway_offset += 6.0
