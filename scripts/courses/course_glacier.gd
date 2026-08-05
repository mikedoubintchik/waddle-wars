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

	_retint_track_walls()
	_decorate()
	# Sunny alpine postcard: rich cobalt sky deepening overhead, warm strong
	# sun against cool sky-fill shadows, restrained ambient/exposure so snow
	# stays textured instead of blowing out, cream clouds for depth.
	build_environment({
		"sky_top": Color(0.05, 0.24, 0.7),
		"sky_horizon": Color(0.6, 0.8, 0.98),
		"ground_color": Color(0.42, 0.6, 0.84),
		"sun_angle_deg": -52.0,
		"sun_yaw_deg": -35.0,
		"sun_energy": 1.85,
		"sun_color": Color(1.0, 0.93, 0.78),
		"sun_angle_max": 22.0,
		"sun_curve": 0.12,
		"sky_energy": 1.0,
		"ambient_energy": 0.82,
		"exposure": 1.0,
		"fog_color": Color(0.7, 0.84, 0.98),
		"fog_density": 0.0012,
		"fog_height": -8.0,
		"fog_height_density": 0.045,
		"glow_threshold": 1.15,
		"shadow_distance": 150.0,
		"snow": true,
		"clouds": true,
		"cloud_color": Color(1.0, 0.96, 0.87, 0.82),
	})
	add_ground_plane(-24.0, Color(0.78, 0.86, 0.97), 4000.0,
		VisualLibrary.snow_material(Color(0.78, 0.86, 0.97), 0.2))


## TrackBuilder ships edge walls as a pale translucent blue and skirts as a
## soft grey-blue; both vanish into sunlit snow on this bright course. Retint
## them to a saturated azure so the track boundary reads clearly against the
## white floor. Walls and skirts get unique StandardMaterial3D instances per
## build_ribbon call, so mutating in place is safe; floors use ShaderMaterial
## overrides and are skipped by the type filter.
func _retint_track_walls() -> void:
	for track: Node in get_children():
		if track.name != &"MainTrack" and not String(track.name).begins_with("Branch_"):
			continue
		for child: Node in track.get_children():
			var instance := child as MeshInstance3D
			if instance == null:
				continue
			var mat := instance.material_override as StandardMaterial3D
			if mat == null:
				continue
			if mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
				mat.albedo_color = Color(0.16, 0.47, 0.9, 0.78)  # wall: saturated ice-blue
				mat.roughness = 0.12
			else:
				mat.albedo_color = Color(0.3, 0.48, 0.72)  # skirt: deep glacial flank


func _offset_near(point: Vector3) -> float:
	return float(main_guide.nearest(point, -1)["offset"])


## --- Decoration -------------------------------------------------------------
## Pure visual dressing. Skipped headless (nothing gameplay reads these nodes);
## instance counts scale with the particle_quality setting. Dense scenery uses
## MultiMeshInstance3D (one draw call per prop kind).

func _decorate() -> void:
	if GameConfig.is_headless():
		return
	var quality := String(SettingsManager.get_setting("display", "particle_quality"))
	var density := 1.0
	if quality == "medium":
		density = 0.75
	elif quality == "low":
		density = 0.5

	var crystal_transforms: Array[Transform3D] = []
	_decorate_flags()
	_decorate_cave(crystal_transforms)
	_decorate_scatter(density, crystal_transforms)
	_decorate_snowbanks(density)
	_decorate_walkways()
	_decorate_spectators(density)
	_decorate_mountains()

	# One shared multimesh for every ice crystal cluster on the course.
	# Cached rock_material is shared — duplicate before tweaking gloss.
	var crystal_mat := VisualLibrary.rock_material(Color(0.7, 0.87, 1.0)).duplicate() as StandardMaterial3D
	crystal_mat.roughness = 0.12
	crystal_mat.metallic = 0.05
	_add_multimesh(VisualLibrary.ice_crystal_mesh(), crystal_transforms, crystal_mat, "IceCrystals")


func _add_multimesh(mesh: Mesh, transforms: Array[Transform3D], material: Material, name_hint: String) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i: int in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = name_hint
	instance.multimesh = mm
	instance.material_override = material
	add_child(instance)


func _crystal_transform(pos: Vector3, height: float) -> Transform3D:
	var crystal_basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(height * 0.7, height, height * 0.7))
	return Transform3D(crystal_basis, pos)


## Route flags every ~70m alternating sides: pole multimesh + red/blue pennant
## multimeshes (saturated race colors against the snow).
func _decorate_flags() -> void:
	var pole_transforms: Array[Transform3D] = []
	var red_transforms: Array[Transform3D] = []
	var blue_transforms: Array[Transform3D] = []
	var offset := 60.0
	var side := 1.0
	while offset < main_guide.length - 60.0:
		var xform := main_guide.transform_at(offset)
		var lateral := (10.0 + rng.randf_range(0.0, 3.0)) * side
		var base := xform.origin + xform.basis.x * lateral
		var yaw := Basis(Vector3.UP, rng.randf() * TAU)
		pole_transforms.append(Transform3D(yaw, base + Vector3.UP * 1.5))
		var flag_basis := yaw * Basis(Vector3(0, 0, 1), deg_to_rad(-90.0))
		var flag_transform := Transform3D(flag_basis, base + Vector3.UP * 2.7 + yaw * Vector3(0.5, 0.0, 0.0))
		if side > 0.0:
			red_transforms.append(flag_transform)
		else:
			blue_transforms.append(flag_transform)
		side = -side
		offset += 70.0
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.05
	pole_mesh.bottom_radius = 0.07
	pole_mesh.height = 3.0
	pole_mesh.radial_segments = 8
	var flag_mesh := PrismMesh.new()
	flag_mesh.size = Vector3(1.0, 0.6, 0.06)
	_add_multimesh(pole_mesh, pole_transforms, TrackBuilder.prop_material(Color(0.5, 0.35, 0.2)), "FlagPoles")
	_add_multimesh(flag_mesh, red_transforms, TrackBuilder.prop_material(Color(0.92, 0.22, 0.25)), "FlagsRed")
	_add_multimesh(flag_mesh, blue_transforms, TrackBuilder.prop_material(Color(0.2, 0.45, 0.95)), "FlagsBlue")


## Ice cave slalom: shared fresnel-ice arches + crystal clusters, plus
## clusters framing the low slide tunnel.
func _decorate_cave(crystal_transforms: Array[Transform3D]) -> void:
	var cave_start := _offset_near(Vector3(8, 30, -460))
	var cave_end := _offset_near(Vector3(0, 26, -565))
	var torus := TorusMesh.new()
	torus.inner_radius = 8.0
	torus.outer_radius = 10.5
	torus.rings = 24
	torus.ring_segments = 10
	var arch_mat := VisualLibrary.ice_material(Color(0.28, 0.6, 0.98), 0.8)
	var cave_offset := cave_start
	while cave_offset < cave_end:
		var xform := main_guide.transform_at(cave_offset)
		var arch := MeshInstance3D.new()
		arch.mesh = torus
		arch.material_override = arch_mat
		arch.transform = Transform3D(xform.basis.rotated(xform.basis.x, deg_to_rad(90)), xform.origin + Vector3.UP * 1.0)
		add_child(arch)
		for side_sign: float in [-1.0, 1.0]:
			crystal_transforms.append(_crystal_transform(
				xform.origin + xform.basis.x * (8.5 * side_sign) + Vector3.DOWN * 0.5,
				rng.randf_range(2.0, 5.0)))
		cave_offset += 22.0
	var tunnel_offset := _offset_near(Vector3(0, 24.5, -620))
	for bar_offset: float in [tunnel_offset - 15.0, tunnel_offset + 13.0]:
		var xform2 := main_guide.transform_at(bar_offset)
		for side_sign: float in [-1.0, 1.0]:
			crystal_transforms.append(_crystal_transform(
				xform2.origin + xform2.basis.x * (7.5 * side_sign),
				rng.randf_range(2.5, 4.5)))


## Snow-capped rocks (two multimeshes: boulder + cap) and extra crystals
## scattered along the whole route.
func _decorate_scatter(density: float, crystal_transforms: Array[Transform3D]) -> void:
	var rock_transforms: Array[Transform3D] = []
	var cap_transforms: Array[Transform3D] = []
	var count := int(30.0 * density)
	for _i: int in count:
		var offset := rng.randf_range(40.0, main_guide.length - 60.0)
		var xform := main_guide.transform_at(offset)
		var lateral := rng.randf_range(13.0, 26.0) * (1.0 if rng.randf() > 0.5 else -1.0)
		var pos := xform.origin + xform.basis.x * lateral + Vector3.DOWN * 1.0
		if rng.randf() > 0.4:
			var s := rng.randf_range(0.7, 1.8)
			var squash := Vector3(rng.randf_range(0.8, 1.4), rng.randf_range(0.6, 1.0), rng.randf_range(0.8, 1.4)) * s
			var rock_basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(squash)
			rock_transforms.append(Transform3D(rock_basis, pos + Vector3.UP * 0.3 * s))
			cap_transforms.append(Transform3D(rock_basis, pos + Vector3.UP * 0.75 * s))
		else:
			crystal_transforms.append(_crystal_transform(pos, rng.randf_range(2.0, 5.5)))
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 0.8
	rock_mesh.height = 1.1
	rock_mesh.radial_segments = 8
	rock_mesh.rings = 5
	var cap_mesh := SphereMesh.new()
	cap_mesh.radius = 0.7
	cap_mesh.height = 0.5
	cap_mesh.radial_segments = 8
	cap_mesh.rings = 4
	_add_multimesh(rock_mesh, rock_transforms, TrackBuilder.prop_material(Color(0.45, 0.48, 0.54), 0.95), "Rocks")
	_add_multimesh(cap_mesh, cap_transforms, TrackBuilder.prop_material(Color(0.96, 0.98, 1.0), 0.9), "RockCaps")


## Snowbank drifts hugging the track edges, with occasional larger banks
## further out for depth. Single multimesh.
func _decorate_snowbanks(density: float) -> void:
	var transforms: Array[Transform3D] = []
	var step := 14.0 / density
	var offset := 24.0
	var side := 1.0
	while offset < main_guide.length - 24.0:
		var xform := main_guide.transform_at(offset)
		var lateral := (13.5 + rng.randf_range(0.0, 5.0)) * side
		var r := rng.randf_range(1.6, 3.6)
		var bank_basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(
			Vector3(r * rng.randf_range(0.85, 1.3), r * rng.randf_range(0.65, 1.0), r))
		transforms.append(Transform3D(bank_basis, xform.origin + xform.basis.x * lateral + Vector3.DOWN * 0.4))
		if rng.randf() > 0.6:
			var far_r := rng.randf_range(2.5, 5.0)
			var far_basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(far_r, far_r * 0.7, far_r))
			transforms.append(Transform3D(far_basis,
				xform.origin + xform.basis.x * (lateral + rng.randf_range(6.0, 14.0) * side) + Vector3.DOWN * 1.2))
		side = -side
		offset += step
	_add_multimesh(VisualLibrary.snow_drift_mesh(), transforms,
		VisualLibrary.rock_material(Color(1.0, 1.0, 1.0)), "Snowbanks")


## Wooden staging walkways flanking the start plateau plus the research
## walkway along the safe loop. Plank + post multimeshes.
func _decorate_walkways() -> void:
	var plank_transforms: Array[Transform3D] = []
	var post_transforms: Array[Transform3D] = []
	var offset := 4.0
	while offset < 52.0:
		var xform := main_guide.transform_at(offset)
		for side: float in [-1.0, 1.0]:
			plank_transforms.append(Transform3D(xform.basis, xform.origin + xform.basis.x * (11.0 * side) + Vector3.UP * 0.5))
			if int(offset) % 12 < 6:
				post_transforms.append(Transform3D(xform.basis, xform.origin + xform.basis.x * (11.0 * side) + Vector3.DOWN * 0.2))
		offset += 6.0
	var walkway_start := _offset_near(Vector3(22, 23, -690))
	var walkway_offset := walkway_start
	while walkway_offset < walkway_start + 120.0:
		var xform2 := main_guide.transform_at(walkway_offset)
		plank_transforms.append(Transform3D(xform2.basis, xform2.origin + xform2.basis.x * 9.5 + Vector3.UP * 0.6))
		if rng.randf() > 0.5:
			post_transforms.append(Transform3D(xform2.basis, xform2.origin + xform2.basis.x * 9.5 + Vector3.DOWN * 0.15))
		walkway_offset += 6.0
	var plank_mesh := BoxMesh.new()
	plank_mesh.size = Vector3(2.4, 0.2, 5.5)
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.09
	post_mesh.bottom_radius = 0.11
	post_mesh.height = 1.5
	post_mesh.radial_segments = 6
	_add_multimesh(plank_mesh, plank_transforms, TrackBuilder.prop_material(Color(0.52, 0.36, 0.2), 0.85), "WalkwayPlanks")
	_add_multimesh(post_mesh, post_transforms, TrackBuilder.prop_material(Color(0.4, 0.28, 0.16), 0.9), "WalkwayPosts")


## Spectator penguins at the start, the finish, and overlooking the
## cracking-ice shortcut from the safe loop.
func _decorate_spectators(density: float) -> void:
	var start_count := maxi(int(10.0 * density), 4)
	for i: int in start_count:
		var near_start := main_guide.transform_at(rng.randf_range(10.0, 90.0))
		var lateral := (11.5 + rng.randf_range(0.0, 4.0)) * (1.0 if i % 2 == 0 else -1.0)
		TrackBuilder.add_spectator(self, near_start.origin + near_start.basis.x * lateral, near_start.origin, rng)
	var finish_count := maxi(int(8.0 * density), 4)
	for i: int in finish_count:
		var near_finish := main_guide.transform_at(finish_offset - rng.randf_range(5.0, 70.0))
		var lateral := (11.5 + rng.randf_range(0.0, 4.0)) * (1.0 if i % 2 == 0 else -1.0)
		TrackBuilder.add_spectator(self, near_finish.origin + near_finish.basis.x * lateral, near_finish.origin, rng)
	var overlook := _offset_near(Vector3(38, 21, -740))
	var overlook_count := maxi(int(6.0 * density), 3)
	for _i: int in overlook_count:
		var xform := main_guide.transform_at(overlook + rng.randf_range(-25.0, 25.0))
		var pos := xform.origin - xform.basis.x * (12.0 + rng.randf_range(0.0, 3.0))
		TrackBuilder.add_spectator(self, pos, xform.origin, rng)


## --- Distant mountains ------------------------------------------------------
## Two depth rings of varied low-poly peaks with baked per-face colors:
## streaked rock walls below a per-peak snowline, white caps above. The far
## ring is pre-hazed toward the horizon tint for atmospheric layering.

func _decorate_mountains() -> void:
	var center := Vector3(0.0, -24.0, -700.0)
	for i: int in 9:
		_place_mountain(1000 + i, center, 300.0, 470.0, 130.0, 220.0, 0.08)
	for i: int in 9:
		_place_mountain(2000 + i, center, 560.0, 790.0, 200.0, 330.0, 0.42)


func _place_mountain(seed_value: int, center: Vector3, dist_min: float, dist_max: float, h_min: float, h_max: float, haze: float) -> void:
	var height := rng.randf_range(h_min, h_max)
	var footprint := height * rng.randf_range(0.55, 0.85)
	for _attempt: int in 10:
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(dist_min, dist_max)
		var pos := center + Vector3(sin(angle) * dist, 0.0, cos(angle) * dist)
		# Never plant a peak on top of the racing line: base-ring vertices
		# reach up to ~1.4x footprint (column scale * jitter), so demand that
		# much horizontal clearance to the nearest main-guide point.
		var res := main_guide.nearest(pos, -1)
		var near_pt := main_guide.position_at(float(res["offset"]))
		var horizontal := Vector2(pos.x - near_pt.x, pos.z - near_pt.z).length()
		if horizontal < footprint * 1.45 + 30.0:
			continue
		var instance := MeshInstance3D.new()
		instance.mesh = _mountain_mesh(seed_value, haze)
		instance.material_override = VisualLibrary.rock_material(Color(1.0, 1.0, 1.0))
		instance.scale = Vector3(footprint, height, footprint)
		instance.rotation.y = rng.randf() * TAU
		instance.position = pos
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		return


## Unit-scale (about 1m tall) irregular ridged cone, deterministic per seed.
## Per-face colors: rock with vertical streak variation below the snowline,
## snow above, blended in a transition band; haze lerps toward horizon blue.
func _mountain_mesh(seed_value: int, haze: float) -> ArrayMesh:
	var mrng := RandomNumberGenerator.new()
	mrng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 8
	var ring_heights: Array[float] = [0.0, mrng.randf_range(0.38, 0.5), mrng.randf_range(0.68, 0.78)]
	var ring_radii: Array[float] = [1.0, mrng.randf_range(0.52, 0.66), mrng.randf_range(0.24, 0.34)]
	var column_scale: Array[float] = []
	var streaks: Array[float] = []
	for i: int in sides:
		column_scale.append(mrng.randf_range(0.78, 1.28))
		streaks.append(mrng.randf_range(0.5, 1.05))
	var rings: Array[PackedVector3Array] = []
	for r: int in ring_heights.size():
		var ring: PackedVector3Array = []
		for i: int in sides:
			var angle := TAU * float(i) / float(sides)
			var radius := ring_radii[r] * column_scale[i] * mrng.randf_range(0.9, 1.1)
			var y := ring_heights[r] + (mrng.randf_range(-0.04, 0.05) if r > 0 else 0.0)
			ring.append(Vector3(cos(angle) * radius, y, sin(angle) * radius))
		rings.append(ring)
	var apex := Vector3(mrng.randf_range(-0.08, 0.08), mrng.randf_range(0.95, 1.1), mrng.randf_range(-0.08, 0.08))
	var snowline := mrng.randf_range(0.5, 0.6)
	# Dark base values on purpose: ACES + sky ambient lift vertex colors a lot,
	# so mid-gray-brown here reads as sunlit rock, not near-white.
	var rock_base := Color(0.26, 0.24, 0.26).lerp(Color(0.33, 0.26, 0.19), mrng.randf())
	for r: int in ring_heights.size() - 1:
		for i: int in sides:
			var j := (i + 1) % sides
			var lo0 := rings[r][i]
			var lo1 := rings[r][j]
			var hi0 := rings[r + 1][i]
			var hi1 := rings[r + 1][j]
			var col := _mountain_face_color((lo0.y + lo1.y + hi0.y + hi1.y) * 0.25, snowline, rock_base, streaks[i], haze)
			_ctri(st, lo0, hi1, hi0, col)
			_ctri(st, lo0, lo1, hi1, col)
	var top := ring_heights.size() - 1
	for i: int in sides:
		var j := (i + 1) % sides
		var col := _mountain_face_color((rings[top][i].y + rings[top][j].y + apex.y) / 3.0, snowline, rock_base, streaks[i], haze)
		_ctri(st, rings[top][i], rings[top][j], apex, col)
	st.generate_normals()
	return st.commit()


func _mountain_face_color(height: float, snowline: float, rock_base: Color, streak: float, haze: float) -> Color:
	var rock := Color(rock_base.r * streak, rock_base.g * streak, rock_base.b * streak)
	var snow := Color(0.95, 0.97, 1.0)
	var col: Color
	if height > snowline + 0.05:
		col = snow
	elif height > snowline - 0.1:
		col = rock.lerp(snow, (height - (snowline - 0.1)) / 0.15)
	else:
		col = rock
	return col.lerp(Color(0.6, 0.77, 0.96), haze)


static func _ctri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	st.set_color(color)
	st.add_vertex(a)
	st.set_color(color)
	st.add_vertex(b)
	st.set_color(color)
	st.add_vertex(c)
