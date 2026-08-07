class_name CourseHollow
extends CourseBase
## SAPPHIRE HOLLOW: a technical run threaded through the inside of the glacier.
## Down a narrow meltwater slot on rough ice, through a vaulted icicle gallery,
## into the howling draught where two crosswinds squeeze a wide bend (or past
## it entirely, down a no-wall moulin ledge), along a boulder run with two
## rolling ice masses on it, a cold swim across the subglacial lake, into the
## crystal cathedral, and out through a long blue exit chute into the open.
##
## The opposite of a wide daylight course: enclosed, dim, cold-blue, lit from
## a narrow sky slot overhead with bounced light off the ice, and won on
## precision rather than top speed. Route readability comes from the glowing
## crystal veins in the walls, not from contrast against snow.

const SNOW := SurfacesDB.Surface.PACKED_SNOW
const ICE := SurfacesDB.Surface.ICE_SMOOTH
const RICE := SurfacesDB.Surface.ICE_ROUGH

## Surface of the subglacial lake, and the floor of the hollow far below the
## upper galleries. Both are course-wide reference heights: the shore foam, the
## swim channel, the wall footings and the mist all key off them.
const LAKE_Y: float = 20.0
const HOLLOW_FLOOR_Y: float = -6.0

## Sky-slot bearing (world yaw, degrees, matching build_environment). The light
## falls almost straight down the crack in the roof, so it is nearly vertical;
## the yaw only decides which wall gets the grazing light.
const SLOT_YAW_DEG: float = 12.0

## Glow crystal palette. Emission stays modest on purpose — the environment's
## glow threshold is low here so these bloom, and a hot value turns the whole
## cavern into a lamp instead of leaving the dark dark.
const CRYSTAL_GLOW: Color = Color(0.28, 0.86, 1.0)
const CRYSTAL_ALBEDO: Color = Color(0.16, 0.55, 0.78)

## Track albedo. Deeper and colder than the daylight courses: this ice is tens
## of metres inside a glacier, where only blue light survives. The rough-ice
## runs stay paler so the two surfaces still read apart in the gloom.
const TRACK_ICE_TINT: Color = Color(0.10, 0.36, 0.66)
const TRACK_RICE_TINT: Color = Color(0.40, 0.58, 0.74)
const TRACK_SNOW_TINT: Color = Color(0.66, 0.72, 0.80)


func _init() -> void:
	course_id = "hollow"


static func p(x: float, y: float, z: float, extra: Dictionary = {}) -> Dictionary:
	var d := {"pos": Vector3(x, y, z)}
	d.merge(extra)
	return d


func build_course() -> void:
	var pts: Array = [
		# 1) Staging hall just inside the cave mouth: long straight for the
		# grid under the first vault, then onto the rough meltwater ice.
		p(0, 46, 35, {"width": 16.0}),
		p(0, 46, -25, {"width": 16.0}),
		p(-2, 44.5, -82, {"width": 16.0, "surface": RICE}),
		# 2) Slot descent: narrow scoured ice, one long left then a right,
		# walls on both sides the whole way. This is the course stating its
		# terms — 13m wide and no room to be sloppy.
		p(-16, 41.5, -132, {"width": 13.0, "surface": RICE}),
		p(-32, 38.5, -180, {"width": 13.0, "surface": RICE}),
		p(-28, 36.0, -230, {"width": 13.0, "surface": RICE}),
		p(-8, 34.0, -274, {"width": 14.0}),
		# 3) Icicle gallery: a vaulted hall with a shallow right kink, packed
		# meltwater snow underfoot and ten spikes hanging over the line.
		p(10, 32.5, -322, {"width": 14.0}),
		p(20, 31.5, -376, {"width": 14.0}),
		p(16, 30.5, -430, {"width": 14.0, "wall_r": false}),
		# 4) The draught: the hollow opens into a wide left bend where wind
		# funnels through two side crevasses. Widened to 16 on purpose — the
		# crosswinds move racers positionally, so the bend has to give that
		# movement somewhere to go.
		p(0, 29.0, -480, {"width": 16.0}),
		p(-20, 27.5, -530, {"width": 16.0}),
		p(-26, 26.0, -580, {"width": 16.0, "wall_r": false}),
		p(-12, 24.5, -630, {"width": 18.0}),
		# 5) Boulder run: a wide, gently falling straight with two rolling ice
		# masses working down it in fixed lanes.
		p(-2, 23.0, -692, {"width": 18.0}),
		p(6, 22.0, -752, {"width": 18.0}),
		# 6) Subglacial lake: an iced run-in to the shelf edge, a cold swim
		# across, and a submerged ramp back out the far side.
		p(2, 21.8, -800, {"width": 16.0, "surface": ICE}),
		p(-2, 21.4, -838, {"width": 14.0}),
		p(-4, 21.0, -866, {"width": 14.0, "gap": true}),   # shelf edge, 1m over water
		p(-4, 20.0, -890, {"width": 14.0, "gap": true}),   # guide at the surface
		p(-4, 20.0, -912, {"width": 14.0, "gap": true}),
		# Submerged exit ramp: its lip sits 0.8m UNDER the lake so a swimmer
		# meets a slope instead of a wall, and the water volume runs 14m past
		# it so the rising floor lifts racers clear while they are still
		# swimming. Both numbers are load-bearing — a lip level with the
		# surface, or water that stops at the lip, traps the whole field in
		# the lake (verified in race_sim).
		p(-3, 19.2, -919, {"width": 18.0, "surface": ICE, "wall_l": false, "wall_r": false}),
		p(0, 21.4, -952, {"width": 18.0, "surface": ICE}),
		# 7) Crystal cathedral: the one big room on the course, a wide right
		# sweep under a 20m vault hung with glowing veins.
		p(4, 22.4, -1002, {"width": 18.0}),
		p(16, 23.4, -1052, {"width": 18.0}),
		p(22, 23.6, -1104, {"width": 16.0}),
		# 8) Exit chute: 22m of sustained drop out of the glacier at about -6
		# degrees, iced end to end so the slide starts at the lip.
		p(14, 20.0, -1162, {"width": 16.0, "surface": ICE}),
		p(0, 14.0, -1224, {"width": 16.0, "surface": ICE}),
		p(-10, 8.0, -1286, {"width": 18.0, "surface": ICE}),
		p(-8, 3.5, -1346, {"width": 18.0, "surface": ICE}),
		# 9) Outwash plain: daylight at last, and the finish banner.
		p(0, 1.5, -1404, {"width": 18.0}),
		p(0, 1.5, -1460, {"width": 18.0}),
	]
	setup_main(pts)

	# Moulin ledge: a narrow no-wall shelf spiralling down the inside of an old
	# meltwater shaft. It cuts the draught bend — and skips both wind zones —
	# but there is nothing at all on either side of it.
	var branch_pts: Array = [
		p(14, 30.0, -444, {"width": 10.0, "surface": RICE, "wall_l": false, "wall_r": false}),
		p(10, 28.4, -492, {"width": 8.0, "surface": RICE, "wall_l": false, "wall_r": false}),
		p(6, 26.8, -540, {"width": 8.0, "surface": RICE, "wall_l": false, "wall_r": false}),
		p(2, 25.6, -586, {"width": 9.0, "surface": RICE, "wall_l": false, "wall_r": false}),
		p(-8, 24.6, -626, {"width": 10.0, "surface": RICE, "wall_l": false, "wall_r": false}),
	]
	var shortcut := add_branch(branch_pts, 0.7, "moulin_ledge")

	finalize()

	# --- Geometry-derived offsets ------------------------------------------
	var slot_start := _offset_near(Vector3(-16, 41.5, -132))
	var gallery_start := _offset_near(Vector3(10, 32.5, -322))
	var gallery_end := _offset_near(Vector3(16, 30.5, -430))
	var draught_start := _offset_near(Vector3(0, 29.0, -480))
	var draught_end := _offset_near(Vector3(-26, 26.0, -580))
	var merge := _offset_near(Vector3(-12, 24.5, -630))
	var boulder_start := _offset_near(Vector3(-2, 23.0, -692))
	var boulder_end := _offset_near(Vector3(2, 21.8, -800))
	var lake_in := _offset_near(Vector3(-2, 21.4, -838))
	var lake_ramp := _offset_near(Vector3(-3, 19.2, -919))
	var lake_out := _offset_near(Vector3(0, 21.4, -952))
	var cathedral := _offset_near(Vector3(16, 23.4, -1052))
	var chute_start := _offset_near(Vector3(14, 20.0, -1162))
	var chute_end := _offset_near(Vector3(-8, 3.5, -1346))

	# --- Subglacial lake ----------------------------------------------------
	# Water is separate geometry laid under the gap span: the swim volume, the
	# visible surface and the lake bed all come from build_water.
	var lake_pts: Array = [
		p(-4, LAKE_Y, -870, {"width": 15.0}),
		p(-4, LAKE_Y, -890),
		p(-4, LAKE_Y, -912),
		p(-3, LAKE_Y, -933),
	]
	var lake := TrackBuilder.build_water(lake_pts, "SubglacialLake")
	add_child(lake)
	_restyle_lake(lake)

	# --- Icicle gallery: ten spikes on a weaving safe line ------------------
	var icicle_laterals: Array = [-3.5, 3.0, -2.0, 3.5, -3.0, 2.0, -3.5, 3.0, -2.5, 3.5]
	for i: int in icicle_laterals.size():
		var offset := gallery_start + 6.0 + float(i) * 11.0
		if offset > gallery_end - 4.0:
			break
		var icicle := HazardIcicle.new()
		icicle.position = main_guide.point_at(offset, float(icicle_laterals[i]), 5.5)
		add_child(icicle)
	# First half hangs left-heavy, second half right-heavy: weave the bots.
	var gallery_mid := (gallery_start + gallery_end) * 0.5
	add_hint(gallery_start - 25.0, "danger_left", gallery_mid)
	add_hint(gallery_mid, "danger_right", gallery_end)

	# --- The draught: two crosswinds, opposed ------------------------------
	# Opposed directions so the bend cannot be taken with one held line, and
	# each gets a danger hint pointing away from the push so the AI
	# pre-compensates instead of being blown into the wall it is hugging.
	var draught_specs: Array = [
		{"offset": draught_start + 16.0, "dir": 1.0},
		{"offset": draught_end - 22.0, "dir": -1.0},
	]
	for spec: Dictionary in draught_specs:
		var offset := float(spec["offset"])
		var xform := main_guide.transform_at(offset)
		var wind := HazardWindZone.new()
		wind.configure(xform.basis.x * float(spec["dir"]), 3.4, Vector3(13.0, 8.0, 30.0))
		wind.transform = Transform3D(xform.basis, xform.origin + xform.basis.y * 3.0)
		add_child(wind)
		var kind := "danger_right" if float(spec["dir"]) > 0.0 else "danger_left"
		add_hint(offset - 32.0, kind, offset + 22.0)

	# --- Boulder run: two rolling ice masses in fixed lanes -----------------
	var boulder_a := HazardSnowball.new()
	boulder_a.configure(main_guide, boulder_start, boulder_end, -4.5, 15.0)
	add_child(boulder_a)
	var boulder_b := HazardSnowball.new()
	boulder_b.configure(main_guide, boulder_start + 55.0, boulder_end, 4.5, 13.0)
	add_child(boulder_b)
	add_hint(boulder_start - 30.0, "danger_left", boulder_start + 40.0)
	add_hint(boulder_start + 40.0, "danger_right", boulder_end)

	# --- Slide hints --------------------------------------------------------
	# Only the authored ice runs: the lake run-in, the ramp out of the water
	# through the cathedral approach, and the whole exit chute (re-acquired
	# mid-chute so a racer respawning inside it does not waddle the rest).
	add_hint(boulder_end - 6.0, "slide", lake_in)
	add_hint(lake_ramp, "slide", lake_out + 20.0)
	# One porpoise out of the water: the jump burst in SWIMMING state carries a
	# racer up onto the ramp lip even if it arrives low and slow.
	add_hint(lake_ramp - 10.0, "jump")
	add_hint(chute_start - 6.0, "slide", chute_end + 12.0)
	add_hint(_offset_near(Vector3(0, 14.0, -1224)), "slide", chute_end + 12.0)
	# The moulin ledge is rough ice all the way down: slide it and hold the
	# line. Branch hints are matched against MAPPED main-line progress, so
	# they run entry..exit.
	var branch_entry := float(branches[0]["entry"])
	var branch_exit := float(branches[0]["exit"])
	add_hint(branch_entry + 20.0, "slide", branch_exit - 12.0, 0)

	# --- Boost pads ---------------------------------------------------------
	# Every pad sits on a straight pointing down-track and well clear of the
	# icicle lanes, the wind zones, the boulder lanes and the shelf edge: the
	# staging-hall exit, the gallery entry straight, the merge straight past
	# the moulin ledge, the swim exit (relaunching lost momentum is the whole
	# point of a swim), and two down the exit chute.
	TrackBuilder.add_boost_pad(self, main_guide, 70.0)
	TrackBuilder.add_boost_pad(self, main_guide, gallery_start - 14.0)
	TrackBuilder.add_boost_pad(self, main_guide, merge + 12.0)
	TrackBuilder.add_boost_pad(self, main_guide, lake_out + 8.0)
	TrackBuilder.add_boost_pad(self, main_guide, chute_start + 34.0, -3.0)
	TrackBuilder.add_boost_pad(self, main_guide, chute_start + 84.0, 3.0)

	# --- Pickups ------------------------------------------------------------
	add_item_row(120.0)
	add_item_row(_offset_near(Vector3(-8, 34.0, -274)))
	add_item_row(merge + 30.0)
	add_item_row(cathedral)
	add_item_row(chute_end + 34.0)
	add_snowball_row(155.0)
	add_snowball_row(gallery_start + 40.0)
	add_snowball_row(cathedral - 40.0)

	add_fish_line(60.0, 8, 5.0, 0.0)
	add_fish_line(slot_start + 10.0, 8, 5.0, -3.0)
	add_fish_line(gallery_start + 12.0, 10, 4.5, 0.0)
	add_fish_line(25.0, 10, 6.0, 0.0, 0.0, shortcut)  # reward the moulin ledge
	add_fish_line(draught_start + 8.0, 8, 5.5, 4.0)
	add_fish_line(boulder_start + 12.0, 10, 5.0, 0.0)
	add_fish_line(_offset_near(Vector3(-4, 20.0, -890)) - 14.0, 8, 5.5, 0.0)  # across the lake
	add_fish_line(cathedral - 20.0, 10, 5.0, -4.0)
	add_fish_line(chute_start + 40.0, 12, 5.5, 0.0)

	# The hollow floor goes down before anything else: the wall footings, the
	# far-field skyline and every seated prop measure themselves against it.
	add_ground_plane(HOLLOW_FLOOR_Y, Color(0.02, 0.06, 0.1), 4000.0,
		VisualLibrary.rock_material(Color(0.03, 0.08, 0.13), 1.0))
	_retint_track()
	_decorate()
	# Deep inside the ice: a near-black roof, a thin band of daylight where the
	# slot opens overhead, a steep cold key light falling almost straight down
	# it, and strong ambient because blue ice bounces light around a cavern far
	# more than snow does. Fog is thicker than any other course — that is what
	# an enclosed, humid, meltwater-fed space looks like — but stays honest
	# enough that the next corner always reads. Glow threshold is low so the
	# crystal veins bloom; nothing else on the course is bright enough to.
	build_environment({
		"sky_top": Color(0.02, 0.05, 0.10),
		"sky_horizon": Color(0.05, 0.16, 0.25),
		"ground_color": Color(0.02, 0.07, 0.12),
		"sun_angle_deg": -66.0,
		"sun_yaw_deg": SLOT_YAW_DEG,
		"sun_energy": 1.0,
		"sun_color": Color(0.72, 0.88, 1.0),
		"sun_angle_max": 6.0,
		"sun_curve": 0.2,
		"sky_energy": 0.68,
		"ambient_energy": 1.0,
		"exposure": 0.9,
		"fog_color": Color(0.05, 0.17, 0.26),
		"fog_density": 0.0035,
		"fog_horizon_blend": 0.28,
		"fog_aerial": 0.3,
		"fog_sun_scatter": 0.1,
		"fog_height": 40.0,
		"fog_height_density": 0.02,
		"glow_threshold": 1.15,
		"glow_intensity": 0.5,
		"shadow_distance": 110.0,
		"contrast": 1.12,
		"saturation": 1.14,
		"snow": false,
		"clouds": false,
		"sky_cover_strength": 0.0,
		"fill_energy": 0.24,
		"fill_color": Color(0.24, 0.5, 0.78),
		"skyline": false,
	})


func _offset_near(point: Vector3) -> float:
	return float(main_guide.nearest(point, -1)["offset"])


## Every floor run is re-skinned per surface with course-local material
## instances — never by mutating TrackBuilder's cached surface materials, which
## every other course in the session shares. Floor meshes are emitted as
## MeshInstance3D followed by their StaticBody3D, so the body's "surface" meta
## identifies the run it belongs to.
func _retint_track() -> void:
	var ice := VisualLibrary.ice_material(TRACK_ICE_TINT, 0.95).duplicate() as ShaderMaterial
	ice.set_shader_parameter("deep_tint", Color(0.01, 0.1, 0.26))
	ice.set_shader_parameter("roughness_base", 0.04)
	ice.set_shader_parameter("crack_strength", 0.85)
	ice.set_shader_parameter("vein_strength", 0.8)
	var rice := VisualLibrary.ice_material(TRACK_RICE_TINT, 0.4).duplicate() as ShaderMaterial
	rice.set_shader_parameter("deep_tint", Color(0.08, 0.24, 0.42))
	rice.set_shader_parameter("roughness_base", 0.38)
	var snow := VisualLibrary.snow_material(TRACK_SNOW_TINT, 0.4).duplicate() as ShaderMaterial
	# Meltwater snow inside a cave is wet and packed, not wind-carved powder.
	snow.set_shader_parameter("sastrugi_strength", 0.08)
	snow.set_shader_parameter("micro_bump_strength", 0.2)
	snow.set_shader_parameter("shadow_tint", Color(0.3, 0.48, 0.72))
	snow.set_shader_parameter("roughness_value", 0.6)
	# Skirt: the ribbon's visible thickness. Its baked vertex gradient is a
	# glacial lip-to-deep-blue, multiplied by this albedo — darkened here so
	# the deck edge does not glow against a cavern that is meant to be dim.
	# Own instance, because the cached skirt material is shared by every
	# ribbon in the session.
	var skirt := VisualLibrary.rock_material(Color(0.38, 0.52, 0.72), 0.6).duplicate() as StandardMaterial3D
	skirt.vertex_color_use_as_albedo = true
	skirt.cull_mode = BaseMaterial3D.CULL_DISABLED
	var wall: ShaderMaterial = null
	for track: Node in get_children():
		if track.name != &"MainTrack" and not String(track.name).begins_with("Branch_"):
			continue
		var children := track.get_children()
		for i: int in children.size():
			var mesh := children[i] as MeshInstance3D
			if mesh == null:
				continue
			var body: StaticBody3D = null
			if i + 1 < children.size():
				body = children[i + 1] as StaticBody3D
			if body == null:
				# No collider behind it: the visual-only side skirt.
				mesh.material_override = skirt
				continue
			if not body.has_meta("surface"):
				# A collider with no surface tag is an edge wall. Deepened to
				# cave ice, with the crest lip left bright so the boundary
				# still reads by brightness in the dark — the accessibility
				# contract the ice wall shader was written for. Re-tinted per
				# instance: the TrackBuilder original is one cached instance
				# shared by every course and must never be mutated.
				if wall == null:
					var source := mesh.material_override as ShaderMaterial
					if source != null:
						wall = source.duplicate() as ShaderMaterial
						wall.set_shader_parameter("tint", Color(0.07, 0.24, 0.46))
						wall.set_shader_parameter("strata_tint", Color(0.36, 0.62, 0.86))
						wall.set_shader_parameter("lip_tint", Color(0.66, 0.94, 1.0))
						wall.set_shader_parameter("base_alpha", 0.88)
						wall.set_shader_parameter("rim_strength", 0.6)
						wall.set_shader_parameter("lip_glow", 0.24)
				if wall != null:
					mesh.material_override = wall
				continue
			match int(body.get_meta("surface")):
				SNOW:
					mesh.material_override = snow
				ICE:
					mesh.material_override = ice
				RICE:
					mesh.material_override = rice


## The shared channel material is a daylight surface; a subglacial lake is
## near-black water with a cold sheen on top. Swapped by override so the shared
## instance every other course uses is untouched.
func _restyle_lake(lake: Node3D) -> void:
	if GameConfig.is_headless():
		return
	var water := VisualLibrary.water_material(Color(0.005, 0.05, 0.09), Color(0.1, 0.42, 0.5), 0.1, 0.3)
	for child: Node in lake.get_children():
		var mesh := child as MeshInstance3D
		if mesh == null:
			continue
		# build_water emits the surface ribbon first, then the bed beneath it.
		if mesh.material_override is StandardMaterial3D \
				and (mesh.material_override as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
			mesh.material_override = water
		else:
			mesh.material_override = VisualLibrary.rock_material(Color(0.03, 0.09, 0.13), 1.0)


## --- Decoration -------------------------------------------------------------
## Pure visual dressing. Skipped headless (nothing gameplay reads these nodes
## except the ploughable snow cones, which the race sim also does without);
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

	var crystals: Array[Transform3D] = []
	var icicles: Array[Transform3D] = []
	_decorate_walls(density)
	_decorate_vaults(icicles)
	_decorate_pillars(density)
	_decorate_crystals(density, crystals)
	_decorate_wall_icicles(density, icicles)
	_decorate_moraine(density)
	_decorate_snow_cones(density)
	_decorate_markers()
	_decorate_lake_shore(density)
	_decorate_glints(density)
	_decorate_spectators(density)
	_decorate_mist(density)

	# One shared multimesh for every glowing crystal cluster in the hollow, and
	# a second for hanging icicles (the same cluster mesh flipped in the
	# instance transform). The glow material is emissive but restrained: these
	# are veins in the ice catching the sky slot, not floodlights.
	var crystal_mat := VisualLibrary.emissive_material(CRYSTAL_ALBEDO, CRYSTAL_GLOW, 1.9, 0.15)
	_add_multimesh(VisualLibrary.ice_crystal_mesh(), crystals, crystal_mat, "GlowCrystals", false)
	var icicle_mat := VisualLibrary.rock_material(Color(0.62, 0.8, 0.98), 0.12, 0.05)
	_add_multimesh(VisualLibrary.ice_crystal_mesh(), icicles, icicle_mat, "HangingIcicles", false)


## range_base > 0 opts the dressing into VisualLibrary.apply_dressing_range
## distance culling. Visibility range keys off the NODE origin, so the node is
## re-anchored at the transforms' centroid (instance transforms made relative):
## the fade then measures from the feature itself, not world zero.
func _add_multimesh(mesh: Mesh, transforms: Array[Transform3D], material: Material,
		name_hint: String, shadows: bool = true, range_base: float = 0.0) -> void:
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


## The hollow's walls. Slabs of fluted blue ice chained along BOTH sides of the
## whole route so the course is a place with sides rather than a ribbon in the
## dark — this is the single load-bearing piece of dressing on the course.
##
## Slabs are proportioned like rock, not like scenery flats: a first pass ran
## them 20m wide and 70m tall (footed all the way down to the hollow floor) and
## the result was a picket fence of paper blades with black sky between them.
## They now sit close to the deck, start 11m under it and rise 20-32m, capped
## at WALL_MAX_STRETCH so no slab ever grows past about twice its own width.
## Three cached mesh variants through one MultiMesh each, one shared material.
const WALL_MAX_STRETCH: float = 1.5


func _decorate_walls(density: float) -> void:
	var buckets: Array = [[], [], []]
	# Dense on purpose: neighbouring slabs have to OVERLAP, or the gaps between
	# them are windows onto empty fog and the hollow stops being enclosed.
	var step := 10.0 / maxf(density, 0.5)
	# The whole route is walled except the lake (open water both sides) and the
	# outwash plain past the chute, where the glacier is behind the racer.
	var lake_start := _offset_near(Vector3(-2, 21.4, -838)) - 16.0
	var lake_end := _offset_near(Vector3(0, 21.4, -952)) + 8.0
	var daylight := _offset_near(Vector3(-8, 3.5, -1346))
	var offset := 8.0
	while offset < daylight:
		if offset > lake_start and offset < lake_end:
			offset += step
			continue
		for side: float in [-1.0, 1.0]:
			var xform := main_guide.transform_at(offset)
			# Hard against the deck edge: this is a slot, and a wall standing
			# 6m back from the boundary reads as a distant cliff instead.
			var lateral := (track_edge_lateral(main_guide, offset, side, 9.0)
				+ rng.randf_range(1.8, 2.6)) * side
			var pos := xform.origin + xform.basis.x * lateral + Vector3.DOWN * 11.0
			var toward := -xform.basis.x * side
			var yaw := atan2(toward.x, toward.z) + rng.randf_range(-0.06, 0.06)
			var slab_width := rng.randf_range(24.0, 32.0)
			var authored_height := rng.randf_range(20.0, 32.0)
			var slab_depth := rng.randf_range(8.0, 12.0)
			var footed := clampf(authored_height, authored_height, slab_width * WALL_MAX_STRETCH)
			var slab_basis := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(slab_width, footed, slab_depth))
			(buckets[rng.randi_range(0, 2)] as Array).append(Transform3D(slab_basis, pos))
		offset += step
	var wall_mat := VisualLibrary.rock_material(Color(1.0, 1.0, 1.0), 0.28, 0.04)
	for v: int in 3:
		var typed: Array[Transform3D] = []
		for t: Transform3D in buckets[v] as Array:
			typed.append(t)
		_add_multimesh(_wall_mesh(6100 + v), typed, wall_mat, "HollowWall_%d" % v, false)


## Unit-scale fluted ice wall slab: x -0.5..0.5, y 0..~1, track-facing side
## toward +Z, backed out to z = -0.5. Meltwater carves flutes into cave ice, so
## the face is a run of columns at varying depths with a scoured waterline at
## the foot, a mid band of deep compressed blue and a pale rime crest, with
## crevice returns between columns.
##
## CLOSED on purpose: the first version was a face and nothing else, and a
## single-sided plane scaled 20m wide reads as a cardboard flat the moment the
## camera sees it at an angle — which, on a course whose whole job is to feel
## enclosed, is fatal. Back face, end caps and a crest shelf give it real
## thickness for about sixty extra triangles. Deterministic per seed; vertex
## colors carry all of it.
func _wall_mesh(seed_value: int) -> ArrayMesh:
	var mrng := RandomNumberGenerator.new()
	mrng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 10
	var back_z := -0.5
	var deep := Color(0.02, 0.13, 0.3)
	var body := Color(0.1, 0.34, 0.58)
	var rime := Color(0.62, 0.78, 0.94)
	var scour := Color(0.05, 0.2, 0.36)
	var hidden := Color(0.02, 0.07, 0.16)
	var front_z: Array[float] = []
	var tops: Array[float] = []
	for i: int in cols:
		front_z.append(mrng.randf_range(0.0, 0.22))
		tops.append(mrng.randf_range(0.78, 1.0))
	for i: int in cols:
		var x0 := -0.5 + float(i) / float(cols)
		var x1 := -0.5 + float(i + 1) / float(cols)
		var z := front_z[i]
		var top := tops[i]
		var flute := mrng.randf_range(0.5, 1.15)
		var face := body.lerp(deep, 1.0 - flute)
		var y_scour := mrng.randf_range(0.1, 0.2)
		var y_rime := top - mrng.randf_range(0.06, 0.14)
		# Column front: scoured waterline -> compressed blue body -> rime crest.
		_cquad(st, Vector3(x0, 0.0, z), Vector3(x1, 0.0, z), Vector3(x1, y_scour, z), Vector3(x0, y_scour, z), scour)
		_cquad(st, Vector3(x0, y_scour, z), Vector3(x1, y_scour, z), Vector3(x1, y_rime, z), Vector3(x0, y_rime, z), face)
		_cquad(st, Vector3(x0, y_rime, z), Vector3(x1, y_rime, z), Vector3(x1, top, z), Vector3(x0, top, z),
			face.lerp(rime, 0.8))
		# Crest shelf running back to the slab's spine, so looking up at the
		# wall from the deck shows a snow-lipped top rather than a cut edge.
		_cquad(st, Vector3(x0, top, z), Vector3(x1, top, z),
			Vector3(x1, top, back_z), Vector3(x0, top, back_z), rime)
		# Back face and the two end caps: cheap, and the only thing standing
		# between the player and seeing straight through the wall.
		_cquad(st, Vector3(x1, 0.0, back_z), Vector3(x0, 0.0, back_z),
			Vector3(x0, top, back_z), Vector3(x1, top, back_z), hidden)
		if i == 0:
			_cquad(st, Vector3(x0, 0.0, back_z), Vector3(x0, 0.0, z),
				Vector3(x0, top, z), Vector3(x0, top, back_z), face.lerp(deep, 0.5))
		if i == cols - 1:
			_cquad(st, Vector3(x1, 0.0, z), Vector3(x1, 0.0, back_z),
				Vector3(x1, top, back_z), Vector3(x1, top, z), face.lerp(deep, 0.5))
		if i > 0:
			# Crevice return between neighbouring columns, both windings so an
			# oblique view never sees through the step.
			var crevice := Color(face.r * 0.35, face.g * 0.4, face.b * 0.55)
			var hi := maxf(top, tops[i - 1])
			var pz := front_z[i - 1]
			_cquad(st, Vector3(x0, 0.0, pz), Vector3(x0, 0.0, z), Vector3(x0, hi, z), Vector3(x0, hi, pz), crevice)
			_cquad(st, Vector3(x0, 0.0, z), Vector3(x0, 0.0, pz), Vector3(x0, hi, pz), Vector3(x0, hi, z), crevice)
	st.generate_normals()
	return st.commit()


## Roof vaults over the three spans that are genuinely enclosed: the staging
## hall, the icicle gallery and the crystal cathedral. Smooth high-segment
## tori, so the arch reads as a curved ceiling rather than a faceted hoop; the
## lower half sits under the deck and is never seen. Every vault hangs a
## fringe of icicles from its crown, which is what sells the clearance.
func _decorate_vaults(icicles: Array[Transform3D]) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 10.5
	torus.outer_radius = 13.5
	torus.rings = 48
	torus.ring_segments = 14
	var vault_mat := VisualLibrary.ice_material(Color(0.14, 0.42, 0.72), 0.85)
	var spans: Array[Vector2] = [
		Vector2(6.0, _offset_near(Vector3(-2, 44.5, -82))),
		Vector2(_offset_near(Vector3(-16, 41.5, -132)), _offset_near(Vector3(-8, 34.0, -274))),
		Vector2(_offset_near(Vector3(10, 32.5, -322)) - 8.0, _offset_near(Vector3(16, 30.5, -430))),
		Vector2(_offset_near(Vector3(4, 22.4, -1002)), _offset_near(Vector3(22, 23.6, -1104))),
	]
	for span: Vector2 in spans:
		var offset := span.x
		while offset < span.y:
			var xform := main_guide.transform_at(offset)
			var arch := MeshInstance3D.new()
			arch.mesh = torus
			arch.material_override = vault_mat
			arch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			arch.transform = Transform3D(
				xform.basis.rotated(xform.basis.x, deg_to_rad(90.0)), xform.origin + Vector3.UP * 1.0)
			VisualLibrary.apply_dressing_range(arch, 300.0)
			add_child(arch)
			for _k: int in 4:
				var hang := xform.origin + xform.basis.x * rng.randf_range(-6.0, 6.0) \
					+ Vector3.UP * rng.randf_range(7.5, 10.0) \
					+ xform.basis.z * rng.randf_range(-2.0, 2.0)
				icicles.append(_icicle_transform(hang, rng.randf_range(1.1, 2.4)))
			offset += 19.0


## Floor-to-ceiling ice columns: where a vault's drip line has been feeding a
## stalagmite for a few thousand years, the two have met. Placed just outside
## the deck edge in the cathedral and the staging hall, tall enough to break
## the roof line, and always clear of the racing floor.
func _decorate_pillars(density: float) -> void:
	var transforms: Array[Transform3D] = []
	var spans: Array[Vector2] = [
		Vector2(_offset_near(Vector3(4, 22.4, -1002)), _offset_near(Vector3(22, 23.6, -1104))),
		Vector2(10.0, _offset_near(Vector3(-2, 44.5, -82))),
	]
	for span: Vector2 in spans:
		var offset := span.x + 8.0
		while offset < span.y - 6.0:
			for side: float in [-1.0, 1.0]:
				if rng.randf() < 0.35:
					continue
				var xform := main_guide.transform_at(offset)
				var lateral := (track_edge_lateral(main_guide, offset, side, 9.0)
					+ rng.randf_range(1.2, 3.4)) * side
				var height := rng.randf_range(9.0, 16.0)
				var radius := rng.randf_range(0.7, 1.6)
				var pillar_basis := Basis(Vector3.UP, rng.randf() * TAU) \
					* Basis.from_scale(Vector3(radius, height, radius))
				transforms.append(Transform3D(pillar_basis,
					seat_dressing(xform, lateral, height, 5.0, 0.06)))
			offset += 16.0 / maxf(density, 0.5)
	_add_multimesh(_pillar_mesh(7250), transforms,
		VisualLibrary.ice_material(Color(0.3, 0.6, 0.88), 0.7), "IcePillars", false, 340.0)


## Unit ice column: an eight-sided taper from a flared drip foot to a narrow
## waist and back out to a ceiling flare, with per-facet tone jitter and
## horizontal growth banding baked in. x/z within +/-0.5, y 0..1.
func _pillar_mesh(seed_value: int) -> ArrayMesh:
	var mrng := RandomNumberGenerator.new()
	mrng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 8
	var bands := 7
	var pale := Color(0.72, 0.88, 1.0)
	var blue := Color(0.16, 0.44, 0.7)
	var wobble: Array[float] = []
	for i: int in sides:
		wobble.append(mrng.randf_range(0.82, 1.18))
	var rings: Array[PackedVector3Array] = []
	for b: int in bands + 1:
		var t := float(b) / float(bands)
		# Hourglass profile: flared at both ends, pinched at the waist.
		var radius := 0.5 * (0.42 + 0.58 * pow(absf(t - 0.48) * 2.0, 1.6)) * mrng.randf_range(0.94, 1.06)
		var ring := PackedVector3Array()
		for i: int in sides:
			var angle := TAU * float(i) / float(sides)
			ring.append(Vector3(cos(angle) * radius * wobble[i], t, sin(angle) * radius * wobble[i]))
		rings.append(ring)
	for b: int in bands:
		var shade := mrng.randf_range(0.75, 1.05)
		for i: int in sides:
			var j := (i + 1) % sides
			var tone := blue.lerp(pale, clampf(float(b) / float(bands) * 0.5 + mrng.randf_range(0.1, 0.5), 0.0, 1.0))
			tone = Color(tone.r * shade, tone.g * shade, tone.b)
			_cquad(st, rings[b][i], rings[b][j], rings[b + 1][j], rings[b + 1][i], tone)
	st.generate_normals()
	return st.commit()


## Glowing crystal veins: the hollow's only real light source and its whole
## navigation language. Clusters cling to the wall bases along the entire
## route (thicker where the course needs reading — the slot bends, the gallery,
## the draught, the cathedral), plus a ring of monoliths around the cathedral.
func _decorate_crystals(density: float, transforms: Array[Transform3D]) -> void:
	var step := 10.0 / maxf(density, 0.5)
	var offset := 20.0
	var daylight := _offset_near(Vector3(-8, 3.5, -1346))
	while offset < daylight:
		for side: float in [-1.0, 1.0]:
			if rng.randf() < 0.4:
				continue
			var xform := main_guide.transform_at(offset)
			var lateral := (track_edge_lateral(main_guide, offset, side, 9.0)
				+ rng.randf_range(0.15, 0.9)) * side
			transforms.append(_crystal_transform(
				seat_dressing(xform, lateral, 2.6, 5.0, 0.12), rng.randf_range(1.6, 3.4)))
		offset += step
	# Cathedral monoliths: landmark scale, so the room reads as the one big
	# space on the course rather than another stretch of corridor.
	var cathedral_start := _offset_near(Vector3(4, 22.4, -1002))
	var cathedral_end := _offset_near(Vector3(22, 23.6, -1104))
	var mono_offset := cathedral_start
	while mono_offset < cathedral_end:
		for side: float in [-1.0, 1.0]:
			var xform := main_guide.transform_at(mono_offset)
			var lateral := (track_edge_lateral(main_guide, mono_offset, side, 9.0)
				+ rng.randf_range(0.3, 1.1)) * side
			transforms.append(_crystal_transform(
				seat_dressing(xform, lateral, 6.0, 5.0, 0.1), rng.randf_range(4.5, 7.5)))
		mono_offset += 21.0


## Ground crystal cluster: random yaw, a slight natural tilt off vertical
## (frost heave, uneven bedding) and per-cluster aspect jitter so no two
## clusters share one silhouette.
func _crystal_transform(pos: Vector3, height: float) -> Transform3D:
	var aspect := rng.randf_range(0.5, 0.85)
	var tilt_dir := rng.randf() * TAU
	var tilt_axis := Vector3(cos(tilt_dir), 0.0, sin(tilt_dir))
	var crystal_basis := Basis(tilt_axis, rng.randf_range(-0.16, 0.16)) \
		* Basis(Vector3.UP, rng.randf() * TAU) \
		* Basis.from_scale(Vector3(height * aspect, height * rng.randf_range(0.85, 1.15), height * aspect))
	return Transform3D(crystal_basis, pos)


## Hanging icicle: the shared crystal mesh flipped upside-down. pos is the
## attachment point (a vault crown, a wall crest); the tip reaches height below.
func _icicle_transform(pos: Vector3, height: float) -> Transform3D:
	var icicle_basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, PI) \
		* Basis.from_scale(Vector3(height * 0.4, height, height * 0.4))
	return Transform3D(icicle_basis, pos)


## Icicle curtains hanging off the wall crests along the open (unvaulted)
## stretches, so the roof line reads as ice even where there is no roof mesh.
## They hang well above racer height and never over the racing floor.
func _decorate_wall_icicles(density: float, transforms: Array[Transform3D]) -> void:
	var step := 13.0 / maxf(density, 0.5)
	var offset := _offset_near(Vector3(-16, 41.5, -132))
	var stop := _offset_near(Vector3(2, 21.8, -800))
	while offset < stop:
		for side: float in [-1.0, 1.0]:
			if rng.randf() < 0.45:
				continue
			var xform := main_guide.transform_at(offset)
			var lateral := (track_edge_lateral(main_guide, offset, side, 9.0)
				+ rng.randf_range(0.2, 1.2)) * side
			var hang := xform.origin + xform.basis.x * lateral \
				+ Vector3.UP * rng.randf_range(6.0, 11.0)
			transforms.append(_icicle_transform(hang, rng.randf_range(0.8, 2.6)))
		offset += step


## Moraine: the grit and shattered rock a glacier carries inside itself,
## thawed out of the walls and lying along the shoulders. Dark, matte and
## irregular — the one warm-neutral note in an entirely blue course, which is
## what stops the palette reading as a colour filter.
func _decorate_moraine(density: float) -> void:
	var rocks: Array[Transform3D] = []
	var count := int(40.0 * density)
	for _i: int in count:
		var offset := rng.randf_range(40.0, main_guide.length - 60.0)
		var xform := main_guide.transform_at(offset)
		var side := 1.0 if rng.randf() > 0.5 else -1.0
		var lateral := (track_edge_lateral(main_guide, offset, side, 9.0)
			+ rng.randf_range(0.6, 4.0)) * side
		var s := rng.randf_range(0.5, 1.7)
		var squash := Vector3(rng.randf_range(0.8, 1.4), rng.randf_range(0.5, 0.9),
			rng.randf_range(0.8, 1.4)) * s
		var rock_basis := Basis.from_euler(Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU,
			rng.randf_range(-0.4, 0.4))).scaled(squash)
		rocks.append(Transform3D(rock_basis,
			seat_dressing(xform, lateral, squash.y, 4.5, 0.14) + Vector3.UP * (squash.y * 0.4)))
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 0.8
	rock_mesh.height = 1.2
	rock_mesh.radial_segments = 7
	rock_mesh.rings = 4
	_add_multimesh(rock_mesh, rocks, TrackBuilder.prop_material(Color(0.16, 0.16, 0.18), 1.0), "Moraine")


## Snow cones: where the roof has opened somewhere above, a cone of blown snow
## has built up on the cavern floor beside the track. Every one the racers can
## reach is also a ploughing volume, so clipping one costs real speed — the
## drawn thing and the felt thing come from one transform.
func _decorate_snow_cones(density: float) -> void:
	var transforms: Array[Transform3D] = []
	var step := 21.0 / density
	var offset := 30.0
	var side := 1.0
	while offset < main_guide.length - 30.0:
		var xform := main_guide.transform_at(offset)
		var lateral := (track_edge_lateral(main_guide, offset, side, 9.0)
			+ rng.randf_range(0.5, 2.6)) * side
		var r := rng.randf_range(1.4, 3.0)
		var cone_basis := Basis(Vector3.UP, rng.randf() * TAU) \
			* Basis.from_scale(Vector3(r, r * rng.randf_range(0.5, 0.85), r * rng.randf_range(0.85, 1.1)))
		var cone_xform := Transform3D(cone_basis,
			seat_dressing(xform, lateral, cone_basis.get_scale().y, 5.0, 0.14))
		transforms.append(cone_xform)
		add_snow_drift(cone_xform)
		side = -side
		offset += step
	_add_multimesh(VisualLibrary.snow_drift_mesh(), transforms,
		VisualLibrary.rock_material(Color(0.82, 0.9, 1.0)), "SnowCones")


## Route markers: survey stakes with a cold glow lamp, planted every ~64m on
## alternating sides, with dense clusters bracketing the grid and the finish.
## On a course this dark they are the primary read of where the track goes
## before the geometry resolves out of the fog.
func _decorate_markers() -> void:
	var post_transforms: Array[Transform3D] = []
	var lamp_transforms: Array[Transform3D] = []
	var offset := 50.0
	var side := 1.0
	while offset < main_guide.length - 50.0:
		_add_marker(post_transforms, lamp_transforms, offset, side)
		side = -side
		offset += 64.0
	for i: int in 5:
		for cluster_side: float in [-1.0, 1.0]:
			_add_marker(post_transforms, lamp_transforms, 10.0 + float(i) * 12.0, cluster_side)
			_add_marker(post_transforms, lamp_transforms, finish_offset - 8.0 - float(i) * 13.0, cluster_side)
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.06
	post_mesh.bottom_radius = 0.09
	post_mesh.height = 3.0
	post_mesh.radial_segments = 6
	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.24
	lamp_mesh.height = 0.48
	lamp_mesh.radial_segments = 8
	lamp_mesh.rings = 5
	_add_multimesh(post_mesh, post_transforms,
		TrackBuilder.prop_material(Color(0.2, 0.24, 0.3), 0.9), "MarkerPosts")
	_add_multimesh(lamp_mesh, lamp_transforms,
		VisualLibrary.emissive_material(Color(0.5, 0.9, 1.0), CRYSTAL_GLOW, 1.3), "MarkerLamps", false)


func _add_marker(posts: Array[Transform3D], lamps: Array[Transform3D], offset: float, side: float) -> void:
	if offset <= 2.0 or offset >= main_guide.length - 2.0:
		return
	var xform := main_guide.transform_at(offset)
	var lateral := (track_edge_lateral(main_guide, offset, side, 9.0) + rng.randf_range(0.7, 1.8)) * side
	var base := seat_dressing(xform, lateral, 3.0)
	var yaw := Basis(Vector3.UP, rng.randf() * TAU)
	posts.append(Transform3D(yaw, base + Vector3.UP * 1.5))
	lamps.append(Transform3D(yaw, base + Vector3.UP * 3.1))


## Lake shore: a rim of pale ice rubble around the water, foam bands lying on
## the surface, and the cold breath rising off it. The swim is the quietest
## thirty seconds on the course and the shore is what gives it a place.
func _decorate_lake_shore(density: float) -> void:
	var rubble: Array[Transform3D] = []
	var edge := _offset_near(Vector3(-4, 21.0, -866))
	var far_edge := _offset_near(Vector3(-3, 19.2, -919))
	var offset := edge - 30.0
	while offset < far_edge + 30.0:
		for side: float in [-1.0, 1.0]:
			var count := rng.randi_range(2, 4)
			for _k: int in count:
				var xform := main_guide.transform_at(offset)
				var lateral := (9.0 + rng.randf_range(1.0, 14.0)) * side
				var s := rng.randf_range(0.8, 2.6)
				var chunk_basis := Basis.from_euler(Vector3(rng.randf_range(-0.5, 0.5),
					rng.randf() * TAU, rng.randf_range(-0.5, 0.5))) \
					* Basis.from_scale(Vector3(s, s * rng.randf_range(0.5, 0.9), s))
				var pos := xform.origin + xform.basis.x * lateral
				rubble.append(Transform3D(chunk_basis, Vector3(pos.x, LAKE_Y - 0.3, pos.z)))
		offset += 12.0 / maxf(density, 0.5)
	_add_multimesh(VisualLibrary.berg_mesh(17), rubble,
		VisualLibrary.ice_material(Color(0.42, 0.68, 0.92), 0.6), "LakeRubble", false, 300.0)
	# Foam bands lying flat on the water where the swell meets the shelf.
	var foam_mat := StandardMaterial3D.new()
	foam_mat.albedo_color = Color(0.7, 0.88, 1.0, 0.28)
	foam_mat.albedo_texture = VisualLibrary.soft_radial_texture(64, 0.75)
	foam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	foam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	foam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	for k: int in 4:
		var band := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(rng.randf_range(24.0, 42.0), rng.randf_range(9.0, 16.0))
		band.mesh = plane
		band.material_override = foam_mat
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var anchor := main_guide.point_at(lerpf(edge, far_edge, float(k) / 3.0), 0.0, 0.0)
		band.position = Vector3(anchor.x + rng.randf_range(-6.0, 6.0), LAKE_Y + 0.1,
			anchor.z + rng.randf_range(-6.0, 6.0))
		band.rotation.y = rng.randf() * TAU
		add_child(band)


## Ice glints: cold pinpoints caught deep in the walls, clustered through the
## slot, the gallery and the cathedral the way real blue ice fires highlights
## as the view angle sweeps past. Alpha stays under the glow threshold — the
## crystals are the light, these are only the sparkle. One draw call.
func _decorate_glints(density: float) -> void:
	var transforms: Array[Transform3D] = []
	var offset := 20.0
	var stop := _offset_near(Vector3(22, 23.6, -1104))
	while offset < stop:
		for side: float in [-1.0, 1.0]:
			if rng.randf() < 0.35:
				continue
			var xform := main_guide.transform_at(offset)
			var s := rng.randf_range(0.4, 1.2)
			var pos := xform.origin + xform.basis.x * (rng.randf_range(8.0, 10.5) * side) \
				+ Vector3.UP * rng.randf_range(0.6, 9.0)
			transforms.append(Transform3D(Basis.from_scale(Vector3(s, s, s)), pos))
		offset += 7.5 / maxf(density, 0.5)
	var glint_mat := StandardMaterial3D.new()
	glint_mat.albedo_color = Color(0.4, 0.78, 1.0, 0.42)
	glint_mat.albedo_texture = VisualLibrary.soft_radial_texture(32, 0.9)
	glint_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glint_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glint_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glint_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glint_mat.billboard_keep_scale = true
	glint_mat.disable_receive_shadows = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_add_multimesh(quad, transforms, glint_mat, "WallGlints", false, 260.0)


## Spectator penguins: crowds at the grid and the finish, plus a knot on the
## cathedral shoulder — the only room in the hollow with space to stand in.
func _decorate_spectators(density: float) -> void:
	var start_count := maxi(int(15.0 * density), 6)
	for i: int in start_count:
		var arc := rng.randf_range(10.0, 80.0)
		var xform := main_guide.transform_at(arc)
		var side := 1.0 if i % 2 == 0 else -1.0
		var lateral := (track_edge_lateral(main_guide, arc, side, 9.0)
			+ rng.randf_range(0.7, 4.0)) * side
		TrackBuilder.add_spectator(self, seat_dressing(xform, lateral, 1.6, GROUND_SHOULDER, 0.05),
			xform.origin, rng)
	var finish_count := maxi(int(14.0 * density), 6)
	for i: int in finish_count:
		var arc := finish_offset - rng.randf_range(5.0, 70.0)
		var xform := main_guide.transform_at(arc)
		var side := 1.0 if i % 2 == 0 else -1.0
		var lateral := (track_edge_lateral(main_guide, arc, side, 9.0)
			+ rng.randf_range(0.7, 5.0)) * side
		TrackBuilder.add_spectator(self, seat_dressing(xform, lateral, 1.6, GROUND_SHOULDER, 0.05),
			xform.origin, rng)
	var overlook := _offset_near(Vector3(16, 23.4, -1052))
	var overlook_count := maxi(int(6.0 * density), 3)
	for _i: int in overlook_count:
		var arc := overlook + rng.randf_range(-25.0, 25.0)
		var xform := main_guide.transform_at(arc)
		var lateral := -(track_edge_lateral(main_guide, arc, -1.0, 9.0) + rng.randf_range(1.0, 4.0))
		TrackBuilder.add_spectator(self, seat_dressing(xform, lateral, 1.6, GROUND_SHOULDER, 0.05),
			xform.origin, rng)


## Cold mist: the breath of a humid cave, pooling in the slot, over the lake
## and in the cathedral. Soft unshaded billboards on slow drift tweens; skipped
## entirely on low particle quality, where the environment's height fog is
## already carrying the mood.
func _decorate_mist(density: float) -> void:
	if density <= 0.5:
		return
	var mist_mat := StandardMaterial3D.new()
	mist_mat.albedo_color = Color(0.55, 0.76, 0.95, 0.15)
	mist_mat.albedo_texture = VisualLibrary.soft_radial_texture(64, 0.8)
	mist_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mist_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mist_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var regions: Array[Vector2] = [
		Vector2(_offset_near(Vector3(-16, 41.5, -132)), _offset_near(Vector3(-8, 34.0, -274))),
		Vector2(_offset_near(Vector3(-2, 21.4, -838)), _offset_near(Vector3(0, 21.4, -952))),
		Vector2(_offset_near(Vector3(4, 22.4, -1002)), _offset_near(Vector3(22, 23.6, -1104))),
	]
	var per_region := maxi(int(5.0 * density), 2)
	for region: Vector2 in regions:
		for _i: int in per_region:
			var offset := rng.randf_range(region.x, region.y)
			var lateral := rng.randf_range(7.0, 16.0) * (1.0 if rng.randf() > 0.5 else -1.0)
			var pos := main_guide.point_at(offset, lateral, rng.randf_range(0.7, 2.4))
			var wisp := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(rng.randf_range(12.0, 22.0), rng.randf_range(3.5, 6.5))
			wisp.mesh = quad
			wisp.material_override = mist_mat
			wisp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			wisp.position = pos
			add_child(wisp)
			if UITheme.reduced_motion():
				continue
			var drift := Vector3(rng.randf_range(-5.0, 5.0), rng.randf_range(0.2, 0.6),
				rng.randf_range(-4.0, 4.0))
			var dur := rng.randf_range(8.0, 14.0)
			var tw := wisp.create_tween()
			tw.set_loops()
			tw.tween_property(wisp, "position", pos + drift, dur) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw.tween_property(wisp, "position", pos, dur) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## --- Baked-color mesh helpers ------------------------------------------------

## Quad as two front-facing triangles; corners given as (bottom-left,
## bottom-right, top-right, top-left) from the viewpoint of the visible side.
static func _cquad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_ctri(st, a, d, c, color)
	_ctri(st, a, c, b, color)


static func _ctri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	st.set_color(color)
	st.add_vertex(a)
	st.set_color(color)
	st.add_vertex(b)
	st.set_color(color)
	st.add_vertex(c)
