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
		# Aerial perspective, retuned. The old haze was both too thin (0.0012) and
		# too BRIGHT (0.7/0.84/0.98, a hair off the horizon sky itself), with the
		# default 0.5 aerial blend carrying far geometry the rest of the way to
		# the sky colour. Measured off qa_shots/env/base_glacier_34.png that put
		# distant terrain at 0.816 mean luma against a 0.807 sky — no separation
		# at all, which is why the horizon read as one undifferentiated pale mass.
		# Real distance haze on a clear polar day is a deeper, more saturated blue
		# than the sky it sits under, so far forms stay a readable silhouette.
		"fog_color": Color(0.44, 0.6, 0.82),
		"fog_density": 0.0019,
		"fog_horizon_blend": 0.2,
		"fog_aerial": 0.3,
		"fog_sky_affect": 0.08,
		"fog_sun_scatter": 0.1,
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
	# Wildlife FIRST: every pass below checks against where the bears ended up,
	# so no boulder, drift, route flag or spectator is ever placed inside one.
	_decorate_wildlife(density)
	_decorate_flags()
	_decorate_cave(crystal_transforms, icicle_transforms)
	_decorate_scatter(density, crystal_transforms)
	_decorate_snowbanks(density)
	_decorate_sastrugi(density)
	_decorate_walkways()
	_decorate_spectators(density)
	_decorate_mountains()
	_decorate_cliffs(density)
	if OS.get_environment("DBG_NO_ICEFALL") == "":
		_decorate_icefall()
	_dbg_camera()
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

	# Baked contact shadows, flushed last so every pass above has had its chance
	# to register one. gl_compatibility has no SSAO, and without an occlusion
	# cue a correctly seated rock still reads as hovering over the snow — this
	# was the single most-reported "props do not sit in the world" tell.
	_add_multimesh(VisualLibrary.contact_patch_mesh(), _contact_patches,
		VisualLibrary.contact_shadow_material(), "ContactShadows", false, 240.0)


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


## Soft contact shadows under trackside dressing, collected during decoration
## and flushed as one MultiMesh at the end of _decorate().
var _contact_patches: Array[Transform3D] = []


## BUILD TIME ONLY. Registers a contact shadow on the surface under `pos`.
## `radius` is the prop's ground footprint; the patch is drawn a shade wider,
## because a real ambient-occlusion contact reaches slightly past the silhouette.
func _add_contact_patch(pos: Vector3, radius: float) -> void:
	# Probed rather than taken from the prop's own Y: dressing is seated with a
	# ground_embed sink, so its origin is already a little UNDER the surface and
	# a patch placed there would be invisible.
	var y := ground_height_at(pos)
	if not is_finite(y):
		y = pos.y
	_contact_patches.append(Transform3D(
		Basis.from_scale(Vector3(radius * 2.4, 1.0, radius * 2.4)),
		Vector3(pos.x, y + 0.04, pos.z)))


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
		if not _clear_of_wildlife(base, 2.6):
			side = -side
			offset += 70.0
			continue
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
			if not _clear_of_wildlife(base, 2.6):
				continue
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
	# The arch is a hollow sweep the racer passes THROUGH, so its inner surface
	# has to draw. Two-sided here rather than two windings in the mesh (see
	# _ice_arch_mesh): coplanar duplicates z-fight and shade half the crown black.
	gate_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
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
## on up-facing crown faces. Local X spans the track.
##
## Single-winding on purpose. Every quad used to be emitted TWICE, once per
## winding, which is not "double-sided" — it is two coplanar triangles fighting
## for the depth buffer, one of them facing away from the light. The loser
## shaded unlit, and the arch crown rendered as the torn black-and-white patch
## visible in qa_shots/env/diag_noskyline_34.png. Both sides are still drawn:
## the gateway material carries CULL_DISABLED, which is what double-sided
## actually means, and Godot flips the normal on back faces so they light
## correctly.
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
		if not _clear_of_wildlife(pos):
			continue
		if rng.randf() > 0.4:
			var s := rng.randf_range(0.7, 1.8)
			var squash := Vector3(rng.randf_range(0.8, 1.4), rng.randf_range(0.6, 1.0), rng.randf_range(0.8, 1.4)) * s
			var rock_basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(squash)
			# Sphere meshes are centre-origin: half the squashed height plus a
			# bite of bed depth puts the boulder's waist at the surface.
			rock_transforms.append(Transform3D(rock_basis, pos + Vector3.UP * (squash.y * 0.42)))
			cap_transforms.append(Transform3D(rock_basis, pos + Vector3.UP * (squash.y * 0.42 + 0.45 * s)))
			_add_contact_patch(pos, maxf(squash.x, squash.z) * 0.8)
		else:
			var crystal_height := rng.randf_range(2.0, 5.5)
			crystal_transforms.append(_crystal_transform(pos, crystal_height))
			_add_contact_patch(pos, crystal_height * 0.3)
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
	# Terrain shader on the rock bodies: a sphere under one flat albedo is the
	# purest form of the "untextured polygon" problem, and strata + a wall/ledge
	# value split turn the same eight-segment sphere into a layered erratic for
	# no extra geometry.
	_add_multimesh(rock_mesh, rock_transforms, VisualLibrary.shader_variant(
		VisualLibrary.terrain_material(Color(0.45, 0.48, 0.54), 1.0, 0.0, 0.95), {
			"strata_strength": 0.55,
			"strata_scale": 0.6,        # ~1.7 m layers on a 1-3 m boulder
			"face_shade": 0.34,
			"snow_catch": 0.42,
		}), "Rocks")
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
		# A bank that would land on a bear is pushed further out rather than
		# dropped: these ones plough, so the field keeps every one it authored.
		if not _clear_of_wildlife(seat_dressing(xform, lateral, 1.0, 5.0, 0.14), 4.0):
			lateral += 3.4 * side
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
		var start_pos := seat_dressing(near_start, lateral, 1.6, GROUND_SHOULDER, 0.05)
		if _clear_of_wildlife(start_pos, 2.4):
			TrackBuilder.add_spectator(self, start_pos, near_start.origin, rng)
	var finish_count := maxi(int(14.0 * density), 6)
	for i: int in finish_count:
		var finish_arc := finish_offset - rng.randf_range(5.0, 70.0)
		var near_finish := main_guide.transform_at(finish_arc)
		var finish_side := 1.0 if i % 2 == 0 else -1.0
		var lateral := (track_edge_lateral(main_guide, finish_arc, finish_side, 9.0)
			+ rng.randf_range(0.7, 5.0)) * finish_side
		var finish_pos := seat_dressing(near_finish, lateral, 1.6, GROUND_SHOULDER, 0.05)
		if _clear_of_wildlife(finish_pos, 2.4):
			TrackBuilder.add_spectator(self, finish_pos, near_finish.origin, rng)
	var overlook := _offset_near(Vector3(38, 46, -740))
	var overlook_count := maxi(int(7.0 * density), 3)
	for _i: int in overlook_count:
		var overlook_arc := overlook + rng.randf_range(-25.0, 25.0)
		var xform := main_guide.transform_at(overlook_arc)
		var overlook_lateral := -(track_edge_lateral(main_guide, overlook_arc, -1.0, 8.0)
			+ rng.randf_range(0.8, 3.8))
		var overlook_pos := seat_dressing(xform, overlook_lateral, 1.6, GROUND_SHOULDER, 0.05)
		if _clear_of_wildlife(overlook_pos, 2.4):
			TrackBuilder.add_spectator(self, overlook_pos, xform.origin, rng)


## Trackside polar bears: the glacier's resident wildlife, watching the race go
## past from the snow beside it. AMBIENT ONLY — PolarBear carries no collision
## body and no hazard behaviour, so a racer that leaves the track passes
## straight through one.
##
## Placement rules, in the order they matter:
##  * Never on the racing line. Every lateral is measured from the REAL deck
##    edge at that offset (the track runs 22 m wide through the opening hills
##    and 11 m through the tunnel) and then pushed 1.1-1.9 m further out. That
##    band is deliberately tight: further out the shoulder runs out from under a
##    2.5 m animal (a 40 cm drift mound hides standing on thin air, a bear with
##    legs does not), and it would read as a speck from the racing line anyway.
##    Facings stay within ~40 degrees of the track heading for the same reason —
##    a bear turned broadside swings its own length back over the deck.
##  * Never against a cliff or the icefall. Those start at 18.5 m and 23 m
##    lateral respectively, so the outer limit here stays under ~15 m.
##  * Well spaced: five spots spread over the whole route, no two closer than a
##    couple of hundred metres of arc, so a bear is a moment rather than a herd.
##  * Standing on something. This track is a ribbon in the air — TrackBuilder's
##    collidable floor ends exactly at the authored width, and everything
##    outside it is skirt, so a prop bedded at deck height off the edge is
##    literally in mid-air. A 40 cm drift mound gets away with that; a 1.3 m
##    animal with four legs does not. Every bear therefore gets a wide, low
##    snow ledge drifted against the track edge underneath it, whose crown sits
##    at deck height and whose inboard side is buried under the deck. The ledge
##    is visual only — no add_snow_drift, so it ploughs nothing and the bears
##    stay free of any gameplay effect whatsoever.
## Count scales with particle quality (5 / 4 / 3), and every bear is skipped
## headless with the rest of _decorate().
var _wildlife_spots: Array[Vector3] = []


## True when `pos` is far enough from every bear for a scatter prop to be
## placed there without burying one.
func _clear_of_wildlife(pos: Vector3, radius: float = 3.2) -> bool:
	for spot: Vector3 in _wildlife_spots:
		if Vector2(pos.x - spot.x, pos.z - spot.z).length_squared() < radius * radius:
			return false
	return true


## Bears are FOUND, not authored.
##
## Five hand-picked spots were tried first and the course rejected every one
## of them: the ribbon is a floor of exactly the authored width in open air, so
## a spot chosen by eye off the edge usually has nothing under it, and the
## spans that do have ground beside them are often the ones carrying an edge
## wall -- which is translucent azure, and turns the animal behind it into a
## blue silhouette. Rather than prop the bears up on invented ledges and accept
## the tinting, the course is swept for sites that already satisfy both
## conditions, and only those get a bear.
const WILDLIFE_MAX: int = 4
const WILDLIFE_SEARCH_STEP: float = 11.0
const WILDLIFE_MIN_SPACING: float = 150.0
const WILDLIFE_POSES: Array[int] = [
	PolarBear.Pose.STANDING, PolarBear.Pose.SITTING,
	PolarBear.Pose.LYING, PolarBear.Pose.STANDING,
]


func _decorate_wildlife(density: float) -> void:
	var spots: Array = []
	var last_offset := -WILDLIFE_MIN_SPACING
	var search := 60.0
	while search < main_guide.length - 60.0 and spots.size() < WILDLIFE_MAX:
		if search - last_offset < WILDLIFE_MIN_SPACING:
			search += WILDLIFE_SEARCH_STEP
			continue
		for side: float in [1.0, -1.0]:
			if spots.size() >= WILDLIFE_MAX:
				break
			var probe_xform := main_guide.transform_at(search)
			var probe_lateral := (track_edge_lateral(main_guide, search, side, 9.0) + 1.5) * side
			var probe_seat := seat_dressing(probe_xform, probe_lateral, 1.35, 6.0, 0.06)
			if not _wildlife_site_ok(probe_xform, probe_seat, probe_lateral, side):
				continue
			# Face across the track, so the animal is looking at the race rather
			# than presenting its flank to it.
			var facing := -PI * 0.5 * side + rng.randf_range(-0.5, 0.5)
			spots.append([search, side, WILDLIFE_POSES[spots.size() % WILDLIFE_POSES.size()],
				facing, rng.randf_range(1.25, 1.42)])
			last_offset = search
		search += WILDLIFE_SEARCH_STEP
	# Every candidate is auditioned before it is built, and a bear that fails
	# is simply not placed.
	#
	# The first pass placed all five and propped up the ones with nothing under
	# them on a purpose-built snow ledge. That solved the floating and created
	# two worse problems: from the racing line the ledge read as a white disc
	# parked in mid-air, and on walled spans the bear was being viewed THROUGH
	# the translucent azure edge wall, which tinted it to a flat blue
	# silhouette. A rock can survive being seen through glass; the one animal
	# on the course cannot -- it just reads as broken. So the ground and the
	# sightline are now entry requirements rather than things to compensate
	# for afterwards, and three bears standing in the open beat five behind a
	# window.
	var wanted := clampi(int(round(5.0 * density)), 3, spots.size())
	var placed := 0
	var rejected := 0
	for spot: Array in spots:
		if placed >= wanted:
			break
		var offset := float(spot[0])
		var side := float(spot[1])
		var xform := main_guide.transform_at(offset)
		var lateral := (track_edge_lateral(main_guide, offset, side, 9.0)
			+ rng.randf_range(1.1, 1.9)) * side
		# Height 1.35 m at the withers; a 6% sink beds the paws into the snow.
		# Shoulder reach 6 m so the probe reads the deck surface from out here
		# instead of falling through to the frozen lake.
		var seat := seat_dressing(xform, lateral, 1.35, 6.0, 0.06)
		var yaw := main_guide.yaw_at(offset) + float(spot[3])
		if not _wildlife_site_ok(xform, seat, lateral, side):
			rejected += 1
			continue
		var bear := PolarBear.new()
		bear.name = "PolarBear_%d" % placed
		add_child(bear)
		bear.configure(spot[2] as PolarBear.Pose)
		bear.position = seat
		bear.rotation.y = yaw + rng.randf_range(-0.12, 0.12)
		var s := float(spot[4]) * rng.randf_range(0.97, 1.03)
		bear.scale = Vector3(s, s, s)
		_wildlife_spots.append(bear.position)
		placed += 1
	if BootProfiler.enabled() or placed == 0:
		print("[glacier] wildlife: %d placed, %d sites rejected (no ground or occluded)"
			% [placed, rejected])


## True when a wildlife site has solid ground under the whole animal AND a
## clear view of it from the racing line.
##
## Two independent gates, because they catch different failures. The ground
## probe rejects the ribbon's outer lip, where the collidable floor stops at
## the authored width and a prop bedded at deck height is literally in the air.
## The sightline probe rejects anything with course geometry -- an edge wall,
## most of all -- between the racer and the animal.
func _wildlife_site_ok(xform: Transform3D, seat: Vector3, lateral: float, side: float) -> bool:
	if not ground_probe_ready():
		return true
	# Four paw corners plus the centre. All must find ground close to the seat
	# height: a hit far below means the probe fell past the deck edge.
	for probe: Vector2 in [Vector2.ZERO, Vector2(-1.1, -0.9), Vector2(1.1, -0.9),
			Vector2(-1.1, 0.9), Vector2(1.1, 0.9)]:
		var at := seat + xform.basis.x * probe.x - xform.basis.z * probe.y
		var ground := _raw_ground(at.x, at.z, seat.y + 1.2, 3.6)
		if ground == -INF or absf(ground - seat.y) > 1.0:
			return false
	# Sightline: chest height on the animal, from head height on the racing
	# line. LAYER_WORLD only -- triggers and pickups are not occluders.
	var eye := xform.origin + Vector3.UP * 1.5
	var chest := seat + Vector3.UP * 1.0 - xform.basis.x * (0.5 * side)
	var los := PhysicsRayQueryParameters3D.create(eye, chest, GameConfig.LAYER_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(los).is_empty()


## TEMPORARY QA harness. DBG_CAM="arc,lateral,lift,ahead" pins a camera on the
## racing line so a dressing change can be A/B'd from an identical viewpoint
## instead of from wherever the autopilot happened to be when the shot fired.
func _dbg_camera() -> void:
	var spec := OS.get_environment("DBG_CAM")
	if spec == "":
		return
	var f := spec.split(",")
	if f.size() < 4:
		return
	var arc := float(f[0])
	var xf := main_guide.transform_at(arc)
	var cam := Camera3D.new()
	cam.name = "DbgCam"
	cam.position = xf.origin + xf.basis.x * float(f[1]) + Vector3.UP * float(f[2])
	cam.look_at_from_position(cam.position,
		main_guide.transform_at(arc + float(f[3])).origin + Vector3.UP * float(f[2]) * 0.5)
	cam.far = 4000.0
	add_child(cam)
	var timer := Timer.new()
	timer.wait_time = 0.25
	timer.autostart = true
	timer.timeout.connect(func() -> void: cam.make_current())
	add_child(timer)


## --- Cliffs, crevasse cracks, fog, glint ------------------------------------

## Towering striated ice cliff walls flanking the cave approach, the deep-snow
## climb, and the final downhill. Five runs, ONE swept ribbon mesh each, so the
## whole feature costs five draw calls.
##
## This used to be a MultiMesh of individually-yawed flat slabs chained along
## the guide. No amount of overlap, end-capping or back-skinning ever made that
## read as a cliff: each slab is a separate box with its own crest height and
## its own yaw, so along a curve the run splays into a row of tombstones, the
## silhouette stair-steps at every slab boundary, and the seams between them
## either show sky or show an unlit interior face. A wall is not a set of
## walls — it has to be ONE surface.
func _decorate_cliffs(density: float) -> void:
	# Terrain shader, not a flat StandardMaterial3D: a 40 m wall wearing one
	# albedo and one roughness is exactly the untextured-polygon read. The
	# strata are driven by WORLD Y, so a run that climbs 30 m with the track
	# keeps one consistent band scale down its whole length instead of
	# smearing them.
	var cliff_mat := VisualLibrary.shader_variant(
		VisualLibrary.terrain_material(Color(1.0, 1.0, 1.0), 1.0, 0.35, 0.45), {
			"strata_strength": 0.32,
			"strata_scale": 0.14,       # ~7 m compression layers
			"strata_tint": Color(0.82, 0.86, 0.92),
			"face_shade": 0.26,
			"snow_catch": 0.45,
			"haze_start": 120.0,
			"haze_end": 620.0,
		})
	# Ring spacing along the sweep. Fine enough that the crest serration reads
	# as erosion rather than as a sawtooth; coarse enough that a 130 m run is
	# about thirty rings and a couple of thousand triangles.
	var step := CLIFF_SWEEP_STEP / clampf(density, 0.7, 1.0)
	var cave_start := _offset_near(Vector3(8, 49, -460))
	_add_cliff_run(cave_start - 130.0, cave_start - 12.0, -1.0, 17.0, step, 7001, cliff_mat)
	_add_cliff_run(cave_start - 100.0, cave_start - 24.0, 1.0, 20.0, step, 7002, cliff_mat)
	var climb := _offset_near(Vector3(8, 41, -1120))
	_add_cliff_run(climb - 55.0, climb + 30.0, 1.0, 15.0, step, 7003, cliff_mat)
	var downhill := _offset_near(Vector3(-16, 18, -1290))
	_add_cliff_run(downhill - 80.0, downhill + 55.0, -1.0, 19.0, step, 7004, cliff_mat)
	_add_cliff_run(downhill - 40.0, downhill + 90.0, 1.0, 16.0, step, 7005, cliff_mat)


## Cliff runs are FOOTED, not floated: the crest stays where it is authored and
## the wall falls away toward the frozen lake instead of stopping a few metres
## under the deck with open sky beneath it. Growth is capped at
## CLIFF_MAX_STRETCH x the local crest height so the shader's world-Y striation
## never has to cover an absurd span; where the cap bites, the foot still ends
## tens of metres below the deck, well behind the track-edge sight line.
const CLIFF_MAX_STRETCH: float = 3.0
## Arc metres between sweep rings at full density.
const CLIFF_SWEEP_STEP: float = 4.5
## Points in the closed cross-section (see _cliff_profile).
const CLIFF_RING: int = 11


## One continuous ice wall swept along `main_guide` from `start_offset` to
## `end_offset`, standing off the centreline on `side` (-1 left, +1 right).
##
## The sweep samples the guide every `step` metres and lays a closed 8-point
## cross-section at each sample: an apron toe at the snowline, a face rising
## and receding to a crest lip, a snow roof running back from the crest, and a
## back wall and floor closing the volume. Consecutive cross-sections are
## joined edge for edge, so the surface is continuous by construction — there
## is no seam anywhere for sky or for an interior face to show through, which
## is the entire point of the rebuild.
##
## Everything that varies does so as a function of ARC LENGTH, through smooth
## multi-octave sine sums seeded per run: crest height, lateral standoff, wall
## girth, roof depth and face fluting. That is what keeps it from reading as an
## extrusion. The crest carries one extra per-ring term so its skyline
## serrates at ring resolution while the face below it stays smooth — eroded
## ice, rather than a noisy wall.
##
## Wound outward everywhere and drawn with the terrain shader's cull_back, so
## the volume's inward faces never rasterise: there is no dark interior for a
## racer to see into. Shadow casting stays off — these are 19 m off the racing
## line and up to 50 m tall, and they used to swallow most of the directional
## shadow atlas while self-shadowing into a stippled mess. The shader's
## wall/ledge value split models them far more cleanly.
func _add_cliff_run(start_offset: float, end_offset: float, side: float,
		base_height: float, step: float, seed_value: int, material: Material) -> void:
	var span := end_offset - start_offset
	if span <= step * 2.0:
		return
	var rings := maxi(4, int(ceil(span / step)) + 1)
	var seg := span / float(rings - 1)
	var sheet_y := ground_plane_y()
	# Phase table, so two runs never undulate in step with each other.
	var prng := RandomNumberGenerator.new()
	prng.seed = seed_value
	var ph := PackedFloat32Array()
	for _i: int in 12:
		ph.append(prng.randf() * TAU)

	# Palette carried over unchanged from the slab build, which spent a whole
	# pass getting it right. Deliberately mid-value and only mildly blue: a
	# near-white wall albedo clips to paper under this course's 1.38-energy key
	# light, and a saturated one turns the whole cliff into cobalt panelling,
	# because these faces are vertical and almost all of their light is sky
	# ambient off a cobalt zenith. The cliff has to read as a grey-blue MASS
	# that is darker than the snow around it, with its structure carried by
	# shading rather than by albedo contrast.
	var wall := Color(0.63, 0.665, 0.71)
	var foot := Color(0.19, 0.25, 0.33)     # shadowed contact, desaturated
	var ice_mid := Color(0.42, 0.5, 0.6)    # glacial blue base band
	var snow := Color(0.94, 0.96, 1.0)

	var pts: Array[PackedVector3Array] = []
	var cols: Array[PackedColorArray] = []
	var outs: Array[PackedVector3Array] = []
	for i: int in rings:
		var o := start_offset + seg * float(i)
		var xf := main_guide.transform_at(o)
		# Long-wavelength swell in the crest line, a slower meander in the
		# standoff, a separate girth term for wall thickness and roof depth,
		# and a short-wavelength flute that pushes the face in and out.
		var swell := sin(o * 0.055 + ph[0]) * 0.62 + sin(o * 0.131 + ph[1]) * 0.26 \
				+ sin(o * 0.29 + ph[2]) * 0.12
		var meander := sin(o * 0.043 + ph[3]) * 0.70 + sin(o * 0.097 + ph[4]) * 0.30
		var girth := sin(o * 0.081 + ph[5]) * 0.70 + sin(o * 0.19 + ph[6]) * 0.30
		# Fluting: a smooth in/out breathing of the face plus a per-ring kick,
		# so consecutive rings sit at slightly different depths and the wall
		# creases vertically the way weathered ice does. Without the per-ring
		# term the face is a smooth sheet no matter how much it undulates.
		var flute := sin(o * 0.71 + ph[7]) * 0.58 + sin(o * 1.29 + ph[8]) * 0.42 \
				+ (_cliff_hash(i, seed_value + 311) * 2.0 - 1.0) * 0.38
		# Crest serration. Half of it is a smooth wave; the other half is one
		# value per ring, which is what gives the skyline a tooth at sweep
		# resolution instead of a sine curve.
		var jag := (sin(o * 0.37 + ph[9]) * 0.6 + sin(o * 0.83 + ph[10]) * 0.4) * 0.46 \
				+ (_cliff_hash(i, seed_value) * 2.0 - 1.0) * 0.54
		# Where the two snow benches cut across the face. They wander, because a
		# dead-level ledge running 130 m reads as a machined groove.
		var ledge := Vector2(
			0.30 + 0.045 * sin(o * 0.062 + ph[11]),
			0.60 + 0.045 * sin(o * 0.091 + ph[2]))

		# Both ends die into the snowfield. A run that simply stops leaves a
		# sheer 20 m end wall standing in open snow.
		var fade := minf(18.0, span * 0.3)
		var taper := smoothstep(0.0, fade, o - start_offset) \
				* smoothstep(0.0, fade, end_offset - o)
		taper = 0.14 + 0.86 * taper

		var u := xf.basis.x * side              # horizontal, points away from the track
		var lateral := (19.0 + meander * 2.6) * side
		var line := xf.origin + xf.basis.x * lateral
		var base_y := xf.origin.y - 3.5         # snowline the apron toe sits on
		var h := base_height * (1.0 + 0.30 * swell) * taper
		var crest_y := base_y + h * (1.0 + 0.16 * jag)
		var girth_w := 1.0 + 0.30 * girth
		var roof := 6.4 + 2.0 * girth
		# Bedded, not planted on the deck: take the lower of the local surface
		# and the snowline, then keep falling toward the lake.
		var terrain_y := ground_height_at(Vector3(line.x, xf.origin.y + 2.0, line.z))
		var foot_y := maxf(sheet_y - 1.5, crest_y - (h + 1.0) * CLIFF_MAX_STRETCH)
		foot_y = minf(foot_y, minf(base_y, terrain_y) - 2.0)

		var prof := _cliff_profile(base_y, crest_y, foot_y, h, girth_w, roof, flute, ledge)
		var ring := PackedVector3Array()
		var out := PackedVector3Array()
		for j: int in CLIFF_RING:
			var pr := prof[j]
			ring.append(Vector3(line.x + u.x * pr.x, pr.y, line.z + u.z * pr.x))
			# Outward normal of the edge j -> j+1. The cross-section is wound
			# clockwise in (outward, up), for which (-dy, dx) points out of the
			# solid; computing it per EDGE rather than from a section centroid
			# keeps it correct across the concave apron toe.
			var e := prof[(j + 1) % CLIFF_RING] - pr
			var ow := u * -e.y + Vector3.UP * e.x
			out.append(ow.normalized() if ow.length_squared() > 1e-9 else u)
		pts.append(ring)
		outs.append(out)

		# Vertical ramp, matched at every shared edge so the wall grades instead
		# of stacking flat bands: shadowed foot, glacial blue at the snowline,
		# streaked wall, snow on the two benches, snow rim and roof. The streak
		# varies along the sweep, which is where the vertical striation comes
		# from now that there are no columns to carry it.
		var s := 1.0 + 0.07 * flute + 0.05 * (_cliff_hash(i, seed_value + 977) * 2.0 - 1.0)
		var face := Color(wall.r * s, wall.g * (0.7 + 0.3 * s), wall.b * (0.85 + 0.15 * s))
		var band_ice := ice_mid.lerp(face, 0.35)
		cols.append(PackedColorArray([
			band_ice,                     #  0 apron toe, at the snowline
			band_ice.lerp(face, 0.55),    #  1 apron shoulder
			face,                         #  2 lower face
			face.lerp(snow, 0.72),        #  3 lower bench
			face.lerp(snow, 0.06),        #  4 mid face
			face.lerp(snow, 0.78),        #  5 upper bench
			face.lerp(snow, 0.18),        #  6 upper face
			face.lerp(snow, 0.9),         #  7 crest lip
			snow,                         #  8 roof, back edge
			foot,                         #  9 back foot
			foot,                         # 10 skirt foot
		]))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in rings - 1:
		for j: int in CLIFF_RING:
			var k := (j + 1) % CLIFF_RING
			var ow := outs[i][j] + outs[i + 1][j]
			_cliff_quad(st, pts[i][j], pts[i][k], pts[i + 1][k], pts[i + 1][j],
				cols[i][j], cols[i][k], cols[i + 1][k], cols[i + 1][j], ow.normalized())
	# Caps, so the ends are solid rather than open tubes. Both sit in the
	# tapered-down tail of the run, buried in the snowfield.
	var head := (_cliff_centre(pts[0]) - _cliff_centre(pts[1])).normalized()
	_cliff_cap(st, pts[0], cols[0], head)
	var tail := (_cliff_centre(pts[rings - 1]) - _cliff_centre(pts[rings - 2])).normalized()
	_cliff_cap(st, pts[rings - 1], cols[rings - 1], tail)

	var instance := MeshInstance3D.new()
	instance.name = "IceCliff_%d" % seed_value
	instance.mesh = st.commit()
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


## Closed cliff cross-section in (outward-from-track, world Y), wound CLOCKWISE
## from the apron toe: up the face to the crest, back along the roof, down the
## back wall and along the floor. Clockwise is what makes (-dy, dx) the outward
## edge normal, which is what _add_cliff_run winds every triangle against.
##
## The face is not one plane. It steps back at two BENCHES — a near-horizontal
## tread at `ledge.x` and `ledge.y` of the crest height — because the single
## biggest reason a swept wall still reads as a flat backdrop is that it has no
## horizontal structure. A bench tread faces up, so it takes the terrain
## shader's snow catch as well as a baked snow colour, and the resulting pair
## of bright lines running the length of the run is what makes the thing read
## as bedded, weathered ice rather than as a painted flat.
##
## `flute` (-1..1) breathes the face in and out along the sweep. It is weighted
## down as the profile climbs, so the base is deeply fluted and the crest line
## stays clean; and it is kept off the toe, the benches' back edges and the
## roof, which want to stay level.
static func _cliff_profile(base_y: float, crest_y: float, foot_y: float, h: float,
		girth: float, roof: float, flute: float, ledge: Vector2) -> PackedVector2Array:
	# Y is strictly increasing from the toe to the crest lip, which is what
	# guarantees the section cannot self-intersect however far the flute pushes
	# a point sideways. 0.78 for the top of the face leaves headroom under the
	# lowest crest the serration can produce (0.84 h).
	var lo := base_y + h * ledge.x
	var hi := base_y + h * ledge.y
	return PackedVector2Array([
		Vector2(-1.70 * girth, base_y),                              #  0 apron toe
		Vector2(-0.85 * girth + flute * 0.20, base_y + h * 0.10),    #  1 apron shoulder
		Vector2(-0.20 * girth + flute * 0.85, lo),                   #  2 lower face
		Vector2(0.55 * girth + flute * 0.85, lo + h * 0.018),        #  3 lower bench
		Vector2(0.80 * girth + flute * 0.62, hi),                    #  4 mid face
		Vector2(1.50 * girth + flute * 0.62, hi + h * 0.016),        #  5 upper bench
		Vector2(1.70 * girth + flute * 0.38, base_y + h * 0.78),     #  6 upper face
		Vector2(2.00 * girth + flute * 0.20, crest_y),               #  7 crest lip
		Vector2(roof, crest_y - h * 0.16),                           #  8 roof, back edge
		Vector2(roof, foot_y),                                       #  9 back foot
		Vector2(-1.05 * girth, foot_y),                              # 10 skirt foot
	])


## Deterministic 0..1 hash. Used for the per-ring half of the crest serration:
## a pure sine sum cannot produce a tooth at sweep resolution without aliasing
## against the ring spacing, and a RandomNumberGenerator draw here would make
## the wall depend on how many other passes had drawn from the course rng.
static func _cliff_hash(n: int, salt: int) -> float:
	var x := (n * 374761393 + salt * 668265263) & 0x7fffffff
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff
	return float(x % 1000003) / 1000003.0


static func _cliff_centre(ring: PackedVector3Array) -> Vector3:
	var sum := Vector3.ZERO
	for p: Vector3 in ring:
		sum += p
	return sum / float(ring.size())


## Fan-caps one end of the sweep. The cross-section is star-shaped about its
## toe (point 0 is its extreme inward point), so a fan from there is valid.
static func _cliff_cap(st: SurfaceTool, ring: PackedVector3Array,
		colors: PackedColorArray, outward: Vector3) -> void:
	for j: int in range(1, ring.size() - 1):
		_cliff_tri(st, ring[0], ring[j], ring[j + 1],
			colors[0], colors[j], colors[j + 1], outward)


## Sweep quad with a colour at every corner, flat-shaded: both triangles are
## given the QUAD's normal rather than their own, so a non-planar ring pair
## does not crease down its diagonal.
static func _cliff_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ca: Color, cb: Color, cc: Color, cd: Color, outward: Vector3) -> void:
	var n := (c - a).cross(d - b)
	if n.length_squared() < 1e-9:
		return
	n = n.normalized()
	if n.dot(outward) < 0.0:
		n = -n
	_cliff_tri(st, a, b, c, ca, cb, cc, n)
	_cliff_tri(st, a, c, d, ca, cc, cd, n)


## Triangle wound so its front face carries `n`, with `n` written explicitly on
## all three vertices. Explicit normals rather than SurfaceTool.generate_normals
## because that merges by position: on a swept tube every ring vertex is shared
## by the quads above and below it, and averaging across those creases rounds a
## crest lip into a wax drip.
static func _cliff_tri(st: SurfaceTool, p: Vector3, q: Vector3, r: Vector3,
		cp: Color, cq: Color, cr: Color, n: Vector3) -> void:
	var v1 := q
	var v2 := r
	var c1 := cq
	var c2 := cr
	# _ctri's front face is the winding for which (r - p) x (q - p) faces the
	# viewer; flip the pair when this triangle came out the other way round.
	if (r - p).cross(q - p).dot(n) < 0.0:
		v1 = r
		v2 = q
		c1 = cr
		c2 = cq
	st.set_normal(n)
	st.set_color(cp)
	st.add_vertex(p)
	st.set_normal(n)
	st.set_color(c1)
	st.add_vertex(v1)
	st.set_normal(n)
	st.set_color(c2)
	st.add_vertex(v2)


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
		# Same treatment as the cliff runs: keep the crown lip where it was
		# authored and pour the cascade down to the lake rather than ending it
		# in mid-air 5m under the deck (capped so the melt-columns keep their
		# proportions).
		var crest_y := pos.y + authored_height
		var footed_height := clampf(crest_y - (sheet_y - 1.5),
			authored_height, authored_height * CLIFF_MAX_STRETCH)
		# X and Z scale EQUALLY, and the mesh carries the wall's depth-to-width
		# ratio itself (FALL_DEPTH_RATIO). This is not cosmetic. A MultiMesh
		# instance transform does NOT get an inverse-transpose applied to its
		# normals -- the non-uniform-scale flag is read off the NODE, which is
		# unscaled -- so a per-instance scale of (20, 50, 5) multiplied every
		# normal's x by 20 and its z by 5. A groove flank 0.15 m deep across
		# 0.5 m, whose true normal is 17 deg off the wall face, came out at 78
		# deg: turned along the wall, away from the key light, no diffuse at
		# all. That is what rendered every groove between the melt-columns as a
		# hard BLACK bar. With x and z scaled alike the ratio survives and the
		# flanks light like the faces they sit between.
		var fall_basis := Basis(Vector3.UP, yaw + yaw_jitter) \
			* Basis.from_scale(Vector3(fall_width, footed_height, fall_width))
		transforms.append(Transform3D(fall_basis, Vector3(pos.x, crest_y - footed_height, pos.z)))
		offset += 19.0
	# Two-sided: the cascade is an open shell of melt-columns, and a groove flank
	# that happens to turn away from the camera must still draw rather than open
	# a hole into the wall. Duplicated off the cache, which is shared.
	var fall_mat := VisualLibrary.rock_material(Color(1.0, 1.0, 1.0), 0.3).duplicate() as StandardMaterial3D
	fall_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add_multimesh(_icefall_mesh(6161), transforms, fall_mat, "FrozenFalls", false, 480.0)


## Unit frozen-waterfall slab: x -0.5..0.5, y 0..1, cascade face toward +Z.
## Vertical melt-columns with per-column width/depth jitter, pale aqua flow
## streaks graded down the column fronts, a frost-white crown lip where the
## cascade pours over the edge, and a hanging icicle tip below each column base.
##
## The recesses between columns are SLANTED grooves, not perpendicular return
## planes drawn in both windings. The old build did the latter, and since this
## wall runs parallel to the racing line it is almost always seen edge-on: each
## plane collapsed to a sub-pixel sliver of saturated cobalt, and the row of
## them is the column of thin vertical hairlines that streaked the right flank
## in qa_shots/props/bt12.png. A groove with real width shades instead of
## aliasing, and needs one winding because its normal always carries +Z.
## Deterministic per seed.
## Wall depth as a fraction of wall WIDTH. Baked into the mesh instead of into
## the instance scale, so _decorate_icefall can scale x and z alike and keep the
## instance normal transform honest (see the note there). The product of this
## and the mesh's z range reproduces the depth the old (17-22 x 4-6) scale gave.
const FALL_DEPTH_RATIO: float = 0.25


func _icefall_mesh(seed_value: int) -> ArrayMesh:
	var mrng := RandomNumberGenerator.new()
	mrng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 10
	var crown := Color(0.94, 0.97, 1.0)
	var flow_hi := Color(0.66, 0.84, 0.97)
	var flow_lo := Color(0.34, 0.6, 0.86)
	var recess := Color(0.3, 0.47, 0.66)
	# Wide grooves, shallow columns. A groove is only ever seen as a clean shaded
	# band if its normal stays near the wall's own facing; a narrow groove between
	# columns of very different depth turns almost edge-on to the camera, which is
	# how this wall produced hairlines (and, at some angles, unlit slivers) in the
	# first place. Roughly a third of a column wide at a third of the old depth
	# spread keeps the melt-column read while holding every flank near-frontal.
	var groove_w := 0.17 / float(cols)
	var prev_z := 0.0
	var prev_lip := 0.0
	for i: int in cols:
		var x0 := -0.5 + float(i) / float(cols)
		var x1 := -0.5 + float(i + 1) / float(cols)
		var z := mrng.randf_range(0.06, 0.11) * FALL_DEPTH_RATIO
		var lip := mrng.randf_range(0.86, 0.93)
		var tip_y := mrng.randf_range(0.02, 0.12)
		var streak := mrng.randf_range(0.8, 1.1)
		var hi := Color(flow_hi.r * streak, flow_hi.g * (0.85 + 0.15 * streak), flow_hi.b)
		var lo := Color(flow_lo.r * streak, flow_lo.g * (0.85 + 0.15 * streak), flow_lo.b)
		var mid_y := lerpf(tip_y, lip, 0.45)
		var fx0 := x0 + groove_w
		var fx1 := x1 - groove_w
		# Column front, graded so the pour reads as one flowing sheet rather than
		# three stacked bands of flat colour.
		_cgrad(st, Vector3(fx0, tip_y, z), Vector3(fx1, tip_y, z),
			Vector3(fx1, mid_y, z), Vector3(fx0, mid_y, z), lo, lo.lerp(hi, 0.5))
		_cgrad(st, Vector3(fx0, mid_y, z), Vector3(fx1, mid_y, z),
			Vector3(fx1, lip, z), Vector3(fx0, lip, z), lo.lerp(hi, 0.5), hi)
		# Crown runs the FULL column width, groove included: cutting it back to
		# the column front left an open vertical slot above every groove.
		_cgrad(st, Vector3(x0, lip, z), Vector3(x1, lip, z),
			Vector3(x1, 1.0, z - 0.1 * FALL_DEPTH_RATIO),
			Vector3(x0, 1.0, z - 0.1 * FALL_DEPTH_RATIO), hi.lerp(crown, 0.6), crown)
		# Icicle tip hanging under the column base. ONE winding: the reversed
		# copy the old build added was coplanar with this triangle, so the two
		# z-fought and the loser — facing away from every light — shaded black.
		# That pair is the same construct that tore a black hole in the ice arch.
		var drop := Vector3((fx0 + fx1) * 0.5 + mrng.randf_range(-0.02, 0.02),
			tip_y - mrng.randf_range(0.05, 0.14), z * 0.5)
		_ctri3(st, Vector3(fx0, tip_y, z), Vector3(fx1, tip_y, z), drop, lo, lo, lo.lerp(hi, 0.4))
		if i > 0:
			var rec := recess * mrng.randf_range(0.85, 1.05)
			rec.a = 1.0
			var rec_lo := Color(rec.r * 0.68, rec.g * 0.74, rec.b * 0.84)
			# Full height of BOTH neighbours, so a groove between columns of
			# different heights never leaves a notch to see through.
			var hi_y := maxf(lip, prev_lip)
			# Symmetric V, not one steeply leaning plane. A single slanted quad
			# between two columns of unequal depth ends up nearly parallel to the
			# view along this wall — the exact condition that produced hairlines
			# in the first place — and its two possible lean directions light
			# completely differently, so alternate grooves went dark. A V has one
			# flank facing each way and a real floor between them.
			var zmid := minf(prev_z, z) - 0.022 * FALL_DEPTH_RATIO
			_cgrad(st, Vector3(x0 - groove_w, 0.0, prev_z), Vector3(x0, 0.0, zmid),
				Vector3(x0, hi_y, zmid), Vector3(x0 - groove_w, hi_y, prev_z), rec_lo, rec)
			_cgrad(st, Vector3(x0, 0.0, zmid), Vector3(x0 + groove_w, 0.0, z),
				Vector3(x0 + groove_w, hi_y, z), Vector3(x0, hi_y, zmid), rec_lo, rec)
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
		if not _clear_of_wildlife(pos, 3.6):
			continue
		transforms.append(Transform3D(boulder_basis, pos))
		_add_contact_patch(pos, maxf(boulder_basis.get_scale().x, boulder_basis.get_scale().z) * 0.75)
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


## Quad with a bottom colour and a top colour, corners in the same order as
## _cquad. Flat-shaded facets all wearing one tone is the "untextured polygon"
## read; a vertical ramp costs nothing extra and gives the surface real value.
static func _cgrad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		low: Color, high: Color) -> void:
	_ctri3(st, a, d, c, low, high, high)
	_ctri3(st, a, c, b, low, high, low)


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


## Shared massif material. The vertex colours already carry rock/snow/moraine
## and a per-ring haze; the shader adds the two things a baked colour cannot:
## a world-scale strata break-up (peaks are placed at 300-1200 m, where a face
## covering 40 px of screen needs internal value to not read as a cut-out) and a
## VIEW-DISTANCE ramp toward a haze tone that stays darker than the sky, so the
## far ring recedes without dissolving into the horizon. Snow catch is kept low
## here — the mesh already decides where its own snowline sits.
func _mountain_material() -> ShaderMaterial:
	return VisualLibrary.shader_variant(
		VisualLibrary.terrain_material(Color(1.0, 1.0, 1.0), 0.7, 0.55, 0.95), {
			"strata_strength": 0.42,
			"strata_scale": 0.035,      # ~29 m bands on a 200-400 m massif
			"face_shade": 0.26,
			"snow_catch": 0.14,
			"haze_start": 260.0,
			"haze_end": 1250.0,
			"haze_color": Color(0.3, 0.42, 0.6),
		})


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
		instance.material_override = _mountain_material()
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
	# Haze target sits BELOW the sky's value on purpose. The old target (a bright
	# 0.6/0.77/0.96) carried the far ring up to the horizon's own brightness, so
	# distant peaks and sky measured within a couple of percent of each other and
	# the skyline read as one pale mass. Real aerial perspective desaturates and
	# converges toward the horizon while staying a distinctly darker silhouette.
	return col.lerp(Color(0.34, 0.45, 0.62), haze)


static func _ctri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	_ctri3(st, a, b, c, color, color, color)


static func _ctri3(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ca: Color, cb: Color, cc: Color) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)
