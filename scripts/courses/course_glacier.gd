class_name CourseGlacier
extends CourseBase
## GLACIER GAUNTLET: bright daytime glacier. Rolling opening hills, a genuine
## climb into the ice cave slalom, low slide tunnel, cracking-ice shortcut,
## rolling snowball slope, deep-snow climb, and a huge sustained final
## downhill slide (crest 44m -> finish 0.5m at -9..-12 degrees).

const SNOW := SurfacesDB.Surface.PACKED_SNOW
const DEEP := SurfacesDB.Surface.DEEP_SNOW
const ICE := SurfacesDB.Surface.ICE_SMOOTH
const RICE := SurfacesDB.Surface.ICE_ROUGH

## Prevailing wind heading (world yaw, degrees). Wind-sculpted snow forms —
## drift banks and sastrugi ridges — elongate along this axis; it sits ~60
## degrees off the sun yaw (-35) so their lee faces model in shadow.
const WIND_YAW_DEG := 24.0


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
		# Rolling opening hills: two dips with a roll crest between them. The
		# first dip is a smooth-ice patch: an early slide reward on a straight
		# descent, well clear of any hazard.
		p(4, 54, -90, {"width": 22.0, "surface": ICE}),
		p(14, 46, -170, {"width": 22.0}),
		p(24, 48.5, -240, {"width": 20.0}),
		# S-curve valley on packed snow, then the climb toward the cave begins.
		p(6, 42.5, -310, {"width": 16.0}),
		p(-14, 40, -370, {"width": 16.0}),
		p(-6, 44, -420, {"width": 14.0}),
		# Ice cave slalom (rough ice, narrower): a genuine climb to a crest.
		p(8, 49, -460, {"width": 12.0, "surface": RICE}),
		p(-8, 52, -500, {"width": 12.0, "surface": RICE}),
		p(8, 53.5, -535, {"width": 12.0, "surface": RICE}),
		p(0, 52.5, -565, {"width": 12.0, "surface": RICE}),
		# Low tunnel: smooth ice, slide required under bars.
		p(0, 51, -600, {"width": 11.0, "surface": ICE}),
		p(0, 49.5, -640, {"width": 11.0, "surface": ICE, "wall_l": false}),
		# Safe loop right (the long way around the crevasse field).
		p(22, 48, -690, {"width": 14.0, "wall_l": false}),
		p(38, 46, -740, {"width": 14.0}),
		p(34, 44, -800, {"width": 14.0, "wall_l": false}),
		p(12, 42.5, -840, {"width": 16.0, "wall_l": false}),
		# Rejoin; rolling snowball slope (wide, descending).
		p(0, 41.5, -880, {"width": 20.0, "wall_l": false}),
		p(-8, 36.5, -950, {"width": 20.0}),
		p(-4, 32, -1020, {"width": 20.0}),
		# Deep snow climb.
		p(4, 35, -1070, {"width": 14.0, "surface": DEEP}),
		p(8, 41, -1120, {"width": 14.0, "surface": DEEP}),
		# Crest, then the big final downhill slide: 43.5m sustained drop. The
		# crest span is smooth ice too, so the slide starts at the top.
		p(4, 44, -1150, {"width": 18.0, "surface": ICE}),
		p(-10, 33, -1220, {"width": 18.0, "surface": ICE}),
		p(-16, 18, -1290, {"width": 18.0, "surface": ICE}),
		p(-8, 4, -1360, {"width": 18.0, "surface": ICE}),
		# Finish straight: iced so the downhill slide carries to the line.
		p(0, 0.5, -1420, {"width": 18.0, "surface": ICE}),
		p(0, 0, -1470, {"width": 18.0}),
	]
	setup_main(pts)

	# Cracking-ice shortcut: cuts the safe loop, narrow smooth ice.
	var branch_pts: Array = [
		p(0, 49.1, -652, {"width": 10.0, "surface": ICE, "wall_l": false, "wall_r": false}),
		p(-4, 47.8, -700, {"width": 8.0, "surface": ICE, "wall_l": false, "wall_r": false}),
		# The crevasse: no floor, only cracking ice tiles bridge it.
		p(-4, 47, -724, {"width": 8.0, "gap": true, "wall_l": false, "wall_r": false}),
		p(-4, 45, -790, {"width": 8.0, "surface": ICE, "wall_l": false, "wall_r": false}),
		p(0, 41.8, -872, {"width": 10.0, "surface": ICE, "wall_l": false, "wall_r": false}),
	]
	var shortcut := add_branch(branch_pts, 0.65, "cracking_ice")

	finalize()

	# --- Track furniture ----------------------------------------------------
	var tunnel_offset := _offset_near(Vector3(0, 50.3, -620))

	# --- Hints for AI (offsets computed from geometry, not guessed) ---------
	add_hint(tunnel_offset - 40.0, "slide", tunnel_offset + 40.0)  # low tunnel
	var snowball_slope := _offset_near(Vector3(-8, 36.5, -950))
	add_hint(snowball_slope - 20.0, "slide", snowball_slope + 110.0)
	var final_downhill := _offset_near(Vector3(-10, 33, -1220))
	add_hint(final_downhill - 10.0, "slide", final_downhill + 190.0)
	add_hint(10.0, "slide", 120.0, 0)  # shortcut: slide the cracking ice fast
	TrackBuilder.add_overhead_bar(self, main_guide, tunnel_offset - 12.0)
	TrackBuilder.add_overhead_bar(self, main_guide, tunnel_offset + 10.0)

	var downhill_offset := _offset_near(Vector3(-10, 33, -1220))
	TrackBuilder.add_boost_pad(self, main_guide, downhill_offset + 20.0, -3.0)
	TrackBuilder.add_boost_pad(self, main_guide, downhill_offset + 60.0, 3.0)

	# More acceleration pads: the opening-dip exit (launch through the roll
	# crest) and both uphill starts (cave climb, deep-snow climb) so held
	# momentum is the reward for a clean line. All on straight track, clear
	# of the snowball lanes and the crevasse field.
	var open_dip := _offset_near(Vector3(4, 54, -90))
	var dip_exit := _offset_near(Vector3(14, 46, -170))
	TrackBuilder.add_boost_pad(self, main_guide, dip_exit + 5.0)
	TrackBuilder.add_boost_pad(self, main_guide, _offset_near(Vector3(-6, 44, -420)) + 8.0)
	TrackBuilder.add_boost_pad(self, main_guide, _offset_near(Vector3(4, 35, -1070)) - 6.0)
	# Slide hints for the new smooth-ice patches (surfaces set in the point
	# list): opening dip, crest-to-downhill bridge, finish straight.
	add_hint(open_dip - 5.0, "slide", dip_exit + 5.0)
	add_hint(_offset_near(Vector3(4, 44, -1150)) + 5.0, "slide", final_downhill - 10.0)
	add_hint(_offset_near(Vector3(0, 0.5, -1420)) - 5.0, "slide", finish_offset)

	# Rolling snowballs on the wide descending slope: two lanes, offset
	# timing, plus AI danger hints steering bots toward the safe side.
	var snowball_slope_start := _offset_near(Vector3(0, 41.5, -880))
	var snowball_slope_end := _offset_near(Vector3(-4, 32, -1020))
	var ball_a := HazardSnowball.new()
	ball_a.configure(main_guide, snowball_slope_start, snowball_slope_end, -4.5, 15.0)
	add_child(ball_a)
	var ball_b := HazardSnowball.new()
	ball_b.configure(main_guide, snowball_slope_start + 60.0, snowball_slope_end, 4.5, 13.0)
	add_child(ball_b)
	add_hint(snowball_slope_start - 30.0, "danger_left", snowball_slope_start + 40.0)
	add_hint(snowball_slope_start + 40.0, "danger_right", snowball_slope_end)

	# Cracking ice tiles bridge the shortcut's crevasse: speed is safety.
	var gap_start := float(shortcut.nearest(Vector3(-4, 47, -724), -1)["offset"]) - 6.0
	var gap_end := float(shortcut.nearest(Vector3(-4, 45, -790), -1)["offset"]) + 6.0
	var tile_offset := gap_start
	while tile_offset < gap_end:
		var tile := HazardCrackingIce.new()
		add_child(tile)
		tile.global_position = shortcut.point_at(tile_offset, 0.0, -0.25)
		tile_offset += 5.8
	# Shortcut-survivor reward: a boost pad on solid ice past the crevasse.
	TrackBuilder.add_boost_pad(self, shortcut, gap_end + 12.0)

	# Item rows and fish.
	add_item_row(120.0)
	add_item_row(_offset_near(Vector3(-6, 44, -420)) - 10.0)
	add_item_row(_offset_near(Vector3(12, 42.5, -840)))
	add_item_row(_offset_near(Vector3(4, 44, -1150)))
	add_snowball_row(160.0)
	add_snowball_row(_offset_near(Vector3(-6, 44, -420)) + 25.0)
	add_snowball_row(_offset_near(Vector3(4, 44, -1150)) - 35.0)
	add_fish_line(70.0, 6, 5.0, 0.0)
	add_fish_line(200.0, 8, 5.0, -4.0)
	add_fish_line(340.0, 8, 5.0, 4.0)
	add_fish_line(_offset_near(Vector3(8, 49, -460)), 10, 4.5, 0.0)
	add_fish_line(20.0, 8, 6.0, 0.0, 0.0, shortcut)  # reward the shortcut
	add_fish_line(_offset_near(Vector3(-8, 36.5, -950)), 10, 5.0, -5.0)
	add_fish_line(_offset_near(Vector3(-16, 18, -1290)), 12, 5.5, 0.0)

	_retint_track_walls()
	# Frozen lake sheet first: the mountains, lake cracks and sun-glint bands
	# all seat themselves on it, so it has to exist before _decorate() runs.
	# Sparkle raised so the distant ice sheet reads as sunlit glitter, backing
	# the additive sun-glint bands placed by _decorate_sun_glint().
	add_ground_plane(-24.0, Color(0.78, 0.86, 0.97), 4000.0,
		VisualLibrary.snow_material(Color(0.78, 0.86, 0.97), 0.5))
	_decorate()
	# Sunny alpine postcard in late-morning light: rich cobalt sky deepening
	# overhead, a warm lower sun raking long shadows off drifts, sastrugi and
	# ridgelines (real form modeling instead of flat noon light), cool
	# sky-fill shadows, restrained ambient/exposure so snow stays textured
	# instead of blowing out, cream clouds for depth.
	build_environment({
		"sky_top": Color(0.05, 0.24, 0.7),
		"sky_horizon": Color(0.6, 0.8, 0.98),
		"ground_color": Color(0.42, 0.6, 0.84),
		"sun_angle_deg": -38.0,
		"sun_yaw_deg": -35.0,
		"sun_energy": 1.38,
		"sun_color": Color(1.0, 0.94, 0.82),
		"sun_angle_max": 22.0,
		"sun_curve": 0.12,
		"sky_energy": 1.0,
		"ambient_energy": 0.72,
		"exposure": 0.90,
		"fog_color": Color(0.7, 0.84, 0.98),
		"fog_density": 0.0012,
		"fog_height": -8.0,
		"fog_height_density": 0.045,
		"glow_threshold": 1.5,
		"shadow_distance": 150.0,
		"snow": true,
		"clouds": true,
		"cloud_color": Color(1.0, 0.96, 0.87, 0.82),
	})


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
	var icicle_transforms: Array[Transform3D] = []
	_decorate_flags()
	_decorate_cave(crystal_transforms, icicle_transforms)
	_decorate_scatter(density, crystal_transforms)
	_decorate_snowbanks(density)
	_decorate_sastrugi(density)
	_decorate_walkways()
	_decorate_spectators(density)
	_decorate_mountains()
	_decorate_cliffs(density)
	_decorate_icefall()
	_decorate_boulders(density)
	_decorate_cave_glints(density)
	_decorate_crevasse_cracks()
	_decorate_lake_cracks()
	_decorate_fog(density)
	_decorate_sun_glint()
	_decorate_birds()

	# One shared multimesh for every ice crystal cluster on the course, plus a
	# second for hanging icicles (same mesh flipped in the instance transform).
	# Cached rock_material is shared — duplicate before tweaking gloss.
	var crystal_mat := VisualLibrary.rock_material(Color(0.7, 0.87, 1.0)).duplicate() as StandardMaterial3D
	crystal_mat.roughness = 0.12
	crystal_mat.metallic = 0.05
	_add_multimesh(VisualLibrary.ice_crystal_mesh(), crystal_transforms, crystal_mat, "IceCrystals")
	_add_multimesh(VisualLibrary.ice_crystal_mesh(), icicle_transforms, crystal_mat, "Icicles")


## range_base > 0 opts the dressing into VisualLibrary.apply_dressing_range
## distance culling. Visibility range keys off the NODE origin, so the node is
## re-anchored at the transforms' centroid (instance transforms made relative):
## the fade then measures from the feature itself, not world zero.
func _add_multimesh(mesh: Mesh, transforms: Array[Transform3D], material: Material, name_hint: String, shadows: bool = true, range_base: float = 0.0) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	var instance := MultiMeshInstance3D.new()
	instance.name = name_hint
	instance.multimesh = mm
	instance.material_override = material
	if not shadows:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if range_base > 0.0:
		var centroid := Vector3.ZERO
		for t: Transform3D in transforms:
			centroid += t.origin
		centroid /= float(transforms.size())
		instance.position = centroid
		for i: int in transforms.size():
			mm.set_instance_transform(i, Transform3D(transforms[i].basis, transforms[i].origin - centroid))
		VisualLibrary.apply_dressing_range(instance, range_base)
	else:
		for i: int in transforms.size():
			mm.set_instance_transform(i, transforms[i])
	add_child(instance)


## Ground crystal cluster: random yaw, a slight natural tilt off vertical
## (frost heave, uneven bedding) and per-cluster width/height aspect jitter
## so no two clusters share one silhouette.
func _crystal_transform(pos: Vector3, height: float) -> Transform3D:
	var aspect := rng.randf_range(0.55, 0.85)
	var tilt_dir := rng.randf() * TAU
	var tilt_axis := Vector3(cos(tilt_dir), 0.0, sin(tilt_dir))
	var crystal_basis := Basis(tilt_axis, rng.randf_range(-0.14, 0.14)) \
		* Basis(Vector3.UP, rng.randf() * TAU) \
		* Basis.from_scale(Vector3(height * aspect, height * rng.randf_range(0.85, 1.1), height * aspect))
	return Transform3D(crystal_basis, pos)


## Hanging icicle: the shared crystal mesh flipped upside-down. pos is the
## attachment point (underside of a bar / arch); the tip reaches height below.
func _icicle_transform(pos: Vector3, height: float) -> Transform3D:
	var icicle_basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, PI) \
		* Basis.from_scale(Vector3(height * 0.45, height, height * 0.45))
	return Transform3D(icicle_basis, pos)


## Route flags every ~70m alternating sides: pole multimesh + red/blue pennant
## multimeshes (saturated race colors against the snow). Laterals are measured
## off the real deck edge and the pole feet are planted on the surface under
## them: the track runs 11m wide through the tunnel and 22m wide through the
## opening hills, so a constant 10-13m lateral used to plant flags on the
## racing floor in one place and 7m out over the drop in another.
func _decorate_flags() -> void:
	var pole_transforms: Array[Transform3D] = []
	var red_transforms: Array[Transform3D] = []
	var blue_transforms: Array[Transform3D] = []
	var offset := 60.0
	var side := 1.0
	while offset < main_guide.length - 60.0:
		var xform := main_guide.transform_at(offset)
		var lateral := (track_edge_lateral(main_guide, offset, side, 9.0) + rng.randf_range(0.7, 2.6)) * side
		var base := seat_dressing(xform, lateral, 3.0)
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
	# Event-energy clusters: dense pennant rows on both sides of the start
	# plateau and the finish straight (red/blue plus gold accents), so the
	# bookend moments of the race read as a staged event, not empty snow.
	var gold_transforms: Array[Transform3D] = []
	var cluster_offsets: Array[float] = [8.0, 20.0, 32.0, 44.0, 56.0]
	for i: int in 5:
		cluster_offsets.append(finish_offset - 10.0 - float(i) * 13.0)
	for cluster_offset: float in cluster_offsets:
		var cluster_xform := main_guide.transform_at(cluster_offset)
		for side_sign: float in [-1.0, 1.0]:
			var lateral := (track_edge_lateral(main_guide, cluster_offset, side_sign, 9.6)
				+ rng.randf_range(0.8, 2.6)) * side_sign
			var base := seat_dressing(cluster_xform, lateral, 3.0)
			var yaw := Basis(Vector3.UP, rng.randf() * TAU)
			pole_transforms.append(Transform3D(yaw, base + Vector3.UP * 1.5))
			var flag_basis := yaw * Basis(Vector3(0, 0, 1), deg_to_rad(-90.0))
			var flag_transform := Transform3D(flag_basis, base + Vector3.UP * 2.7 + yaw * Vector3(0.5, 0.0, 0.0))
			var pick := rng.randi_range(0, 2)
			if pick == 0:
				red_transforms.append(flag_transform)
			elif pick == 1:
				blue_transforms.append(flag_transform)
			else:
				gold_transforms.append(flag_transform)
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
	_add_multimesh(flag_mesh, gold_transforms, TrackBuilder.prop_material(Color(0.98, 0.78, 0.22)), "FlagsGold")


## Ice cave slalom: a monumental wind-carved natural ice arch gateway at the
## entrance, smooth high-segment fresnel-ice arches through the slalom,
## towering crystal monoliths (3-8m — landmark scale, not garden gnomes), and
## icicle clusters hanging under the arch crown and the low slide bars.
func _decorate_cave(crystal_transforms: Array[Transform3D], icicle_transforms: Array[Transform3D]) -> void:
	var cave_start := _offset_near(Vector3(8, 49, -460))
	var cave_end := _offset_near(Vector3(0, 52.5, -565))

	# Monumental gateway spanning the track where the slalom begins.
	var gate_xform := main_guide.transform_at(cave_start - 6.0)
	var arch_gate := MeshInstance3D.new()
	arch_gate.name = "IceArchGateway"
	arch_gate.mesh = _ice_arch_mesh(4242)
	var gate_mat := VisualLibrary.rock_material(Color(1.0, 1.0, 1.0)).duplicate() as StandardMaterial3D
	gate_mat.roughness = 0.18
	gate_mat.rim_enabled = true
	gate_mat.rim = 0.35
	arch_gate.material_override = gate_mat
	# Feet buried deeper than the mesh's own flare: they land ~12m out, well
	# past the 6m-half cave deck, so a shallow set left two thick stumps
	# hanging over the drop. At -3.2 they sit below the track-edge sight line
	# and the crown still clears 8m over the gateway.
	arch_gate.transform = Transform3D(gate_xform.basis, gate_xform.origin + Vector3.DOWN * 3.2)
	add_child(arch_gate)
	# Icicle fringe under the arch crown (well above racer height).
	for _i: int in 6:
		var hang := gate_xform.origin + gate_xform.basis.x * rng.randf_range(-4.5, 4.5) \
			+ Vector3.UP * rng.randf_range(8.2, 10.2) + gate_xform.basis.z * rng.randf_range(-1.2, 1.2)
		icicle_transforms.append(_icicle_transform(hang, rng.randf_range(1.3, 2.3)))
	# Towering monolith crystals flanking the gateway feet, rooted on the
	# shoulder instead of hovering at a constant 11-13.5m over a 12m-wide deck.
	var gate_offset := cave_start - 6.0
	var back_xform := main_guide.transform_at(gate_offset + 6.0)
	for side_sign: float in [-1.0, 1.0]:
		crystal_transforms.append(_crystal_transform(
			seat_dressing(gate_xform,
				(track_edge_lateral(main_guide, gate_offset, side_sign, 8.0) + 1.2) * side_sign, 7.5, 4.0, 0.1),
			rng.randf_range(6.0, 9.0)))
		crystal_transforms.append(_crystal_transform(
			seat_dressing(back_xform,
				(track_edge_lateral(main_guide, gate_offset + 6.0, side_sign, 8.0) + 3.2) * side_sign, 4.7, 4.5, 0.1),
			rng.randf_range(3.5, 6.0)))

	# Slalom interior: smooth high-segment ice arches (no low-poly banding).
	var torus := TorusMesh.new()
	torus.inner_radius = 8.0
	torus.outer_radius = 10.5
	torus.rings = 48
	torus.ring_segments = 16
	var arch_mat := VisualLibrary.ice_material(Color(0.28, 0.6, 0.98), 0.8)
	var cave_offset := cave_start + 20.0
	while cave_offset < cave_end:
		var xform := main_guide.transform_at(cave_offset)
		var arch := MeshInstance3D.new()
		arch.mesh = torus
		arch.material_override = arch_mat
		arch.transform = Transform3D(xform.basis.rotated(xform.basis.x, deg_to_rad(90)), xform.origin + Vector3.UP * 1.0)
		add_child(arch)
		for side_sign: float in [-1.0, 1.0]:
			crystal_transforms.append(_crystal_transform(
				seat_dressing(xform,
					(track_edge_lateral(main_guide, cave_offset, side_sign, 6.0) + 1.0) * side_sign,
					5.7, 4.0, 0.1),
				rng.randf_range(3.5, 8.0)))
		cave_offset += 22.0
	var tunnel_offset := _offset_near(Vector3(0, 50.3, -620))
	for bar_offset: float in [tunnel_offset - 15.0, tunnel_offset + 13.0]:
		var xform2 := main_guide.transform_at(bar_offset)
		for side_sign: float in [-1.0, 1.0]:
			crystal_transforms.append(_crystal_transform(
				seat_dressing(xform2,
					(track_edge_lateral(main_guide, bar_offset, side_sign, 5.5) + 1.0) * side_sign,
					4.5, 4.0, 0.1),
				rng.randf_range(3.0, 6.0)))
	# Icicles fringe the undersides of the two slide bars: they whip past
	# overhead as racers belly-slide through, selling the low clearance.
	for bar_offset: float in [tunnel_offset - 12.0, tunnel_offset + 10.0]:
		var bar_xform := main_guide.transform_at(bar_offset)
		for k: int in 6:
			var lateral := rng.randf_range(4.0, 7.4) * (1.0 if k % 2 == 0 else -1.0)
			var hang := bar_xform.origin + bar_xform.basis.x * lateral + bar_xform.basis.y * 1.03
			icicle_transforms.append(_icicle_transform(hang, rng.randf_range(0.45, 0.85)))


## Monumental wind-carved natural ice arch: an elliptical sweep with an
## irregular 7-gon cross-section, thick flared feet buried below grade,
## per-face glacial banding (deep blue feet -> pale crown) and snow dusting
## on up-facing crown faces. Faces are emitted double-sided so the gateway
## reads correctly from every camera angle. Local X spans the track.
func _ice_arch_mesh(seed_value: int) -> ArrayMesh:
	var mrng := RandomNumberGenerator.new()
	mrng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 16
	var sides := 7
	var half_span := 13.0
	var rise := 12.0
	var deep := Color(0.2, 0.44, 0.68)
	var pale := Color(0.78, 0.9, 1.0)
	var snow := Color(0.96, 0.98, 1.0)
	var rings: Array[PackedVector3Array] = []
	var ring_dirs: Array[Vector3] = []  # in-plane outward direction per ring
	for s: int in segs + 1:
		var theta := lerpf(-0.1 * PI, 1.1 * PI, float(s) / float(segs))
		var center := Vector3(cos(theta) * half_span, sin(theta) * rise, 0.0)
		var arc := clampf(sin(theta), 0.0, 1.0)
		var thickness := lerpf(3.3, 1.8, arc) * mrng.randf_range(0.92, 1.08)
		var depth := lerpf(2.6, 1.6, arc) * mrng.randf_range(0.92, 1.08)
		var out_dir := Vector3(cos(theta), sin(theta), 0.0)
		var ring: PackedVector3Array = []
		for j: int in sides:
			var phi := TAU * float(j) / float(sides)
			var wobble := mrng.randf_range(0.85, 1.15)
			ring.append(center + out_dir * (cos(phi) * thickness * wobble) + Vector3(0.0, 0.0, sin(phi) * depth * wobble))
		rings.append(ring)
		ring_dirs.append(out_dir)
	for s: int in segs:
		var t_mid := clampf(sin(lerpf(-0.1 * PI, 1.1 * PI, (float(s) + 0.5) / float(segs))), 0.0, 1.0)
		for j: int in sides:
			var k := (j + 1) % sides
			var phi_mid := TAU * (float(j) + 0.5) / float(sides)
			var shade := mrng.randf_range(0.88, 1.04)
			var col := deep.lerp(pale, t_mid)
			col = Color(col.r * shade, col.g * shade, minf(col.b * (shade + 0.03), 1.0))
			var up_amount := clampf(ring_dirs[s].y * cos(phi_mid), 0.0, 1.0)
			col = col.lerp(snow, up_amount * t_mid * 0.85)
			var a := rings[s][j]
			var b := rings[s][k]
			var c := rings[s + 1][k]
			var d := rings[s + 1][j]
			_ctri(st, a, b, c, col)
			_ctri(st, a, c, d, col)
			_ctri(st, a, c, b, col)
			_ctri(st, a, d, c, col)
	st.generate_normals()
	return st.commit()


## Snow-capped rocks (two multimeshes: boulder + cap) and extra crystals
## scattered along the whole route. The old 13-26m band put every one of these
## between 2m and 20m past the deck edge with nothing underneath: they are now
## bedded on the shoulder, which is the only ground off this ribbon.
func _decorate_scatter(density: float, crystal_transforms: Array[Transform3D]) -> void:
	var rock_transforms: Array[Transform3D] = []
	var cap_transforms: Array[Transform3D] = []
	var count := int(38.0 * density)
	for _i: int in count:
		var offset := rng.randf_range(40.0, main_guide.length - 60.0)
		var xform := main_guide.transform_at(offset)
		var margin := rng.randf_range(0.8, 5.0)
		var side := 1.0 if rng.randf() > 0.5 else -1.0
		var lateral := (track_edge_lateral(main_guide, offset, side, 9.0) + margin) * side
		var pos := seat_dressing(xform, lateral, 1.6, 4.5, 0.12)
		if rng.randf() > 0.4:
			var s := rng.randf_range(0.7, 1.8)
			var squash := Vector3(rng.randf_range(0.8, 1.4), rng.randf_range(0.6, 1.0), rng.randf_range(0.8, 1.4)) * s
			var rock_basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(squash)
			# Sphere meshes are centre-origin: half the squashed height plus a
			# bite of bed depth puts the boulder's waist at the surface.
			rock_transforms.append(Transform3D(rock_basis, pos + Vector3.UP * (squash.y * 0.42)))
			cap_transforms.append(Transform3D(rock_basis, pos + Vector3.UP * (squash.y * 0.42 + 0.45 * s)))
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


## Wind-sculpted snowbank drifts hugging the track edges: every bank is
## elongated along the prevailing wind heading (small per-bank jitter, lower
## profile) the way real drifts streamline, instead of round random blobs.
## Occasional larger banks further out for depth. Single multimesh.
func _decorate_snowbanks(density: float) -> void:
	var transforms: Array[Transform3D] = []
	var wind_yaw := deg_to_rad(WIND_YAW_DEG)
	var step := 14.0 / density
	var offset := 24.0
	var side := 1.0
	while offset < main_guide.length - 24.0:
		var xform := main_guide.transform_at(offset)
		var edge := track_edge_lateral(main_guide, offset, side, 9.0)
		var lateral := (edge + rng.randf_range(0.6, 4.0)) * side
		var r := rng.randf_range(1.6, 3.6)
		var bank_basis := Basis(Vector3.UP, wind_yaw + rng.randf_range(-0.25, 0.25)) \
			* Basis.from_scale(Vector3(
				r * rng.randf_range(1.5, 2.3), r * rng.randf_range(0.5, 0.8), r * rng.randf_range(0.7, 0.95)))
		# Low mounds hide their own footprint, so the shoulder reach is generous.
		var bank_xform := Transform3D(bank_basis,
			seat_dressing(xform, lateral, bank_basis.get_scale().y, 5.0, 0.14))
		transforms.append(bank_xform)
		# Trackside banks plough: running wide into one costs real speed.
		add_snow_drift(bank_xform)
		if rng.randf() > 0.6:
			var far_r := rng.randf_range(2.5, 5.0)
			var far_basis := Basis(Vector3.UP, wind_yaw + rng.randf_range(-0.35, 0.35)) \
				* Basis.from_scale(Vector3(
					far_r * rng.randf_range(1.4, 2.0), far_r * 0.55, far_r * rng.randf_range(0.7, 0.9)))
			var far_lateral := lateral + rng.randf_range(1.5, 5.0) * side
			transforms.append(Transform3D(far_basis,
				seat_dressing(xform, far_lateral, far_basis.get_scale().y, 6.5, 0.15)))
		side = -side
		offset += step
	# Drifts piled AGAINST the track walls: low, long tails of blown snow
	# hugging the wall base on spans whose authored width is constant (so the
	# lateral clears the racing floor exactly). Elongated along the track —
	# wind rakes snow down the wall line, not across it. Same multimesh.
	var cave_start := _offset_near(Vector3(8, 49, -460))
	var cave_end := _offset_near(Vector3(0, 52.5, -565))
	var tunnel := _offset_near(Vector3(0, 50.3, -620))
	var wall_runs: Array = [
		[6.0, 52.0, 9.9],            # start plateau, width 18
		[cave_start + 4.0, cave_end - 4.0, 6.8],   # cave slalom, width 12
		[tunnel - 24.0, tunnel + 18.0, 6.3],       # low tunnel, width 11
		[_offset_near(Vector3(-10, 33, -1220)) - 8.0,
			_offset_near(Vector3(-8, 4, -1360)), 9.9],  # final downhill, width 18
	]
	for run: Array in wall_runs:
		var run_offset := float(run[0])
		var run_side := 1.0
		while run_offset < float(run[1]):
			var run_xform := main_guide.transform_at(run_offset)
			var run_lateral := float(run[2]) * run_side + rng.randf_range(-0.2, 0.3)
			var drift_basis := Basis(Vector3.UP,
				main_guide.yaw_at(run_offset) + rng.randf_range(-0.1, 0.1)) \
				* Basis.from_scale(Vector3(rng.randf_range(0.8, 1.3),
					rng.randf_range(0.35, 0.65), rng.randf_range(2.6, 4.8)))
			var drift_xform := Transform3D(drift_basis,
				seat_dressing(run_xform, run_lateral, drift_basis.get_scale().y, 3.0, 0.15))
			transforms.append(drift_xform)
			add_snow_drift(drift_xform)
			run_side = -run_side
			run_offset += rng.randf_range(7.0, 11.0) / maxf(density, 0.5)
	_add_multimesh(VisualLibrary.snow_drift_mesh(), transforms,
		VisualLibrary.rock_material(Color(1.0, 1.0, 1.0)), "Snowbanks")


## Sastrugi: strips of parallel wind-carved snow ridges beside the track, all
## aligned to the prevailing wind so the ground between props reads
## wind-worked. One multimesh; strip count scales with quality density.
func _decorate_sastrugi(density: float) -> void:
	var transforms: Array[Transform3D] = []
	var wind_yaw := deg_to_rad(WIND_YAW_DEG)
	var strip_count := maxi(int(10.0 * density), 4)
	for _i: int in strip_count:
		var strip_offset := rng.randf_range(50.0, main_guide.length - 80.0)
		var side := 1.0 if rng.randf() > 0.5 else -1.0
		# Strips start at the deck edge and march outward across the shoulder
		# (0.9m apart rather than 1.7m, so a 7-ridge strip still lands on ground
		# instead of trailing 10m into open air).
		var base_lateral := (track_edge_lateral(main_guide, strip_offset, side, 9.0)
			+ rng.randf_range(0.4, 1.6)) * side
		var ridges := rng.randi_range(4, 7)
		for k: int in ridges:
			var ridge_offset := strip_offset + rng.randf_range(-4.0, 4.0)
			var ridge_lateral := base_lateral + float(k) * 0.9 * side + rng.randf_range(-0.5, 0.5)
			var ridge_basis := Basis(Vector3.UP, wind_yaw + rng.randf_range(-0.12, 0.12)) \
				* Basis.from_scale(Vector3(
					rng.randf_range(2.6, 5.5), rng.randf_range(0.22, 0.42), rng.randf_range(0.55, 0.95)))
			transforms.append(Transform3D(ridge_basis,
				seat_dressing(main_guide.transform_at(ridge_offset), ridge_lateral,
					ridge_basis.get_scale().y, 5.0, 0.15)))
	_add_multimesh(_sastrugi_mesh(), transforms,
		VisualLibrary.rock_material(Color(1.0, 1.0, 1.0)), "Sastrugi")


## Unit sastrugi ridge: a wind-carved snow blade along X with the real
## asymmetric profile — long gentle windward slope (+Z), steep sculpted lee
## face (-Z). Vertex colors bake warm sunlit windward vs cool shadowed lee.
func _sastrugi_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var crest: Array[Vector3] = [
		Vector3(-0.5, 0.02, 0.0), Vector3(-0.16, 0.8, -0.05),
		Vector3(0.2, 1.0, 0.04), Vector3(0.5, 0.06, 0.0),
	]
	var windward: Array[Vector3] = [
		Vector3(-0.44, 0.0, 0.3), Vector3(-0.1, 0.0, 0.52),
		Vector3(0.24, 0.0, 0.48), Vector3(0.48, 0.0, 0.22),
	]
	var lee: Array[Vector3] = [
		Vector3(-0.44, 0.0, -0.16), Vector3(-0.12, 0.0, -0.3),
		Vector3(0.22, 0.0, -0.26), Vector3(0.48, 0.0, -0.12),
	]
	var warm := Color(1.0, 0.99, 0.96)
	var cool := Color(0.78, 0.85, 0.97)
	for i: int in 3:
		_cquad(st, windward[i], windward[i + 1], crest[i + 1], crest[i], warm)
		_cquad(st, lee[i + 1], lee[i], crest[i], crest[i + 1], cool)
	st.generate_normals()
	return st.commit()


## Wooden staging walkways flanking the start plateau plus the research
## walkway along the safe loop. Plank + post multimeshes.
func _decorate_walkways() -> void:
	var plank_transforms: Array[Transform3D] = []
	var post_transforms: Array[Transform3D] = []
	# Boardwalk decks ride 0.5m over whatever surface their posts stand in, so
	# both follow the shoulder instead of a fixed height off the centreline.
	var offset := 4.0
	while offset < 52.0:
		var xform := main_guide.transform_at(offset)
		for side: float in [-1.0, 1.0]:
			var lateral := (track_edge_lateral(main_guide, offset, side, 9.0) + 1.8) * side
			var ground := seat_dressing(xform, lateral, 1.5, 4.0, 0.0)
			plank_transforms.append(Transform3D(xform.basis, ground + Vector3.UP * 0.5))
			if int(offset) % 12 < 6:
				post_transforms.append(Transform3D(xform.basis, ground + Vector3.DOWN * 0.2))
		offset += 6.0
	var walkway_start := _offset_near(Vector3(22, 48, -690))
	var walkway_offset := walkway_start
	while walkway_offset < walkway_start + 120.0:
		var xform2 := main_guide.transform_at(walkway_offset)
		var lateral2 := track_edge_lateral(main_guide, walkway_offset, 1.0, 8.5) + 1.4
		var ground2 := seat_dressing(xform2, lateral2, 1.5, 4.0, 0.0)
		plank_transforms.append(Transform3D(xform2.basis, ground2 + Vector3.UP * 0.6))
		if rng.randf() > 0.5:
			post_transforms.append(Transform3D(xform2.basis, ground2 + Vector3.DOWN * 0.15))
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
## cracking-ice shortcut from the safe loop. Start/finish crowds are dense
## (two loose depth rows) so the race bookends feel like a staged event.
func _decorate_spectators(density: float) -> void:
	var start_count := maxi(int(16.0 * density), 6)
	for i: int in start_count:
		var start_arc := rng.randf_range(10.0, 90.0)
		var near_start := main_guide.transform_at(start_arc)
		var start_side := 1.0 if i % 2 == 0 else -1.0
		var lateral := (track_edge_lateral(main_guide, start_arc, start_side, 9.0)
			+ rng.randf_range(0.7, 5.0)) * start_side
		TrackBuilder.add_spectator(self, seat_dressing(near_start, lateral, 1.6, GROUND_SHOULDER, 0.05),
			near_start.origin, rng)
	var finish_count := maxi(int(14.0 * density), 6)
	for i: int in finish_count:
		var finish_arc := finish_offset - rng.randf_range(5.0, 70.0)
		var near_finish := main_guide.transform_at(finish_arc)
		var finish_side := 1.0 if i % 2 == 0 else -1.0
		var lateral := (track_edge_lateral(main_guide, finish_arc, finish_side, 9.0)
			+ rng.randf_range(0.7, 5.0)) * finish_side
		TrackBuilder.add_spectator(self, seat_dressing(near_finish, lateral, 1.6, GROUND_SHOULDER, 0.05),
			near_finish.origin, rng)
	var overlook := _offset_near(Vector3(38, 46, -740))
	var overlook_count := maxi(int(7.0 * density), 3)
	for _i: int in overlook_count:
		var overlook_arc := overlook + rng.randf_range(-25.0, 25.0)
		var xform := main_guide.transform_at(overlook_arc)
		var overlook_lateral := -(track_edge_lateral(main_guide, overlook_arc, -1.0, 8.0)
			+ rng.randf_range(0.8, 3.8))
		TrackBuilder.add_spectator(self, seat_dressing(xform, overlook_lateral, 1.6, GROUND_SHOULDER, 0.05),
			xform.origin, rng)


## --- Cliffs, crevasse cracks, fog, glint ------------------------------------

## Towering striated ice cliff walls flanking the cave approach, the deep-snow
## climb, and the final downhill. Three cached mesh variants instanced through
## MultiMesh; vertex colors bake the striation, blue ice base band, and snow
## rim, so the whole feature costs three draw calls.
func _decorate_cliffs(density: float) -> void:
	var buckets: Array = [[], [], []]
	var step := 16.0 / maxf(density, 0.5)
	var cave_start := _offset_near(Vector3(8, 49, -460))
	_add_cliff_run(buckets, cave_start - 130.0, cave_start - 12.0, -1.0, 17.0, step)
	_add_cliff_run(buckets, cave_start - 100.0, cave_start - 24.0, 1.0, 20.0, step)
	var climb := _offset_near(Vector3(8, 41, -1120))
	_add_cliff_run(buckets, climb - 55.0, climb + 30.0, 1.0, 15.0, step)
	var downhill := _offset_near(Vector3(-16, 18, -1290))
	_add_cliff_run(buckets, downhill - 80.0, downhill + 55.0, -1.0, 19.0, step)
	_add_cliff_run(buckets, downhill - 40.0, downhill + 90.0, 1.0, 16.0, step)
	var cliff_mat := VisualLibrary.rock_material(Color(1.0, 1.0, 1.0)).duplicate() as StandardMaterial3D
	cliff_mat.roughness = 0.45
	for v: int in 3:
		var typed: Array[Transform3D] = []
		for t: Transform3D in buckets[v] as Array:
			typed.append(t)
		_add_multimesh(_cliff_mesh(7000 + v), typed, cliff_mat, "IceCliffs_%d" % v)


## Chains cliff slabs along the guide so runs follow track curvature instead
## of clipping across it. Each slab faces the track from its side.
##
## Slabs are FOOTED, not floated: the crest stays where it was authored and the
## base is stretched down toward the frozen lake instead of stopping 3.5m under
## the deck with open sky beneath it. Growth is capped at CLIFF_MAX_STRETCH so
## the baked striation bands never smear into ribbons on the high stretches —
## where the cap bites, the foot still ends tens of metres below the deck and
## stays behind the track-edge sight line.
const CLIFF_MAX_STRETCH: float = 3.0


func _add_cliff_run(buckets: Array, start_offset: float, end_offset: float, side: float, base_height: float, step: float) -> void:
	var sheet_y := ground_plane_y()
	var offset := start_offset
	while offset < end_offset:
		var xform := main_guide.transform_at(offset)
		var lateral := (18.5 + rng.randf_range(0.0, 3.5)) * side
		var pos := xform.origin + xform.basis.x * lateral + Vector3.DOWN * 3.5
		var toward := -xform.basis.x * side
		var yaw := atan2(toward.x, toward.z)
		# Draws stay in their original order (jitter, width, height, depth,
		# bucket); only what is done with the height changed.
		var yaw_jitter := rng.randf_range(-0.08, 0.08)
		var slab_width := rng.randf_range(19.0, 25.0)
		var authored_height := base_height * rng.randf_range(0.85, 1.3)
		var slab_depth := rng.randf_range(4.5, 7.0)
		var crest_y := pos.y + authored_height
		var footed_height := clampf(crest_y - (sheet_y - 1.5),
			authored_height, authored_height * CLIFF_MAX_STRETCH)
		var cliff_basis := Basis(Vector3.UP, yaw + yaw_jitter) \
			* Basis.from_scale(Vector3(slab_width, footed_height, slab_depth))
		(buckets[rng.randi_range(0, 2)] as Array).append(
			Transform3D(cliff_basis, Vector3(pos.x, crest_y - footed_height, pos.z)))
		offset += step


## Unit-scale striated ice cliff slab: x -0.5..0.5, y 0..~1, front toward +Z.
## Column faces carry vertical striation bands (bright/dark streaks), a deep
## blue ice band at the base, snow along the top rim; recessed return faces
## between columns are crevice-dark and double-sided. Deterministic per seed.
func _cliff_mesh(seed_value: int) -> ArrayMesh:
	var mrng := RandomNumberGenerator.new()
	mrng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 9
	var wall := Color(0.5, 0.68, 0.88)
	var ice_deep := Color(0.16, 0.36, 0.6)
	var snow := Color(0.94, 0.97, 1.0)
	var prev_z := 0.0
	var prev_top := 0.0
	for i: int in cols:
		var x0 := -0.5 + float(i) / float(cols)
		var x1 := -0.5 + float(i + 1) / float(cols)
		var z := mrng.randf_range(0.0, 0.16)
		var top := mrng.randf_range(0.8, 1.0)
		var streak := mrng.randf_range(0.55, 1.12)
		var face := Color(wall.r * streak, wall.g * (0.3 + 0.7 * streak), wall.b * (0.55 + 0.45 * streak))
		var y_ice := mrng.randf_range(0.14, 0.22)
		var y_snow := top - mrng.randf_range(0.1, 0.18)
		# Front striation bands: blue ice base -> streaked wall -> snow rim.
		_cquad(st, Vector3(x0, 0.0, z), Vector3(x1, 0.0, z), Vector3(x1, y_ice, z), Vector3(x0, y_ice, z), ice_deep)
		_cquad(st, Vector3(x0, y_ice, z), Vector3(x1, y_ice, z), Vector3(x1, y_snow, z), Vector3(x0, y_snow, z), face)
		_cquad(st, Vector3(x0, y_snow, z), Vector3(x1, y_snow, z), Vector3(x1, top, z), Vector3(x0, top, z), face.lerp(snow, 0.85))
		# Snow-capped shelf running back from the rim.
		_cquad(st, Vector3(x0, top, z), Vector3(x1, top, z), Vector3(x1, top, z - 0.4), Vector3(x0, top, z - 0.4), snow)
		if i > 0:
			var crevice := Color(face.r * 0.4, face.g * 0.45, face.b * 0.55)
			var hi := maxf(top, prev_top)
			_cquad(st, Vector3(x0, 0.0, prev_z), Vector3(x0, 0.0, z), Vector3(x0, hi, z), Vector3(x0, hi, prev_z), crevice)
			_cquad(st, Vector3(x0, 0.0, z), Vector3(x0, 0.0, prev_z), Vector3(x0, hi, prev_z), Vector3(x0, hi, z), crevice)
		prev_z = z
		prev_top = top
	st.generate_normals()
	return st.commit()


## Frozen waterfall wall: a broad columnar icefall frozen mid-pour down the
## sunlit right flank of the opening dip — five overlapping slabs of one
## seeded cascade mesh chained along the guide so the wall follows the
## track's curvature (kept clear of the cliff runs at the cave approach and
## final downhill). One MultiMesh draw call, one cached glossy rock material
## (vertex colors carry the glacial banding); 23m+ off the racing line,
## shadows off, distance-culled on the low/medium presets.
func _decorate_icefall() -> void:
	var wall_start := _offset_near(Vector3(4, 54, -90)) + 6.0
	var sheet_y := ground_plane_y()
	var transforms: Array[Transform3D] = []
	var offset := wall_start
	for _i: int in 5:
		var xform := main_guide.transform_at(offset)
		var lateral := 23.0 + rng.randf_range(0.0, 3.0)
		var pos := xform.origin + xform.basis.x * lateral + Vector3.DOWN * 5.0
		var toward := -xform.basis.x
		var yaw := atan2(toward.x, toward.z)
		var yaw_jitter := rng.randf_range(-0.06, 0.06)
		var fall_width := rng.randf_range(17.0, 22.0)
		var authored_height := rng.randf_range(15.0, 20.0)
		var fall_depth := rng.randf_range(4.0, 6.0)
		# Same treatment as the cliff runs: keep the crown lip where it was
		# authored and pour the cascade down to the lake rather than ending it
		# in mid-air 5m under the deck (capped so the melt-columns keep their
		# proportions).
		var crest_y := pos.y + authored_height
		var footed_height := clampf(crest_y - (sheet_y - 1.5),
			authored_height, authored_height * CLIFF_MAX_STRETCH)
		var fall_basis := Basis(Vector3.UP, yaw + yaw_jitter) \
			* Basis.from_scale(Vector3(fall_width, footed_height, fall_depth))
		transforms.append(Transform3D(fall_basis, Vector3(pos.x, crest_y - footed_height, pos.z)))
		offset += 19.0
	_add_multimesh(_icefall_mesh(6161), transforms,
		VisualLibrary.rock_material(Color(1.0, 1.0, 1.0), 0.3), "FrozenFalls", false, 480.0)


## Unit frozen-waterfall slab: x -0.5..0.5, y 0..1, cascade face toward +Z.
## Vertical melt-columns with per-column width/depth jitter, deep glacial
## teal in the recesses between columns, pale aqua flow streaks down the
## column fronts, a frost-white crown lip where the cascade pours over the
## edge, and a hanging icicle tip below each column base. Deterministic per
## seed; recess return faces are double-sided so oblique views never see
## through the wall.
func _icefall_mesh(seed_value: int) -> ArrayMesh:
	var mrng := RandomNumberGenerator.new()
	mrng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 10
	var crown := Color(0.94, 0.97, 1.0)
	var flow_hi := Color(0.66, 0.84, 0.97)
	var flow_lo := Color(0.34, 0.6, 0.86)
	var recess := Color(0.1, 0.28, 0.5)
	var prev_z := 0.0
	var prev_lip := 0.0
	for i: int in cols:
		var x0 := -0.5 + float(i) / float(cols)
		var x1 := -0.5 + float(i + 1) / float(cols)
		var z := mrng.randf_range(0.03, 0.14)
		var lip := mrng.randf_range(0.86, 0.93)
		var tip_y := mrng.randf_range(0.02, 0.12)
		var streak := mrng.randf_range(0.8, 1.1)
		var hi := Color(flow_hi.r * streak, flow_hi.g * (0.85 + 0.15 * streak), flow_hi.b)
		var lo := Color(flow_lo.r * streak, flow_lo.g * (0.85 + 0.15 * streak), flow_lo.b)
		var mid_y := lerpf(tip_y, lip, 0.45)
		# Column front: deep pour base -> pale upper flow -> frost crown lip.
		_cquad(st, Vector3(x0, tip_y, z), Vector3(x1, tip_y, z), Vector3(x1, mid_y, z), Vector3(x0, mid_y, z), lo)
		_cquad(st, Vector3(x0, mid_y, z), Vector3(x1, mid_y, z), Vector3(x1, lip, z), Vector3(x0, lip, z), hi)
		_cquad(st, Vector3(x0, lip, z), Vector3(x1, lip, z), Vector3(x1, 1.0, z - 0.1), Vector3(x0, 1.0, z - 0.1), crown)
		# Icicle tip hanging under the column base (both windings).
		var drop := Vector3((x0 + x1) * 0.5 + mrng.randf_range(-0.02, 0.02),
			tip_y - mrng.randf_range(0.05, 0.14), z * 0.5)
		_ctri(st, Vector3(x0, tip_y, z), Vector3(x1, tip_y, z), drop, lo)
		_ctri(st, Vector3(x1, tip_y, z), Vector3(x0, tip_y, z), drop, lo)
		if i > 0:
			var rec := recess * mrng.randf_range(0.8, 1.05)
			rec.a = 1.0
			var hi_y := maxf(lip, prev_lip)
			_cquad(st, Vector3(x0, 0.0, prev_z), Vector3(x0, 0.0, z), Vector3(x0, hi_y, z), Vector3(x0, hi_y, prev_z), rec)
			_cquad(st, Vector3(x0, 0.0, z), Vector3(x0, 0.0, prev_z), Vector3(x0, hi_y, prev_z), Vector3(x0, hi_y, z), rec)
		prev_z = z
		prev_lip = lip
	st.generate_normals()
	return st.commit()


## Occasional distant birds: snow-petrel flocks wheeling high over the frozen
## lake — thin dark billboard slivers on slow-circling pivots (one looping
## tween per flock, zero per-frame script cost). UITheme.reduced_motion()
## pins the flocks static; flock count scales with display/quality_preset.
## Anchors sit 90-150m off the racing line; shadows off on every quad.
func _decorate_birds() -> void:
	var quality := String(SettingsManager.get_setting("display", "quality_preset"))
	var flock_count := 3
	if quality == "medium":
		flock_count = 2
	elif quality == "low":
		flock_count = 1
	var bird_mesh := QuadMesh.new()
	bird_mesh.size = Vector2(1.9, 0.42)
	var bird_mat := VisualLibrary.billboard_puff_material(Color(0.13, 0.15, 0.2, 0.92), 32, 1.0)
	var anchors: Array[Vector3] = [
		Vector3(-120.0, 58.0, -560.0),
		Vector3(150.0, 50.0, -820.0),
		Vector3(-90.0, 46.0, -1120.0),
	]
	for f: int in flock_count:
		var pivot := Node3D.new()
		pivot.name = "BirdFlock_%d" % f
		# Genuinely sky dressing, so it must never sit at deck height where a
		# dark sliver 100m off the line reads as a floating rock: hold each
		# flock at least 30m clear of the nearest stretch of track.
		var anchor := anchors[f]
		var near := main_guide.position_at(float(main_guide.nearest(anchor, -1)["offset"]))
		pivot.position = Vector3(anchor.x, maxf(anchor.y, near.y + 30.0), anchor.z)
		add_child(pivot)
		for _b: int in 4:
			var bird := MeshInstance3D.new()
			bird.mesh = bird_mesh
			bird.material_override = bird_mat
			bird.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var ang := rng.randf() * TAU
			var rad := rng.randf_range(7.0, 15.0)
			bird.position = Vector3(cos(ang) * rad, rng.randf_range(-2.5, 2.5), sin(ang) * rad)
			pivot.add_child(bird)
		if not UITheme.reduced_motion():
			var tw := pivot.create_tween()
			tw.set_loops()
			var dir := 1.0 if f % 2 == 0 else -1.0
			tw.tween_property(pivot, "rotation:y", TAU * dir, rng.randf_range(26.0, 40.0)).as_relative()


## Scattered ice boulders: calved glacial blocks wearing the full smooth-ice
## track shader (crack veins, deep tint, sun streak — the shader skips its
## frost border on non-track meshes via the UV2.y gate), tumbled at random
## tilts just off both edges with occasional satellite shards. One shared
## seeded berg silhouette -> one MultiMesh draw call; shadows stay on the big
## course lights only (these cast none).
func _decorate_boulders(density: float) -> void:
	var transforms: Array[Transform3D] = []
	var count := int(22.0 * density)
	for _i: int in count:
		var offset := rng.randf_range(60.0, main_guide.length - 70.0)
		var xform := main_guide.transform_at(offset)
		var side := 1.0 if rng.randf() > 0.5 else -1.0
		var lateral := (track_edge_lateral(main_guide, offset, side, 9.0)
			+ rng.randf_range(0.8, 4.5)) * side
		var sink := rng.randf_range(0.1, 0.4)
		var s := rng.randf_range(0.9, 2.6)
		var boulder_basis := Basis.from_euler(Vector3(
			rng.randf_range(-0.35, 0.35), rng.randf() * TAU, rng.randf_range(-0.35, 0.35))) \
			* Basis.from_scale(Vector3(
				s * rng.randf_range(0.85, 1.3), s * rng.randf_range(0.5, 0.85), s * rng.randf_range(0.85, 1.3)))
		var pos := seat_dressing(xform, lateral, boulder_basis.get_scale().y, 4.5, 0.12) \
			+ Vector3.DOWN * sink
		transforms.append(Transform3D(boulder_basis, pos))
		# Calving debris: a smaller shard shed beside ~40% of blocks.
		if rng.randf() > 0.6:
			var shard_s := s * rng.randf_range(0.3, 0.5)
			var shard_basis := Basis.from_euler(Vector3(
				rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.5, 0.5))) \
				* Basis.from_scale(Vector3(shard_s, shard_s * 0.7, shard_s))
			var shard_lateral := lateral + rng.randf_range(1.0, 2.4) * side
			transforms.append(Transform3D(shard_basis,
				seat_dressing(xform, shard_lateral, shard_s * 0.7, 5.0, 0.12) + Vector3.DOWN * 0.15))
	_add_multimesh(VisualLibrary.berg_mesh(11), transforms,
		TrackBuilder.surface_material(SurfacesDB.Surface.ICE_SMOOTH), "IceBoulders", false)


## Blue ice-cave glints: cold light caught deep in the cave walls — soft
## additive billboards clustered through the gateway, the slalom arches and
## the low tunnel at varying heights, the way real blue ice fires point
## highlights as the view angle sweeps past. Alpha stays under the glow
## threshold: cold pinpricks, not a lightshow. One MultiMesh, one draw call.
func _decorate_cave_glints(density: float) -> void:
	var cave_start := _offset_near(Vector3(8, 49, -460))
	var tunnel_offset := _offset_near(Vector3(0, 50.3, -620))
	var transforms: Array[Transform3D] = []
	var offset := cave_start - 10.0
	while offset < tunnel_offset + 26.0:
		var xform := main_guide.transform_at(offset)
		for side_sign: float in [-1.0, 1.0]:
			if rng.randf() < 0.3:
				continue
			var s := rng.randf_range(0.45, 1.3)
			var pos := xform.origin + xform.basis.x * (rng.randf_range(6.4, 9.6) * side_sign) \
				+ Vector3.UP * rng.randf_range(0.5, 5.5)
			transforms.append(Transform3D(Basis.from_scale(Vector3(s, s, s)), pos))
		offset += 6.5 / maxf(density, 0.5)
	var glint_mat := StandardMaterial3D.new()
	glint_mat.albedo_color = Color(0.45, 0.75, 1.0, 0.5)
	glint_mat.albedo_texture = VisualLibrary.soft_radial_texture(32, 0.9)
	glint_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glint_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glint_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glint_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glint_mat.billboard_keep_scale = true
	glint_mat.disable_receive_shadows = true
	var glint_quad := QuadMesh.new()
	glint_quad.size = Vector2(1.0, 1.0)
	_add_multimesh(glint_quad, transforms, glint_mat, "CaveGlints", false)


## Crevasse cracks flush with the ice near the cracking-ice shortcut: dark
## jagged strips with a cold blue emission tint (below the bloom threshold —
## a glow tint, not a lightshow), telling the thin-ice story before and after
## the gap.
func _decorate_crevasse_cracks() -> void:
	if branches.is_empty():
		return
	var shortcut_guide: PathGuide = branches[0]["guide"]
	var entry := float(branches[0]["entry"])
	var transforms: Array[Transform3D] = []
	# Warning cracks on the main line just before the branch peels off.
	for i: int in 4:
		transforms.append(_crack_transform(main_guide, entry - 34.0 + float(i) * 9.0, rng.randf_range(-3.0, 3.0)))
	# Branch ice before and after the crevasse gap.
	var gap_start := float(shortcut_guide.nearest(Vector3(-4, 47, -724), -1)["offset"]) - 10.0
	var gap_end := float(shortcut_guide.nearest(Vector3(-4, 45, -790), -1)["offset"]) + 10.0
	var offset := 10.0
	while offset < gap_start - 4.0:
		transforms.append(_crack_transform(shortcut_guide, offset, rng.randf_range(-2.2, 2.2)))
		offset += 8.0
	offset = gap_end + 4.0
	while offset < shortcut_guide.length - 8.0:
		transforms.append(_crack_transform(shortcut_guide, offset, rng.randf_range(-2.2, 2.2)))
		offset += 9.0
	var crack_mat := StandardMaterial3D.new()
	crack_mat.vertex_color_use_as_albedo = true
	crack_mat.albedo_color = Color(1.0, 1.0, 1.0)
	crack_mat.roughness = 0.35
	crack_mat.emission_enabled = true
	crack_mat.emission = Color(0.1, 0.32, 0.75)
	crack_mat.emission_energy_multiplier = 0.4
	_add_multimesh(_crack_mesh(9090), transforms, crack_mat, "CrevasseCracks")


func _crack_transform(guide: PathGuide, offset: float, lateral: float) -> Transform3D:
	var pos := guide.point_at(offset, lateral, 0.04)
	var crack_basis := Basis(Vector3.UP, guide.yaw_at(offset) + rng.randf_range(-0.5, 0.5)) \
		* Basis.from_scale(Vector3(rng.randf_range(1.6, 2.8), 1.0, rng.randf_range(7.0, 13.0)))
	return Transform3D(crack_basis, pos)


## Unit jagged crack strip lying in the XZ plane: runs along Z (-0.5..0.5),
## tapered ends, zigzag midline. Vertex colors: near-black navy core with
## lighter fractured-blue segments.
func _crack_mesh(seed_value: int) -> ArrayMesh:
	var mrng := RandomNumberGenerator.new()
	mrng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 7
	var core := Color(0.02, 0.07, 0.18)
	var rim := Color(0.12, 0.3, 0.55)
	var mid_x: Array[float] = []
	var half_w: Array[float] = []
	for i: int in segs + 1:
		var t := float(i) / float(segs)
		mid_x.append(mrng.randf_range(-0.07, 0.07) if i > 0 and i < segs else 0.0)
		half_w.append(0.004 + sin(t * PI) * mrng.randf_range(0.028, 0.05))
	for i: int in segs:
		var z0 := -0.5 + float(i) / float(segs)
		var z1 := -0.5 + float(i + 1) / float(segs)
		var col := core.lerp(rim, mrng.randf_range(0.0, 0.45))
		_cquad(st,
			Vector3(mid_x[i + 1] - half_w[i + 1], 0.0, z1),
			Vector3(mid_x[i + 1] + half_w[i + 1], 0.0, z1),
			Vector3(mid_x[i] + half_w[i], 0.0, z0),
			Vector3(mid_x[i] - half_w[i], 0.0, z0),
			col)
	st.generate_normals()
	return st.commit()


## Cracked-ice patches across the frozen lake sheet the course overlooks:
## clusters of long crossing fissure lines (reusing the jagged crack strip
## mesh at lake scale) scattered over the inner sheet and the finish vista,
## so the distant ice reads as a real fractured frozen lake instead of a
## flat painted plane. One multimesh, one draw call.
func _decorate_lake_cracks() -> void:
	var transforms: Array[Transform3D] = []
	var center := Vector3(0.0, 0.0, -700.0)
	for _i: int in 12:
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(140.0, 280.0)
		_add_lake_crack_patch(transforms, center + Vector3(sin(angle) * dist, 0.0, cos(angle) * dist))
	for _i: int in 6:
		_add_lake_crack_patch(transforms,
			Vector3(rng.randf_range(-240.0, 180.0), 0.0, rng.randf_range(-1880.0, -1500.0)))
	var lake_crack_mat := StandardMaterial3D.new()
	lake_crack_mat.vertex_color_use_as_albedo = true
	lake_crack_mat.albedo_color = Color(1.0, 1.0, 1.0)
	lake_crack_mat.roughness = 0.3
	_add_multimesh(_crack_mesh(4711), transforms, lake_crack_mat, "LakeCracks")


## One fracture patch: 2-4 fissures sharing a dominant direction (lake ice
## cracks propagate in families), with yaw spread and lateral jitter so they
## cross and branch instead of lying parallel.
func _add_lake_crack_patch(transforms: Array[Transform3D], pos: Vector3) -> void:
	var patch_yaw := rng.randf() * TAU
	for _k: int in rng.randi_range(2, 4):
		var crack_basis := Basis(Vector3.UP, patch_yaw + rng.randf_range(-0.7, 0.7)) \
			* Basis.from_scale(Vector3(rng.randf_range(7.0, 13.0), 1.0, rng.randf_range(40.0, 85.0)))
		var jitter := Vector3(rng.randf_range(-18.0, 18.0), 0.0, rng.randf_range(-18.0, 18.0))
		# Flush with the sheet itself (was a hand-picked -23.5 that left the
		# fissures hovering half a metre over the ice they fracture).
		transforms.append(Transform3D(crack_basis,
			Vector3(pos.x, ground_plane_y() + 0.05, pos.z) + jitter))


## Low drifting ground-fog wisps in the crevasse field, the valley floor and
## the finish straight: soft unshaded billboards on slow sine drift tweens.
## Skipped entirely on low particle quality (density 0.5).
func _decorate_fog(density: float) -> void:
	if density <= 0.5:
		return
	var fog_mat := StandardMaterial3D.new()
	fog_mat.albedo_color = Color(0.88, 0.94, 1.0, 0.16)
	fog_mat.albedo_texture = VisualLibrary.soft_radial_texture(64, 0.8)
	fog_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fog_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fog_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var regions: Array[Vector2] = [
		Vector2(_offset_near(Vector3(22, 48, -690)), _offset_near(Vector3(12, 42.5, -840))),
		Vector2(_offset_near(Vector3(-8, 36.5, -950)), _offset_near(Vector3(-4, 32, -1020))),
		Vector2(finish_offset - 90.0, finish_offset - 5.0),
	]
	var per_region := maxi(int(4.0 * density), 2)
	for region: Vector2 in regions:
		for _i: int in per_region:
			var offset := rng.randf_range(region.x, region.y)
			var lateral := rng.randf_range(7.0, 18.0) * (1.0 if rng.randf() > 0.5 else -1.0)
			var pos := main_guide.point_at(offset, lateral, rng.randf_range(0.6, 2.2))
			var wisp := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(rng.randf_range(13.0, 24.0), rng.randf_range(3.5, 6.5))
			wisp.mesh = quad
			wisp.material_override = fog_mat
			wisp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			wisp.position = pos
			add_child(wisp)
			var drift := Vector3(rng.randf_range(-6.0, 6.0), rng.randf_range(0.2, 0.7), rng.randf_range(-4.0, 4.0))
			var dur := rng.randf_range(7.0, 12.0)
			var tw := wisp.create_tween()
			tw.set_loops()
			tw.tween_property(wisp, "position", pos + drift, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw.tween_property(wisp, "position", pos, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Sun-glint shimmer bands lying flat on the distant ice sheet: stretched
## soft additive quads placed toward the sun and beyond the finish vista.
func _decorate_sun_glint() -> void:
	var glint_mat := StandardMaterial3D.new()
	glint_mat.albedo_color = Color(1.0, 0.96, 0.82, 0.55)
	glint_mat.albedo_texture = VisualLibrary.soft_radial_texture(64, 0.7)
	glint_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glint_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glint_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	# Horizontal direction the sunlight arrives from (build_environment yaw -35).
	var sun_dir := Vector3(-sin(deg_to_rad(35.0)), 0.0, cos(deg_to_rad(35.0)))
	var placements: Array[Vector3] = [
		Vector3(0.0, 0.0, -560.0) + sun_dir * 470.0,
		Vector3(-80.0, 0.0, -1790.0),
	]
	var sheet_y := ground_plane_y()
	for pos: Vector3 in placements:
		var band := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(rng.randf_range(420.0, 520.0), rng.randf_range(55.0, 80.0))
		band.mesh = plane
		band.material_override = glint_mat
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Lying ON the sheet: 0.1m of separation is enough to beat z-fighting
		# without the band reading as a slab hovering over the ice.
		band.position = Vector3(pos.x, sheet_y + 0.1, pos.z)
		band.rotation.y = atan2(sun_dir.x, sun_dir.z)
		add_child(band)


## Quad as two front-facing triangles; corners given as (bottom-left,
## bottom-right, top-right, top-left) from the viewpoint of the visible side.
static func _cquad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_ctri(st, a, d, c, color)
	_ctri(st, a, c, b, color)


## --- Distant mountains ------------------------------------------------------
## Two depth rings of varied low-poly peaks with baked per-face colors:
## streaked rock walls below a per-peak snowline, white caps above. The far
## ring is pre-hazed toward the horizon tint for atmospheric layering.

func _decorate_mountains() -> void:
	# Rooted on the frozen lake plane rather than a hand-copied -24: the two
	# would silently drift apart if the sheet height is ever retuned, leaving a
	# whole skyline hanging above (or sunk into) the ice.
	var center := Vector3(0.0, ground_plane_y(), -700.0)
	for i: int in 10:
		_place_mountain(1000 + i, center, 300.0, 470.0, 130.0, 220.0, 0.08)
	for i: int in 11:
		_place_mountain(2000 + i, center, 560.0, 790.0, 200.0, 330.0, 0.42)
	# Third, near-horizon ring: taller massifs almost dissolved into the sky
	# tint. Three stacked haze bands (0.08 / 0.42 / 0.74) give the receding
	# ridge-behind-ridge layering of real alpine distance.
	for i: int in 9:
		_place_mountain(3000 + i, center, 860.0, 1180.0, 260.0, 430.0, 0.74)


func _place_mountain(seed_value: int, center: Vector3, dist_min: float, dist_max: float, h_min: float, h_max: float, haze: float) -> void:
	var height := rng.randf_range(h_min, h_max)
	# Footprint as a fraction of height. Below ~0.9 the hull reads as a spire:
	# the old 0.55-0.85 band produced the row of identical sharp cones that made
	# the skyline look like placeholder geometry. Real massifs are wider than
	# they are tall, and the wide spread here (some squat, some steep) is what
	# stops neighbouring peaks reading as copies of one mesh.
	var footprint := height * rng.randf_range(0.95, 1.7)
	for _attempt: int in 10:
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(dist_min, dist_max)
		var pos := center + Vector3(sin(angle) * dist, 0.0, cos(angle) * dist)
		# Never plant a peak on top of the racing line: base-ring vertices
		# reach up to ~1.6x footprint (column scale * 2-octave angular noise *
		# jitter), so demand that much horizontal clearance to the nearest
		# main-guide point.
		var res := main_guide.nearest(pos, -1)
		var near_pt := main_guide.position_at(float(res["offset"]))
		var horizontal := Vector2(pos.x - near_pt.x, pos.z - near_pt.z).length()
		if horizontal < footprint * 1.65 + 30.0:
			continue
		var instance := MeshInstance3D.new()
		instance.mesh = _mountain_mesh(seed_value, haze)
		instance.material_override = VisualLibrary.rock_material(Color(1.0, 1.0, 1.0))
		instance.scale = Vector3(footprint, height, footprint)
		instance.rotation.y = rng.randf() * TAU
		# Base ring sits at local y = 0: sink it a little so the open underside
		# is never visible along a grazing sightline across the sheet.
		instance.position = pos + Vector3.DOWN * ground_embed(height, 0.01)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		return


## Unit-scale (about 1m tall) irregular ridged peak, deterministic per seed.
## Twelve-sided with four rings for a smooth, craggy silhouette (blockiness
## is low segment counts). Ring vertices carry 2-octave angular noise plus a
## height-scaled lean drift, so every profile is asymmetric — no perfect
## cones. Per-face colors: dark exposed rock with vertical streak variation,
## a glacial blue ice band and moraine debris at the base, exposed blue ice
## on steep faces, and a dappled snowline scattering into white caps; haze
## lerps toward horizon blue for the far ring.
func _mountain_mesh(seed_value: int, haze: float) -> ArrayMesh:
	var mrng := RandomNumberGenerator.new()
	mrng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Varying the column count changes the silhouette's whole rhythm, so peaks
	# differ in outline and not just in noise.
	var sides := mrng.randi_range(9, 14)
	var ring_heights: Array[float] = [
		0.0,
		mrng.randf_range(0.3, 0.4),
		mrng.randf_range(0.55, 0.65),
		mrng.randf_range(0.76, 0.84),
	]
	var ring_radii: Array[float] = [
		1.0,
		mrng.randf_range(0.64, 0.78),
		mrng.randf_range(0.4, 0.5),
		mrng.randf_range(0.2, 0.28),
	]
	var column_scale: Array[float] = []
	var streaks: Array[float] = []
	for i: int in sides:
		column_scale.append(mrng.randf_range(0.8, 1.18))
		streaks.append(mrng.randf_range(0.7, 1.2))
	# 2-octave angular noise (frequencies 2 and 5, random phases): ridge-and-
	# gully undulation that breaks radial symmetry without spiking the hull.
	var phase_a := mrng.randf() * TAU
	var phase_b := mrng.randf() * TAU
	var amp_a := mrng.randf_range(0.1, 0.17)
	var amp_b := mrng.randf_range(0.05, 0.09)
	# Lean drift: ring centers migrate with altitude so the massif tilts.
	var drift := Vector2(mrng.randf_range(-0.14, 0.14), mrng.randf_range(-0.14, 0.14))
	var rings: Array[PackedVector3Array] = []
	for r: int in ring_heights.size():
		var ring: PackedVector3Array = []
		for i: int in sides:
			var angle := TAU * float(i) / float(sides)
			var noise := 1.0 + amp_a * sin(angle * 2.0 + phase_a) + amp_b * sin(angle * 5.0 + phase_b)
			var radius := ring_radii[r] * column_scale[i] * noise * mrng.randf_range(0.92, 1.08)
			var y := ring_heights[r] + (mrng.randf_range(-0.055, 0.06) if r > 0 else 0.0)
			ring.append(Vector3(
				cos(angle) * radius + drift.x * ring_heights[r], y,
				sin(angle) * radius + drift.y * ring_heights[r]))
		rings.append(ring)
	var apex := Vector3(
		drift.x + mrng.randf_range(-0.08, 0.08),
		mrng.randf_range(0.97, 1.1),
		drift.y + mrng.randf_range(-0.08, 0.08))
	var snowline := mrng.randf_range(0.48, 0.62)
	# Very dark base values on purpose: ACES + strong sky ambient lift vertex
	# colors roughly two stops, so 0.12-0.2 here reads as sunlit alpine rock
	# with real presence instead of washed-out near-white.
	var rock_base := Color(0.13, 0.125, 0.14).lerp(Color(0.2, 0.155, 0.11), mrng.randf())
	for r: int in ring_heights.size() - 1:
		for i: int in sides:
			var j := (i + 1) % sides
			var lo0 := rings[r][i]
			var lo1 := rings[r][j]
			var hi0 := rings[r + 1][i]
			var hi1 := rings[r + 1][j]
			# Steepness 0..1 from radial inset per unit rise: near-vertical
			# columns approach 1 and shed snow into exposed glacial ice.
			var rise := maxf((hi0.y + hi1.y - lo0.y - lo1.y) * 0.5, 0.05)
			var inset := (Vector2(lo0.x, lo0.z).length() + Vector2(lo1.x, lo1.z).length()
				- Vector2(hi0.x, hi0.z).length() - Vector2(hi1.x, hi1.z).length()) * 0.5
			var steep := clampf(1.0 - (inset / rise) * 0.85, 0.0, 1.0)
			var col := _mountain_face_color(
				(lo0.y + lo1.y + hi0.y + hi1.y) * 0.25, snowline, rock_base, streaks[i], haze, steep, mrng)
			_ctri(st, lo0, hi1, hi0, col)
			_ctri(st, lo0, lo1, hi1, col)
	var top := ring_heights.size() - 1
	for i: int in sides:
		var j := (i + 1) % sides
		var col := _mountain_face_color(
			(rings[top][i].y + rings[top][j].y + apex.y) / 3.0, snowline, rock_base, streaks[i], haze, 0.0, mrng)
		_ctri(st, rings[top][i], rings[top][j], apex, col)
	st.generate_normals()
	return st.commit()


## height: face average height on the unit peak. steep 0..1: how vertical the
## face is. mrng drives per-face dappling — deterministic per mountain seed.
func _mountain_face_color(height: float, snowline: float, rock_base: Color, streak: float,
		haze: float, steep: float, mrng: RandomNumberGenerator) -> Color:
	# Blue channel decays slower than red/green so shadowed streaks cool off.
	var rock := Color(rock_base.r * streak, rock_base.g * streak, rock_base.b * (0.6 + 0.4 * streak))
	var snow := Color(0.95, 0.97, 1.0)
	var band := 0.1
	var col: Color
	if height > snowline + 0.05:
		col = snow
	elif height > snowline - band:
		# Dappled snowline: real transitions are patchy scatter, not a ruled
		# line. A face's odds of holding full snow rise through the band;
		# bare faces still pick up a thin random dusting.
		var t := (height - (snowline - band)) / (band + 0.05)
		if mrng.randf() < t * t:
			col = snow
		else:
			col = rock.lerp(snow, 0.12 + 0.3 * t * mrng.randf())
	else:
		col = rock
	# Exposed glacial blue ice where faces are too steep to hold snow cover.
	if height < snowline + 0.06 and steep > 0.5:
		col = col.lerp(Color(0.3, 0.55, 0.8),
			clampf((steep - 0.5) * 1.6 * mrng.randf_range(0.35, 1.0), 0.0, 0.65))
	# Subtle glacial blue ice band where the peak meets the snowfield. Faces
	# carry the average height of their corners (bottom band ~0.15-0.2), so
	# the 0.28 threshold tints the whole base ring, fading with altitude.
	if height < 0.28:
		col = col.lerp(Color(0.22, 0.4, 0.6), (1.0 - height / 0.28) * 0.5)
	# Moraine debris band at the foot: grey-brown rockfall rubble shed off
	# the faces above, strongest right at grade.
	if height < 0.11:
		var debris := Color(0.17, 0.145, 0.12).lerp(Color(0.26, 0.21, 0.155), mrng.randf())
		col = col.lerp(debris, clampf((0.11 - height) / 0.11, 0.0, 1.0) * mrng.randf_range(0.5, 0.85))
	return col.lerp(Color(0.6, 0.77, 0.96), haze)


static func _ctri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	st.set_color(color)
	st.add_vertex(a)
	st.set_color(color)
	st.add_vertex(b)
	st.set_color(color)
	st.add_vertex(c)
