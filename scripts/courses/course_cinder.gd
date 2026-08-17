class_name CourseCinder
extends CourseBase
## CINDER COAST: dusk on the geothermal side of the island, where the ice sheet
## runs out onto black volcanic sand. A glassy obsidian ramp off the lava
## terrace, a long sweeping black-sand shore arc past basking seals, a crust
## shortcut over a boiling mud pool, a drifting-floe hop across the steam
## lagoon, a fumarole flat that launches racers off six steam vents, a heavy
## ash climb onto the scoria ridge, and a long glazed-lava chute back down to
## the surf. Warm dusk grade: ember horizon under a slate sky, low amber key
## light raking the basalt, steam and ash haze instead of clean polar air.
##
## Deliberately NOT another white course: the ground reads dark, the light
## reads warm, and the hazard mix is led by steam vents rather than ice.

const SNOW := SurfacesDB.Surface.PACKED_SNOW
const DEEP := SurfacesDB.Surface.DEEP_SNOW
const ICE := SurfacesDB.Surface.ICE_SMOOTH
const RICE := SurfacesDB.Surface.ICE_ROUGH

## Sea level. The shore plateau sits ~3m over it at the finish and the lava
## terrace ~25m over it at the grid, so the whole course reads as one bench
## stepping down to the water.
const SEA_Y: float = -1.0

## Onshore breeze heading (world yaw, degrees). Ash drifts, steam plumes and
## the sand ripples all streamline along this axis; it sits ~55 degrees off the
## sun yaw so their lee faces model in shadow instead of flattening out.
const BREEZE_YAW_DEG: float = 96.0

## Yaw of the dusk sun (must match the build_environment sun_yaw_deg). The
## ember rim tints, the sea glitter band and the backlit steam all key off it.
const SUN_YAW_DEG: float = 152.0

## Track albedo. Under a warm low key light the stock snow/ice tints tone-map
## to pink concrete, and this course's whole point is that the ground is dark:
## the deck is basalt sand with an ash-grey ice glaze, so racers, fish and the
## amber boost pads all separate against it.
const TRACK_SAND_TINT: Color = Color(0.22, 0.20, 0.21)
const TRACK_GLAZE_TINT: Color = Color(0.17, 0.23, 0.31)
const TRACK_CRUST_TINT: Color = Color(0.40, 0.40, 0.43)
## Sinter crust: the pale mineral rind around a hot spring. Used for the ash
## climb so the deep-ash section still reads as a different material.
const TRACK_ASH_TINT: Color = Color(0.46, 0.42, 0.40)

## Warm rim for sun-facing basalt edges and the ember fissures.
const EMBER: Color = Color(1.0, 0.42, 0.12)


func _init() -> void:
	course_id = "cinder"


static func p(x: float, y: float, z: float, extra: Dictionary = {}) -> Dictionary:
	var d := {"pos": Vector3(x, y, z)}
	d.merge(extra)
	return d


func build_course() -> void:
	var pts: Array = [
		# 1) Lava terrace: long straight for the grid, then a glassy obsidian
		# ramp down to the beach. The ramp is smooth ice — an early slide
		# reward on a dead-straight descent, well before the shore arc asks
		# for any steering.
		p(0, 26, 35, {"width": 18.0}),
		p(0, 26, -25, {"width": 18.0}),
		p(2, 22, -95, {"width": 20.0, "surface": ICE}),
		p(8, 17, -160, {"width": 20.0}),
		# 2) Black-sand shore arc: one long right-hand sweep along the surf
		# line, wide and fast, undulating over old lava benches. wall_l opens
		# at the mouth and the merge of the crust shortcut, which peels off
		# inland on the left.
		p(26, 14.5, -225, {"width": 20.0, "wall_l": false}),
		p(48, 13.0, -290, {"width": 18.0}),
		p(58, 12.0, -360, {"width": 18.0}),
		p(50, 11.0, -430, {"width": 20.0, "wall_l": false}),
		p(30, 10.5, -490, {"width": 20.0}),
		# 3) Steam lagoon: the sand runs out and the crossing is bridged by
		# drifting ice floes. The bench rise at -540 doubles as the launch
		# hump into the jump.
		p(14, 10.0, -540, {"width": 16.0}),
		p(6, 9.6, -570, {"width": 14.0}),
		p(2, 9.4, -596, {"width": 12.0, "gap": true}),
		p(0, 9.4, -628, {"width": 14.0}),
		# 4) Fumarole flat: a wide, gently falling basalt shelf with six steam
		# vents on it. Wide on purpose — the vents launch, and a launch has to
		# land somewhere forgiving.
		p(0, 9.0, -660, {"width": 20.0}),
		p(-6, 8.4, -720, {"width": 22.0}),
		p(-8, 7.6, -790, {"width": 22.0}),
		p(-4, 7.0, -860, {"width": 20.0}),
		# 5) Ash climb: heavy volcanic ash up onto the scoria ridge (+10m over
		# ~100m). Deep-snow physics — this is the one place the course asks
		# racers to grind rather than flow.
		p(6, 9.5, -915, {"width": 16.0, "surface": DEEP}),
		p(18, 13.5, -965, {"width": 16.0, "surface": DEEP}),
		p(24, 17.0, -1010, {"width": 16.0}),
		# 6) Scoria ridge traverse: a left sweep over the crest of the old
		# cone, then onto the glazed lava crust.
		p(20, 19.5, -1060, {"width": 16.0}),
		p(4, 21.0, -1110, {"width": 16.0}),
		p(-14, 20.0, -1160, {"width": 18.0, "surface": ICE}),
		# 7) Obsidian chute: 18m of sustained drop back to the surf at about
		# -6 degrees, iced end to end so the slide starts at the crest and
		# carries all the way to the line.
		p(-24, 15.5, -1215, {"width": 18.0, "surface": ICE}),
		p(-26, 9.5, -1275, {"width": 18.0, "surface": ICE}),
		p(-18, 4.5, -1330, {"width": 18.0, "surface": ICE}),
		p(-6, 2.5, -1385, {"width": 18.0, "surface": ICE}),
		# 8) Shore straight to the finish banner.
		p(0, 2.0, -1440, {"width": 18.0}),
		p(0, 2.0, -1500, {"width": 18.0}),
	]
	setup_main(pts)

	# Crust shortcut: a mineral sinter shelf running inland across a boiling
	# mud pool. Narrow, no walls, and the pool span has no floor at all — only
	# cracking crust tiles bridge it, so speed is the only thing keeping a
	# racer out of the mud.
	var branch_pts: Array = [
		p(24, 14.2, -238, {"width": 10.0, "surface": ICE, "wall_l": false, "wall_r": false}),
		p(18, 12.9, -300, {"width": 8.0, "surface": ICE, "wall_l": false, "wall_r": false}),
		p(16, 12.2, -352, {"width": 8.0, "gap": true, "wall_l": false, "wall_r": false}),
		p(18, 11.5, -412, {"width": 8.0, "surface": ICE, "wall_l": false, "wall_r": false}),
		p(24, 10.9, -468, {"width": 10.0, "surface": ICE, "wall_l": false, "wall_r": false}),
	]
	var shortcut := add_branch(branch_pts, 0.6, "crust_shelf")

	finalize()

	# --- Geometry-derived offsets ------------------------------------------
	var ramp := _offset_near(Vector3(2, 22, -95))
	var beach_in := _offset_near(Vector3(26, 14.5, -225))
	var beach_apex := _offset_near(Vector3(58, 12.0, -360))
	var beach_out := _offset_near(Vector3(30, 10.5, -490))
	var lagoon_edge := _offset_near(Vector3(2, 9.4, -596))
	var flat_start := _offset_near(Vector3(0, 9.0, -660))
	var flat_end := _offset_near(Vector3(-4, 7.0, -860))
	var ash_start := _offset_near(Vector3(6, 9.5, -915))
	var ridge_crest := _offset_near(Vector3(4, 21.0, -1110))
	var chute_start := _offset_near(Vector3(-14, 20.0, -1160))
	var chute_end := _offset_near(Vector3(-6, 2.5, -1385))

	# --- Steam lagoon: three drifting floes ---------------------------------
	# The first floe is anchored (fast ice) so the crossing is survivable at
	# any arrival phase; the two behind it drift laterally on the lagoon
	# current, which is the actual skill element.
	add_hint(lagoon_edge - 2.0, "jump")
	var floe_periods: Array[float] = [4.6, 5.4, 6.2]
	var floe_phases: Array[float] = [0.0, 1.9, 3.8]
	for i: int in 3:
		var floe := HazardPlatform.new()
		var drift := 0.0 if i == 0 else 2.4
		floe.configure(Vector3(13.0, 0.8, 11.0), Vector3.RIGHT, drift, floe_periods[i], 0.0, floe_phases[i],
			{"heave": 0.26, "heave_freq": 0.55, "yaw_deg": 6.0, "yaw_freq": 0.42, "variance": 0.12, "seed": 140 + i})
		floe.position = Vector3(1.0, 9.0, -599.0 - 10.0 * float(i))
		add_child(floe)

	# --- Fumarole flat: six steam vents, staggered lanes and phases ---------
	# Laterals stay inside +/-5 on a 20-22m deck: a vent near the edge throws
	# racers off the shelf instead of down the track, which is a launch pad,
	# not a hazard. Phases are spread so the flat never fires as one wall.
	var vent_laterals: Array = [-4.5, 3.5, -1.0, 4.5, -3.5, 1.5]
	var vent_phases: Array = [0.0, 1.1, 2.0, 0.6, 2.6, 1.6]
	for i: int in 6:
		var vent := HazardGeyser.new()
		vent.phase_offset = float(vent_phases[i])
		# Clamped to the shelf: a vent that drifts past the flat onto the ash
		# climb would launch racers backwards down a grade they just fought up.
		var vent_offset := minf(flat_start + 24.0 + float(i) * 28.0, flat_end - 14.0)
		vent.position = main_guide.point_at(vent_offset, float(vent_laterals[i]), 0.0)
		add_child(vent)

	# --- Basking seals on the warm sand -------------------------------------
	# Geothermal ground is where seals actually haul out, so the shore arc is
	# where they sleep. Each gets a danger hint so the AI drifts off its lane
	# rather than bowling straight through it.
	var seal_data: Array = [
		{"pos": Vector3(44, 13.2, -272), "sweep": 7.0, "speed": 3.4, "hint": "danger_left"},
		{"pos": Vector3(57, 12.1, -350), "sweep": 8.5, "speed": 4.2, "hint": "danger_right"},
		{"pos": Vector3(46, 11.2, -448), "sweep": 7.5, "speed": 3.8, "hint": "danger_left"},
	]
	for data: Dictionary in seal_data:
		var seal := HazardSeal.new()
		var seal_offset := _offset_near(data["pos"])
		seal.configure(main_guide, seal_offset, float(data["sweep"]), float(data["speed"]))
		add_child(seal)
		add_hint(seal_offset - 35.0, String(data["hint"]), seal_offset + 8.0)

	# --- Cracking crust over the mud pool -----------------------------------
	var pool_start := float(shortcut.nearest(Vector3(16, 12.2, -352), -1)["offset"]) - 6.0
	var pool_end := float(shortcut.nearest(Vector3(18, 11.5, -412), -1)["offset"]) + 6.0
	var tile_offset := pool_start
	while tile_offset < pool_end:
		var tile := HazardCrackingIce.new()
		add_child(tile)
		tile.global_position = shortcut.point_at(tile_offset, 0.0, -0.25)
		tile_offset += 5.8
	# Survivor reward, on solid crust past the pool.
	TrackBuilder.add_boost_pad(self, shortcut, pool_end + 12.0)
	# The shelf is flat smooth ice: sliding it hard is the whole point. Branch
	# hints are matched against MAPPED main-line progress, so use entry..exit.
	var branch_entry := float(branches[0]["entry"])
	var branch_exit := float(branches[0]["exit"])
	add_hint(branch_entry + 8.0, "slide", branch_exit - 8.0, 0)

	# --- Slide hints ---------------------------------------------------------
	# Every authored ice run gets one, and only ice runs get one: sliding on
	# sand (packed snow physics) scrubs speed, so an over-long hint would make
	# the AI slower, not faster.
	add_hint(ramp - 6.0, "slide", _offset_near(Vector3(8, 17, -160)))
	add_hint(chute_start - 6.0, "slide", chute_end + 10.0)
	# The chute is long enough that a racer respawning inside it needs to
	# re-acquire the hint rather than waddle the rest of the drop.
	add_hint(_offset_near(Vector3(-26, 9.5, -1275)), "slide", chute_end + 10.0)

	# --- Boost pads ----------------------------------------------------------
	# All on straights pointing down-track, clear of the vent lanes, the floe
	# jump edge and the seal sweeps: the shore-arc entry straight, the exit
	# straight after the arc unwinds, the foot of the ash climb (extra speed
	# into a grade is always safe), and two down the obsidian chute.
	TrackBuilder.add_boost_pad(self, main_guide, _offset_near(Vector3(8, 17, -160)) + 6.0)
	TrackBuilder.add_boost_pad(self, main_guide, beach_out + 8.0)
	TrackBuilder.add_boost_pad(self, main_guide, ash_start - 8.0)
	TrackBuilder.add_boost_pad(self, main_guide, chute_start + 30.0, -3.0)
	TrackBuilder.add_boost_pad(self, main_guide, chute_start + 78.0, 3.0)

	# --- Pickups -------------------------------------------------------------
	add_item_row(115.0)
	add_item_row(beach_apex - 20.0)
	add_item_row(flat_start - 12.0)
	add_item_row(ridge_crest)
	add_item_row(chute_end + 30.0)
	add_snowball_row(150.0)
	add_snowball_row(beach_in + 30.0)
	add_snowball_row(_offset_near(Vector3(24, 17.0, -1010)))

	add_fish_line(70.0, 8, 5.0, 0.0)
	add_fish_line(beach_in + 10.0, 8, 5.0, 4.0)
	add_fish_line(20.0, 8, 6.0, 0.0, 0.0, shortcut)  # reward the crust shelf
	add_fish_line(beach_apex, 10, 5.0, -4.0)
	add_fish_line(lagoon_edge + 6.0, 6, 5.0, 0.0, 1.2)  # arc across the floes
	add_fish_line(flat_start + 30.0, 10, 5.5, 5.0)
	add_fish_line(ash_start + 10.0, 8, 5.0, 0.0)
	add_fish_line(chute_start + 40.0, 12, 5.5, 0.0)
	add_fish_line(chute_end + 40.0, 8, 5.0, 0.0)

	# The sea goes down before anything else: the surf bands, the sea stacks,
	# the far cone and every skyline form seat themselves on it.
	var sea_mat := VisualLibrary.water_material(
		Color(0.02, 0.07, 0.10), Color(0.30, 0.42, 0.40), 0.14, 0.06).duplicate() as ShaderMaterial
	# Grazing water reflects the ember dusk band, not the shared default's
	# daylight blue: the wrong sky is the loudest tell on any water sheet.
	sea_mat.set_shader_parameter("reflect_tint", Color(0.80, 0.36, 0.17, 0.8))
	add_ground_plane(SEA_Y, Color(0.05, 0.12, 0.16), 4000.0, sea_mat, true)
	_retint_track()
	_decorate()
	# Dusk on a dark coast: ember band low on the horizon under a cooling
	# slate sky, a warm low key light raking the basalt columns, restrained
	# energy so the black sand stays black instead of tone-mapping to mud, and
	# a warm steam haze thick enough to read as geothermal air. Sun energy
	# deliberately below the daylight courses — the drama here is contrast
	# between the dark ground and the ember sky, not brightness.
	build_environment({
		"sky_top": Color(0.07, 0.08, 0.17),
		"sky_horizon": Color(0.80, 0.36, 0.17),
		"ground_color": Color(0.07, 0.05, 0.05),
		"sun_angle_deg": -11.0,
		"sun_yaw_deg": SUN_YAW_DEG,
		"sun_energy": 1.22,
		"sun_color": Color(1.0, 0.70, 0.42),
		"sun_angle_max": 14.0,
		"sun_curve": 0.16,
		"sky_energy": 0.86,
		"ambient_energy": 0.78,
		"exposure": 0.90,
		"fog_color": Color(0.26, 0.19, 0.20),
		"fog_density": 0.0024,
		"fog_horizon_blend": 0.34,
		"fog_sun_scatter": 0.2,
		"fog_height": 16.0,
		"fog_height_density": 0.035,
		"glow_threshold": 1.4,
		"glow_intensity": 0.45,
		"shadow_distance": 150.0,
		"contrast": 1.12,
		"saturation": 1.05,
		"snow": false,
		"clouds": true,
		"cloud_color": Color(0.70, 0.42, 0.34, 0.8),
		"cloud_cover": 0.42,
		"cloud_streaks": 0.72,
		"fill_energy": 0.16,
		"fill_color": Color(0.32, 0.40, 0.62),
		"skyline_color": Color(0.16, 0.14, 0.16),
		"skyline_density": 0.6,
	})


func _offset_near(point: Vector3) -> float:
	return float(main_guide.nearest(point, -1)["offset"])


## The stock track materials are authored for snow courses; on black sand they
## tone-map to pale concrete and the racers vanish into them. Every floor run
## is re-skinned per surface with course-local material instances — never by
## mutating TrackBuilder's cached surface materials, which every other course
## in the session shares. Floor meshes are emitted as MeshInstance3D followed
## by their StaticBody3D, so the body's "surface" meta identifies the run.
func _retint_track() -> void:
	var sand := VisualLibrary.snow_material(TRACK_SAND_TINT, 0.16).duplicate() as ShaderMaterial
	sand.set_shader_parameter("sastrugi_strength", 0.22)
	sand.set_shader_parameter("normal_strength", 0.35)
	sand.set_shader_parameter("detail_strength", 0.5)
	# Snow shading assumes blue sky bounce in shadow and warm subsurface in the
	# light; black sand does the opposite, so both tints are re-aimed warm-dark
	# or the deck reads as bruised lilac under the dusk key.
	sand.set_shader_parameter("shadow_tint", Color(0.14, 0.12, 0.14))
	sand.set_shader_parameter("cavity_tint", Color(0.16, 0.13, 0.13))
	sand.set_shader_parameter("sss_tint", Color(0.9, 0.5, 0.28))
	sand.set_shader_parameter("sss_strength", 0.25)
	sand.set_shader_parameter("shadow_cool", 0.1)
	var ash := VisualLibrary.snow_material(TRACK_ASH_TINT, 0.1).duplicate() as ShaderMaterial
	ash.set_shader_parameter("sastrugi_strength", 0.55)
	ash.set_shader_parameter("normal_strength", 0.6)
	ash.set_shader_parameter("detail_strength", 0.75)
	ash.set_shader_parameter("shadow_tint", Color(0.22, 0.19, 0.18))
	ash.set_shader_parameter("sss_tint", Color(0.9, 0.55, 0.3))
	ash.set_shader_parameter("shadow_cool", 0.12)
	var glaze := VisualLibrary.ice_material(TRACK_GLAZE_TINT, 0.55).duplicate() as ShaderMaterial
	glaze.set_shader_parameter("roughness_base", 0.06)
	glaze.set_shader_parameter("crack_strength", 0.95)
	glaze.set_shader_parameter("deep_tint", Color(0.02, 0.03, 0.05))
	# The ice shader frosts the ends of every run white for accessibility. On
	# cooled lava that reads as snow drifted onto the ramp, so the border is
	# narrowed and warmed to a dull ash rind rather than removed — the run
	# boundary still reads by brightness.
	glaze.set_shader_parameter("frost_tint", Color(0.55, 0.5, 0.47))
	glaze.set_shader_parameter("frost_strength", 0.45)
	glaze.set_shader_parameter("frost_edge_width", 0.035)
	var crust := VisualLibrary.ice_material(TRACK_CRUST_TINT, 0.25).duplicate() as ShaderMaterial
	crust.set_shader_parameter("roughness_base", 0.42)
	crust.set_shader_parameter("deep_tint", Color(0.2, 0.17, 0.15))
	crust.set_shader_parameter("frost_tint", Color(0.62, 0.58, 0.54))
	# Skirt: the ribbon's visible thickness. Its baked vertex gradient is a
	# glacial lip-to-deep-blue, multiplied by this albedo — a warm dark tint
	# turns it into the ash bench the deck is cut into. Own instance, because
	# the cached skirt material is shared by every ribbon in the session.
	var skirt := VisualLibrary.rock_material(Color(0.42, 0.28, 0.24), 0.75).duplicate() as StandardMaterial3D
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
				# A collider with no surface tag is an edge wall. The glacial
				# barrier shader is the wrong material on black sand — it reads
				# as a lit ice fence — so it is re-tinted per instance (the
				# TrackBuilder original is one cached instance shared by every
				# course, and must never be mutated).
				if wall == null:
					var source := mesh.material_override as ShaderMaterial
					if source != null:
						wall = source.duplicate() as ShaderMaterial
						wall.set_shader_parameter("tint", Color(0.12, 0.1, 0.1))
						wall.set_shader_parameter("strata_tint", Color(0.42, 0.28, 0.2))
						# Crest lip kept bright and warm: the boundary still has
						# to read by brightness, which is the accessibility
						# contract the ice wall shader was written for.
						wall.set_shader_parameter("lip_tint", Color(0.92, 0.58, 0.34))
						wall.set_shader_parameter("base_alpha", 0.92)
						wall.set_shader_parameter("rim_strength", 0.35)
						wall.set_shader_parameter("lip_glow", 0.1)
				if wall != null:
					mesh.material_override = wall
				continue
			match int(body.get_meta("surface")):
				SNOW:
					mesh.material_override = sand
				DEEP:
					mesh.material_override = ash
				ICE:
					mesh.material_override = glaze
				RICE:
					mesh.material_override = crust


## --- Decoration -------------------------------------------------------------
## Pure visual dressing. Skipped headless (nothing gameplay reads these nodes
## except the ploughable ash drifts, which the race sim also does without);
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

	_decorate_basalt(density)
	_decorate_scoria(density)
	_decorate_ash_drifts(density)
	_decorate_lanterns()
	_decorate_ember_fissures(density)
	_decorate_fumaroles(density)
	_decorate_arch()
	_decorate_sea_stacks(density)
	_decorate_surf()
	_decorate_cone()
	_decorate_spectators(density)
	_decorate_haze(density)

	# Baked contact shadows, flushed last so every pass above has had its chance
	# to register one. The dusk sun rakes this coast almost horizontally, so the
	# real cast shadows all run far off to one side and leave nothing under the
	# props themselves; without an occlusion cue at the foot a correctly bedded
	# column still reads as standing on top of the ash rather than in it.
	_add_multimesh(VisualLibrary.contact_patch_mesh(), _contact_patches,
		_contact_material(), "ContactShadows", false, 260.0)


## --- Contact shadows ---------------------------------------------------------
## gl_compatibility has no SSAO, so the occlusion that plants a prop on the
## ground has to be geometry: one soft alpha quad per prop, all of them through
## a single MultiMesh (one draw call for the whole coastline).

var _contact_patches: Array[Transform3D] = []


## Volcanic dusk: near-black ash and basalt under a low ember sun, with the sky
## the only fill. A shadow here is a WARM near-black — glacier's blue-grey sky
## bounce belongs to snow under a noon sun and on this ground would read as a
## pale slick rather than shade. Kept weak: the ground is already dark, so the
## patch only has to deepen it a little.
func _contact_material() -> StandardMaterial3D:
	var mat := VisualLibrary.contact_shadow_material().duplicate() as StandardMaterial3D
	mat.albedo_color = Color(0.07, 0.045, 0.05, 0.38)
	return mat


## BUILD TIME ONLY. Registers a contact shadow under a prop seated at `pos`.
## `radius` is the prop's ground footprint; the patch is drawn a shade wider,
## because a real ambient-occlusion contact reaches slightly past the silhouette.
##
## `surface_y` is the height of the ground the prop was SEATED on, and it has to
## be passed in rather than probed here for two reasons. Dressing is sunk below
## grade by ground_embed, so a patch at the prop's own Y is buried. And a fresh
## downward probe under a prop is worthless anyway: trackside dressing stands a
## metre or two past the deck's collision edge, so the cast falls straight
## through to the sea plane far below. seat_dressing already resolved the right
## surface by walking back toward the centreline — this reuses that answer
## instead of asking a worse question.
##
## Props that found no floor at all were seated on the sea plane; they get no
## patch, because a disc lying on open water is worse than no contact cue.
func _add_contact_patch(pos: Vector3, radius: float, surface_y: float) -> void:
	if is_equal_approx(surface_y, ground_plane_y()):
		return
	_contact_patches.append(Transform3D(
		Basis.from_scale(Vector3(radius * 2.4, 1.0, radius * 2.4)),
		Vector3(pos.x, surface_y + 0.04, pos.z)))


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


## Columnar basalt: the signature form of this coast. Cooling lava fractures
## into packed hexagonal columns, so palisades of them line the route — short
## broken ranks along the shore, tall organ-pipe walls flanking the chute and
## the lava terrace. Every column is one instance of a single seeded hexagonal
## prism mesh (vertex colors carry the facet shading and the ember-stained
## base), so a whole coastline of them costs two draw calls.
func _decorate_basalt(density: float) -> void:
	var short_ranks: Array[Transform3D] = []
	var tall_ranks: Array[Transform3D] = []
	# Rank runs: [start offset, end offset, side, base height, spacing].
	var terrace := _offset_near(Vector3(0, 26, -25))
	var chute := _offset_near(Vector3(-14, 20.0, -1160))
	var runs: Array = [
		[6.0, terrace + 40.0, -1.0, 6.5, 5.0],
		[6.0, terrace + 30.0, 1.0, 5.5, 5.5],
		[_offset_near(Vector3(26, 14.5, -225)), _offset_near(Vector3(58, 12.0, -360)), 1.0, 3.2, 6.5],
		[_offset_near(Vector3(0, 9.0, -660)), _offset_near(Vector3(-8, 7.6, -790)), -1.0, 4.0, 7.0],
		[_offset_near(Vector3(6, 9.5, -915)), _offset_near(Vector3(24, 17.0, -1010)), 1.0, 5.0, 6.0],
		[chute - 10.0, chute + 130.0, -1.0, 9.0, 5.5],
		[chute + 20.0, chute + 150.0, 1.0, 7.5, 6.0],
	]
	for run: Array in runs:
		var offset := float(run[0])
		var side := float(run[2])
		var base_height := float(run[3])
		var step := float(run[4]) / maxf(density, 0.5)
		while offset < float(run[1]):
			var xform := main_guide.transform_at(offset)
			# Columns stand in ranks two or three deep, marching outward from
			# the deck edge: a single file of prisms reads as a fence.
			var ranks := rng.randi_range(2, 3)
			for k: int in ranks:
				var lateral := (track_edge_lateral(main_guide, offset, side, 9.0)
					+ 0.9 + float(k) * rng.randf_range(1.1, 1.8)) * side
				var height := base_height * rng.randf_range(0.5, 1.35) * (1.0 - float(k) * 0.12)
				var radius := rng.randf_range(0.55, 1.05)
				var column_basis := Basis(Vector3.UP, rng.randf() * TAU) \
					* Basis(Vector3(cos(float(k)), 0.0, sin(float(k))), rng.randf_range(-0.06, 0.06)) \
					* Basis.from_scale(Vector3(radius, height, radius))
				var seat := seat_dressing(xform, lateral, height, 5.0, 0.12)
				if height > 6.0:
					tall_ranks.append(Transform3D(column_basis, seat))
				else:
					short_ranks.append(Transform3D(column_basis, seat))
				# A hexagonal prism has the hardest silhouette on the course and
				# the smallest footprint to sell it with, so the foot shadow is
				# what stops a rank reading as fence posts pushed into a photo.
				_add_contact_patch(seat, radius * 0.9, seat.y + ground_embed(height, 0.12))
			offset += step
	var basalt_mat := VisualLibrary.rock_material(Color(1.0, 1.0, 1.0), 0.85)
	_add_multimesh(_basalt_mesh(3311), short_ranks, basalt_mat, "BasaltColumns")
	_add_multimesh(_basalt_mesh(3312), tall_ranks, basalt_mat, "BasaltPipes", true, 420.0)


## Unit columnar-basalt prism: a six-sided column, x/z within +/-0.5, y 0..1,
## with a fractured stepped crown, per-facet tonal variation and an ember-warm
## stain at the foot where the rock is still stained by the flow it froze in.
## Faces carry the shading as vertex colors so one matte material serves every
## column on the coast.
func _basalt_mesh(seed_value: int) -> ArrayMesh:
	var mrng := RandomNumberGenerator.new()
	mrng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 6
	var dark := Color(0.055, 0.05, 0.055)
	var lit := Color(0.17, 0.155, 0.15)
	var stain := Color(0.19, 0.08, 0.045)
	var ring: Array[Vector3] = []
	var facet: Array[Color] = []
	for i: int in sides:
		var angle := TAU * float(i) / float(sides) + mrng.randf_range(-0.08, 0.08)
		var radius := 0.5 * mrng.randf_range(0.82, 1.1)
		ring.append(Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
		facet.append(dark.lerp(lit, mrng.randf_range(0.1, 1.0)))
	# Fractured crown: each column snaps off at its own height, and the top
	# face tilts, so a rank of them never presents one flat sawn line.
	var crown: Array[float] = []
	for i: int in sides:
		crown.append(1.0 - mrng.randf_range(0.0, 0.09))
	for i: int in sides:
		var j := (i + 1) % sides
		var a := ring[i]
		var b := ring[j]
		var top_a := Vector3(a.x, crown[i], a.z)
		var top_b := Vector3(b.x, crown[j], b.z)
		var col: Color = facet[i]
		# Ember stain at the foot, cooling to bare rock by a quarter height.
		_cquad(st, a, b, Vector3(b.x, 0.24, b.z), Vector3(a.x, 0.24, a.z), col.lerp(stain, 0.55))
		_cquad(st, Vector3(a.x, 0.24, a.z), Vector3(b.x, 0.24, b.z), top_b, top_a, col)
	# Crown fan from the centre, brightest face on the column (it catches sky).
	var cap := Color(0.2, 0.19, 0.19)
	var centre := Vector3(mrng.randf_range(-0.05, 0.05), 1.0, mrng.randf_range(-0.05, 0.05))
	for i: int in sides:
		var j := (i + 1) % sides
		_ctri(st, Vector3(ring[i].x, crown[i], ring[i].z),
			Vector3(ring[j].x, crown[j], ring[j].z), centre, cap)
	st.generate_normals()
	return st.commit()


## Volcanic bombs and scoria rubble scattered along the shoulders: lumpy dark
## spheres, half of them wearing a pale sinter crust where spray and steam have
## mineralised them. Two multimeshes, both bedded on the shoulder rather than
## floating at a constant lateral.
func _decorate_scoria(density: float) -> void:
	var bombs: Array[Transform3D] = []
	var crusted: Array[Transform3D] = []
	var count := int(46.0 * density)
	for _i: int in count:
		var offset := rng.randf_range(40.0, main_guide.length - 60.0)
		var xform := main_guide.transform_at(offset)
		var side := 1.0 if rng.randf() > 0.5 else -1.0
		var lateral := (track_edge_lateral(main_guide, offset, side, 9.0)
			+ rng.randf_range(0.7, 5.5)) * side
		var s := rng.randf_range(0.6, 2.2)
		var squash := Vector3(rng.randf_range(0.85, 1.4), rng.randf_range(0.55, 1.0),
			rng.randf_range(0.85, 1.4)) * s
		var bomb_basis := Basis.from_euler(Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU,
			rng.randf_range(-0.3, 0.3))).scaled(squash)
		# Sphere meshes are centre-origin: half the squashed height plus a bite
		# of bed depth puts the boulder's waist at the surface.
		var seat := seat_dressing(xform, lateral, squash.y, 4.5, 0.12)
		var pos := seat + Vector3.UP * (squash.y * 0.42)
		if rng.randf() > 0.55:
			crusted.append(Transform3D(bomb_basis, pos))
		else:
			bombs.append(Transform3D(bomb_basis, pos))
		# Measured off the bed, not the raised sphere centre: `pos` is half a
		# bomb's height above the ground it is bedded in.
		_add_contact_patch(seat, maxf(squash.x, squash.z) * 0.8,
			seat.y + ground_embed(squash.y, 0.12))
	var bomb_mesh := SphereMesh.new()
	bomb_mesh.radius = 0.8
	bomb_mesh.height = 1.3
	bomb_mesh.radial_segments = 7
	bomb_mesh.rings = 4
	_add_multimesh(bomb_mesh, bombs, TrackBuilder.prop_material(Color(0.09, 0.085, 0.09), 1.0), "VolcanicBombs")
	_add_multimesh(bomb_mesh, crusted, TrackBuilder.prop_material(Color(0.42, 0.39, 0.36), 0.95), "SinterBombs")


## Wind-blown ash banks hugging the track edges, elongated along the onshore
## breeze the way real drifts streamline. Every bank the racers can reach is
## also registered as a ploughing volume, so running wide into one costs real
## speed — the drawn thing and the felt thing come from one transform.
func _decorate_ash_drifts(density: float) -> void:
	var transforms: Array[Transform3D] = []
	var breeze := deg_to_rad(BREEZE_YAW_DEG)
	var step := 15.0 / density
	var offset := 26.0
	var side := 1.0
	while offset < main_guide.length - 26.0:
		var xform := main_guide.transform_at(offset)
		var lateral := (track_edge_lateral(main_guide, offset, side, 9.0)
			+ rng.randf_range(0.5, 3.4)) * side
		var r := rng.randf_range(1.5, 3.4)
		var bank_basis := Basis(Vector3.UP, breeze + rng.randf_range(-0.22, 0.22)) \
			* Basis.from_scale(Vector3(r * rng.randf_range(1.6, 2.4), r * rng.randf_range(0.45, 0.75),
				r * rng.randf_range(0.7, 0.95)))
		var bank_xform := Transform3D(bank_basis,
			seat_dressing(xform, lateral, bank_basis.get_scale().y, 5.0, 0.14))
		transforms.append(bank_xform)
		add_snow_drift(bank_xform)
		if rng.randf() > 0.62:
			var far_r := rng.randf_range(2.4, 4.6)
			var far_basis := Basis(Vector3.UP, breeze + rng.randf_range(-0.3, 0.3)) \
				* Basis.from_scale(Vector3(far_r * 1.9, far_r * 0.5, far_r * 0.85))
			transforms.append(Transform3D(far_basis,
				seat_dressing(xform, lateral + rng.randf_range(1.6, 5.0) * side,
					far_basis.get_scale().y, 6.5, 0.15)))
		side = -side
		offset += step
	# Ash is dark and matte: the shared drift mesh with a near-black tint reads
	# as blown cinder rather than the snow the same mesh makes elsewhere.
	_add_multimesh(VisualLibrary.snow_drift_mesh(), transforms,
		VisualLibrary.rock_material(Color(0.2, 0.18, 0.18), 1.0), "AshDrifts")


## Shore lanterns: the route markers of a course with no snow to read against.
## Weathered posts with a warm lamp head every ~72m, alternating sides, plus
## dense clusters bracketing the grid and the finish so both bookends read as a
## staged event. Lamp heads are emissive but kept under the bloom threshold —
## warm points in the dusk, not a lightshow.
func _decorate_lanterns() -> void:
	var post_transforms: Array[Transform3D] = []
	var lamp_transforms: Array[Transform3D] = []
	var offset := 55.0
	var side := 1.0
	while offset < main_guide.length - 55.0:
		_add_lantern(post_transforms, lamp_transforms, offset, side)
		side = -side
		offset += 72.0
	for i: int in 5:
		for cluster_side: float in [-1.0, 1.0]:
			_add_lantern(post_transforms, lamp_transforms, 10.0 + float(i) * 12.0, cluster_side)
			_add_lantern(post_transforms, lamp_transforms, finish_offset - 8.0 - float(i) * 13.0, cluster_side)
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.07
	post_mesh.bottom_radius = 0.1
	post_mesh.height = 3.4
	post_mesh.radial_segments = 6
	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.26
	lamp_mesh.height = 0.52
	lamp_mesh.radial_segments = 8
	lamp_mesh.rings = 5
	_add_multimesh(post_mesh, post_transforms,
		TrackBuilder.prop_material(Color(0.16, 0.14, 0.13), 0.95), "LanternPosts")
	_add_multimesh(lamp_mesh, lamp_transforms,
		VisualLibrary.emissive_material(Color(1.0, 0.72, 0.36), Color(1.0, 0.6, 0.24), 1.1), "LanternLamps", false)


func _add_lantern(posts: Array[Transform3D], lamps: Array[Transform3D], offset: float, side: float) -> void:
	if offset <= 2.0 or offset >= main_guide.length - 2.0:
		return
	var xform := main_guide.transform_at(offset)
	var lateral := (track_edge_lateral(main_guide, offset, side, 9.0) + rng.randf_range(0.8, 2.2)) * side
	var base := seat_dressing(xform, lateral, 3.4)
	var yaw := Basis(Vector3.UP, rng.randf() * TAU)
	posts.append(Transform3D(yaw, base + Vector3.UP * 1.7))
	lamps.append(Transform3D(yaw, base + Vector3.UP * 3.5))
	# Small pool at the foot of the post. A lantern is the one prop players
	# actually look at on this course, and a 10cm pole meeting the ash with no
	# darkening under it is the most obvious "stuck in, not standing on" tell.
	_add_contact_patch(base, 0.34, base.y + ground_embed(3.4))


## Ember fissures: cracks in the cooled flow with the glow of the rock beneath
## still showing through. They lie flush with the ground just off both edges of
## the fumarole flat and the obsidian chute — the visual promise the steam
## vents then keep. Emission energy is low on purpose: a hot hairline, not a
## river of lava.
func _decorate_ember_fissures(density: float) -> void:
	var transforms: Array[Transform3D] = []
	var regions: Array[Vector2] = [
		Vector2(_offset_near(Vector3(0, 9.0, -660)), _offset_near(Vector3(-4, 7.0, -860))),
		Vector2(_offset_near(Vector3(-14, 20.0, -1160)), _offset_near(Vector3(-18, 4.5, -1330))),
		Vector2(_offset_near(Vector3(26, 14.5, -225)), _offset_near(Vector3(58, 12.0, -360))),
	]
	for region: Vector2 in regions:
		var count := maxi(int(9.0 * density), 4)
		for _i: int in count:
			var offset := rng.randf_range(region.x, region.y)
			var xform := main_guide.transform_at(offset)
			var side := 1.0 if rng.randf() > 0.5 else -1.0
			var lateral := (track_edge_lateral(main_guide, offset, side, 9.0)
				+ rng.randf_range(0.4, 4.0)) * side
			var seat := seat_dressing(xform, lateral, 0.2, 5.0, 0.0) + Vector3.UP * 0.04
			var fissure_basis := Basis(Vector3.UP, main_guide.yaw_at(offset) + rng.randf_range(-1.2, 1.2)) \
				* Basis.from_scale(Vector3(rng.randf_range(1.4, 2.6), 1.0, rng.randf_range(6.0, 14.0)))
			transforms.append(Transform3D(fissure_basis, seat))
	var fissure_mat := StandardMaterial3D.new()
	fissure_mat.vertex_color_use_as_albedo = true
	fissure_mat.albedo_color = Color(1.0, 1.0, 1.0)
	fissure_mat.roughness = 0.7
	fissure_mat.emission_enabled = true
	fissure_mat.emission = EMBER
	fissure_mat.emission_energy_multiplier = 0.55
	_add_multimesh(_fissure_mesh(5150), transforms, fissure_mat, "EmberFissures", false, 260.0)


## Unit jagged fissure lying in the XZ plane: runs along Z (-0.5..0.5) with a
## zigzag midline and tapered ends. Vertex colors run from a near-black crust
## at the lips to a hot core along the centre, so the emission tint above lands
## where the crack is actually open.
func _fissure_mesh(seed_value: int) -> ArrayMesh:
	var mrng := RandomNumberGenerator.new()
	mrng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 8
	var crust := Color(0.04, 0.03, 0.03)
	var core := Color(1.0, 0.55, 0.16)
	var mid_x: Array[float] = []
	var half_w: Array[float] = []
	for i: int in segs + 1:
		var t := float(i) / float(segs)
		mid_x.append(mrng.randf_range(-0.08, 0.08) if i > 0 and i < segs else 0.0)
		half_w.append(0.006 + sin(t * PI) * mrng.randf_range(0.03, 0.055))
	for i: int in segs:
		var z0 := -0.5 + float(i) / float(segs)
		var z1 := -0.5 + float(i + 1) / float(segs)
		var heat := mrng.randf_range(0.35, 1.0)
		# Two ribbons per segment: cool crust lips flanking a hot centre line.
		var l0 := Vector3(mid_x[i] - half_w[i], 0.0, z0)
		var l1 := Vector3(mid_x[i + 1] - half_w[i + 1], 0.0, z1)
		var c0 := Vector3(mid_x[i], 0.0, z0)
		var c1 := Vector3(mid_x[i + 1], 0.0, z1)
		var r0 := Vector3(mid_x[i] + half_w[i], 0.0, z0)
		var r1 := Vector3(mid_x[i + 1] + half_w[i + 1], 0.0, z1)
		_cquad(st, l1, c1, c0, l0, crust.lerp(core, heat * 0.75))
		_cquad(st, c1, r1, r0, c0, crust.lerp(core, heat))
	st.generate_normals()
	return st.commit()


## Fumaroles: the steam this coast is named for. Each vent hazard gets a stack
## of soft backlit plume billboards rising off it, and a dozen more sit off the
## racing line on the flat and around the lagoon so the whole basin breathes.
## Plumes are unshaded alpha quads on looping scale/position tweens (no
## per-frame script cost); reduced motion pins them still.
func _decorate_fumaroles(density: float) -> void:
	var plume_mat := StandardMaterial3D.new()
	plume_mat.albedo_color = Color(0.86, 0.79, 0.74, 0.17)
	plume_mat.albedo_texture = VisualLibrary.soft_radial_texture(64, 0.85)
	plume_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plume_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plume_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	plume_mat.billboard_keep_scale = true
	plume_mat.disable_receive_shadows = true
	var flat_start := _offset_near(Vector3(0, 9.0, -660))
	# On the vents themselves, then scattered across the flat and the lagoon
	# shoulders where no racer will ever drive.
	var anchors: Array[Vector3] = []
	for i: int in 6:
		anchors.append(main_guide.point_at(flat_start + 24.0 + float(i) * 28.0,
			[-4.5, 3.5, -1.0, 4.5, -3.5, 1.5][i], 0.4))
	var scatter := maxi(int(9.0 * density), 4)
	for _i: int in scatter:
		var offset := rng.randf_range(_offset_near(Vector3(14, 10.0, -540)),
			_offset_near(Vector3(6, 9.5, -915)))
		var xform := main_guide.transform_at(offset)
		var side := 1.0 if rng.randf() > 0.5 else -1.0
		var lateral := (track_edge_lateral(main_guide, offset, side, 10.0)
			+ rng.randf_range(2.5, 16.0)) * side
		anchors.append(seat_dressing(xform, lateral, 0.5, 6.0, 0.0) + Vector3.UP * 0.3)
	for anchor: Vector3 in anchors:
		var puffs := rng.randi_range(3, 5)
		for k: int in puffs:
			var t := float(k) / float(puffs)
			var size := lerpf(1.8, 5.6, t) * rng.randf_range(0.85, 1.15)
			var plume := MeshInstance3D.new()
			var quad := QuadMesh.new()
			# Taller than wide: a rising column, not a ball of cotton.
			quad.size = Vector2(size, size * rng.randf_range(1.2, 1.7))
			plume.mesh = quad
			plume.material_override = plume_mat
			plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var base := anchor + Vector3.UP * (0.9 + t * 6.5) \
				+ Vector3(rng.randf_range(-0.9, 0.9), 0.0, rng.randf_range(-0.9, 0.9))
			plume.position = base
			VisualLibrary.apply_dressing_range(plume, 320.0)
			add_child(plume)
			if UITheme.reduced_motion():
				continue
			# Rise-and-thin: the puff drifts downwind and swells as it climbs,
			# then the loop restarts it low and small.
			var drift := Vector3(sin(deg_to_rad(BREEZE_YAW_DEG)), 0.0, cos(deg_to_rad(BREEZE_YAW_DEG))) \
				* rng.randf_range(2.0, 6.0)
			var dur := rng.randf_range(4.5, 8.0)
			var tw := plume.create_tween()
			tw.set_loops()
			tw.tween_property(plume, "position", base + Vector3.UP * 2.6 + drift, dur) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw.tween_property(plume, "position", base, dur * 0.5) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


## Obsidian sea arch spanning the mouth of the final chute: a wave-cut span of
## black glass the racers drop through on the way back to the shore. Built from
## the same seeded ring sweep the basalt columns imply, with the crown high
## enough to clear any launch.
func _decorate_arch() -> void:
	var offset := _offset_near(Vector3(-14, 20.0, -1160)) + 8.0
	var xform := main_guide.transform_at(offset)
	var arch := MeshInstance3D.new()
	arch.name = "ObsidianArch"
	arch.mesh = _arch_mesh(8080)
	var arch_mat := VisualLibrary.rock_material(Color(1.0, 1.0, 1.0), 0.35, 0.15)
	arch.material_override = arch_mat
	# Feet buried well below grade: they land ~13m out, past the 9m-half deck,
	# so a shallow set would leave two stumps hanging over the drop.
	arch.transform = Transform3D(xform.basis, xform.origin + Vector3.DOWN * 3.4)
	add_child(arch)


## Wave-cut arch of columnar black glass: an elliptical sweep with an
## irregular 7-gon cross-section, thick flared feet, per-face banding (ember
## stained near the feet, glassy at the crown) and a wet sheen at the base.
## Faces are emitted double-sided so the span reads from every camera angle.
## Local X spans the track.
func _arch_mesh(seed_value: int) -> ArrayMesh:
	var mrng := RandomNumberGenerator.new()
	mrng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 16
	var sides := 7
	var half_span := 13.5
	var rise := 12.5
	var foot_col := Color(0.15, 0.07, 0.05)
	var glass := Color(0.09, 0.09, 0.11)
	var sheen := Color(0.32, 0.3, 0.33)
	var rings: Array[PackedVector3Array] = []
	var ring_dirs: Array[Vector3] = []
	for s: int in segs + 1:
		var theta := lerpf(-0.1 * PI, 1.1 * PI, float(s) / float(segs))
		var centre := Vector3(cos(theta) * half_span, sin(theta) * rise, 0.0)
		var arc := clampf(sin(theta), 0.0, 1.0)
		var thickness := lerpf(3.4, 1.7, arc) * mrng.randf_range(0.9, 1.1)
		var depth := lerpf(2.8, 1.5, arc) * mrng.randf_range(0.9, 1.1)
		var out_dir := Vector3(cos(theta), sin(theta), 0.0)
		var ring: PackedVector3Array = []
		for j: int in sides:
			var phi := TAU * float(j) / float(sides)
			var wobble := mrng.randf_range(0.86, 1.14)
			ring.append(centre + out_dir * (cos(phi) * thickness * wobble)
				+ Vector3(0.0, 0.0, sin(phi) * depth * wobble))
		rings.append(ring)
		ring_dirs.append(out_dir)
	for s: int in segs:
		var t_mid := clampf(sin(lerpf(-0.1 * PI, 1.1 * PI, (float(s) + 0.5) / float(segs))), 0.0, 1.0)
		for j: int in sides:
			var k := (j + 1) % sides
			var phi_mid := TAU * (float(j) + 0.5) / float(sides)
			var shade := mrng.randf_range(0.85, 1.1)
			var col := foot_col.lerp(glass, t_mid)
			col = Color(col.r * shade, col.g * shade, col.b * shade)
			# Up-facing crown faces catch the ember sky and read as wet glass.
			var up_amount := clampf(ring_dirs[s].y * cos(phi_mid), 0.0, 1.0)
			col = col.lerp(sheen, up_amount * t_mid * 0.7)
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


## Sea stacks: eroded basalt fangs standing out in the surf, well off the
## racing line, seated on the sea plane. They give the water something to break
## against and hold the middle distance on the ocean side, which would
## otherwise be a bare gradient all the way to the horizon.
func _decorate_sea_stacks(density: float) -> void:
	var transforms: Array[Transform3D] = []
	var count := maxi(int(16.0 * density), 7)
	for _i: int in count:
		var offset := rng.randf_range(60.0, main_guide.length - 60.0)
		var xform := main_guide.transform_at(offset)
		# Sea side only: the shore arc curves right around the bay, so the sea
		# is consistently to the right of travel out to the horizon.
		var lateral := rng.randf_range(70.0, 260.0)
		var pos := xform.origin + xform.basis.x * lateral
		var height := rng.randf_range(7.0, 26.0)
		var radius := height * rng.randf_range(0.16, 0.34)
		var stack_basis := Basis(Vector3.UP, rng.randf() * TAU) \
			* Basis(Vector3.FORWARD, rng.randf_range(-0.08, 0.08)) \
			* Basis.from_scale(Vector3(radius, height, radius))
		transforms.append(Transform3D(stack_basis, Vector3(pos.x, SEA_Y - 0.6, pos.z)))
	_add_multimesh(_basalt_mesh(3313), transforms,
		VisualLibrary.rock_material(Color(0.85, 0.85, 0.88), 0.8), "SeaStacks", false, 700.0)


## Surf: long soft foam bands lying on the water where it meets the shore
## bench, plus a wide glitter band aimed down the sun bearing. Additive and
## thin — this is the one place on a black course where brightness belongs.
func _decorate_surf() -> void:
	var foam_mat := StandardMaterial3D.new()
	foam_mat.albedo_color = Color(0.94, 0.9, 0.88, 0.36)
	foam_mat.albedo_texture = VisualLibrary.soft_radial_texture(64, 0.75)
	foam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	foam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	foam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var offset := 90.0
	while offset < main_guide.length - 60.0:
		var xform := main_guide.transform_at(offset)
		var band := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(rng.randf_range(26.0, 52.0), rng.randf_range(110.0, 190.0))
		band.mesh = plane
		band.material_override = foam_mat
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pos := xform.origin + xform.basis.x * rng.randf_range(26.0, 44.0)
		band.position = Vector3(pos.x, SEA_Y + 0.12, pos.z)
		band.rotation.y = main_guide.yaw_at(offset) + rng.randf_range(-0.2, 0.2)
		VisualLibrary.apply_dressing_range(band, 420.0)
		add_child(band)
		offset += rng.randf_range(95.0, 150.0)
	# Sun glitter corridor on the open water, aimed along the dusk sun bearing.
	var sun_dir := Vector3(sin(deg_to_rad(SUN_YAW_DEG)), 0.0, cos(deg_to_rad(SUN_YAW_DEG)))
	var glint_mat := StandardMaterial3D.new()
	glint_mat.albedo_color = Color(1.0, 0.55, 0.24, 0.5)
	glint_mat.albedo_texture = VisualLibrary.soft_radial_texture(64, 0.7)
	glint_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glint_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glint_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	for anchor: Vector3 in [Vector3(60.0, 0.0, -360.0), Vector3(-40.0, 0.0, -1420.0)]:
		var band := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(rng.randf_range(90.0, 130.0), rng.randf_range(430.0, 560.0))
		band.mesh = plane
		band.material_override = glint_mat
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pos := anchor + sun_dir * 330.0
		band.position = Vector3(pos.x, SEA_Y + 0.16, pos.z)
		band.rotation.y = atan2(sun_dir.x, sun_dir.z)
		add_child(band)


## The cinder cone itself: the hero backdrop this course is named after, a
## broad ash cone with a blown-out crater rim, standing far inland behind the
## ridge traverse with a lazy smoke column leaning off downwind. One mesh, one
## material, plus a handful of unshaded smoke quads.
func _decorate_cone() -> void:
	var anchor := main_guide.position_at(main_guide.length * 0.62)
	var centre := Vector3(anchor.x + 620.0, SEA_Y, anchor.z - 540.0)
	var cone := MeshInstance3D.new()
	cone.name = "CinderCone"
	cone.mesh = _cone_mesh(9191)
	cone.material_override = VisualLibrary.rock_material(Color(1.0, 1.0, 1.0), 1.0)
	cone.scale = Vector3(430.0, 280.0, 430.0)
	cone.position = centre
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cone)
	# Smoke column: big soft quads stacked above the crater, leaning downwind
	# and fading as they climb.
	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.albedo_color = Color(0.3, 0.25, 0.26, 0.2)
	smoke_mat.albedo_texture = VisualLibrary.soft_radial_texture(64, 0.8)
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smoke_mat.billboard_keep_scale = true
	var lean := Vector3(sin(deg_to_rad(BREEZE_YAW_DEG)), 0.0, cos(deg_to_rad(BREEZE_YAW_DEG)))
	for k: int in 7:
		var t := float(k) / 6.0
		var puff := MeshInstance3D.new()
		var quad := QuadMesh.new()
		var size := lerpf(120.0, 260.0, t)
		quad.size = Vector2(size, size * 0.85)
		puff.mesh = quad
		puff.material_override = smoke_mat
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		puff.position = centre + Vector3.UP * (270.0 + t * 300.0) + lean * (t * 320.0) \
			+ Vector3(rng.randf_range(-40.0, 40.0), 0.0, rng.randf_range(-40.0, 40.0))
		add_child(puff)


## Unit ash cone with a crater: x/z within +/-0.5, apex rim at y = 1. The rim
## is notched (one flank blown out), the outer flanks carry ash-gully streaks,
## and the crater interior darkens to a warm ember floor.
func _cone_mesh(seed_value: int) -> ArrayMesh:
	var mrng := RandomNumberGenerator.new()
	mrng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 20
	var rim_radius := 0.19
	var flank := Color(0.11, 0.1, 0.11)
	var gully := Color(0.05, 0.045, 0.05)
	var throat := Color(0.22, 0.09, 0.05)
	var base_ring: Array[Vector3] = []
	var rim_ring: Array[Vector3] = []
	var floor_ring: Array[Vector3] = []
	var streaks: Array[float] = []
	for i: int in sides:
		var angle := TAU * float(i) / float(sides)
		var wobble := 1.0 + 0.09 * sin(angle * 3.0 + mrng.randf()) + mrng.randf_range(-0.05, 0.05)
		# One flank of the rim is blown out and sits far lower than the rest.
		var breach := smoothstep(0.6, 0.0, absf(wrapf(angle - 2.1, -PI, PI)))
		var rim_y := (1.0 - breach * 0.34) * mrng.randf_range(0.97, 1.03)
		base_ring.append(Vector3(cos(angle) * 0.5 * wobble, 0.0, sin(angle) * 0.5 * wobble))
		rim_ring.append(Vector3(cos(angle) * rim_radius * wobble, rim_y, sin(angle) * rim_radius * wobble))
		floor_ring.append(Vector3(cos(angle) * rim_radius * 0.62 * wobble, rim_y - 0.16,
			sin(angle) * rim_radius * 0.62 * wobble))
		streaks.append(mrng.randf_range(0.55, 1.25))
	for i: int in sides:
		var j := (i + 1) % sides
		var col := gully.lerp(flank, clampf(streaks[i], 0.0, 1.0))
		_cquad(st, base_ring[i], base_ring[j], rim_ring[j], rim_ring[i], col)
		# Crater interior: steep inner wall down to a warm floor.
		_cquad(st, rim_ring[j], rim_ring[i], floor_ring[i], floor_ring[j],
			col.lerp(throat, 0.6))
		_ctri(st, floor_ring[i], floor_ring[j],
			Vector3(0.0, rim_ring[i].y - 0.2, 0.0), throat)
	st.generate_normals()
	return st.commit()


## Spectator penguins: dense crowds at the grid and the finish, plus a knot on
## the headland overlooking the crust shortcut, who have all come to watch
## someone go through the mud.
func _decorate_spectators(density: float) -> void:
	var start_count := maxi(int(16.0 * density), 6)
	for i: int in start_count:
		var arc := rng.randf_range(10.0, 88.0)
		var xform := main_guide.transform_at(arc)
		var side := 1.0 if i % 2 == 0 else -1.0
		var lateral := (track_edge_lateral(main_guide, arc, side, 9.0)
			+ rng.randf_range(0.7, 5.0)) * side
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
	var overlook := _offset_near(Vector3(48, 13.0, -290))
	var overlook_count := maxi(int(7.0 * density), 3)
	for _i: int in overlook_count:
		var arc := overlook + rng.randf_range(-30.0, 30.0)
		var xform := main_guide.transform_at(arc)
		var lateral := -(track_edge_lateral(main_guide, arc, -1.0, 9.0) + rng.randf_range(0.8, 4.0))
		TrackBuilder.add_spectator(self, seat_dressing(xform, lateral, 1.6, GROUND_SHOULDER, 0.05),
			xform.origin, rng)


## Low geothermal haze pooling in the lagoon basin, the fumarole flat and along
## the surf line: soft unshaded billboards on slow drift tweens. Skipped
## entirely on low particle quality, where the fog term in the environment is
## already carrying the mood.
func _decorate_haze(density: float) -> void:
	if density <= 0.5:
		return
	var haze_mat := StandardMaterial3D.new()
	haze_mat.albedo_color = Color(0.72, 0.6, 0.55, 0.16)
	haze_mat.albedo_texture = VisualLibrary.soft_radial_texture(64, 0.8)
	haze_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	haze_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	haze_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var regions: Array[Vector2] = [
		Vector2(_offset_near(Vector3(14, 10.0, -540)), _offset_near(Vector3(0, 9.0, -660))),
		Vector2(_offset_near(Vector3(0, 9.0, -660)), _offset_near(Vector3(-4, 7.0, -860))),
		Vector2(finish_offset - 110.0, finish_offset - 5.0),
	]
	var per_region := maxi(int(5.0 * density), 2)
	for region: Vector2 in regions:
		for _i: int in per_region:
			var offset := rng.randf_range(region.x, region.y)
			var lateral := rng.randf_range(8.0, 20.0) * (1.0 if rng.randf() > 0.5 else -1.0)
			var pos := main_guide.point_at(offset, lateral, rng.randf_range(0.8, 2.6))
			var wisp := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(rng.randf_range(15.0, 27.0), rng.randf_range(4.0, 7.5))
			wisp.mesh = quad
			wisp.material_override = haze_mat
			wisp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			wisp.position = pos
			add_child(wisp)
			if UITheme.reduced_motion():
				continue
			var drift := Vector3(rng.randf_range(-7.0, 7.0), rng.randf_range(0.2, 0.8),
				rng.randf_range(-5.0, 5.0))
			var dur := rng.randf_range(7.0, 13.0)
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
